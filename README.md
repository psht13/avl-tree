# avl-tree-rust

[![CI](https://github.com/psht13/avl-tree/actions/workflows/ci.yml/badge.svg)](https://github.com/psht13/avl-tree/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`avl-tree-rust` is a Node.js native addon that stores signed 32-bit integer keys
and string values in a self-balancing AVL tree implemented in safe Rust. It
exports one constructor with insertion, lookup, membership, removal, and an
in-order debug dump while preserving the JavaScript API published in version
2.1.2.

## Installation

```bash
npm install avl-tree-rust
```

The repository prepares platform-specific optional npm packages instead of
shipping one developer machine's native binary as a universal artifact. The
current npm registry release predates that packaging scheme; the new platform
packages will become available only after a maintainer performs a future
release.

## Runtime support

The support policy is Node.js 22 and 24 on these native targets:

| Operating system | Architectures | C library      |
| ---------------- | ------------- | -------------- |
| Linux            | x64, arm64    | glibc and musl |
| macOS            | x64, arm64    | system         |
| Windows          | x64           | MSVC           |

Normal CI exercises Node.js 22 and 24, plus native builds on Linux x64, macOS
arm64, macOS x64, and Windows x64. The release-preparation workflow also builds
Linux arm64 and musl artifacts. Unsupported combinations fail with an error
that includes the detected platform and architecture.

This package is for Node.js and is not a browser or WebAssembly package.

## Usage

### CommonJS

```js
const AvlTree = require('avl-tree-rust');

const tree = new AvlTree();
tree.insert(10, 'ten');
tree.insert(5, 'five');
tree.insert(15, 'fifteen');

console.log(tree.find(10)); // 'ten'
console.log(tree.has(7)); // false
console.log(tree.remove(5)); // 'five'
console.log(tree.dump());
// "{ key: 10, value: 'ten' }, { key: 15, value: 'fifteen' }"
```

### ES modules

```js
import AvlTree from 'avl-tree-rust';

const tree = new AvlTree();
tree.insert(-1, 'one below zero');
console.log(tree.find(-1)); // 'one below zero'
```

## Data contract

Keys are JavaScript numbers converted by Node-API to Rust `i32`; values must be
JavaScript strings. Applications should pass integers in the inclusive range
`-2_147_483_648` through `2_147_483_647`.

For compatibility with version 2.1.2, conversion currently follows Node-API
int32 behavior:

- fractional numbers truncate toward zero;
- `NaN`, `Infinity`, and `-Infinity` convert to `0`;
- out-of-range numbers wrap to the corresponding signed 32-bit value;
- non-number keys and non-string values throw a type error;
- missing required arguments throw, while extra arguments are ignored.

These coercions are documented compatibility behavior, not a recommendation.
Changing them to strict integer validation would require a future major release.

Inserting an existing key replaces its value without adding another node.
JavaScript strings returned by `find` are independent values and remain valid
after later tree mutations.

## API

### `new AvlTree()`

Creates an empty tree. Extra constructor arguments are ignored.

### `tree.insert(key, value): void`

Adds `key` with the string `value`, or replaces the value at an existing key.
The JavaScript return value is `undefined`.

### `tree.find(key): string | null`

Returns the value stored at `key`, or `null` when the key is absent. An empty
string is returned as `''`, not `null`.

### `tree.remove(key): string | null`

Removes `key` and returns its previous value. Returns `null` without changing
the tree when the key is absent.

### `tree.has(key): boolean`

Returns `true` when `key` exists and `false` otherwise.

### `tree.dump(): string`

Returns entries in ascending key order using the legacy format:

```text
{ key: 1, value: 'one' }, { key: 2, value: 'two' }
```

An empty tree returns `''`. Values are not escaped, so quotes, commas, and braces
can make the output ambiguous. `dump()` is a human-readable debugging aid, not a
stable serialization format; do not parse it or persist it as data.

## Complexity

| Operation | Worst-case time |                         Auxiliary space |
| --------- | --------------: | --------------------------------------: |
| `insert`  |      `O(log n)` |                              `O(log n)` |
| `find`    |      `O(log n)` |                                  `O(1)` |
| `has`     |      `O(log n)` |                                  `O(1)` |
| `remove`  |      `O(log n)` |                              `O(log n)` |
| `dump`    |          `O(n)` | `O(n)` output plus `O(log n)` traversal |

AVL balancing keeps tree height logarithmic, but algorithmic complexity does
not remove the Node-API call boundary or JavaScript/Rust string-conversion cost.
For very small operations that boundary can dominate the tree work. See
[BENCHMARKS.md](https://github.com/psht13/avl-tree/blob/main/BENCHMARKS.md) for
measured workloads, results, and reproduction instructions.

## Architecture

- [`src/tree.rs`](https://github.com/psht13/avl-tree/blob/main/src/tree.rs)
  contains the pure Rust tree, rotations, ownership logic, traversal, and
  test-only invariants.
- [`src/lib.rs`](https://github.com/psht13/avl-tree/blob/main/src/lib.rs) is the
  thin NAPI-RS class boundary.
- [`native.js`](native.js) and [`native.d.ts`](native.d.ts) are deterministic
  generated bindings.
- [`index.js`](index.js) and [`index.d.ts`](index.d.ts) preserve the default
  constructor export for CommonJS, ESM, and type consumers.

The production implementation remains one Rust crate plus plain JavaScript.
There is no TypeScript implementation and no install-time binary downloader.

## Development

The repository pins Rust in `rust-toolchain.toml`. Local development also needs
Node.js 22 or 24, npm, and the platform's native linker toolchain.

```bash
npm ci
npm run build
npm test
npm run validate
```

Useful focused commands:

| Command                | Purpose                                           |
| ---------------------- | ------------------------------------------------- |
| `npm run test:rust`    | Rust unit, invariant, and property tests          |
| `npm run test:node`    | Node consumer contract tests                      |
| `npm run test:package` | Pack, install, load, and type-check real tarballs |
| `npm run coverage`     | Rust and handwritten JavaScript coverage          |
| `npm run benchmark`    | Criterion and Node end-to-end benchmarks          |
| `npm run format`       | Write Prettier and rustfmt changes                |
| `npm run format:check` | Check formatting without modifying files          |
| `npm run lint`         | Check JavaScript with ESLint                      |
| `npm run native:check` | Rebuild and verify generated bindings are clean   |
| `npm run pack:check`   | Validate metadata and packed file contents        |
| `npm run validate`     | Run every reasonable local merge gate             |

Rust coverage requires
[`cargo-llvm-cov`](https://github.com/taiki-e/cargo-llvm-cov):

```bash
cargo install cargo-llvm-cov --version 0.8.7 --locked
rustup component add llvm-tools-preview
```

See
[CONTRIBUTING.md](https://github.com/psht13/avl-tree/blob/main/CONTRIBUTING.md)
for setup, testing, benchmarks, pull requests, and the non-publishing
release-preparation process.

## License

[MIT](LICENSE)
