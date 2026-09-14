import Dexie, { type EntityTable } from 'dexie';
import type { AppSettings, Chat, DayCost, Folder, GenerationSettings, MemoryEntry, Message, ModelCatalogue, Preset } from './types';

interface KV { key: string; value: unknown }

export class QuireDB extends Dexie {
  chats!: EntityTable<Chat, 'id'>;
  messages!: EntityTable<Message, 'id'>;
  folders!: EntityTable<Folder, 'id'>;
  presets!: EntityTable<Preset, 'id'>;
  memory!: EntityTable<MemoryEntry, 'id'>;
  catalogue!: EntityTable<ModelCatalogue, 'key'>;
  kv!: EntityTable<KV, 'key'>;
  dayCosts!: EntityTable<DayCost, 'day'>;

  constructor() {
    super('quire');
    this.version(1).stores({
      chats: 'id, updatedAt, folderId, pinned, archived',
      messages: 'id, chatId, parentId, createdAt, [chatId+createdAt]',
      folders: 'id, order',
      presets: 'id, name',
      memory: 'id, category, updatedAt, pinned',
      catalogue: 'key',
      kv: 'key',
      dayCosts: 'day',
    });
  }
}

export const db = new QuireDB();

export const DEFAULT_GENERATION: GenerationSettings = {
  stream: true,
  reasoning: { mode: 'off', effort: 'medium', exclude: false },
  provider: { allowFallbacks: true, requireParameters: true, denyDataCollection: false },
  webSearch: { enabled: false, maxResults: 5 },
  transforms: [],
  fallbackModels: [],
};

export const DEFAULT_SETTINGS: AppSettings = {
  apiKey: null,
  defaultModelId: 'anthropic/claude-sonnet-4',
  globalSettings: DEFAULT_GENERATION,
  globalSystemPrompt: '',
  memory: { enabled: true, autoExtract: true, extractionModelId: 'openai/gpt-4o-mini', maxInjectedChars: 2000 },
  ui: {
    theme: 'dark',
    fontScale: 1,
    density: 'comfortable',
    readingFace: 'serif',
    showReasoningByDefault: false,
    showCosts: true,
    sendOnEnter: true,
    hapticsEnabled: false,
  },
  lastSyncedModelsAt: 0,
  favouriteModelIds: [],
  recentModelIds: [],
  lastChatId: null,
  lastExportAt: 0,
  messagesSinceExport: 0,
  persistRequested: false,
  keyMeta: null,
  seenModelIds: [],
};

export async function loadSettings(): Promise<AppSettings> {
  const row = await db.kv.get('settings');
  if (!row) return structuredClone(DEFAULT_SETTINGS);
  const v = row.value as Partial<AppSettings>;
  return {
    ...structuredClone(DEFAULT_SETTINGS),
    ...v,
    memory: { ...DEFAULT_SETTINGS.memory, ...(v.memory ?? {}) },
    ui: { ...DEFAULT_SETTINGS.ui, ...(v.ui ?? {}) },
    globalSettings: { ...DEFAULT_GENERATION, ...(v.globalSettings ?? {}) },
  };
}

export async function saveSettings(s: AppSettings): Promise<void> {
  await db.kv.put({ key: 'settings', value: s });
}

export const uid = (): string => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`);
export const dayKey = (t = Date.now()): string => { const d = new Date(t); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
