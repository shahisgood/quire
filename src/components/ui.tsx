import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { Drawer } from 'vaul';
import * as RadixDialog from '@radix-ui/react-dialog';
import { Toaster } from 'sonner';
import { useApp } from '@/store/app';
import { useUI, type DialogSpec } from '@/store/ui';

// ---------- Icons (hand-drawn, 1.5px strokes so they sit with the type) ----------
const I = (d: ReactNode, vb = '0 0 24 24') => ({ size = 20, className = '' }: { size?: number; className?: string }) => (
  <svg width={size} height={size} viewBox={vb} fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden>{d}</svg>
);
export const Icons = {
  back: I(<path d="M15 5l-7 7 7 7" />),
  chevronRight: I(<path d="M9 5l7 7-7 7" />),
  chevronDown: I(<path d="M5 9l7 7 7-7" />),
  chevronUp: I(<path d="M5 15l7-7 7 7" />),
  down: I(<path d="M12 4v16M5 13l7 7 7-7" />),
  more: I(<><circle cx="5" cy="12" r="1.2" fill="currentColor" /><circle cx="12" cy="12" r="1.2" fill="currentColor" /><circle cx="19" cy="12" r="1.2" fill="currentColor" /></>),
  send: I(<path d="M12 19V5M5 12l7-7 7 7" />),
  stop: I(<rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor" stroke="none" />),
  plus: I(<path d="M12 5v14M5 12h14" />),
  x: I(<path d="M6 6l12 12M18 6L6 18" />),
  check: I(<path d="M5 12l5 5L19 7" />),
  search: I(<><circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" /></>),
  star: I(<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z" />),
  starFilled: I(<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z" fill="currentColor" />),
  settings: I(<><circle cx="12" cy="12" r="3" /><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1" /></>),
  sliders: I(<><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="15" cy="7" r="2" /><circle cx="9" cy="17" r="2" /></>),
  image: I(<><rect x="3" y="5" width="18" height="14" rx="2" /><circle cx="8.5" cy="10" r="1.5" /><path d="M21 15l-5-5-7 7" /></>),
  camera: I(<><path d="M4 8h3l2-2.5h6L17 8h3v11H4z" /><circle cx="12" cy="13" r="3" /></>),
  file: I(<><path d="M6 3h8l4 4v14H6z" /><path d="M14 3v4h4" /></>),
  paperclip: I(<path d="M20 11l-8.5 8.5a5 5 0 01-7-7L13 4a3.3 3.3 0 014.7 4.7L9.5 17a1.6 1.6 0 01-2.3-2.3L14.5 7.5" />),
  copy: I(<><rect x="9" y="9" width="11" height="11" rx="2" /><path d="M5 15V5a1 1 0 011-1h10" /></>),
  edit: I(<path d="M4 20h4l11-11-4-4L4 16zM13 7l4 4" />),
  refresh: I(<path d="M20 12a8 8 0 01-14.5 4.6M4 12a8 8 0 0114.5-4.6M4 4v4h4M20 20v-4h-4" />),
  branch: I(<><circle cx="6" cy="5" r="2" /><circle cx="6" cy="19" r="2" /><circle cx="18" cy="9" r="2" /><path d="M6 7v10M18 11c0 4-12 2-12 6" /></>),
  trash: I(<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" />),
  share: I(<path d="M12 3v12M8 7l4-4 4 4M5 13v7h14v-7" />),
  code: I(<path d="M8 8l-4 4 4 4M16 8l4 4-4 4M14 4l-4 16" />),
  info: I(<><circle cx="12" cy="12" r="9" /><path d="M12 11v6M12 8v.5" /></>),
  pin: I(<path d="M9 4h6l-1 6 3 3v2H7v-2l3-3zM12 15v6" />),
  archive: I(<><rect x="3" y="4" width="18" height="4" rx="1" /><path d="M5 8v12h14V8M10 12h4" /></>),
  folder: I(<path d="M3 6h6l2 2h10v11H3z" />),
  memory: I(<><path d="M12 4a4 4 0 014 4v1a3 3 0 012 5.2 3 3 0 01-2 5.3H10a4 4 0 01-4-4V8a4 4 0 014-4z" /><path d="M12 4v16" /></>),
  incognito: I(<><path d="M4 12h16M7 12l2-6h6l2 6" /><circle cx="8" cy="16" r="2.5" /><circle cx="16" cy="16" r="2.5" /><path d="M10.5 16h3" /></>),
  eye: I(<><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" /><circle cx="12" cy="12" r="3" /></>),
  eyeOff: I(<><path d="M3 3l18 18M10.6 10.6a2 2 0 002.8 2.8M7 7.5C4.2 9.3 2.5 12 2.5 12S6 18.5 12 18.5c1.5 0 2.9-.4 4.1-1M9.5 5.8c.8-.2 1.6-.3 2.5-.3 6 0 9.5 6.5 9.5 6.5s-1 1.9-2.8 3.6" /></>),
  dice: I(<><rect x="4" y="4" width="16" height="16" rx="3" /><circle cx="9" cy="9" r="1" fill="currentColor" /><circle cx="15" cy="15" r="1" fill="currentColor" /><circle cx="15" cy="9" r="1" fill="currentColor" /><circle cx="9" cy="15" r="1" fill="currentColor" /></>),
  wifiOff: I(<path d="M3 3l18 18M8.5 8.6A11 11 0 002 9.5M5.5 12.6a8 8 0 013.3-2M9 16a4 4 0 014-1M12 19.5h.01M16.4 11.9a8 8 0 002.1.7M11.5 5.6A11 11 0 0122 9.5" />),
  list: I(<path d="M4 6h16M4 12h16M4 18h10" />),
  spark: I(<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z" />),
  reasoning: I(<><path d="M9 3h6M12 3v3M8 6h8a4 4 0 014 4v5a4 4 0 01-4 4H8a4 4 0 01-4-4v-5a4 4 0 014-4z" /><circle cx="9.5" cy="13" r="1" fill="currentColor" /><circle cx="14.5" cy="13" r="1" fill="currentColor" /></>),
  tools: I(<path d="M14.5 4.5a4 4 0 00-4.9 5L4 15v5h5l5.5-5.6a4 4 0 005-4.9l-2.8 2.8-2.1-.4-.4-2.1z" />),
};

// ---------- Buttons ----------
export function IconButton({ icon: Ico, label, onClick, className = '', size = 20, disabled, accent, style }: { icon: (p: { size?: number; className?: string }) => ReactNode; label: string; onClick?: (e: React.MouseEvent) => void; className?: string; size?: number; disabled?: boolean; accent?: boolean; style?: CSSProperties }) {
  return (
    <button type="button" aria-label={label} title={label} onClick={onClick} disabled={disabled} style={style} className={`tap pressable inline-flex items-center justify-center rounded-full ${accent ? 'text-accent' : 'text-ink2'} ${className}`}>
      <Ico size={size} />
    </button>
  );
}

export function Button({ children, onClick, kind = 'ghost', className = '', disabled, type = 'button', full }: { children: ReactNode; onClick?: () => void; kind?: 'ghost' | 'primary' | 'outline' | 'text'; className?: string; disabled?: boolean; type?: 'button' | 'submit'; full?: boolean }) {
  const base = 'tap pressable inline-flex items-center justify-center gap-2 rounded-lg px-4 text-body font-medium';
  const kinds = {
    ghost: 'bg-raised text-ink',
    primary: 'bg-accent text-onaccent',
    outline: 'border border-rule text-ink',
    text: 'text-accent',
  } as const;
  return <button type={type} onClick={onClick} disabled={disabled} className={`${base} ${kinds[kind]} ${full ? 'w-full' : ''} ${className}`}>{children}</button>;
}

export function Switch({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label?: string }) {
  return <button type="button" role="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)} className="switch" />;
}

export function Segmented<T extends string>({ value, options, onChange, className = '' }: { value: T | undefined; options: Array<{ value: T; label: string }>; onChange: (v: T) => void; className?: string }) {
  return (
    <div role="radiogroup" className={`inline-flex rounded-lg bg-raised p-0.5 ${className}`}>
      {options.map((o) => (
        <button key={o.value} type="button" role="radio" aria-checked={value === o.value} onClick={() => onChange(o.value)}
          className={`pressable min-h-[36px] rounded-md px-3 text-sm ${value === o.value ? 'bg-base text-ink shadow-[0_0_0_1px_var(--c-rule)]' : 'text-ink2'}`}>{o.label}</button>
      ))}
    </div>
  );
}

// ---------- Rows ----------
export function Row({ children, onClick, className = '', right, sub, disabled }: { children: ReactNode; onClick?: () => void; className?: string; right?: ReactNode; sub?: ReactNode; disabled?: boolean }) {
  const inner = (
    <>
      <div className="min-w-0 flex-1">
        <div className="text-body text-ink">{children}</div>
        {sub && <div className="mt-0.5 text-sm text-ink2">{sub}</div>}
      </div>
      {right && <div className="ml-3 flex shrink-0 items-center gap-2 text-ink2">{right}</div>}
    </>
  );
  const cls = `flex min-h-[48px] w-full items-center px-4 py-2.5 text-left ${onClick ? 'row-press' : ''} ${className}`;
  return onClick ? <button type="button" disabled={disabled} className={cls} onClick={onClick}>{inner}</button> : <div className={cls}>{inner}</div>;
}

export function SectionTitle({ children, right }: { children: ReactNode; right?: ReactNode }) {
  return <div className="flex items-end justify-between px-4 pb-1 pt-6 text-sm text-ink2"><span>{children}</span>{right}</div>;
}

export function Hint({ children }: { children: ReactNode }) {
  return <p className="px-4 pb-2 pt-1 text-sm leading-snug text-ink2">{children}</p>;
}

// ---------- Sheet ----------
export function Sheet({ open, onClose, title, children, tall, right }: { open: boolean; onClose: () => void; title?: ReactNode; children: ReactNode; tall?: boolean; right?: ReactNode }) {
  return (
    <Drawer.Root open={open} onOpenChange={(o) => { if (!o) onClose(); }} shouldScaleBackground={false} repositionInputs={false}>
      <Drawer.Portal>
        <Drawer.Overlay className="sheet-overlay fixed inset-0 z-40" />
        <Drawer.Content aria-describedby={undefined} className={`sheet chrome fixed inset-x-0 bottom-0 z-40 flex flex-col outline-none ${tall ? 'h-[92%] sm:h-[85vh]' : 'max-h-[88%] sm:max-h-[85vh]'} sm:mx-auto sm:w-[560px]`}>
          <Drawer.Handle className="sheet-handle" />
          <div className="flex items-center justify-between px-4 pb-2 pt-3">
            <Drawer.Title className="text-md font-semibold">{title ?? ''}</Drawer.Title>
            <div className="flex items-center gap-1">{right}<Drawer.Close asChild><IconButton icon={Icons.x} label="Close" /></Drawer.Close></div>
          </div>
          <div className="scroll min-h-0 flex-1 pb-safe-b" data-vaul-no-drag={undefined}>{children}</div>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}

// ---------- Dialog ----------
export function DialogHost() {
  const dialog = useUI((s) => s.dialog);
  const close = useUI((s) => s.closeDialog);
  const [value, setValue] = useState('');
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const ref = useRef<HTMLInputElement | HTMLTextAreaElement>(null);
  useEffect(() => { setValue(dialog?.input?.initial ?? ''); setTyped(''); setBusy(false); }, [dialog]);
  const d: DialogSpec | null = dialog;
  const canConfirm = !!d && !busy && (!d.typed || typed.trim() === d.typed) && (!d.input || value.trim().length > 0 || d.input.initial !== undefined);
  const confirm = async () => { if (!d) return; setBusy(true); try { await d.onConfirm(d.input ? value : undefined); } finally { close(); } };
  const cancel = () => { d?.onCancel?.(); close(); };
  return (
    <RadixDialog.Root open={!!d} onOpenChange={(o) => { if (!o) cancel(); }}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="modal-overlay fixed inset-0 z-50" />
        <RadixDialog.Content aria-describedby={undefined} onOpenAutoFocus={(e) => { if (d?.input) { e.preventDefault(); ref.current?.focus(); } }} className="modal chrome fixed left-1/2 top-1/2 z-50 w-[calc(100%-48px)] max-w-[380px] rounded-2xl border border-rule bg-base p-5 outline-none">
          {d && (
            <>
              <RadixDialog.Title className="text-md font-semibold">{d.title}</RadixDialog.Title>
              {d.body && <div className="mt-2 text-body text-ink2">{d.body}</div>}
              {d.input && (d.input.multiline
                ? <textarea ref={ref as React.RefObject<HTMLTextAreaElement>} value={value} onChange={(e) => setValue(e.target.value)} placeholder={d.input.placeholder} rows={4} className="mt-3 w-full rounded-lg border border-rule bg-raised px-3 py-2 text-body" />
                : <input ref={ref as React.RefObject<HTMLInputElement>} value={value} onChange={(e) => setValue(e.target.value)} placeholder={d.input.placeholder} onKeyDown={(e) => { if (e.key === 'Enter' && canConfirm) void confirm(); }} className="mt-3 w-full rounded-lg border border-rule bg-raised px-3 py-2 text-body" />)}
              {d.typed && (
                <div className="mt-3">
                  <div className="text-sm text-ink2">Type <span className="font-mono text-ink">{d.typed}</span> to confirm</div>
                  <input value={typed} onChange={(e) => setTyped(e.target.value)} autoCapitalize="off" autoCorrect="off" className="mt-1 w-full rounded-lg border border-rule bg-raised px-3 py-2 font-mono text-body" />
                </div>
              )}
              <div className="mt-5 flex justify-end gap-2">
                <Button kind="text" onClick={cancel} className="text-ink2">{d.cancelLabel ?? 'Cancel'}</Button>
                <Button kind={d.destructive ? 'outline' : 'primary'} onClick={() => void confirm()} disabled={!canConfirm} className={d.destructive ? 'text-accent' : ''}>{d.confirmLabel ?? 'OK'}</Button>
              </div>
            </>
          )}
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  );
}

// ---------- Toasts (Sonner) ----------
export function ToastHost() {
  const theme = useApp((s) => s.settings.ui.theme);
  return <Toaster theme={theme} position="top-center" offset={{ top: 'calc(env(safe-area-inset-top) + 8px)' }} mobileOffset={{ top: 'calc(env(safe-area-inset-top) + 8px)' }} closeButton={false} gap={8} visibleToasts={3} toastOptions={{ unstyled: true, classNames: { toast: 'toast', title: 'toast-title', actionButton: 'toast-action', description: 'toast-desc' } }} />;
}

// ---------- Bars ----------
export function Bar({ children, action, onAction, onClose }: { children: ReactNode; action?: string; onAction?: () => void; onClose?: () => void }) {
  return (
    <div className="chrome flex items-center gap-3 border-b border-rule bg-raised px-4 py-2 text-sm">
      <span className="flex-1 text-ink">{children}</span>
      {action && <button type="button" className="text-accent" onClick={onAction}>{action}</button>}
      {onClose && <IconButton icon={Icons.x} label="Dismiss" onClick={onClose} size={16} className="!min-h-8 !min-w-8" />}
    </div>
  );
}

export function Empty({ title, body, action }: { title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="flex h-full flex-col items-center justify-center px-8 text-center">
      <div className="font-read text-lg text-ink">{title}</div>
      {body && <div className="mt-2 max-w-[32ch] text-body text-ink2">{body}</div>}
      {action && <div className="mt-5">{action}</div>}
    </div>
  );
}

/** Long-press helper returning pointer handlers. */
export function useLongPress(onLong: () => void, ms = 420) {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const fired = useRef(false);
  const start = useRef<{ x: number; y: number } | null>(null);
  const clear = () => { if (timer.current) clearTimeout(timer.current); timer.current = null; };
  return {
    onPointerDown: (e: React.PointerEvent) => { fired.current = false; start.current = { x: e.clientX, y: e.clientY }; clear(); timer.current = setTimeout(() => { fired.current = true; onLong(); }, ms); },
    onPointerMove: (e: React.PointerEvent) => { if (start.current && Math.hypot(e.clientX - start.current.x, e.clientY - start.current.y) > 8) clear(); },
    onPointerUp: clear,
    onPointerCancel: clear,
    onPointerLeave: clear,
    onContextMenu: (e: React.MouseEvent) => { e.preventDefault(); if (!fired.current) onLong(); },
    didFire: () => fired.current,
  };
}

/**
 * Horizontal swipe on a row. Tracks 1:1 with pointer capture, rubber-bands past `limit`,
 * commits on distance or on a flick (velocity > 0.11 px/ms), settles with WAAPI.
 * Nothing re-renders during the drag: the transform goes straight onto the face element.
 */
export function useSwipe({ onLeft, onRight, threshold = 70, limit = 120, disabled }: { onLeft?: () => void; onRight?: () => void; threshold?: number; limit?: number; disabled?: boolean }) {
  const face = useRef<HTMLDivElement>(null);
  const under = useRef<HTMLDivElement>(null);
  const st = useRef<{ id: number; x0: number; y0: number; t0: number; dx: number; active: boolean; lastX: number; lastT: number } | null>(null);
  const rubber = (over: number) => (over * limit * 0.55) / (limit + 0.55 * Math.abs(over));
  const settle = (from: number, to: number, cb?: () => void) => {
    const f = face.current; if (!f) return;
    const a = f.animate([{ transform: `translateX(${from}px)` }, { transform: `translateX(${to}px)` }], { duration: 220, easing: 'cubic-bezier(0.23, 1, 0.32, 1)', fill: 'forwards' });
    a.onfinish = () => { a.cancel(); f.style.transform = to ? `translateX(${to}px)` : ''; cb?.(); };
  };
  const paint = (dx: number) => {
    const f = face.current, u = under.current; if (!f) return;
    f.style.transform = `translateX(${dx}px)`;
    if (u) { u.dataset.dir = dx > 0 ? 'right' : 'left'; u.style.opacity = String(Math.min(1, Math.abs(dx) / threshold)); }
  };
  const bind = {
    onPointerDown: (e: React.PointerEvent) => {
      if (disabled || st.current || e.pointerType === 'mouse' && e.button !== 0) return;
      st.current = { id: e.pointerId, x0: e.clientX, y0: e.clientY, t0: performance.now(), dx: 0, active: false, lastX: e.clientX, lastT: performance.now() };
    },
    onPointerMove: (e: React.PointerEvent) => {
      const s = st.current; if (!s || e.pointerId !== s.id) return;
      const dx = e.clientX - s.x0, dy = e.clientY - s.y0;
      if (!s.active) {
        if (Math.abs(dx) < 10) return;                    // hysteresis before committing to a direction
        if (Math.abs(dy) > Math.abs(dx)) { st.current = null; return; }  // vertical wins: let the scroller have it
        s.active = true; (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
      }
      const allowed = (dx > 0 && onRight) || (dx < 0 && onLeft);
      const bounded = !allowed ? rubber(dx) : Math.abs(dx) > limit ? Math.sign(dx) * (limit + rubber(Math.abs(dx) - limit)) : dx;
      s.dx = bounded; s.lastX = e.clientX; s.lastT = performance.now();
      paint(bounded);
    },
    onPointerUp: (e: React.PointerEvent) => {
      const s = st.current; if (!s || e.pointerId !== s.id) return;
      st.current = null;
      if (!s.active) return;
      const velocity = Math.abs(e.clientX - s.lastX) / Math.max(1, performance.now() - s.lastT);
      const dir = s.dx > 0 ? 'right' : 'left';
      const commit = (Math.abs(s.dx) >= threshold || velocity > 0.11) && ((dir === 'right' && onRight) || (dir === 'left' && onLeft));
      settle(s.dx, 0, () => { if (under.current) under.current.style.opacity = '0'; if (commit) (dir === 'right' ? onRight : onLeft)?.(); });
    },
    onPointerCancel: () => { const s = st.current; st.current = null; if (s?.active) settle(s.dx, 0, () => { if (under.current) under.current.style.opacity = '0'; }); },
  };
  return { bind, face, under, isDragging: () => Boolean(st.current?.active) };
}
