/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: ['class', '[data-theme="dark"]'],
  theme: {
    colors: {
      transparent: 'transparent',
      current: 'currentColor',
      base: 'var(--c-base)',
      raised: 'var(--c-raised)',
      ink: 'var(--c-ink)',
      ink2: 'var(--c-ink2)',
      rule: 'var(--c-rule)',
      accent: 'var(--c-accent)',
      onaccent: 'var(--c-on-accent)',
    },
    fontFamily: {
      ui: 'var(--f-ui)',
      read: 'var(--f-read)',
      mono: 'var(--f-mono)',
    },
    fontSize: {
      xs: ['12px', '16px'],
      sm: ['13px', '18px'],
      body: ['15px', '22px'],
      md: ['17px', '28px'],
      lg: ['20px', '28px'],
      xl: ['24px', '32px'],
    },
    extend: {
      spacing: { 'safe-t': 'env(safe-area-inset-top)', 'safe-b': 'env(safe-area-inset-bottom)' },
      transitionTimingFunction: { spring: 'cubic-bezier(.2,.9,.25,1.05)' },
    },
  },
  plugins: [],
};
