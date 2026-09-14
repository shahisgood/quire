import { memo, useEffect, useMemo, useState } from 'react';
import type { Chat } from '@/lib/types';
import { db, dayKey } from '@/lib/db';
import { buildBundle, searchMessages, shareFile, type SearchHit } from '@/lib/data';
import { dayGroup, fmtUsd, relTime, shortModelName } from '@/lib/format';
import { useApp } from '@/store/app';
import { useChat } from '@/store/chat';
import { useChats } from '@/store/chats';
import { useModels } from '@/store/models';
import { useUI } from '@/store/ui';
import { Empty, IconButton, Icons, Row, SectionTitle, Sheet, useLongPress, useSwipe } from '@/components/ui';

export function ChatListScreen() {
  const { chats, folders, loaded } = useChats();
  const navigate = useUI((s) => s.navigate);
  const openSheet = useUI((s) => s.openSheet);
  const newChat = useChat((s) => s.newChat);
  const showCosts = useApp((s) => s.settings.ui.showCosts);
  const [q, setQ] = useState('');
  const [hits, setHits] = useState<SearchHit[] | null>(null);
  const [sel, setSel] = useState<Set<string> | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [dayCost, setDayCost] = useState(0);
  const wide = useUI((s) => s.wide);
  const activeId = useChat((s) => s.chat?.id);

  useEffect(() => {
    const load = () => db.dayCosts.get(dayKey()).then((d) => setDayCost(d?.costUsd ?? 0));
    void load();
    window.addEventListener('quire:cost-changed', load);
    return () => window.removeEventListener('quire:cost-changed', load);
  }, []);
  useEffect(() => {
    if (q.trim().length < 2) { setHits(null); return; }
    let live = true;
    const t = setTimeout(() => { void searchMessages(q).then((h) => { if (live) setHits(h); }); }, 120);
    return () => { live = false; clearTimeout(t); };
  }, [q]);

  const visible = useMemo(() => chats.filter((c) => (showArchived ? c.archived : !c.archived)), [chats, showArchived]);
  const groups = useMemo(() => {
    const pinned = visible.filter((c) => c.pinned && !c.folderId);
    const byFolder = new Map<string, Chat[]>();
    for (const c of visible) if (c.folderId) byFolder.set(c.folderId, [...(byFolder.get(c.folderId) ?? []), c]);
    const rest = visible.filter((c) => !c.pinned && !c.folderId);
    const days = new Map<string, Chat[]>();
    for (const c of rest) { const g = dayGroup(c.updatedAt); days.set(g, [...(days.get(g) ?? []), c]); }
    return { pinned, byFolder, days: (['Today', 'Yesterday', 'This week', 'Earlier'] as const).filter((g) => days.has(g)).map((g) => ({ title: g, items: days.get(g)! })) };
  }, [visible]);

  const open = (id: string) => { if (sel) { setSel((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; }); return; } navigate({ name: 'chat', chatId: id }); };
  const startSelect = (id: string) => setSel(new Set([id]));
  const fabLp = useLongPress(() => openSheet({ kind: 'presetPick', onPick: (pid) => { void newChat({ presetId: pid }); navigate({ name: 'chat', chatId: null }); } }));

  const row = (c: Chat) => <ChatRow key={c.id} chat={c} selected={sel?.has(c.id) ?? null} active={wide && c.id === activeId} onOpen={() => open(c.id)} onLong={() => startSelect(c.id)} showCost={showCosts} />;

  return (
    <div className="relative flex h-full min-h-0 flex-1 flex-col">
      <header className="chrome safe-t hairline flex items-center gap-1 px-2" style={{ minHeight: 'calc(48px + env(safe-area-inset-top))' }}>
        <div className="flex-1 px-2 text-md font-semibold">{sel ? `${sel.size} selected` : 'Chats'}</div>
        {showCosts && !sel && <span className="num px-2 text-sm text-ink2" title="Spent today">{fmtUsd(dayCost)} today</span>}
        {sel ? <IconButton icon={Icons.x} label="Cancel selection" onClick={() => setSel(null)} /> : <>
          <IconButton icon={Icons.memory} label="Memory" onClick={() => navigate({ name: 'memory' })} />
          <IconButton icon={Icons.settings} label="Settings" onClick={() => navigate({ name: 'settings' })} />
        </>}
      </header>
      <div className="px-3 pb-1 pt-2">
        <div className="flex items-center gap-2 rounded-lg border border-rule bg-raised px-3">
          <Icons.search size={16} className="text-ink2" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search every message" className="min-h-[40px] flex-1" aria-label="Search messages" />
          {q && <IconButton icon={Icons.x} label="Clear" onClick={() => setQ('')} size={16} className="!min-h-8 !min-w-8" />}
        </div>
      </div>
      <div className="scroll min-h-0 flex-1 pb-28">
        {hits !== null ? (
          hits.length ? hits.map((h) => <SearchRow key={h.messageId} hit={h} q={q} onOpen={() => navigate({ name: 'chat', chatId: `${h.chatId}#${h.messageId}` })} />) : <div className="px-4 py-8 text-center text-body text-ink2">Nothing in any message matches “{q}”.</div>
        ) : !loaded ? null : visible.length === 0 && !folders.length ? (
          <Empty title={showArchived ? 'No archived chats.' : 'No chats on this device yet.'} body={showArchived ? undefined : 'Start one below. Everything you write stays in this browser until you export it.'} />
        ) : (
          <>
            {folders.map((f) => <FolderSection key={f.id} name={f.name} id={f.id} items={(groups.byFolder.get(f.id) ?? []).map(row)} />)}
            {groups.pinned.length > 0 && <SectionTitle>Pinned</SectionTitle>}
            {groups.pinned.map(row)}
            {groups.days.map((g) => <div key={g.title}><SectionTitle>{g.title}</SectionTitle>{g.items.map(row)}</div>)}
          </>
        )}
        <div className="px-4 pt-6 text-center"><button type="button" className="min-h-[44px] text-sm text-ink2" onClick={() => setShowArchived((v) => !v)}>{showArchived ? 'Show active chats' : `Archived (${chats.filter((c) => c.archived).length})`}</button></div>
      </div>
      {sel ? <BulkBar ids={[...sel]} onDone={() => setSel(null)} /> : (
        <button type="button" {...fabLp} onClick={() => { if (!fabLp.didFire()) { void newChat(); navigate({ name: 'chat', chatId: null }); } }} className="pressable absolute right-5 flex h-14 w-14 items-center justify-center rounded-full bg-ink text-base shadow-[0_8px_24px_rgb(0_0_0/.35)]" style={{ bottom: 'calc(env(safe-area-inset-bottom) + 20px)' }} aria-label="New chat (hold for a persona)">
          <Icons.plus size={24} />
        </button>
      )}
    </div>
  );
}

function FolderSection({ name, id, items }: { name: string; id: string; items: React.ReactNode[] }) {
  const [open, setOpen] = useState(true);
  const { renameFolder, deleteFolder } = useChats();
  const openDialog = useUI((s) => s.openDialog);
  const lp = useLongPress(() => openDialog({ title: 'Rename folder', input: { initial: name }, confirmLabel: 'Rename', cancelLabel: 'Delete folder', onCancel: () => void deleteFolder(id), onConfirm: (v) => { if (v?.trim()) void renameFolder(id, v.trim()); } }));
  return (
    <div>
      <button type="button" {...lp} onClick={() => { if (!lp.didFire()) setOpen((v) => !v); }} className="flex min-h-[44px] w-full items-center gap-2 px-4 pt-3 text-sm text-ink2" aria-expanded={open}>
        <Icons.folder size={14} /><span className="flex-1 text-left">{name}</span><span className="num">{items.length}</span>{open ? <Icons.chevronUp size={14} /> : <Icons.chevronDown size={14} />}
      </button>
      {open && items}
      {open && !items.length && <div className="px-6 pb-2 text-sm text-ink2">Empty. Move chats here from a chat's options.</div>}
    </div>
  );
}

const ChatRow = memo(function ChatRow({ chat, selected, active, onOpen, onLong, showCost }: { chat: Chat; selected: boolean | null; active: boolean; onOpen: () => void; onLong: () => void; showCost: boolean }) {
  const patchChat = useChats((s) => s.patchChat);
  const toast = useUI((s) => s.toast);
  const model = useModels((s) => s.byId.get(chat.modelId));
  const lp = useLongPress(onLong);
  const sw = useSwipe({
    disabled: selected !== null,
    onLeft: () => { void patchChat(chat.id, { archived: !chat.archived }); toast(chat.archived ? 'Unarchived' : 'Archived', { label: 'Undo', onClick: () => void patchChat(chat.id, { archived: chat.archived }) }); },
    onRight: () => { void patchChat(chat.id, { pinned: !chat.pinned }); },
  });
  return (
    <div className="swipe-row" {...sw.bind}>
      <div ref={sw.under} className="swipe-under" style={{ opacity: 0 }}>
        <span className="swipe-label-right">{chat.pinned ? 'Unpin' : 'Pin'}</span>
        <span className="flex-1" />
        <span className="swipe-label-left">{chat.archived ? 'Unarchive' : 'Archive'}</span>
      </div>
      <div ref={sw.face} className={`swipe-face ${active ? 'bg-raised' : ''}`} {...lp}>
        <button type="button" onClick={() => { if (!lp.didFire() && !sw.isDragging()) onOpen(); }} className={`row-press flex w-full items-start gap-3 px-4 py-3 text-left ${selected ? 'bg-raised' : ''}`}>
          {selected !== null && <span className={`mt-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border ${selected ? 'border-accent bg-accent text-onaccent' : 'border-rule'}`}>{selected && <Icons.check size={12} />}</span>}
          <div className="min-w-0 flex-1">
            <div className="flex items-baseline gap-2">
              {chat.pinned && <Icons.pin size={12} className="shrink-0 self-center text-ink2" />}
              <span className="truncate text-body text-ink">{chat.title}</span>
              <span className="num ml-auto shrink-0 text-sm text-ink2">{relTime(chat.updatedAt)}</span>
            </div>
            <div className="truncate-1 mt-0.5 text-sm text-ink2">{chat.lastPreview || (chat.draft ? `Draft: ${chat.draft}` : 'Empty')}</div>
            <div className="mt-1 flex items-center gap-2 text-xs text-ink2">
              <span className="truncate">{shortModelName(model, chat.modelId)}</span>
              {!chat.memoryEnabled && <Icons.incognito size={12} />}
              {showCost && chat.totalCostUsd > 0 && <span className="num ml-auto">{fmtUsd(chat.totalCostUsd)}</span>}
            </div>
          </div>
        </button>
      </div>
    </div>
  );
});

function SearchRow({ hit, q, onOpen }: { hit: SearchHit; q: string; onOpen: () => void }) {
  const i = hit.snippet.toLowerCase().indexOf(q.toLowerCase());
  return (
    <button type="button" onClick={onOpen} className="row-press block w-full px-4 py-3 text-left">
      <div className="flex items-baseline gap-2"><span className="truncate text-body text-ink">{hit.title}</span><span className="num ml-auto text-sm text-ink2">{relTime(hit.createdAt)}</span></div>
      <div className="mt-0.5 text-sm text-ink2">{i >= 0 ? <>{hit.snippet.slice(0, i)}<mark>{hit.snippet.slice(i, i + q.length)}</mark>{hit.snippet.slice(i + q.length)}</> : hit.snippet}</div>
    </button>
  );
}

function BulkBar({ ids, onDone }: { ids: string[]; onDone: () => void }) {
  const { deleteChats, patchChat } = useChats();
  const { openDialog, openSheet, toast } = useUI();
  const [more, setMore] = useState(false);
  const cur = useChat((s) => s.chat?.id);
  const newChat = useChat((s) => s.newChat);
  const del = () => openDialog({ title: `Delete ${ids.length} chat${ids.length > 1 ? 's' : ''}?`, body: 'This cannot be undone.', confirmLabel: 'Delete', destructive: true, onConfirm: async () => { await deleteChats(ids); if (cur && ids.includes(cur)) await newChat(); onDone(); } });
  const move = () => openSheet({ kind: 'folderPick', onPick: async (fid) => { for (const id of ids) await patchChat(id, { folderId: fid ?? undefined }); onDone(); } });
  const exp = async () => { const b = await buildBundle({ includeKey: false, chatIds: ids }); await shareFile(`quire-${ids.length}-chats.json`, JSON.stringify(b), 'application/json'); onDone(); };
  const arch = async () => { for (const id of ids) await patchChat(id, { archived: true }); toast('Archived'); onDone(); };
  return (
    <div className="chrome hairline-t absolute inset-x-0 bottom-0 flex items-center justify-around bg-base px-2 pt-1 safe-b">
      <IconButton icon={Icons.folder} label="Move to folder" onClick={move} />
      <IconButton icon={Icons.archive} label="Archive" onClick={() => void arch()} />
      <IconButton icon={Icons.share} label="Export selected" onClick={() => void exp()} />
      <IconButton icon={Icons.trash} label="Delete" onClick={del} accent />
      <IconButton icon={Icons.more} label="More" onClick={() => setMore(true)} />
      <Sheet open={more} onClose={() => setMore(false)} title={`${ids.length} chats`}>
        <Row onClick={async () => { for (const id of ids) await patchChat(id, { pinned: true }); setMore(false); onDone(); }}>Pin</Row>
        <Row onClick={async () => { for (const id of ids) await patchChat(id, { pinned: false }); setMore(false); onDone(); }}>Unpin</Row>
        <Row onClick={async () => { for (const id of ids) await patchChat(id, { archived: false }); setMore(false); onDone(); }}>Unarchive</Row>
      </Sheet>
    </div>
  );
}
