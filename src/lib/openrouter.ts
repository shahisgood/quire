import type { KeyMeta, ORModel } from './types';

export const OR_ORIGIN = 'https://openrouter.ai';
export const APP_TITLE = 'Quire';

export class ORError extends Error {
  status: number;
  code: string;
  metadata?: Record<string, unknown>;
  retryAfterMs?: number;
  constructor(status: number, message: string, code?: string, metadata?: Record<string, unknown>) {
    super(message);
    this.status = status;
    this.code = code ?? String(status);
    this.metadata = metadata;
  }
}

export interface ClientConfig { apiKey: string | null; baseUrl?: string }

function base(cfg: ClientConfig): string {
  const b = (cfg.baseUrl ?? '').trim();
  return b ? b.replace(/\/+$/, '') : `${OR_ORIGIN}/api/v1`;
}

function headers(cfg: ClientConfig, auth = true): Record<string, string> {
  const h: Record<string, string> = { 'Content-Type': 'application/json', 'X-Title': APP_TITLE };
  if (typeof location !== 'undefined') h['HTTP-Referer'] = location.origin;
  if (auth && cfg.apiKey) h.Authorization = `Bearer ${cfg.apiKey}`;
  return h;
}

/** Parse an error response body into an ORError, surfacing the real message verbatim. */
export async function toError(res: Response): Promise<ORError> {
  let body: unknown = null;
  let text = '';
  try { text = await res.text(); body = JSON.parse(text); } catch { /* not json */ }
  const err = (body as { error?: { message?: string; code?: string | number; metadata?: Record<string, unknown> } } | null)?.error;
  const msg = err?.message ?? (text ? text.slice(0, 400) : `${res.status} ${res.statusText}`);
  const e = new ORError(res.status, msg, err?.code != null ? String(err.code) : undefined, err?.metadata);
  const ra = res.headers.get('retry-after');
  if (ra) { const n = Number(ra); e.retryAfterMs = Number.isFinite(n) ? n * 1000 : Math.max(0, Date.parse(ra) - Date.now()); }
  return e;
}

// ---------------- Models ----------------
const str = (v: unknown, d = ''): string => (typeof v === 'string' ? v : d);
const num = (v: unknown, d = 0): number => (typeof v === 'number' && Number.isFinite(v) ? v : d);
const numOrNull = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const strArr = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

export function normaliseModel(raw: unknown): ORModel | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const id = str(r.id);
  if (!id) return null;
  const arch = (r.architecture ?? {}) as Record<string, unknown>;
  const pricing = (r.pricing ?? {}) as Record<string, unknown>;
  const top = (r.top_provider ?? {}) as Record<string, unknown>;
  return {
    id,
    canonicalSlug: str(r.canonical_slug, id),
    name: str(r.name, id),
    created: num(r.created),
    description: str(r.description),
    contextLength: num(r.context_length),
    architecture: {
      modality: str(arch.modality, 'text->text'),
      inputModalities: strArr(arch.input_modalities).length ? strArr(arch.input_modalities) : ['text'],
      outputModalities: strArr(arch.output_modalities).length ? strArr(arch.output_modalities) : ['text'],
      tokenizer: str(arch.tokenizer),
      instructType: typeof arch.instruct_type === 'string' ? arch.instruct_type : null,
    },
    pricing: {
      prompt: str(pricing.prompt, '0'),
      completion: str(pricing.completion, '0'),
      request: str(pricing.request, '0'),
      image: str(pricing.image, '0'),
      web_search: str(pricing.web_search, '0'),
      internal_reasoning: str(pricing.internal_reasoning, '0'),
      input_cache_read: str(pricing.input_cache_read, '0'),
      input_cache_write: str(pricing.input_cache_write, '0'),
    },
    topProvider: { contextLength: numOrNull(top.context_length), maxCompletionTokens: numOrNull(top.max_completion_tokens), isModerated: Boolean(top.is_moderated) },
    supportedParameters: strArr(r.supported_parameters),
    perRequestLimits: r.per_request_limits,
  };
}

export async function fetchModels(cfg: ClientConfig, signal?: AbortSignal): Promise<ORModel[]> {
  const res = await fetch(`${base(cfg)}/models`, { headers: headers(cfg, false), signal });
  if (!res.ok) throw await toError(res);
  const json = (await res.json()) as { data?: unknown[] };
  const list = Array.isArray(json.data) ? json.data : [];
  return list.map(normaliseModel).filter((m): m is ORModel => m !== null);
}

// ---------------- Key ----------------
export async function fetchKeyMeta(cfg: ClientConfig): Promise<KeyMeta> {
  const res = await fetch(`${base(cfg)}/key`, { headers: headers(cfg) });
  if (!res.ok) throw await toError(res);
  const j = (await res.json()) as { data?: Record<string, unknown> };
  const d = j.data ?? {};
  const rl = d.rate_limit as { requests?: number; interval?: string } | undefined;
  return {
    label: str(d.label, 'API key'),
    usage: num(d.usage),
    limit: numOrNull(d.limit),
    limitRemaining: numOrNull(d.limit_remaining),
    isFreeTier: Boolean(d.is_free_tier),
    rateLimit: rl ? { requests: num(rl.requests), interval: str(rl.interval) } : null,
    fetchedAt: Date.now(),
  };
}

// ---------------- Generation stats ----------------
export interface GenerationStats {
  id: string;
  totalCost: number;
  tokensPrompt: number;
  tokensCompletion: number;
  nativeTokensPrompt: number;
  nativeTokensCompletion: number;
  nativeTokensReasoning: number;
  model: string;
  providerName: string;
  latencyMs: number | null;
}

export async function fetchGeneration(cfg: ClientConfig, id: string): Promise<GenerationStats> {
  const res = await fetch(`${base(cfg)}/generation?id=${encodeURIComponent(id)}`, { headers: headers(cfg) });
  if (!res.ok) throw await toError(res);
  const j = (await res.json()) as { data?: Record<string, unknown> };
  const d = j.data ?? {};
  return {
    id: str(d.id, id),
    totalCost: num(d.total_cost),
    tokensPrompt: num(d.tokens_prompt),
    tokensCompletion: num(d.tokens_completion),
    nativeTokensPrompt: num(d.native_tokens_prompt),
    nativeTokensCompletion: num(d.native_tokens_completion),
    nativeTokensReasoning: num(d.native_tokens_reasoning),
    model: str(d.model),
    providerName: str(d.provider_name),
    latencyMs: numOrNull(d.latency),
  };
}

/** Poll /generation with backoff; it lags the stream by a second or two. */
export async function fetchGenerationWithRetry(cfg: ClientConfig, id: string, attempts = 4): Promise<GenerationStats | null> {
  let delay = 1200;
  for (let i = 0; i < attempts; i++) {
    await new Promise((r) => setTimeout(r, delay));
    try {
      const g = await fetchGeneration(cfg, id);
      if (g.totalCost > 0 || g.nativeTokensCompletion > 0 || g.tokensCompletion > 0) return g;
    } catch (e) {
      if (e instanceof ORError && e.status === 401) return null;
    }
    delay = Math.min(delay * 1.8, 6000);
  }
  return null;
}

// ---------------- Chat completions ----------------
export type ContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string } }
  | { type: 'file'; file: { filename: string; file_data: string } };

export interface ChatMessageParam { role: 'system' | 'user' | 'assistant'; content: string | ContentPart[] }

export interface StreamUsage { promptTokens: number; completionTokens: number; reasoningTokens?: number; cost?: number; webSearchCost?: number }

export interface StreamEvent {
  id?: string;
  model?: string;
  content?: string;
  reasoning?: string;
  finishReason?: string | null;
  usage?: StreamUsage;
}

function parseUsage(u: unknown): StreamUsage | undefined {
  if (!u || typeof u !== 'object') return undefined;
  const r = u as Record<string, unknown>;
  const cd = r.completion_tokens_details as Record<string, unknown> | undefined;
  const cost = num(r.cost, NaN);
  const costDetails = r.cost_details as Record<string, unknown> | undefined;
  return {
    promptTokens: num(r.prompt_tokens),
    completionTokens: num(r.completion_tokens),
    reasoningTokens: cd ? num(cd.reasoning_tokens) : undefined,
    cost: Number.isFinite(cost) ? cost : undefined,
    webSearchCost: costDetails ? num(costDetails.upstream_inference_cost, 0) : undefined,
  };
}

function reasoningFromDelta(delta: Record<string, unknown>): string {
  if (typeof delta.reasoning === 'string' && delta.reasoning) return delta.reasoning;
  if (typeof delta.reasoning_content === 'string' && delta.reasoning_content) return delta.reasoning_content;  // DeepSeek-native field, passed through by some providers
  const details = delta.reasoning_details;
  if (Array.isArray(details)) {
    return details
      .map((d) => {
        if (!d || typeof d !== 'object') return '';
        const x = d as Record<string, unknown>;
        return str(x.text) || str(x.summary) || '';
      })
      .join('');
  }
  return '';
}

/** Turn one parsed SSE JSON chunk into a StreamEvent. Throws on in-stream error objects. */
export function chunkToEvent(chunk: unknown): StreamEvent | null {
  if (!chunk || typeof chunk !== 'object') return null;
  const c = chunk as Record<string, unknown>;
  if (c.error && typeof c.error === 'object') {
    const e = c.error as Record<string, unknown>;
    throw new ORError(num(e.code, 500), str(e.message, 'Provider returned an error mid-stream'), e.code != null ? String(e.code) : undefined, e.metadata as Record<string, unknown> | undefined);
  }
  const ev: StreamEvent = {};
  if (typeof c.id === 'string') ev.id = c.id;
  if (typeof c.model === 'string') ev.model = c.model;
  const choices = Array.isArray(c.choices) ? c.choices : [];
  const ch0 = choices[0] as Record<string, unknown> | undefined;
  if (ch0) {
    if (ch0.error && typeof ch0.error === 'object') {
      const e = ch0.error as Record<string, unknown>;
      throw new ORError(num(e.code, 500), str(e.message, 'Provider returned an error mid-stream'), e.code != null ? String(e.code) : undefined);
    }
    const delta = (ch0.delta ?? ch0.message ?? {}) as Record<string, unknown>;
    if (typeof delta.content === 'string' && delta.content) ev.content = delta.content;
    const r = reasoningFromDelta(delta);
    if (r) ev.reasoning = r;
    if (ch0.finish_reason !== undefined) ev.finishReason = ch0.finish_reason as string | null;
  }
  const u = parseUsage(c.usage);
  if (u) ev.usage = u;
  return ev;
}

/** Async generator over SSE lines. Handles keep-alive comments, partial lines and [DONE]. */
export async function* readSSE(body: ReadableStream<Uint8Array>, signal?: AbortSignal): AsyncGenerator<unknown> {
  const reader = body.getReader();
  const dec = new TextDecoder();
  let buf = '';
  try {
    while (true) {
      if (signal?.aborted) return;
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let nl: number;
      while ((nl = buf.indexOf('\n')) >= 0) {
        let line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (line.endsWith('\r')) line = line.slice(0, -1);
        if (!line || line.startsWith(':')) continue; // keep-alive / comment
        if (!line.startsWith('data:')) continue;
        const data = line.slice(5).trimStart();
        if (data === '[DONE]') return;
        try { yield JSON.parse(data); } catch { /* skip malformed line */ }
      }
    }
    const rest = buf.trim();
    if (rest.startsWith('data:')) {
      const data = rest.slice(5).trim();
      if (data && data !== '[DONE]') { try { yield JSON.parse(data); } catch { /* ignore */ } }
    }
  } finally {
    try { reader.releaseLock(); } catch { /* ignore */ }
  }
}

export interface CompletionRequest { body: Record<string, unknown>; signal?: AbortSignal }

/** Streaming completion: yields StreamEvents. Non-2xx throws ORError with the real message. */
export async function* streamCompletion(cfg: ClientConfig, req: CompletionRequest): AsyncGenerator<StreamEvent> {
  const res = await fetch(`${base(cfg)}/chat/completions`, {
    method: 'POST',
    headers: headers(cfg),
    body: JSON.stringify({ ...req.body, stream: true }),
    signal: req.signal,
  });
  if (!res.ok) throw await toError(res);
  if (!res.body) throw new ORError(0, 'No response body from OpenRouter');
  for await (const chunk of readSSE(res.body, req.signal)) {
    const ev = chunkToEvent(chunk);
    if (ev) yield ev;
  }
}

export interface CompletionResult { id: string; model: string; content: string; reasoning: string; finishReason: string | null; usage?: StreamUsage }

export async function completeOnce(cfg: ClientConfig, req: CompletionRequest): Promise<CompletionResult> {
  const res = await fetch(`${base(cfg)}/chat/completions`, {
    method: 'POST',
    headers: headers(cfg),
    body: JSON.stringify({ ...req.body, stream: false }),
    signal: req.signal,
  });
  if (!res.ok) throw await toError(res);
  const j = (await res.json()) as Record<string, unknown>;
  if (j.error && typeof j.error === 'object') {
    const e = j.error as Record<string, unknown>;
    throw new ORError(num(e.code, 500), str(e.message, 'Request failed'), e.code != null ? String(e.code) : undefined, e.metadata as Record<string, unknown> | undefined);
  }
  const ch0 = (Array.isArray(j.choices) ? j.choices[0] : undefined) as Record<string, unknown> | undefined;
  const msg = (ch0?.message ?? {}) as Record<string, unknown>;
  let content = '';
  if (typeof msg.content === 'string') content = msg.content;
  else if (Array.isArray(msg.content)) content = msg.content.map((p) => str((p as Record<string, unknown>).text)).join('');
  return {
    id: str(j.id),
    model: str(j.model),
    content,
    reasoning: reasoningFromDelta(msg),
    finishReason: (ch0?.finish_reason as string | null | undefined) ?? null,
    usage: parseUsage(j.usage),
  };
}

// ---------------- OAuth PKCE ----------------
const PKCE_KEY = 'quire.pkce_verifier';

function b64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = '';
  for (const b of arr) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function beginOAuth(): Promise<void> {
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(48)));
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  const challenge = b64url(digest);
  localStorage.setItem(PKCE_KEY, verifier);
  const cb = `${location.origin}${location.pathname}`;
  const url = `${OR_ORIGIN}/auth?callback_url=${encodeURIComponent(cb)}&code_challenge=${encodeURIComponent(challenge)}&code_challenge_method=S256`;
  location.assign(url);
}

/** If the URL carries an OAuth `code`, exchange it for a key. Returns the key or null. Cleans the URL either way. */
export async function completeOAuthIfPresent(cfg: ClientConfig): Promise<{ key: string | null; error?: string }> {
  const params = new URLSearchParams(location.search);
  const code = params.get('code');
  if (!code) return { key: null };
  const verifier = localStorage.getItem(PKCE_KEY);
  history.replaceState(null, '', location.pathname);
  if (!verifier) return { key: null, error: 'The sign-in round trip lost its state. Paste your key manually instead.' };
  try {
    const res = await fetch(`${base(cfg)}/auth/keys`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, code_verifier: verifier, code_challenge_method: 'S256' }),
    });
    if (!res.ok) { const e = await toError(res); return { key: null, error: e.message }; }
    const j = (await res.json()) as { key?: string };
    localStorage.removeItem(PKCE_KEY);
    return j.key ? { key: j.key } : { key: null, error: 'OpenRouter did not return a key.' };
  } catch (e) {
    return { key: null, error: e instanceof Error ? e.message : 'Key exchange failed' };
  }
}
