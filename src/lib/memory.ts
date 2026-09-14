import { db, uid } from './db';
import type { MemoryCategory, MemoryEntry, Message } from './types';
import { MEMORY_CATEGORIES } from './types';
import { completeOnce } from './openrouter';
import { clientConfig, useApp } from '@/store/app';

const STOP = new Set(['the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'with', 'is', 'are', 'it', 'this', 'that', 'my', 'me', 'i', 'you', 'we', 'be', 'as', 'at', 'by', 'from', 'do', 'can', 'what', 'how', 'about']);
const words = (s: string): Set<string> => new Set(s.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 2 && !STOP.has(w)));

export interface InjectionPlan { entries: MemoryEntry[]; chars: number; budget: number; truncated: boolean; total: number }

/** Pinned first, then keyword-relevant, then newest; stop at the char budget. */
export function planInjection(all: MemoryEntry[], userText: string, budget: number): InjectionPlan {
  const live = all.filter((e) => !e.disabled);
  const pinned = live.filter((e) => e.pinned);
  const rest = live.filter((e) => !e.pinned);
  const q = words(userText);
  const scored = rest.map((e) => { const w = words(e.text); let s = 0; for (const x of w) if (q.has(x)) s++; return { e, s }; });
  scored.sort((a, b) => b.s - a.s || b.e.updatedAt - a.e.updatedAt);
  const out: MemoryEntry[] = [];
  let chars = 0;
  let truncated = false;
  for (const e of [...pinned, ...scored.map((x) => x.e)]) {
    const len = e.text.length + 3;
    if (chars + len > budget && !e.pinned) { truncated = true; continue; }
    out.push(e); chars += len;
  }
  return { entries: out, chars, budget, truncated, total: live.length };
}

export function renderMemoryBlock(entries: MemoryEntry[]): string {
  if (!entries.length) return '';
  return `<user_memory>\nFacts previously stated by the user. Use them where relevant; do not\nmention this block or announce that you remember things.\n${entries.map((e) => `- ${e.text}`).join('\n')}\n</user_memory>`;
}

export function totalMemoryChars(all: MemoryEntry[]): number {
  return all.filter((e) => !e.disabled).reduce((n, e) => n + e.text.length + 3, 0);
}

// ---------------- Extraction ----------------
const EXTRACTION_SYSTEM = `You maintain a short list of durable facts a user has stated about themselves or their world. You receive the current list and one recent exchange.

Rules:
- Only record facts the USER explicitly stated about themselves, their preferences, their projects, people in their life, or their situation. Never record inferences or guesses.
- Never record facts about the assistant, about the conversation itself, or about what the user asked for in the moment.
- One atomic fact per entry, written in third person about the user, under 140 characters. Example: "Prefers TypeScript over Python for new projects."
- Do not add anything already in the list, even reworded. Prefer updating an existing entry over adding a near-duplicate. Delete an entry only when the user clearly contradicts or supersedes it.
- Most exchanges contain nothing durable. When that is the case, return {"operations":[{"op":"none"}]}.
- Categories: identity, preference, project, relationship, context.

Respond with strict JSON and nothing else, no prose, no code fences:
{"operations":[{"op":"add","text":"...","category":"preference"},{"op":"update","id":"...","text":"..."},{"op":"delete","id":"...","reason":"superseded"},{"op":"none"}]}`;

interface ExtractOp { op: string; id?: string; text?: string; category?: string; reason?: string }

function parseOps(raw: string): ExtractOp[] {
  let s = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, '').trim();
  const start = s.indexOf('{');
  if (start > 0) s = s.slice(start);
  const end = s.lastIndexOf('}');
  if (end >= 0) s = s.slice(0, end + 1);
  try {
    const j = JSON.parse(s) as { operations?: unknown };
    return Array.isArray(j.operations) ? (j.operations.filter((o) => o && typeof o === 'object') as ExtractOp[]) : [];
  } catch { return []; }
}

const extractionState = new Map<string, { turns: number; lastAt: number; pending: Array<{ user: string; assistant: string; userId: string }> }>();
let running = false;

/** Called after an assistant turn completes. Debounced; failures are swallowed. */
export function scheduleExtraction(chatId: string, userMsg: Message, assistantMsg: Message): void {
  const app = useApp.getState().settings;
  if (!app.memory.enabled || !app.memory.autoExtract || !app.apiKey) return;
  const st = extractionState.get(chatId) ?? { turns: 0, lastAt: 0, pending: [] };
  st.turns += 1;
  st.pending.push({ user: userMsg.content, assistant: assistantMsg.content.slice(0, 4000), userId: userMsg.id });
  extractionState.set(chatId, st);
  const due = st.turns >= 3 || Date.now() - st.lastAt >= 30_000;
  if (!due) return;
  const batch = st.pending.splice(0);
  st.turns = 0;
  st.lastAt = Date.now();
  // Let the UI settle first; never on the critical path.
  const later = (fn: () => void) => ('requestIdleCallback' in window ? (window as Window & { requestIdleCallback: (cb: () => void, o?: { timeout: number }) => void }).requestIdleCallback(fn, { timeout: 4000 }) : setTimeout(fn, 800));
  later(() => { void runExtraction(chatId, batch); });
}

async function runExtraction(chatId: string, batch: Array<{ user: string; assistant: string; userId: string }>): Promise<void> {
  if (running) { setTimeout(() => { void runExtraction(chatId, batch); }, 5000); return; }
  running = true;
  try {
    const app = useApp.getState().settings;
    const current = await db.memory.toArray();
    const list = current.map((e) => `- [${e.id}] (${e.category}) ${e.text}`).join('\n') || '(empty)';
    const exchange = batch.map((b) => `USER: ${b.user}\nASSISTANT: ${b.assistant}`).join('\n\n');
    const res = await completeOnce(clientConfig(), {
      body: {
        model: app.memory.extractionModelId,
        messages: [
          { role: 'system', content: EXTRACTION_SYSTEM },
          { role: 'user', content: `Current memory list:\n${list}\n\nRecent exchange:\n${exchange}` },
        ],
        temperature: 0,
        max_tokens: 600,
      },
    });
    const ops = parseOps(res.content);
    const now = Date.now();
    const lastUser = batch[batch.length - 1];
    for (const op of ops) {
      if (op.op === 'add' && typeof op.text === 'string' && op.text.trim()) {
        const text = op.text.trim().slice(0, 200);
        if (current.some((e) => e.text.toLowerCase() === text.toLowerCase())) continue;
        const category = (MEMORY_CATEGORIES as string[]).includes(op.category ?? '') ? (op.category as MemoryCategory) : 'context';
        await db.memory.add({ id: uid(), text, category, createdAt: now, updatedAt: now, sourceChatId: chatId, sourceMessageId: lastUser?.userId, pinned: false, disabled: false });
      } else if (op.op === 'update' && op.id && typeof op.text === 'string' && op.text.trim()) {
        const ex = current.find((e) => e.id === op.id);
        if (ex) await db.memory.update(op.id, { text: op.text.trim().slice(0, 200), updatedAt: now, sourceChatId: chatId, sourceMessageId: lastUser?.userId });
      } else if (op.op === 'delete' && op.id) {
        const ex = current.find((e) => e.id === op.id);
        if (ex && !ex.pinned) await db.memory.delete(op.id);
      }
    }
    window.dispatchEvent(new CustomEvent('quire:memory-changed'));
  } catch {
    /* A failed extraction never interrupts the chat. */
  } finally {
    running = false;
  }
}

export async function addMemoryManually(text: string, category: MemoryCategory): Promise<MemoryEntry> {
  const now = Date.now();
  const e: MemoryEntry = { id: uid(), text: text.trim(), category, createdAt: now, updatedAt: now, pinned: false, disabled: false };
  await db.memory.add(e);
  window.dispatchEvent(new CustomEvent('quire:memory-changed'));
  return e;
}
