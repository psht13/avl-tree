'use strict';

const assert = require('node:assert/strict');
const {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const validation = path.join(root, 'target', 'package-validation');
const npmDirectory = path.join(validation, 'npm');
const packsDirectory = path.join(validation, 'packs');
const artifactsDirectory = path.join(validation, 'artifacts');
const packagePath = require.resolve('@napi-rs/cli/package.json');
const napiCli = path.join(path.dirname(packagePath), 'dist', 'cli.js');
const npmCli =
  process.env.npm_execpath ||
  path.join(
    path.dirname(process.execPath),
    '..',
    'lib',
    'node_modules',
    'npm',
    'bin',
    'npm-cli.js'
  );

function runNode(script, args, options = {}) {
  const result = spawnSync(process.execPath, [script, ...args], {
    cwd: options.cwd || root,
    encoding: options.capture ? 'utf8' : undefined,
    env: process.env,
    stdio: options.capture ? ['ignore', 'pipe', 'inherit'] : 'inherit',
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
  return result.stdout;
}

function runNpm(args, options = {}) {
  return runNode(npmCli, args, options);
}

function localPackageDirectory() {
  if (process.platform === 'darwin' && process.arch === 'arm64') {
    return 'darwin-arm64';
  }
  if (process.platform === 'darwin' && process.arch === 'x64') {
    return 'darwin-x64';
  }
  if (process.platform === 'win32' && process.arch === 'x64') {
    return 'win32-x64-msvc';
  }
  if (process.platform === 'linux' && process.arch === 'x64') {
    const report = process.report?.getReport();
    return report?.header?.glibcVersionRuntime
      ? 'linux-x64-gnu'
      : 'linux-x64-musl';
  }
  if (process.platform === 'linux' && process.arch === 'arm64') {
    const report = process.report?.getReport();
    return report?.header?.glibcVersionRuntime
      ? 'linux-arm64-gnu'
      : 'linux-arm64-musl';
  }
  throw new Error(
    `Package validation does not support ${process.platform}/${process.arch}`
  );
}

function pack(cwd) {
  const output = runNpm(
    [
      'pack',
      '--json',
      '--ignore-scripts',
      '--pack-destination',
      packsDirectory,
    ],
    { cwd, capture: true }
  );
  const parsed = JSON.parse(output);
  assert.equal(parsed.length, 1);
  return parsed[0];
}

rmSync(validation, { recursive: true, force: true });
mkdirSync(packsDirectory, { recursive: true });

runNode(path.join(root, 'scripts', 'build-native.js'), []);
runNode(napiCli, [
  'create-npm-dirs',
  '--npm-dir',
  path.relative(root, npmDirectory),
]);

const platformDirectory = path.join(npmDirectory, localPackageDirectory());
const platformPackage = JSON.parse(
  readFileSync(path.join(platformDirectory, 'package.json'), 'utf8')
);
mkdirSync(artifactsDirectory, { recursive: true });
copyFileSync(
  path.join(root, platformPackage.main),
  path.join(artifactsDirectory, platformPackage.main)
);
runNode(napiCli, [
  'artifacts',
  '--output-dir',
  path.relative(root, artifactsDirectory),
  '--npm-dir',
  path.relative(root, npmDirectory),
]);

const rootPack = pack(root);
const actualFiles = rootPack.files.map(({ path: file }) => file).sort();
const expectedFiles = [
  'LICENSE',
  'README.md',
  'index.d.ts',
  'index.js',
  'native.d.ts',
  'native.js',
  'package.json',
].sort();
assert.deepEqual(actualFiles, expectedFiles);

assert.ok(existsSync(path.join(platformDirectory, platformPackage.main)));
const platformPack = pack(platformDirectory);

const rootTarball = path.join(packsDirectory, rootPack.filename);
const platformTarball = path.join(packsDirectory, platformPack.filename);
const report = {
  root: {
    filename: rootPack.filename,
    size: rootPack.size,
    unpackedSize: rootPack.unpackedSize,
    files: actualFiles,
  },
  platform: {
    name: platformPackage.name,
    filename: platformPack.filename,
    size: platformPack.size,
    unpackedSize: platformPack.unpackedSize,
    files: platformPack.files.map(({ path: file }) => file).sort(),
  },
};

if (!process.argv.includes('--pack-only')) {
  const consumer = mkdtempSync(
    path.join(os.tmpdir(), 'avl-tree-rust-consumer-')
  );
  try {
    writeFileSync(
      path.join(consumer, 'package.json'),
      `${JSON.stringify(
        {
          name: 'avl-tree-rust-package-consumer',
          private: true,
          type: 'module',
        },
        null,
        2
      )}\n`
    );
    runNpm(
      [
        'install',
        '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        '--package-lock=false',
        rootTarball,
        platformTarball,
      ],
      { cwd: consumer }
    );

    writeFileSync(
      path.join(consumer, 'smoke.cjs'),
      [
        "'use strict';",
        "const assert = require('node:assert/strict');",
        "const AvlTree = require('avl-tree-rust');",
        'const tree = new AvlTree();',
        "tree.insert(2, 'two');",
        "tree.insert(1, 'one');",
        "assert.equal(tree.find(2), 'two');",
        "assert.equal(tree.dump(), \"{ key: 1, value: 'one' }, { key: 2, value: 'two' }\");",
        '',
      ].join('\n')
    );
    writeFileSync(
      path.join(consumer, 'smoke.mjs'),
      [
        "import assert from 'node:assert/strict';",
        "import AvlTree from 'avl-tree-rust';",
        'const tree = new AvlTree();',
        "tree.insert(1, 'one');",
        "assert.equal(tree.remove(1), 'one');",
        'assert.equal(tree.find(1), null);',
        '',
      ].join('\n')
    );
    runNode(path.join(consumer, 'smoke.cjs'), [], { cwd: consumer });
    runNode(path.join(consumer, 'smoke.mjs'), [], { cwd: consumer });

    writeFileSync(
      path.join(consumer, 'consumer.cts'),
      [
        "import AvlTree = require('avl-tree-rust');",
        'const tree = new AvlTree();',
        "tree.insert(1, 'one');",
        'const found: string | null = tree.find(1);',
        'void found;',
        '',
      ].join('\n')
    );
    writeFileSync(
      path.join(consumer, 'consumer.mts'),
      [
        "import AvlTree from 'avl-tree-rust';",
        'const tree = new AvlTree();',
        "tree.insert(1, 'one');",
        'const present: boolean = tree.has(1);',
        'void present;',
        '',
      ].join('\n')
    );
    writeFileSync(
      path.join(consumer, 'tsconfig.json'),
      `${JSON.stringify(
        {
          compilerOptions: {
            esModuleInterop: true,
            module: 'NodeNext',
            moduleResolution: 'NodeNext',
            noEmit: true,
            strict: true,
            target: 'ES2022',
          },
          include: ['consumer.cts', 'consumer.mts'],
        },
        null,
        2
      )}\n`
    );
    const typescriptPackage = require.resolve('typescript/package.json');
    const typescriptCli = path.join(
      path.dirname(typescriptPackage),
      'bin',
      'tsc'
    );
    runNode(
      typescriptCli,
      ['--project', path.join(consumer, 'tsconfig.json')],
      {
        cwd: consumer,
      }
    );
  } finally {
    rmSync(consumer, { recursive: true, force: true });
  }
}

writeFileSync(
  path.join(validation, 'report.json'),
  `${JSON.stringify(report, null, 2)}\n`
);
console.log(JSON.stringify(report, null, 2));
