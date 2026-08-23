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
- Production AES-GCM and receipt hashing use `ring`'s runtime-dispatched
  implementations on every supported target, with portable fallback selected
  by that backend when hardware acceleration is unavailable. A local 4 MiB
  transform probe improved AES-GCM from about 23 ms to about 2.5 ms and SHA-256
  from about 9 ms to about 1.75 ms. A chunk sweep found 4 MiB remains the best
  tested encrypted transfer granularity. The earlier direct `sha2` dependency
  and its target-specific GNU assembly feature are no longer part of the FFI
  production path.
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
- Corrected exact-head hosted Linux diagnostics at `9bf8cbb8` pass every file,
  transport, and metric gate. Native MessagePack/CBOR file transfer reaches
  2.98/2.49 Gbit/s, segmented TLS/WebSocket reaches 2.13/2.17 Gbit/s, Dart
  buffered CBOR reaches 262 Mbit/s, and true native AES-GCM E2EE reaches 347
  Mbit/s. The E2EE result is more than twice the preceding 147 Mbit/s hosted
  baseline but remains below target.
- The hosted standard large-frame matrix also confirms the remaining boundary:
  one-way throughput reaches 665/818 Mbit/s for Dart/native 32 MiB MessagePack
  and 380/457 Mbit/s for Dart/native 64 MiB CBOR. All workloads pass without
  transport alerts; aggregate duplex figures are not used for the target.
- Exact native internal RPC echoes now retain the incoming CALL handle across
  router isolates and compose the final RESULT from the original MessagePack or
  CBOR payload slices. The fast path is restricted to an unchanged serializer,
  exact argument/keyword byte views, and an ordinary final YIELD; progressive,
  PPT, error, and modified responses retain the existing validated fallback and
  every clone has one explicit release owner.
- The large-frame runner now prepares one immutable encoded request-byte
  template before timing and creates a fresh lazy payload wrapper per call.
  Concurrent calls share only the encoded `Uint8List`, not mutable decode,
  anchor, or provider state. It logs encoded lengths without forcing ordinary
  lazy result materialization. Transformed payloads are still unpacked inside
  the timed operation so E2EE measurements include receive-side decryption. The
  previous debug interpolation retained or decoded each giant result and could
  stall after roughly eight 128 MiB calls. A regression proves RPC timing does
  not invoke the result decoder, and the native heavy sample volume is doubled
  to 16 x 128 MiB and 8 x 256 MiB per serializer.
- The corrected local heavy matrix moves 16 GiB bidirectionally across native
  workloads and passes: one-way response throughput reaches 8.48/5.19 Gbit/s
  for 128 MiB MessagePack/CBOR and 5.53/3.60 Gbit/s for 256 MiB. The standard
  matrix reaches 6.83 Gbit/s for 32 MiB native MessagePack and 2.83 Gbit/s for
  64 MiB native CBOR. Dart reaches 3.33 Gbit/s for 32 MiB MessagePack, but CBOR
  remains a measured boundary at 1.52 Gbit/s for 64 MiB and 1.19 Gbit/s for
  128 MiB; native giant frames now clear the target across both serializers.
- Exact-head CI `32510532801` at `307f0743` exposed that sharing the original
  mutable lazy wrapper across six concurrent native CBOR RPC peers could time
  out the first call group and poison later session setup until the Fast Checks
  job limit. The per-call wrapper correction retains the shared encoded bytes.
  A focused identity regression, six consecutive exact real-router repro runs,
  the full 30-test transport integration, `bin/test-fast`, and full
  `bin/verify` pass locally; fresh hosted evidence remains pending for the
  follow-up commit.
- Follow-up CI at `dec8af426be174ab9af0c9605081b42fde04b39e` reached the
  unchanged Dart CBOR cross-connection large-payload case, then exposed a
  native message-retention self-deadlock. `clone_message` kept a `DashMap` read
  guard while inserting the retained handle, so source and destination IDs on
  one shard could block forever. The clone now scopes and drops the guard before
  insertion. A deterministic same-shard regression, all 63 ordinary FFI tests,
  50 consecutive focused real-router repetitions, the full 30-test transport
  integration, `bin/test-fast`, and full `bin/verify` pass locally; fresh hosted
  CI, package, native artifact, Router Image, and standard WAMP evidence passes
  at `799ce1d0`. Heavy diagnostics stalled once in the first TLS file sample,
  then passed unchanged on attempt two. Clear native MessagePack/CBOR file paths
  reach 2.87/2.40 Gbit/s, bounded TLS/WebSocket paths reach 2.17/2.20 Gbit/s,
  and E2EE remains a measured boundary at 353 Mbit/s. Native large RawSocket
  MessagePack reaches 3.43 Gbit/s one-way, while hosted native CBOR remains below
  target at 1.54 Gbit/s and Dart MessagePack/CBOR reach 1.76/0.92 Gbit/s. The
  exact-head content audit and protected `master` strict audit both pass.
- Native Call and Publish request frames with retained MessagePack or CBOR
  payloads now remain segmented through serializer output and the native send
  queue. Dart fills exact-size Rust-owned buffers once; RawSocket and WebSocket
  consume the resulting `Bytes` without a second FFI-side copy or contiguous
  frame assembly. Optional symbols retain compatibility with older native
  libraries. Three final local repetitions produce median one-way response
  throughput of 8.00 Gbit/s for native 32 MiB MessagePack and 2.97 Gbit/s for
  native 64 MiB CBOR, versus 3.50/1.56 Gbit/s for Dart. Full `bin/verify`
  passes; one first-run HTTP/3 direct-JSON helper timeout passed in isolation
  and did not recur in the unchanged complete retry. Exact-head `3cd390c9`
  hosted CI, package dry run, standard/heavy WAMP workflows, five-platform
  native artifact rehearsal, Router Image dry run, comprehensive audit, and
  protected `master` strict audit all pass. Hosted native large-frame
  MessagePack/CBOR reach 3.62/1.55 Gbit/s; hosted clear native file paths remain
  above target at 2.84/2.32 Gbit/s for MessagePack/CBOR.
- The pure-Dart CBOR and MessagePack fast paths now inspect the outer arguments
  token before considering the direct-binary extension. Ordinary single-field
  argument arrays remain encoded and lazy instead of being fully decoded and
  discarded on every Result, Event, or Invocation; definite direct CBOR byte
  strings are exposed as frame-backed views. Deferred-malformed-payload and
  direct-binary aliasing regressions pass. Three complete local 32/64 MiB
  RawSocket repetitions produce median one-way response throughput of
  4.63/7.90 Gbit/s for Dart/native MessagePack and 2.79/2.95 Gbit/s for
  Dart/native CBOR, clearing the target in every current large-frame row. Full
  `bin/verify` passes, including the 380-test core suite, the 467-test router
  suite, consumer/live MCP smokes, remote auth, and Chrome Dart2Wasm.
- Concurrent native TLS file transfers now flush each completed WAMP frame
  before waiting for the next queue item. A deterministic two-client 16-frame
  regression reproduced the missing terminal frame before the fix and passes
  five consecutive runs after it. Same-serializer plain progressive CALL
  chunks retain native payload forwarding through an ABI-safe v2 invocation
  export; all serializers preserve `INVOCATION.Details.progress`, while PPT,
  custom-detail, timeout, transaction-hash, and mixed-serializer cases keep the
  Dart fallback. The post-fix canonical and heavy file/large-frame matrices all
  pass their artifact gates. Native file paths reach 4.99-13.49 Gbit/s across
  clear/TLS/WebSocket workloads, and native 32-256 MiB RawSocket frames reach
  2.91-9.29 Gbit/s. Dart buffered file transfer, native E2EE, and 128 MiB Dart
  CBOR remain measured sub-target boundaries at 607-630 Mbit/s, 811 Mbit/s,
  and 1.68 Gbit/s respectively.
- Native E2EE file preparation now runs off the async socket runtime, validates
  exact transformed lengths before framing, and uses `ring` AES-256-GCM and
  SHA-256.
  Progressive PPT chunks retain native router forwarding only when their
  scheme, serializer, cipher, and key ID exactly match the initiating CALL.
  A sustained 4 GiB run improves from 791.90 Mbit/s to 2.185 Gbit/s. The
  checked-in heavy file matrix now retains the same 4 GiB encrypted workload
  and passes it at 2.165 Gbit/s, alongside 15.70 Gbit/s repeated native CBOR,
  15.83 Gbit/s concurrent native MessagePack, and 10.11 Gbit/s pipelined native
  CBOR. Its pure-Dart buffered reference remains below target at 1.678 Gbit/s.
  The prior exact-head hosted diagnostic remains below target at 858.99 Mbit/s
  for E2EE, 774.71 Mbit/s for Dart buffered file delivery, and 1.570 Gbit/s for
  the native 64 MiB CBOR RPC control, so fresh hosted evidence is required.
  The full file matrix reaches 5.02-13.11 Gbit/s across native
  clear/TLS/WebSocket paths. The heavy native 128/256 MiB RawSocket matrix
  reaches 3.81-9.55 Gbit/s one-way
  and 7.62-19.10 Gbit/s aggregate across CBOR and MessagePack. Its 128 MiB
  Dart CBOR reference reaches 2.80 Gbit/s one-way and 5.60 Gbit/s aggregate.
  Transformed paths cannot preserve literal kernel zero copy.
- Fragmented pure-Dart RawSocket frames of at least 64 KiB now accumulate in
  FFI-finalized external memory. Direct CBOR and MessagePack binary arguments
  remain frame-backed and native SHA-256 hashes their anchored ranges without a
  Dart copy. Buffered file senders use a local cooperative drain and a 4 MiB
  default chunk, while native file, `sendfile`, and E2EE segments remain on
  their existing native paths. The final heavy file gate passes at 15.28-15.49
  Gbit/s for repeated/concurrent native paths, 9.82 Gbit/s pipelined, 4.57/4.56
  Gbit/s for Dart CBOR/MessagePack, and 2.14 Gbit/s for E2EE. The heavy 128/256
  MiB RawSocket gate passes all rows at 2.82-9.67 Gbit/s one-way. Full
  `bin/verify` passes with 132 Rust core, 72 ordinary Rust FFI, 385 Dart core,
  118 MCP, 108 benchmark/live-WAMP, and 468 router tests plus consumer,
  remote-auth, native-forwarding, and Chrome Dart2Wasm coverage. Exact-head CI,
  package dry run, WAMP diagnostics, and the unchanged profile-gate retry pass;
  the comprehensive feature-head audit and protected `master` strict audit are
  clean.
- Native JSON file delivery now uses a bounded native base64 file-segment mode
  and native canonical invocation decode instead of reading, encoding, or
  decoding each file chunk in Dart. Exact empty/padding/multi-chunk RawSocket
  and masked-WebSocket regressions pass, while noncanonical JSON retains the
  Dart fallback. The exact final 64 MiB matrix reaches 6.59/6.50/6.03 Gbit/s
  for native JSON over clear RawSocket/TLS/WebSocket and 8.56-14.41 Gbit/s for
  native MessagePack/CBOR. A sustained 4 GiB native JSON row reaches 8.95
  Gbit/s and sustained E2EE remains above target at 2.16 Gbit/s. Pure-Dart JSON
  remains a measured transform boundary at 1.20-1.26 Gbit/s. The expanded
  32-256 MiB JSON/MessagePack/CBOR RawSocket matrices pass every local row at
  2.55-17.05 Gbit/s aggregate. Full exact-tree `bin/verify` passes with 134
  Rust core tests, 74 ordinary Rust FFI tests, all Dart package suites,
  consumer and live WAMP/MCP smokes, remote auth, router-native follow-ups,
  benchmark integration, and Chrome Dart2Wasm.
- Benchmark throughput now uses the measured WAMP operation window when the
  worker supplies valid bounds and retains lifecycle throughput as a separate
  setup/teardown-inclusive result. Legacy responses fall back to lifecycle
  time, and dominant-direction accounting correctly measures upload-only file
  delivery. The final heavy 128/256 MiB frame suite passes all nine rows at
  2.985-22.050 Gbit/s over the data window. Its short Dart JSON row measures
  1.761 Gbit/s including lifecycle, while a sustained run reaches 3.598 Gbit/s
  over the data window and 3.253 Gbit/s including lifecycle.
- The final eight-row heavy file suite clears 2 Gbit/s over both data and
  lifecycle windows. Native paths reach 9.936-19.392 Gbit/s data-window and
  8.957-15.526 Gbit/s lifecycle throughput. Dart CBOR, MessagePack, and JSON
  reach 5.397/5.344, 5.373/5.275, and 2.713/2.690 Gbit/s respectively, and the
  sustained native AES-GCM E2EE row reaches 2.200/2.147 Gbit/s. The same run
  exposed and fixed premature remote-error observation and false receiver
  capacity failures for synchronous sinks; focused regressions and full
  `bin/verify` pass. Exact-head CI `32585919050`, package dry run
  `32585919054`, WAMP profile benchmarks `32585942593`, WAMP profile
  diagnostics `32585946481`, the comprehensive feature-head audit, and the
  protected `master` strict audit are clean.
- Exact-head hosted diagnostics `32598079549` showed why host-permitted
  boundaries must not be hidden inside one scenario-wide threshold. All four
  native non-E2EE production rows clear 2 Gbit/s over both windows, while the
  pure-Dart JSON fallback reaches 1.223/1.217 Gbit/s and native AES-GCM E2EE
  reaches 1.025/1.000 Gbit/s on the shared two-vCPU runner. The 2 Gbit/s value
  is unchanged and now selects the four intended production workloads; the
  reference and encrypted transform rows remain present and reported in the
  heavy artifact. A local chunk/concurrency sweep found 4 MiB at eight
  concurrent sessions is the first encrypted shape to clear both windows at
  2.233/2.028 Gbit/s, while 16-64 MiB chunks regress to
  1.280-1.453 Gbit/s. The checked-in E2EE stress keeps the same 4 GiB volume
  and adopts that measured eight-session shape. The complete updated 24 GiB
  matrix passes locally at 8.993-20.559/8.212-16.464 Gbit/s data/lifecycle for
  the four gated native rows and 2.317/2.253 Gbit/s for E2EE.

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
- [x] Use `ring`'s runtime-dispatched AES-GCM and SHA-256 implementations across
  supported production targets while preserving portable fallback.
- [x] Complete the strengthened local canonical and heavy file and large-frame
  matrices. Clear native file paths exceed the multi-gigabit target; true E2EE
  and giant one-way RawSocket frames remain explicit measured boundaries.
- [x] Remove router-isolate copies from exact native internal RPC echoes and
  correct large-frame benchmark payload/result lifetime amplification. The
  repeated 128/256 MiB native MessagePack and CBOR matrix now clears 2 Gbit/s
  one-way while preserving fallback semantics and handle ownership tests.
  Encoded request bytes are shared across samples, while every concurrent call
  receives an independent mutable lazy wrapper.
- [x] Remove the native retained-message self-deadlock revealed by concurrent
  large-frame routing. The message-store clone releases its shard guard before
  inserting the new handle, with a deterministic same-shard regression and
  repeated real-router evidence.
- [x] Remove contiguous-frame assembly and the second FFI copy from native
  retained MessagePack/CBOR Call and Publish sends. Rust-owned exact-size
  buffers have explicit consume-on-call ownership, serializer reconstruction
  covers arguments and keyword arguments, and local native 32/64 MiB
  MessagePack/CBOR medians reach 8.00/2.97 Gbit/s one-way.
- [x] Complete full local verification for the owned-segment send revision.
  All 66 ordinary FFI tests, serializer/native transport regressions, live WAMP
  integration, the 467-test router suite, consumer smokes, remote auth,
  zero-copy follow-ups, and Chrome Dart2Wasm pass.
- [x] Remove eager single-arguments decode from Dart MessagePack and CBOR
  receive fast paths and expose definite direct CBOR binary values as
  frame-backed views. Focused lazy-error and aliasing regressions pass, and all
  four standard large RawSocket rows exceed 2 Gbit/s across three local runs.
- [x] Fix native TLS/WebSocket terminal frame delivery by flushing complete
  frames, preserve progressive invocation payloads through the native router
  path with a versioned FFI export, and rerun the canonical/heavy file and
  32-256 MiB RawSocket matrices with clean artifact gates.
- [x] Complete the exact post-fix local verification. `bin/verify` passes with
  128 Rust core tests, 67 ordinary FFI tests, 380 Dart core tests, 118 MCP
  tests, 108 benchmark tests, the 468-test router suite, package-consumer and
  live WAMP/MCP smokes, remote auth, zero-copy follow-ups, and Chrome
  Dart2Wasm.
- [x] Remove quadratic pure-Dart RawSocket fragmented-frame assembly, segment
  large MessagePack/CBOR sends without creating a contiguous payload, read
  path-backed buffered file chunks directly into exact-size buffers, and use
  packaged native SHA-256 for ordinary Dart file-receive buffers when
  available. The heavy 128 MiB Dart CBOR reference improves from 1.91 to 2.83
  Gbit/s while native controls remain stable. Native clear/TLS/WebSocket file
  paths reach 5.05-14.44 Gbit/s, while Dart CBOR and native AES-GCM E2EE remain
  measured boundaries at 715 and 812 Mbit/s.
- [x] Complete full local verification for the exact-accumulator and buffered
  file-source revision. `bin/verify` passes with 128 Rust core tests, 67
  ordinary Rust FFI tests, the focused `ffi-test` metrics regression, 380 Dart
  core tests, 118 MCP tests, 108 benchmark tests, the 468-test router suite,
  consumer and live WAMP/MCP smokes, remote auth, zero-copy follow-ups, and
  Chrome Dart2Wasm.
- [x] Move native E2EE file preparation off the async runtime, accelerate
  AES-256-GCM with the `ring` backend, and retain complete progressive PPT
  chunks across router workers without weakening metadata fallback rules.
  Sustained E2EE file throughput now exceeds 2 Gbit/s locally, and the repeated
  128/256 MiB native RawSocket matrix reaches 3.81-9.55 Gbit/s one-way. Full
  `bin/verify` passes with 132 Rust core, 69 ordinary Rust FFI, 380 Dart core,
  118 MCP, 108 benchmark/live-WAMP, and 468 router tests plus consumer,
  remote-auth, zero-copy, and Chrome Dart2Wasm coverage.
- [x] Move native receipt hashing to `ring` SHA-256 and add a checked-in 4 GiB
  sustained E2EE workload to the heavy file matrix. Local sustained E2EE rises
  from 2.087 to 2.185 Gbit/s and the complete heavy artifact passes the new row
  at 2.165 Gbit/s without weakening digest-handle lifecycle semantics. Full
  exact-tree `bin/verify` passes with 132 Rust core, 72 ordinary Rust FFI, 380
  Dart core, 118 MCP, 108 benchmark/live-WAMP, and 468 router tests plus
  consumer, remote-auth, zero-copy, and Chrome Dart2Wasm coverage.
- [x] Preserve materialized Dart MessagePack binary arguments as unchanged
  RawSocket fragments, cover every MessagePack binary-length tier and fallback
  shape, and add repeated Dart MessagePack controls to the heavy file and
  128 MiB frame matrices. The heavy file suite moves 12.5 GiB and passes at
  968 Mbit/s for Dart MessagePack, 721 Mbit/s for Dart CBOR, 2.15 Gbit/s for
  sustained E2EE, and 9.87-15.64 Gbit/s for clear native paths. The 17 GiB
  duplex heavy frame suite passes every row at 3.68-10.03 Gbit/s one-way. Full
  `bin/verify` passes with 132 Rust core, 72 ordinary Rust FFI, 383 Dart core,
  118 MCP, 108 benchmark/live-WAMP, and 468 router tests plus consumer,
  remote-auth, zero-copy, and Chrome Dart2Wasm coverage.
- [x] Remove the remaining large buffered-Dart receive copy by accumulating
  fragmented frames in externally finalized memory, expose direct CBOR and
  MessagePack binary views to native SHA-256, propagate the exact native
  library into benchmark children, and pace buffered progressive sends without
  affecting native segment paths. Sustained 3 GiB-per-serializer file rows now
  reach 4.56-4.57 Gbit/s and the heavy 128/256 MiB RawSocket rows all pass at
  2.82-9.67 Gbit/s one-way. Full exact-tree `bin/verify` passes.
- [x] Add JSON to the canonical and heavy file/large-frame matrices, stream
  native JSON file segments through bounded base64 transforms, and decode
  canonical JSON invocation bytes into FFI-finalized native buffers. Preserve
  kernel `sendfile` for identity RawSocket segments and retain the Dart decoder
  fallback for noncanonical peers. Native JSON file paths now reach 6.10-8.95
  Gbit/s locally and every expanded 32-256 MiB RawSocket row clears 2 Gbit/s
  aggregate.
- [x] Complete exact-tree local verification and rerun the final 13-row file
  matrix against the rebuilt release library. `bin/verify` passes, native
  filesystem-backed rows reach 6.03-14.41 Gbit/s across clear RawSocket, TLS,
  and WebSocket, and the pure-Dart JSON fallback remains an explicit 1.20
  Gbit/s measured boundary.
- [x] Remove the remaining buffered-Dart JSON receive bottleneck. Canonical
  terminal binary arguments now bypass whole-frame UTF-8/string materialization,
  retained external RawSocket frames can be decoded into FFI-finalized native
  buffers, and ordinary Dart consumers use a direct canonical ASCII decoder.
  Noncanonical, ambiguous, and kwargs-bearing payloads retain the exact SDK
  fallback. The canonical and sustained Dart JSON file rows reach 2.18 and 2.43
  Gbit/s; the refreshed 32/64 MiB and 128/256 MiB RawSocket matrices pass every
  row at 2.34-17.02 Gbit/s aggregate with zero transport alerts. Full exact-tree
  `bin/verify` passes with 134 Rust core, 75 ordinary Rust FFI, 395 Dart core,
  118 MCP, 108 benchmark/live-WAMP, and 468 router tests plus isolated consumer,
  remote-auth, native-forwarding, and Chrome Dart2Wasm coverage.
- [x] Remove the fixed 1 ms timer from each buffered Dart progressive-file
  drain while retaining `Socket.flush()`, a cooperative event-loop yield, and
  strict per-chunk backpressure. Two identical local matrix passes improve
  Dart CBOR from 3.75 to 4.32-4.46 Gbit/s, MessagePack from 3.73 to 4.38-4.40
  Gbit/s, and JSON from 2.18 to 2.34-2.38 Gbit/s. A deterministic asynchronous
  drain test proves the next chunk is not sent early. A native base64-send
  experiment was discarded after leaving the 32 MiB Dart JSON RPC row flat at
  1.40 Gbit/s one-way and 2.79 Gbit/s aggregate. Full `bin/verify` passes with
  the new regression and all package, consumer, live WAMP, router, native, and
  Chrome Dart2Wasm checks green.
- [x] Preserve canonical single-binary JSON argument bytes after validated
  decode and reuse them as unchanged Call/Publish/Yield frame segments. This
  removes the second base64 encode and whole-payload JSON string/UTF-8 cycle
  from ordinary lazy echoes while retaining exact decoded values and every
  noncanonical/kwargs fallback. Three repeated 32 MiB Dart JSON RawSocket runs
  improve from 1.40 Gbit/s to 2.39-2.57 Gbit/s one-way; the 128 MiB Dart JSON
  reference remains a measured 1.86 Gbit/s boundary. Validation-only native
  scanning and manual Dart encoder unrolling were measured and discarded.
- [x] Correct WAMP throughput timing and upload accounting, preserve legacy
  artifact compatibility, surface remote progressive-call failures during
  buffered file streaming, and release synchronous receiver capacity without
  weakening bounded async backpressure. The final heavy file suite clears 2
  Gbit/s over both data and lifecycle windows for every row, and every heavy
  large-frame row clears 2 Gbit/s over the measured data window.
- [x] Add a manual 24 GiB large-transport matrix covering native/Dart,
  JSON/MessagePack/CBOR, RawSocket/WebSocket, and clear/TLS paths. The 64 MiB
  RawSocket and safety-cap-compatible 8 MiB WebSocket rows complete without
  transport errors; every native production row reaches 2.225-4.608 Gbit/s
  lifecycle throughput. Reuse lazy serializer fragments for Dart WebSocket
  sends while retaining JSON text frames, improving focused clear JSON from
  0.925 to 1.213 Gbit/s lifecycle and WSS JSON from 0.464 to 0.532 Gbit/s.
  Pure-Dart TLS and WebSocket JSON remain explicit runtime boundaries rather
  than being represented as native production-path failures. Exact-tree
  `bin/verify` passes with text/binary frame regressions, package consumers,
  live WAMP/MCP, router integration, remote auth, and Chrome Dart2Wasm.
- [x] Repeat the complete 24 GiB matrix against the current release library and
  add a focused 6 GiB secure-Dart scenario. Both artifact gates pass without
  transport or protocol errors. The focused TLS RawSocket/WSS rows remain at
  0.531-0.874 Gbit/s lifecycle across JSON, MessagePack, and CBOR. Dart SDK
  inspection identifies its asynchronous 8 KiB plaintext/10 KiB encrypted
  `SecureSocket` filter pipeline as the non-application boundary. Exact A/B
  native-base64 and one-allocation WebSocket JSON experiments were discarded:
  repeated samples overlapped baseline variance, and the concurrency stress
  measured 1.535 Gbit/s baseline versus 1.528 Gbit/s with the reduced
  allocation path. Multi-gigabit secure production use remains on the native
  transport implementation.
- [x] Gate the heavy file and 128/256 MiB RawSocket suites on both data-window
  and setup-inclusive lifecycle throughput, run them in hosted WAMP
  diagnostics, and strengthen every 128 MiB Dart RawSocket control to 16
  iterations. The exact-tree local 24 GiB file run passes all eight rows at
  2.178-20.741/2.127-16.472 Gbit/s data/lifecycle throughput, and the 36 GiB
  bidirectional RawSocket run passes all nine rows at
  3.147-22.114/2.652-9.652 Gbit/s with zero transport findings.
- [x] Correct the hosted heavy-file policy scope after exact-head evidence.
  Keep the 2 Gbit/s threshold unchanged for every native non-E2EE production
  row, retain Dart fallback and native E2EE rows as measured transform
  boundaries, and reshape the encrypted 4 GiB stress row to the best measured
  4 MiB/eight-session configuration without reducing its byte volume. The
  complete revised matrix passes locally, including E2EE at
  2.317/2.253 Gbit/s data/lifecycle throughput, and the exact updated tree
  passes `bin/verify`.
- [x] Correct the hosted large-frame policy scope after exact-head diagnostics
  `32600261031` completed all nine rows. Keep the unchanged 2 Gbit/s data and
  lifecycle gates on all six native JSON, MessagePack, and CBOR production
  rows at 128/256 MiB, where the shared runner measured
  7.121-12.943/2.329-4.563 Gbit/s. Retain the three pure-Dart references as
  informational performance measurements with strict transport checks; the
  sole finding was Dart JSON at 2.169/1.757 Gbit/s. Native production
  performance remains release-blocking. The corrected selector passes all 23
  benchmark artifact tests, exact hosted-artifact replay, `bin/test-fast`, and
  `bin/verify`.
- [x] Overlap large native receipt hashing with transport progress without
  retaining Dart-mutable FFI memory. Chunks of at least 256 KiB are copied
  synchronously into a per-digest FIFO SHA-256 worker with a two-chunk bounded
  queue and deterministic finalize/release joins; small and non-native chunks
  retain the synchronous path. Ordered sync-to-async and async-to-sync updates,
  immediate caller mutation, cancellation, and invalid pointers have focused
  Rust regressions. A 2 GiB single-session E2EE run reaches 2.115/2.085 Gbit/s
  data/lifecycle throughput, while the checked-in 4 GiB heavy row reaches
  2.433/2.366 Gbit/s. The complete heavy file matrix passes all eight rows above
  2 Gbit/s over both timing windows, and clear native MessagePack/CBOR RawSocket
  delivery remains the only literal filesystem-to-socket `sendfile` path. Full
  exact-tree `bin/verify` passes with 134 Rust core, 78 ordinary Rust FFI, 397
  Dart core, 118 MCP, 116 benchmark, and 468 router tests plus consumer/live
  WAMP and MCP smokes, remote auth, native-forwarding follow-ups, and Chrome
  Dart2Wasm.
- [x] Extend bounded asynchronous receipt hashing to large ordinary Dart-owned
  chunks while retaining a synchronous ownership copy before FFI return. A
  mutation regression proves that a queued 1 MiB buffer hashes its original
  contents. Exact A/B file probes improve Dart CBOR lifecycle throughput from
  5.005 to 6.234 Gbit/s and MessagePack from 5.224 to 6.465 Gbit/s, while JSON
  remains flat at 2.855 versus 2.865 Gbit/s because base64 dominates. Full
  `bin/verify` passes. The current 24 GiB file artifact gate passes all eight
  rows at 2.352-16.331 Gbit/s lifecycle throughput, and the 36 GiB repeated
  128/256 MiB RawSocket gate passes all nine rows at 2.972-9.879 Gbit/s.
  Reject consumed-message in-place AES-GCM because Dart materialized views
  borrow native message storage; runtime-thread, queue-recycling, and chunk-size
  experiments also did not improve the existing configuration.
- [ ] Optimize remaining measured receive/write/serializer bottlenecks.
- [x] Complete heavy hosted matrix evidence. The exact-head hosted file and
  large-frame matrices pass all transport and metric gates. Clear native
  MessagePack/CBOR and segmented native TLS/WebSocket exceed 2 Gbit/s; Dart,
  E2EE, and large-frame serializer paths remain measured optimization work.
- [x] Complete full post-change local verification. `bin/verify` passes with
  127 Rust core tests, 62 ordinary Rust FFI tests, the focused `ffi-test`
  metrics regression, 372 Dart core tests, 118 MCP tests, 107 benchmark tests,
  the 467-test router suite, isolated consumers, live WAMP/MCP smokes, remote
  auth, zero-copy router follow-ups, and Chrome Dart2Wasm. A second full run
  passes after target-scoping SHA assembly away from Windows MSVC.
- [x] Complete exact-head hosted workflow evidence and the deployment audit for
  the E2EE, crypto-dispatch, and heavy-scenario revision. CI `32500570350`, WAMP
  Profile Benchmarks `32500580587`, WAMP Profile Diagnostics `32500587107`,
  Router Image `32500602434`, and Native Artifacts prerelease dry run
  `32503716277` are clean at `9bf8cbb8`; package dry run `32499298980` remains
  relevant. The comprehensive content audit passes, while literal strict mode
  reports only the expected unprotected development branch.
