# Instructions for Codex agents

Read the README.md and README_NEXT.md. Understand it, read the relevant code and wamp-proto.org specs or relevant GitHub
discussions on certain topics or implementation specs. Then tell me what's next to be done.

## Before creating pull requests

- write unit tests for new code lines
- test all code on chromium and dart-vm
- have 100% coverage on new code line
- run `dart format .` to format all files
- run `dart analyze` again
- check `dart outdated`

## Running Rust tests locally

```
cd native/transport
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

`CONNECTANUM_NATIVE_LIB` defaults to `libct_ffi.so` in the current directory. so usually you can just run `dart test`.