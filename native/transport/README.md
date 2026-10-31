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

## Runtime workers

The primary Tokio runtime keeps its automatic worker count. Cleartext MQTT TCP
and WebSocket connections move their socket and buffered input to a separate
single-worker runtime after protocol negotiation. WAMP, HTTP, TLS and secure
WebSocket connections keep the primary runtime. Both runtimes shut down with
the native engine.

Set `CONNECTANUM_NATIVE_RUNTIME_THREADS` to a positive integer to choose a
shared pool size explicitly. `TOKIO_WORKER_THREADS` remains supported when the
Connectanum override is unset. Either explicit override keeps MQTT on that
shared pool; an empty Connectanum override uses the default policy.
