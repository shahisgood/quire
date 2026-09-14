import { create } from 'zustand';
import { db, uid } from '@/lib/db';
import type { Chat, Folder, MemoryEntry, Message, Preset } from '@/lib/types';

interface ChatsState {
  chats: Chat[];
  folders: Folder[];
  presets: Preset[];
  memory: MemoryEntry[];
  loaded: boolean;
  reload: () => Promise<void>;
  reloadMemory: () => Promise<void>;
  patchChat: (id: string, patch: Partial<Chat>) => Promise<void>;
  deleteChats: (ids: string[]) => Promise<void>;
  duplicateChat: (id: string) => Promise<string>;
  createFolder: (name: string) => Promise<Folder>;
  renameFolder: (id: string, name: string) => Promise<void>;
  deleteFolder: (id: string) => Promise<void>;
  savePreset: (p: Preset) => Promise<void>;
  deletePreset: (id: string) => Promise<void>;
  patchMemory: (id: string, patch: Partial<MemoryEntry>) => Promise<void>;
  deleteMemory: (id: string) => Promise<void>;
  clearMemory: () => Promise<void>;
}

export const useChats = create<ChatsState>((set, get) => ({
  chats: [],
  folders: [],
  presets: [],
  memory: [],
  loaded: false,
  reload: async () => {
    const [chats, folders, presets, memory] = await Promise.all([
      db.chats.orderBy('updatedAt').reverse().toArray(),
      db.folders.orderBy('order').toArray(),
      db.presets.orderBy('name').toArray(),
      db.memory.orderBy('updatedAt').reverse().toArray(),
    ]);
    set({ chats, folders, presets, memory, loaded: true });
  },
  reloadMemory: async () => set({ memory: await db.memory.orderBy('updatedAt').reverse().toArray() }),
  patchChat: async (id, patch) => {
    await db.chats.update(id, patch);
    set((s) => ({ chats: s.chats.map((c) => (c.id === id ? { ...c, ...patch } : c)).sort((a, b) => b.updatedAt - a.updatedAt) }));
  },
  deleteChats: async (ids) => {
    await db.transaction('rw', db.chats, db.messages, async () => {
      for (const id of ids) { await db.messages.where('chatId').equals(id).delete(); await db.chats.delete(id); }
    });
    set((s) => ({ chats: s.chats.filter((c) => !ids.includes(c.id)) }));
  },
  duplicateChat: async (id) => {
    const src = await db.chats.get(id);
    if (!src) throw new Error('Chat not found');
    const msgs = await db.messages.where('chatId').equals(id).toArray();
    const idMap = new Map<string, string>(msgs.map((m) => [m.id, uid()]));
    const newId = uid();
    const now = Date.now();
    const copy: Chat = { ...src, id: newId, title: `${src.title} (copy)`, createdAt: now, updatedAt: now, pinned: false, activeLeafId: src.activeLeafId ? idMap.get(src.activeLeafId) ?? null : null, draft: '' };
    const newMsgs: Message[] = msgs.map((m) => ({ ...m, id: idMap.get(m.id)!, chatId: newId, parentId: m.parentId ? idMap.get(m.parentId) ?? null : null, editedFrom: m.editedFrom ? idMap.get(m.editedFrom) : undefined }));
    await db.transaction('rw', db.chats, db.messages, async () => { await db.chats.add(copy); await db.messages.bulkAdd(newMsgs); });
    await get().reload();
    return newId;
  },
  createFolder: async (name) => {
    const f: Folder = { id: uid(), name, createdAt: Date.now(), order: get().folders.length };
    await db.folders.add(f);
    set((s) => ({ folders: [...s.folders, f] }));
    return f;
  },
  renameFolder: async (id, name) => { await db.folders.update(id, { name }); set((s) => ({ folders: s.folders.map((f) => (f.id === id ? { ...f, name } : f)) })); },
  deleteFolder: async (id) => {
    await db.transaction('rw', db.folders, db.chats, async () => {
      await db.chats.where('folderId').equals(id).modify((c) => { delete c.folderId; });
      await db.folders.delete(id);
    });
    await get().reload();
  },
  savePreset: async (p) => { await db.presets.put(p); set((s) => ({ presets: [...s.presets.filter((x) => x.id !== p.id), p].sort((a, b) => a.name.localeCompare(b.name)) })); },
  deletePreset: async (id) => { await db.presets.delete(id); set((s) => ({ presets: s.presets.filter((p) => p.id !== id) })); },
  patchMemory: async (id, patch) => { await db.memory.update(id, { ...patch, updatedAt: Date.now() }); await get().reloadMemory(); },
  deleteMemory: async (id) => { await db.memory.delete(id); await get().reloadMemory(); },
  clearMemory: async () => { await db.memory.clear(); set({ memory: [] }); },
}));

if (typeof window !== 'undefined') window.addEventListener('quire:memory-changed', () => { void useChats.getState().reloadMemory(); });
