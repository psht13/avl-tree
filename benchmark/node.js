'use strict';

const { execFileSync } = require('node:child_process');
const { writeFileSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { performance } = require('node:perf_hooks');

const modulePath = process.env.AVL_TREE_MODULE || path.join(__dirname, '..');
const AvlTree = require(modulePath);

const SIZES = [1_000, 10_000, 100_000];
const SEED = 0x4d595df4;
const WARMUPS = 3;
const SAMPLES = 11;

function shuffledKeys(size) {
  const keys = Array.from({ length: size }, (_, index) => index);
  let state = SEED >>> 0;

  for (let index = keys.length - 1; index > 0; index -= 1) {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    const target = (state >>> 0) % (index + 1);
    [keys[index], keys[target]] = [keys[target], keys[index]];
  }

  return keys;
}

function entries(keys, prefix = 'value') {
  return keys.map((key) => [key, `${prefix}-${key}`]);
}

function buildTree(input) {
  const tree = new AvlTree();
  for (const [key, value] of input) {
    tree.insert(key, value);
  }
  return tree;
}

function percentile(sorted, ratio) {
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * ratio) - 1)];
}

function measure(name, size, operations, setup, run) {
  const samples = [];

  for (let iteration = 0; iteration < WARMUPS + SAMPLES; iteration += 1) {
    const fixture = setup();
    const start = performance.now();
    run(fixture);
    const elapsedNs = (performance.now() - start) * 1e6;

    if (iteration >= WARMUPS) {
      samples.push(elapsedNs / operations);
    }
  }

  samples.sort((a, b) => a - b);
  const median = percentile(samples, 0.5);
  const deviations = samples
    .map((sample) => Math.abs(sample - median))
    .sort((a, b) => a - b);

  return {
    name,
    size,
    operations,
    unit: 'ns/op',
    median: Number(median.toFixed(2)),
    p95: Number(percentile(samples, 0.95).toFixed(2)),
    mad: Number(percentile(deviations, 0.5).toFixed(2)),
    samples: samples.map((sample) => Number(sample.toFixed(2))),
  };
}

function topologyTrees(input, count) {
  return Array.from({ length: count }, () => buildTree(input));
}

const results = [];

for (const size of SIZES) {
  const randomKeys = shuffledKeys(size);
  const randomEntries = entries(randomKeys);
  const ascendingEntries = entries(Array.from({ length: size }, (_, key) => key));
  const descendingEntries = [...ascendingEntries].reverse();

  for (const [name, input] of [
    ['insert/random', randomEntries],
    ['insert/ascending', ascendingEntries],
    ['insert/descending', descendingEntries],
  ]) {
    results.push(
      measure(
        name,
        size,
        size,
        () => input,
        (fixture) => buildTree(fixture)
      )
    );
  }

  results.push(
    measure(
      'duplicate_update',
      size,
      size,
      () => ({
        tree: buildTree(randomEntries),
        updates: entries(randomKeys, 'replacement'),
      }),
      ({ tree, updates }) => {
        for (const [key, value] of updates) {
          tree.insert(key, value);
        }
      }
    )
  );

  results.push(
    measure(
      'lookup/successful',
      size,
      size,
      () => buildTree(randomEntries),
      (tree) => {
        for (const key of randomKeys) {
          tree.find(key);
        }
      }
    )
  );

  const missingKeys = Array.from({ length: size }, (_, key) => size + key);
  results.push(
    measure(
      'lookup/missing',
      size,
      size,
      () => buildTree(randomEntries),
      (tree) => {
        for (const key of missingKeys) {
          tree.find(key);
        }
      }
    )
  );

  results.push(
    measure(
      'remove/missing',
      size,
      size,
      () => buildTree(randomEntries),
      (tree) => {
        for (const key of missingKeys) {
          tree.remove(key);
        }
      }
    )
  );

  results.push(
    measure(
      'mixed/read_heavy',
      size,
      size,
      () => buildTree(randomEntries),
      (tree) => {
        for (let index = 0; index < randomKeys.length; index += 1) {
          const key = randomKeys[index];
          if (index % 10 === 0) {
            tree.insert(key, `updated-${index}`);
          } else {
            tree.find(key);
          }
        }
      }
    )
  );

  results.push(
    measure(
      'mixed/balanced_mutation',
      size,
      size,
      () => buildTree(randomEntries),
      (tree) => {
        for (let index = 0; index < randomKeys.length; index += 1) {
          const key = randomKeys[index];
          if (index % 2 === 0) {
            tree.find(key);
          } else {
            tree.remove(key);
            tree.insert(key, `reinserted-${index}`);
          }
        }
      }
    )
  );

  results.push(
    measure(
      'dump',
      size,
      size,
      () => buildTree(randomEntries),
      (tree) => tree.dump()
    )
  );
}

const topologyBatch = 4_096;
for (const [name, input, key] of [
  ['remove/leaf', [[2, 'two'], [1, 'one'], [3, 'three']], 1],
  ['remove/one_child', [[2, 'two'], [1, 'one']], 2],
  ['remove/two_children', [[2, 'two'], [1, 'one'], [3, 'three']], 2],
]) {
  results.push(
    measure(
      name,
      topologyBatch,
      topologyBatch,
      () => topologyTrees(input, topologyBatch),
      (trees) => {
        for (const tree of trees) {
          tree.remove(key);
        }
      }
    )
  );
}

function commandVersion(command, args) {
  try {
    return execFileSync(command, args, { encoding: 'utf8' }).trim();
  } catch {
    return 'unavailable';
  }
}

const report = {
  metadata: {
    implementationCommit:
      process.env.BENCHMARK_IMPLEMENTATION_COMMIT ||
      commandVersion('git', ['rev-parse', 'HEAD']),
    harnessCommit: commandVersion('git', ['rev-parse', 'HEAD']),
    timestamp: new Date().toISOString(),
    platform: `${os.platform()} ${os.release()}`,
    architecture: os.arch(),
    cpu: os.cpus()[0]?.model || 'unknown',
    rust: commandVersion('rustc', ['--version']),
    node: process.version,
    profile: 'release',
    seed: `0x${SEED.toString(16)}`,
    sizes: SIZES,
    warmups: WARMUPS,
    samples: SAMPLES,
    modulePath,
  },
  results,
};

const outputIndex = process.argv.indexOf('--output');
if (outputIndex !== -1) {
  const output = process.argv[outputIndex + 1];
  if (!output) {
    throw new Error('--output requires a file path');
  }
  writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`);
}

console.log(JSON.stringify(report, null, 2));
