import { Suspense, lazy, memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useShallow } from 'zustand/react/shallow';
import type { Message } from '@/lib/types';
import { fmtTokens, fmtUsd, relTime, shortModelName } from '@/lib/format';
import { useApp } from '@/store/app';
import { scrollMemory, siblingInfo, useChat, useStream } from '@/store/chat';
import { db } from '@/lib/db';
import { useModels } from '@/store/models';
import { useUI } from '@/store/ui';
import { Button, IconButton, Icons, useLongPress } from './ui';
import { PlainFallback } from './MarkdownFallback';

const Markdown = lazy(() => import('./Markdown'));

// ---------------- Reasoning ----------------
function ReasoningBlock({ text, streaming, contentStarted, tokens, cost }: { text: string; streaming: boolean; contentStarted: boolean; tokens?: number; cost?: number }) {
  const showDefault = useApp((s) => s.settings.ui.showReasoningByDefault);
  const [open, setOpen] = useState(showDefault);
  const userTouched = useRef(false);
  useEffect(() => {
    if (userTouched.current) return;
    if (streaming && !contentStarted) setOpen(true);
    else if (streaming && contentStarted && !showDefault) setOpen(false);
    else if (!streaming) setOpen(showDefault);
  }, [streaming, contentStarted, showDefault]);
  if (!text && !tokens) return null;
  if (!text) return <div className="mb-3 text-sm text-ink2"><span className="num">Reasoned for {fmtTokens(tokens ?? 0)} tokens</span> · trace not returned by this provider</div>;
  return (
    <div className="mb-3">
      <button type="button" onClick={() => { userTouched.current = true; setOpen((v) => !v); }} className="chrome pressable inline-flex min-h-[32px] items-center gap-1.5 text-sm text-ink2">
        <span className={streaming && !contentStarted ? 'text-accent' : ''}>{streaming && !contentStarted ? 'Thinking' : 'Reasoning'}</span>
        {tokens != null && <span className="num">· {fmtTokens(tokens)} tokens{cost != null && cost > 0 ? ` · ${fmtUsd(cost)}` : ''}</span>}
        {open ? <Icons.chevronUp size={14} /> : <Icons.chevronDown size={14} />}
      </button>
      <div className={`disclosure ${open ? 'is-open' : ''}`} aria-hidden={!open}>
        <div><div className={`msg-reasoning selectable mt-1 ${streaming && !contentStarted ? 'caret' : ''}`}>{text}</div></div>
      </div>
    </div>
  );
}

// ---------------- One message ----------------
const MessageRow = memo(function MessageRow({ id, onMenu }: { id: string; onMenu: (id: string) => void }) {
  const m = useChat((s) => s.messages[id]);
  const messages = useChat((s) => s.messages);
  const streamId = useStream((s) => s.id);
  const isStreaming = streamId === id;
  const live = useStream(useShallow((s) => (isStreaming ? { content: s.content, reasoning: s.reasoning, ct: s.completionTokens, rt: s.reasoningTokens, est: s.estCost, retryAt: s.retryAt, retryReason: s.retryReason, firstTokenAt: s.firstTokenAt, startedAt: s.startedAt } : null)));
  const model = useModels((s) => (m?.modelId ? s.byId.get(m.modelId) : undefined));
  const showCosts = useApp((s) => s.settings.ui.showCosts);
  const lp = useLongPress(() => onMenu(id));
  const sib = useMemo(() => siblingInfo(messages, id), [messages, id]);
  const switchBranch = useChat((s) => s.switchBranch);
  const continueFrom = useChat((s) => s.continueFrom);
  const retryMessage = useChat((s) => s.retryMessage);
  const regenerate = useChat((s) => s.regenerate);
  const generating = useChat((s) => s.generating);
  const openSheet = useUI((s) => s.openSheet);
  const navigate = useUI((s) => s.navigate);
  if (!m) return null;

  const content = isStreaming ? live!.content : m.content;
  const reasoning = isStreaming ? live!.reasoning : (m.reasoning ?? '');
  const contentStarted = content.length > 0;

  if (m.role === 'user') {
    return (
      <div className="mx-auto w-full max-w-[720px] px-[var(--msg-pad)] pt-[var(--msg-gap)]" {...lp}>
        <div className="msg-user-row"><div className="msg-user selectable">
          {m.attachments?.length ? (
            <div className="chrome mb-2 flex flex-wrap gap-2">
              {m.attachments.map((a) => a.kind === 'image'
                ? <img key={a.id} src={a.dataUrl} alt={a.name} className="max-h-[220px] rounded-lg border border-rule object-cover" />
                : <span key={a.id} className="inline-flex items-center gap-1.5 rounded-md border border-rule px-2 py-1 text-sm text-ink2"><Icons.file size={14} />{a.name}</span>)}
            </div>
          ) : null}
          {m.content}
        </div></div>
        {sib.count > 1 && <div className="flex justify-end"><BranchNav index={sib.index} count={sib.count} onPrev={() => void switchBranch(id, -1)} onNext={() => void switchBranch(id, 1)} disabled={generating} /></div>}
      </div>
    );
  }

  const usage = m.usage;
  const rt = isStreaming ? live!.rt : usage?.reasoningTokens;
  const pReason = model ? Number(model.pricing.internal_reasoning || model.pricing.completion) : 0;
  return (
    <div className="mx-auto w-full max-w-[720px] px-[var(--msg-pad)] pt-[var(--msg-gap)]" {...lp}>
      <div className="chrome mb-2 flex items-center gap-2 text-sm text-ink2">
        <span className={isStreaming ? 'text-accent' : ''}>{shortModelName(model, m.modelId)}</span>
        {!isStreaming && <span className="num">{relTime(m.createdAt)}</span>}
        {isStreaming && live!.retryAt && <Countdown until={live!.retryAt} reason={live!.retryReason} />}
        {isStreaming && !live!.retryAt && !live!.firstTokenAt && <span className="pulse">Waiting for first token</span>}
      </div>
      <ReasoningBlock text={reasoning} streaming={isStreaming} contentStarted={contentStarted} tokens={rt} cost={rt != null ? rt * pReason : undefined} />
      {(content || isStreaming) && (
        <div className="msg-assistant">
          <Suspense fallback={<PlainFallback content={content} streaming={isStreaming} />}>
            <Markdown content={content} streaming={isStreaming} />
          </Suspense>
        </div>
      )}
      {!isStreaming && m.status === 'error' && (
        <div className="chrome mt-2 rounded-lg border border-rule bg-raised p-3 text-sm">
          <div className="text-accent">Request failed{m.error?.code ? ` (${m.error.code})` : ''}</div>
          <div className="mt-1 whitespace-pre-wrap text-ink">{m.error?.message}</div>
          <ErrorActions m={m} onRetry={() => void retryMessage(id)} onModel={() => openSheet({ kind: 'picker', title: 'Retry with a different model', onPick: (mid) => void regenerate(id, mid) })} onKey={() => navigate({ name: 'settings', section: 'connection' })} onProvider={() => openSheet({ kind: 'chatSettings' })} disabled={generating} />
        </div>
      )}
      {!isStreaming && m.status === 'interrupted' && (
        <div className="chrome mt-2 flex flex-wrap items-center gap-2 text-sm">
          <span className="text-ink2">{m.error?.message ?? 'Interrupted'}</span>
          <Button kind="outline" className="!min-h-[36px] !px-3 text-sm" onClick={() => void continueFrom(id)} disabled={generating}>Continue</Button>
          <Button kind="text" className="!min-h-[36px] !px-2 text-sm" onClick={() => void regenerate(id)} disabled={generating}>Regenerate</Button>
        </div>
      )}
      {!isStreaming && m.status === 'complete' && m.error?.code === 'length' && (
        <div className="chrome mt-2 flex flex-wrap items-center gap-2 text-sm">
          <span className="text-ink2">Hit the output limit</span>
          <Button kind="outline" className="!min-h-[36px] !px-3 text-sm" onClick={() => void continueFrom(id)} disabled={generating}>Continue</Button>
        </div>
      )}
      <div className="chrome mt-2 flex min-h-[28px] items-center gap-3 text-sm text-ink2">
        {showCosts && (isStreaming
          ? <span className="num">{fmtTokens(live!.ct)} tokens · {fmtUsd(live!.est, { estimate: true })}</span>
          : usage && <span className="num" title={usage.authoritative ? 'From OpenRouter' : usage.estimated ? 'Estimated' : 'From the stream'}>{fmtTokens(usage.completionTokens)} tokens · {fmtUsd(usage.costUsd, { estimate: usage.estimated })}</span>)}
        {sib.count > 1 && <BranchNav index={sib.index} count={sib.count} onPrev={() => void switchBranch(id, -1)} onNext={() => void switchBranch(id, 1)} disabled={generating} />}
        {!isStreaming && <span className="flex-1" />}
        {!isStreaming && <IconButton icon={Icons.more} label="Message actions" onClick={() => onMenu(id)} size={16} className="!min-h-8 !min-w-8" />}
      </div>
    </div>
  );
});

function Countdown({ until, reason }: { until: number; reason: string | null }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 250); return () => clearInterval(t); }, []);
  const s = Math.max(0, Math.ceil((until - now) / 1000));
  return <span className="text-accent">Retrying in {s}s{reason ? ` · ${reason.slice(0, 80)}` : ''}</span>;
}

function ErrorActions({ m, onRetry, onModel, onKey, onProvider, disabled }: { m: Message; onRetry: () => void; onModel: () => void; onKey: () => void; onProvider: () => void; disabled: boolean }) {
  const code = m.error?.code ?? '';
  const b = '!min-h-[36px] !px-3 text-sm';
  return (
    <div className="mt-3 flex flex-wrap gap-2">
      {code === '401' && <Button kind="primary" className={b} onClick={onKey}>Fix API key</Button>}
      {code === '402' && <a href="https://openrouter.ai/settings/credits" target="_blank" rel="noopener noreferrer" className="inline-flex min-h-[36px] items-center rounded-lg bg-accent px-3 text-sm text-onaccent">Add credits</a>}
      {code !== '401' && code !== '403' && <Button kind="outline" className={b} onClick={onRetry} disabled={disabled}>Retry</Button>}
      {code !== '401' && code !== '402' && <Button kind="text" className={b} onClick={onModel} disabled={disabled}>Different model</Button>}
      {(code === '502' || code === '408' || code === '504' || code === '503') && <Button kind="text" className={b} onClick={onProvider}>Routing</Button>}
    </div>
  );
}

function BranchNav({ index, count, onPrev, onNext, disabled }: { index: number; count: number; onPrev: () => void; onNext: () => void; disabled: boolean }) {
  return (
    <span className="chrome inline-flex items-center text-sm text-ink2">
      <button type="button" className="tap !min-w-8 !min-h-8 px-1" onClick={onPrev} disabled={disabled || index <= 0} aria-label="Previous version">‹</button>
      <span className="num">{index + 1}/{count}</span>
      <button type="button" className="tap !min-w-8 !min-h-8 px-1" onClick={onNext} disabled={disabled || index >= count - 1} aria-label="Next version">›</button>
    </span>
  );
}

// ---------------- The list ----------------
const WINDOW = 60;

/**
 * Native scroller with DOM windowing instead of virtualisation.
 * Virtualisers re-measure a growing row on every streamed frame and correct the scroll offset,
 * which reads as shaking on iOS. Here nothing moves unless we set scrollTop ourselves, once per frame.
 */
export function MessageList({ onMenu, jumpTo }: { onMenu: (id: string) => void; jumpTo?: string | null }) {
  const path = useChat((s) => s.path);
  const chatId = useChat((s) => s.chat?.id);
  const pinned = useChat((s) => s.pinned);
  const setPinned = useChat((s) => s.setPinned);
  const generating = useChat((s) => s.generating);
  const streamLen = useStream((s) => s.content.length + s.reasoning.length);
  const el = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const programmatic = useRef(false);
  const raf = useRef(0);
  const [showJump, setShowJump] = useState(false);
  const [from, setFrom] = useState(() => Math.max(0, path.length - WINDOW));
  const restored = useRef<string | null>(null);

  const visible = useMemo(() => path.slice(from), [path, from]);

  const scrollToEnd = useCallback(() => {
    if (raf.current) return;
    raf.current = requestAnimationFrame(() => {
      raf.current = 0;
      const n = el.current; if (!n) return;
      programmatic.current = true;
      n.scrollTop = n.scrollHeight;
    });
  }, []);

  // New chat or route change: reset the window and restore position.
  useLayoutEffect(() => {
    if (!chatId || restored.current === chatId) return;
    restored.current = chatId;
    const target = jumpTo ? path.indexOf(jumpTo) : -1;
    const start = target >= 0 ? Math.max(0, Math.min(target - 5, path.length - WINDOW)) : Math.max(0, path.length - WINDOW);
    setFrom(start);
    const saved = scrollMemory.get(chatId) ?? useChat.getState().chat?.scrollTop;
    requestAnimationFrame(() => {
      const n = el.current; if (!n) return;
      if (target >= 0) { document.getElementById(`m-${jumpTo}`)?.scrollIntoView({ block: 'start' }); setPinned(false); return; }
      if (saved != null && saved < n.scrollHeight - n.clientHeight - 40) { programmatic.current = true; n.scrollTop = saved; setPinned(false); }
      else { setPinned(true); scrollToEnd(); }
    });
  }, [chatId, path, jumpTo, scrollToEnd, setPinned]);

  // Keep the tail in view while pinned; content growth below the fold never moves the viewport otherwise.
  useEffect(() => { if (pinned) scrollToEnd(); }, [streamLen, path.length, visible.length, pinned, scrollToEnd]);
  useEffect(() => { if (generating) { setPinned(true); scrollToEnd(); } }, [generating, setPinned, scrollToEnd]);
  // Content can grow by a stream frame, a persisted flush, or a lazy markdown chunk landing; observe the wrapper, not the sources.
  useEffect(() => {
    const n = inner.current; if (!n || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => { if (useChat.getState().pinned) scrollToEnd(); });
    ro.observe(n);
    return () => ro.disconnect();
  }, [scrollToEnd]);
  useEffect(() => {
    const on = () => { if (useChat.getState().pinned) setTimeout(scrollToEnd, 50); };
    window.addEventListener('quire:viewport', on);
    return () => window.removeEventListener('quire:viewport', on);
  }, [scrollToEnd]);

  const onScroll = useCallback(() => {
    const n = el.current; if (!n) return;
    const atBottom = n.scrollHeight - n.clientHeight - n.scrollTop < 48;
    if (programmatic.current) programmatic.current = false; else setPinned(atBottom);
    setShowJump((v) => (v !== !atBottom ? !atBottom : v));
    if (chatId) scrollMemory.set(chatId, n.scrollTop);
  }, [chatId, setPinned]);

  // Reveal earlier messages without the viewport jumping (Safari has no scroll anchoring).
  const showEarlier = useCallback(() => {
    const n = el.current; if (!n) return;
    const before = n.scrollHeight;
    setFrom((f) => Math.max(0, f - WINDOW));
    requestAnimationFrame(() => { const m = el.current; if (!m) return; programmatic.current = true; m.scrollTop += m.scrollHeight - before; });
  }, []);

  useEffect(() => {
    const save = () => { if (!chatId) return; const off = scrollMemory.get(chatId); if (off != null && useChat.getState().persisted) void db.chats.update(chatId, { scrollTop: off }); };
    document.addEventListener('visibilitychange', save);
    return () => { document.removeEventListener('visibilitychange', save); save(); };
  }, [chatId]);

  return (
    <div className="relative min-h-0 flex-1">
      <div ref={el} id="messages" className="scroll h-full" onScroll={onScroll} style={{ overscrollBehavior: 'contain', overflowAnchor: 'none' }}>
        <div ref={inner}>
        {from > 0 && (
          <button type="button" onClick={showEarlier} className="pressable mx-auto my-3 flex min-h-[36px] items-center rounded-full border border-rule px-3 text-sm text-ink2">
            Show {Math.min(WINDOW, from)} earlier of {from}
          </button>
        )}
        {visible.map((id) => <div key={id} id={`m-${id}`}><MessageRow id={id} onMenu={onMenu} /></div>)}
        <div className="h-6" />
        </div>
      </div>
      <div className={`pill-wrap absolute bottom-3 left-1/2 -translate-x-1/2 ${showJump ? 'is-on' : ''}`} aria-hidden={!showJump}>
        <button type="button" tabIndex={showJump ? 0 : -1} onClick={() => { setPinned(true); scrollToEnd(); }} className="chrome pressable flex min-h-[36px] items-center gap-1.5 rounded-full border border-rule bg-raised px-3 text-sm text-ink shadow-[0_6px_20px_rgb(0_0_0/.3)]" aria-label="Jump to latest">
          <Icons.down size={14} /> {generating ? 'Streaming' : 'Latest'}
        </button>
      </div>
    </div>
  );
}
