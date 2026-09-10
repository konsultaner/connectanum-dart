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
| Core protocol and serializers | Malformed JSON/MessagePack/CBOR, lengths, IDs, nesting, lazy payload consistency | Pending |
| Native transport and FFI | RawSocket/WebSocket/HTTP1/2/3, TLS, framing, resource bounds, handle ownership, unsafe code, zero-copy lifetimes | SA-002 native dependency mitigation and bounded H2/QUIC regressions pass; broader review and performance confirmation pending |
| Client sessions | Authentication lifecycle, reconnect races, unsolicited replies, cancellation, file transfer, browser/native parity | Pending |
| Authentication and auth service | Ticket/CRA/SCRAM/cryptosign, remote delegation, credential rotation, KDF limits, identity binding, pending transactions | SA-001 admission and SA-003 transaction fixes reproduced and locally verified; SA-003 performance provisional, broader review pending |
| Router authorization and state | Realm/role boundaries, RPC/pubsub/meta, pattern grants, dynamic authorization races, worker isolation | Pending; previous Meta fix is baseline only |
| HTTP and MCP | Origins, redirects, HTTP auth grants, sessions/SSE, tool/resource access, request smuggling, file/proxy routes and SSRF | Pending |
| Payload cryptography | Key/nonce lifetime, replay/context binding, authenticated metadata, E2EE parity and file integrity | Pending |
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

## Related Plans

The broader WampApp feature plan is paused while this security goal is active.
The Meta-discovery and coverage-CI fixes remain merged baseline work, not evidence
that this audit's other surfaces have been reviewed.

## Next Implementation Slice

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
