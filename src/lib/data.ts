import { db, uid } from './db';
import type { AppSettings, Chat, DayCost, Folder, MemoryEntry, Message, Preset } from './types';
import { useApp } from '@/store/app';
import { useChats } from '@/store/chats';

export interface Bundle {
  app: 'quire';
  version: 1;
  exportedAt: number;
  chats: Chat[];
  messages: Message[];
  folders: Folder[];
  presets: Preset[];
  memory: MemoryEntry[];
  dayCosts: DayCost[];
  settings: Omit<AppSettings, 'apiKey'> & { apiKey?: string | null };
}

export async function buildBundle(opts: { includeKey: boolean; chatIds?: string[] }): Promise<Bundle> {
  const settings = structuredClone(useApp.getState().settings) as Bundle['settings'];
  if (!opts.includeKey) delete settings.apiKey;
  const chats = opts.chatIds ? (await db.chats.bulkGet(opts.chatIds)).filter((c): c is Chat => Boolean(c)) : await db.chats.toArray();
  const messages = opts.chatIds ? await db.messages.where('chatId').anyOf(opts.chatIds).toArray() : await db.messages.toArray();
  return {
    app: 'quire', version: 1, exportedAt: Date.now(), chats, messages,
    folders: await db.folders.toArray(), presets: await db.presets.toArray(), memory: await db.memory.toArray(), dayCosts: await db.dayCosts.toArray(), settings,
  };
}

/** Share a file via the iOS share sheet when possible; otherwise trigger a download. */
export async function shareFile(name: string, text: string, mime: string): Promise<'shared' | 'downloaded'> {
  const file = new File([text], name, { type: mime });
  const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
  if (nav.share && nav.canShare?.({ files: [file] })) {
    try { await nav.share({ files: [file], title: name }); return 'shared'; } catch (e) { if (e instanceof DOMException && e.name === 'AbortError') return 'shared'; }
  }
  const url = URL.createObjectURL(file);
  const a = document.createElement('a');
  a.href = url; a.download = name; a.rel = 'noopener';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return 'downloaded';
}

export async function exportAll(includeKey = false): Promise<void> {
  const b = await buildBundle({ includeKey });
  const stamp = new Date().toISOString().slice(0, 10);
  await shareFile(`quire-backup-${stamp}.json`, JSON.stringify(b), 'application/json');
  useApp.getState().update({ lastExportAt: Date.now(), messagesSinceExport: 0 });
}

export async function exportChatJson(chatId: string): Promise<void> {
  const b = await buildBundle({ includeKey: false, chatIds: [chatId] });
  const title = b.chats[0]?.title ?? 'chat';
  await shareFile(`${slug(title)}.json`, JSON.stringify(b), 'application/json');
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'chat';

export function chatToMarkdown(chat: Chat, thread: Message[]): string {
  const lines = [`# ${chat.title}`, '', `_${new Date(chat.createdAt).toLocaleString()} · ${chat.modelId}_`, ''];
  for (const m of thread) {
    if (m.role === 'user') { lines.push('## You', '', m.content, ''); }
    else { lines.push(`## ${m.modelId ?? 'Assistant'}`, ''); if (m.reasoning) lines.push('<details><summary>Reasoning</summary>', '', m.reasoning, '', '</details>', ''); lines.push(m.content, ''); }
  }
  return lines.join('\n');
}

export async function exportChatMarkdown(chat: Chat, thread: Message[]): Promise<void> {
  await shareFile(`${slug(chat.title)}.md`, chatToMarkdown(chat, thread), 'text/markdown');
}

export interface ImportResult { chats: number; messages: number; memory: number; presets: number; folders: number }

export async function importBundle(text: string, mode: 'merge' | 'replace'): Promise<ImportResult> {
  let j: unknown;
  try { j = JSON.parse(text); } catch { throw new Error('That file is not valid JSON.'); }
  const b = j as Partial<Bundle>;
  if (!b || b.app !== 'quire' || !Array.isArray(b.chats) || !Array.isArray(b.messages)) throw new Error('That file is not a Quire backup.');
  const chats = b.chats as Chat[];
  const messages = b.messages as Message[];
  const folders = (b.folders ?? []) as Folder[];
  const presets = (b.presets ?? []) as Preset[];
  const memory = (b.memory ?? []) as MemoryEntry[];
  const dayCosts = (b.dayCosts ?? []) as DayCost[];
  await db.transaction('rw', [db.chats, db.messages, db.folders, db.presets, db.memory, db.dayCosts], async () => {
    if (mode === 'replace') { await Promise.all([db.chats.clear(), db.messages.clear(), db.folders.clear(), db.presets.clear(), db.memory.clear(), db.dayCosts.clear()]); }
    await db.folders.bulkPut(folders);
    await db.presets.bulkPut(presets);
    await db.chats.bulkPut(chats);
    await db.messages.bulkPut(messages.map((m) => ({ ...m, lc: m.role === 'user' ? m.content.toLowerCase() : undefined })));
    if (mode === 'replace') { await db.memory.bulkPut(memory); await db.dayCosts.bulkPut(dayCosts); }
    else {
      const existing = new Set((await db.memory.toArray()).map((e) => e.text.toLowerCase()));
      await db.memory.bulkPut(memory.filter((e) => !existing.has(e.text.toLowerCase())).map((e) => ({ ...e, id: uid() })));
      for (const d of dayCosts) { const cur = await db.dayCosts.get(d.day); if (!cur) await db.dayCosts.put(d); }
    }
  });
  if (b.settings && typeof b.settings === 'object') {
    const app = useApp.getState();
    const s = b.settings as Partial<AppSettings>;
    const { apiKey, ...rest } = s;
    app.update((cur) => ({ ...rest, apiKey: apiKey ?? cur.apiKey, keyMeta: null, ui: { ...cur.ui, ...(rest.ui ?? {}) }, memory: { ...cur.memory, ...(rest.memory ?? {}) }, globalSettings: { ...cur.globalSettings, ...(rest.globalSettings ?? {}) } }));
    if (rest.ui) app.updateUI(rest.ui);
  }
  await useChats.getState().reload();
  return { chats: chats.length, messages: messages.length, memory: memory.length, presets: presets.length, folders: folders.length };
}

export async function wipeEverything(): Promise<void> {
  await db.delete();
  try { localStorage.clear(); } catch { /* ignore */ }
  if ('caches' in window) { const keys = await caches.keys(); await Promise.all(keys.map((k) => caches.delete(k))); }
  location.replace('/');
}

export async function clearCaches(): Promise<void> {
  if ('caches' in window) { const keys = await caches.keys(); await Promise.all(keys.map((k) => caches.delete(k))); }
  await db.catalogue.clear();
}

export async function storageEstimate(): Promise<{ usage: number; quota: number; persisted: boolean }> {
  const est = navigator.storage?.estimate ? await navigator.storage.estimate() : { usage: 0, quota: 0 };
  const persisted = navigator.storage?.persisted ? await navigator.storage.persisted() : false;
  return { usage: est.usage ?? 0, quota: est.quota ?? 0, persisted };
}

// ---------------- Search ----------------
export interface SearchHit { chatId: string; messageId: string; snippet: string; start: number; end: number; createdAt: number; title: string }

/**
 * Naive lowercase scan over every message. Fine to roughly 5,000 messages on a phone
 * (a few tens of ms); replace with a trigram index beyond that.
 */
export async function searchMessages(query: string, limit = 60): Promise<SearchHit[]> {
  const q = query.trim().toLowerCase();
  if (q.length < 2) return [];
  const chats = new Map((await db.chats.toArray()).map((c) => [c.id, c]));
  const hits: SearchHit[] = [];
  await db.messages.orderBy('createdAt').reverse().until(() => hits.length >= limit).each((m) => {
    const hay = (m.lc ?? m.content.toLowerCase());
    const i = hay.indexOf(q);
    if (i < 0) return;
    const chat = chats.get(m.chatId);
    if (!chat) return;
    const s = Math.max(0, i - 40);
    const e = Math.min(m.content.length, i + q.length + 60);
    hits.push({ chatId: m.chatId, messageId: m.id, snippet: (s > 0 ? '…' : '') + m.content.slice(s, e).replace(/\s+/g, ' ') + (e < m.content.length ? '…' : ''), start: i - s + (s > 0 ? 1 : 0), end: i - s + q.length + (s > 0 ? 1 : 0), createdAt: m.createdAt, title: chat.title });
  });
  return hits;
}
