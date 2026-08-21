# Multi-Gigabit Transfer Performance

Status: active
Started: 2026-08-21

## Goal

Reduce avoidable copies and CPU amplification in large WAMP frames and
progressive file delivery, then establish repeatable throughput, memory, and
correctness evidence across the supported transport, serializer, security, and
runtime variants. The optimization work must preserve WAMP behavior, exact byte
counts, SHA-256 receipt validation, bounded buffering, cancellation, timeout,
and backpressure semantics.

The target is at least 2 Gbit/s where the protocol and host permit it. Results
that cannot reach that target because a required transform prevents kernel
zero-copy or saturates the available CPU must be reported as an explicit,
measured boundary rather than hidden by aggregate-duplex accounting.

## Current Evidence

- The pre-change hosted Linux native 1 GiB file transfer reached 610.0 Mbit/s
  with MessagePack and 398.0 Mbit/s with CBOR. Hosted large-frame one-way
  throughput reached 637.6 Mbit/s for 32 MiB native MessagePack and 268.0
  Mbit/s for 64 MiB native CBOR.
- Local native CBOR 256 MiB file delivery improved from about 670 Mbit/s to
  1.11 Gbit/s after native receipt hashing, to 1.73 Gbit/s after exposing the
  retained binary argument directly, and to 3.41 Gbit/s after enabling the BSD
  `sendfile` path on macOS.
- The corrected sustained local file matrix uses 1 GiB per native workload and
  one native runtime thread. It reaches 3.39 Gbit/s for cleartext RawSocket
  MessagePack, 3.05 Gbit/s for cleartext RawSocket CBOR, 2.85 Gbit/s for TLS
  RawSocket CBOR, and 2.92 Gbit/s for WebSocket CBOR. Dart RawSocket CBOR
  remains at 461 Mbit/s and native E2EE CBOR with AES-GCM remains at 381
  Mbit/s because those paths still transform or copy complete payload chunks.
- Local repeated 64 MiB native CBOR RawSocket RPC reaches about 982 Mbit/s
  one-way after the first parser/allocation change, about 1.5% above the exact
  pre-change worktree on the stable repeated workload. Hosted Linux evidence
  remains required.
- The post-change canonical and high-memory RawSocket frame artifacts pass the
  transport-counter gate without alerts. Native MessagePack reaches 1.43
  Gbit/s at 32 MiB and 1.22 Gbit/s at 128 MiB one-way. CBOR reaches 580 Mbit/s
  for Dart at 64 MiB and 454 Mbit/s for native at 256 MiB, confirming that
  serializer and full-frame memory amplification remain active bottlenecks.
- The strengthened repeated large-frame matrix moves 4 GiB aggregate duplex
  traffic. One-way throughput reaches 1.44 Gbit/s for Dart and 1.76 Gbit/s for
  native 32 MiB MessagePack frames, plus 704 Mbit/s for Dart and 881 Mbit/s for
  native 64 MiB CBOR frames. Every workload passes the transport-counter gate,
  but none yet meets the 2 Gbit/s one-way target.
- Linux and macOS cleartext native RawSocket MessagePack and CBOR sending uses
  `sendfile`. Native TLS and WebSocket MessagePack/CBOR now accept the same
  file-backed frames and stream them through bounded 4 MiB positional reads;
  WebSocket keeps one RFC 6455 frame and continuous masking state across the
  prefix, file, and suffix. JSON/base64, E2EE, Dart-only, and unsupported
  paths still cannot use the filesystem-to-socket kernel path unchanged.
- A repeated 1 GiB TLS file workload passes at 3.16 Gbit/s with the canonical
  one-thread native runtime but times out with the auto-sized local runtime
  after process RSS approaches 1 GiB. This is a separate receive/retention
  scaling boundary that must be diagnosed before claiming every runtime
  configuration is production-ready.
- Exact-head GitHub CI, package dry run, and the standard WAMP benchmark
  workflow pass at `d326cd875e5e865ed1053e885d050ba3fa2d3805`. The first heavy
  hosted Linux diagnostic reaches 2.60 Gbit/s for clear native MessagePack and
  2.26 Gbit/s for clear native CBOR over 1 GiB, then terminates the TLS
  workload at exactly 30 seconds before the large-frame suite runs. The
  configured workload timeout was 300 seconds, but the blocking WAMP control
  client imposed a separate hard-coded 30-second request timeout. The harness
  now applies the configured workload timeout plus a 30-second response grace
  only to the long-running WAMP POST; health, metrics, and stop requests retain
  their 30-second default. All 56 `http_stream` tests pass, including delayed
  response and timeout regressions. A fresh hosted diagnostic remains required
  for actual TLS and large-frame Linux evidence.

## Plan

1. Remove redundant allocation and full-frame decode work while retaining lazy
   payload ownership and malformed-frame validation.
2. Move file receipt hashing onto retained native payload slices where safe,
   retaining the validated Dart fallback for transformed payloads and
   non-native transports.
3. Measure and optimize receiver file-write and serializer paths after hashing
   is no longer the dominant worker-side cost.
4. Extend the benchmark matrix with repeated large RawSocket frames and file
   transfers across MessagePack, CBOR, JSON where supported, Dart/native
   clients, TLS, WebSocket, E2EE, concurrency, and negotiated frame sizes.
5. Run `bin/verify`, local review, Linux hosted performance evidence, and the
   strict deployment audit before making a release-readiness claim.

## Verification

- Exact-worktree before/after benchmark comparisons with repeated samples.
- Focused malformed CBOR, payload ownership, fragmented read, checksum,
  cancellation, timeout, and fallback regressions.
- Heavy large-frame and file-transfer matrices with one-way throughput, total
  throughput, latency distribution, errors, and maximum RSS.
- `bin/test-fast` before substantial slices and `bin/verify` before handoff.

## Progress

- [x] Establish local and hosted baseline evidence.
- [x] Eliminate RawSocket receive-buffer zero-fill and contiguous CBOR
  full-payload reserialization while preserving lazy payload slices.
- [x] Accelerate validated file receipt hashing without changing the contract.
  Native MessagePack/CBOR receivers hash retained binary slices, retain the
  message handle through asynchronous sink use, and preserve the Dart fallback
  for transformed and non-native payloads.
- [x] Add a tested macOS `sendfile` path while retaining Linux `sendfile` and
  bounded fallback behavior elsewhere.
- [x] Add native file-backed TLS and WebSocket sending with positional reads,
  continuous WebSocket masking, serializer capability checks, and multi-chunk
  correctness regressions.
- [ ] Optimize remaining measured receive/write/serializer bottlenecks.
- [ ] Complete heavy hosted matrix evidence. The corrected local file and
  large-frame matrices pass their transport-counter gates. Hosted clear native
  MessagePack and CBOR now exceed 2 Gbit/s; the benchmark control-timeout fix
  must be rerun for TLS and large-frame evidence.
- [ ] Complete full verification and deployment audit. Local `bin/verify`
  passes on 2026-08-21 with 127 Rust core tests, 55 Rust FFI tests, the
  466-test router suite, generated consumers, live WAMP/MCP smokes, and Chrome
  Dart2Wasm. Exact-head CI, package dry run, and standard WAMP benchmarks pass;
  the heavy hosted diagnostic must pass after the harness fix before the final
  feature-branch and protected-branch audits are repeated.
