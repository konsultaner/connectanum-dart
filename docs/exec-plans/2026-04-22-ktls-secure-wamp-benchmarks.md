# Exec Plan: ktls-secure-wamp-benchmarks

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Extend the existing benchmark harness so secure RawSocket and secure WebSocket
WAMP workloads can run on the same TLS-enabled Linux bench path that now works
for the HTTP/2 kTLS prototype.

## Scope

- In scope:
  - Add a TLS-enabled WAMP listener to the shipped bench router config.
  - Ensure the bench target-resolution path can deliberately select secure WAMP
    targets instead of always preferring the current cleartext listener.
  - Add at least one secure WAMP smoke/benchmark scenario that proves the new
    listener path works for the existing harness.
  - Refresh `docs/project_state.md` and related kTLS notes with the secure-WAMP
    benchmark contract.
- Out of scope:
  - Broad kTLS performance tuning beyond what is needed to get secure WAMP
    measurements running.
  - New non-WAMP transport benchmarks.
  - Declaring production-ready TLS 1.3 key-update handling on the kTLS path.

## Files Expected To Change

- `native/bench/bench_router.json`
- `native/bench/scenarios/*.toml`
- `packages/connectanum_bench/lib/src/wamp_transport_targets.dart`
- `packages/connectanum_bench/dart_test.yaml`
- `packages/connectanum_bench/tool/bench_main.dart` and/or
  `packages/connectanum_bench/tool/wamp_client_main.dart` if secure-target
  selection needs to become explicit
- `bin/test-fast`
- `bin/test-all`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-ktls-secure-wamp-benchmarks.md`
- `docs/ktls_research.md` if the benchmark contract changes materially

## Preconditions

- The hosted HTTP/2 kTLS correctness milestone is already closed on commit
  `6d18344`.
- `bin/test-fast` is green before changing the bench path again.

## Plan

1. Add a TLS-enabled WAMP bench listener and confirm it advertises the same
   protocol and serializer surface the current WAMP bench scenarios need.
2. Make secure-target selection explicit in the bench runner so a secure WAMP
   benchmark does not silently fall back to the current higher-scored cleartext
   listener.
3. Add a secure WAMP smoke or benchmark scenario, run local verification, and
   then update the checked-in state before scheduling hosted Linux runs.

## Verification

- `bin/test-fast`
- Targeted bench-harness tests for secure WAMP target resolution
- `bin/verify`

## Decision Log

- 2026-04-22: The HTTP/2 kTLS prototype is now correct enough to shift from
  transport-handshake debugging to expanding benchmark coverage.
- 2026-04-22: The current bench target scorer prefers non-HTTP, non-secure
  listeners, so secure WAMP benchmarking needs an explicit selection path
  rather than relying on listener ordering.
- 2026-04-22: Used an explicit `secure_transport = true` workload flag instead
  of inventing a second secure-only WAMP protocol family, because the existing
  protocol names already describe the wire transport and serializer surface.
- 2026-04-22: Extended the shipped bench router config with a TLS WAMP listener
  on `127.0.0.1:8083` and aligned both the cleartext and TLS WebSocket
  listeners to advertise `wamp.2.json`, `wamp.2.msgpack`, and `wamp.2.cbor`.
- 2026-04-22: Queued GitHub Actions run `24777296956` (`kTLS Validation`) via
  `workflow_dispatch` with `scenario=native/bench/scenarios/wamp_secure_smoke.toml`
  because the push-triggered workflow still defaults to `h2_smoke.toml`.
- 2026-04-22: Hosted run `24777296956` failed before the bench reported `READY`
  because the Dart router layer incorrectly rejected shared SNI hostname
  `localhost` across distinct TLS endpoints.
- 2026-04-22: Follow-up runs `24778942812`, `24778930521`, and `24778930527`
  showed that the attempted `127.0.0.1` workaround was also wrong because the
  native TLS config path requires DNS-style SNI hostnames, not IP literals.
- 2026-04-22: The shipped secure WAMP listener is back on `localhost`, the
  cross-endpoint duplicate-SNI restriction is removed from the Dart router, and
  `packages/connectanum_bench/test/bench_router_config_test.dart` now starts
  the shipped config through `Router.start(NativeTransportRuntime)` with
  distinct reserved listener/http3 ports so this startup path fails locally
  before another hosted run.
- 2026-04-22: Hosted runs `24780721173` (`kTLS Validation`) and
  `24780721191` (`kTLS HTTP/2 Benchmarks`) passed on commit `70f1525`, but the
  generic `CI` run `24780721174` still failed in `Full Verify` because
  `bin/test-all` invoked `dart test packages/connectanum_bench/test` from the
  repo root, bypassing the bench package's future serial test contract and
  letting `bench_router_config_test.dart` collide with the Linux-only
  process-global native WAMP harness in the same package.
- 2026-04-22: Running the bench suite from `packages/connectanum_bench` also
  exposed that `bench_router_config_test.dart` relied on repo-root current
  directory state for the shipped config's relative TLS asset paths, so the
  regression now temporarily switches to the repo root while loading and
  starting `native/bench/bench_router.json`; the bench package stays
  serialised via `packages/connectanum_bench/dart_test.yaml`, so that cwd
  change does not race the rest of the suite.
- 2026-04-22: GitHub Actions run `24782645871` (`CI`) passed on commit
  `b6e458e`, confirming the hosted Linux root-verification fix for the bench
  package package-root/serial test contract.
- 2026-04-22: Manual `kTLS Validation` run `24783846529` reached the secure
  WAMP workloads and completed the secure RawSocket cases, then failed on
  `websocket_secure_rpc_json` with `HandshakeException:
  CERTIFICATE_VERIFY_FAILED: self signed certificate`, which showed the
  remaining blocker was the Dart secure WebSocket bench client path rather
  than router startup or native secure-listener selection.
- 2026-04-22: Added `packages/connectanum_bench/test/wamp_session_factory_test.dart`
  as a real self-signed `wss://localhost` regression and fixed
  `WebSocketWampSessionFactory` to forward `allowInsecureCertificates` into the
  Dart `connectanum_client` WebSocket transport factories for JSON, MsgPack,
  and CBOR workloads.
- 2026-04-22: The first full local `bin/verify` pass after that bench fix
  exposed an unrelated flaky router test:
  `Cryptosign authenticator rejects wrong signature` sometimes regenerated the
  same signature because it hard-coded the first byte to `ff`; the test now
  always flips the first byte so the full suite can validate the secure-WAMP
  work without a 1-in-256 false negative.
- 2026-04-22: GitHub Actions run `24785214332` (`kTLS Validation`,
  `workflow_dispatch`) passed on commit `0b4f1e7`, and push `CI` run
  `24785189137` passed on the same commit, closing the hosted secure-WAMP
  smoke milestone.

## Handoff

- This plan starts with harness/config work, not more low-level kTLS handoff
  changes.
- This milestone is closed. The next active work is throughput-grade secure
  WAMP measurement in `docs/exec-plans/2026-04-22-ktls-secure-wamp-throughput.md`.
