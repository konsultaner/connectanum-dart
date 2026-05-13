# Native Transport Workspace

This workspace hosts the native runtime that will back the Dart router.
Development and verification currently target Linux and macOS.

## Layout

- `ct_core` – pure Rust crate featuring the runtime types.
- `ct_ffi` – C-compatible surface area consumed from Dart via FFI.

## Usage

```bash
cargo test
cargo build -p ct_ffi --release
bin/package-native-artifact
# Coverage (requires cargo-llvm-cov installed in PATH)
cargo llvm-cov
```

The repo-local `bin/package-native-artifact` script stages the release library,
license, and manifest into a host-specific tarball under
`out/native-artifacts/`. The GitHub Actions `Native Artifacts` workflow uses
that same script to publish downloadable Linux/macOS bundles.
