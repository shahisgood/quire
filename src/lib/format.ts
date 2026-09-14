import type { Attachment, ORModel } from './types';

/** Parse a per-token USD price string safely. Returns 0 for anything unparsable. */
export function parsePrice(s: string | undefined): number {
  if (!s) return 0;
  const n = Number(s);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

/** Per-million-token display, working in integer micro-dollars to avoid float artefacts. */
export function perMillion(s: string | undefined): string {
  const n = parsePrice(s);
  if (n === 0) return 'free';
  const v = n * 1_000_000;
  if (v >= 100) return `$${v.toFixed(0)}`;
  if (v >= 10) return `$${v.toFixed(1)}`;
  if (v >= 1) return `$${v.toFixed(2)}`;
  return `$${v.toFixed(3).replace(/0+$/, '').replace(/\.$/, '')}`;
}

export function isFree(m: ORModel): boolean {
  return parsePrice(m.pricing.prompt) === 0 && parsePrice(m.pricing.completion) === 0;
}

export type PriceBand = 'free' | 'cheap' | 'mid' | 'premium';
export function priceBand(m: ORModel): PriceBand {
  const c = parsePrice(m.pricing.completion) * 1_000_000;
  const p = parsePrice(m.pricing.prompt) * 1_000_000;
  if (c === 0 && p === 0) return 'free';
  if (c <= 1.5 && p <= 0.5) return 'cheap';
  if (c <= 12 && p <= 4) return 'mid';
  return 'premium';
}

export function fmtUsd(n: number | undefined | null, opts: { estimate?: boolean } = {}): string {
  if (n == null || !Number.isFinite(n)) return '—';
  const prefix = opts.estimate ? '~' : '';
  if (n === 0) return `${prefix}$0`;
  if (n < 0.0001) return `${prefix}<$0.0001`;
  if (n < 0.01) return `${prefix}$${n.toFixed(4)}`;
  if (n < 1) return `${prefix}$${n.toFixed(3)}`;
  return `${prefix}$${n.toFixed(2)}`;
}

export function fmtTokens(n: number | undefined): string {
  if (n == null || !Number.isFinite(n)) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 10_000) return `${Math.round(n / 1000)}k`;
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(n);
}

export function fmtContext(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n % 1_000_000 === 0 ? 0 : 1)}M`;
  return `${Math.round(n / 1000)}k`;
}

export function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  if (n < 1024 ** 3) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 ** 3).toFixed(2)} GB`;
}

/** Cheap token estimate: ~4 chars/token for prose, a bit denser for code-like text. */
export function estimateTokens(text: string): number {
  if (!text) return 0;
  const words = text.split(/\s+/).filter(Boolean).length;
  return Math.ceil(Math.max(text.length / 4, words * 1.3));
}

export function estimateAttachmentTokens(a: Attachment): number {
  if (a.kind === 'image') return 1000; // typical vision tile cost; authoritative count replaces it
  return Math.ceil(a.size / 4);
}

export function relTime(t: number, now = Date.now()): string {
  const s = Math.max(0, (now - t) / 1000);
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  const d = Math.floor(s / 86400);
  if (d < 7) return `${d}d`;
  const dt = new Date(t);
  const sameYear = dt.getFullYear() === new Date(now).getFullYear();
  return dt.toLocaleDateString(undefined, sameYear ? { month: 'short', day: 'numeric' } : { year: 'numeric', month: 'short', day: 'numeric' });
}

export function dayGroup(t: number, now = Date.now()): 'Today' | 'Yesterday' | 'This week' | 'Earlier' {
  const d = new Date(now); d.setHours(0, 0, 0, 0);
  const start = d.getTime();
  if (t >= start) return 'Today';
  if (t >= start - 86400_000) return 'Yesterday';
  if (t >= start - 6 * 86400_000) return 'This week';
  return 'Earlier';
}

export function providerOf(id: string): string {
  const i = id.indexOf('/');
  return i > 0 ? id.slice(0, i) : '';
}

export function shortModelName(m: ORModel | undefined, id?: string): string {
  if (m) { const i = m.name.indexOf(': '); return i > 0 ? m.name.slice(i + 2) : m.name; }
  if (!id) return 'No model';
  const j = id.indexOf('/');
  return j > 0 ? id.slice(j + 1) : id;
}

/** Strip markdown to a one-line preview. */
export function stripMd(s: string, max = 120): string {
  const t = s
    .replace(/```[\s\S]*?```/g, ' [code] ')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '[image]')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/[*_~>]+/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

export const isTouch = (): boolean => typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches;
export const isIOS = (): boolean => /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
export const isStandalone = (): boolean => (navigator as Navigator & { standalone?: boolean }).standalone === true || matchMedia('(display-mode: standalone)').matches;

export function clamp(n: number, lo: number, hi: number): number { return Math.min(hi, Math.max(lo, n)); }

export function fuzzyScore(query: string, text: string): number {
  const q = query.toLowerCase();
  const t = text.toLowerCase();
  if (!q) return 1;
  const idx = t.indexOf(q);
  if (idx >= 0) return 100 - Math.min(idx, 50) + q.length; // substring: strongest
  // subsequence match with contiguity bonus
  let ti = 0, score = 0, streak = 0;
  for (const ch of q) {
    const j = t.indexOf(ch, ti);
    if (j < 0) return 0;
    streak = j === ti ? streak + 1 : 0;
    score += 1 + streak;
    ti = j + 1;
  }
  return score;
}
