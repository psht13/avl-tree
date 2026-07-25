'use strict';

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const {
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const npmDirectory = path.join(root, 'npm');
const releaseDirectory = path.join(root, 'release');
const packageJsonPath = path.join(root, 'package.json');
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

function runNpm(args, cwd) {
  const result = spawnSync(process.execPath, [npmCli, ...args], {
    cwd,
    encoding: 'utf8',
    env: process.env,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.stderr.write(result.stderr);
    throw new Error(
      `npm ${args.join(' ')} failed with status ${result.status}`
    );
  }
  const parsed = JSON.parse(result.stdout);
  assert.equal(parsed.length, 1);
  return parsed[0];
}

function sha256(file) {
  return createHash('sha256').update(readFileSync(file)).digest('hex');
}

const rootPackageSource = readFileSync(packageJsonPath, 'utf8');
const rootPackage = JSON.parse(rootPackageSource);
const targetDirectories = {
  'aarch64-apple-darwin': 'darwin-arm64',
  'aarch64-unknown-linux-gnu': 'linux-arm64-gnu',
  'aarch64-unknown-linux-musl': 'linux-arm64-musl',
  'x86_64-apple-darwin': 'darwin-x64',
  'x86_64-pc-windows-msvc': 'win32-x64-msvc',
  'x86_64-unknown-linux-gnu': 'linux-x64-gnu',
  'x86_64-unknown-linux-musl': 'linux-x64-musl',
};
const expectedDirectories = rootPackage.napi.targets
  .map((target) => targetDirectories[target])
  .sort();

assert.ok(
  expectedDirectories.every(Boolean),
  'Every NAPI target must be mapped'
);
const actualDirectories = readdirSync(npmDirectory)
  .filter((entry) => statSync(path.join(npmDirectory, entry)).isDirectory())
  .sort();
assert.deepEqual(actualDirectories, expectedDirectories);

const platformPackages = actualDirectories.map((directory) => {
  const packageDirectory = path.join(npmDirectory, directory);
  const packageJson = JSON.parse(
    readFileSync(path.join(packageDirectory, 'package.json'), 'utf8')
  );
  const binaryPath = path.join(packageDirectory, packageJson.main);
  assert.ok(
    statSync(binaryPath).size > 0,
    `${packageJson.name} is missing ${packageJson.main}`
  );
  return { directory: packageDirectory, packageJson };
});

rmSync(releaseDirectory, { recursive: true, force: true });
mkdirSync(releaseDirectory, { recursive: true });

const optionalDependencies = Object.fromEntries(
  platformPackages
    .map(({ packageJson }) => [packageJson.name, rootPackage.version])
    .sort(([left], [right]) => left.localeCompare(right))
);
const releaseRootPackage = {
  ...rootPackage,
  optionalDependencies,
};

const packs = [];
try {
  writeFileSync(
    packageJsonPath,
    `${JSON.stringify(releaseRootPackage, null, 2)}\n`
  );
  packs.push(runNpm(['pack', '--json', '--ignore-scripts'], root));
} finally {
  writeFileSync(packageJsonPath, rootPackageSource);
}

for (const { directory } of platformPackages) {
  packs.push(runNpm(['pack', '--json', '--ignore-scripts'], directory));
}

for (const pack of packs) {
  const packageDirectory =
    pack.name === rootPackage.name
      ? root
      : platformPackages.find(
          ({ packageJson }) => packageJson.name === pack.name
        ).directory;
  renameSync(
    path.join(packageDirectory, pack.filename),
    path.join(releaseDirectory, pack.filename)
  );
}

const manifest = packs
  .map((pack) => ({
    name: pack.name,
    filename: pack.filename,
    size: pack.size,
    unpackedSize: pack.unpackedSize,
    sha256: sha256(path.join(releaseDirectory, pack.filename)),
    files: pack.files.map(({ path: file }) => file).sort(),
  }))
  .sort(({ name: left }, { name: right }) => left.localeCompare(right));

writeFileSync(
  path.join(releaseDirectory, 'manifest.json'),
  `${JSON.stringify(manifest, null, 2)}\n`
);
console.log(JSON.stringify(manifest, null, 2));
