'use strict';

const { mkdirSync } = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const outputDirectory = path.join(root, 'target', 'coverage', 'node');
mkdirSync(outputDirectory, { recursive: true });

const result = spawnSync(
  process.execPath,
  [
    '--experimental-test-coverage',
    '--test-coverage-include=index.js',
    '--test-coverage-lines=100',
    '--test-coverage-functions=100',
    '--test-reporter=lcov',
    `--test-reporter-destination=${path.join(outputDirectory, 'lcov.info')}`,
    '--test',
    'test/*.test.js',
  ],
  {
    cwd: root,
    env: process.env,
    stdio: 'inherit',
  }
);

if (result.error) {
  throw result.error;
}
process.exit(result.status ?? 1);
