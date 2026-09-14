import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import { execSync } from 'node:child_process';
import path from 'node:path';

const CSP = [
  "default-src 'self'",
  "connect-src 'self' https://openrouter.ai https://*.openrouter.ai",
  "img-src 'self' data: blob:",
  "style-src 'self' 'unsafe-inline'",
  "script-src 'self'",
  "font-src 'self' data:",
  "worker-src 'self'",
  "manifest-src 'self'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join('; ');

/** Injects the production CSP meta tag. Dev needs ws: for HMR, so it is build-only. */
function csp(): Plugin {
  return {
    name: 'quire-csp',
    apply: 'build',
    transformIndexHtml: (html) =>
      html.replace('<meta charset="UTF-8" />', `<meta charset="UTF-8" />\n    <meta http-equiv="Content-Security-Policy" content="${CSP}" />`),
  };
}

let hash = 'dev';
try { hash = execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { hash = Date.now().toString(36); }

export default defineConfig({
  resolve: { alias: { '@': path.resolve(process.cwd(), 'src') } },
  define: { __BUILD_HASH__: JSON.stringify(hash), __BUILD_TIME__: JSON.stringify(new Date().toISOString()) },
  build: { target: 'es2022', sourcemap: false, chunkSizeWarningLimit: 600 },
  plugins: [
    react(),
    csp(),
    VitePWA({
      registerType: 'prompt',
      includeAssets: ['icons/*.png'],
      manifest: {
        name: 'Quire',
        short_name: 'Quire',
        description: 'A reading instrument for OpenRouter models.',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'any',
        background_color: '#0e1013',
        theme_color: '#0e1013',
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icons/icon-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,png,woff2,webmanifest}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api\//],
        maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
        runtimeCaching: [
          { urlPattern: /^https:\/\/openrouter\.ai\/api\//, handler: 'NetworkOnly' },
          { urlPattern: /^https:\/\/api\.openrouter\.ai\//, handler: 'NetworkOnly' },
        ],
      },
    }),
  ],
});
