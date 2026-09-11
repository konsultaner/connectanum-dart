# Component Security Audit

Status: active
Started: 2026-09-10
Baseline: `733c6d91`

## Objective

Deeply review every Connectanum component and its trust boundaries. Reproduce
and fix confirmed security defects without sacrificing legitimate-traffic
performance. A green regression suite alone is not a security audit, and a
narrow fix does not complete this plan.

## Required Coverage

| Component | Review and attack cases | Evidence status |
| --- | --- | --- |
| Core protocol and serializers | Malformed JSON/MessagePack/CBOR, lengths, IDs, nesting, lazy payload consistency | SA-012 nesting, complete-value framing, core integer, seven-field arity and diagnostic hardening, SA-013 declared-collection allocation hardening, and SA-014 lazy argument/keyword shape, key and diagnostic integrity are locally regression/performance-verified; optional numeric strictness, short-array normalization, consistency outside the reviewed lazy collection paths, and broader protocol review remain pending |
| Native transport and FFI | RawSocket/WebSocket/HTTP1/2/3, TLS, framing, resource bounds, handle ownership, unsafe code, zero-copy lifetimes | SA-002 dependencies, SA-004/005 message ownership/handles, SA-006 HTTP/3 admission, SA-007 restart isolation, SA-008 checked resource allocation, SA-009 response completion, SA-010 HTTP/1 request framing and SA-011 paused-producer delivery are locally regression-verified; broader framing/lifetime review, finite ID availability and earlier performance confirmation pending |
| Client sessions | Authentication lifecycle, reconnect races, unsolicited replies, cancellation, file transfer, browser/native parity | Pending |
| Authentication and auth service | Ticket/CRA/SCRAM/cryptosign, remote delegation, credential rotation, KDF limits, identity binding, pending transactions | SA-001 admission and SA-003 transaction fixes reproduced and locally verified; SA-003 performance provisional, broader review pending |
| Router authorization and state | Realm/role boundaries, RPC/pubsub/meta, pattern grants, dynamic authorization races, worker isolation | Pending; previous Meta fix is baseline only |
| HTTP and MCP | Origins, redirects, HTTP auth grants, sessions/SSE, tool/resource access, request smuggling, file/proxy routes and SSRF | SA-009 response completion, SA-010 ambiguous request framing and SA-011 paused-producer delivery are locally verified; SA-010/011 affected-path performance is cleared, while deployment-specific proxy differentials and other boundaries remain pending |
| Payload cryptography | Key/nonce lifetime, replay/context binding, authenticated metadata, E2EE parity and file integrity | SA-007 native provider restart key confusion reproduced and locally fixed for both ciphers; broader cryptography review pending |
| Consumer application | Account/device trust, encrypted storage/backup, attachments, push, WebRTC, MCP consent, native/web boundaries | Pending |
| Packaging and dependencies | All Dart/Rust lockfiles, advisories and reachability, native download verification, CLI/config secrets, workflows and publishing | SA-002: transport and benchmark scans now have zero published vulnerabilities; transport maintenance warnings and other coverage pending |

The compatibility facade, benchmark CLI/harness, auth-server executable, router
executable, all three Rust crates, and standalone application packages are in
scope, including code excluded from the root workspace gates.

## Method And Completion Gates

1. Record the threat model, trust assumptions, attack prerequisites, affected
   files, severity, and reproducible evidence for findings. Distinguish confirmed
   defects from candidates and intentional operator-controlled capabilities.
2. Review sources using symbolic navigation where available, supplemented by
   bounded local-model second opinions. Validate advisory output independently.
3. Inventory resolved dependencies and check current public advisories; assess
   exploit reachability rather than equating an advisory count with a result.
4. Add fail-first regressions for confirmed defects before changing production
   behavior. Cover authorized positive controls, rejected attempts, concurrency,
   cleanup, and the actual public transport/API path where relevant.
5. Capture before/after benchmarks on the same machine and runtime configuration
   for each hardening change. Use warmup, repeated measurements, and alternating
   baseline/patched runs; retain raw results and workload/commit/toolchain data.
   Do not overlap benchmarks with builds or test workloads.
6. Compare throughput, latency (including tails), memory, and errors on affected
   paths; run existing production performance budgets, including the canonical
   WAMP and large-frame/file lanes when those paths change. Investigate any
   slowdown beyond observed noise. Never weaken a security invariant or reduce
   cryptographic work to manufacture a passing speed comparison. Identical
   timing cannot be guaranteed; claims must match measured uncertainty.
7. Run `bin/test-fast` before substantial changes, `bin/verify` before handoff,
   and additional standalone-app gates for application changes. After code pushes,
   inspect the hosted chain and strict audit as relevant. Preserve protected
   master review and synchronized package versions.
8. Deliver a component-by-component report with findings/fixes, source and dynamic
   evidence, dependency results, benchmark comparisons, and explicit residual
   risks. Complete this goal only after every row is reviewed and all required
   fixes and performance checks are resolved.

## Progress

- Baseline master CI `34478086614` and fresh `bin/test-fast` pass. Preserved the
  previous uncommitted merge-evidence notes for the next implementation commit.
- SA-001: direct service regressions reproduce 13 failures and two mTLS RPC
  regressions reproduce independent binding failures. Service admission now
  precedes either pending map; schema parsing precedes consumption. All 25 auth
  service tests and eight remote-auth integration tests pass. `dart analyze`
  and full `bin/verify` pass. Full findings and prerequisites are in the
  [audit report](../security/2026-09-10-component-audit.md).
- Twelve alternating JIT/AOT baseline/patched passes completed 60,000 measured
  valid logins plus 14,400 warmup logins with no errors. JIT median concurrent
  throughput improved 3.1%; serial throughput fell 3.1%. AOT confirmation shows
  +2.7% serial and +5.4% concurrent throughput with lower median tail latency.
  No consistent slowdown reproduced across runtime modes; ranges overlap on
  this shared host. Both modes, CPU/RSS evidence, and caveats are preserved in
  the report and its machine-readable comparison. No unchanged-timing or
  statistically proven speedup claim is made.
- Installed `cargo-audit`; both Rust lockfiles have published network dependency
  advisories. `h2` and `quinn-proto` are shipping native dependencies; older
  `rustls-webpki` resolves through benchmark-control `reqwest` 0.11, not the
  router's current Rustls server. Dependency upgrades and attack/performance
  validation are the next security slice. The combined workspace/app Pub scan
  queried 163 public package/version pairs against OSV with no listed matching
  advisories and no pending pages. SDK/native-platform and bundled asset scans
  remain open; absence of advisories does not replace component source review.
- SA-002 shipping manifests now enforce patched h2/QUIC minimums and share
  http 1.x types. Four paused-body H2 regressions fail before and pass after the
  upgrade. The identical upstream-source QUIC probe rejects gapped packet
  allocations on patched versions and retains ordinary reorder/overlap behavior.
  The native lockfiles are local ignored resolution artifacts, not checked-in
  pins; resolved versions/hashes are captured in the report.
- All 97 feature-enabled FFI tests and 23 verification-script tests pass after
  repairing three stale TLS event fixtures and one mismatched injected-counter
  expectation. The full FFI test-hook suite is now part of `bin/verify`, not only
  its metrics test. The fresh pre-change fast suite hit a secure MCP timeout;
  the isolated full live MCP smoke rerun passed without production changes.
- Six alternating native-library passes completed 73,152 measured HTTP requests
  plus 6,144 warmups without errors. The serial H2 median fell 4.9%; unrelated
  VM contention also reduced baseline multiplex throughput by roughly 70%.
  Every timed pass is retained. Performance is **not cleared**: repeat on a
  quieter host and investigate any reproducible decrease. Full `bin/verify`
  passes, including live MCP, 482 router tests, eight remote-auth tests, 13
  zero-copy tests, and Chrome/Dart2Wasm. A lower-load confirmation completed two
  processes with 24,384 measured requests and no errors before being stopped
  between processes because unrelated inference remained busy. These partial
  results are retained and do not resolve the comparison.
- The benchmark graph now uses patched h2/QUIC minima, reqwest 0.13.5, and
  anyhow >=1.0.103; unused ureq and Hyper's old H2 feature are removed. Its
  resolved audit has zero vulnerabilities and zero warnings. All 29 artifact
  library tests and 74 driver tests pass, including large UTF-8 JSON/error-status
  preservation and real HTTPS control ALPN. The complete native benchmark suite
  joins the full verification gate; 24 script tests pass after a fail-first gate
  regression. Full combined verification passes. An isolated control-timeout
  run then exposed a test-order dependency on another fixture installing the
  Rustls provider; the fixture now initializes it explicitly and passes alone.
  Final full verification passes after that test-only correction, including
  142 Rust core, 90 default FFI, 97 test-hook FFI, 29 native artifact, and 74
  HTTP-driver tests, plus the full Dart/live MCP/router/browser gates.
- All nine canonical WAMP scenarios pass (102 workload gates), as do the full
  24 GiB large-frame matrix (24 workloads / 864 samples) and 25.5 GiB file-transfer
  matrix (30 workloads / 408 samples). There are no counter or metric findings.
  These are unchanged absolute production budgets, not before/after speed
  comparisons. Native/driver performance confirmation and the broader audit
  remain open; this does not complete SA-002.

## SA-004 Native Payload Ownership

- Six fail-first weak-observer tests reproduced premature native allocation
  release for client/router JSON, MessagePack, and CBOR views. The new shared
  native slice-owner API preserves zero-copy storage independently of routing
  handles; older libraries safely copy. Internal CALL receivers retain before
  reading and reject expired transfers. Reply fallback no longer dereferences
  transferred addresses.
- Four Rust export/release tests and all 11 focused Dart tests pass, including
  exact native pointers, store clearing, 100 release races, sole-binary views,
  legacy fallback, and normal isolate-group cleanup of a retained subview. A
  live internal WebSocket CALL test passes after reply and router shutdown.
- Full `bin/verify` passes with 494 router tests and all existing native,
  benchmark, remote-auth, zero-copy, package/MCP, and Chrome/Dart2Wasm gates.
  Earlier transient compile and overlapping runtime-lock failures are preserved
  separately; the isolated rerun passes.
- Six alternating AOT native/client/router comparison passes completed 184,176
  measured operations plus 11,160 warmups, without errors. The first candidate
  is not performance-cleared: CBOR RawSocket 64 KiB RPC drops 12.1%, large
  MessagePack/CBOR RPC drops 9.7%/8.3%, and observed memory rises. The report
  retains all runs, exact binary hashes, scenario, and shared-host caveats.
- Next: profile and optimize ownership/materialization while preserving the
  safety tests, repeat comparisons, run large-frame/file gates, add live
  cancellation/late transfer regressions, and review other external/JSON/E2EE
  owners. SA-002/SA-003 performance confirmation is still open. The full audit
  remains active; this is not a release or a completed component review.
- Metadata optimization: six fail-first cases confirmed lazy metadata could pin
  the entire native frame. A temporary native owner now protects a Dart-owned
  metadata copy and synchronous string decoding, without changing zero-copy
  payload views or the native ABI. All 20 focused cases pass; 17 legacy cases
  pass with three native-owner-only cases skipped. Fresh full `bin/verify`
  passes with 503 router tests. Local bounded review found no concrete defect;
  its stale/disagreement cleanup concern is covered explicitly.
- Two further ABBAAB comparisons each finish 184,176 measured operations and
  11,160 warmups without errors. Both are retained. Lower inference load does
  not clear performance: 32/64 MiB RPC still falls 8.3%/8.6%, with higher memory.
  The 24-workload large-frame, eight-workload heavy-file, and 30-workload file
  matrix absolute gates pass, covering 24 GiB of frames and 49.5 GiB of files.
  Remove redundant receiver
  materialization/owner allocations next, not ownership or external-memory
  accounting. Keep this checkpoint local and continue all pending audit rows.

- Direct Arc tokens now remove the extra native allocation per nonempty byte
  export. The fail-first allocation-reuse test also verifies independent equal
  token addresses, partial release, and concurrent final cleanup. All five
  focused Rust tests and fresh `bin/verify` pass, including 102 test-hook FFI
  and 503 router tests. The measured binary is the verified `target/ffi-test`
  release output; the ordinary release directory still contains an older build.
- Incremental and full-baseline comparisons each retain all six ABBAAB passes,
  184,176 measured operations and 11,160 warmups without errors. The incremental
  native-only result is mixed; the full comparison still drops 11.4%/11.1% on
  32/64 MiB RPC and 15.2% on 64 KiB CBOR RawSocket. Shared VM contention remains.
  All 62 large-frame/heavy-file/file-matrix absolute gates pass on this binary,
  covering 73.5 GiB application payload without errors. These do not clear the
  relative regression. Keep this local and optimize receiver materialization
  next; all other audit rows and final production/profile evidence remain open.

- Payload-only receiver: native internal CALL delivery no longer constructs a
  full incoming-message wrapper or unnecessary metadata. It validates type and
  serializer before exporting argument/keyword views, and releases the temporary
  retained handle on all helper exits. Lifetime ownership, legacy copies, and
  external-memory accounting remain intact. All 31 focused cases, 28 applicable
  legacy cases, 14 live WebSocket tests, router analysis, and fresh `bin/verify`
  pass, including 514 router tests and the existing native/live/browser gates.
- The first fast gate found absolute repository paths in the previous Arc gate
  artifact, added after that checkpoint's verification. Normalization fixes
  this public-artifact failure without altering measurements. The corrected
  fast gate, full verify, and post-generation public-reference guard pass.
- Full-baseline and incremental six-pass comparisons each complete 184,176
  measured operations and 11,160 warmups without errors. The full repeat shows
  +2.3%/+2.4% large-frame throughput, but its baseline moved under host contention,
  tails/memory remain higher, and the incremental 32 MiB result falls 3.4%.
  Retain all earlier decreases. All 62 unchanged frame/file gates pass over
  73.5 GiB; relative performance is still not cleared.
- Six separate AOT GC passes retain 18 hashed process traces with explicit
  aggregation and runtime options. Both safe readers have the same 147 young
  and 72 old server collection intervals, including 146 `external` young events.
  Payload-only materialization does not remove that pressure. This is whole-
  process instrumented evidence, not proof of throughput causality or pause time
  obtained by summing nested/concurrent events. Keep ownership/accounting intact.
- Next bounded native review: reproduce signed-positive message-handle exhaustion
  without billions of allocations, then investigate cancellation/late-transfer
  and escaped HTTP body views. These are leads, not confirmed vulnerabilities.
  Do not spend the full audit repeating noisy microbenchmarks; retain unresolved
  performance work for controlled final confirmation and continue every pending
  component row. No audit candidate has been pushed or released.

## SA-005 Message Handle Boundaries

- Four bounded fail-first tests confirm negative/sentinel handles and live-entry
  replacement from unchecked unsigned allocation. They use isolated stores,
  not billions of packets or an unsafe global-counter injection.
- Local checked admission permits the last positive ID, rejects invalid/exhausted
  counters and collisions, drops rejected owners, and preserves old handles and
  stale-ID safety across clear. Typed internal errors map to existing FFI -4/-14
  statuses without an ABI change. Ten store tests and FFI result mapping are
  covered by the passing 112-test confirmation run. The initial full FFI run
  had an HTTP/3 handshake timeout; isolated and complete reruns pass, but its
  root cause is not established. Fresh `bin/verify` passes, including 105 default
  FFI, 112 test-hook FFI, 514 router, and all existing live/package/browser gates.
  Six longer ABBAAB comparison passes complete 188,640 measured operations plus
  11,160 warmups without errors, including 384 GiB of large-frame payload.
- This is a mitigation, not a solution to finite process-lifetime availability.
  Complete an additive wide-handle ABI across polling, materialization, byte
  exports, binary/SHA-256/E2EE consumers, native forwarding, test queues, both
  Dart bindings, and the shared exporter. Legacy adapters must reject truncation;
  capability selection must cover the entire family. Include tests above the
  old boundary, partial-library rejection/fallback, escaped owners and old ABI.
- The checked-allocator comparison uses identical Dart executables and frozen
  native libraries. Results are mixed: 32/64 MiB throughput +3.9%/+14.1%, but
  WebSocket pub/sub -6.5%. Late background inference exceeds 2200% CPU; retain
  every pass and do not infer either a guard speedup or harmless noise. All 62
  unchanged frame/file gates pass over 73.5 GiB. Relative performance, especially
  pub/sub, remains open alongside SA-002/SA-004 confirmation. Full artifact,
  verification outcomes and source fingerprints are in the audit report.
  Next: implement the complete wide-handle migration, then confirm performance
  without repeatedly replacing unfavorable evidence. Review reset/wrap behavior
  of other native stores as separate coverage. Keep this checkpoint local.

- SA-005 native-wide checkpoint: the complete additive native handle family is
  implemented with independent monotonic allocation and unchanged legacy ABI.
  Two fail-first cases led to a bit-31 marker and carry skip, so accidental
  signed-32-bit narrowing rejects wide IDs instead of aliasing a legacy entry.
  All 17 focused cases and six included live transport/serializer combinations
  pass, including E2EE and zero-copy owner preservation. Final `bin/verify`
  passes with 121 default/129 test-hook FFI and 514 router tests plus existing
  live/package/browser gates. Transient test-fixture/default-feature errors are
  retained separately. Dart still uses the old family: next migrate both
  bindings and the shared exporter atomically, test partial/legacy libraries and
  actual high-handle transfers, then measure the wide application path. Do not
  equate the native-only checkpoint or legacy-adapter benchmarks with completion.
- The dynamic C-ABI probe verifies all 18 production exports and escaped-owner
  lifetime with full-width handles. Six ABBAAB legacy-adapter passes complete
  188,640 measured operations plus 11,160 warmups without errors. Throughput is
  mixed and sampled memory rises; neither this nor earlier audit performance is
  cleared. The initial 62-workload absolute run fails one file-lifecycle metric
  (buffered Dart WebSocket JSON: 1.952 versus 2.0 GBit/s). A fixed four-pass
  baseline/candidate ABBA confirmation repeats all 30 file workloads unchanged;
  all gates pass over 1,632 samples and 102 GiB. Candidate results of 2.169 and
  2.167 GBit/s do not reproduce the miss, but its cause remains unproven. Preserve
  the original failure and both comparisons. The report links exact artifacts;
  keep this implementation checkpoint local and continue the Dart migration.

## SA-005 Dart Adoption Checkpoint (2026-09-11)

- Both Dart bindings and the shared byte exporter now adopt the complete wide
  family or retain the complete legacy family; unknown/partial advertisements
  fail closed before lookups. Legacy consumers reject overflow/underflow before
  narrowing, including crypto/hash/forward/release paths. Six fail-first Dart
  cases, 25 capability cases, compiled partial-library fixtures, actual high-ID
  transport/hash/E2EE cases and existing owner/isolate lifetime tests pass.
- All 36 focused live transport/router cases pass. Legacy owner/copy libraries
  pass 35/32 applicable cases. The first full `bin/verify` passes with 526 router
  tests and all existing native/live/package/browser gates. A separate fail-first
  gate test fixes both explicit client runners omitting the capability suite;
  all 25 script tests pass. Updated-runner verification hits two HTTP/3 handshake
  timeouts; eight isolated H3 cases and the complete 526-case router suite with
  native debug logging pass on the same library. Final ordinary full
  `bin/verify` passes, including the updated capability gate and all existing
  live/package/zero-copy/Chrome checks. The original failure and unproven cause
  remain explicit; no timeout or retry policy was changed.
- Six same-native-library ABBAAB AOT passes complete 188,640 measured operations
  and 11,160 warmups without errors, including 384 GiB measured large frames.
  Median RawSocket pub/sub falls 8.0%, Dart CBOR RPC 11.6%, and 64 MiB RPC 6.7%.
  Other results and CPU load vary; the full comparison is retained. All 62
  unchanged large/file gates pass over 73.5 GiB, and all nine canonical WAMP
  scenarios / 102 workload gates pass separately on the current-tree JIT paths.
  Absolute budgets do not clear relative performance or earlier audit findings.
- Next: profile the wide application decreases, particularly the non-overlapping
  pub/sub observations, without weakening stale-handle or owner safety. Continue
  other resource-store reset/wrap and native HTTP-body lifetime review, then the
  remaining component rows. Also reproduce bounded half-open HTTP/3 admission:
  source inspection shows a serial handshake accept loop, but this is not proven
  to cause the observed verification timeouts. Do not add retries or relax tests
  in lieu of diagnosing that failure. The audit remains active and unpublished.

## SA-006 HTTP/3 Admission Checkpoint (2026-09-11)

- Two fail-first real-QUIC tests reproduce listener-wide blocking by an
  incomplete handshake and failure to enforce the configured handshake timeout.
  Ordinary-client and shutdown controls pass on unchanged production code after
  allowing Quinn's protocol closing interval in the new cleanup assertion.
- Listener-owned concurrent tasks now use the existing positive backlog as an
  admission bound, enforce handshake expiry, refuse excess arrivals, and cancel
  when the listener or receiver closes. All six focused tests pass. Final
  `bin/verify` passes with 148 core, 121/129 FFI, 526 router, live/package,
  zero-copy and browser checks. Prior intermittent HTTP/3 failures remain
  independently recorded, without an established causal link.
- Six ABBAAB native-only AOT runs complete 103,728 measured requests and 7,680
  warmups without errors or unexpected reconnects. Fresh parallel throughput
  improves 26.9%, but request-p99 increases 2.95 to 8.89 ms with non-overlapping
  ranges and sampled server RSS increases 141.5 to 151.6 MiB. Multiplexed reused
  H3 falls 2.3%, with overlapping ranges. Five existing H3 pressure gates pass
  (640 requests); no policy was relaxed. Preserve all results.
- Performance remains open. Next measure handshake-inclusive operation latency
  and profile the increased request tails/memory before claiming no regression;
  current per-request timing excludes connection setup. Preserve independent
  handshake progress rather than restore serialization for a better isolated
  latency metric. Continue SA-005/earlier performance work, resource-store/body
  ownership review, and every remaining component row. Keep changes unpublished.

## SA-006 Setup-Inclusive Timing Checkpoint (2026-09-11)

- Added optional raw-sample setup and operation-total timing to plain fresh
  H1/H2/H3 requests, preserving existing request latency, aggregate gates, auth,
  reuse and legacy JSON behavior. Two fail-first cases and a reused-H3 control
  reproduce the missing measurement. All three tests pass after instrumentation,
  including a delayed QUIC handshake and concurrent clients. Local GLM review
  is checked against source; no confirmed regression remains in this diff.
- Full `bin/verify` exits zero: 77 benchmark-driver, 526 router (one explicit
  skip), 124 Dart benchmark, native, consumer, zero-copy and browser checks.
  The initial `bin/test-fast` process reached its final passing test group;
  its numeric exit handle was lost during context compaction, recorded as
  unavailable rather than invented in the evidence.
- Six further ABBAAB native-only passes use one identical instrumented driver
  and unchanged native/Dart AOT inputs. All 103,728 measured requests plus 7,680
  warmups succeed without reconnect surprises or error/timeout counter deltas.
  Fresh parallel throughput improves 20.8%, setup-inclusive p99 falls from
  15.791 to 13.860 ms (-12.2%, non-overlapping ranges), while request-only p99
  rises 3.184 to 10.423 ms. The complete measured operation is faster, not the
  threefold slowdown that request-only timing could suggest.
- Performance remains open: sampled server RSS still rises 140.0 to 150.5 MiB.
  Next profile connection/task retention, closing lifetimes, allocation and
  post-drain memory; do not infer a leak from RSS alone or restore handshake
  serialization. Reused H3 multiplex is -0.39% in this follow-up with overlapping
  ranges; preserve the earlier -2.32% result. Continue SA-005/earlier performance
  work and the remaining component matrix. Changes remain unpublished.
- Normalized results, hashes, scripts and verification provenance are in
  `docs/security/2026-09-11-http3-operation-timing-benchmarks.json`.

## SA-006 Connection-Churn Memory Checkpoint (2026-09-11)

- A new native regression covers 32 TLS/QUIC clients in four eight-client
  bursts, alternating a drained GET and no request. All connection/stream weak
  owners, registry entries and endpoint connections drain between bursts;
  registry ownership returns to the initial baseline and every accepted ID
  receives one graceful terminal event while the listener stays open. This
  passes without a production change and is not a new leak reproduction.
- Six ABBAAB runs of the new diagnostic churn scenario pass 98,304 measured
  fresh connections, 3,072 warmups and 30 idle probes with exact bytes/counts
  and no errors. Frozen binaries are identical to the timing checkpoint.
  Final post-idle RSS is 68.938 versus 83.281 MiB (baseline/candidate medians),
  with non-overlapping ranges. Both variants still grow across later bursts.
- Final-idle macOS allocator snapshots show 28.6 versus 40.5 MiB median resident
  malloc-zone memory, but about 1.733 versus 1.940 MiB allocated. This supports
  retention/fragmentation as a contributor, not complete attribution or proof
  of leak freedom. Native ownership coverage does not clear Dart/FFI handles.
  Preserve the different earlier mixed-workload RSS history as separate evidence.
- The initial zero-response idle probe failed strict byte validation because
  the handler's empty echo fallback returns five bytes. Preserve that attempt;
  explicit 1 KiB probe responses fix the fixture without weakening validation.
  No own tests/builds/inference overlap the valid runs. Initial and final full
  `bin/verify` exit zero, including 149 core, 121/129 FFI, 29 artifact, 77 driver,
  526 router (one skip), 124 Dart benchmark, consumer/MCP and browser checks.
- Evidence: `docs/security/2026-09-11-http3-connection-churn-benchmarks.json`.
  Keep performance and the broader audit open, continue allocator/resource-store
  ownership review and earlier comparisons, and do not tune security behavior
  based on RSS alone. No production code, versions, remotes or releases changed.

## SA-007 Resource Restart Checkpoint (2026-09-11)

- Six Dart and six native fail-first regressions confirm stale resource handles
  alias new files, E2EE keyrings/sessions, and HTTP connection events after
  explicit native runtime shutdown/restart. Both ciphers demonstrate replacement
  key use, not merely old-key retention. This requires surviving in-process
  owners and is not a demonstrated remote-only exploit.
- Resource clearing remains; only the four counter resets are removed. All six
  native cases and 13 focused Dart cases pass. Both root gates now include the
  restart suite. Full `bin/verify` passes with 149 core, 127/135 FFI, 29 native
  artifact, 77 driver and existing router/live/package/browser checks.
- Six fixed-input native-only ABBAAB passes complete 63,648 measured operations
  plus 5,160 warmups without errors, including 42 GiB file payload. All seven
  file throughput medians improve; E2EE ranges overlap, with two throughput
  medians down 0.7%/1.7% and RawSocket Dart AES pub/sub p99 up 19.5%. Unrelated
  host contention and small Dart AES/file samples limit confidence; retain all
  observations and do not claim identical performance or attributed speedups.
- All 70 unchanged absolute workload gates pass over 2,040 samples, including
  24 GiB combined large-frame payload and 25.5 GiB file payload. Evidence is
  `docs/security/2026-09-11-resource-restart-benchmarks.json`. Earlier performance
  questions remain open; nothing has been pushed, versioned, or released.
- Next: bounded exhaustion/collision handling for the remaining resource stores,
  then continue other HTTP/FFI owner and component rows. Removing restart resets
  does not solve eventual unsigned wrap; do not describe it as unlimited IDs.

## SA-008 Resource Allocation Checkpoint (2026-09-11)

- All twelve non-message FFI resource stores use checked monotonic positive
  signed-C allocation, fail closed on exhaustion/collision, preserve occupied
  entries and drop rejected resources. Existing -14 errors and public ABI are
  preserved. Response writers are allocated before success headers and removed
  when dispatch fails. This is not a final finite-capacity availability solution.
- Eight assertions fail with the extracted original allocator/dispatch order;
  five controls pass. All thirteen cases pass after the fix. Private seeded
  counters reproduce boundaries without global mutation or billions of requests.
  Initial full verification passes with an HTTP/3 test retry; fresh final
  `bin/verify` passes without retry, including 149 core, 140/148 FFI and all
  existing live/package/browser gates.
- Three benchmark-client readiness regressions also fail first. Plain,
  protected and JSON Hyper HTTP/1 sends now wait for readiness; all 80 driver
  tests and 27 authentication smoke workloads / 126 requests pass. JSON callers
  already time the whole login/refresh operation. Both native variants use one
  frozen corrected driver; no performance or reconnect threshold is relaxed.
- Three rejected old-library matrices are retained, the third with corrected
  readiness. A separate 4,096-request diagnostic observes a first-iteration TLS
  response-body EOF and recovery on an extra connection. Cause is not established
  or fixed. Temporary diagnostic logging is removed; source matches final
  verified driver exactly. Do not equate successful retries with clean transport.
- Six ABBAAB passes complete 136,512 measured operations plus 8,904 warmups,
  including 42 GiB file payload. Eight HTTP/1 streaming connection-count findings
  (eleven extra connections) force comparison exit one; both variants are
  affected. All logical requests finish with expected byte counts, but successful
  retries and zero counters do not establish clean transport. Every run remains.
- Performance is not cleared: TLS file throughput -8.4%, native XSalsa RPC -5.3%,
  HTTP/2 streaming -4.5%; all ranges overlap, while several tails and final
  sampled RSS also increase. Shared inference/VM/emulator contention limits
  attribution. Unchanged absolute budgets pass 74 of 75 workloads / 2,680
  samples. Buffered Dart/JSON WebSocket file transfer misses 2.000 GBit/s at
  1.952 GBit/s; a full file-matrix repeat fails at 1.900 GBit/s and the same
  matrix with the previous SA-007 library fails at 1.921 GBit/s. Each extra
  matrix completes 408 samples and passes the other 29 file workloads. The
  failure is not unique to SA-008, but is not cleared. All negative runs,
  source/input hashes and reproduction scripts are linked from the audit report.
- Next: HTTP/1 response/reclaim/connection-close tracing with a bounded native
  regression; buffered JSON file profiling and controlled-load performance
  confirmation; compatible wide resource-handle availability; separate core
  listener/connection-ID boundaries; then all other pending component rows and
  earlier performance questions. Do not push or release incomplete audit work.

## SA-009 HTTP/1 Response Completion (2026-09-11)

- Confirmed response-boundary flush omission in buffered and chunked HTTP/1
  writers. Real TLS with forced in-memory backpressure returns with ciphertext
  still pending; four cases fail. Two flush-error cases incorrectly succeed;
  a plain-wire control passes. Initial fixture handshake timeouts were fixed
  independently by disabling test-only TLS tickets; production TLS unchanged.
- Both helpers now flush at completion, not per chunk, and propagate errors.
  All seven focused cases pass, including exact first/second response bytes and
  keep-alive. No version/ABI/crypto change. Baseline fast suite passes. Initial
  full verification exits one on a protected HTTP/3 MCP handshake timeout,
  with 156 core, 140/148 FFI, 80 driver and 525 router passes. Correct test-runtime
  isolated rerun passes without code or timeout changes; a wrong-library skip
  is not counted as a pass. Fresh full `bin/verify` passes with 526 router tests
  (one explicit skip), 11 remote-auth, 13 zero-copy and the live/package/browser
  gates. Initial baseline comparison exits one on streaming warmup with TLS
  body truncation after the existing reconnect. Preserve that process and its
  two completed serial rows. The remaining five planned runs retain another
  failed baseline and a completed baseline with two extra connections. All
  three patched processes pass strict checks (36,432 measured / 1,872 warmup
  requests); both collectors still exit one because baseline failures remain.
  Complete rows across both variants contain 52,576 measured / 2,592 warmup
  requests; partial failed attempts are unknown. No failed entries were rerun
  and no driver, scenario, timeout or retry gate changed. Only HTTP/1 serial
  has three complete runs per variant: +0.079% median throughput, p99 3.060 to
  3.088 ms. Patched streaming reaches 8.153-9.288 GBit/s without reconnects,
  but the sole completed baseline has retries, not clean speedup evidence.
  Other workload observations are unbalanced and performance remains open.
  All 27 HTTP authentication workloads and 126 samples pass. Evidence is
  `docs/security/2026-09-11-http1-response-flush-benchmarks.json` (SHA-256
  `f5ad1394f7cd78450095f0910d30b55c6f5b22ac0a5fd65d2c42f286f3edd8ee`).
- Do not infer full audit or speed clearance from this fix. Retain historical
  HTTP/1 retries, the buffered JSON file budget failure, all older relative
  comparisons, finite resource capacity and remaining component review rows.
- Response completion tests do not establish timely delivery while a long-lived
  producer is paused mid-response. Review that separate SSE/streaming boundary
  with a deterministic producer-stall test and sustained-throughput evidence.
- The HTTP framing lead is resolved as SA-010 below with malformed/list/repeated
  Transfer-Encoding, CL+TE and real TCP/TLS fail-first evidence. This SA-009
  checkpoint alone still makes no request-framing claim.

## SA-010 HTTP/1 Request Framing (2026-09-11)

- Confirmed that transfer-coding lists and repeated fields bypass the old exact
  `chunked` check while `Content-Length` frames the request. A gzip, chunked body
  containing an embedded request is dispatched as `/outer` and `/inside-body`
  over parser, real TCP and generated TLS initial/keep-alive cases. The confirmed
  before suite has six passes and 17 failures. This is a deployment-dependent
  backend smuggling primitive, not a demonstrated named-proxy authorization
  bypass or direct-client privilege escalation.
- Request framing is now classified once. CL+TE, HTTP/1.0 transfer coding,
  empty/unknown lists, non-final or repeated chunked and parameterized chunked
  fail 400; valid final chunked fails 501 because request decoding remains
  unsupported. No case falls back to CL or an empty body. Content-Length is
  strict ASCII digits after SP/HTAB trimming, with overflow, signs, non-ASCII
  whitespace and ambiguous duplicates rejected. Malformed keep-alive reads get
  a generic mapped response and close.
- The first after run exposed an accidental compile break from removing a shared
  WebSocket helper and is retained as failure. Corrected confirmation passes 23
  tests and the expanded suite passes 28. A review-added form-feed length case
  then fails first because an httparse error is not mapped to a 400 response;
  generic request-error mapping fixes it. The final focused suite passes all 29,
  including ordinary gzip body handling and complete draining of an ignored
  body larger than the 64 KiB inline threshold before a legitimate next TCP/TLS
  request. Final production release build and fresh full `bin/verify` pass with
  526 router passes (one skip), 11 remote-auth, 13 native-router integration and
  browser gates. No retry, timeout, framing policy or performance threshold
  changed.
- The primary frozen ABBAAB comparison passes 24,288 measured requests and 1,248
  warmups with no strict findings: serial +2.01%, streaming +0.51%, and a retained
  short fresh-connection signal of -5.24%. A longer attempt preserves one 8,192-
  request baseline and stops its candidate on OS ephemeral-port exhaustion; the
  failed entry was not rerun. The host's 15-second MSL and 16,384-port range
  explain that harness ceiling.
- A distinct reverse-order campaign waits 35 seconds before every position and
  completes all 49,152 measured fresh connections plus 768 warmups. Candidate
  throughput is -0.25% with overlapping roughly 2.4-2.5% ranges; setup-inclusive
  p50/p99 are slightly lower, mean operation time +0.30%, and median server RSS
  slightly lower. No material affected-path regression is reproduced. This
  clears SA-010 valid-path performance only; earlier negative comparisons and
  audit-wide performance work remain open.
- The measured candidate is `6ca3966f`; final candidate `1a6d317f` changes only
  malformed httparse error classification and its regression. Two immutable
  final-binary campaigns each retain 31 preflight snapshots and stop before any
  warmup or measurement because unrelated inference remains above the unchanged
  quiet-host threshold. Direct final-binary timing remains pending; no external
  process or threshold was changed to manufacture a result.
- Evidence is
  `docs/security/2026-09-11-http1-request-framing-benchmarks.json` (SHA-256
  `1f450bbec6c95e3f380d4bf1cc0ad514b60a5401bd52158d0cc865ea98f59e73`).
  Keep the checkpoint local. Request chunked compatibility, paused SSE producer
  delivery, direct final-binary timing, deployment-specific proxy differential
  testing and every remaining component row still require review.

## SA-011 HTTP/1 Paused-Producer Delivery (2026-09-11)

- Confirmed that the chunked HTTP/1 writer could block on the next producer
  frame while response headers or a complete SSE chunk remained buffered below
  it. Two deterministic real-TLS regressions time out before the fix: headers
  are not readable while the producer has not emitted its first chunk, and a
  complete chunk is not readable while the producer remains open. This is a
  deployment-dependent availability and state-retention issue, not a
  demonstrated confidentiality, integrity or authorization bypass.
- The writer now flushes headers before waiting for the producer. After each
  chunk it drains immediately ready frames in order, flushes before awaiting a
  paused producer, and bounds a continuously ready batch to 64 chunks or 16 KiB.
  Terminal framing remains flushed. All write/flush failures close the response
  reader and propagate. Exact chunked wire bytes, TLS settings, ABI and versions
  are unchanged.
- A direct per-chunk implementation first passes ten focused cases. A new
  fail-first batching case then observes five flushes for three prequeued chunks
  instead of the expected header plus completed-body flush. The retained bounded
  coalescing implementation passes all 12 focused cases, including the two TLS
  stall regressions, midstream failure closure, exact wire bytes, completed-batch
  coalescing and the 64-chunk/16-KiB bound. All 190 `ct_core` unit tests and three
  serializer integrations pass outside the socket-restricted sandbox; the
  sandbox-only run retains 66 `PermissionDenied` socket failures rather than
  treating them as code evidence. `bin/test-fast`, a release build and fresh
  full `bin/verify` pass; full verification includes 526 router tests with one
  explicit skip, 11 remote-auth, 13 native-router integration and browser gates.
- The first immutable benchmark campaign stops before warmup because all 31
  unchanged quiet-host preflight snapshots contain high unrelated inference,
  VM, emulator or other CPU load. It is retained and not rerun in place. A
  distinct frozen ABBAAB campaign completes 24,288 measured requests and 864
  warmups with exact byte/sample/connection accounting, zero sample errors,
  zero selected transport-counter deltas and no strict findings.
- Median lifecycle throughput changes +1.00% for one 1-KiB response chunk,
  +0.56% for a 1-MiB response in eight 128-KiB chunks, and +37.49% for a 64-KiB
  response in 256-byte chunks. The first two ranges overlap; the small-chunk
  candidate is faster in all three runs. Median p99 and RSS do not regress
  materially. The small-chunk result is consistent with avoiding one awaited
  receive per immediately queued chunk, but does not prove a sole cause.
- Evidence is
  `docs/security/2026-09-11-http1-stream-delivery-benchmarks.json` (SHA-256
  `64c7368e63d697e4765e1520fb3e08a89bdc8f31866cd211e6b4b4b3efd9c267`).
  This clears SA-011 affected-path performance only. Earlier negative
  comparisons, direct SA-010 final-binary timing, finite resource availability
  and every unreviewed component row remain open. Keep this checkpoint local
  and unpublished.

## SA-012 Core Serializer Resource Boundaries (2026-09-11)

- Frozen-source probes reproduce `StackOverflowError` for 8,192-level
  MessagePack/CBOR and 65,536-level JSON WAMP payloads. Additional fail-first
  cases reproduce trailing binary-object acceptance, floating-point truncation
  in core binary integer fields, raw failure diagnostics, and an eight-field
  WAMP `RESULT` hidden in a valid RFC 8949 indefinite CBOR array.
- The retained serializers enforce depth 64 across recursive payload/PPT scans,
  require complete MessagePack/CBOR value consumption, reject floats in core
  binary WAMP integer fragments, bound recognized envelopes to seven fields,
  and emit only type/length diagnostics. Indefinite CBOR remains supported and
  uses a direct bounded top-level range scan rather than an incompatible ban.
- Nine focused security tests and all 192 serializer tests pass. Final probes
  turn each extreme nesting crash into `FormatException`, reject indefinite
  arity overflow, and show no probe payload in JSON/CBOR/MessagePack errors.
  Core analysis and `git diff --check` pass.
- The first long AOT candidate retained a 5.08% tiny-JSON median decrease. A
  no-redaction control did not recover it; removing only the unconditional
  pre-dispatch arity check did. The final dispatch-aware implementation keeps
  validation on every recognized fixed/payload path and restores the control.
- The final ABBAAB campaign completes 296,062,200 measured deserializations plus
  478,914 warmups, with 21 samples per variant/scenario and valid checksums. All
  ordinary ranges overlap; medians are -4.72% to -0.13%, indefinite CBOR is
  +21.39%, and median max RSS differs by +0.43%. Earlier opposite MessagePack
  movement for unchanged code is retained as shared-host variability. This
  clears measured SA-012 paths under the fixed -5%/range rule, not identical
  speed or audit-wide performance.
- Evidence is
  `docs/security/2026-09-11-serializer-resource-benchmarks.json`. Keep this
  checkpoint local and unpublished. The first full verification run hit one
  HTTP/3 handshake timeout; the exact test passed six isolated runs and a fresh
  complete `bin/verify` then exited zero. Continue collection/allocation
  amplification, optional numeric strictness, malformed short-array
  normalization, and every remaining component row rather than closing the
  audit.

## SA-013 Serializer Collection Allocation Boundaries (2026-09-11)

- A fail-first 9-byte MessagePack WAMP `RESULT` declaring a nested array32 of
  1,000,000 items reaches `msgpack_dart` and allocates its fixed-length list
  before discovering that item bytes are absent. The frozen AOT probe grows
  max RSS from 14,565,376 to 22,593,536 bytes and raises `RangeError`.
  `cbor` 6.5.1 builds collections incrementally, but impossible CBOR
  declarations are covered by the same early scanner invariant.
- MessagePack ordinary and depth-limited array/map scanners now reject a
  declared cardinality that cannot fit in the remaining frame: at least one
  byte per array item and two bytes per map entry. Definite CBOR scanners apply
  the same encoding lower bound. This introduces no arbitrary item cap, so
  valid collections remain bounded only by transport size and existing depth
  limits. Errors are payload-free `FormatException`s.
- The candidate AOT probe rejects the same MessagePack frame in 14 microseconds
  without increasing its 14,614,528-byte RSS. Ten focused tests, all 193
  serializer tests, core analysis, artifact validation, and `git diff --check`
  pass.
- The first complete implementation put CBOR exception construction in the hot
  recursive scanner. Its `array_1024` median was 4.46% lower with
  non-overlapping ranges, and a focused ABBAAB rerun confirmed 3.83% lower, so
  it was rejected. Outlining that cold path recovered the focused scenario to
  +1.53% with overlapping ranges while preserving fail-closed behavior.
- The final fresh ABBAAB campaign completes 313,030,914 measured
  deserializations plus 825,186 warmups across 16 scenarios. Every slower range
  overlaps baseline, the largest negative median is -2.07%, and median max RSS
  is identical. MessagePack 1,024-item arrays and 512-entry maps measure +7.72%
  and +8.90%; retain these as host observations rather than universal claims.
  Evidence is
  `docs/security/2026-09-11-serializer-collection-allocation-benchmarks.json`.
  Final repository-wide `bin/verify` exits zero, including native, Dart,
  package-consumer, router/MCP, and Chrome Dart2Wasm coverage.
  Keep this checkpoint local and unpublished. Continue optional numeric
  strictness, malformed short-array normalization, lazy-payload consistency,
  and every remaining component row rather than closing the audit.

## SA-014 Serializer Lazy-Payload Integrity (2026-09-12)

- The frozen `fbd29c37` probe confirms that valid eight-item MessagePack and
  CBOR argument lists fail only during lazy access, malformed MessagePack
  argument errors contain attacker-controlled text, and both binary serializers
  silently stringify numeric keyword keys. JSON also silently discarded
  malformed keyword maps.
- MessagePack and CBOR now use payload-specific positional decoders rather than
  the seven-field WAMP envelope parser, while preserving direct single-binary
  views. JSON, MessagePack, and CBOR validate materialized positional/keyword
  shapes, reject non-string keyword keys, and emit payload-free diagnostics.
  Valid wire behavior, envelope arity, and argument ordering remain unchanged.
- Thirteen focused tests, all 196 serializer tests, core analysis, and
  `git diff --check` pass. Final repository-wide `bin/verify` exits zero across
  native, Dart, package-consumer, router/MCP, live transport, and Chrome
  Dart2Wasm coverage.
- The first implementation's separated slower JSON argument/keyword ranges
  were rejected. Removing an unnecessary list copy and redundant key scan
  preserved strict validation and recovered both paths. The final ABBAAB AOT
  campaign completes 658,056,000 measured deserialize-plus-materialize
  operations and 7,200 warmups across 12 serializer/scenario pairs. No scenario
  triggers the fixed -5%/separated-slower-range rule; the largest negative
  median is -0.12% with overlapping ranges, and candidate median maximum RSS is
  slightly lower. Evidence is
  `docs/security/2026-09-12-serializer-lazy-payload-benchmarks.json`.
- Keep this checkpoint local and unpublished. Continue optional numeric
  strictness, malformed short-array normalization, consistency outside the
  reviewed lazy collection paths, and every remaining component row.

## Related Plans

The broader WampApp feature plan is paused while this security goal is active.
The Meta-discovery and coverage-CI fixes remain merged baseline work, not evidence
that this audit's other surfaces have been reviewed.

## Next Implementation Slice

SA-014 closes the confirmed lazy positional/keyword shape, key, and diagnostic
integrity defects without changing wire behavior and with final AOT performance
evidence. Continue the remaining component matrix rather than repeating
SA-012/013/014 serializer benchmarks. The next bounded core review should
inspect optional numeric strictness and malformed short-array normalization
across JSON, MessagePack, and CBOR, with fail-first protocol tests before any
behavior change.

SA-003 authentication-only hardening is locally verified, not published. Six
fail-first direct-service lifecycle regressions were reproduced on `1bc60ef1`.
The candidate shared transaction registry, capacity/timeout/cancellation guards,
and owner-scoped binding cleanup pass all 41 auth-service and 11 live mTLS
tests. An additional live abort experiment reproduced in-process router RPC
head-of-line blocking, including a second connection sharing the worker. The
experimental detached dispatch passed the same-connection regression but was
removed pending native lazy-payload ownership review. Router code is unchanged;
the retained live test proves deadline expiry during provider creation. The
85 worker tests pass. Initial full verification failed an experimental worker
assertion and a native HTTP/3 timeout; separated `bin/verify` now passes,
including the full router, package/live MCP, zero-copy, and browser checks.
Independently verify ownership after cancellation/disconnect and escaped views
before accepting detached dispatch; the retained-handle/reply-port lifetime
needs explicit evidence. Do not hide the blocking behavior behind the narrowed
service acceptance tests.
Six alternating AOT authentication benchmark passes completed 30,000 measured
logins plus 7,200 warmups without errors. Serial median throughput decreased
1.4%; concurrent increased 3.3%, with similar memory and lower median tails.
Ranges overlap; unrelated inference appeared during two baseline pass boundaries.
Retain the complete comparison and confirm under quieter conditions before
claiming zero overhead. Router RPC performance must be rechecked with any future
dispatch/ownership fix. Do not treat these green tests as complete audit or
release clearance.

1. Preserve the verified SA-001 implementation and its performance evidence.
   It is local only; do not confuse baseline master CI with hosted evidence for
   this new code. No publication or master integration has occurred.
2. Finish SA-002 performance evidence: the transport and benchmark dependency
   graphs and targeted regressions are upgraded. Retain the old compiled driver
   for native-only attribution and compare the new driver separately on the
   same patched server. Do not equate the source-level QUIC probe with encrypted
   network packet replay.
3. Complete quiet alternating HTTP comparisons. Final `bin/verify`, canonical
   production budgets, and large-frame/file checks pass. Retain the initial noisy
   comparison and partial lower-load attempt; do not call the serial H2 slowdown
   resolved without follow-up evidence. Keep unsafe TLS bypasses restricted to
   intentional benchmark fixtures.
4. Continue every outstanding row, including admitted-auth pending-state bounds
   and races, protocol/FFI fuzz and ownership cases, router/MCP authorization,
   payload key/replay handling, consumer device/storage boundaries, and
   platform-native/bundled dependencies. Do not close the goal after SA-002.
