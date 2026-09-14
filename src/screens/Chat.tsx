import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Attachment } from '@/lib/types';
import { chatToMarkdown, exportChatJson, exportChatMarkdown, shareFile } from '@/lib/data';
import { fmtTokens, fmtUsd, isTouch, shortModelName } from '@/lib/format';
import { toAttachment } from '@/lib/attach';
import { acceptsFiles, acceptsImages } from '@/lib/params';
import { useApp } from '@/store/app';
import { contextTokens, useChat, useStream } from '@/store/chat';
import { useChats } from '@/store/chats';
import { useModels } from '@/store/models';
import { useUI } from '@/store/ui';
import { MessageList } from '@/components/Messages';
import { Button, Empty, IconButton, Icons, Row, Sheet } from '@/components/ui';

export function ChatScreen({ chatId, jumpTo }: { chatId: string | null; jumpTo?: string | null }) {
  const open = useChat((s) => s.open);
  const chat = useChat((s) => s.chat);
  const path = useChat((s) => s.path);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  useEffect(() => { void open(chatId); }, [chatId, open]);
  const empty = path.length === 0;
  return (
    <div className="flex h-full min-h-0 flex-1 flex-col">
      <Header />
      {empty ? <EmptyChat /> : <MessageList onMenu={setMenuFor} jumpTo={jumpTo} />}
      <StatusStrip />
      <Composer />
      {chat && <MessageMenu id={menuFor} onClose={() => setMenuFor(null)} />}
    </div>
  );
}

function Header() {
  const chat = useChat((s) => s.chat);
  const patchChat = useChat((s) => s.patchChat);
  const navigate = useUI((s) => s.navigate);
  const openDialog = useUI((s) => s.openDialog);
  const wide = useUI((s) => s.wide);
  const [menu, setMenu] = useState(false);
  const rename = () => { if (!chat) return; openDialog({ title: 'Rename chat', input: { initial: chat.title, placeholder: 'Title' }, confirmLabel: 'Rename', onConfirm: (v) => { if (v?.trim()) void patchChat({ title: v.trim(), titleAuto: false }); } }); };
  return (
    <header className="chrome safe-t hairline flex items-center gap-1 px-2" style={{ minHeight: 'calc(48px + env(safe-area-inset-top))' }}>
      {!wide && <IconButton icon={Icons.back} label="All chats" onClick={() => navigate({ name: 'list' })} />}
      {wide && <div className="w-2" />}
      <button type="button" onClick={rename} className="min-w-0 flex-1 truncate px-2 py-2 text-left text-body font-medium text-ink" aria-label="Rename chat">
        {chat?.title ?? 'New chat'}
        {chat && !chat.memoryEnabled && <span className="ml-2 inline-flex items-center align-middle text-ink2" title="Incognito: memory off"><Icons.incognito size={14} /></span>}
      </button>
      <IconButton icon={Icons.plus} label="New chat" onClick={() => navigate({ name: 'chat', chatId: null }, false) } />
      <IconButton icon={Icons.more} label="Chat options" onClick={() => setMenu(true)} />
      <ChatOverflow open={menu} onClose={() => setMenu(false)} />
    </header>
  );
}

function ChatOverflow({ open, onClose }: { open: boolean; onClose: () => void }) {
  const chat = useChat((s) => s.chat);
  const path = useChat((s) => s.path);
  const messages = useChat((s) => s.messages);
  const persisted = useChat((s) => s.persisted);
  const patchChat = useChat((s) => s.patchChat);
  const newChat = useChat((s) => s.newChat);
  const { openSheet, openDialog, toast, navigate } = useUI();
  const chats = useChats();
  if (!chat) return null;
  const thread = path.map((id) => messages[id]).filter((m): m is NonNullable<typeof m> => Boolean(m));
  const act = (fn: () => void) => () => { onClose(); fn(); };
  return (
    <Sheet open={open} onClose={onClose} title="Chat">
      <Row onClick={act(() => openSheet({ kind: 'chatSettings' }))} right={<Icons.chevronRight size={16} />}>Chat settings</Row>
      <Row onClick={act(() => void patchChat({ memoryEnabled: !chat.memoryEnabled }))} sub={chat.memoryEnabled ? 'Facts from this chat are remembered and injected' : 'Incognito: memory is neither read nor written'} right={<span className="text-sm">{chat.memoryEnabled ? 'On' : 'Off'}</span>}>Memory for this chat</Row>
      <Row onClick={act(() => openSheet({ kind: 'folderPick', onPick: (fid) => void patchChat({ folderId: fid ?? undefined }) }))} sub={chats.folders.find((f) => f.id === chat.folderId)?.name ?? 'None'} right={<Icons.chevronRight size={16} />}>Folder</Row>
      <Row onClick={act(() => void patchChat({ pinned: !chat.pinned }))}>{chat.pinned ? 'Unpin' : 'Pin'}</Row>
      <Row onClick={act(() => { void patchChat({ archived: !chat.archived }); toast(chat.archived ? 'Unarchived' : 'Archived'); })}>{chat.archived ? 'Unarchive' : 'Archive'}</Row>
      <Row onClick={act(() => { if (!persisted) { toast('Nothing to export yet'); return; } void exportChatMarkdown(chat, thread); })} disabled={!persisted}>Export as Markdown</Row>
      <Row onClick={act(() => { if (!persisted) { toast('Nothing to export yet'); return; } void exportChatJson(chat.id); })} disabled={!persisted}>Export as JSON</Row>
      <Row onClick={act(async () => { if (!persisted) return; const id = await chats.duplicateChat(chat.id); navigate({ name: 'chat', chatId: id }); })} disabled={!persisted}>Duplicate</Row>
      <Row onClick={act(() => openDialog({ title: 'Delete this chat?', body: 'Every message and branch in it is removed. This cannot be undone.', confirmLabel: 'Delete', destructive: true, onConfirm: async () => { await chats.deleteChats([chat.id]); await newChat(); navigate({ name: 'chat', chatId: null }, true); } }))} className="text-accent">Delete chat</Row>
    </Sheet>
  );
}

function EmptyChat() {
  const chat = useChat((s) => s.chat);
  const model = useModels((s) => (chat ? s.byId.get(chat.modelId) : undefined));
  const hasKey = useApp((s) => Boolean(s.settings.apiKey));
  const navigate = useUI((s) => s.navigate);
  const openSheet = useUI((s) => s.openSheet);
  if (!hasKey) return <Empty title="Quire needs an OpenRouter key." body="It stays on this device and is sent only to openrouter.ai." action={<Button kind="primary" onClick={() => navigate({ name: 'settings', section: 'connection' })}>Add key</Button>} />;
  return <Empty title={`Talking to ${shortModelName(model, chat?.modelId)}.`} body={chat && !chat.memoryEnabled ? 'Incognito. Nothing from this chat is remembered.' : 'Type below, or pick another of the models OpenRouter offers.'} action={<Button kind="outline" onClick={() => openSheet({ kind: 'picker' })}>Change model</Button>} />;
}

function StatusStrip() {
  const chat = useChat((s) => s.chat);
  const messages = useChat((s) => s.messages);
  const path = useChat((s) => s.path);
  const generating = useChat((s) => s.generating);
  const model = useModels((s) => (chat ? s.byId.get(chat.modelId) : undefined));
  const showCosts = useApp((s) => s.settings.ui.showCosts);
  const openSheet = useUI((s) => s.openSheet);
  const streamTokens = useStream((s) => s.completionTokens + s.reasoningTokens);
  const online = useApp((s) => s.online);
  const used = useMemo(() => contextTokens(chat, messages, path) + streamTokens, [chat, messages, path, streamTokens]);
  const max = model?.contextLength || 0;
  const pct = max ? Math.min(100, (used / max) * 100) : 0;
  return (
    <div className="chrome hairline-t flex items-center gap-3 px-3 text-sm text-ink2" style={{ minHeight: 34 }}>
      <button type="button" onClick={() => openSheet({ kind: 'picker' })} className={`min-w-0 max-w-[50%] truncate py-1.5 text-left ${generating ? 'text-accent' : 'text-ink'}`}>{shortModelName(model, chat?.modelId)}</button>
      {!online && <span className="inline-flex items-center gap-1 text-accent"><Icons.wifiOff size={14} />Offline</span>}
      <button type="button" onClick={() => openSheet({ kind: 'chatSettings' })} className="flex min-w-0 flex-1 items-center gap-2 py-1.5" aria-label="Context usage">
        <span className="h-[3px] flex-1 overflow-hidden rounded-full bg-rule"><span className={`block h-full rounded-full ${pct > 85 ? 'bg-accent' : 'bg-ink2'}`} style={{ width: `${pct}%` }} /></span>
        <span className="num shrink-0">{fmtTokens(used)}{max ? ` / ${fmtTokens(max)}` : ''}</span>
      </button>
      {showCosts && chat && <span className="num shrink-0">{fmtUsd(chat.totalCostUsd)}</span>}
    </div>
  );
}

function Composer() {
  const chat = useChat((s) => s.chat);
  const generating = useChat((s) => s.generating);
  const send = useChat((s) => s.send);
  const stop = useChat((s) => s.stop);
  const saveDraft = useChat((s) => s.saveDraft);
  const sendOnEnter = useApp((s) => s.settings.ui.sendOnEnter);
  const online = useApp((s) => s.online);
  const model = useModels((s) => (chat ? s.byId.get(chat.modelId) : undefined));
  const openSheet = useUI((s) => s.openSheet);
  const toast = useUI((s) => s.toast);
  const ref = useRef<HTMLTextAreaElement>(null);
  const [text, setText] = useState('');
  const [att, setAtt] = useState<Attachment[]>([]);
  const touch = useMemo(() => isTouch(), []);
  const chatId = chat?.id;
  useEffect(() => { setText(chat?.draft ?? ''); setAtt([]); }, [chatId]); // eslint-disable-line react-hooks/exhaustive-deps

  const grow = useCallback(() => {
    const el = ref.current; if (!el) return;
    el.style.height = '0px';
    const max = Math.round(window.innerHeight * 0.4);
    el.style.height = `${Math.min(max, el.scrollHeight)}px`;
    el.style.overflowY = el.scrollHeight > max ? 'auto' : 'hidden';
  }, []);
  useEffect(grow, [text, grow]);

  const onChange = (v: string) => { setText(v); saveDraft(v); };
  const doSend = async () => {
    if (generating) { stop(); return; }
    if (!text.trim() && !att.length) return;
    if (!online) { toast('You are offline. The draft is saved; send when you are back.'); return; }
    const t = text; const a = att;
    setText(''); setAtt([]); saveDraft('');
    requestAnimationFrame(grow);
    await send(t, a);
  };
  const onKey = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key !== 'Enter' || touch) return;
    const plain = !e.shiftKey && !e.metaKey && !e.ctrlKey && !e.altKey;
    if ((sendOnEnter && plain) || (!sendOnEnter && (e.metaKey || e.ctrlKey))) { e.preventDefault(); void doSend(); }
  };
  const addFiles = async (files: FileList | File[]) => {
    for (const f of Array.from(files)) {
      try { const a = await toAttachment(f); setAtt((x) => [...x, a]); } catch (e) { toast(e instanceof Error ? e.message : 'Could not attach that'); }
    }
  };
  const onPaste = (e: React.ClipboardEvent) => {
    const files = Array.from(e.clipboardData.files ?? []).filter((f) => (acceptsImages(model) && f.type.startsWith('image/')) || (acceptsFiles(model) && !f.type.startsWith('image/')));
    if (files.length) { e.preventDefault(); void addFiles(files); }
  };
  const canImg = acceptsImages(model);
  const canFile = acceptsFiles(model);
  const canSend = generating || text.trim().length > 0 || att.length > 0;
  return (
    <div className="chrome safe-b hairline-t bg-base px-2 pt-2">
      {att.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-2 px-1">
          {att.map((a) => (
            <span key={a.id} className="relative inline-flex items-center gap-1.5 rounded-md border border-rule bg-raised px-2 py-1 text-sm">
              {a.kind === 'image' ? <img src={a.dataUrl} alt="" className="h-7 w-7 rounded object-cover" /> : <Icons.file size={14} />}
              <span className="max-w-[140px] truncate">{a.name}</span>
              <button type="button" aria-label="Remove" onClick={() => setAtt((x) => x.filter((y) => y.id !== a.id))} className="tap !min-h-7 !min-w-7 text-ink2"><Icons.x size={14} /></button>
            </span>
          ))}
        </div>
      )}
      <div className="flex items-end gap-1">
        {(canImg || canFile) && <AttachButton canImg={canImg} canFile={canFile} onFiles={addFiles} />}
        <IconButton icon={Icons.sliders} label="Quick settings" onClick={() => openSheet({ kind: 'quick' })} />
        <textarea ref={ref} value={text} onChange={(e) => onChange(e.target.value)} onKeyDown={onKey} onPaste={onPaste} rows={1} enterKeyHint={touch ? 'enter' : 'send'} placeholder={chat && !chat.memoryEnabled ? 'Incognito message' : 'Message'} aria-label="Message" autoCapitalize="sentences"
          className="min-h-[44px] flex-1 rounded-xl border border-rule bg-raised px-3 py-[10px] text-body leading-[24px]" />
        <button type="button" aria-label={generating ? 'Stop' : 'Send'} title={generating ? 'Stop' : 'Send'} onClick={() => void doSend()} disabled={!canSend} className={`tap pressable morph inline-flex items-center justify-center rounded-full ${generating ? 'text-accent' : canSend ? 'bg-accent text-onaccent' : 'bg-raised text-ink2'}`} style={{ transition: 'transform var(--t-press) var(--ease-out), background-color var(--t-fast) ease, color var(--t-fast) ease' }}>
          <span className={generating ? 'is-off' : ''}><Icons.send size={20} /></span>
          <span className={generating ? '' : 'is-off'}><Icons.stop size={20} /></span>
        </button>
      </div>
    </div>
  );
}

function AttachButton({ canImg, canFile, onFiles }: { canImg: boolean; canFile: boolean; onFiles: (f: FileList) => void }) {
  const lib = useRef<HTMLInputElement>(null);
  const cam = useRef<HTMLInputElement>(null);
  const file = useRef<HTMLInputElement>(null);
  const [open, setOpen] = useState(false);
  const touch = useMemo(() => isTouch(), []);
  const pick = (r: React.RefObject<HTMLInputElement>) => { setOpen(false); r.current?.click(); };
  const handle = (e: React.ChangeEvent<HTMLInputElement>) => { if (e.target.files?.length) onFiles(e.target.files); e.target.value = ''; };
  return (
    <>
      <IconButton icon={Icons.paperclip} label="Attach" onClick={() => setOpen(true)} />
      <input ref={lib} type="file" accept="image/*" multiple hidden onChange={handle} />
      <input ref={cam} type="file" accept="image/*" capture="environment" hidden onChange={handle} />
      <input ref={file} type="file" accept=".pdf,.txt,.md,.csv,.json,application/pdf,text/*" multiple hidden onChange={handle} />
      <Sheet open={open} onClose={() => setOpen(false)} title="Attach">
        {canImg && <Row onClick={() => pick(lib)} right={<Icons.image size={18} />}>Photo library</Row>}
        {canImg && touch && <Row onClick={() => pick(cam)} right={<Icons.camera size={18} />}>Camera</Row>}
        {canFile && <Row onClick={() => pick(file)} right={<Icons.file size={18} />} sub="PDF and text files. Some models need OpenRouter's file parser, billed separately.">File</Row>}
      </Sheet>
    </>
  );
}

function MessageMenu({ id, onClose }: { id: string | null; onClose: () => void }) {
  const m = useChat((s) => (id ? s.messages[id] : undefined));
  const chat = useChat((s) => s.chat);
  const messages = useChat((s) => s.messages);
  const path = useChat((s) => s.path);
  const generating = useChat((s) => s.generating);
  const { regenerate, editResend, deleteMessage, branchFrom } = useChat();
  const { openDialog, openSheet, toast, navigate } = useUI();
  const model = useModels((s) => (m?.modelId ? s.byId.get(m.modelId) : undefined));
  if (!m || !chat) return null;
  const act = (fn: () => unknown) => () => { onClose(); void fn(); };
  const copy = async (t: string) => { try { await navigator.clipboard.writeText(t); toast('Copied'); } catch { toast('Clipboard is not available here'); } };
  const stripForCopy = (s: string) => s.replace(/```[\s\S]*?\n([\s\S]*?)```/g, '$1').replace(/^#{1,6}\s+/gm, '').replace(/\*\*([^*]+)\*\*/g, '$1').replace(/`([^`]+)`/g, '$1');
  const raw = (title: string, body: string) => openDialog({ title, body: <pre className="scroll max-h-[50vh] whitespace-pre-wrap break-words font-mono text-xs text-ink">{body}</pre>, confirmLabel: 'Copy', cancelLabel: 'Close', onConfirm: () => void copy(body) });
  const u = m.usage;
  return (
    <Sheet open={Boolean(id)} onClose={onClose} title={m.role === 'user' ? 'Your message' : shortModelName(model, m.modelId)}>
      <Row onClick={act(() => copy(m.role === 'user' ? m.content : stripForCopy(m.content)))} right={<Icons.copy size={18} />}>Copy text</Row>
      {m.role === 'assistant' && <Row onClick={act(() => copy(m.content))}>Copy as Markdown</Row>}
      {m.role === 'user' && <Row onClick={act(() => openDialog({ title: 'Edit and resend', body: 'The original stays as a branch.', input: { initial: m.content, multiline: true }, confirmLabel: 'Send', onConfirm: (v) => { if (v?.trim()) void editResend(m.id, v); } }))} disabled={generating} right={<Icons.edit size={18} />}>Edit and resend</Row>}
      {m.role === 'assistant' && <Row onClick={act(() => regenerate(m.id))} disabled={generating} right={<Icons.refresh size={18} />}>Regenerate</Row>}
      {m.role === 'assistant' && <Row onClick={act(() => openSheet({ kind: 'picker', title: 'Regenerate with', onPick: (mid) => void regenerate(m.id, mid) }))} disabled={generating}>Regenerate with a different model</Row>}
      <Row onClick={act(async () => { const nid = await branchFrom(m.id); navigate({ name: 'chat', chatId: nid }); })} right={<Icons.branch size={18} />} sub="Start a new chat from this point">Branch into a new chat</Row>
      <Row onClick={act(() => shareFile(`${chat.title.slice(0, 30)}.md`, chatToMarkdown(chat, path.map((i) => messages[i]!).filter(Boolean)), 'text/markdown'))} right={<Icons.share size={18} />}>Share thread</Row>
      <Row onClick={act(() => raw('Raw text', m.content))}>Show raw</Row>
      {m.role === 'assistant' && <Row onClick={act(() => openDialog({ title: 'Tokens and cost', body: <div className="num space-y-1 text-body"><div>Prompt: {fmtTokens(u?.promptTokens)}</div><div>Completion: {fmtTokens(u?.completionTokens)}</div>{u?.reasoningTokens != null && <div>Reasoning: {fmtTokens(u.reasoningTokens)}</div>}<div>Cost: {fmtUsd(u?.costUsd, { estimate: u?.estimated })}{u?.authoritative ? ' (from OpenRouter)' : u?.estimated ? ' (estimated)' : ' (from the stream)'}</div>{m.generationId && <div className="truncate text-sm text-ink2">gen {m.generationId}</div>}</div>, confirmLabel: 'Close', cancelLabel: 'Copy id', onCancel: () => { if (m.generationId) void copy(m.generationId); }, onConfirm: () => undefined }))}>Tokens and cost</Row>}
      {m.role === 'assistant' && m.requestSnapshot && <Row onClick={act(() => raw('Request sent', m.requestSnapshot ?? ''))} right={<Icons.code size={18} />}>Show the request</Row>}
      <Row onClick={act(() => openDialog({ title: 'Delete message?', body: 'Later messages on this branch are deleted with it.', confirmLabel: 'Delete', destructive: true, onConfirm: () => deleteMessage(m.id) }))} disabled={generating} className="text-accent" right={<Icons.trash size={18} />}>Delete</Row>
      <div className="px-4 pb-2 pt-3 text-sm text-ink2">{new Date(m.createdAt).toLocaleString()}{m.editedFrom ? ' · edited' : ''}</div>
    </Sheet>
  );
}
