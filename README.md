# Quire

A single-user chat client for OpenRouter that runs entirely in the browser and installs to an iPhone home screen. No backend, no accounts, no analytics: your key and your chats live in this browser's storage and the only network traffic is to `openrouter.ai`.

## Run it

```sh
npm install
npm run dev        # http://localhost:5173, hot reload, no service worker
```

## Build and deploy

```sh
npm run build      # typechecks, then writes dist/
npm run preview    # serves dist/ locally on :4173 to test the installed behaviour
```

`dist/` is a static site. Put it on any HTTPS host (Cloudflare Pages, Netlify, GitHub Pages, an S3 bucket behind a CDN, nginx). Requirements:

- **HTTPS**, or `localhost`. Service workers and `navigator.storage.persist()` refuse to run otherwise.
- **Serve `index.html` for unknown paths** (SPA fallback), so `/chat/<id>` and `/settings/data` reload correctly. On Netlify that is a `_redirects` file with `/* /index.html 200`; on Cloudflare Pages it is automatic.
- Don't add a `Content-Security-Policy` header that is stricter than the one already in the built `index.html`; if you add one, mirror it.

The build injects a strict CSP, precaches the app shell, and never caches API responses.

## Install on an iPhone

1. Open the deployed URL in **Safari** (not Chrome; only Safari can install).
2. Share → **Add to Home Screen**.
3. Open Quire from the home screen. It runs full-screen with its own splash and icon.
4. Settings → Connection: paste an API key from [openrouter.ai/keys](https://openrouter.ai/keys), or use **Sign in with OpenRouter**.

Chats, memory and settings stay on the device. **Export a backup** from Settings → Data now and then; iOS can evict a web app's storage if the phone runs low on space, and there is no server copy.

## Layout of the code

```
src/
  lib/          types, Dexie schema, OpenRouter client (SSE, OAuth), parameter table,
                memory extraction/injection, export/import, formatting, viewport tracking
  store/        zustand stores: app (settings), models (catalogue), chats (lists),
                chat (open thread + stream engine), ui (routing, sheets, dialogs, toasts)
  components/   ui primitives, Markdown (lazy), Messages (virtualised list),
                ModelPicker, Params (capability-aware settings editor), Sheets
  screens/      Chat, ChatList, Settings (lazy), Memory (lazy)
  styles/       tokens and the iOS shell rules
scripts/
  icons.py      regenerates public/icons (needs Pillow)
  e2e.py        headless smoke test against dist/ with OpenRouter mocked (needs playwright)
.agents/skills/ design-engineering skills (emilkowalski/skill) the interface is held to; read before UI work
```

## Testing

```sh
npm run build
python3 scripts/e2e.py     # drives the built app in headless Chromium on an iPhone viewport
```

The harness mocks every OpenRouter endpoint, including SSE keep-alive comments and chunks split across packet boundaries, and fails on any console error. It does not replace testing on a real phone; see the acceptance checklist in the spec and the "Not done" section of `DECISIONS.md`.

## Privacy and security

- The API key is stored **unencrypted** in IndexedDB on this device. Anyone with access to this browser profile can read it. Use a key with a spending limit.
- Requests go straight from the browser to `openrouter.ai` with `HTTP-Referer` and `X-Title` headers so they appear as "Quire" on your OpenRouter activity page.
- Markdown from models is rendered with raw HTML stripped.
- Memory extraction sends your recent exchanges to the extraction model you choose; turn it off in Settings → Memory, or per chat, if that is not acceptable for a conversation.
