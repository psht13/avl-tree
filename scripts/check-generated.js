'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const generated = ['native.js', 'native.d.ts'];
const before = new Map(
  generated.map((file) => [file, readFileSync(path.join(root, file), 'utf8')])
);

const result = spawnSync(process.execPath, ['scripts/build-native.js'], {
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

for (const file of generated) {
  assert.equal(
    readFileSync(path.join(root, file), 'utf8'),
    before.get(file),
    `${file} was stale; commit the regenerated file`
  );
}
