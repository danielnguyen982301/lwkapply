import js from '@eslint/js'
import vue from 'eslint-plugin-vue'
import tseslint from 'typescript-eslint'
import vueParser from 'vue-eslint-parser'
import globals from 'globals'
import eslintConfigPrettier from 'eslint-config-prettier'

export default tseslint.config(
  { ignores: ['dist/**', 'node_modules/**', 'coverage/**', '.vite/'] },

  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...vue.configs['flat/recommended'],

  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tseslint.parser,
        extraFileExtensions: ['.vue'],
      },
    },
  },

  {
    files: ['**/*.{ts,vue}'],
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
    },
    rules: {
      // Vue's single-word-component-name rule fights view/layout naming
      // conventions like DashboardView.vue, AppLayout.vue — those names
      // are already unambiguous without a second word.
      'vue/multi-word-component-names': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
    },
  },

  // Must be LAST: turns off every ESLint/eslint-plugin-vue rule that
  // overlaps with Prettier's own formatting (indentation, quotes, comma
  // placement, line length, etc.). Without this, `lint:fix` and `format`
  // fight each other — each one "fixes" the file to a different style
  // the other then flags. This makes ESLint responsible for code
  // *correctness* only; Prettier owns all formatting, unopposed.
  eslintConfigPrettier,
)
