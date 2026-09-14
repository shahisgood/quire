import { useState } from 'react';
import type { GenerationSettings } from '@/lib/types';
import { shortModelName } from '@/lib/format';
import { useApp } from '@/store/app';
import { effectiveSettings, useChat } from '@/store/chat';
import { useChats } from '@/store/chats';
import { useModels } from '@/store/models';
import { useUI } from '@/store/ui';
import { ModelCard, ModelPicker } from './ModelPicker';
import { GenerationEditor } from './Params';
import { Button, Icons, Row, SectionTitle, Sheet, Switch } from './ui';

export function SheetHost() {
  const sheet = useUI((s) => s.sheet);
  const close = useUI((s) => s.closeSheet);
  if (!sheet) return null;
  switch (sheet.kind) {
    case 'picker': return <ModelPicker open onClose={close} onPick={sheet.onPick} title={sheet.title} />;
    case 'modelCard': return <ModelCard modelId={sheet.modelId} onClose={close} />;
    case 'chatSettings': return <ChatSettingsSheet onClose={close} />;
    case 'quick': return <ChatSettingsSheet onClose={close} compact />;
    case 'presetPick': return <PresetPickSheet onClose={close} onPick={sheet.onPick} />;
    case 'folderPick': return <FolderPickSheet onClose={close} onPick={sheet.onPick} />;
    case 'custom': return <Sheet open onClose={close} title={sheet.title}>{sheet.render()}</Sheet>;
  }
}

function ChatSettingsSheet({ onClose, compact }: { onClose: () => void; compact?: boolean }) {
  const chat = useChat((s) => s.chat);
  const patchChat = useChat((s) => s.patchChat);
  const presets = useChats((s) => s.presets);
  const model = useModels((s) => (chat ? s.byId.get(chat.modelId) : undefined));
  const openSheet = useUI((s) => s.openSheet);
  const openDialog = useUI((s) => s.openDialog);
  const globalPrompt = useApp((s) => s.settings.globalSystemPrompt);
  const [tick, setTick] = useState(0);
  if (!chat) return null;
  const effective = effectiveSettings(chat);
  const overrides = chat.settingsOverride ?? {};
  const onChange = (patch: Partial<GenerationSettings>) => { void patchChat({ settingsOverride: { ...overrides, ...patch } }); setTick((t) => t + 1); };
  const clear = (k: keyof GenerationSettings) => { const next = { ...overrides }; delete next[k]; void patchChat({ settingsOverride: Object.keys(next).length ? next : undefined }); setTick((t) => t + 1); };
  const preset = presets.find((p) => p.id === chat.systemPromptId);
  const nOv = Object.keys(overrides).length;
  const editPrompt = () => openDialog({ title: 'System prompt for this chat', body: 'Leave empty to use the persona or global prompt.', input: { initial: chat.systemPromptInline ?? '', multiline: true, placeholder: preset?.systemPrompt || globalPrompt || 'You are…' }, confirmLabel: 'Save', onConfirm: (v) => void patchChat({ systemPromptInline: v?.trim() ? v : undefined }) });
  return (
    <Sheet open onClose={onClose} tall={!compact} title={compact ? 'Quick settings' : 'Chat settings'} right={nOv > 0 ? <button type="button" className="min-h-[36px] px-2 text-sm text-accent" onClick={() => { void patchChat({ settingsOverride: undefined }); setTick((t) => t + 1); }}>Reset {nOv}</button> : undefined}>
      <Row onClick={() => openSheet({ kind: 'picker' })} right={<Icons.chevronRight size={16} />} sub={chat.modelId}>{shortModelName(model, chat.modelId)}</Row>
      <Row onClick={() => openSheet({ kind: 'presetPick', onPick: (id) => { void patchChat({ systemPromptId: id ?? undefined, modelId: id ? presets.find((p) => p.id === id)?.modelId ?? chat.modelId : chat.modelId }); setTick((t) => t + 1); } })} right={<Icons.chevronRight size={16} />} sub={preset ? preset.systemPrompt.slice(0, 80) || 'No prompt' : 'Uses the global prompt'}>Persona: {preset?.name ?? 'None'}</Row>
      <Row onClick={editPrompt} right={<Icons.edit size={16} />} sub={chat.systemPromptInline ? chat.systemPromptInline.slice(0, 80) : 'Inherited'}>{chat.systemPromptInline ? <span className="dot-override">System prompt override</span> : 'System prompt override'}</Row>
      <Row right={<Switch checked={chat.memoryEnabled} onChange={(v) => void patchChat({ memoryEnabled: v })} label="Memory" />} sub={chat.memoryEnabled ? 'Reads and writes memory' : 'Incognito: neither reads nor writes memory'}>Memory</Row>
      <SectionTitle right={<span className="text-xs">● = set for this chat</span>}>Generation</SectionTitle>
      <GenerationEditor key={`${chat.modelId}-${tick}`} model={model} value={effective} overrides={overrides} onChange={onChange} onClearOverride={clear} compact={compact} />
      {!compact && <div className="px-4"><Button kind="outline" full onClick={() => { void patchChat({ settingsOverride: undefined, systemPromptInline: undefined }); setTick((t) => t + 1); }} disabled={nOv === 0 && !chat.systemPromptInline}>Reset to defaults</Button></div>}
    </Sheet>
  );
}

function PresetPickSheet({ onClose, onPick }: { onClose: () => void; onPick: (id: string | null) => void }) {
  const presets = useChats((s) => s.presets);
  const navigate = useUI((s) => s.navigate);
  return (
    <Sheet open onClose={onClose} title="Persona">
      <Row onClick={() => { onClose(); onPick(null); }} sub="Global system prompt and defaults">None</Row>
      {presets.map((p) => <Row key={p.id} onClick={() => { onClose(); onPick(p.id); }} sub={p.systemPrompt.slice(0, 90) || 'No prompt'} right={p.modelId ? <span className="text-xs">{shortModelName(undefined, p.modelId)}</span> : undefined}>{p.icon ? `${p.icon} ` : ''}{p.name}</Row>)}
      <Row onClick={() => { onClose(); navigate({ name: 'settings', section: 'prompts' }); }} className="text-accent">Manage personas</Row>
    </Sheet>
  );
}

function FolderPickSheet({ onClose, onPick }: { onClose: () => void; onPick: (id: string | null) => void }) {
  const folders = useChats((s) => s.folders);
  const createFolder = useChats((s) => s.createFolder);
  const openDialog = useUI((s) => s.openDialog);
  return (
    <Sheet open onClose={onClose} title="Folder">
      <Row onClick={() => { onClose(); onPick(null); }}>No folder</Row>
      {folders.map((f) => <Row key={f.id} onClick={() => { onClose(); onPick(f.id); }} right={<Icons.folder size={16} />}>{f.name}</Row>)}
      <Row onClick={() => { onClose(); openDialog({ title: 'New folder', input: { placeholder: 'Name' }, confirmLabel: 'Create', onConfirm: async (v) => { if (v?.trim()) { const f = await createFolder(v.trim()); onPick(f.id); } } }); }} className="text-accent">New folder</Row>
    </Sheet>
  );
}
