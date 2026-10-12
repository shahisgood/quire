# Decisions

Choices made in porting Quire from the PWA to native SwiftUI, one line of reasoning each. Behaviour not mentioned here was ported as the PWA's own `DECISIONS.md` and `CHANGELOG.md` describe it: the reasoning-family table, cost reconciliation, memory extraction and injection, title generation, default-model hints, the backup format.

## Platform and build

- **iOS 26 only**, as requested. Navigation bars, toolbars and sheets get Liquid Glass from the system; the composer, toasts, the jump-to-latest pill and primary buttons use `glassEffect` and the glass button styles explicitly.
- **XcodeGen instead of a committed `.xcodeproj`.** The project is generated in CI from `project.yml`, so it can't drift or be hand-edited wrong.
- **Built on GitHub Actions (`macos-26`), unsigned.** Signing happens at install time with Sideloadly, AltStore or SideStore and the user's own Apple ID, so no certificates or secrets live in the repo.
- **Swift 5 language mode, main-actor-by-default, approachable concurrency.** The code was written where no Swift compiler could be installed, so Swift 5 mode keeps concurrency diagnostics as warnings for the first builds. Value types are marked `nonisolated` so their Codable/Hashable conformances can be used anywhere. **Flip `SWIFT_VERSION` to `6.0` once a build log is clean.**
- **No third-party packages.** Markdown, highlighting, storage, charts and networking use Foundation, SwiftUI, UIKit, ImageIO, Network and Charts only.

## Data

- **JSON files, not SwiftData.** The on-disk format is the PWA's backup format split into files (`chats.json`, `messages/<chatId>.json`, `presets.json`, `memory.json`, `folders.json`…), so import and export are a straight copy with no migration layer.
- **Lenient decoding everywhere.** A missing or mistyped field falls back to a default instead of failing the file, because the other side of an import may be an older or newer build of either app.
- **Writes are coalesced per file for 300 ms**, then encoded and written off the main thread in order. Dragging a slider or streaming a reply never rewrites a file dozens of times a second. Everything is flushed before export, search and backgrounding.
- **Per-chat export carries only those chats** and the personas they use, never memory or settings. The PWA put everything into a single-chat export; sharing a chat shouldn't share what you've told the app about yourself. Full backups are unchanged.
- **Import merge rules are the PWA's:** chats, messages, folders and personas by id; memory added only when the text is new; day costs only for days not already present. "Replace" asks you to type "replace".

## Security

- **The API key lives in the Keychain** (`AfterFirstUnlockThisDeviceOnly`), never in the settings file. Backups include it only if you switch on "Include API key".
- **Sign in with OpenRouter uses the code-display PKCE flow**, where openrouter.ai shows a code to paste back. OpenRouter's docs don't mention custom URL schemes, so a `quire://` callback could fail in ways that are hard to diagnose.
- **`HTTP-Referer`** is the Quire GitHub repository, so requests are attributed to Quire on the OpenRouter activity page.

## Streaming and lifecycle

- **One stream engine per chat (`ChatSession`), kept alive while it streams.** You can go back to the list or open settings mid-reply. Idle sessions are dropped when another chat opens.
- **The live reply is published at most 20 times a second** and persisted every 1.5 s and at the end. Inline Markdown is cached per paragraph, so a long reply only re-parses the paragraph that's still growing.
- **Backgrounding doesn't abort the stream immediately.** The PWA aborted because Safari suspends the page; a native app gets about 30 seconds of background time, and only if that runs out is the reply cancelled and kept as "interrupted".
- **Autoscroll follows new text only while you're near the bottom.** Scrolling up to read stops the follow; a glass "Latest" pill brings it back. Long chats show the last 40 messages with "Show earlier", the native equivalent of the PWA's windowing, which keeps scroll positions stable.

## Interface

- **The reading object, made native.** Replies are typeset in New York (or SF, if you choose Sans) under a small-caps folio line with the model's name and a hairline rule; your messages are raised hairline cards. Large titles throughout use the serif. One periwinkle accent marks what's alive: the streaming cursor (the same mark as the app icon), the send button, current selections.
- **Settings is a dashboard first.** Account status with remaining credit, today/7-day/30-day spending with a 14-day chart, then sections that each show their state in one line, so most questions are answered without opening anything.
- **Help is one tap away.** Every generation control has an (i) that reveals what it does, in the PWA's words.
- **Destructive actions are tiered.** Archive is instant with Undo; deleting a chat or message asks once; erasing everything, replacing on import, and clearing memory ask you to type a word.
- **Text size follows Dynamic Type**, and "Reply size" shifts replies relative to it rather than overriding it.
- **Haptics are on by default.** The PWA's toggle couldn't work in iOS Safari; here it does. Importing a PWA backup keeps this device's haptics setting.
- **Math is shown as TeX source** in a labelled card, copyable. Native math typesetting would need a third-party renderer; it's the most visible gap left.
- **"Select text" opens a sheet with real range selection** (a read-only text view), because SwiftUI's text selection on iOS copies only whole strings and would fight the message context menu.

## Not verified

- **Not compiled before the first CI run.** No Swift toolchain could be installed where this was written (the download hosts and container registries were unreachable). Every file passes a Swift grammar check, and the code was reviewed line by line for type and isolation errors, but expect a round or two of compiler errors on the first builds. The workflow prints just the `error:` lines to paste back.
- **Not run against live OpenRouter or a real iPhone.** Request and response shapes are ported from the PWA, and the PWA's list of likely drift points (file attachment shape, `reasoning_details`, `usage.cost`, `/key` fields) applies unchanged.
- **Default model ids** (`deepseek/deepseek-v4-flash-0731`, `z-ai/glm-5.3-flash`) are the PWA's guesses, resolved against the live catalogue by name pattern exactly as in the PWA.
