// Metro config for an npm-workspaces monorepo.
//
// The app lives at the workspace root, so there is a single hoisted
// node_modules and no second copy of React to guard against. Metro's defaults
// handle resolution; the one thing it cannot infer is that packages/* are part
// of this project, so edits there must trigger a rebuild.
//
// Deliberately NOT set: resolver.disableHierarchicalLookup. It is the usual
// advice for monorepos where the app sits in apps/<name> with its own
// node_modules, but here it only stops Metro finding legitimately nested
// dependencies — @expo/metro-runtime is nested under expo-router, and turning
// this on breaks the bundle with an unresolved-import error.

const { getDefaultConfig } = require('expo/metro-config');
const path = require('node:path');

const projectRoot = __dirname;

const config = getDefaultConfig(projectRoot);

// Watch the workspace packages so changes there hot-reload.
config.watchFolders = [path.resolve(projectRoot, 'packages')];

module.exports = config;
