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
| Native transport and FFI | RawSocket/WebSocket/HTTP1/2/3, TLS, framing, resource bounds, handle ownership, unsafe code, zero-copy lifetimes | Pending |
| Client sessions | Authentication lifecycle, reconnect races, unsolicited replies, cancellation, file transfer, browser/native parity | Pending |
| Authentication and auth service | Ticket/CRA/SCRAM/cryptosign, remote delegation, credential rotation, KDF limits, identity binding, pending transactions | SA-001 admission fix reproduced and locally passing; broader review pending |
| Router authorization and state | Realm/role boundaries, RPC/pubsub/meta, pattern grants, dynamic authorization races, worker isolation | Pending; previous Meta fix is baseline only |
| HTTP and MCP | Origins, redirects, HTTP auth grants, sessions/SSE, tool/resource access, request smuggling, file/proxy routes and SSRF | Pending |
| Payload cryptography | Key/nonce lifetime, replay/context binding, authenticated metadata, E2EE parity and file integrity | Pending |
| Consumer application | Account/device trust, encrypted storage/backup, attachments, push, WebRTC, MCP consent, native/web boundaries | Pending |
| Packaging and dependencies | All Dart/Rust lockfiles, advisories and reachability, native download verification, CLI/config secrets, workflows and publishing | SA-002: both Rust lockfiles scanned, network advisories open; other coverage pending |

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

## Related Plans

The broader WampApp feature plan is paused while this security goal is active.
The Meta-discovery and coverage-CI fixes remain merged baseline work, not evidence
that this audit's other surfaces have been reviewed.

## Next Implementation Slice

1. Preserve the verified SA-001 implementation and its performance evidence.
   It is local only; do not confuse baseline master CI with hosted evidence for
   this new code. No publication or master integration has occurred.
2. Address SA-002 before returning to other surfaces: capture HTTP/2 and HTTP/3
   baselines, update shipping `quinn-proto` and migrate `h2`/HTTP types to patched
   versions, then update the benchmark's legacy TLS client dependency. Inspect
   upstream regression tests and add relevant transport attack regressions.
3. Rerun both dependency audits, targeted transport tests, before/after HTTP
   benchmarks and production budgets, and `bin/verify`. Keep unsafe TLS bypasses
   restricted to intentional benchmark fixtures, not consumer/production paths.
4. Continue every outstanding row, including admitted-auth pending-state bounds
   and races, protocol/FFI fuzz and ownership cases, router/MCP authorization,
   payload key/replay handling, consumer device/storage boundaries, and
   platform-native/bundled dependencies. Do not close the goal after SA-002.
