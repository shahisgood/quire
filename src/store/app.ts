import { create } from 'zustand';
import type { AppSettings, GenerationSettings, KeyMeta } from '@/lib/types';
import { DEFAULT_SETTINGS, loadSettings, saveSettings } from '@/lib/db';

interface AppState {
  settings: AppSettings;
  ready: boolean;
  online: boolean;
  init: () => Promise<void>;
  update: (patch: Partial<AppSettings> | ((s: AppSettings) => Partial<AppSettings>)) => void;
  updateUI: (patch: Partial<AppSettings['ui']>) => void;
  updateGlobal: (patch: Partial<GenerationSettings>) => void;
  updateMemory: (patch: Partial<AppSettings['memory']>) => void;
  setApiKey: (key: string | null) => void;
  setKeyMeta: (m: KeyMeta | null) => void;
  toggleFavourite: (id: string) => void;
  touchRecent: (id: string) => void;
}

let saveTimer: ReturnType<typeof setTimeout> | null = null;
function persist(s: AppSettings): void {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => { void saveSettings(s); }, 150);
}

export function applyTheme(s: AppSettings): void {
  const ui = s.ui;
  const theme = ui.theme === 'system' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : ui.theme;
  const root = document.documentElement;
  root.dataset.theme = theme;
  root.dataset.density = ui.density;
  root.dataset.face = ui.readingFace;
  root.style.setProperty('--font-scale', String(ui.fontScale));
  try { localStorage.setItem('quire.theme', ui.theme); } catch { /* private mode */ }
  const meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]:not([media])');
  const color = theme === 'dark' ? '#0e1013' : '#f6f6f3';
  if (meta) meta.content = color;
  else { const m = document.createElement('meta'); m.name = 'theme-color'; m.content = color; document.head.appendChild(m); }
}

export const useApp = create<AppState>((set, get) => ({
  settings: structuredClone(DEFAULT_SETTINGS),
  ready: false,
  online: typeof navigator === 'undefined' ? true : navigator.onLine,
  init: async () => {
    const s = await loadSettings();
    applyTheme(s);
    set({ settings: s, ready: true });
    window.addEventListener('online', () => set({ online: true }));
    window.addEventListener('offline', () => set({ online: false }));
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => applyTheme(get().settings));
  },
  update: (patch) => {
    const cur = get().settings;
    const p = typeof patch === 'function' ? patch(cur) : patch;
    const next = { ...cur, ...p };
    set({ settings: next });
    persist(next);
  },
  updateUI: (patch) => {
    const cur = get().settings;
    const next = { ...cur, ui: { ...cur.ui, ...patch } };
    applyTheme(next);
    set({ settings: next });
    persist(next);
  },
  updateGlobal: (patch) => {
    const cur = get().settings;
    const next = { ...cur, globalSettings: { ...cur.globalSettings, ...patch } };
    set({ settings: next });
    persist(next);
  },
  updateMemory: (patch) => {
    const cur = get().settings;
    const next = { ...cur, memory: { ...cur.memory, ...patch } };
    set({ settings: next });
    persist(next);
  },
  setApiKey: (key) => get().update({ apiKey: key ? key.trim() : null, keyMeta: null }),
  setKeyMeta: (m) => get().update({ keyMeta: m }),
  toggleFavourite: (id) => get().update((s) => ({ favouriteModelIds: s.favouriteModelIds.includes(id) ? s.favouriteModelIds.filter((x) => x !== id) : [...s.favouriteModelIds, id] })),
  touchRecent: (id) => get().update((s) => ({ recentModelIds: [id, ...s.recentModelIds.filter((x) => x !== id)].slice(0, 8) })),
}));

export const selectApiKey = (s: AppState): string | null => s.settings.apiKey;
export const clientConfig = (): { apiKey: string | null; baseUrl?: string } => {
  const s = useApp.getState().settings;
  return { apiKey: s.apiKey, baseUrl: s.proxyBaseUrl };
};
