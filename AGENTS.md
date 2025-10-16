# Instructions for Codex agents

This repository does not include a Dart SDK. If a Codex agent needs to run Dart
commands and `dart` command is not working, execute the `codex.sh` script first. This installs Dart and
exposes the `dart` command in the current session. At the same time it prepares
the chrome executable to be able to run dart tests in headless chrome.

The CI pipeline already sets up Dart on GitHub Actions, so the scripts should **not** be called from CI workflows.

After running the script or if dart is already available, run:

```
dart pub get
```

## Before creating pull requests

- write unit tests for new code lines
- test all code on chromium and dart-vm
- have 100% coverage on new code line
- run `dart format .` to format all files
- run `dart analyze` again
- check `dart outdated`

## Running Rust tests locally

The Codex sandbox blocks socket operations, so run Rust tests on your machine with repo-local `TMPDIR` and `CARGO_TARGET_DIR`:

```
cd native/transport
export TMPDIR=$(pwd)/tmp
export CARGO_TARGET_DIR=$(pwd)/target
cargo test -p ct_core
cargo test -p ct_ffi
```

(Rebuild with `cargo build -p ct_ffi --release` to refresh the shared library.)

## Running Dart tests

After exporting `CONNECTANUM_NATIVE_LIB` to the built `libct_ffi.so`, run the Dart tests from inside the package:

```
cd packages/connectanum_dart
export CONNECTANUM_NATIVE_LIB=/absolute/path/to/native/transport/target/release/libct_ffi.so
dart test test/router/router_json_test.dart test/router/router_runtime_test.dart
```

If the sandbox cannot resolve `dart` commands; run them locally or execute `./codex.sh` to install the SDK when needed.
