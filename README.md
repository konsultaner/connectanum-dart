# connectanum-dart Monorepo

This repository hosts the next generation of the connectanum WAMP stack. It is
split into a Dart workspace that keeps the client and upcoming router code
side-by-side, and a Rust workspace that will provide the native transport
runtime.

- `packages/connectanum_dart` – Dart package containing the existing WAMP
  client and the new router modules (work in progress).
- `native/transport` – Rust workspace for the native networking runtime
  (currently a skeleton).

## Getting Started

1. Install the Dart SDK locally (or run `./codex.sh`).
2. Fetch dependencies and run tests from the Dart package:

   ```bash
   cd packages/connectanum_dart
   dart pub get
   dart test
   ```

3. Build or test the native workspace (Linux support is implemented first):

   ```bash
   cd native/transport
   cargo test
   cargo build -p ct_ffi --release
   ```

For additional package level documentation see
`packages/connectanum_dart/README.md`.
