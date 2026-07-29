// jest-expo provides the React Native transform and module mapping.
// Workspace packages are plain TypeScript and are covered by the same preset.
module.exports = {
  preset: 'jest-expo',
  roots: ['<rootDir>/app', '<rootDir>/components', '<rootDir>/packages'],
  moduleNameMapper: {
    '^@friends/schedule-core$': '<rootDir>/packages/schedule-core/src',
    '^@friends/schedule-ui$': '<rootDir>/packages/schedule-ui/src',
  },
  collectCoverageFrom: ['packages/*/src/**/*.{ts,tsx}', 'components/**/*.{ts,tsx}'],
};
