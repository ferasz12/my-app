/* eslint-env node */
module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  parserOptions: {
    project: ['tsconfig.json', 'tsconfig.dev.json'],
    tsconfigRootDir: __dirname,
  },
  plugins: ['@typescript-eslint'],
  extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended'],
  ignorePatterns: ['lib/**', 'node_modules/**', '**/*.js'],
  rules: {
    'object-curly-spacing': ['error', 'never'],
    'max-len': ['warn', {code: 120, ignoreStrings: true, ignoreTemplateLiterals: true, ignoreComments: true}],
    '@typescript-eslint/no-explicit-any': 'off',
  },
};
