# Instructions for Codex agents

Read the ROADMAP.md and ROADMAP_NEXT.md. Understand it, read the relevant code and wamp-proto.org specs or relevant GitHub
discussions on certain topics or implementation specs. Then tell me what's next to be done, once a task is finished. 
If you started working on a blocking issue, try to fix it without asking for next steps and next steps summaries.

## Blocking issues

- try to reproduce it with a unit test or a reproducible example
- work out a solution and don't tell me next steps until you are done with investigating and fixing it
- fix it and tell me next steps

## Before creating pull requests / after finishing a task

- update ROADMAP.md, ROADMAP_NEXT.md, STRUCTURE.md
- check if you wrote unit tests for new code lines
- test all code on chromium and dart-vm
- have 100% coverage on the new code lines
- run `dart format .` to format all files
- run `dart analyze` again
- run all tests in all packages and native code again to find broken code.
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