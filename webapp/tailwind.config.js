/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,ts}'],
  theme: {
    extend: {
      colors: {
        // Design tokens — see src/style.css for the CSS-variable mirror
        // used by PrimeVue theming.
        ink: '#14213D', // primary text, nav, headings — trust/authority
        paper: '#F7F8FA', // app background — cool, quiet, not stark white
        slate: {
          DEFAULT: '#5C677D', // secondary text, captions
          light: '#8D96A8',
        },
        teal: {
          DEFAULT: '#2A9D8F', // primary action, "offer/active" status
          dark: '#1F7A6F',
        },
        amber: '#E9A23B', // interview/reminder status, attention states
        coral: '#E15554', // rejected/error status
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
