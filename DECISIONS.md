# Decisions

Choices made in porting Quire from the PWA to native SwiftUI, one line of reasoning each. Behaviour that isn't mentioned here was ported as the PWA's `DECISIONS.md` describes it.

## Platform and build

- **iOS 26 only.** As requested. It also means Liquid Glass comes from the system: navigation bars and toolbars get it automatically, and the composer and the jump-to-latest pill use `glassEffect` / `.glass` explicitly.
- **XcodeGen instead of a committed `.xcodeproj`.** The project file is generated in CI from `project.yml`, so it can't drift or be hand-edited wrong. On a Mac, `xcodegen generate` makes it locally.
- **Built on GitHub Actions (`macos-26`), unsigned.** The workflow produces an unsigned IPA. Signing happens at install time with Sideloadly, AltStore or SideStore and the user's own Apple ID, so no certificates or secrets live in the repo.
- **Swift 5 language mode, main-actor-by-default, approachable concurrency.** The port was written without access to a compiler (the authoring environment is Linux, and Swift toolchains weren't downloadable there). Swift 5 mode turns concurrency diagnostics into warnings so the first builds aren't blocked on strict-checking edge cases. **Flip `SWIFT_VERSION` to `6.0` in `project.yml` once a build log is clean of concurrency warnings.**
- **No third-party packages.** Every dependency is an API surface that couldn't be checked before the first CI build. Markdown, storage and networking are written against Foundation, SwiftUI and UIKit only.

## Data

- **JSON files, not SwiftData.** The on-disk format is the PWA's backup format split into files (`chats.json`, `messages/<chatId>.json`, …). Import and export are a straight copy in either direction, with no migration layer and no `@Model` schema to version.
- **Every type decodes leniently.** A missing or mistyped field falls back to a default instead of failing the file, because the other side of an import may be an older or newer build of either app.
- **Writes are chained.** Each write waits for the previous one, so writes land in order. Encoding and file I/O run off the main thread, in an actor. `flush()` awaits the chain before export, search and backgrounding.
- **Backup sections without screens are preserved.** Personas, memory entries and folders from a PWA backup are stored untouched in `extras.json` and exported again. A chat created from a persona still gets that persona's system prompt and settings.
- **Search** is the PWA's linear lowercase scan, run off the main thread over the message files. It's fine to roughly 5,000 messages; the seam for an index is `Search.run` in `Core/Store.swift`.

## Security

- **The API key lives in the Keychain** (`AfterFirstUnlockThisDeviceOnly`), never in the settings file. Backups include it only if you switch on "Include API key". This is the one place the native app is meaningfully safer than the PWA, which had to keep the key in IndexedDB.
- **Sign in with OpenRouter uses the code-display PKCE flow.** OpenRouter documents a flow without a callback URL, where the user is shown a code to paste back. Its docs don't mention custom URL schemes, so relying on one (`quire://`) could fail in a way that's hard to diagnose. If OpenRouter confirms custom schemes work, `ASWebAuthenticationSession` with a callback is the upgrade.
- **`HTTP-Referer`** is set to the Quire GitHub repository, so requests are attributed to Quire on the OpenRouter activity page.

## Streaming and lifecycle

- **One stream engine per chat (`ChatSession`), kept alive while it streams.** You can go back to the list or open settings mid-reply and the stream continues. Idle sessions are dropped when another chat opens.
- **The live reply is published at most ~30 times a second** and persisted every 1.5 s and at the end. The PWA flushed every 500 ms; a chat file here can hold image data URLs, so writing it twice a second during a stream is wasteful.
- **Backgrounding doesn't abort the stream immediately.** The PWA aborted on `visibilitychange` because Safari suspends the page. A native app gets about 30 seconds of background time (`beginBackgroundTask`); the reply keeps streaming, and only if time runs out is it cancelled, keeping the partial text as "interrupted".
- **Autoscroll:** the list follows new text only while it's within 60 pt of the bottom, via `ScrollPosition.scrollTo(edge: .bottom)`. Scrolling up to read stops the follow, and a glass "Latest" pill brings it back. This is the same rule as the PWA's revision-2 fix, without the DOM workarounds.

## Interface

- **Palette and type** are the PWA's tokens as dynamic colours: dark base `#0e1013`, accent `#9aa8ff`, light base `#f6f6f3`, accent `#3450c8`. Replies render in New York (the system serif) by default, with a Sans option; the user's own messages are raised hairline cards, right-aligned, in SF.
- **Text size follows Dynamic Type**, replacing the PWA's own font-scale slider. The system setting already does this better and applies everywhere.
- **Haptics are on by default.** The PWA's toggle existed but did nothing on iOS Safari; here it works. Importing a PWA backup keeps this device's haptics setting rather than the web app's "off".
- **Markdown is a small hand-written block parser** plus `AttributedString(markdown:)` for inline syntax. It covers what models emit (headings, lists, tasks, tables, quotes, fences, rules, `$$` math) and tolerates partial input, since it re-parses a streaming reply many times a second. Finished messages' parses are cached.
- **Math is shown as TeX source** in a monospaced card. Native typesetting (e.g. SwiftMath) is a later pass.
- **No syntax highlighting in code blocks yet.** Code is monospaced and selectable with a copy button.
- **Regenerate keeps the old reply** as a sibling with a ‹ n/m › switcher. The tree model is the PWA's, so edit-and-resend can be added on top without a data change.

## Deferred to the second pass

Memory extraction and injection, persona editing, folders, edit-and-resend, the full per-parameter editor (top-k, penalties, min-p, seed, stop sequences, per-chat overrides), the "new models" badge, and the storage-pressure export reminder.

## Not verified

- **Not compiled before the first CI run.** Expect a round or two of compiler errors on the first builds; the workflow prints just the `error:` lines to paste back.
- **Not run against live OpenRouter.** Request and response shapes are ported from the PWA, and its own list of likely drift points (file attachment shape, `reasoning_details`, `usage.cost`, `/key` fields) applies here unchanged.
- **Default model ids** (`deepseek/deepseek-v4-flash-0731`, `z-ai/glm-5.3-flash`) are the PWA's guesses, resolved against the live catalogue by name pattern exactly as in the PWA.
