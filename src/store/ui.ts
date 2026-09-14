import { create } from 'zustand';
import { toast as sonnerToast } from 'sonner';
import type { ReactNode } from 'react';

export type Route =
  | { name: 'chat'; chatId: string | null }
  | { name: 'list' }
  | { name: 'settings'; section?: string }
  | { name: 'memory' }
  | { name: 'model'; modelId: string };

export type SheetKind =
  | { kind: 'picker'; onPick?: (id: string) => void; title?: string }
  | { kind: 'chatSettings' }
  | { kind: 'quick' }
  | { kind: 'messageMenu'; messageId: string }
  | { kind: 'presetPick'; onPick: (presetId: string | null) => void }
  | { kind: 'folderPick'; onPick: (folderId: string | null) => void }
  | { kind: 'modelCard'; modelId: string }
  | { kind: 'custom'; title?: string; render: () => ReactNode };

export interface DialogSpec {
  title: string;
  body?: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
  /** Require the user to type this string to enable confirm. */
  typed?: string;
  input?: { placeholder?: string; initial?: string; multiline?: boolean };
  onConfirm: (value?: string) => void | Promise<void>;
  onCancel?: () => void;
}

export interface Toast { id: number; text: string; action?: { label: string; onClick: () => void }; ttl?: number }

interface UIState {
  route: Route;
  sheet: SheetKind | null;
  dialog: DialogSpec | null;
  toasts: Toast[];
  keyboardOpen: boolean;
  updateReady: boolean;
  applyUpdate: (() => void) | null;
  wide: boolean;
  navigate: (r: Route, replace?: boolean) => void;
  back: () => void;
  openSheet: (s: SheetKind) => void;
  closeSheet: () => void;
  openDialog: (d: DialogSpec) => void;
  closeDialog: () => void;
  toast: (text: string, action?: Toast['action'], ttl?: number) => void;
  dismissToast: (id: number) => void;
  setKeyboardOpen: (v: boolean) => void;
  setUpdate: (ready: boolean, apply: (() => void) | null) => void;
}

let toastSeq = 1;

function routeToPath(r: Route): string {
  switch (r.name) {
    case 'chat': return r.chatId ? `/chat/${r.chatId}` : '/';
    case 'list': return '/chats';
    case 'settings': return r.section ? `/settings/${r.section}` : '/settings';
    case 'memory': return '/memory';
    case 'model': return `/model/${encodeURIComponent(r.modelId)}`;
  }
}

export function pathToRoute(path: string): Route {
  const p = path.replace(/\/+$/, '') || '/';
  if (p === '/' ) return { name: 'chat', chatId: null };
  if (p === '/chats') return { name: 'list' };
  if (p === '/memory') return { name: 'memory' };
  if (p.startsWith('/settings')) return { name: 'settings', section: p.split('/')[2] };
  if (p.startsWith('/chat/')) return { name: 'chat', chatId: p.slice(6) };
  if (p.startsWith('/model/')) return { name: 'model', modelId: decodeURIComponent(p.slice(7)) };
  return { name: 'chat', chatId: null };
}

export const useUI = create<UIState>((set, get) => ({
  route: { name: 'chat', chatId: null },
  sheet: null,
  dialog: null,
  toasts: [],
  keyboardOpen: false,
  updateReady: false,
  applyUpdate: null,
  wide: typeof matchMedia !== 'undefined' && matchMedia('(min-width: 900px)').matches,
  navigate: (r, replace = false) => {
    const path = routeToPath(r);
    try { (replace ? history.replaceState : history.pushState).call(history, { q: 1 }, '', path); } catch { /* file:// etc */ }
    set({ route: r, sheet: null });
  },
  back: () => {
    const r = get().route;
    if (r.name === 'chat') { get().navigate({ name: 'list' }); return; }
    if (r.name === 'settings' && r.section) { get().navigate({ name: 'settings' }); return; }
    get().navigate({ name: 'chat', chatId: null });
  },
  openSheet: (s) => set({ sheet: s }),
  closeSheet: () => set({ sheet: null }),
  openDialog: (d) => set({ dialog: d }),
  closeDialog: () => set({ dialog: null }),
  toast: (text, action, ttl = 3500) => {
    const id = toastSeq++;
    sonnerToast(text, { id, duration: ttl > 0 ? ttl : Infinity, action: action ? { label: action.label, onClick: action.onClick } : undefined });
  },
  dismissToast: (id) => sonnerToast.dismiss(id),
  setKeyboardOpen: (v) => { if (get().keyboardOpen !== v) set({ keyboardOpen: v }); },
  setUpdate: (ready, apply) => set({ updateReady: ready, applyUpdate: apply }),
}));

if (typeof window !== 'undefined') {
  window.addEventListener('popstate', () => {
    const ui = useUI.getState();
    if (ui.sheet || ui.dialog) { useUI.setState({ sheet: null, dialog: null }); return; }
    useUI.setState({ route: pathToRoute(location.pathname) });
  });
  matchMedia('(min-width: 900px)').addEventListener('change', (e) => useUI.setState({ wide: e.matches }));
}

export const haptic = (): void => {
  const on = false; // iOS Safari has no vibration API; kept for parity, no-op everywhere.
  if (on && 'vibrate' in navigator) navigator.vibrate(8);
};
