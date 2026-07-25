'use strict';

const { readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const packagePath = require.resolve('@napi-rs/cli/package.json');
const cliPath = path.join(path.dirname(packagePath), 'dist', 'cli.js');
const forwarded = process.argv.slice(2);
const debugIndex = forwarded.indexOf('--debug');
const release = debugIndex === -1;

if (!release) {
  forwarded.splice(debugIndex, 1);
}

const args = [
  cliPath,
  'build',
  '--platform',
  '--js',
  'native.js',
  '--dts',
  'native.d.ts',
];
if (release) {
  args.push('--release');
}
args.push(...forwarded);

const result = spawnSync(process.execPath, args, {
  cwd: root,
  env: process.env,
  stdio: 'inherit',
});
if (result.error) {
  throw result.error;
}
if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

const loaderPath = path.join(root, 'native.js');
const loader = readFileSync(loaderPath, 'utf8');
const original = '`Cannot find native binding. ` +';
const actionable =
  '`Cannot find native binding for ${process.platform}/${process.arch}. ` +';

if (!loader.includes(original) && !loader.includes(actionable)) {
  throw new Error(
    'Generated loader error text no longer matches the expected form'
  );
}
if (loader.includes(original)) {
  writeFileSync(loaderPath, loader.replace(original, actionable));
}
