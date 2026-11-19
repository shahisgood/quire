# Quire for iPhone

A native SwiftUI version of [Quire](https://github.com/shahisgood/quire), the single-user OpenRouter chat client, with everything the web app does. No backend, no accounts, no analytics. Your chats stay on the phone, the key lives in the Keychain, and the only network traffic is to `openrouter.ai`.

Requires **iOS 26**. Built on GitHub's macOS runners, so you don't need a Mac.

## What's in it

**Chat**
- Streaming replies with a live accent cursor, reasoning traces that open while the model thinks and fold away when it answers, and automatic retry with a countdown on 429/5xx.
- Stop, continue, retry, regenerate (or regenerate with another model), and **edit and resend**. Every version is kept as a branch, with a ‹ 2/3 › switcher.
- Branch any message into a new chat, duplicate a chat, share it as Markdown or JSON.
- Web sources the way an answer engine shows them: a citation in a reply becomes a small pill with the site's icon and name, and a Sources button under the reply (its icons stacked) lists every page with its title and a line of what it said. Links open in Safari inside Quire. Icons come from DuckDuckGo's icon service and can be turned off (Settings → Appearance → Site icons).
- **Export a chat as a PDF**: the conversation typeset on white A4 (or US Letter) pages in your typeface and theme colours, your messages on the right as in the app, replies in the reading face with their headings, lists, tables, quotes and coloured code, images inline, and the title and page number at the foot of each page. It opens as a page-by-page preview first, with times and reasoning to include or leave out, then shares to Files, Mail, AirDrop or Print. From a message's menu, Chat settings, or a chat's Export menu in the list.
- Markdown rendered natively: headings, lists, task lists, tables, quotes, rules, and code blocks with syntax colouring and a copy button. Display math is shown as TeX.
- Attachments from Photos, the camera, Files or the clipboard, from Quire's own attach window: your latest photos along the top (once you've allowed it; asked only when you tap that line), Camera, Photos, Files and Paste as tiles, and the chat's project, with the projects a page away. Images are resized to 1600 px, as in the web app.
- Images the model draws (for models that output images) are kept on the reply. Tap any image in a chat to see it full screen and swipe through all of them, with pinch and double-tap zoom and swipe down to close.
- A composer after Claude's: at rest a single line that stands in from the sides and sits down by the home indicator; tapped, it widens on a soft spring as it rises with the keyboard and the model settles in a beat behind. Attach and the model open Quire's own glass windows rather than system menus, each growing out of its button and folding back into it: the model window shows what's answering with its context and price, its thinking levels in a sliding track, your last four models and the way into the full picker. A send button appears once there's something to send; what you send rises out of the box from the send corner. Offline is detected and your draft waits.
- The context window, when it's on (Settings → Appearance → Context window; off by default): once a chat has begun, a ring in the top corner, in a circle of its own, opens a window that sets the context out as a hundred squares in the colours of what fills them (instructions, memory, your messages, replies, images and files, what's not sent yet), with the figures, the provider's own count of the last prompt, and a way into a fresh chat when it's nearly full.
- Replies carry on after you leave Quire: a reply asks iOS for a continued-processing task as it starts, so it keeps going in the background with a progress card on the Lock Screen and in the Dynamic Island, where you can stop it. Optionally (Settings → Appearance → Tell me when a reply is done), a notification when one finishes while you're away; tap it to open the chat.
- Quote in Reply: select a passage of any message (Select text) and choose Quote in Reply; it waits above the message box, goes out as a quote in front of your question, and shows as one in your message and in PDFs.
- The screen stays on while a reply is being written, so a long one isn't cut off by the phone locking; it sleeps as usual the moment none is.
- Quire opens on a fresh chat after you close it. Reopen within 30 seconds of leaving a chat and you're back in it. Switching away and back never moves you, and if iOS ends Quire in the background to free memory, you come back exactly where you were.
- Swipe down or tap anywhere on a chat to put the keyboard away.
- A greeting on every new chat that follows the time of day, always on one clean line.
- Chats are named from their opening exchange (Settings → Models → Name new chats), and a chat that missed its name (offline, a failed first reply) gets one when you next open it.
- Home Screen quick actions: press and hold the icon for New chat, Incognito chat, or one of your two most recent chats.
- Long-press any message for copy, select text, edit, branch, details (tokens, cost, the exact request sent) and delete.
- Toasts drop in under the Dynamic Island with a ring that runs down the time left to Undo. Drag one to hold it, flick it up to throw it off at the speed you flicked; the clock waits while Quire is in the background; Undo confirms itself.

**Memory**
- Facts are extracted from your chats after replies (batched, never on the critical path) and injected into requests within a character budget: pinned first, then the most relevant, then the newest.
- A memory manager with categories, search, inline editing, pin, disable, jump to source, add your own, and a typed "clear" confirmation.
- Incognito chats neither read nor write memory.

**Prompts and personas**
- Global system prompt, per-chat prompt overrides, and personas: icon, name, prompt, optional pinned model, and their own generation settings. Hold the compose button to start a chat from one. Import and export personas as JSON.

**Models and settings**
- A model picker over the live OpenRouter catalogue, set out like the rest of Quire: the chosen model as a headline, one strip of chips (Vision/Files/Tools/Reasoning/JSON and New) with Filters opening provider, price bands, context sizes and an order (popular, newest, cheapest, longest context), then the models in cards of rows, each with its maker, price, context and abilities; fuzzy search at the bottom, favourites, recents, and a full model card.
- A generation editor that only shows what the model supports, in cards: sampling (with Precise, Balanced and Creative styles), repetition, output, reasoning and routing. Sliders are Quire's own, filling from their neutral point with a tick at the inherited value; every setting's (i) opens its explanation in place. It covers every sampling parameter, seed, max tokens, stop sequences, reasoning effort or budget per model family, provider routing, fallback models, web search and middle-out trimming. It works at three levels (global, persona, chat), with an Inherit button and a dot on anything set at that level.
- A chat list set like a journal: the day in small capitals over a large serif Quire (with today's spend opposite), your projects in a strip that runs sideways (only once you have one), then a day's chats together in one card under a small-capital label with how many it holds (Pinned, Today, Yesterday, This week, Earlier), pinned while you scroll. Each chat is its title and time, one line of the last thing said, and, only when there's something to say, one quiet line of what sets it apart (persona, a model other than the one a new chat would get, incognito) with its cost. A dot marks a reply that finished while you were elsewhere, until you open it. Swipe left to archive (with Undo), pin or delete; multi-select to move, archive, export, pin or delete; search across every message and jump to the match.
- Swipes that work from anywhere, not just the edge: right on a chat, a project or Memory to go back; right on the chat list to pull settings in, following your finger; left on settings to put it away. Sliders, switches, code blocks that scroll sideways and text you're selecting keep their own swipes.
- Projects: homes for related chats, each with its own symbol and colour. A project opens on a headline card in its colour (how many chats, when last active, its model, its instructions set like a pull quote, New chat and Incognito), and is made or edited on a page laid out like the settings, with its name typed straight into the card. Give one instructions and every chat in it follows them (added after the system prompt), or leave it as a plain group. A project can also choose the model its new chats start with. Hold a project's card to start a chat in it, edit it, or delete it (keeping its chats or not, with Undo for the first); chats move in and out from their menu or in bulk. Stored as the web app's folders, so backups still round-trip.
- Costs: a live estimate while streaming, replaced by OpenRouter's authoritative figure a few seconds later. Settings shows the last 30 days at a glance; the breakdown charts cost, tokens or replies over 7 days to all time, stacked by model (each model keeps its colour), with a model table, the token mix and the costliest chats.
- Appearance: four themes (Quire's ink, paper and periwinkle; Velvet's obsidian, velvet and almond; Amethyst's noir, amethyst and steel; and Pitch, true black and white for OLED screens, where everything that carries a colour elsewhere (settings icons, code, charts, projects, warnings, swipe actions, switches) turns to greys; only site icons in links keep theirs), each in light, dark or auto, and the whole app re-colours as you pick; a typeface for the whole app, picked from four specimens (Geist, the default, then Allo, New York and SF Pro), with replies following it or set apart; Allo, Josh Puckett's friendly sans for screens, sets titles, replies and what you type, and carries into exported PDFs; Geist, Vercel's family, comes in four cuts from a menu (Geist Serif by default, Geist Sans, Geist Mono, and Geist Pixel for titles), sets code in Geist Mono, and carries into exported PDFs; reply size on top of Dynamic Type; comfortable or compact; text strength; haptics.
- About opens on a dictionary entry for the word, then what you've gathered (chats, messages, remembered facts, replies week by week, the room it takes), where everything is kept, and a colophon of how your copy is set.
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

## Fonts

Geist Sans, Geist Mono, Geist Serif and Geist Pixel are by Vercel and ship under the SIL Open Font License 1.1 (`Quire/Resources/Fonts/Geist-OFL.txt`). Geist Serif and Geist Pixel were converted from the `geist` package's WOFF2 files to TrueType, unchanged otherwise. Allo is by Josh Puckett and ships under the SIL Open Font License 1.1 (`Quire/Resources/Fonts/Allo-OFL.txt`): the static OpenType cuts from Allo 1.0.1 (Regular, Medium, SemiBold and Bold, with obliques), unchanged.
