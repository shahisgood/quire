import { useMemo, useState, type ReactNode } from 'react';
import type { GenerationSettings, ORModel, ReasoningSettings } from '@/lib/types';
import { PARAM_DEFS, SAMPLING_PRESETS, detectReasoningStyle, matchesPreset, supports, supportsReasoning, unsupportedParams, type ParamDef } from '@/lib/params';
import { clamp, perMillion, shortModelName } from '@/lib/format';
import { useModels } from '@/store/models';
import { useUI } from '@/store/ui';
import { Icons, Segmented, Switch } from './ui';

type Patch = Partial<GenerationSettings>;
const EFFORT_LABEL: Record<NonNullable<ReasoningSettings['effort']>, string> = { none: 'None', minimal: 'Min', low: 'Low', medium: 'Med', high: 'High', xhigh: 'XHigh' };
export interface EditorProps {
  model: ORModel | undefined;
  value: GenerationSettings;
  onChange: (patch: Patch) => void;
  /** Per-chat mode: keys present here are overrides; others are inherited. */
  overrides?: Partial<GenerationSettings>;
  onClearOverride?: (key: keyof GenerationSettings) => void;
  compact?: boolean;
}

function Control({ label, help, children, overridden, onInherit, inline }: { label: string; help: string; children: ReactNode; overridden?: boolean; onInherit?: () => void; inline?: boolean }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="px-4 py-2">
      <div className="flex items-center gap-2">
        <button type="button" onClick={() => setOpen((v) => !v)} className={`flex min-h-[32px] items-center gap-1.5 text-body text-ink ${overridden ? 'dot-override' : ''}`} aria-expanded={open}>
          {label}<Icons.info size={13} className="text-ink2" />
        </button>
        <span className="flex-1" />
        {inline && <div className="flex items-center gap-2">{children}</div>}
        {onInherit && overridden && <button type="button" onClick={onInherit} className="min-h-[32px] px-1 text-sm text-ink2">Inherit</button>}
      </div>
      {open && <p className="pb-1 text-sm leading-snug text-ink2">{help}</p>}
      {!inline && <div className="mt-1">{children}</div>}
    </div>
  );
}

function NumberField({ value, onChange, min, max, step, placeholder, className = '' }: { value: number | undefined; onChange: (v: number | undefined) => void; min?: number; max?: number; step?: number; placeholder?: string; className?: string }) {
  const [text, setText] = useState<string | null>(null);
  const shown = text ?? (value === undefined ? '' : String(value));
  return (
    <input inputMode="decimal" value={shown} placeholder={placeholder ?? 'unset'}
      onChange={(e) => setText(e.target.value)}
      onBlur={() => { if (text === null) return; const n = Number(text); if (text.trim() === '' || !Number.isFinite(n)) onChange(undefined); else onChange(clamp(n, min ?? -Infinity, max ?? Infinity)); setText(null); }}
      className={`num min-h-[36px] w-[92px] rounded-md border border-rule bg-raised px-2 text-right text-body ${className}`} />
  );
}

function ParamControl({ d, value, onChange, model }: { d: ParamDef; value: GenerationSettings; onChange: (p: Patch) => void; model: ORModel | undefined }) {
  const v = value[d.key];
  if (d.control === 'slider') {
    const n = typeof v === 'number' ? v : d.defaultValue ?? 0;
    return (
      <div className="flex items-center gap-3">
        <input type="range" min={d.min} max={d.max} step={d.step} value={n} onChange={(e) => onChange({ [d.key]: Number(e.target.value) })} aria-label={d.label} />
        <NumberField value={typeof v === 'number' ? v : undefined} placeholder={String(d.defaultValue ?? '')} min={d.min} max={d.max} step={d.step} onChange={(x) => onChange({ [d.key]: x })} />
      </div>
    );
  }
  if (d.control === 'number') return <NumberField value={typeof v === 'number' ? v : undefined} placeholder={String(d.defaultValue ?? '')} min={d.min} max={d.max} step={d.step} onChange={(x) => onChange({ [d.key]: x })} />;
  if (d.control === 'seed') return (
    <div className="flex items-center gap-2">
      <NumberField value={typeof v === 'number' ? v : undefined} min={0} step={1} onChange={(x) => onChange({ seed: x === undefined ? undefined : Math.round(x) })} />
      <button type="button" className="tap pressable inline-flex items-center gap-1 rounded-md border border-rule px-2 text-sm text-ink2" onClick={() => onChange({ seed: Math.floor(Math.random() * 2_147_483_647) })}><Icons.dice size={16} />Roll</button>
      {typeof v === 'number' && <button type="button" className="min-h-[36px] px-1 text-sm text-ink2" onClick={() => onChange({ seed: undefined })}>Unset</button>}
    </div>
  );
  if (d.control === 'maxTokens') {
    const cap = model?.topProvider.maxCompletionTokens ?? undefined;
    return (
      <div className="flex items-center gap-2">
        <NumberField value={typeof v === 'number' ? v : undefined} min={1} max={cap} step={1} onChange={(x) => onChange({ maxTokens: x === undefined ? undefined : Math.round(x) })} />
        {cap && <button type="button" className="min-h-[36px] rounded-md border border-rule px-2 text-sm text-ink2" onClick={() => onChange({ maxTokens: cap })}>Max {cap.toLocaleString()}</button>}
        {typeof v === 'number' && <button type="button" className="min-h-[36px] px-1 text-sm text-ink2" onClick={() => onChange({ maxTokens: undefined })}>Unset</button>}
      </div>
    );
  }
  // tags
  const tags = Array.isArray(v) ? (v as string[]) : [];
  return <TagInput tags={tags} onChange={(t) => onChange({ stop: t })} max={4} placeholder="Add a stop sequence" />;
}

export function TagInput({ tags, onChange, max, placeholder }: { tags: string[]; onChange: (t: string[]) => void; max?: number; placeholder?: string }) {
  const [t, setT] = useState('');
  const add = () => { const s = t; if (!s || (max && tags.length >= max)) return; onChange([...tags, s]); setT(''); };
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {tags.map((x, i) => <span key={`${x}${i}`} className="inline-flex items-center gap-1 rounded-md border border-rule bg-raised px-2 py-1 font-mono text-sm">{JSON.stringify(x).slice(1, -1)}<button type="button" aria-label="Remove" onClick={() => onChange(tags.filter((_, j) => j !== i))} className="text-ink2"><Icons.x size={12} /></button></span>)}
      {(!max || tags.length < max) && <input value={t} onChange={(e) => setT(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); add(); } }} onBlur={add} placeholder={placeholder} className="min-h-[36px] min-w-[140px] flex-1 rounded-md border border-rule bg-raised px-2 font-mono text-sm" autoCapitalize="off" autoCorrect="off" />}
    </div>
  );
}

export function GenerationEditor({ model, value, onChange, overrides, onClearOverride, compact }: EditorProps) {
  const isOv = (k: keyof GenerationSettings) => Boolean(overrides && overrides[k] !== undefined);
  const inherit = (k: keyof GenerationSettings) => (onClearOverride ? () => onClearOverride(k) : undefined);
  const r: ReasoningSettings = value.reasoning ?? { mode: 'off', effort: 'medium', exclude: false };
  const style = useMemo(() => detectReasoningStyle(model), [model]);
  const p = value.provider ?? { allowFallbacks: true, requireParameters: true, denyDataCollection: false };
  const setR = (patch: Partial<ReasoningSettings>) => onChange({ reasoning: { ...r, ...patch } });
  const setP = (patch: Partial<NonNullable<GenerationSettings['provider']>>) => onChange({ provider: { ...p, ...patch } });
  const openSheet = useUI((s) => s.openSheet);
  const byId = useModels((s) => s.byId);
  const activePreset = SAMPLING_PRESETS.find((sp) => matchesPreset(value, sp));
  const [showAdv, setShowAdv] = useState(!compact);
  const unsupported = unsupportedParams(model);
  const hasReasoning = supportsReasoning(model);
  const webPrice = model ? Number(model.pricing.web_search) : 0;

  return (
    <div className="pb-4">
      <div className="px-4 pb-1 pt-3">
        <div className="flex flex-wrap items-center gap-1.5">
          {SAMPLING_PRESETS.map((sp) => <button key={sp.name} type="button" onClick={() => onChange(sp.values)} className={`pressable min-h-[32px] rounded-full border px-3 text-sm ${activePreset?.name === sp.name ? 'border-ink bg-ink text-base' : 'border-rule text-ink2'}`}>{sp.name}</button>)}
          {!activePreset && <span className="text-sm text-ink2">Custom</span>}
        </div>
      </div>
      {PARAM_DEFS.filter((d) => supports(model, d.api)).map((d) => (
        <Control key={d.key} label={d.label} help={d.help} overridden={isOv(d.key)} onInherit={inherit(d.key)}>
          <ParamControl d={d} value={value} onChange={onChange} model={model} />
        </Control>
      ))}
      <Control label="Stream" help="Show tokens as they arrive. Off is useful for debugging and for the few models that stream badly." inline overridden={isOv('stream')} onInherit={inherit('stream')}>
        <Switch checked={value.stream} onChange={(v) => onChange({ stream: v })} label="Stream" />
      </Control>

      {hasReasoning && (
        <>
          <Control label="Reasoning" help={`Let the model think before answering. ${style.note ?? ''}`} overridden={isOv('reasoning')} onInherit={inherit('reasoning')}>
            <Segmented value={r.mode} onChange={(m) => setR({ mode: m, effort: r.effort ?? 'medium', maxTokens: r.maxTokens ?? style.defaultBudget })} options={[...(style.canDisable ? [{ value: 'off' as const, label: 'Off' }] : []), { value: 'effort' as const, label: 'Effort' }, { value: 'budget' as const, label: 'Budget' }]} />
            {!style.canDisable && r.mode === 'off' && <p className="mt-1 text-sm text-ink2">This model always reasons. Pick effort or budget; use Hide to keep the trace out of the reply.</p>}
            {r.mode === 'effort' && <div className="mt-2"><Segmented value={r.effort ?? 'medium'} onChange={(e) => setR({ effort: e })} options={style.efforts.map((e) => ({ value: e, label: EFFORT_LABEL[e] }))} /></div>}
            {r.mode === 'budget' && <div className="mt-2 flex items-center gap-2"><NumberField value={r.maxTokens ?? style.defaultBudget} min={1} step={1} onChange={(v) => setR({ maxTokens: v === undefined ? style.defaultBudget : Math.round(v) })} /><span className="text-sm text-ink2">thinking tokens</span></div>}
          </Control>
          <Control label="Hide reasoning" help="Think, but don't return the trace. Reasoning tokens are still billed." inline overridden={isOv('reasoning')}>
            <Switch checked={r.exclude} onChange={(v) => setR({ exclude: v })} label="Hide reasoning" />
          </Control>
        </>
      )}

      <button type="button" onClick={() => setShowAdv((v) => !v)} className="flex min-h-[44px] w-full items-center justify-between px-4 text-body text-ink2" aria-expanded={showAdv}>
        <span>Advanced routing</span>{showAdv ? <Icons.chevronUp size={16} /> : <Icons.chevronDown size={16} />}
      </button>
      {showAdv && (
        <>
          <Control label="Sort providers by" help="Which provider OpenRouter tries first for this model. Unset uses OpenRouter's default balance of price and uptime." overridden={isOv('provider')} onInherit={inherit('provider')}>
            <Segmented value={p.sort ?? 'default'} onChange={(v) => setP({ sort: v === 'default' ? undefined : (v as 'price' | 'throughput' | 'latency') })} options={[{ value: 'default', label: 'Default' }, { value: 'price', label: 'Price' }, { value: 'throughput', label: 'Speed' }, { value: 'latency', label: 'Latency' }]} />
          </Control>
          <Control label="Deny data collection" help="Only route to providers that promise not to train on or retain your prompts. Can exclude cheaper providers." inline overridden={isOv('provider')}>
            <Switch checked={p.denyDataCollection} onChange={(v) => setP({ denyDataCollection: v })} label="Deny data collection" />
          </Control>
          <Control label="Require parameters" help="Only route to providers that honour every sampling parameter you send, instead of silently dropping them." inline overridden={isOv('provider')}>
            <Switch checked={p.requireParameters} onChange={(v) => setP({ requireParameters: v })} label="Require parameters" />
          </Control>
          <Control label="Allow provider fallbacks" help="If the preferred provider fails, try another one for the same model." inline overridden={isOv('provider')}>
            <Switch checked={p.allowFallbacks} onChange={(v) => setP({ allowFallbacks: v })} label="Allow fallbacks" />
          </Control>
          <Control label="Ignore providers" help="Provider slugs OpenRouter must never route this to, e.g. deepinfra." overridden={isOv('provider')}>
            <TagInput tags={p.ignore ?? []} onChange={(t) => setP({ ignore: t })} placeholder="provider slug" />
          </Control>
          <Control label="Fallback models" help="If the model errors or is unavailable, OpenRouter tries these in order." overridden={isOv('fallbackModels')} onInherit={inherit('fallbackModels')}>
            <div className="flex flex-wrap items-center gap-1.5">
              {(value.fallbackModels ?? []).map((id) => <span key={id} className="inline-flex items-center gap-1 rounded-md border border-rule bg-raised px-2 py-1 text-sm">{shortModelName(byId.get(id), id)}<button type="button" aria-label="Remove" onClick={() => onChange({ fallbackModels: (value.fallbackModels ?? []).filter((x) => x !== id) })} className="text-ink2"><Icons.x size={12} /></button></span>)}
              <button type="button" className="min-h-[36px] rounded-md border border-rule px-2 text-sm text-ink2" onClick={() => openSheet({ kind: 'picker', title: 'Add a fallback model', onPick: (id) => onChange({ fallbackModels: Array.from(new Set([...(value.fallbackModels ?? []), id])) }) })}>Add model</button>
            </div>
          </Control>
          <Control label="Web search" help={`Let the model search the web through OpenRouter's plugin. Billed separately${webPrice > 0 ? ` (about $${(webPrice * 1000).toFixed(2)} per thousand results on this model)` : ''}.`} inline overridden={isOv('webSearch')} onInherit={inherit('webSearch')}>
            <Switch checked={Boolean(value.webSearch?.enabled)} onChange={(v) => onChange({ webSearch: { enabled: v, maxResults: value.webSearch?.maxResults ?? 5 } })} label="Web search" />
          </Control>
          {value.webSearch?.enabled && (
            <Control label="Search results" help="How many results to feed the model per request. More is slower and costs more." inline>
              <NumberField value={value.webSearch.maxResults} min={1} max={10} step={1} onChange={(v) => onChange({ webSearch: { enabled: true, maxResults: Math.round(v ?? 5) } })} />
            </Control>
          )}
          <Control label="Trim long chats to fit" help="When the conversation exceeds the model's context, OpenRouter silently removes content from the middle. Turn on only if you would rather lose context than get an error." inline overridden={isOv('transforms')} onInherit={inherit('transforms')}>
            <Switch checked={Boolean(value.transforms?.includes('middle-out'))} onChange={(v) => onChange({ transforms: v ? ['middle-out'] : [] })} label="Trim long chats" />
          </Control>
        </>
      )}

      {unsupported.length > 0 && <UnsupportedList model={model} defs={unsupported} />}
      {!hasReasoning && model && <p className="px-4 pt-2 text-sm text-ink2">{shortModelName(model)} does not list reasoning support, so the reasoning controls are hidden.</p>}
      {model && <p className="px-4 pt-2 text-sm text-ink2">Pricing: {perMillion(model.pricing.prompt)} in, {perMillion(model.pricing.completion)} out, per million tokens.</p>}
    </div>
  );
}

function UnsupportedList({ model, defs }: { model: ORModel | undefined; defs: ParamDef[] }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="px-4 pt-2">
      <button type="button" onClick={() => setOpen((v) => !v)} className="flex min-h-[36px] items-center gap-1 text-sm text-ink2" aria-expanded={open}>
        {defs.length} unsupported for {shortModelName(model)}{open ? <Icons.chevronUp size={14} /> : <Icons.chevronDown size={14} />}
      </button>
      {open && <p className="text-sm text-ink2">{defs.map((d) => d.label).join(', ')}. Stored values are kept but not sent.</p>}
    </div>
  );
}
