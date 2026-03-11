# Repository Guidelines

## Project Structure & Module Organization
HHVM is a large CMake-based monorepo. Core runtime and VM code lives under `hphp/runtime`, `hphp/hhvm`, and `hphp/util`. The Hack toolchain and Rust/OCaml components live under `hphp/hack/src`. End-to-end language and runtime tests live in `hphp/test`, with `quick`, `slow`, `zend`, and `server` suites. Supporting build, packaging, and CI files are in `CMake/`, `ci/`, and `build/`. Vendored dependencies are under `third-party/`; avoid changing them unless the task is explicitly dependency-related.

## Build, Test, and Development Commands
Initialize submodules before building:

```bash
git submodule update --init --recursive
./configure -DCMAKE_BUILD_TYPE=Debug
cmake --build . -j"$(nproc)"
```

Use `./configure` to pass CMake options at the repo root. For a packaging-style CI build, run `ci/bin/make-debianish-package`. For local validation, the main test entry point is `hphp/test/run`:

```bash
hphp/test/run test/quick
hphp/test/run test/slow/ext_array
hphp/test/run --typechecker slow
```

## Coding Style & Naming Conventions
Follow [`hphp/doc/coding-conventions.md`](hphp/doc/coding-conventions.md) for C++ changes. `.cpp`, `.h`, `CMakeLists.txt`, and `*.cmake` files use 2-space indentation via `.editorconfig`. Prefer `#pragma once`, include the matching header first, group includes by category, and keep them alphabetized. New HHVM code should live in `namespace HPHP`. Match local naming patterns when touching older code. For Rust changes, format with the repo settings in `rustfmt.toml`, for example `cargo fmt --manifest-path hphp/hack/src/Cargo.toml`.

## Testing Guidelines
Add or update tests with every behavior change. Default new runtime tests to `hphp/test/slow/...`; reserve `hphp/test/quick/...` for high-signal, low-duplication coverage. Name tests descriptively and pair source files with `.expect`, `.expectf`, or typechecker expectation files as documented in [`hphp/test/README.md`](hphp/test/README.md). Run the narrowest relevant suite locally before opening a PR.

## Commit & Pull Request Guidelines
Recent history favors short, imperative subjects such as `Fix infinite loop...` or `Validate enum names...`. Keep the first line concise and behavior-focused. Pull requests should explain the bug or feature, summarize the approach, list local test coverage, and link the relevant issue when available. Include screenshots only for user-visible tooling/UI changes. Contributors must complete the CLA described in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Security & Configuration Tips
Report vulnerabilities through [`SECURITY.md`](SECURITY.md), not public issues. Keep machine-specific build flags out of commits, and do not commit generated packaging artifacts or local configuration files.
