# Benchmarks

## Scope

The benchmark suite separates the pure Rust tree from calls through the actual
Node-API addon:

- Criterion measures tree algorithms without JavaScript conversion overhead.
- `benchmark/node.js` measures the public constructor and methods through the
  native boundary.

Both harnesses use deterministic datasets and create random keys, strings, and
tree fixtures outside timed sections. They cover 1,000, 10,000, and 100,000
nodes, plus 4,096-tree batches for removal topology. Timings are not CI
thresholds; they are comparison evidence from one controlled machine.

Lower values are better. A negative change is an improvement.

## Recorded environment

| Item                    | Value                                                 |
| ----------------------- | ----------------------------------------------------- |
| Reviewed implementation | `2e9e6b83c17f7fffcc40cefa5c9216991fcb87e4`            |
| Baseline harness commit | `173f04752e3f12e802f4d9f0ebf741dde55bb879`            |
| Final branch            | `main`                                                |
| Final implementation    | `29e48b10c086b97654e88ddd9b32de76879cab98`            |
| OS                      | macOS 26.5.2, Darwin 25.5.0                           |
| Architecture            | arm64                                                 |
| CPU                     | Apple M5                                              |
| Rust                    | `rustc 1.97.1 (8bab26f4f 2026-07-14)`                 |
| Node.js                 | `v22.22.2`                                            |
| npm                     | `10.9.7`                                              |
| Rust profile            | Criterion `bench`                                     |
| Native profile          | release, thin LTO, one codegen unit, stripped symbols |
| Rust seed               | `0x4d595df4d0f33173`                                  |
| Node seed               | `0x4d595df4`                                          |

Commit `173f047` introduced the contract and benchmark scaffolding while keeping
the reviewed AVL algorithms materially unchanged. It is therefore the
executable baseline for the exact same harness used by the final code.

## Pure Rust results

Criterion reports the median time for a complete batch. Each numbered workload
performs that many operations; each topology workload removes one node from
4,096 independently prepared trees.

| Workload                       |   Baseline |      Final | Change |
| ------------------------------ | ---------: | ---------: | -----: |
| Random insert, 1,000           |  22.600 µs |  24.805 µs |  +9.8% |
| Random insert, 10,000          | 545.349 µs | 582.522 µs |  +6.8% |
| Random insert, 100,000         |  10.907 ms |  11.253 ms |  +3.2% |
| Ascending insert, 1,000        |  25.141 µs |  25.933 µs |  +3.1% |
| Ascending insert, 10,000       | 307.328 µs | 323.797 µs |  +5.4% |
| Ascending insert, 100,000      |   3.656 ms |   3.968 ms |  +8.5% |
| Descending insert, 1,000       |  23.851 µs |  26.300 µs | +10.3% |
| Descending insert, 10,000      | 296.725 µs | 331.917 µs | +11.9% |
| Descending insert, 100,000     |   3.579 ms |   3.936 ms | +10.0% |
| Duplicate update, 1,000        |  38.121 µs |  32.571 µs | -14.6% |
| Duplicate update, 10,000       | 815.860 µs | 662.754 µs | -18.8% |
| Duplicate update, 100,000      |  13.206 ms |  11.387 ms | -13.8% |
| Successful lookup, 100,000     |   7.865 ms |   7.902 ms |  +0.5% |
| Missing lookup, 100,000        | 552.538 µs | 566.448 µs |  +2.5% |
| Leaf removal, 4,096 trees      | 238.422 µs | 190.058 µs | -20.3% |
| One-child removal, 4,096 trees | 167.688 µs | 117.526 µs | -29.9% |
| Two-child removal, 4,096 trees | 238.059 µs | 183.930 µs | -22.7% |
| Missing removal, 100,000       |   6.778 ms |   5.241 ms | -22.7% |
| Read-heavy mixed, 100,000      |  10.549 ms |  10.316 ms |  -2.2% |
| Balanced mutation, 100,000     |  19.509 ms |  19.337 ms |  -0.9% |
| `dump()`, 1,000                |  38.176 µs |  20.257 µs | -46.9% |
| `dump()`, 10,000               | 393.944 µs | 215.301 µs | -45.3% |
| `dump()`, 100,000              |   4.356 ms |   2.806 ms | -35.6% |

The expected targeted wins are visible: ownership-moving deletion improves
every removal shape, missing removals avoid unchanged-path balancing, duplicate
updates avoid unchanged-path balancing, and the one-buffer dump removes
per-node temporary strings.

New-key insertion has a measured tradeoff. Propagating whether a key was added
allows exact length tracking and lets duplicate updates leave ancestors
untouched, but costs a branch along newly inserted paths. Several safe
alternatives were prototyped—tuple/result propagation and borrowed in-place
rotation—and were materially slower. The final code keeps the smallest,
clearest safe implementation. The regression is 3.2% for the representative
100,000-key random workload and up to 11.9% for synthetic sorted workloads,
while duplicate updates improve 13.8–18.8%. A more complex structure or unsafe
pointer encoding was rejected.

## Node end-to-end results

The Node harness performs three warm-up passes and eleven measured passes per
workload. The table pools two counterbalanced baseline/final runs, or 22 samples
per side, and reports nanoseconds per public operation. Passes that overlapped
an unrelated high-CPU test process were discarded before analysis rather than
used to support a performance claim. The final runs use the aligned NAPI-RS 3
binding.

| Workload                       | Baseline median / p95 | Final median / p95 | Change |
| ------------------------------ | --------------------: | -----------------: | -----: |
| Random insert, 100,000         |    178.06 / 182.07 ns | 185.59 / 192.68 ns |  +4.2% |
| Ascending insert, 100,000      |    102.38 / 104.58 ns | 112.50 / 114.92 ns |  +9.9% |
| Descending insert, 100,000     |     99.47 / 100.89 ns | 110.72 / 112.89 ns | +11.3% |
| Duplicate update, 100,000      |    224.59 / 381.01 ns | 184.91 / 355.92 ns | -17.7% |
| Successful lookup, 100,000     |    133.24 / 136.47 ns | 118.87 / 124.45 ns | -10.8% |
| Missing lookup, 100,000        |      37.81 / 38.35 ns |   36.29 / 37.12 ns |  -4.0% |
| Missing removal, 100,000       |      75.53 / 76.75 ns |   60.78 / 61.96 ns | -19.5% |
| Read-heavy mixed, 100,000      |    143.43 / 146.70 ns | 129.06 / 133.21 ns | -10.0% |
| Balanced mutation, 100,000     |    272.60 / 279.40 ns | 261.58 / 269.09 ns |  -4.0% |
| `dump()`, 100,000              |      49.68 / 55.63 ns |   30.79 / 35.71 ns | -38.0% |
| Leaf removal, 4,096 trees      |      72.55 / 73.47 ns |   61.43 / 68.65 ns | -15.3% |
| One-child removal, 4,096 trees |      73.51 / 77.55 ns |   57.40 / 67.80 ns | -21.9% |
| Two-child removal, 4,096 trees |      70.11 / 76.39 ns |   60.07 / 62.24 ns | -14.3% |

The Node results are intentionally smaller in percentage terms for some core
operations. Node-API dispatch and JavaScript/Rust string conversion are part of
these measurements and can dominate short tree traversals. Criterion is the
appropriate evidence for pure algorithm changes; this table is the consumer's
end-to-end view. The final NAPI-RS 3 alignment also changes boundary overhead,
so the lookup and read-heavy gains in this table must not be attributed solely
to the AVL algorithm.

## Native binary size

The comparable local release artifact is the macOS arm64 binary built from
source on the same machine:

| Artifact              |   Bytes | Change |
| --------------------- | ------: | -----: |
| Baseline Mach-O addon | 512,320 |      — |
| Final Mach-O addon    | 451,536 | -11.9% |

The checked-in baseline `dist/index.node` was a 587,920-byte Linux x64 ELF
binary, so it is not used for this cross-architecture size comparison.
Aligning the Rust bindings and CLI on NAPI-RS 3 increased the final candidate
from 418,400 to 451,536 bytes (+7.9%), an accepted correctness and portability
tradeoff after a clean Linux build exposed empty declarations from mixed major
versions.

## Reproducing

Install dependencies and build release code:

```bash
npm ci
npm run build
```

Run the suites:

```bash
npm run benchmark:rust
npm run benchmark:node
node benchmark/node.js --output target/benchmarks/final-node.json
```

For a direct Criterion comparison, save a named baseline and then run the same
harness after the implementation change:

```bash
cargo bench --bench avl_tree -- --save-baseline before
cargo bench --bench avl_tree -- --baseline before
```

For an historical comparison without changing the working tree, create an
ignored detached worktree at the harness commit:

```bash
git worktree add --detach target/audit/baseline-run \
  173f04752e3f12e802f4d9f0ebf741dde55bb879
```

On macOS, that historical NAPI-RS configuration needs dynamic Node-API link
lookup for the baseline addon. From the repository root:

```bash
BASELINE_TREE_DIR="$PWD/target/audit/baseline-run"
(
  cd "$BASELINE_TREE_DIR"
  npm ci
  RUSTFLAGS="-C link-arg=-undefined -C link-arg=dynamic_lookup" npm run build
)
```

Then invoke the current Node harness with the baseline module:

```bash
AVL_TREE_MODULE="$BASELINE_TREE_DIR" \
  node benchmark/node.js \
  --output target/benchmarks/baseline-node.json
```

Run benchmarks on an otherwise idle machine, retain the JSON and Criterion
artifacts under ignored `target/benchmarks` and `target/criterion` directories,
and compare medians plus the reported spread rather than one timing.
