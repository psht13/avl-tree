# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

## 2.2.0 - 2026-07-25

### Changed

- Split the pure Rust AVL core from the thin NAPI-RS class boundary.
- Move owned strings during two-child deletion and skip balancing work on
  missing removals and duplicate updates.
- Build `dump()` into one output buffer while preserving its exact legacy
  format.
- Track tree length for capacity planning and invariant validation.
- Align the Rust bindings with NAPI-RS 3 so clean builds use the current CLI's
  declaration and platform-package tooling, while retaining dynamic symbol
  loading.
- Replace the checked-in single-platform binary with generated bindings,
  platform-specific optional package preparation, and actionable unsupported
  platform errors.
- Declare Node.js 22 and 24 as the supported runtime policy.

### Added

- Rust unit, invariant, deterministic stress, and property tests.
- Node.js CommonJS, ESM, conversion, mutation, and loader contract tests.
- Packed-tarball installation and declaration-resolution tests.
- Reproducible Rust and JavaScript coverage commands and LCOV output.
- Criterion and Node end-to-end benchmark harnesses.
- Cross-platform CI plus a non-publishing native release-preparation workflow.
- Contributor, architecture, benchmark, and release documentation.

### Removed

- The checked-in Linux x64 `dist/index.node` binary and duplicated generated
  declaration files.
- Unsupported claims about string keys, numeric values, legacy `search`,
  bulk insertion, universal platform support, and unmeasured performance.

### Compatibility

- The version 2.1.2 constructor and method surface is unchanged.
- Keys remain Node-API-converted signed 32-bit numbers and values remain
  strings.
- Duplicate replacement, return values, null behavior, and the exact `dump()`
  text are unchanged.
- Strict integer validation would be a future major-version change and is not
  included here.
