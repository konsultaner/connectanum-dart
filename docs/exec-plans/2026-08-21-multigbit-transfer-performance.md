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
- The local file matrix sustains 3.27 Gbit/s for native cleartext RawSocket
  MessagePack and 2.92 Gbit/s for native cleartext RawSocket CBOR. The same
  workload reaches 427 Mbit/s for Dart RawSocket CBOR, 778 Mbit/s for native
  TLS RawSocket CBOR, 887 Mbit/s for native WebSocket CBOR, and 354 Mbit/s for
  native E2EE CBOR with AES-GCM.
- Local repeated 64 MiB native CBOR RawSocket RPC reaches about 982 Mbit/s
  one-way after the first parser/allocation change, about 1.5% above the exact
  pre-change worktree on the stable repeated workload. Hosted Linux evidence
  remains required.
- The post-change canonical and high-memory RawSocket frame artifacts pass the
  transport-counter gate without alerts. Native MessagePack reaches 1.43
  Gbit/s at 32 MiB and 1.22 Gbit/s at 128 MiB one-way. CBOR reaches 580 Mbit/s
  for Dart at 64 MiB and 454 Mbit/s for native at 256 MiB, confirming that
  serializer and full-frame memory amplification remain active bottlenecks.
- Linux and macOS cleartext native RawSocket MessagePack and CBOR sending uses
  `sendfile`. TLS encryption, WebSocket masking, JSON/base64, E2EE, Dart-only,
  and unsupported-platform paths transform or buffer bytes and cannot use that
  filesystem-to-socket kernel path unchanged.

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
- [ ] Optimize remaining measured receive/write/serializer bottlenecks.
- [ ] Complete heavy local and hosted matrix evidence.
- [ ] Complete full verification and deployment audit. Local `bin/verify`
  passes on 2026-08-21; hosted Linux workflows and the strict audit remain.
