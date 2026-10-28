# Quire for iPhone

A native SwiftUI version of [Quire](https://github.com/shahisgood/quire), the single-user OpenRouter chat client, with everything the web app does. No backend, no accounts, no analytics. Your chats stay on the phone, the key lives in the Keychain, and the only network traffic is to `openrouter.ai`.

Requires **iOS 26**. Built on GitHub's macOS runners, so you don't need a Mac.

## What's in it

**Chat**
- Streaming replies with a live accent cursor, reasoning traces that open while the model thinks and fold away when it answers, and automatic retry with a countdown on 429/5xx.
- Stop, continue, retry, regenerate (or regenerate with another model), and **edit and resend**. Every version is kept as a branch, with a ‹ 2/3 › switcher.
- Branch any message into a new chat, duplicate a chat, share it as Markdown or JSON.
- **Export a chat as a PDF**: the conversation typeset on white A4 (or US Letter) pages in your typeface and theme colours, your messages on the right as in the app, replies in the reading face with their headings, lists, tables, quotes and coloured code, images inline, and the title and page number at the foot of each page. It opens as a page-by-page preview first, with times and reasoning to include or leave out, then shares to Files, Mail, AirDrop or Print. From a message's menu, Chat settings, or a chat's Export menu in the list.
- Markdown rendered natively: headings, lists, task lists, tables, quotes, rules, and code blocks with syntax colouring and a copy button. Display math is shown as TeX.
- Attachments from Photos, the camera, Files or the clipboard. Images are resized to 1600 px, as in the web app.
- Images the model draws (for models that output images) are kept on the reply. Tap any image in a chat to see it full screen and swipe through all of them, with pinch and double-tap zoom and swipe down to close.
- A composer after Claude's: attach, the model with its thinking level, a context ring (tap for details and the chat's cost; Settings → Appearance → Context window hides it), and a send button that appears once there's something to send. Offline is detected and your draft waits.
- Quire opens on a fresh chat. Come back within 30 seconds of leaving a chat and you're back in it; any longer and a clean page is waiting.
- A greeting on every new chat that follows the time of day, always on one clean line.
- Chats are named from their opening exchange (Settings → Models → Name new chats), and a chat that missed its name (offline, a failed first reply) gets one when you next open it.
- Home Screen quick actions: press and hold the icon for New chat, Incognito chat, or one of your two most recent chats.
- Long-press any message for copy, select text, edit, branch, details (tokens, cost, the exact request sent) and delete.
- Toasts drop in under the Dynamic Island with a ring that runs down the time left to Undo. Drag one to hold it, flick it up to dismiss; Undo confirms itself.

**Memory**
- Facts are extracted from your chats after replies (batched, never on the critical path) and injected into requests within a character budget: pinned first, then the most relevant, then the newest.
- A memory manager with categories, search, inline editing, pin, disable, jump to source, add your own, and a typed "clear" confirmation.
- Incognito chats neither read nor write memory.

**Prompts and personas**
- Global system prompt, per-chat prompt overrides, and personas: icon, name, prompt, optional pinned model, and their own generation settings. Hold the compose button to start a chat from one. Import and export personas as JSON.

**Models and settings**
- A model picker over the live OpenRouter catalogue: fuzzy search, Vision/Files/Tools/Reasoning/Structured, price bands, context sizes, provider filter, a "New" filter for models that appeared since you last looked, favourites, recents, and a full model card.
- A generation editor that only shows what the model supports, in cards: sampling (with Precise, Balanced and Creative styles), repetition, output, reasoning and routing. Sliders are Quire's own, filling from their neutral point with a tick at the inherited value; every setting's (i) opens its explanation in place. It covers every sampling parameter, seed, max tokens, stop sequences, reasoning effort or budget per model family, provider routing, fallback models, web search and middle-out trimming. It works at three levels (global, persona, chat), with an Inherit button and a dot on anything set at that level.
- A chat list set like a journal: the day in small capitals over a large serif Quire (with today's spend opposite), projects as a shelf of tinted cards two across, then your chats as cards under serif headings (Pinned, Today, Yesterday, This week, Earlier) that stay pinned while you scroll. Each card shows the title, the last thing said, and pills for only what sets the chat apart (persona, a model other than the one a new chat would get, incognito), with its cost. A dot marks a reply that finished while you were elsewhere, until you open it. Swipe left to archive (with Undo), pin or delete; multi-select to move, archive, export, pin or delete; search across every message and jump to the match.
- Swipes that work from anywhere, not just the edge: right on a chat, a project or Memory to go back; right on the chat list to pull settings in, following your finger; left on settings to put it away. Sliders, switches, code blocks that scroll sideways and text you're selecting keep their own swipes.
- Projects: homes for related chats, each with its own symbol and colour. Give one instructions and every chat in it follows them (added after the system prompt), or leave it as a plain group. A project can also choose the model its new chats start with. Hold a project's card to start a chat in it, edit it, or delete it (keeping its chats or not, with Undo for the first); chats move in and out from their menu or in bulk. Stored as the web app's folders, so backups still round-trip.
- Costs: a live estimate while streaming, replaced by OpenRouter's authoritative figure a few seconds later. Settings shows the last 30 days at a glance; the breakdown charts cost, tokens or replies over 7 days to all time, stacked by model (each model keeps its colour), with a model table, the token mix and the costliest chats.
- Appearance: four themes (Quire's ink, paper and periwinkle; Velvet's obsidian, velvet and almond; Amethyst's noir, amethyst and steel; and Pitch, true black and white for OLED screens), each in light, dark or auto, and the whole app re-colours as you pick; a typeface for the whole app, picked from three specimens (New York, SF Pro or SF Pro Rounded), with replies following it or kept in New York; reply size on top of Dynamic Type; comfortable or compact; text strength; haptics.
- About reads like the back pages of a book: what a quire is, what you've gathered (chats, messages, remembered facts, the room it takes), where everything is kept, and a colophon of how your copy is set.
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
  State/      AppModel (settings, catalogue, chats, personas, memory, projects, costs),
              ChatSession (one thread and its stream engine), memory extraction, backups
  Markdown/   block parser, native renderer, code highlighter
  Design/     palette, type, motion tokens, shared components
  Views/      every screen and sheet
```
