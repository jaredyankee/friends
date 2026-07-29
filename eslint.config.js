// ESLint flat config. eslint-config-expo carries the React Native and
// React Hooks rules; eslint-config-prettier goes last so formatting rules
// never fight Prettier.

const expoConfig = require('eslint-config-expo/flat');
const prettierConfig = require('eslint-config-prettier');

module.exports = [
  ...expoConfig,
  prettierConfig,
  {
    ignores: [
      'node_modules/**',
      '.expo/**',
      'dist/**',
      'web/**', // static site, not part of the app build
      'coverage/**',
    ],
  },
  {
    rules: {
      // The packages must not reach for app-level dependencies. This is the
      // architectural boundary from CLAUDE.md, enforced rather than trusted.
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['**/lib/supabase', '@supabase/*'],
              message:
                'schedule-core and schedule-ui must not import Supabase. Data comes in as props or arguments — see CLAUDE.md.',
            },
          ],
        },
      ],
    },
  },
];
