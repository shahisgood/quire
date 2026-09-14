import type { GenerationSettings, ORModel, ReasoningEffort, ReasoningSettings } from './types';
import { DEFAULT_GENERATION } from './db';

export type ParamKey = keyof Omit<GenerationSettings, 'stream' | 'reasoning' | 'provider' | 'webSearch' | 'transforms' | 'fallbackModels'>;

export interface ParamDef {
  key: ParamKey;
  api: string;
  label: string;
  help: string;
  control: 'slider' | 'number' | 'seed' | 'maxTokens' | 'tags';
  min?: number;
  max?: number;
  step?: number;
  defaultValue?: number;
}

export const PARAM_DEFS: ParamDef[] = [
  { key: 'temperature', api: 'temperature', label: 'Temperature', help: 'How much randomness to allow. 0 is nearly deterministic; above 1.2 gets loose.', control: 'slider', min: 0, max: 2, step: 0.05, defaultValue: 1 },
  { key: 'topP', api: 'top_p', label: 'Top P', help: 'Only sample from the smallest set of tokens whose probabilities add up to this. 1 means no cutoff.', control: 'slider', min: 0, max: 1, step: 0.01, defaultValue: 1 },
  { key: 'topK', api: 'top_k', label: 'Top K', help: 'Only consider the K most likely next tokens. 0 turns it off.', control: 'number', min: 0, step: 1, defaultValue: 0 },
  { key: 'frequencyPenalty', api: 'frequency_penalty', label: 'Frequency penalty', help: 'Push down tokens in proportion to how often they already appeared. Reduces repetition.', control: 'slider', min: -2, max: 2, step: 0.05, defaultValue: 0 },
  { key: 'presencePenalty', api: 'presence_penalty', label: 'Presence penalty', help: 'Push down any token that has appeared at all. Encourages new topics.', control: 'slider', min: -2, max: 2, step: 0.05, defaultValue: 0 },
  { key: 'repetitionPenalty', api: 'repetition_penalty', label: 'Repetition penalty', help: 'Multiplicative penalty on repeated tokens. 1 is off; above 1 discourages repeats.', control: 'slider', min: 0, max: 2, step: 0.01, defaultValue: 1 },
  { key: 'minP', api: 'min_p', label: 'Min P', help: 'Drop tokens whose probability is below this fraction of the top token. 0 is off.', control: 'slider', min: 0, max: 1, step: 0.01, defaultValue: 0 },
  { key: 'topA', api: 'top_a', label: 'Top A', help: 'Dynamic cutoff based on the top token probability squared. 0 is off.', control: 'slider', min: 0, max: 1, step: 0.01, defaultValue: 0 },
  { key: 'seed', api: 'seed', label: 'Seed', help: 'Fix the random seed so repeated requests give the same answer where the provider supports it. Unset is random.', control: 'seed', step: 1 },
  { key: 'maxTokens', api: 'max_tokens', label: 'Max output tokens', help: 'Hard cap on the reply length. Unset lets the model decide, up to its limit.', control: 'maxTokens', min: 1, step: 1 },
  { key: 'stop', api: 'stop', label: 'Stop sequences', help: 'Generation halts as soon as any of these strings appears. Up to four.', control: 'tags' },
];

export const PARAM_BY_KEY = Object.fromEntries(PARAM_DEFS.map((d) => [d.key, d])) as Record<ParamKey, ParamDef>;

export function supports(model: ORModel | undefined, api: string): boolean {
  if (!model) return true; // unknown model: show everything, send everything
  return model.supportedParameters.includes(api);
}

export function supportsReasoning(model: ORModel | undefined): boolean {
  if (!model) return false;
  return model.supportedParameters.includes('reasoning') || model.supportedParameters.includes('include_reasoning');
}

export function acceptsImages(model: ORModel | undefined): boolean {
  return Boolean(model?.architecture.inputModalities.includes('image'));
}
export function acceptsFiles(model: ORModel | undefined): boolean {
  return Boolean(model?.architecture.inputModalities.includes('file'));
}

export interface ReasoningStyle {
  /** Which control to show by default. */
  defaultMode: 'effort' | 'budget';
  /** Whether the model can be told to not reason at all. */
  canDisable: boolean;
  /** Whether the trace is normally returned. */
  returnsTrace: boolean;
  /** Effort levels the model actually distinguishes. */
  efforts: ReasoningEffort[];
  /** Sensible default thinking budget when using budget mode. */
  defaultBudget: number;
  note?: string;
}

/**
 * Explicit family mapping, with a permissive fallback. OpenRouter normalises `effort`
 * into a budget for budget-style models, so exposing both controls is always safe.
 */
/**
 * Which reasoning controls to show for a model.
 * This is a curated table keyed on the model id, NOT data from OpenRouter: the catalogue's
 * `supported_parameters` only says whether `reasoning` is accepted, never which effort levels.
 * OpenRouter maps any level on its unified scale to the nearest the provider supports, so a wrong
 * guess degrades to "close enough", never to an error. Edit freely as families change.
 */
export function detectReasoningStyle(model: ORModel | undefined): ReasoningStyle {
  const id = (model?.id ?? '').toLowerCase();
  const std: ReasoningStyle['efforts'] = ['low', 'medium', 'high'];
  const src = 'Levels come from a table in Quire keyed on the model family, not from OpenRouter; OpenRouter maps a level the provider lacks to the nearest one.';
  if (/^openai\/gpt-5\.[1-9]|^openai\/gpt-5-codex|^openai\/codex/.test(id)) return { defaultMode: 'effort', canDisable: true, returnsTrace: true, efforts: ['none', 'minimal', 'low', 'medium', 'high', 'xhigh'], defaultBudget: 8000, note: `GPT-5.1-class models take the full effort scale including none and xhigh. ${src}` };
  if (/^openai\/gpt-5/.test(id)) return { defaultMode: 'effort', canDisable: false, returnsTrace: true, efforts: ['minimal', 'low', 'medium', 'high'], defaultBudget: 8000, note: `GPT-5 takes minimal to high and always reasons. ${src}` };
  if (/^openai\/(o[1-9])/.test(id)) return { defaultMode: 'effort', canDisable: false, returnsTrace: true, efforts: std, defaultBudget: 8000, note: `o-series models take low, medium or high and always reason. ${src}` };
  if (/^anthropic\/claude-(3\.7|4|opus-4|sonnet-4|haiku-4)/.test(id)) return { defaultMode: 'budget', canDisable: true, returnsTrace: true, efforts: std, defaultBudget: 8000, note: `Claude takes a thinking-token budget; effort is converted to a budget by OpenRouter. ${src}` };
  if (/^google\/gemini-(2\.5|3)/.test(id)) return { defaultMode: 'budget', canDisable: !/pro/.test(id), returnsTrace: true, efforts: std, defaultBudget: 8000, note: `Gemini takes a thinking budget; Pro models cannot turn thinking off. ${src}` };
  if (/^deepseek\/deepseek-v4|^deepseek\/deepseek-v3\.[1-9]/.test(id)) return { defaultMode: 'effort', canDisable: true, returnsTrace: true, efforts: std, defaultBudget: 8000, note: `DeepSeek V3.1+ and V4 are hybrid: thinking can be turned off, and the trace is returned. ${src}` };
  if (/^deepseek\/deepseek-r1/.test(id)) return { defaultMode: 'effort', canDisable: false, returnsTrace: true, efforts: ['high'], defaultBudget: 0, note: `R1 always reasons at one level; you can only hide the trace. ${src}` };
  if (/^x-ai\/grok/.test(id)) return { defaultMode: 'effort', canDisable: false, returnsTrace: true, efforts: ['low', 'high'], defaultBudget: 0, note: `Grok distinguishes low and high only. ${src}` };
  if (/^qwen\/qwen3|^moonshotai\/kimi|^z-ai\/glm|^minimax/.test(id)) return { defaultMode: 'budget', canDisable: true, returnsTrace: true, efforts: std, defaultBudget: 4096, note: src };
  return { defaultMode: 'effort', canDisable: true, returnsTrace: true, efforts: ['minimal', 'low', 'medium', 'high', 'xhigh'], defaultBudget: 4096, note: `This family is not in Quire's table, so the whole unified scale is offered. ${src}` };
}

/** Merge global settings with a chat's overrides. Overrides win only where defined. */
export function resolveSettings(global: GenerationSettings, override?: Partial<GenerationSettings> | null): GenerationSettings {
  const out: GenerationSettings = { ...DEFAULT_GENERATION, ...global };
  if (!override) return out;
  for (const k of Object.keys(override) as Array<keyof GenerationSettings>) {
    const v = override[k];
    if (v === undefined) continue;
    (out as unknown as Record<string, unknown>)[k] = v;
  }
  return out;
}

export function reasoningPayload(r: ReasoningSettings | undefined, model: ORModel | undefined): Record<string, unknown> | undefined {
  if (!r || !supportsReasoning(model)) return undefined;
  const style = detectReasoningStyle(model);
  if (r.mode === 'off') return style.canDisable ? { enabled: false } : r.exclude ? { exclude: true } : undefined;
  const p: Record<string, unknown> = {};
  if (r.mode === 'effort') p.effort = r.effort ?? 'medium';
  else if (r.mode === 'budget') p.max_tokens = Math.max(1, Math.round(r.maxTokens ?? style.defaultBudget));
  if (r.exclude) p.exclude = true;
  return p;
}

/** Build the OpenRouter request body, sending only parameters the model supports. */
export function buildRequestBody(opts: {
  modelId: string;
  model: ORModel | undefined;
  settings: GenerationSettings;
  messages: unknown[];
}): Record<string, unknown> {
  const { modelId, model, settings: s, messages } = opts;
  const body: Record<string, unknown> = { model: modelId, messages, usage: { include: true } };
  for (const d of PARAM_DEFS) {
    if (!supports(model, d.api)) continue;
    const v = s[d.key];
    if (v === undefined || v === null) continue;
    if (d.key === 'stop') { const arr = (v as string[]).filter(Boolean); if (arr.length) body.stop = arr.slice(0, 4); continue; }
    if (typeof v === 'number' && Number.isFinite(v)) {
      let val = v;
      if (d.key === 'maxTokens' && model?.topProvider.maxCompletionTokens) val = Math.min(val, model.topProvider.maxCompletionTokens);
      body[d.api] = val;
    }
  }
  const reasoning = reasoningPayload(s.reasoning, model);
  if (reasoning) body.reasoning = reasoning;
  if (s.provider) {
    const p: Record<string, unknown> = {};
    if (s.provider.sort) p.sort = s.provider.sort;
    if (s.provider.order?.length) p.order = s.provider.order;
    if (s.provider.ignore?.length) p.ignore = s.provider.ignore;
    p.allow_fallbacks = s.provider.allowFallbacks;
    p.require_parameters = s.provider.requireParameters;
    if (s.provider.denyDataCollection) p.data_collection = 'deny';
    body.provider = p;
  }
  if (s.webSearch?.enabled) body.plugins = [{ id: 'web', max_results: Math.max(1, Math.min(10, s.webSearch.maxResults || 5)) }];
  if (s.transforms?.length) body.transforms = s.transforms;
  if (s.fallbackModels?.length) body.models = [modelId, ...s.fallbackModels.filter((m) => m !== modelId)];
  return body;
}

// ---- Sampling presets ----
export interface SamplingPreset { name: string; values: Partial<GenerationSettings> }
export const SAMPLING_PRESETS: SamplingPreset[] = [
  { name: 'Precise', values: { temperature: 0.2, topP: 0.9, frequencyPenalty: 0, presencePenalty: 0 } },
  { name: 'Balanced', values: { temperature: 0.7, topP: 1, frequencyPenalty: 0, presencePenalty: 0 } },
  { name: 'Creative', values: { temperature: 1.1, topP: 1, frequencyPenalty: 0.2, presencePenalty: 0.3 } },
];

export function matchesPreset(s: GenerationSettings, p: SamplingPreset): boolean {
  return (Object.keys(p.values) as Array<keyof GenerationSettings>).every((k) => {
    const want = p.values[k];
    const have = s[k];
    if (typeof want === 'number') return typeof have === 'number' ? Math.abs(have - want) < 1e-6 : want === (PARAM_BY_KEY[k as ParamKey]?.defaultValue ?? undefined);
    return want === have;
  });
}

export function unsupportedParams(model: ORModel | undefined): ParamDef[] {
  if (!model) return [];
  return PARAM_DEFS.filter((d) => !supports(model, d.api));
}
