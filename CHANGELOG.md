# Changelog

One entry per milestone, in build order. "Verified" means exercised by `scripts/e2e.py` against the production build; "implemented" means written per spec but needing a real device or the live API to confirm.

## M1 — Shell

Installs as a PWA with manifest, generated icons (192, 512, 512 maskable, opaque 180 apple-touch), six iPhone splash screens, and `apple-mobile-web-app-*` meta. Layout uses `100dvh`, safe-area insets on the header and composer, `visualViewport` tracking that pins the composer above the keyboard, `overscroll-behavior: none` on the shell, and 16px inputs so Safari does not zoom. Dark and light token sets, system typefaces, reduced-motion support. Service worker precaches the shell, uses NetworkOnly for `openrouter.ai/api`, and shows an update bar instead of reloading under the user. Strict CSP injected at build. Initial JS 125 KB gzipped. Verified: shell boots, theme applies, no console errors; keyboard and safe-area behaviour implemented, not device-tested.

## M2 — Talk to OpenRouter

Settings → Connection accepts a pasted key (show/hide, replace, remove), runs the OAuth PKCE flow, and reads `/key` for label, usage, limit and rate limit. Model catalogue loads cache-first from IndexedDB, refreshes after six hours, and diffs new ids. Picker sheet with fuzzy search over id/name/description, capability chips (vision, files, tools, reasoning, structured), price bands, context filter, provider select, Recent/Favourites/All, star to favourite, long-press for a full model card (pricing, limits, supported parameters, Set as default). Non-streaming send works, chats and messages persist, chat list shows title/preview/model/time. Verified: key entry, key metadata, picker search, model switching, persistence across reload.

## M3 — Streaming

`fetch` + reader SSE parser: handles `: OPENROUTER PROCESSING` comments, lines split across packets, `[DONE]`, and error objects mid-stream. Tokens are buffered and committed once per animation frame; markdown re-parses at most every 60 ms with open code fences auto-closed so blocks never flash as raw text. Reasoning trace streams in its own collapsible block, expanded while thinking and collapsed when the answer begins. Stop shares the send button and keeps partial text. The list autoscrolls only while pinned to the bottom; scrolling up releases it and a "Latest" pill appears. Assistant text is flushed to IndexedDB every 500 ms; a background/abort marks the message interrupted with Continue and Retry. 429/408/5xx auto-retry with a visible countdown. Verified: streaming with reasoning, markdown with highlighted code, keep-alive handling, split chunks, stop state machine.

## M4 — Settings that respect the model

Every generation control is gated on `supported_parameters`; the table (with help text and ranges) lives in `src/lib/params.ts`. Reasoning controls switch between effort, budget and off according to a per-family mapping with a show-both fallback. Advanced routing (sort, deny data collection, require parameters, fallbacks, ignore list, fallback models), web search plugin with cost note, middle-out with a warning, `max_tokens` with a "Max" button from `top_provider`, seed with a dice, stop sequences. Precise/Balanced/Creative presets with a "Custom" drift indicator. An "unsupported" list shows what is stored but not sent. Verified: temperature hidden on `o4-mini`, reasoning control shown, presets applied.

## M5 — Prompts, presets, and per-chat overrides

Global system prompt. Personas: name, icon, prompt, optional pinned model, partial settings; create, edit, duplicate, delete, export and import as JSON. Per-chat settings sheet shows effective values with a dot on anything set for this chat, an Inherit button per control, an inline system-prompt override, and Reset. Resolution order is global → persona → chat. Long-press the new-chat button to start from a persona. Verified: quick settings sheet, override dots, persona pick path.

## M6 — Memory

Flat atomic facts with category, pinned, disabled, source chat and message. Extraction runs after a reply on `requestIdleCallback`, batched to every three exchanges or 30 s, using a JSON `operations` protocol (`add`/`update`/`delete`) parsed defensively from whatever the model returns. Injection builds a budgeted `<user_memory>` block (pinned → keyword-relevant → newest) into the system message. Memory screen: grouped list, tap to edit inline, swipe to delete, pin/disable, add manually, jump to source, character budget bar, typed "clear" confirmation, extraction model picker. Per-chat memory toggle gives incognito. Verified: fact extracted from a chat appears in the memory screen and is present in the next request's system message.

## M7 — Conversation management

Branching via `parentId`: edit-and-resend and regenerate create siblings with a ‹ n/m › switcher; branch-from-here copies to a new chat. Message menu: copy, copy as markdown, edit and resend, regenerate, regenerate with another model, branch, share thread, show raw, tokens and cost, show the exact request sent, delete (with descendants). Chat list: Today/Yesterday/This week/Earlier, pinned section, collapsible folders (long-press to rename/delete), swipe left to archive with undo toast, swipe right to pin, long-press for multi-select with move/archive/export/delete, archived view, search across every message with highlighted snippets that jump to the message. Export all or one chat as JSON (via the share sheet when installed) or markdown; import with merge or replace. Verified: list grouping, bulk actions path, search, export bundle shape, import round-trip in unit form.

## M8 — Attachments

Attach button offers library, camera and file. Images are downscaled on a canvas to ≤1568 px and stored as base64; PDFs and text files are sent as file parts. Paste an image into the composer to attach it. Previews with remove in the composer; thumbnails in the message. Controls hide when the model lists no image or file input. Verified: gating; upload shape implemented against the spec, unverified against the live API.

## M9 — Polish

Light theme as its own palette with `theme-color` for both schemes. Storage estimate and persistence status in Settings → Data with a request button; backup nudge after 30 days or 200 messages; offline bar; update bar that waits for the current reply. Live cost estimate → streamed `usage.cost` → authoritative `/generation` reconciliation, per-chat and per-day totals in the list, status strip and under each reply. Context meter with a warning near the limit. Empty states for no key, no chats, no memory. Typed confirmations for wipe/replace/clear. Reduced-motion. Two-pane layout above 900 px. Verified: authoritative cost replaces estimate in the reply, the row and the day total; desktop layout.

## Not started

§16 stretch features.

## R2 — Interface rewrite and device bug fixes

Fixed the two bugs reported from an iPhone: input text was painted in the background colour (a Tailwind `text-base` colour/size collision; size token renamed to `text-body`, inputs given explicit ink colour), and the interface shook during streaming (virtualiser and autoscroll fighting over the offset; replaced by a native windowed scroller pinned by a `ResizeObserver`). Rebuilt the interface on the animations.dev skills: motion tokens, press feedback on `:active`, transitions over keyframes, hover gated to fine pointers, reduced-motion that keeps comprehension aids. Sheets moved to Vaul, dialogs to Radix, toasts to Sonner. Swipe gestures track 1:1 with pointer capture, rubber-band, and commit on flick velocity. Reasoning trace collapses with an animation; send/stop crossfades. Reasoning effort exposes OpenRouter's full unified scale per model family with the source of the list stated in the UI. Verified: typed text colour in both themes, zero scroll jitter across 255 sampled frames on an overflowing stream with the list pinned at the end, plus the full earlier flow. Not device-tested; the skills are vendored in `.agents/skills/`.

## R3 — New chat, reasoning display, user layer, defaults

New chat now opens a fresh chat (`/chat/new`, URL replaced with the real id after the first send). Reasoning traces render: the animated container collided with Tailwind's `collapse` utility, and the parser ignored `reasoning_details` when `reasoning` was an empty string. Restored the prose/code styles lost in R2. User messages are a right-aligned raised card in sans; replies stay full-width serif. Defaults are DeepSeek V4 Flash 0731 and GLM 5.3 Flash, resolved against the live catalogue by name and migrated on existing installs. Verified end to end, including a cold launch resuming the newest chat.
