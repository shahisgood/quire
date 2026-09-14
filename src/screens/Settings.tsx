import { useEffect, useRef, useState } from 'react';
import type { Preset } from '@/lib/types';
import { db, uid } from '@/lib/db';
import { clearCaches, exportAll, importBundle, shareFile, storageEstimate, wipeEverything } from '@/lib/data';
import { fmtBytes, fmtUsd, isIOS, isStandalone, shortModelName } from '@/lib/format';
import { beginOAuth, fetchKeyMeta } from '@/lib/openrouter';
import { clientConfig, useApp } from '@/store/app';
import { useChats } from '@/store/chats';
import { useModels } from '@/store/models';
import { useUI } from '@/store/ui';
import { GenerationEditor } from '@/components/Params';
import { Button, Hint, IconButton, Icons, Row, SectionTitle, Segmented, Sheet, Switch } from '@/components/ui';

declare const __BUILD_HASH__: string;
declare const __BUILD_TIME__: string;

const SECTIONS: Array<{ id: string; title: string; sub: string }> = [
  { id: 'connection', title: 'Connection', sub: 'API key, credits, usage' },
  { id: 'generation', title: 'Default model and generation', sub: 'Applied to new chats' },
  { id: 'prompts', title: 'Prompts and personas', sub: 'Global system prompt, presets' },
  { id: 'memory', title: 'Memory', sub: 'What Quire remembers about you' },
  { id: 'appearance', title: 'Appearance', sub: 'Theme, type, density' },
  { id: 'data', title: 'Data', sub: 'Storage, backup, import' },
  { id: 'about', title: 'About', sub: 'Version and updates' },
];

export function SettingsScreen({ section }: { section?: string }) {
  const navigate = useUI((s) => s.navigate);
  const apiKey = useApp((s) => s.settings.apiKey);
  const title = SECTIONS.find((s) => s.id === section)?.title ?? 'Settings';
  return (
    <div className="flex h-full min-h-0 flex-1 flex-col">
      <header className="chrome safe-t hairline flex items-center gap-1 px-2" style={{ minHeight: 'calc(48px + env(safe-area-inset-top))' }}>
        <IconButton icon={Icons.back} label="Back" onClick={() => (section ? navigate({ name: 'settings' }) : navigate({ name: 'chat', chatId: null }))} />
        <div className="flex-1 px-2 text-md font-semibold">{title}</div>
      </header>
      <div className="scroll min-h-0 flex-1 pb-12">
        {!section && (
          <>
            {!apiKey && <Hint>No API key yet. Start with Connection.</Hint>}
            {SECTIONS.map((s) => <Row key={s.id} onClick={() => navigate({ name: 'settings', section: s.id })} sub={s.sub} right={<Icons.chevronRight size={16} />}>{s.title}</Row>)}
          </>
        )}
        {section === 'connection' && <Connection />}
        {section === 'generation' && <Generation />}
        {section === 'prompts' && <Prompts />}
        {section === 'memory' && <MemorySettings />}
        {section === 'appearance' && <Appearance />}
        {section === 'data' && <Data />}
        {section === 'about' && <About />}
      </div>
    </div>
  );
}

function Connection() {
  const { settings, setApiKey, setKeyMeta, update } = useApp();
  const toast = useUI((s) => s.toast);
  const [draft, setDraft] = useState('');
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const meta = settings.keyMeta;
  const refresh = async () => {
    if (!settings.apiKey) return;
    setBusy(true); setErr(null);
    try { setKeyMeta(await fetchKeyMeta(clientConfig())); } catch (e) { setErr(e instanceof Error ? e.message : 'Could not read key'); } finally { setBusy(false); }
  };
  useEffect(() => { if (settings.apiKey && (!meta || Date.now() - meta.fetchedAt > 60_000)) void refresh(); }, [settings.apiKey]); // eslint-disable-line react-hooks/exhaustive-deps
  const save = () => { const k = draft.trim(); if (!k) return; setApiKey(k); setDraft(''); toast('Key saved on this device'); };
  return (
    <>
      <SectionTitle>Key</SectionTitle>
      {settings.apiKey ? (
        <>
          <Row sub={meta ? `${meta.label}${meta.isFreeTier ? ' · free tier' : ''}` : err ? err : busy ? 'Checking' : 'Saved'} right={<IconButton icon={Icons.refresh} label="Refresh" onClick={() => void refresh()} className={busy ? 'pulse' : ''} />}>
            <span className="font-mono">{show ? settings.apiKey : `${settings.apiKey.slice(0, 12)}…${settings.apiKey.slice(-4)}`}</span>
          </Row>
          {meta && (
            <>
              <Row sub="Spent on this key so far">{fmtUsd(meta.usage)} used</Row>
              <Row sub={meta.limit == null ? 'No limit set on this key' : 'Credit limit on this key'}>{meta.limit == null ? 'Unlimited' : `${fmtUsd(meta.limitRemaining)} of ${fmtUsd(meta.limit)} left`}</Row>
              {meta.rateLimit && <Row sub="Rate limit">{meta.rateLimit.requests} requests per {meta.rateLimit.interval}</Row>}
            </>
          )}
          <div className="flex gap-2 px-4 py-2">
            <Button kind="outline" onClick={() => setShow((v) => !v)}>{show ? 'Hide key' : 'Show key'}</Button>
            <Button kind="outline" onClick={() => { setApiKey(null); toast('Key removed'); }} className="text-accent">Remove key</Button>
          </div>
        </>
      ) : (
        <Hint>Quire has no key. Paste one from openrouter.ai/keys, or sign in and let OpenRouter create one.</Hint>
      )}
      <SectionTitle>{settings.apiKey ? 'Replace key' : 'Add key'}</SectionTitle>
      <div className="px-4">
        <input value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="sk-or-v1-…" type={show ? 'text' : 'password'} autoCapitalize="off" autoCorrect="off" spellCheck={false} className="w-full rounded-lg border border-rule bg-raised px-3 py-2.5 font-mono text-body" aria-label="OpenRouter API key" onKeyDown={(e) => { if (e.key === 'Enter') save(); }} />
        <div className="mt-2 flex gap-2">
          <Button kind="primary" onClick={save} disabled={!draft.trim()}>Save key</Button>
          <Button kind="outline" onClick={() => void beginOAuth()}>Sign in with OpenRouter</Button>
        </div>
      </div>
      <Hint>Sign-in uses OpenRouter's PKCE flow: you approve on openrouter.ai and come back with a key. From the home-screen app the round trip may open Safari; if the key does not appear afterwards, paste it manually.</Hint>
      <Hint>The key is stored on this device in browser storage, unencrypted, and is only ever sent to openrouter.ai.</Hint>
      <SectionTitle>Advanced</SectionTitle>
      <div className="px-4">
        <input value={settings.proxyBaseUrl ?? ''} onChange={(e) => update({ proxyBaseUrl: e.target.value.trim() || undefined })} placeholder="https://openrouter.ai/api/v1" autoCapitalize="off" autoCorrect="off" spellCheck={false} className="w-full rounded-lg border border-rule bg-raised px-3 py-2.5 font-mono text-sm" aria-label="API base URL" />
      </div>
      <Hint>Only change this if direct browser calls to OpenRouter stop working and you run your own pass-through proxy. Leave empty for the default.</Hint>
      <SectionTitle>Your own provider keys</SectionTitle>
      <Hint>OpenRouter can route requests through API keys you hold with OpenAI, Anthropic, Google and others, charging a small fee instead of full inference cost. That is configured in your OpenRouter account, not here; Quire simply works with whatever routing your account uses. <a className="text-accent underline" href="https://openrouter.ai/settings/integrations" target="_blank" rel="noopener noreferrer">Manage on openrouter.ai</a>.</Hint>
    </>
  );
}

function Generation() {
  const { settings, update, updateGlobal } = useApp();
  const model = useModels((s) => s.byId.get(settings.defaultModelId));
  const openSheet = useUI((s) => s.openSheet);
  return (
    <>
      <SectionTitle>Default model</SectionTitle>
      <Row onClick={() => openSheet({ kind: 'picker', title: 'Default model', onPick: (id) => update({ defaultModelId: id }) })} sub={settings.defaultModelId} right={<Icons.chevronRight size={16} />}>{shortModelName(model, settings.defaultModelId)}</Row>
      {!model && <Hint>This model id is not in the cached catalogue. It will still be sent as-is; pick another if requests fail.</Hint>}
      <SectionTitle>Generation defaults</SectionTitle>
      <Hint>Controls shown are the ones this model supports. Values for hidden controls are kept and used when you switch to a model that supports them.</Hint>
      <GenerationEditor key={settings.defaultModelId} model={model} value={settings.globalSettings} onChange={updateGlobal} />
    </>
  );
}

function Prompts() {
  const { settings, update } = useApp();
  const { presets, savePreset, deletePreset } = useChats();
  const { openDialog, openSheet, toast } = useUI();
  const [editing, setEditing] = useState<Preset | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const exp = () => shareFile('quire-personas.json', JSON.stringify({ app: 'quire-presets', presets }), 'application/json');
  const imp = async (f: File) => {
    try {
      const j = JSON.parse(await f.text()) as { presets?: Preset[] };
      if (!Array.isArray(j.presets)) throw new Error('Not a personas file');
      for (const p of j.presets) await savePreset({ ...p, id: presets.some((x) => x.id === p.id) ? uid() : p.id, createdAt: p.createdAt ?? Date.now() });
      toast(`Imported ${j.presets.length} personas`);
    } catch (e) { toast(e instanceof Error ? e.message : 'Import failed'); }
  };
  return (
    <>
      <SectionTitle>Global system prompt</SectionTitle>
      <div className="px-4"><textarea value={settings.globalSystemPrompt} onChange={(e) => update({ globalSystemPrompt: e.target.value })} rows={5} placeholder="Sent at the start of every chat that has no persona or override." className="w-full rounded-lg border border-rule bg-raised px-3 py-2 text-body leading-relaxed" /></div>
      <SectionTitle right={<div className="flex gap-3"><button type="button" className="text-sm text-accent" onClick={() => fileRef.current?.click()}>Import</button><button type="button" className="text-sm text-accent" onClick={() => void exp()} disabled={!presets.length}>Export</button></div>}>Personas</SectionTitle>
      <input ref={fileRef} type="file" accept="application/json" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void imp(f); e.target.value = ''; }} />
      {presets.map((p) => <Row key={p.id} onClick={() => setEditing(p)} sub={p.systemPrompt.slice(0, 100) || 'No prompt'} right={<Icons.chevronRight size={16} />}>{p.icon ? `${p.icon} ` : ''}{p.name}</Row>)}
      {!presets.length && <Hint>A persona is a saved system prompt, optionally with its own model and settings. Hold the new-chat button to start from one.</Hint>}
      <div className="px-4 py-2"><Button kind="outline" onClick={() => setEditing({ id: uid(), name: '', systemPrompt: '', settings: {}, createdAt: Date.now() })}>New persona</Button></div>
      {editing && <PresetEditor preset={editing} onClose={() => setEditing(null)} onSave={async (p) => { await savePreset(p); setEditing(null); }} onDelete={() => openDialog({ title: `Delete ${editing.name || 'persona'}?`, confirmLabel: 'Delete', destructive: true, onConfirm: async () => { await deletePreset(editing.id); setEditing(null); } })} onDuplicate={async () => { await savePreset({ ...editing, id: uid(), name: `${editing.name} (copy)`, createdAt: Date.now() }); setEditing(null); }} onPickModel={(cb) => openSheet({ kind: 'picker', title: 'Persona model', onPick: cb })} />}
    </>
  );
}

function PresetEditor({ preset, onClose, onSave, onDelete, onDuplicate, onPickModel }: { preset: Preset; onClose: () => void; onSave: (p: Preset) => Promise<void>; onDelete: () => void; onDuplicate: () => Promise<void>; onPickModel: (cb: (id: string) => void) => void }) {
  const [p, setP] = useState(preset);
  const model = useModels((s) => (p.modelId ? s.byId.get(p.modelId) : undefined));
  const isNew = !useChats.getState().presets.some((x) => x.id === preset.id);
  return (
    <Sheet open onClose={onClose} tall title={isNew ? 'New persona' : 'Edit persona'} right={<button type="button" className="min-h-[36px] px-2 text-body text-accent" onClick={() => void onSave(p)} disabled={!p.name.trim()}>Save</button>}>
      <div className="space-y-3 px-4 pt-1">
        <div className="flex gap-2">
          <input value={p.icon ?? ''} onChange={(e) => setP({ ...p, icon: e.target.value.slice(0, 2) })} placeholder="◦" className="w-14 rounded-lg border border-rule bg-raised px-2 py-2.5 text-center text-body" aria-label="Icon" />
          <input value={p.name} onChange={(e) => setP({ ...p, name: e.target.value })} placeholder="Name" className="flex-1 rounded-lg border border-rule bg-raised px-3 py-2.5 text-body" aria-label="Name" />
        </div>
        <textarea value={p.systemPrompt} onChange={(e) => setP({ ...p, systemPrompt: e.target.value })} rows={7} placeholder="System prompt" className="w-full rounded-lg border border-rule bg-raised px-3 py-2 text-body leading-relaxed" />
      </div>
      <Row onClick={() => onPickModel((id) => setP((x) => ({ ...x, modelId: id })))} sub={p.modelId ?? 'Uses the chat’s model'} right={p.modelId ? <button type="button" className="text-sm" onClick={(e) => { e.stopPropagation(); setP({ ...p, modelId: undefined }); }}>Clear</button> : <Icons.chevronRight size={16} />}>Pinned model: {p.modelId ? shortModelName(model, p.modelId) : 'None'}</Row>
      <SectionTitle>Settings this persona sets</SectionTitle>
      <Hint>Only values you change here are stored with the persona; everything else inherits from the global defaults.</Hint>
      <GenerationEditor model={model} value={{ ...useApp.getState().settings.globalSettings, ...p.settings }} overrides={p.settings} onChange={(patch) => setP({ ...p, settings: { ...p.settings, ...patch } })} onClearOverride={(k) => { const s = { ...p.settings }; delete s[k]; setP({ ...p, settings: s }); }} compact />
      {!isNew && <div className="flex gap-2 px-4 pb-6"><Button kind="outline" onClick={() => void onDuplicate()}>Duplicate</Button><Button kind="outline" onClick={onDelete} className="text-accent">Delete</Button></div>}
    </Sheet>
  );
}

function MemorySettings() {
  const { settings, updateMemory } = useApp();
  const memory = useChats((s) => s.memory);
  const model = useModels((s) => s.byId.get(settings.memory.extractionModelId));
  const { openSheet, navigate } = useUI();
  return (
    <>
      <Row onClick={() => navigate({ name: 'memory' })} sub={`${memory.length} entries`} right={<Icons.chevronRight size={16} />}>Open memory</Row>
      <Row right={<Switch checked={settings.memory.enabled} onChange={(v) => updateMemory({ enabled: v })} label="Memory" />} sub="Inject remembered facts into new chats">Use memory</Row>
      <Row right={<Switch checked={settings.memory.autoExtract} onChange={(v) => updateMemory({ autoExtract: v })} label="Auto extract" />} sub="After replies, quietly ask a cheap model to note durable facts you stated">Extract automatically</Row>
      <Row onClick={() => openSheet({ kind: 'picker', title: 'Extraction model', onPick: (id) => updateMemory({ extractionModelId: id }) })} sub={settings.memory.extractionModelId} right={<Icons.chevronRight size={16} />}>Extraction model: {shortModelName(model, settings.memory.extractionModelId)}</Row>
      {!model && <Hint>This model is not in the cached catalogue. Extraction and titles will fail until you pick one that exists.</Hint>}
      <Row sub="Characters of memory injected per request" right={<input inputMode="numeric" value={settings.memory.maxInjectedChars} onChange={(e) => { const n = Number(e.target.value); if (Number.isFinite(n)) updateMemory({ maxInjectedChars: Math.max(200, Math.min(20000, n)) }); }} className="num w-[88px] rounded-md border border-rule bg-raised px-2 py-1.5 text-right" aria-label="Injection budget" />}>Injection budget</Row>
      <Hint>Extraction runs at most once per three turns or thirty seconds, after the reply is rendered, and never delays the chat. It costs a small call to the extraction model each time.</Hint>
    </>
  );
}

function Appearance() {
  const { settings, updateUI } = useApp();
  const ui = settings.ui;
  const ios = isIOS();
  return (
    <>
      <Row right={<Segmented value={ui.theme} onChange={(v) => updateUI({ theme: v })} options={[{ value: 'dark', label: 'Dark' }, { value: 'light', label: 'Light' }, { value: 'system', label: 'Auto' }]} />}>Theme</Row>
      <Row right={<Segmented value={ui.readingFace} onChange={(v) => updateUI({ readingFace: v })} options={[{ value: 'serif', label: 'Serif' }, { value: 'sans', label: 'Sans' }]} />} sub="Typeface for replies">Reading face</Row>
      <Row right={<Segmented value={ui.density} onChange={(v) => updateUI({ density: v })} options={[{ value: 'comfortable', label: 'Comfortable' }, { value: 'compact', label: 'Compact' }]} />}>Density</Row>
      <div className="px-4 py-2">
        <div className="flex items-center justify-between text-body"><span>Text size</span><span className="num text-sm text-ink2">{Math.round(ui.fontScale * 100)}%</span></div>
        <input type="range" min={0.85} max={1.4} step={0.05} value={ui.fontScale} onChange={(e) => updateUI({ fontScale: Number(e.target.value) })} aria-label="Text size" />
      </div>
      <Row right={<Switch checked={ui.showReasoningByDefault} onChange={(v) => updateUI({ showReasoningByDefault: v })} label="Show reasoning" />} sub="Keep reasoning traces expanded after the answer starts">Show reasoning by default</Row>
      <Row right={<Switch checked={ui.showCosts} onChange={(v) => updateUI({ showCosts: v })} label="Show costs" />} sub="Token counts and cost under replies, in the chat list, and in the status strip">Show costs</Row>
      <Row right={<Switch checked={ui.sendOnEnter} onChange={(v) => updateUI({ sendOnEnter: v })} label="Send on Enter" />} sub="Desktop only. Shift+Enter is the inverse. On a phone, Enter always adds a line.">Send on Enter</Row>
      <Row right={<Switch checked={ui.hapticsEnabled} onChange={(v) => updateUI({ hapticsEnabled: v })} label="Haptics" />} sub={ios ? 'Safari on iOS does not expose haptics to web apps, so this does nothing here.' : 'Not available in this browser.'}>Haptics</Row>
    </>
  );
}

function Data() {
  const { settings, update } = useApp();
  const { openDialog, toast } = useUI();
  const [est, setEst] = useState<{ usage: number; quota: number; persisted: boolean } | null>(null);
  const [counts, setCounts] = useState<{ chats: number; messages: number } | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const [mode, setMode] = useState<'merge' | 'replace'>('merge');
  const [includeKey, setIncludeKey] = useState(false);
  useEffect(() => { void storageEstimate().then(setEst); void Promise.all([db.chats.count(), db.messages.count()]).then(([c, m]) => setCounts({ chats: c, messages: m })); }, []);
  const doImport = async (f: File) => {
    const text = await f.text();
    const go = async () => { try { const r = await importBundle(text, mode); toast(`Imported ${r.chats} chats, ${r.messages} messages, ${r.memory} memory entries`); } catch (e) { toast(e instanceof Error ? e.message : 'Import failed', undefined, 6000); } };
    if (mode === 'replace') openDialog({ title: 'Replace everything?', body: 'Current chats, memory and presets are deleted first.', confirmLabel: 'Replace', destructive: true, typed: 'replace', onConfirm: go }); else await go();
  };
  return (
    <>
      <SectionTitle>Storage</SectionTitle>
      <Row sub={est ? `${fmtBytes(est.usage)} used of about ${fmtBytes(est.quota)}` : 'Measuring'}>{counts ? `${counts.chats} chats, ${counts.messages} messages` : '…'}</Row>
      <Row sub={est?.persisted ? 'The browser has agreed not to evict this data without asking.' : settings.persistRequested === false && counts && counts.chats > 0 ? 'Persistence was not granted. Installed apps are treated better than tabs, but export regularly.' : 'Requested after your first chat.'} right={!est?.persisted && navigator.storage?.persist ? <button type="button" className="text-sm text-accent" onClick={() => navigator.storage.persist().then((ok) => { update({ persistRequested: ok }); void storageEstimate().then(setEst); })}>Request</button> : undefined}>Persistent storage{est?.persisted ? ': granted' : ''}</Row>
      <SectionTitle>Backup</SectionTitle>
      <Row sub={settings.lastExportAt ? `Last export ${new Date(settings.lastExportAt).toLocaleDateString()}` : 'Never exported'} right={<Switch checked={includeKey} onChange={setIncludeKey} label="Include API key" />}>Include API key in export</Row>
      <div className="px-4 py-2"><Button kind="primary" onClick={() => void exportAll(includeKey).then(() => toast('Backup ready'))}>Export everything</Button></div>
      <Hint>{isStandalone() ? 'Opens the share sheet with a JSON file. Save it to Files or iCloud Drive.' : 'Downloads a JSON file with every chat, branch, persona, memory entry and setting.'}</Hint>
      <SectionTitle>Import</SectionTitle>
      <Row right={<Segmented value={mode} onChange={setMode} options={[{ value: 'merge', label: 'Merge' }, { value: 'replace', label: 'Replace' }]} />}>Mode</Row>
      <input ref={fileRef} type="file" accept="application/json,.json" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void doImport(f); e.target.value = ''; }} />
      <div className="px-4 py-2"><Button kind="outline" onClick={() => fileRef.current?.click()}>Choose a backup file</Button></div>
      <SectionTitle>Danger</SectionTitle>
      <Row onClick={() => void clearCaches().then(() => toast('Caches cleared; model list will refetch'))} sub="Service worker cache and the model catalogue. Chats are untouched.">Clear cache</Row>
      <Row onClick={() => openDialog({ title: 'Wipe everything?', body: 'Chats, memory, personas, settings and the API key on this device are erased. Export first if you want any of it.', confirmLabel: 'Wipe', destructive: true, typed: 'wipe', onConfirm: wipeEverything })} className="text-accent">Wipe everything</Row>
    </>
  );
}

function About() {
  const { updateReady, applyUpdate, toast } = useUI();
  const [sw, setSw] = useState('Checking');
  const check = async () => {
    if (!('serviceWorker' in navigator)) { setSw('Not supported'); return; }
    const reg = await navigator.serviceWorker.getRegistration();
    if (!reg) { setSw('Not registered'); return; }
    setSw(reg.active ? `Active${reg.waiting ? ', update waiting' : ''}` : reg.installing ? 'Installing' : 'Registered');
    try { await reg.update(); toast(reg.waiting ? 'Update ready' : 'Up to date'); } catch { toast('Could not check for updates'); }
  };
  useEffect(() => { void check(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
      <Row sub={new Date(__BUILD_TIME__).toLocaleString()}>Quire · build {__BUILD_HASH__}</Row>
      <Row sub={sw} right={updateReady ? <button type="button" className="text-sm text-accent" onClick={() => applyUpdate?.()}>Reload</button> : <button type="button" className="text-sm text-accent" onClick={() => void check()}>Check</button>}>Service worker</Row>
      <Row sub={isStandalone() ? 'Running from the home screen' : 'Running in a browser tab. Add to home screen for the full app.'}>{isStandalone() ? 'Installed' : 'Not installed'}</Row>
      <Hint>Quire talks only to openrouter.ai. There is no server, no analytics, and nothing leaves this device except your requests to OpenRouter.</Hint>
    </>
  );
}
