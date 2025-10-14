# Native Transport Workspace

This workspace hosts the native runtime that will back the Dart router.
Development currently targets Linux while keeping the layout ready for other
platforms.

## Layout

- `ct_core` – pure Rust crate featuring the runtime types.
- `ct_ffi` – C-compatible surface area consumed from Dart via FFI.

## Usage

```bash
cargo test
cargo build -p ct_ffi --release
# Coverage (requires cargo-llvm-cov installed in PATH)
cargo llvm-cov
```

The `ct_core::Runtime::new()` constructor returns an `UnsupportedPlatform`
error on operating systems other than Linux for now.
