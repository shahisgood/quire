import { useMemo, useState } from 'react';
import type { MemoryCategory, MemoryEntry } from '@/lib/types';
import { MEMORY_CATEGORIES } from '@/lib/types';
import { addMemoryManually, totalMemoryChars } from '@/lib/memory';
import { useApp } from '@/store/app';
import { useChats } from '@/store/chats';
import { useUI } from '@/store/ui';
import { Button, Hint, IconButton, Icons, SectionTitle, Segmented, useSwipe } from '@/components/ui';

const LABEL: Record<MemoryCategory, string> = { identity: 'Identity', preference: 'Preferences', project: 'Projects', relationship: 'Relationships', context: 'Context' };

export function MemoryScreen() {
  const { memory, patchMemory, deleteMemory, clearMemory } = useChats();
  const budget = useApp((s) => s.settings.memory.maxInjectedChars);
  const enabled = useApp((s) => s.settings.memory.enabled);
  const { navigate, openDialog, toast } = useUI();
  const [adding, setAdding] = useState(false);
  const [text, setText] = useState('');
  const [cat, setCat] = useState<MemoryCategory>('context');
  const total = totalMemoryChars(memory);
  const groups = useMemo(() => MEMORY_CATEGORIES.map((c) => ({ c, items: memory.filter((e) => e.category === c) })).filter((g) => g.items.length), [memory]);
  const add = async () => { if (!text.trim()) return; await addMemoryManually(text, cat); setText(''); setAdding(false); toast('Remembered'); };
  return (
    <div className="flex h-full min-h-0 flex-1 flex-col">
      <header className="chrome safe-t hairline flex items-center gap-1 px-2" style={{ minHeight: 'calc(48px + env(safe-area-inset-top))' }}>
        <IconButton icon={Icons.back} label="Back" onClick={() => navigate({ name: 'chat', chatId: null })} />
        <div className="flex-1 px-2 text-md font-semibold">Memory</div>
        <IconButton icon={Icons.settings} label="Memory settings" onClick={() => navigate({ name: 'settings', section: 'memory' })} />
        <IconButton icon={Icons.plus} label="Add a fact" onClick={() => setAdding(true)} accent />
      </header>
      <div className="scroll min-h-0 flex-1 pb-12">
        <div className="px-4 pt-3">
          <div className="flex items-baseline justify-between text-sm text-ink2"><span>{memory.length} {memory.length === 1 ? "entry" : "entries"} · {total.toLocaleString()} of {budget.toLocaleString()} characters</span><span className={total > budget ? 'text-accent' : ''}>{total > budget ? 'Over budget: some entries are left out per request' : 'Fits in every request'}</span></div>
          <div className="mt-1 h-[3px] overflow-hidden rounded-full bg-rule"><div className={`h-full ${total > budget ? 'bg-accent' : 'bg-ink2'}`} style={{ width: `${Math.min(100, (total / budget) * 100)}%` }} /></div>
        </div>
        {!enabled && <Hint>Memory is turned off in settings. Entries are kept but nothing is injected or extracted.</Hint>}
        <Hint>This is everything Quire will say about you to a model, minus anything you disable. Pinned entries always go first.</Hint>
        {adding && (
          <div className="mx-4 mt-2 rounded-lg border border-rule bg-raised p-3">
            <textarea value={text} onChange={(e) => setText(e.target.value)} rows={2} placeholder="One fact, e.g. Works mostly in TypeScript." className="w-full text-body" autoFocus />
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Segmented value={cat} onChange={setCat} options={MEMORY_CATEGORIES.map((c) => ({ value: c, label: LABEL[c].replace(/s$/, '') }))} />
              <span className="flex-1" />
              <Button kind="text" onClick={() => setAdding(false)} className="text-ink2">Cancel</Button>
              <Button kind="primary" onClick={() => void add()} disabled={!text.trim()}>Add</Button>
            </div>
          </div>
        )}
        {memory.length === 0 && !adding && <div className="px-6 py-10 text-center text-body text-ink2">Nothing remembered yet. Facts you state in chats show up here after a reply, or add one yourself.</div>}
        {groups.map((g) => (
          <div key={g.c}>
            <SectionTitle>{LABEL[g.c]}</SectionTitle>
            {g.items.map((e) => <Entry key={e.id} e={e} onPatch={(p) => void patchMemory(e.id, p)} onDelete={() => void deleteMemory(e.id)} onSource={() => e.sourceChatId && navigate({ name: 'chat', chatId: e.sourceMessageId ? `${e.sourceChatId}#${e.sourceMessageId}` : e.sourceChatId })} />)}
          </div>
        ))}
        {memory.length > 0 && <div className="px-4 pt-8"><Button kind="outline" className="text-accent" onClick={() => openDialog({ title: 'Clear all memory?', body: `${memory.length} entries are deleted. Chats are not affected.`, confirmLabel: 'Clear', destructive: true, typed: 'clear', onConfirm: clearMemory })}>Clear all memory</Button></div>}
      </div>
    </div>
  );
}

function Entry({ e, onPatch, onDelete, onSource }: { e: MemoryEntry; onPatch: (p: Partial<MemoryEntry>) => void; onDelete: () => void; onSource: () => void }) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(e.text);
  const sw = useSwipe({ disabled: editing, onLeft: onDelete, threshold: 80 });
  const commit = () => { setEditing(false); if (text.trim() && text.trim() !== e.text) onPatch({ text: text.trim() }); else setText(e.text); };
  return (
    <div className="swipe-row" {...sw.bind}>
      <div ref={sw.under} className="swipe-under justify-end text-accent" style={{ opacity: 0 }}>Delete</div>
      <div ref={sw.face} className="swipe-face px-4 py-2">
        {editing ? (
          <textarea value={text} onChange={(ev) => setText(ev.target.value)} onBlur={commit} onKeyDown={(ev) => { if (ev.key === 'Enter' && !ev.shiftKey) { ev.preventDefault(); commit(); } }} rows={2} className="w-full rounded-md border border-rule bg-raised px-2 py-1 text-body" autoFocus />
        ) : (
          <button type="button" onClick={() => { if (!sw.isDragging()) setEditing(true); }} className={`w-full text-left text-body leading-snug ${e.disabled ? 'text-ink2 line-through' : 'text-ink'}`}>{e.pinned && <Icons.pin size={12} className="mr-1 inline text-accent" />}{e.text}</button>
        )}
        <div className="mt-1 flex items-center gap-1 text-sm text-ink2">
          <button type="button" className="tap pressable !min-h-8 px-1.5" onClick={() => onPatch({ pinned: !e.pinned })}>{e.pinned ? 'Unpin' : 'Pin'}</button>
          <button type="button" className="tap pressable !min-h-8 px-1.5" onClick={() => onPatch({ disabled: !e.disabled })}>{e.disabled ? 'Enable' : 'Disable'}</button>
          {e.sourceChatId && <button type="button" className="tap pressable !min-h-8 px-1.5" onClick={onSource}>Source</button>}
          <span className="flex-1" />
          <IconButton icon={Icons.trash} label="Delete" onClick={onDelete} size={15} className="!min-h-8 !min-w-8" />
        </div>
      </div>
    </div>
  );
}
