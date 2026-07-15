# Exec Plan: WAMP Profile Production Readiness Audit

## Status

Complete.

## Goal

Establish an evidence-backed Basic Profile and Advanced Profile support matrix,
correct feature negotiation so peers see exactly the capabilities implemented,
and decide whether the canonical benchmark evidence is sufficient for
production use.

## Scope

- Map every Basic Profile message flow required by the implemented client and
  router roles to source and behavioral tests.
- Classify every Advanced Profile feature as implemented, partial, unsupported,
  or out of scope, preserving the specification's modular feature model.
- Reproduce and correct inaccurate `HELLO`/`WELCOME` feature announcements
  without advertising MCP-only APIs as WAMP Advanced Profile support.
- Audit conformance-vector breadth separately from package-owned behavioral
  tests.
- Audit canonical benchmark coverage, checked-in budgets, latest hosted values,
  repeatability, platform/worker coverage, and operational blind spots.

## Non-Goals

- Implement every experimental Advanced Profile feature; alpha, beta, and
  sketch features remain demand-driven.
- Treat transport throughput as proof of protocol conformance.
- Reopen unrelated HTTP/3, kTLS, E2EE, or MCP feature work.

## Verification Plan

- Run `bin/test-fast` before substantial edits.
- Add focused feature-announcement regressions before changing defaults.
- Run focused core, client, and router tests for negotiation and advertised
  behaviors.
- Validate benchmark artifacts against the checked-in policies and inspect the
  latest hosted WAMP Profile Benchmarks run.
- Run `bin/verify` before handoff.

## Progress

- 2026-07-13: Confirmed the latest hosted WAMP Profile Benchmarks run
  `29084302142` passed on commit `5034dc7`; all three performance-policy
  families have substantial throughput and p95 latency headroom.
- 2026-07-13: Confirmed the canonical gate covers cleartext and TLS
  RawSocket/WebSocket RPC and pub/sub across JSON, MessagePack, and CBOR,
  control cycles, and native-client fan-out, but runs on one hosted Linux
  configuration with one router worker and one native runtime thread.
- 2026-07-13: Found that router `WELCOME` details currently leave every Broker
  and Dealer Advanced Profile feature flag false despite tested support for
  several features. Client role defaults also under-announce call cancellation
  and contain subscriber-role fields that do not match the specification.
- 2026-07-13: Pre-change `bin/test-fast` passed. Corrected role feature models,
  outgoing `HELLO`/`WELCOME` announcements, and the standard
  `publication_trustlevels` wire key while retaining decode compatibility for
  the historical spelling.
- 2026-07-13: Added feature-announcement, serializer, conformance-normalizer,
  and native message-binding regressions. Focused tests and package analysis
  passed, and full `bin/verify` completed successfully.
- 2026-07-13: Published the support and evidence matrix in
  `docs/wamp_profile_support.md`. The implemented Basic Profile and announced
  Advanced Profile subset are ready for controlled production use with a
  workload-specific load test. Full Advanced Profile compatibility and
  arbitrary production scale are not claimed; the main evidence gaps are
  multi-worker/platform gates, soak and resource budgets, broader upstream
  multi-session conformance vectors, and performance gates for advanced
  behaviors.

## Outcome

- Feature negotiation now advertises only existing, tested role capabilities.
- At this audit checkpoint, timeout, WAMP Meta API, and progressive invocation
  were unsupported. They were subsequently implemented and verified under
  `2026-07-15-final-wamp-release-features.md`; trust-level assignment, history,
  sharding, router-side revocation, reflection, and rerouting remain disabled.
- Benchmark results have substantial margin against the checked-in policies,
  but the gate remains a single-host Linux configuration with short samples;
  it is release evidence for the covered topology rather than universal
  capacity certification.
