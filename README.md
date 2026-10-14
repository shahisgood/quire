# Quire for iPhone

A native SwiftUI version of [Quire](https://github.com/shahisgood/quire), the single-user OpenRouter chat client, with everything the web app does. No backend, no accounts, no analytics. Your chats stay on the phone, the key lives in the Keychain, and the only network traffic is to `openrouter.ai`.

Requires **iOS 26**. Built on GitHub's macOS runners, so you don't need a Mac.

## What's in it

**Chat**
- Streaming replies with a live accent cursor, reasoning traces that open while the model thinks and fold away when it answers, and automatic retry with a countdown on 429/5xx.
- Stop, continue, retry, regenerate (or regenerate with another model), and **edit and resend**. Every version is kept as a branch, with a ‹ 2/3 › switcher.
- Branch any message into a new chat, duplicate a chat, share it as Markdown or JSON.
- Markdown rendered natively: headings, lists, task lists, tables, quotes, rules, and code blocks with syntax colouring and a copy button. Display math is shown as TeX.
- Attachments from Photos, the camera, Files or the clipboard. Images are resized to 1600 px, as in the web app.
- A composer after Claude's: attach, the model with its thinking level, a context ring (tap for details and the chat's cost), and a send button that appears once there's something to send. Offline is detected and your draft waits.
- A greeting on every new chat that follows the time of day, with starter prompts (Explain, Write, Summarize, Brainstorm, Code, Plan) that fill the message box without sending.
- **Live Activity**: leave Quire while a reply is being written and it follows you onto the Lock Screen and into the Dynamic Island (status, timer, tokens, the latest lines); a tap opens the chat. Switch it off under Settings → Appearance.
- Chats are named a moment after their first message (Settings → Models & generation → Name new chats).
- Home Screen quick actions: press and hold the icon for New chat, Incognito chat, or one of your two most recent chats.
- Long-press any message for copy, select text, edit, branch, details (tokens, cost, the exact request sent) and delete.

**Memory**
- Facts are extracted from your chats after replies (batched, never on the critical path) and injected into requests within a character budget: pinned first, then the most relevant, then the newest.
- A memory manager with categories, search, inline editing, pin, disable, jump to source, add your own, and a typed "clear" confirmation.
- Incognito chats neither read nor write memory.

**Prompts and personas**
- Global system prompt, per-chat prompt overrides, and personas: icon, name, prompt, optional pinned model, and their own generation settings. Hold the compose button to start a chat from one. Import and export personas as JSON.

**Models and settings**
- A model picker over the live OpenRouter catalogue: fuzzy search, Vision/Files/Tools/Reasoning/Structured, price bands, context sizes, provider filter, a "New" filter for models that appeared since you last looked, favourites, recents, and a full model card.
- A generation editor that only shows what the model supports: sampling presets (Precise, Balanced, Creative), every sampling parameter, seed, max tokens, stop sequences, reasoning effort or budget per model family, provider routing, fallback models, web search and middle-out trimming. It works at three levels (global, persona, chat), with an Inherit button and a dot on anything set at that level.
- Chat list with pinned chats, collapsible folders, Today/Yesterday/This week/Earlier, swipe to archive (with Undo) or pin, multi-select to move, archive, export, pin or delete, and search across every message that jumps to the match.
- Costs: a live estimate while streaming, replaced by OpenRouter's authoritative figure a few seconds later, and per-chat, per-day and 14-day totals with a chart.
- Appearance: dark, light or auto; serif or sans replies; reply size on top of Dynamic Type; comfortable or compact; haptics.
- Backups in the web app's format, so you can move between the two in either direction. A reminder appears after 200 messages or 30 days.

Accessibility: Dynamic Type throughout, VoiceOver labels and custom actions on messages, spoken "reply finished", Reduce Motion honoured everywhere (motion becomes a crossfade), and 44 pt touch targets.

## Get it onto your iPhone (from Windows)

### 1. Put this folder in a GitHub repository

Create a new repository on GitHub (public is simplest; see the note on minutes below) and upload everything in this folder, including the hidden `.github` folder. With Git:

```sh
git init
git add .
git commit -m "Quire for iPhone"
git branch -M main
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```

### 2. Let GitHub build it

Pushing to `main` starts the **Build IPA** workflow (Actions tab). It takes about 5–10 minutes. When it goes green, open the run and download the **Quire-ipa** artifact, a zip containing `Quire.ipa`.

If the build fails, open the run, expand the **Compiler errors** step, and paste what it shows back to Claude. The **build-log** artifact has the full log.

> **Minutes:** builds on a public repo are free. On a private repo, macOS minutes count 10× against your monthly allowance (2,000 free minutes ≈ 200 macOS minutes ≈ 25 builds).

### 3. Sign and install

The IPA is unsigned, and iOS only runs signed apps, so sign it with your Apple ID using one of these on Windows:

- **[Sideloadly](https://sideloadly.io)**: install iTunes and iCloud (the non-Store versions it links to), plug in the iPhone, drag in `Quire.ipa`, enter your Apple ID, press Start.
- **[AltStore](https://altstore.io)** or **[SideStore](https://sidestore.io)**: AltServer runs on Windows; SideStore can refresh on the phone itself after the first setup.

Then on the phone:

1. **Settings → General → VPN & Device Management**: trust your Apple ID's developer profile.
2. **Settings → Privacy & Security → Developer Mode**: turn it on (the phone restarts).

Quire includes a small widget extension (`QuireLive`) that draws the Live Activity. Sideloadly, AltStore and SideStore sign it along with the app; keep it in (don't tick an option to remove app extensions), or the Live Activity won't appear. It needs one extra App ID, which counts toward a free Apple ID's limit of 10 per week.

With a **free Apple ID** the app stops opening after **7 days** and needs re-signing (AltStore and SideStore can do it automatically), and you can have at most 3 sideloaded apps. A paid Apple Developer account ($99/year) signs for a year.

### 4. First run

Open Quire, then Settings → Connection: paste a key from [openrouter.ai/keys](https://openrouter.ai/keys), or use **Sign in with OpenRouter**, which shows you a code on openrouter.ai to paste back. To bring your web-app chats, memory and personas across, export a backup there (Settings → Data) and import it under Settings → Data & backup.

## Working on it

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen), so there's no `.xcodeproj` in the repo. On a Mac: `brew install xcodegen && xcodegen generate && open Quire.xcodeproj`.

```
Quire/
  App/        entry point, navigation root, toasts
  Models/     data types (mirroring the web app's) and JSONValue
  Core/       OpenRouter client and SSE parsing, request builder, memory logic, storage,
              Keychain, attachments, formatting, connectivity, haptics
  State/      AppModel (settings, catalogue, chats, personas, memory, folders, costs),
              ChatSession (one thread and its stream engine), memory extraction, backups
  Markdown/   block parser, native renderer, code highlighter
  Design/     palette, type, motion tokens, shared components
  Views/      every screen and sheet
```
