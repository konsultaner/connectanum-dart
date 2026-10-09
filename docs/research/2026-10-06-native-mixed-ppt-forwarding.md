# Native body reuse for mixed binary PPT routes

Status: implemented and fully verified locally; resulting-head hosted
acceptance and artifacts remain pending.

The [WAMP Payload Passthru specification](https://wamp-proto.org/wamp_latest_ietf.html)
requires one binary argument, with absent or empty outer keyword arguments.
The inner payload serializer is independent of the negotiated outer serializer.
A router forwards encrypted and custom-scheme bytes without interpreting their
application schema or decrypting them. JSON requires its binary Base64 conversion.

The preceding native eligibility in `runtime/ffi.rs` permits homogeneous forwarding
and ordinary CBOR/FlatBuffers routes sharing CBOR argument spans. It rejects
mixed PPT/transparent routes, so they use the existing Dart conversion path.
The new bridge retains valid PPT
bodies between all three binary codecs. Live fail-first assertions also exposed
explicit Dart RPC exclusions for the reserved `wamp` scheme, including
homogeneous encrypted routes. Those exclusions are removed: the router changes
routing controls without interpreting the encrypted application body. Custom
INVOCATION detail, timeout and transaction-hash restrictions remain intact.
CBOR/MessagePack parse results retain encoded argument-list spans. The existing
single-binary-argument readers validate the container and borrow its body.
FlatBuffers uses a separate transparent body span, excluding ordinary arguments
and keyword vectors. This allows retaining the body while
rebuilding only the outer wrapper.

The bridge covers CBOR, MessagePack and FlatBuffers in both directions.
The initial checkpoint requires explicit valid PPT metadata, one binary body
and absent outer kwargs. The subsequent [empty-keyword optimization](2026-10-06-native-empty-ppt-keywords.md) verifies and retains valid empty
CBOR/MessagePack outer maps too; nonempty and malformed shapes retain fallback. Ordinary routing stays unchanged.
The bridge must preserve scheme/serializer/cipher/key metadata and progressive
and error-routing fields. It must not infer an application schema or restrict
valid opaque bytes to a particular cipher or application scheme.

The binary targets need a small list/bin wrapper followed by a retained body
segment; FlatBuffers needs its transparent vector. An empty binary body must
remain present and distinguishable from an absent argument or empty argument
list. Source storage must outlive every derived send, including empty spans;
pointer identity alone cannot prove a zero-length span's lifetime.

Fail-first verification reproduced the eligibility and echo-metadata failures.
The resulting checks cover all binary directions, forwarding kinds, empty and
large bodies, trailing ranges, metadata, retained storage after source-handle
release, malformed/rejected
shapes, and real mixed RPC/pub/sub. Existing ownership and CI gates remain intact.
The Rust matrix passes 405 direction/body-size/forwarding-kind combinations,
plus malformed metadata, wrapper, mixed-vector and kwargs rejection controls.
Nonempty pointers are reused; even empty-body producers survive source-handle
release and fan-out until the final segment is dropped exactly once.
Six new encrypted/typed live CBOR-to-MessagePack assertions fail against the
preceding production library, while a non-forwarding custom-details control
passes. The expanded current-library live assertions exposed 28 reserved-scheme
fallbacks before the Dart exclusion repair; wire semantics already passed.
Body reuse at this boundary does not establish whole-pipeline transcode copy
counts or benchmark parity.

Local GLM review raised metadata validation, fallback checks and empty-span
lifetime risks. The specification resolves its suggested scheme whitelist:
routers must treat valid PPT bodies as opaque regardless of their inner scheme.
The remaining concerns require source validation and regression tests.

All 109 current public routing and eligibility cases pass after the reserved
scheme repair. They include the six new CBOR/MessagePack directions/modes,
encrypted RPC and ERROR, progressive results, pub/sub, custom-detail fallback,
JSON conversion and the legacy optional-ABI control. The final local GLM review
checks the Rust/Dart change together. Its segment-framing concern is covered by
the actual socket tests; its empty-body concern is covered by the 405-case
identity/lifetime matrix. The borrowed single-binary readers require the body
to end exactly at the source span boundary. Unsupported mixed kwargs shapes
never enter the native conversion helper. No review concern is accepted as a
confirmed defect without source or test evidence.

Reproduce the focused native checks from the repository root:

```sh
cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi \
  segmented_forwarding_tests -- --test-threads=1
CARGO_TARGET_DIR=native/transport/target/ffi-test cargo build \
  --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test --release
```

Then run `test/router_flatbuffers_session_ppt_test.dart` and
`test/native/mixed_forwarding_test.dart` with `dart test --concurrency=1` from
`packages/connectanum_router`, setting `CONNECTANUM_NATIVE_LIB` to the freshly
built host library under `native/transport/target/ffi-test/release`. Canonical
handoff checks remain `bin/test-fast` and `bin/verify`.

The corrected worker regression exercises both unavailable-handle fallback and
native encrypted RPC transfer without application decoding. All 204 worker/live
cases pass. Canonical `bin/test-fast` passes before the test-only repair; fresh
root analysis and full `bin/verify` pass after it, including Rust, VM, consumers,
1,563 benchmark, 4,958 router, 4,690 core Chrome/Dart2Wasm and 2,829 client browser
cases (20 declared native-only skips). GuardMalloc passes 83 ownership cases
with all 141 native/schema inputs unchanged. Existing coverage and performance
thresholds remain intact; this evidence does not establish benchmark parity.
