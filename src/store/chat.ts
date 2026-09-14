import { create } from 'zustand';
import { db, dayKey, uid } from '@/lib/db';
import type { Attachment, Chat, GenerationSettings, Message, Usage } from '@/lib/types';
import { ORError, completeOnce, fetchGenerationWithRetry, streamCompletion, type ChatMessageParam, type ContentPart } from '@/lib/openrouter';
import { buildRequestBody, resolveSettings } from '@/lib/params';
import { estimateAttachmentTokens, estimateTokens, parsePrice, stripMd } from '@/lib/format';
import { planInjection, renderMemoryBlock, scheduleExtraction } from '@/lib/memory';
import { clientConfig, useApp } from './app';
import { getModel, useModels } from './models';
import { useChats } from './chats';
import { useUI } from './ui';

// ---------- Streaming view state (rAF-batched; only the streaming row subscribes) ----------
interface StreamState {
  id: string | null;
  content: string;
  reasoning: string;
  startedAt: number;
  firstTokenAt: number | null;
  promptTokens: number;
  completionTokens: number;
  reasoningTokens: number;
  estCost: number;
  retryAt: number | null;
  retryReason: string | null;
}
export const useStream = create<StreamState>(() => ({ id: null, content: '', reasoning: '', startedAt: 0, firstTokenAt: null, promptTokens: 0, completionTokens: 0, reasoningTokens: 0, estCost: 0, retryAt: null, retryReason: null }));

// ---------- Active chat ----------
interface ChatState {
  chat: Chat | null;
  messages: Record<string, Message>;
  path: string[];
  persisted: boolean;
  generating: boolean;
  pinned: boolean;
  open: (id: string | null) => Promise<void>;
  newChat: (opts?: { presetId?: string | null; incognito?: boolean; modelId?: string }) => Promise<void>;
  patchChat: (patch: Partial<Chat>) => Promise<void>;
  saveDraft: (text: string) => void;
  setModel: (id: string) => Promise<void>;
  send: (text: string, attachments?: Attachment[]) => Promise<void>;
  stop: () => void;
  regenerate: (assistantId: string, modelId?: string) => Promise<void>;
  editResend: (userId: string, text: string) => Promise<void>;
  continueFrom: (assistantId: string) => Promise<void>;
  retryMessage: (assistantId: string) => Promise<void>;
  switchBranch: (messageId: string, dir: -1 | 1) => Promise<void>;
  deleteMessage: (id: string) => Promise<void>;
  branchFrom: (messageId: string) => Promise<string>;
  setPinned: (v: boolean) => void;
  applyAuthoritative: (msgId: string, usage: Usage) => Promise<void>;
}

let abortCtl: AbortController | null = null;
/** Last known scroll offset per chat, kept out of React state to avoid render churn. */
export const scrollMemory = new Map<string, number>();
let draftTimer: ReturnType<typeof setTimeout> | null = null;

function computePath(messages: Record<string, Message>, leafId: string | null | undefined): string[] {
  const out: string[] = [];
  let cur = leafId ? messages[leafId] : undefined;
  while (cur) { out.push(cur.id); cur = cur.parentId ? messages[cur.parentId] : undefined; }
  return out.reverse();
}

export function childrenOf(messages: Record<string, Message>, parentId: string | null): Message[] {
  return Object.values(messages).filter((m) => m.parentId === parentId).sort((a, b) => a.createdAt - b.createdAt);
}

function deepest(messages: Record<string, Message>, id: string): string {
  let cur = id;
  for (;;) {
    const kids = childrenOf(messages, cur);
    if (!kids.length) return cur;
    cur = kids[kids.length - 1]!.id;
  }
}

function freshChat(opts: { presetId?: string | null; incognito?: boolean; modelId?: string } = {}): Chat {
  const app = useApp.getState().settings;
  const preset = opts.presetId ? useChats.getState().presets.find((p) => p.id === opts.presetId) : undefined;
  const now = Date.now();
  return {
    id: uid(),
    title: 'New chat',
    createdAt: now,
    updatedAt: now,
    pinned: false,
    archived: false,
    modelId: opts.modelId ?? preset?.modelId ?? app.defaultModelId,
    systemPromptId: preset?.id,
    memoryEnabled: !opts.incognito && app.memory.enabled,
    tokenEstimate: 0,
    totalCostUsd: 0,
    activeLeafId: null,
    draft: '',
    titleAuto: true,
  };
}

async function ensurePersisted(): Promise<void> {
  const st = useChat.getState();
  if (!st.chat || st.persisted) return;
  await db.chats.put(st.chat);
  useChat.setState({ persisted: true });
  useApp.getState().update({ lastChatId: st.chat.id });
  await useChats.getState().reload();
  const app = useApp.getState().settings;
  if (!app.persistRequested && navigator.storage?.persist) {
    navigator.storage.persist().then((ok) => useApp.getState().update({ persistRequested: ok })).catch(() => undefined);
  }
}

async function applyCostDelta(chatId: string, delta: number): Promise<void> {
  if (!Number.isFinite(delta) || delta === 0) return;
  const day = dayKey();
  await db.transaction('rw', db.chats, db.dayCosts, async () => {
    const c = await db.chats.get(chatId);
    if (c) await db.chats.update(chatId, { totalCostUsd: Math.max(0, (c.totalCostUsd || 0) + delta) });
    const d = await db.dayCosts.get(day);
    await db.dayCosts.put({ day, costUsd: Math.max(0, (d?.costUsd ?? 0) + delta), messages: (d?.messages ?? 0) });
  });
  const st = useChat.getState();
  if (st.chat?.id === chatId) useChat.setState({ chat: { ...st.chat, totalCostUsd: Math.max(0, st.chat.totalCostUsd + delta) } });
  void useChats.getState().reload();
  window.dispatchEvent(new CustomEvent('quire:cost-changed'));
}

export function effectiveSettings(chat: Chat | null): GenerationSettings {
  const app = useApp.getState().settings;
  const preset = chat?.systemPromptId ? useChats.getState().presets.find((p) => p.id === chat.systemPromptId) : undefined;
  return resolveSettings(resolveSettings(app.globalSettings, preset?.settings), chat?.settingsOverride);
}

export function effectiveSystemPrompt(chat: Chat | null): string {
  const app = useApp.getState().settings;
  if (chat?.systemPromptInline != null && chat.systemPromptInline !== '') return chat.systemPromptInline;
  const preset = chat?.systemPromptId ? useChats.getState().presets.find((p) => p.id === chat.systemPromptId) : undefined;
  return preset?.systemPrompt ?? app.globalSystemPrompt;
}

function toParam(m: Message): ChatMessageParam {
  if (!m.attachments?.length) return { role: m.role, content: m.content };
  const parts: ContentPart[] = [];
  if (m.content) parts.push({ type: 'text', text: m.content });
  for (const a of m.attachments) {
    if (a.kind === 'image') parts.push({ type: 'image_url', image_url: { url: a.dataUrl } });
    else parts.push({ type: 'file', file: { filename: a.name, file_data: a.dataUrl } });
  }
  return { role: m.role, content: parts };
}

export function contextTokens(chat: Chat | null, messages: Record<string, Message>, path: string[]): number {
  let n = estimateTokens(effectiveSystemPrompt(chat));
  for (const id of path) { const m = messages[id]; if (!m) continue; n += estimateTokens(m.content) + (m.attachments ?? []).reduce((s, a) => s + estimateAttachmentTokens(a), 0) + 4; }
  return n;
}

/** Build the request thread up to (not including) the assistant placeholder. */
function buildThread(messages: Record<string, Message>, path: string[], uptoExclusive: string): Message[] {
  const out: Message[] = [];
  for (const id of path) {
    if (id === uptoExclusive) break;
    const m = messages[id];
    if (!m) continue;
    if (m.role === 'assistant' && m.status === 'error' && !m.content) continue;
    if (m.role === 'assistant' && !m.content) continue;
    out.push(m);
  }
  return out;
}

function errorFrom(e: unknown): { code: string; message: string; retryAfterMs?: number; status: number } {
  if (e instanceof ORError) {
    let message = e.message;
    const reasons = e.metadata?.reasons;
    if (e.status === 403 && Array.isArray(reasons) && reasons.length) message += ` (${reasons.join(', ')})`;
    if (e.status === 403 && typeof e.metadata?.flagged_input === 'string') message += `\nFlagged input: ${e.metadata.flagged_input}`;
    const provider = e.metadata?.provider_name;
    if (typeof provider === 'string') message += ` [${provider}]`;
    return { code: String(e.status || e.code), message, retryAfterMs: e.retryAfterMs, status: e.status };
  }
  if (e instanceof DOMException && e.name === 'AbortError') return { code: 'aborted', message: 'Stopped', status: 0 };
  if (e instanceof TypeError) return { code: 'network', message: navigator.onLine ? `Network error: ${e.message}` : 'You are offline. The message is kept; retry when you are back online.', status: 0 };
  return { code: 'unknown', message: e instanceof Error ? e.message : String(e), status: 0 };
}

const sleep = (ms: number, signal?: AbortSignal) => new Promise<void>((res, rej) => {
  const t = setTimeout(res, ms);
  signal?.addEventListener('abort', () => { clearTimeout(t); rej(new DOMException('Aborted', 'AbortError')); }, { once: true });
});

async function generate(opts: { assistantId: string; modelId: string; continueMode?: boolean }): Promise<void> {
  const st = useChat.getState();
  const chat = st.chat;
  if (!chat) return;
  const app = useApp.getState().settings;
  const cfg = clientConfig();
  if (!cfg.apiKey) {
    useUI.getState().toast('Add your OpenRouter key to start', { label: 'Open settings', onClick: () => useUI.getState().navigate({ name: 'settings', section: 'connection' }) }, 6000);
    await finalizeError(opts.assistantId, { code: '401', message: 'No API key set. Add one in Settings → Connection.' });
    return;
  }
  if (!navigator.onLine) {
    await finalizeError(opts.assistantId, { code: 'offline', message: 'You are offline. The message is kept; retry when you are back online.' });
    return;
  }

  const model = getModel(opts.modelId);
  const settings = effectiveSettings(chat);
  const thread = buildThread(st.messages, st.path, opts.assistantId);
  const lastUser = [...thread].reverse().find((m) => m.role === 'user');
  const sys: string[] = [];
  const sp = effectiveSystemPrompt(chat);
  if (sp.trim()) sys.push(sp.trim());
  if (chat.memoryEnabled && app.memory.enabled) {
    const plan = planInjection(useChats.getState().memory, lastUser?.content ?? '', app.memory.maxInjectedChars);
    const block = renderMemoryBlock(plan.entries);
    if (block) sys.push(block);
  }
  const msgs: ChatMessageParam[] = [];
  if (sys.length) msgs.push({ role: 'system', content: sys.join('\n\n') });
  for (const m of thread) msgs.push(toParam(m));
  const existing = st.messages[opts.assistantId];
  if (opts.continueMode && existing?.content) msgs.push({ role: 'assistant', content: existing.content });

  const body = buildRequestBody({ modelId: opts.modelId, model, settings, messages: msgs });
  const requestSnapshot = JSON.stringify({ ...body, messages: msgs.map((m) => ({ role: m.role, content: typeof m.content === 'string' ? m.content : m.content.map((p) => (p.type === 'text' ? p.text : `[${p.type}]`)).join('\n') })) }, null, 2);
  const promptTokensEst = msgs.reduce((n, m) => n + (typeof m.content === 'string' ? estimateTokens(m.content) : m.content.reduce((k, p) => k + (p.type === 'text' ? estimateTokens(p.text) : p.type === 'image_url' ? 1000 : 2000), 0)) + 4, 0);
  const pPrompt = parsePrice(model?.pricing.prompt);
  const pComp = parsePrice(model?.pricing.completion);
  const pReason = parsePrice(model?.pricing.internal_reasoning) || pComp;

  abortCtl = new AbortController();
  const signal = abortCtl.signal;
  useChat.setState({ generating: true });
  await db.messages.update(opts.assistantId, { status: 'streaming', modelId: opts.modelId, settingsSnapshot: settings, requestSnapshot });
  useChat.setState((s) => ({ messages: { ...s.messages, [opts.assistantId]: { ...s.messages[opts.assistantId]!, status: 'streaming', modelId: opts.modelId, settingsSnapshot: settings, requestSnapshot } } }));

  const base = opts.continueMode ? (existing?.content ?? '') : '';
  const baseReason = opts.continueMode ? (existing?.reasoning ?? '') : '';
  let content = base;
  let reasoning = baseReason;
  let generationId: string | undefined = existing?.generationId;
  let usage: Usage | undefined;
  let finish: string | null = null;
  let firstTokenAt: number | null = null;
  let dirty = false;
  let raf = 0;
  const startedAt = Date.now();
  useStream.setState({ id: opts.assistantId, content, reasoning, startedAt, firstTokenAt: null, promptTokens: promptTokensEst, completionTokens: 0, reasoningTokens: 0, estCost: 0, retryAt: null, retryReason: null });

  const flushView = () => {
    raf = 0;
    const ct = estimateTokens(content.slice(base.length));
    const rt = estimateTokens(reasoning.slice(baseReason.length));
    useStream.setState({ content, reasoning, firstTokenAt, completionTokens: ct, reasoningTokens: rt, estCost: promptTokensEst * pPrompt + ct * pComp + rt * pReason });
  };
  const schedule = () => { if (!raf) raf = requestAnimationFrame(flushView); };
  const persistTimer = setInterval(() => {
    if (!dirty) return;
    dirty = false;
    void db.messages.update(opts.assistantId, { content, reasoning, generationId });
  }, 500);

  const onVisibility = () => { if (document.visibilityState === 'hidden' && abortCtl) abortCtl.abort(new DOMException('Backgrounded', 'AbortError')); };
  document.addEventListener('visibilitychange', onVisibility);

  let attempt = 0;
  let finalErr: ReturnType<typeof errorFrom> | null = null;
  let aborted = false;
  try {
    for (;;) {
      try {
        if (settings.stream) {
          for await (const ev of streamCompletion(cfg, { body, signal })) {
            if (ev.id && !generationId) generationId = ev.id;
            if (ev.content) { if (!firstTokenAt) firstTokenAt = Date.now(); content += ev.content; dirty = true; schedule(); }
            if (ev.reasoning) { if (!firstTokenAt) firstTokenAt = Date.now(); reasoning += ev.reasoning; dirty = true; schedule(); }
            if (ev.finishReason !== undefined && ev.finishReason !== null) finish = ev.finishReason;
            if (ev.usage) usage = { promptTokens: ev.usage.promptTokens, completionTokens: ev.usage.completionTokens, reasoningTokens: ev.usage.reasoningTokens, costUsd: ev.usage.cost, webSearchCostUsd: ev.usage.webSearchCost };
          }
        } else {
          const r = await completeOnce(cfg, { body, signal });
          generationId = r.id || generationId;
          content += r.content; reasoning += r.reasoning; finish = r.finishReason; firstTokenAt = Date.now();
          if (r.usage) usage = { promptTokens: r.usage.promptTokens, completionTokens: r.usage.completionTokens, reasoningTokens: r.usage.reasoningTokens, costUsd: r.usage.cost };
          schedule();
        }
        break;
      } catch (e) {
        const err = errorFrom(e);
        if (err.code === 'aborted') { aborted = true; break; }
        const retriable = (err.status === 429 || err.status === 408 || err.status === 502 || err.status === 503 || err.status === 504) && !content && attempt < 3;
        if (!retriable) { finalErr = err; break; }
        attempt += 1;
        const wait = Math.max(err.retryAfterMs ?? 0, 1500 * 2 ** (attempt - 1));
        useStream.setState({ retryAt: Date.now() + wait, retryReason: err.message });
        try { await sleep(wait, signal); } catch { aborted = true; break; }
        useStream.setState({ retryAt: null, retryReason: null });
      }
    }
  } finally {
    clearInterval(persistTimer);
    document.removeEventListener('visibilitychange', onVisibility);
    if (raf) cancelAnimationFrame(raf);
    abortCtl = null;
  }

  const completionTokens = usage?.completionTokens ?? estimateTokens(content.slice(base.length));
  const reasoningTokens = usage?.reasoningTokens ?? (reasoning ? estimateTokens(reasoning.slice(baseReason.length)) : undefined);
  const promptTokens = usage?.promptTokens ?? promptTokensEst;
  const est = promptTokens * pPrompt + completionTokens * pComp + (reasoningTokens ?? 0) * pReason;
  const cost = usage?.costUsd != null ? usage.costUsd + (usage.webSearchCostUsd ?? 0) : est;
  const finalUsage: Usage = { promptTokens, completionTokens, reasoningTokens, costUsd: cost, estimated: usage?.costUsd == null, authoritative: false, webSearchCostUsd: usage?.webSearchCostUsd };
  const prevCost = existing?.usage?.costUsd ?? 0;
  const status: Message['status'] = finalErr ? (content ? 'interrupted' : 'error') : aborted ? 'interrupted' : 'complete';
  const patch: Partial<Message> = { content, reasoning: reasoning || undefined, generationId, usage: finalUsage, status, error: finalErr ? { code: finalErr.code, message: finalErr.message } : aborted ? { code: 'interrupted', message: document.visibilityState === 'hidden' ? 'Interrupted when the app went to the background' : 'Stopped' } : undefined };
  if (finish === 'length' && status === 'complete') patch.error = { code: 'length', message: 'Reply hit the max output token limit' };
  await db.messages.update(opts.assistantId, patch);
  useChat.setState((s) => ({ generating: false, messages: { ...s.messages, [opts.assistantId]: { ...s.messages[opts.assistantId]!, ...patch } } }));
  useStream.setState({ id: null, content: '', reasoning: '', retryAt: null, retryReason: null });

  const preview = stripMd(content || finalErr?.message || '', 100);
  const now = Date.now();
  const st2 = useChat.getState();
  const tokenEstimate = contextTokens(st2.chat, st2.messages, st2.path);
  await db.chats.update(chat.id, { updatedAt: now, lastPreview: preview, tokenEstimate });
  useChat.setState((s) => (s.chat ? { chat: { ...s.chat, updatedAt: now, lastPreview: preview, tokenEstimate } } : {}));
  await applyCostDelta(chat.id, (cost || 0) - prevCost);
  await db.dayCosts.get(dayKey()).then((d) => db.dayCosts.put({ day: dayKey(), costUsd: d?.costUsd ?? 0, messages: (d?.messages ?? 0) + 1 }));
  useApp.getState().update((s) => ({ messagesSinceExport: (s.messagesSinceExport ?? 0) + 2 }));
  void useChats.getState().reload();

  if (generationId && status !== 'error' && cfg.apiKey) {
    void fetchGenerationWithRetry(cfg, generationId).then(async (g) => {
      if (!g) return;
      const authoritative: Usage = { promptTokens: g.nativeTokensPrompt || g.tokensPrompt || promptTokens, completionTokens: g.nativeTokensCompletion || g.tokensCompletion || completionTokens, reasoningTokens: g.nativeTokensReasoning || reasoningTokens, costUsd: g.totalCost, authoritative: true, estimated: false, webSearchCostUsd: usage?.webSearchCostUsd };
      await useChat.getState().applyAuthoritative(opts.assistantId, authoritative);
    });
  }
  if (status === 'complete' && lastUser && chat.titleAuto !== false && !opts.continueMode) void maybeTitle(chat.id, lastUser.content, content);
  if (status === 'complete' && lastUser && chat.memoryEnabled) {
    const final = useChat.getState().messages[opts.assistantId];
    if (final) scheduleExtraction(chat.id, lastUser, final);
  }
}

async function finalizeError(assistantId: string, error: { code: string; message: string }): Promise<void> {
  await db.messages.update(assistantId, { status: 'error', error });
  useChat.setState((s) => ({ generating: false, messages: { ...s.messages, [assistantId]: { ...s.messages[assistantId]!, status: 'error', error } } }));
}

async function maybeTitle(chatId: string, userText: string, assistantText: string): Promise<void> {
  const app = useApp.getState().settings;
  const cur = await db.chats.get(chatId);
  if (!cur || cur.titleAuto === false || (cur.title !== 'New chat' && !cur.title.endsWith('…') && cur.title.length < 48 && cur.title !== stripMd(userText, 48))) return;
  try {
    const r = await completeOnce(clientConfig(), {
      body: {
        model: app.memory.extractionModelId,
        messages: [
          { role: 'system', content: 'Write a title for this conversation: two to six words, sentence case, no quotes, no trailing punctuation. Reply with the title only.' },
          { role: 'user', content: `User: ${userText.slice(0, 1500)}\n\nAssistant: ${assistantText.slice(0, 1500)}` },
        ],
        max_tokens: 24,
        temperature: 0.3,
      },
    });
    const title = r.content.trim().replace(/^["'“”]+|["'“”.]+$/g, '').split('\n')[0]?.slice(0, 60);
    if (title) {
      await db.chats.update(chatId, { title });
      const st = useChat.getState();
      if (st.chat?.id === chatId) useChat.setState({ chat: { ...st.chat, title } });
      void useChats.getState().reload();
    }
  } catch { /* fallback title stays */ }
}

export const useChat = create<ChatState>((set, get) => ({
  chat: null,
  messages: {},
  path: [],
  persisted: false,
  generating: false,
  pinned: true,
  open: async (id) => {
    if (abortCtl) abortCtl.abort();
    let chat: Chat | undefined;
    if (id) chat = await db.chats.get(id);
    if (!chat) {
      const last = useApp.getState().settings.lastChatId;
      if (last) chat = await db.chats.get(last);
      if (!chat) chat = await db.chats.orderBy('updatedAt').reverse().filter((c) => !c.archived).first();
    }
    if (!chat) { await get().newChat(); return; }
    const list = await db.messages.where('chatId').equals(chat.id).toArray();
    const messages: Record<string, Message> = {};
    for (const m of list) {
      // Anything left mid-stream by a torn-down page becomes interrupted.
      if (m.status === 'streaming') { m.status = m.content ? 'interrupted' : 'error'; m.error = { code: 'interrupted', message: 'Interrupted before the reply finished' }; void db.messages.update(m.id, { status: m.status, error: m.error }); }
      messages[m.id] = m;
    }
    let leaf = chat.activeLeafId ?? null;
    if (!leaf || !messages[leaf]) { const roots = childrenOf(messages, null); leaf = roots.length ? deepest(messages, roots[roots.length - 1]!.id) : null; }
    set({ chat, messages, path: computePath(messages, leaf), persisted: true, generating: false, pinned: true });
    useApp.getState().update({ lastChatId: chat.id });
  },
  newChat: async (opts = {}) => {
    if (abortCtl) abortCtl.abort();
    const chat = freshChat(opts);
    set({ chat, messages: {}, path: [], persisted: false, generating: false, pinned: true });
  },
  patchChat: async (patch) => {
    const c = get().chat;
    if (!c) return;
    const next = { ...c, ...patch };
    set({ chat: next });
    if (get().persisted) { await db.chats.update(c.id, patch); void useChats.getState().reload(); }
  },
  saveDraft: (text) => {
    const c = get().chat;
    if (!c) return;
    set({ chat: { ...c, draft: text } });
    if (draftTimer) clearTimeout(draftTimer);
    draftTimer = setTimeout(() => { if (get().persisted) void db.chats.update(c.id, { draft: text }); }, 200);
  },
  setModel: async (id) => {
    await get().patchChat({ modelId: id });
    useApp.getState().touchRecent(id);
  },
  send: async (text, attachments = []) => {
    const st = get();
    const chat = st.chat;
    if (!chat || st.generating) return;
    const trimmed = text.trim();
    if (!trimmed && !attachments.length) return;
    const now = Date.now();
    const parent = st.path[st.path.length - 1] ?? null;
    const user: Message = { id: uid(), chatId: chat.id, parentId: parent, role: 'user', content: trimmed, attachments: attachments.length ? attachments : undefined, createdAt: now, status: 'complete', lc: trimmed.toLowerCase() };
    const asst: Message = { id: uid(), chatId: chat.id, parentId: user.id, role: 'assistant', content: '', modelId: chat.modelId, createdAt: now + 1, status: 'streaming' };
    const isFirst = st.path.length === 0;
    const title = isFirst && chat.title === 'New chat' ? stripMd(trimmed || attachments[0]?.name || 'New chat', 48) : chat.title;
    const nextChat: Chat = { ...chat, title, updatedAt: now, activeLeafId: asst.id, draft: '', lastPreview: stripMd(trimmed, 100) };
    set((s) => ({ chat: nextChat, messages: { ...s.messages, [user.id]: user, [asst.id]: asst }, path: [...s.path, user.id, asst.id], pinned: true }));
    await ensurePersisted();
    await db.transaction('rw', db.chats, db.messages, async () => { await db.messages.bulkAdd([user, asst]); await db.chats.update(chat.id, { title, updatedAt: now, activeLeafId: asst.id, draft: '', lastPreview: nextChat.lastPreview }); });
    useApp.getState().touchRecent(chat.modelId);
    await generate({ assistantId: asst.id, modelId: chat.modelId });
  },
  stop: () => { abortCtl?.abort(new DOMException('Stopped', 'AbortError')); },
  regenerate: async (assistantId, modelId) => {
    const st = get();
    const chat = st.chat;
    const old = st.messages[assistantId];
    if (!chat || !old || st.generating) return;
    const mid = modelId ?? chat.modelId;
    const asst: Message = { id: uid(), chatId: chat.id, parentId: old.parentId, role: 'assistant', content: '', modelId: mid, createdAt: Date.now(), status: 'streaming' };
    const messages = { ...st.messages, [asst.id]: asst };
    set({ messages, path: computePath(messages, asst.id), chat: { ...chat, activeLeafId: asst.id, modelId: mid }, pinned: true });
    await db.transaction('rw', db.chats, db.messages, async () => { await db.messages.add(asst); await db.chats.update(chat.id, { activeLeafId: asst.id, modelId: mid }); });
    if (modelId) useApp.getState().touchRecent(modelId);
    await generate({ assistantId: asst.id, modelId: mid });
  },
  editResend: async (userId, text) => {
    const st = get();
    const chat = st.chat;
    const old = st.messages[userId];
    if (!chat || !old || st.generating) return;
    const now = Date.now();
    const user: Message = { ...old, id: uid(), content: text.trim(), createdAt: now, editedFrom: old.id, lc: text.trim().toLowerCase() };
    const asst: Message = { id: uid(), chatId: chat.id, parentId: user.id, role: 'assistant', content: '', modelId: chat.modelId, createdAt: now + 1, status: 'streaming' };
    const messages = { ...st.messages, [user.id]: user, [asst.id]: asst };
    set({ messages, path: computePath(messages, asst.id), chat: { ...chat, activeLeafId: asst.id }, pinned: true });
    await db.transaction('rw', db.chats, db.messages, async () => { await db.messages.bulkAdd([user, asst]); await db.chats.update(chat.id, { activeLeafId: asst.id }); });
    await generate({ assistantId: asst.id, modelId: chat.modelId });
  },
  continueFrom: async (assistantId) => {
    const st = get();
    const m = st.messages[assistantId];
    if (!st.chat || !m || st.generating) return;
    if (st.path[st.path.length - 1] !== assistantId) { set({ path: computePath(st.messages, assistantId) }); }
    await generate({ assistantId, modelId: m.modelId ?? st.chat.modelId, continueMode: true });
  },
  retryMessage: async (assistantId) => {
    const st = get();
    const m = st.messages[assistantId];
    if (!st.chat || !m || st.generating) return;
    const reset: Message = { ...m, content: '', reasoning: undefined, error: undefined, usage: undefined, status: 'streaming' };
    set((s) => ({ messages: { ...s.messages, [assistantId]: reset }, path: computePath({ ...s.messages, [assistantId]: reset }, assistantId), pinned: true }));
    await db.messages.update(assistantId, { content: '', reasoning: undefined, error: undefined, usage: undefined, status: 'streaming' });
    await generate({ assistantId, modelId: m.modelId ?? st.chat.modelId });
  },
  switchBranch: async (messageId, dir) => {
    const st = get();
    const m = st.messages[messageId];
    if (!st.chat || !m) return;
    const sibs = childrenOf(st.messages, m.parentId);
    const i = sibs.findIndex((x) => x.id === messageId);
    const target = sibs[i + dir];
    if (!target) return;
    const leaf = deepest(st.messages, target.id);
    set({ path: computePath(st.messages, leaf), chat: { ...st.chat, activeLeafId: leaf } });
    if (st.persisted) await db.chats.update(st.chat.id, { activeLeafId: leaf });
  },
  deleteMessage: async (id) => {
    const st = get();
    const m = st.messages[id];
    if (!st.chat || !m) return;
    const doomed = new Set<string>();
    const stack = [id];
    while (stack.length) { const cur = stack.pop()!; doomed.add(cur); for (const k of childrenOf(st.messages, cur)) stack.push(k.id); }
    const messages = { ...st.messages };
    for (const d of doomed) delete messages[d];
    let leaf: string | null = st.chat.activeLeafId ?? null;
    if (!leaf || doomed.has(leaf)) leaf = m.parentId ? deepest(messages, m.parentId) : (childrenOf(messages, null).at(-1)?.id ?? null);
    set({ messages, path: computePath(messages, leaf), chat: { ...st.chat, activeLeafId: leaf } });
    await db.transaction('rw', db.chats, db.messages, async () => { await db.messages.bulkDelete([...doomed]); await db.chats.update(st.chat!.id, { activeLeafId: leaf }); });
    void useChats.getState().reload();
  },
  branchFrom: async (messageId) => {
    const st = get();
    if (!st.chat) throw new Error('No chat');
    const ids = computePath(st.messages, messageId);
    const now = Date.now();
    const newId = uid();
    const idMap = new Map<string, string>(ids.map((i) => [i, uid()]));
    const copies: Message[] = ids.map((i) => { const m = st.messages[i]!; return { ...m, id: idMap.get(i)!, chatId: newId, parentId: m.parentId ? idMap.get(m.parentId) ?? null : null, editedFrom: undefined }; });
    const chat: Chat = { ...st.chat, id: newId, title: `${st.chat.title} (branch)`, createdAt: now, updatedAt: now, pinned: false, archived: false, activeLeafId: idMap.get(messageId) ?? null, draft: '', totalCostUsd: 0, titleAuto: false };
    await db.transaction('rw', db.chats, db.messages, async () => { await db.chats.add(chat); await db.messages.bulkAdd(copies); });
    void useChats.getState().reload();
    return newId;
  },
  setPinned: (v) => { if (get().pinned !== v) set({ pinned: v }); },
  applyAuthoritative: async (msgId, usage) => {
    const st = get();
    const stored = await db.messages.get(msgId);
    if (!stored) return;
    const prev = stored.usage?.costUsd ?? 0;
    await db.messages.update(msgId, { usage });
    if (st.messages[msgId]) set((s) => ({ messages: { ...s.messages, [msgId]: { ...s.messages[msgId]!, usage } } }));
    await applyCostDelta(stored.chatId, (usage.costUsd ?? 0) - prev);
  },
}));

/** Siblings info for the ‹ n/m › control. */
export function siblingInfo(messages: Record<string, Message>, id: string): { index: number; count: number } {
  const m = messages[id];
  if (!m) return { index: 0, count: 1 };
  const sibs = childrenOf(messages, m.parentId);
  return { index: sibs.findIndex((x) => x.id === id), count: sibs.length };
}
