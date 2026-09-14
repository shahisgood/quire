import { useUI } from '@/store/ui';

/**
 * In iOS standalone mode the layout viewport does not shrink when the keyboard opens;
 * the page is pushed instead. We size the root to the visual viewport and translate it
 * by the visual offset so the whole app appears pinned, with the composer directly on
 * the keyboard. Also pins window scroll to 0 so Safari can't mangle position.
 */
export function installViewportTracking(): () => void {
  const vv = window.visualViewport;
  const root = document.documentElement;
  let lastH = 0;
  let raf = 0;
  const apply = () => {
    raf = 0;
    const h = vv ? vv.height : window.innerHeight;
    const top = vv ? vv.offsetTop : 0;
    root.style.setProperty('--vvh', `${Math.round(h)}px`);
    root.style.setProperty('--vvt', `${Math.round(top)}px`);
    const kb = Math.max(0, window.innerHeight - h);
    root.style.setProperty('--kb', `${Math.round(kb)}px`);
    useUI.getState().setKeyboardOpen(kb > 120);
    if (window.scrollY !== 0) window.scrollTo(0, 0);
    if (h !== lastH) { lastH = h; window.dispatchEvent(new CustomEvent('quire:viewport', { detail: { height: h, keyboard: kb } })); }
  };
  const schedule = () => { if (!raf) raf = requestAnimationFrame(apply); };
  apply();
  vv?.addEventListener('resize', schedule);
  vv?.addEventListener('scroll', schedule);
  window.addEventListener('resize', schedule);
  window.addEventListener('orientationchange', schedule);
  window.addEventListener('scroll', schedule);
  return () => {
    vv?.removeEventListener('resize', schedule);
    vv?.removeEventListener('scroll', schedule);
    window.removeEventListener('resize', schedule);
    window.removeEventListener('orientationchange', schedule);
    window.removeEventListener('scroll', schedule);
  };
}
