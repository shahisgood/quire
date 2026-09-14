import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './styles/index.css';

// Theme before first paint, from the persisted preference (no inline script: keeps CSP strict).
try {
  const t = localStorage.getItem('quire.theme') ?? 'dark';
  document.documentElement.dataset.theme = t === 'system' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : t;
} catch { /* private mode */ }

createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>);
