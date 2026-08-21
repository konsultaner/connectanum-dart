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
  one native runtime thread. Its latest complete run reaches 3.37 Gbit/s for
  cleartext RawSocket MessagePack, 3.01 Gbit/s for cleartext RawSocket CBOR,
  2.77 Gbit/s for TLS RawSocket CBOR, and 2.73 Gbit/s for WebSocket CBOR. Dart
  RawSocket CBOR remains at 450 Mbit/s and native E2EE CBOR with AES-GCM at 367
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
  traffic. Its latest complete run reaches 1.55/1.86 Gbit/s one-way for
  Dart/native 32 MiB MessagePack frames and 748/874 Mbit/s one-way for
  Dart/native 64 MiB CBOR frames. Aggregate duplex throughput is 3.10/3.72
  Gbit/s for MessagePack and 1.50/1.75 Gbit/s for CBOR. Every workload passes
  the transport-counter gate, but none yet meets the 2 Gbit/s one-way target.
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
- Exact-head heavy hosted Linux diagnostics pass at
  `1e3f1d743c448a9de680e6edad55f629f69e7bb9` after the benchmark file
  receiver inherits the configured scenario deadline. Native clear file
  transfer reaches 2.93/2.48 Gbit/s for MessagePack/CBOR, native TLS reaches
  2.16 Gbit/s, and native WebSocket reaches 2.09 Gbit/s. Dart buffered CBOR and
  native E2EE remain hard boundaries at 217 and 147 Mbit/s. Hosted large-frame
  one-way throughput is also below target: 645/830 Mbit/s for Dart/native 32
  MiB MessagePack and 379/422 Mbit/s for Dart/native 64 MiB CBOR. All 50 heavy
  workloads pass their transport and metric gates without findings.
- Native E2EE file delivery now bypasses Dart file reads and intermediate
  plaintext/ciphertext copies. The client passes positional file ranges to a
  fused Rust path that reads into the final canonical CBOR PPT allocation,
  encrypts in place with a detached AES-GCM tag, hashes the transformed bytes,
  and sends one native-backed WAMP argument. Incoming canonical single-binary
  E2EE payloads decrypt into an externally owned Rust buffer that remains
  anchored to the message and is hashed without a second Dart copy. Unsupported
  shapes retain the validated Dart fallback.
- Production AArch64 macOS and Linux builds enable runtime-detected ARMv8 AES
  and POLYVAL dispatch plus SHA-256 assembly, with safe software fallback on
  unsupported CPUs. A local 4 MiB transform probe improved AES-GCM from about
  23 ms to about 2.5 ms and SHA-256 from about 9 ms to about 1.75 ms. A chunk
  sweep found 4 MiB remains the best tested encrypted transfer granularity.
  The first exact-head artifact rehearsal passed Linux and macOS but confirmed
  GNU SHA assembly cannot compile with Windows MSVC, so the assembly feature is
  target-scoped to AArch64 Linux/macOS and Windows retains portable SHA-256.
- The latest local canonical file matrix moves 1 GiB per native workload and
  passes every transport and metric gate: clear RawSocket reaches 8.94 Gbit/s
  with MessagePack and 6.89 Gbit/s with CBOR, TLS RawSocket CBOR reaches 6.43
  Gbit/s, WebSocket CBOR reaches 5.78 Gbit/s, and true native AES-GCM E2EE CBOR
  reaches 810.91 Mbit/s. The Dart buffered CBOR reference reaches 514.37
  Mbit/s. E2EE is materially faster but remains below the 2 Gbit/s target.
- The heavy local file matrix passes at 8.82 Gbit/s for repeated 1 GiB native
  CBOR, 9.73 Gbit/s for concurrent 256 MiB native MessagePack, and 7.35 Gbit/s
  for pipelined 256 MiB native CBOR. The Dart buffered 128 MiB reference reaches
  513.75 Mbit/s.
- The heavy large-frame matrix passes all 28 samples. Native MessagePack reaches
  1.87 Gbit/s one-way for 128 MiB frames and 1.57 Gbit/s for 256 MiB frames;
  native CBOR reaches 928 and 813 Mbit/s respectively. Aggregate duplex values
  reach 3.75/3.13 Gbit/s for MessagePack and 1.86/1.63 Gbit/s for CBOR, but no
  large-frame workload reaches the 2 Gbit/s one-way target.

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
- [x] Add fused native E2EE file segments, in-place canonical PPT encryption,
  retained-message zero-copy decryption, transformed-byte hashing, exact-range
  regressions, and real-router encrypted file smoke coverage.
- [x] Enable runtime-detected AArch64 AES, POLYVAL, and SHA-256 acceleration for
  production macOS and Linux builds while preserving portable fallback.
- [x] Complete the strengthened local canonical and heavy file and large-frame
  matrices. Clear native file paths exceed the multi-gigabit target; true E2EE
  and giant one-way RawSocket frames remain explicit measured boundaries.
- [ ] Optimize remaining measured receive/write/serializer bottlenecks.
- [x] Complete heavy hosted matrix evidence. The exact-head hosted file and
  large-frame matrices pass all transport and metric gates. Clear native
  MessagePack/CBOR and segmented native TLS/WebSocket exceed 2 Gbit/s; Dart,
  E2EE, and large-frame serializer paths remain measured optimization work.
- [x] Complete full post-change local verification. `bin/verify` passes with
  127 Rust core tests, 61 ordinary Rust FFI tests, the focused `ffi-test`
  metrics regression, 372 Dart core tests, 118 MCP tests, 105 benchmark tests,
  the 466-test router suite, isolated consumers, live WAMP/MCP smokes, remote
  auth, zero-copy router follow-ups, and Chrome Dart2Wasm. A second full run
  passes after target-scoping SHA assembly away from Windows MSVC.
- [ ] Complete exact-head hosted workflow evidence and the strict deployment
  audit for the E2EE, crypto-dispatch, and heavy-scenario revision.
