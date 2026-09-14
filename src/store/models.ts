import { DEFAULT_MODEL_HINTS } from '@/lib/db';
import { create } from 'zustand';
import type { ORModel } from '@/lib/types';
import { db } from '@/lib/db';
import { fetchModels } from '@/lib/openrouter';
import { clientConfig, useApp } from './app';

interface ModelsState {
  models: ORModel[];
  byId: Map<string, ORModel>;
  fetchedAt: number;
  loading: boolean;
  error: string | null;
  newIds: string[];
  load: () => Promise<void>;
  refresh: (force?: boolean) => Promise<void>;
  acknowledgeNew: () => void;
}

const STALE_MS = 6 * 60 * 60 * 1000;

export const useModels = create<ModelsState>((set, get) => ({
  models: [],
  byId: new Map(),
  fetchedAt: 0,
  loading: false,
  error: null,
  newIds: [],
  load: async () => {
    const cached = await db.catalogue.get('catalogue');
    if (cached) { set({ models: cached.models, byId: new Map(cached.models.map((m) => [m.id, m])), fetchedAt: cached.fetchedAt }); reconcileDefaults(cached.models); }
    const stale = !cached || Date.now() - cached.fetchedAt > STALE_MS;
    if (navigator.onLine) void get().refresh(stale);
  },
  refresh: async (force = true) => {
    if (get().loading) return;
    if (!force && get().fetchedAt && Date.now() - get().fetchedAt < STALE_MS) return;
    set({ loading: true, error: null });
    try {
      const models = await fetchModels(clientConfig());
      if (!models.length) throw new Error('OpenRouter returned an empty model list');
      models.sort((a, b) => a.name.localeCompare(b.name));
      const fetchedAt = Date.now();
      await db.catalogue.put({ key: 'catalogue', fetchedAt, models });
      const app = useApp.getState();
      const seen = new Set(app.settings.seenModelIds ?? []);
      const prevHad = seen.size > 0;
      const newIds = prevHad ? models.filter((m) => !seen.has(m.id)).map((m) => m.id) : [];
      set({ models, byId: new Map(models.map((m) => [m.id, m])), fetchedAt, loading: false, newIds: newIds.length ? newIds : get().newIds });
      reconcileDefaults(models);
      app.update({ lastSyncedModelsAt: fetchedAt, seenModelIds: prevHad ? app.settings.seenModelIds : models.map((m) => m.id) });
    } catch (e) {
      set({ loading: false, error: e instanceof Error ? e.message : 'Could not load models' });
    }
  },
  acknowledgeNew: () => {
    const { models } = get();
    useApp.getState().update({ seenModelIds: models.map((m) => m.id) });
    set({ newIds: [] });
  },
}));

export const getModel = (id: string | undefined): ORModel | undefined => (id ? useModels.getState().byId.get(id) : undefined);

/**
 * Resolve the default chat and extraction models against the live catalogue.
 * If the guessed id is absent, adopt the newest model whose name matches the hint; migrate the old defaults once.
 */
function reconcileDefaults(models: ORModel[]): void {
  const app = useApp.getState();
  const s = app.settings;
  const ids = new Set(models.map((m) => m.id));
  const find = (h: { id: string; name: RegExp }) => (ids.has(h.id) ? h.id : models.filter((m) => h.name.test(m.name) || h.name.test(m.id)).sort((a, b) => b.created - a.created)[0]?.id);
  const chat = find(DEFAULT_MODEL_HINTS.chat);
  const ext = find(DEFAULT_MODEL_HINTS.extraction);
  const isOld = (id: string, h: { id: string; previous: readonly string[] }) => id === h.id || h.previous.includes(id);
  if (chat && isOld(s.defaultModelId, DEFAULT_MODEL_HINTS.chat) && s.defaultModelId !== chat) app.update({ defaultModelId: chat });
  if (ext && isOld(s.memory.extractionModelId, DEFAULT_MODEL_HINTS.extraction) && s.memory.extractionModelId !== ext) app.updateMemory({ extractionModelId: ext });
}
