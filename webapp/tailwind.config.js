/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,ts}'],
  // Class-based strategy (not the default media-query one) so the theme
  // store can toggle dark mode manually, independent of the OS preference,
  // by adding/removing '.app-dark' on <html> — see src/stores/theme.ts.
  // Same selector PrimeVue's `darkModeSelector` is configured with
  // (src/main.ts), so both theming systems flip together.
  darkMode: ['selector', '.app-dark'],
  theme: {
    extend: {
      colors: {
        // Design tokens — see src/style.css for the CSS-variable mirror
        // used by PrimeVue theming. Values come from CSS custom properties
        // (not plain hex) so `.app-dark` can redefine them for dark mode;
        // the `<alpha-value>` placeholder keeps Tailwind's opacity
        // modifiers (`bg-ink/40`, `text-paper/60`, used throughout) working.
        ink: 'rgb(var(--color-ink) / <alpha-value>)', // primary text, nav, headings — trust/authority
        paper: 'rgb(var(--color-paper) / <alpha-value>)', // app background — cool, quiet, not stark white
        // Elevated surfaces (cards, table/paginator chrome, the app header)
        // — deliberately a different value from `paper` in both themes, not
        // an alias for it: a card needs to read as distinct from the page
        // it sits on, which a shared background color can't do on its own
        // (a thin border alone isn't enough separation, especially once a
        // dark page removes the light-mode white-vs-off-white cue too).
        surface: 'rgb(var(--color-surface) / <alpha-value>)',
        slate: {
          DEFAULT: 'rgb(var(--color-slate) / <alpha-value>)', // secondary text, captions
          light: 'rgb(var(--color-slate-light) / <alpha-value>)',
        },
        teal: {
          DEFAULT: 'rgb(var(--color-teal) / <alpha-value>)', // primary action, "offer/active" status
          dark: 'rgb(var(--color-teal-dark) / <alpha-value>)',
        },
        amber: 'rgb(var(--color-amber) / <alpha-value>)', // interview/reminder status, attention states
        coral: 'rgb(var(--color-coral) / <alpha-value>)', // rejected/error status
        // Fixed brand colors for the sidebar/scrim (AppLayout.vue) — these
        // never swap between light/dark app themes, unlike `ink`/`paper`
        // above: the sidebar is a permanently-dark navy panel regardless
        // of overall theme, so it can't ride on tokens that invert.
        sidebar: '#14213D',
        'sidebar-fg': '#F7F8FA',
      },
      fontFamily: {
        display: ['"Space Grotesk"', 'sans-serif'],
        sans: ['Inter', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'monospace'],
      },
      borderRadius: {
        card: '10px',
      },
    },
  },
  plugins: [],
}
