import { memo, useEffect, useMemo, useRef, useState } from 'react';
import { VList } from 'virtua';
import type { ORModel } from '@/lib/types';
import { fmtContext, fuzzyScore, isFree, perMillion, priceBand, providerOf, type PriceBand } from '@/lib/format';
import { acceptsFiles, acceptsImages, supportsReasoning } from '@/lib/params';
import { useApp } from '@/store/app';
import { useChat } from '@/store/chat';
import { useModels } from '@/store/models';
import { useUI } from '@/store/ui';
import { Button, IconButton, Icons, Row, Sheet, SectionTitle, useLongPress } from './ui';

type Chip = 'vision' | 'files' | 'tools' | 'reasoning' | 'structured' | PriceBand | 'ctx32' | 'ctx200' | 'ctx1m';
const CHIPS: Array<{ id: Chip; label: string }> = [
  { id: 'vision', label: 'Vision' }, { id: 'files', label: 'Files' }, { id: 'tools', label: 'Tools' }, { id: 'reasoning', label: 'Reasoning' }, { id: 'structured', label: 'Structured' },
  { id: 'free', label: 'Free' }, { id: 'cheap', label: 'Cheap' }, { id: 'mid', label: 'Mid' }, { id: 'premium', label: 'Premium' },
  { id: 'ctx32', label: '≥32k' }, { id: 'ctx200', label: '≥200k' }, { id: 'ctx1m', label: '≥1M' },
];

function passes(m: ORModel, chips: Set<Chip>, provider: string | null): boolean {
  if (provider && providerOf(m.id) !== provider) return false;
  for (const c of chips) {
    switch (c) {
      case 'vision': if (!acceptsImages(m)) return false; break;
      case 'files': if (!acceptsFiles(m)) return false; break;
      case 'tools': if (!m.supportedParameters.includes('tools')) return false; break;
      case 'reasoning': if (!supportsReasoning(m)) return false; break;
      case 'structured': if (!m.supportedParameters.includes('structured_outputs') && !m.supportedParameters.includes('response_format')) return false; break;
      case 'free': case 'cheap': case 'mid': case 'premium': if (priceBand(m) !== c) return false; break;
      case 'ctx32': if (m.contextLength < 32_000) return false; break;
      case 'ctx200': if (m.contextLength < 200_000) return false; break;
      case 'ctx1m': if (m.contextLength < 1_000_000) return false; break;
    }
  }
  return true;
}

export function ModelPicker({ open, onClose, onPick, title }: { open: boolean; onClose: () => void; onPick?: (id: string) => void; title?: string }) {
  const models = useModels((s) => s.models);
  const loading = useModels((s) => s.loading);
  const error = useModels((s) => s.error);
  const newIds = useModels((s) => s.newIds);
  const refresh = useModels((s) => s.refresh);
  const ack = useModels((s) => s.acknowledgeNew);
  const favs = useApp((s) => s.settings.favouriteModelIds);
  const recents = useApp((s) => s.settings.recentModelIds);
  const current = useChat((s) => s.chat?.modelId);
  const setModel = useChat((s) => s.setModel);
  const openSheet = useUI((s) => s.openSheet);
  const [q, setQ] = useState('');
  const [chips, setChips] = useState<Set<Chip>>(new Set());
  const [provider, setProvider] = useState<string | null>(null);
  const [onlyNew, setOnlyNew] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { if (open) { setQ(''); setOnlyNew(false); setTimeout(() => input.current?.focus(), 80); } }, [open]);

  const providers = useMemo(() => Array.from(new Set(models.map((m) => providerOf(m.id)))).sort(), [models]);
  const newSet = useMemo(() => new Set(newIds), [newIds]);
  const filtered = useMemo(() => {
    let list = models.filter((m) => passes(m, chips, provider) && (!onlyNew || newSet.has(m.id)));
    if (q.trim()) {
      const scored = list.map((m) => ({ m, s: Math.max(fuzzyScore(q, m.id) * 1.2, fuzzyScore(q, m.name) * 1.1, fuzzyScore(q, m.description.slice(0, 200)) * 0.5) })).filter((x) => x.s > 0);
      scored.sort((a, b) => b.s - a.s);
      list = scored.map((x) => x.m);
    }
    return list;
  }, [models, chips, provider, q, onlyNew, newSet]);

  const byId = useModels((s) => s.byId);
  const sections = useMemo(() => {
    if (q.trim() || chips.size || provider || onlyNew) return [{ title: `${filtered.length} models`, items: filtered }];
    const rec = recents.map((id) => byId.get(id)).filter((m): m is ORModel => Boolean(m));
    const fav = favs.map((id) => byId.get(id)).filter((m): m is ORModel => Boolean(m) && !recents.includes(m!.id));
    const rest = filtered.filter((m) => !recents.includes(m.id) && !favs.includes(m.id));
    const out: Array<{ title: string; items: ORModel[] }> = [];
    if (rec.length) out.push({ title: 'Recent', items: rec });
    if (fav.length) out.push({ title: 'Favourites', items: fav });
    out.push({ title: `All models (${rest.length})`, items: rest });
    return out;
  }, [q, chips, provider, onlyNew, filtered, recents, favs, byId]);

  const rows = useMemo(() => sections.flatMap((s) => [{ kind: 'h' as const, title: s.title }, ...s.items.map((m) => ({ kind: 'm' as const, m }))]), [sections]);
  const pick = (id: string) => { onClose(); if (onPick) onPick(id); else void setModel(id); };
  const toggleChip = (c: Chip) => setChips((s) => { const n = new Set(s); if (n.has(c)) n.delete(c); else { if (['free', 'cheap', 'mid', 'premium'].includes(c)) for (const x of ['free', 'cheap', 'mid', 'premium'] as Chip[]) n.delete(x); if (c.startsWith('ctx')) for (const x of ['ctx32', 'ctx200', 'ctx1m'] as Chip[]) n.delete(x); n.add(c); } return n; });

  return (
    <Sheet open={open} onClose={onClose} tall title={title ?? 'Model'} right={<IconButton icon={Icons.refresh} label="Refresh models" onClick={() => void refresh(true)} className={loading ? 'pulse' : ''} />}>
      <div className="px-3 pb-2">
        <div className="flex items-center gap-2 rounded-lg border border-rule bg-raised px-3">
          <Icons.search size={16} className="text-ink2" />
          <input ref={input} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search id, name, or description" className="min-h-[44px] flex-1" autoCapitalize="off" autoCorrect="off" spellCheck={false} aria-label="Search models" />
          {q && <IconButton icon={Icons.x} label="Clear" onClick={() => setQ('')} size={16} className="!min-h-8 !min-w-8" />}
        </div>
        <div className="scroll -mx-3 mt-2 flex gap-1.5 overflow-x-auto px-3 pb-1" style={{ scrollbarWidth: 'none' }}>
          {newIds.length > 0 && <ChipBtn active={onlyNew} onClick={() => { setOnlyNew((v) => !v); if (!onlyNew) ack(); }} accent>{newIds.length} new</ChipBtn>}
          {CHIPS.map((c) => <ChipBtn key={c.id} active={chips.has(c.id)} onClick={() => toggleChip(c.id)}>{c.label}</ChipBtn>)}
          <select value={provider ?? ''} onChange={(e) => setProvider(e.target.value || null)} className={`min-h-[32px] shrink-0 rounded-full border px-3 text-sm ${provider ? 'border-ink text-ink' : 'border-rule text-ink2'}`} aria-label="Provider">
            <option value="">Provider</option>
            {providers.map((p) => <option key={p} value={p}>{p}</option>)}
          </select>
        </div>
      </div>
      {error && !models.length && <div className="px-4 py-6 text-body text-ink2">Could not load the model list: {error}. <button type="button" className="text-accent" onClick={() => void refresh(true)}>Try again</button></div>}
      {!error && !models.length && <div className="px-4 py-6 text-body text-ink2">{loading ? 'Loading the model list' : 'No models cached yet. Connect once to fetch the list.'}</div>}
      <VList className="scroll h-full" overscan={6}>
        {rows.map((r) => (r.kind === 'h'
          ? <SectionTitle key={`h:${r.title}`}>{r.title}</SectionTitle>
          : <ModelRow key={r.m.id} m={r.m} current={r.m.id === current} fav={favs.includes(r.m.id)} isNew={newSet.has(r.m.id)} onPick={() => pick(r.m.id)} onLong={() => openSheet({ kind: 'modelCard', modelId: r.m.id })} />))}
        <div className="h-8" />
      </VList>
    </Sheet>
  );
}

function ChipBtn({ active, onClick, children, accent }: { active: boolean; onClick: () => void; children: React.ReactNode; accent?: boolean }) {
  return <button type="button" onClick={onClick} className={`pressable min-h-[32px] shrink-0 rounded-full border px-3 text-sm ${active ? 'border-ink bg-ink text-base' : accent ? 'border-accent text-accent' : 'border-rule text-ink2'}`}>{children}</button>;
}

const ModelRow = memo(function ModelRow({ m, current, fav, isNew, onPick, onLong }: { m: ORModel; current: boolean; fav: boolean; isNew: boolean; onPick: () => void; onLong: () => void }) {
  const lp = useLongPress(onLong);
  const toggleFav = useApp((s) => s.toggleFavourite);
  return (
    <div className={`row-press flex items-center px-2 ${current ? 'bg-raised' : ''}`} {...lp}>
      <button type="button" onClick={() => { if (!lp.didFire()) onPick(); }} className="min-w-0 flex-1 px-2 py-2.5 text-left">
        <div className="flex items-center gap-2">
          <span className={`truncate text-body ${current ? 'text-accent' : 'text-ink'}`}>{m.name}</span>
          {isNew && <span className="shrink-0 text-xs text-accent">new</span>}
        </div>
        <div className="mt-0.5 flex items-center gap-2 text-sm text-ink2">
          <span className="num">{fmtContext(m.contextLength)}</span>
          <span className="num">{isFree(m) ? 'free' : `${perMillion(m.pricing.prompt)} / ${perMillion(m.pricing.completion)}`}</span>
          <span className="inline-flex items-center gap-1">
            {acceptsImages(m) && <Icons.image size={13} />}
            {acceptsFiles(m) && <Icons.file size={13} />}
            {supportsReasoning(m) && <Icons.reasoning size={13} />}
            {m.supportedParameters.includes('tools') && <Icons.tools size={13} />}
          </span>
        </div>
        {m.description && <div className="truncate-1 mt-0.5 text-sm text-ink2">{m.description}</div>}
      </button>
      <IconButton icon={fav ? Icons.starFilled : Icons.star} label={fav ? 'Unfavourite' : 'Favourite'} onClick={(e) => { e.stopPropagation(); toggleFav(m.id); }} accent={fav} size={18} />
    </div>
  );
});

export function ModelCard({ modelId, onClose }: { modelId: string; onClose: () => void }) {
  const m = useModels((s) => s.byId.get(modelId));
  const update = useApp((s) => s.update);
  const defaultId = useApp((s) => s.settings.defaultModelId);
  const toast = useUI((s) => s.toast);
  const setModel = useChat((s) => s.setModel);
  if (!m) return null;
  const pr = m.pricing;
  const line = (k: string, v: string) => <div className="flex justify-between gap-4 py-1 text-sm"><span className="text-ink2">{k}</span><span className="num text-right text-ink">{v}</span></div>;
  return (
    <Sheet open onClose={onClose} tall title={m.name}>
      <div className="px-4">
        <div className="font-mono text-sm text-ink2">{m.id}</div>
        <p className="mt-3 text-body leading-relaxed text-ink">{m.description || 'No description.'}</p>
        <div className="mt-4 flex gap-2">
          <Button kind="primary" onClick={() => { void setModel(m.id); onClose(); }}>Use in this chat</Button>
          <Button kind="outline" onClick={() => { update({ defaultModelId: m.id }); toast('Default model set'); }} disabled={defaultId === m.id}>{defaultId === m.id ? 'Default' : 'Set as default'}</Button>
        </div>
        <SectionTitle>Pricing per million tokens</SectionTitle>
        {line('Prompt', perMillion(pr.prompt))}{line('Completion', perMillion(pr.completion))}
        {Number(pr.internal_reasoning) > 0 && line('Reasoning', perMillion(pr.internal_reasoning))}
        {Number(pr.image) > 0 && line('Per image', `$${Number(pr.image).toFixed(4)}`)}
        {Number(pr.request) > 0 && line('Per request', `$${Number(pr.request).toFixed(4)}`)}
        {Number(pr.web_search) > 0 && line('Web search', `$${Number(pr.web_search).toFixed(4)}`)}
        {Number(pr.input_cache_read) > 0 && line('Cache read', perMillion(pr.input_cache_read))}
        {Number(pr.input_cache_write) > 0 && line('Cache write', perMillion(pr.input_cache_write))}
        <SectionTitle>Limits</SectionTitle>
        {line('Context', `${m.contextLength.toLocaleString()} tokens`)}
        {line('Top provider context', m.topProvider.contextLength ? m.topProvider.contextLength.toLocaleString() : '—')}
        {line('Max completion', m.topProvider.maxCompletionTokens ? m.topProvider.maxCompletionTokens.toLocaleString() : '—')}
        {line('Moderated', m.topProvider.isModerated ? 'Yes' : 'No')}
        {line('Input', m.architecture.inputModalities.join(', '))}
        {line('Output', m.architecture.outputModalities.join(', '))}
        {line('Tokenizer', m.architecture.tokenizer || '—')}
        <SectionTitle>Supported parameters</SectionTitle>
        <div className="flex flex-wrap gap-1.5 pb-8">{m.supportedParameters.map((p) => <span key={p} className="rounded-md border border-rule px-2 py-0.5 font-mono text-xs text-ink2">{p}</span>)}{!m.supportedParameters.length && <span className="text-sm text-ink2">None listed</span>}</div>
      </div>
      <Row onClick={onClose}>Close</Row>
    </Sheet>
  );
}
