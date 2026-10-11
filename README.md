# Quire for iPhone

A native SwiftUI port of [Quire](https://github.com/shahisgood/quire), the single-user OpenRouter chat client. Same idea as the web app: no backend, no accounts, no analytics. Your chats stay on the phone, the key lives in the Keychain, and the only network traffic is to `openrouter.ai`.

Requires **iOS 26**. Built entirely on GitHub's macOS runners, so you don't need a Mac.

## What's in this build

- Streaming chat with reasoning traces, retry with backoff on 429/5xx, stop, continue, and regenerate (optionally with another model). Regenerated replies are kept as siblings, with a ‹ 1/2 › switcher.
- Markdown rendered natively: headings, lists and task lists, tables, quotes, code blocks with copy. Math is shown as TeX source for now.
- Model picker over the live OpenRouter catalogue, with search, Free/Vision/Reasoning/Files filters, favourites and recents.
- Photo and file attachments (images downscaled to 1600 px, same as the web app).
- Costs: a live estimate while streaming, replaced by OpenRouter's authoritative figure a few seconds later. Per-chat and per-day totals.
- Chat list with pin, archive, rename, delete and search across every message.
- Settings: API key (paste, or Sign in with OpenRouter), default and title models, system prompt, temperature/top-p/max tokens, reasoning mode, web search, provider routing, theme and typeface.
- **Backups in the web app's format.** Export from the web app (Settings → Data), import here, and everything comes across: chats, messages, costs, settings, even personas and memory, which are kept for a later build.

Not here yet: memory extraction, persona editing, folders, editing a sent message, and the full parameter editor. See `DECISIONS.md`.

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

Pushing to `main` starts the **Build IPA** workflow (Actions tab). It takes about 5–10 minutes. When it goes green, open the run and download the **Quire-ipa** artifact. It's a zip containing `Quire.ipa`.

If the build fails, open the run, expand the **Compiler errors** step, and paste what it shows back to Claude. The **build-log** artifact has the full log.

> **Minutes:** builds on a public repo are free. On a private repo, macOS minutes count 10× against your monthly allowance (2,000 free minutes ≈ 200 macOS minutes ≈ 25 builds).

### 3. Sign and install

The IPA is unsigned. iOS only runs signed apps, so sign it with your Apple ID using one of these tools on Windows:

- **[Sideloadly](https://sideloadly.io)**: install iTunes and iCloud (the non-Store versions it links to), plug in the iPhone, drag in `Quire.ipa`, enter your Apple ID, and press Start.
- **[AltStore](https://altstore.io)** or **[SideStore](https://sidestore.io)**: AltServer runs on Windows. SideStore can refresh on the phone itself after the first setup.

Then on the phone:

1. **Settings → General → VPN & Device Management**: trust your Apple ID's developer profile.
2. **Settings → Privacy & Security → Developer Mode**: turn it on (the phone restarts).

With a **free Apple ID** the app stops opening after **7 days** and needs re-signing (AltStore and SideStore can do this automatically), and you can have at most 3 sideloaded apps. A paid Apple Developer account ($99/year) signs for a year.

### 4. First run

Open Quire → Settings → Connection, and either paste a key from [openrouter.ai/keys](https://openrouter.ai/keys) or use **Sign in with OpenRouter**. That opens openrouter.ai, which shows you a code to paste back into the app. To bring your web-app chats across, export a backup there and import it under Settings → Data.

## Working on it

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen), so there's no `.xcodeproj` in the repo. On a Mac: `brew install xcodegen && xcodegen generate && open Quire.xcodeproj`.

```
Quire/
  App/        entry point, navigation root
  Models/     data types (mirroring the web app's), JSONValue
  Core/       OpenRouter client and SSE parsing, request builder, storage, Keychain, attachments, formatting
  State/      AppModel (settings, catalogue, chat list), ChatSession (one thread + stream engine), backups
  Markdown/   block parser and native renderer
  Views/      screens
```
