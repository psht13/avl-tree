'use strict';

const { mkdirSync } = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const outputDirectory = path.join(root, 'target', 'coverage', 'rust');
mkdirSync(outputDirectory, { recursive: true });

for (const args of [
  [
    'llvm-cov',
    '--lib',
    '--lcov',
    '--output-path',
    path.join(outputDirectory, 'lcov.info'),
    '--fail-under-lines',
    '90',
  ],
  ['llvm-cov', 'report', '--summary-only', '--show-missing-lines'],
]) {
  const result = spawnSync('cargo', args, {
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
}
