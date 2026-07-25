import globals from 'globals';
import pluginJs from '@eslint/js';

/** @type {import('eslint').Linter.Config[]} */
export default [
  {
    ignores: [
      'artifacts/**',
      'dist/**',
      'native.js',
      'node_modules/**',
      'npm/**',
      'target/**',
    ],
  },
  { files: ['**/*.js'], languageOptions: { sourceType: 'script' } },
  { languageOptions: { globals: globals.node } },
  pluginJs.configs.recommended,
];
