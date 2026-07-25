'use strict';

const { spawnSync } = require('node:child_process');

const commands = [
  ['npm', ['run', 'format:check']],
  ['npm', ['run', 'lint']],
  [
    'cargo',
    ['clippy', '--all-targets', '--all-features', '--', '-D', 'warnings'],
  ],
  ['cargo', ['test', '--all-targets']],
  ['npm', ['run', 'native:check']],
  ['npm', ['run', 'test:node']],
  ['npm', ['run', 'coverage:rust']],
  ['npm', ['run', 'coverage:node']],
  ['npm', ['run', 'publint']],
  ['npm', ['run', 'test:package']],
  ['npm', ['audit', '--audit-level=high']],
  ['git', ['diff', '--check']],
];

for (const [command, args] of commands) {
  console.log(`\n> ${command} ${args.join(' ')}`);
  const result = spawnSync(command, args, {
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
