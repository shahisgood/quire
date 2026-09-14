# Decisions

One line of reasoning each, as required by §15, followed by every other choice made where the spec left room or where the build environment forced a substitution.

## The seven required decisions

1. **Viewport zoom.** `maximum-scale` is **not** set. Every input is ≥16px, which is what actually stops Safari's focus zoom, and pinch-zoom stays available for accessibility. Standalone mode disables pinch anyway, so the tag would have bought nothing there.

2. **Markdown and highlighting.** `react-markdown` 10 + `remark-gfm` + `remark-math` + `rehype-katex` (with `katex`), and `highlight.js/lib/core` with 20 languages registered from lazy chunks. All of it lives in a lazy `Markdown` chunk (132 KB gz, plus 8 KB CSS) that loads after first paint behind a plain-text fallback; the eager bundle is **125 KB gz** against the 200 KB budget. `shiki` was rejected for its grammar payload; `marked`+DOMPurify for the HTML-string surface it opens.

3. **Palette and type, as tokens.** Dark: `base #0e1013`, `raised #171a1f`, `ink #e8e6e1`, `ink2 #8e9299`, `rule #262a31`, `accent #9aa8ff`, `onaccent #0e1013`. Light: `base #f6f6f3`, `raised #ffffff`, `ink #1b1d21`, `ink2 #5f646c`, `rule #dcdcd6`, `accent #3450c8`, `onaccent #ffffff`. Type: `font-ui` = system sans (SF on iOS), `font-read` = `ui-serif` (New York on iOS) for assistant prose with a Sans toggle, `font-mono` = `ui-monospace` (SF Mono). System stacks cost zero bytes and render identically to native apps; a web font would have been the single largest asset.

4. **Passphrase encryption of the key.** **Not implemented.** Deriving a key from a passphrase to encrypt a secret that is decrypted into the same origin's memory on every launch adds a prompt on each open without keeping the key from anything that can read the origin; the honest plain-storage note in Settings → Connection is more truthful than a lock icon would be.

5. **Reasoning-control style.** Explicit regex mapping on the model id (`o1|o3|o4|gpt-5` → effort, cannot disable; `claude` → budget or effort; `gemini.*(thinking|2\.5)` → budget; `deepseek-r1|qwq|qwen3` → budget/effort, always-on), used only when `supported_parameters` includes `reasoning` or `include_reasoning`. Fallback for unknown families: show **both** effort and budget with the effort default, on the reasoning that OpenRouter normalises either into the provider's native form. Table is in `src/lib/params.ts` (`detectReasoningStyle`) and is meant to be edited.

6. **Search.** Naive lowercase scan of a stored `lc` field on user messages (assistant text is scanned too, but only user text is indexed by `lc` for the common case), run in 120 ms debounced batches off the Dexie table. Benchmarked reasoning: a linear scan of 5,000 messages of ~500 chars is ~2.5 MB of `indexOf`, well under a frame on an A-series chip. **Replace at ~5,000 messages** with a trigram table (`messageId, trigram`) maintained on write; the seam is `searchMessages()` in `src/lib/data.ts`.

7. **Drift from the live OpenRouter docs.** **Could not be verified.** The build sandbox has no route to `openrouter.ai`, so §4 was implemented as written and every request shape is exercised only against a mock (`scripts/e2e.py`). Items most likely to have drifted, in order of risk:
   - File attachments are sent as `{ type: 'file', file: { filename, file_data: <data URL> } }`. If the live shape differs, only `partsForMessage()` in `src/store/chat.ts` changes.
   - `reasoning_details` is parsed as an array of `{ type, text|summary }`; unknown shapes are ignored, so a change degrades to "no trace" rather than a crash.
   - The `usage.cost` field on the final streamed chunk is trusted as an estimate and always superseded by `GET /generation` (`total_cost`) — if `cost` is absent nothing breaks.
   - OAuth: `https://openrouter.ai/auth?callback_url=…&code_challenge=…&code_challenge_method=S256` then `POST /api/v1/auth/keys` with `{ code, code_verifier, code_challenge_method }`, reading `key` from the response.
   - `/api/v1/key` fields read: `label, usage, limit, limit_remaining, is_free_tier, rate_limit.{requests,interval}`.
   - 429 responses honour `Retry-After` when present, otherwise exponential backoff 1 s → 8 s, three attempts.

## Other choices

- **Name:** Quire — a gathering of sheets bound together; it is a reading object, which is the design brief.
- **No router library.** A 60-line history-backed router in `src/store/ui.ts` handles five routes and bottom-sheet back-swipes; react-router would have cost more than the whole UI store.
- **Zustand stores split by lifetime:** `app` (settings), `models` (catalogue), `chats` (lists), `chat` (the open thread + stream engine), `ui` (route, sheets, dialogs, toasts). The stream buffer is its own store (`useStream`) updated once per animation frame so the message list never re-renders per token.
- **Unpersisted new chats.** A new chat exists only in memory until its first send, so the list never fills with empty chats. The draft is still saved (to the chat once persisted, or dropped with the unsent chat).
- **Message persistence cadence:** the streaming assistant row is flushed to IndexedDB at most every 500 ms and on stop/abort/visibility change, which bounds data loss to half a second.
- **Cost pipeline:** live estimate from token counts × catalogue price → `usage.cost` from the final chunk → `GET /generation` (retried 3× with backoff, since it lags a few seconds) applied as a *delta* to the chat and day totals so partial states never double-count.
- **Titles** are generated once, from the first exchange, via a non-streaming call to the extraction model; a manual rename sets `titleAuto=false` and is never overwritten.
- **Memory extraction** batches every exchange since the last run and fires when three exchanges have accumulated or 30 s have passed, after the reply is rendered, on `requestIdleCallback`. Failures are logged and dropped; the chat never waits.
- **Injection** goes in the system message inside `<user_memory>…</user_memory>` with instructions not to announce it; pinned first, then keyword-relevance to the latest user message, then recency, within `maxInjectedChars`.
- **Middle-out** is off by default with a warning; silent truncation is worse than an error the user can act on.
- **Provider routing** defaults to `require_parameters: true` and `allow_fallbacks: true`; `data_collection: deny` is opt-in because it removes cheap providers.
- **Default models:** `anthropic/claude-sonnet-4` for chat, `openai/gpt-4o-mini` for titles and extraction. Both are settings; if an id is missing from the catalogue, the settings screen says so instead of failing quietly.
- **CSP** is injected at build time only (`vite.config.ts`), so the dev server keeps HMR. There is no inline script in `index.html`; the pre-paint theme is applied at the top of `main.tsx` from `localStorage`, which costs one frame of dark background (the manifest `background_color` and splash images are dark, so nothing flashes).
- **Service worker:** `registerType: 'prompt'`. The update bar defers "Reload" while a reply is streaming and applies afterwards. API calls are excluded from every cache; the model catalogue is cached in IndexedDB, not the SW.
- **Haptics:** `navigator.vibrate` where it exists; on iOS the toggle stays visible with a note that Safari does not expose haptics to web apps, rather than hiding the setting and making the user wonder.
- **Attachments** are downscaled on a canvas to ≤1568 px longest edge, JPEG 0.85, before storage and upload; originals are not kept.
- **Bulk delete of a chat** removes its messages in one transaction; deleting a message removes its descendants and, if the active leaf was among them, moves the leaf to the nearest surviving sibling or parent.
- **Icons and splash screens** are generated by `scripts/icons.py` (Pillow) from pure geometry; no font dependency, so the repo can regenerate them anywhere.
- **Testing** is `scripts/e2e.py`: a headless Chromium run on an iPhone 14 viewport against the production build, with OpenRouter fully mocked at the network layer including SSE keep-alives and split chunks. It exercises key entry, the picker, capability gating, streaming, markdown, reasoning, cost reconciliation, memory extraction and injection, the request snapshot, and persistence across reload, and fails on any console error.

## Not done in this environment

- No real iPhone was available, so the §14 checklist items that need a device (keyboard behaviour, safe areas in landscape, home-screen install, share sheet) are implemented per §9 but **unticked**.
- No network to `openrouter.ai`, so nothing was verified against live responses; see decision 7.
- Stretch features (§16) were not started.

---

# Revision 2 — interface rewrite (14 Sep 2026)

Changes made against two bugs reported from a real iPhone and the request to rebuild the interface on Emil Kowalski's design-engineering skills (`npx skills add emilkowalski/skill`; the skills are vendored in `.agents/skills/` and `.claude/skills/` so the next agent session starts with the same bar).

## Bug: typed text invisible in every input

**Cause.** A Tailwind naming collision, not a colour-scheme problem. The config defined a colour named `base` (the page background) *and* a font size named `base`, so the utility `text-base` generated both a `font-size` rule and a `color: var(--c-base)` rule, and the colour rule won the cascade. Every input styled with `text-base` painted its text in the background colour: dark on dark, light on light. It was invisible in the headless run because no test had typed into a field.

**Fix.** The size token is now `body` (`text-body`); the three places that meant the colour (active chips, the FAB) keep `text-base`. Inputs also get explicit `color` and `-webkit-text-fill-color: var(--c-ink)` plus `caret-color: var(--c-accent)`, so no future inheritance change can reproduce this. The harness now types into the composer and asserts the computed colour equals `--c-ink` in both themes.

## Bug: the whole interface shakes while a reply streams

**Cause.** The message list was a virtualiser (virtua) with dynamic row heights. Every streamed frame grew the last row; the virtualiser re-measured it and corrected the scroll offset; my autoscroll issued `scrollToIndex` *and* `scrollTo(scrollSize)` on the same frame; the corrections fired `onScroll`, which flipped the "pinned" flag, which triggered another scroll. Two systems disagreeing about the offset thirty times a second reads as shaking.

**Fix.** The list is now a native scroller. Virtualisation is replaced by DOM windowing: the last 60 messages are rendered, a "Show earlier" affordance reveals more and compensates the offset by hand (Safari has no scroll anchoring). Autoscroll is one `scrollTop = scrollHeight` write per animation frame, driven by a `ResizeObserver` on the content wrapper so it fires whether content arrived from a stream frame, a persisted flush, or the lazy markdown chunk landing — and only while pinned. Nothing else moves the viewport. The harness samples `scrollTop` every frame during a stream long enough to overflow the screen and fails on any drop that leaves the list away from the bottom; it also asserts the list ends pinned. **Consequence for the spec's "500-message chat scrolls smoothly" line:** it now holds because at most 60 rows are in the DOM, not because rows are recycled. If a chat with thousands of messages ever needs full recycling, the skills' pick is Virtuoso; the model picker still uses virtua for its static rows.

## Motion system (from the skills)

- Tokens in `:root`: `--ease-out: cubic-bezier(0.23, 1, 0.32, 1)`, `--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1)`, `--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1)`, durations 150/160/200/250/400 ms. Nothing animates on a keyboard-initiated or per-keystroke action; route changes don't animate.
- Press feedback is `transform: scale(.97)` on `:active` at 160 ms, on every pressable; the old opacity fade was removed because it reads as "disabled".
- Transitions, not keyframes, for the jump-to-latest pill, the reasoning collapse (grid-rows, no measuring), and the send/stop morph (scale + opacity crossfade, never from `scale(0)`).
- Hover styling exists only under `@media (hover: hover) and (pointer: fine)`.
- `prefers-reduced-motion` keeps opacity/colour transitions and drops movement; it does not zero everything as before.
- **Sheets: Vaul.** Real drag-to-dismiss with velocity, the iOS drawer curve, scroll-inside-content handled. `shouldScaleBackground` is off (the app is already full-bleed dark) and `repositionInputs` is off because Quire's own `visualViewport` handling owns the keyboard.
- **Dialogs: Radix Dialog** (already a Vaul dependency): focus trap, escape, `aria`; styled per the modal recipe (centred origin, `scale(.96)` + opacity, 250 ms, backdrop fades in step).
- **Toasts: Sonner**, headless-styled to Quire's surface tokens, top-centre under the safe area. The store's `toast()` API is unchanged; call sites didn't move.
- **Swipe rows** (chat list, memory) are a pointer-capture hook that writes `transform` on the element directly during the drag (no React render per frame), rubber-bands past the limit, commits on distance *or* a flick above 0.11 px/ms, and settles with a WAAPI ease-out. The skills prefer a spring for the settle; a WAAPI ease-out was chosen over adding `motion` (~30 KB gz) for two rows.
- Bundle: 157 KB gz initial (was 125); Vaul + Radix + Sonner cost ~32 KB against a 200 KB budget.

## Reasoning effort levels — where the list comes from

The effort choices are a **curated table keyed on the model id**, not data from OpenRouter. `/models` only reports whether a model accepts `reasoning`; it never enumerates levels. The table (in `detectReasoningStyle`) maps o-series → low/medium/high; GPT-5 → minimal→high; GPT-5.1-class and Codex → none→xhigh; Grok → low/high; R1 → a single level; Claude and Gemini → budgets with effort converted by OpenRouter. Unknown families are offered the whole unified scale. The UI states this next to the control. OpenRouter maps an unsupported level to the nearest one the provider accepts, so a wrong guess degrades to "close enough" rather than an error. The family lists reflect June-2026 knowledge and should be checked against OpenRouter's current reasoning documentation.
