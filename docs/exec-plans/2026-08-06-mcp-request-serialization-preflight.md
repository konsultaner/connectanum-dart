# MCP Request Serialization Preflight

Status: implementation complete; local and non-WAMP hosted verification clean;
WAMP hosted evidence blocked by a GitHub Actions major outage

## Goal

Ensure public Streamable HTTP and direct JSON MCP operations reject payloads
that cannot be encoded as JSON before opening an HTTP request or applying
authorization/session headers, while keeping caller-owned transports reusable.

## Scope

- In scope: ordinary POST-backed MCP requests and request-scoped listener setup,
  focused client regressions, public package boundary verification, and the
  normal local/hosted deployment evidence chain.
- Out of scope: changing accepted JSON-RPC shapes, adding a configurable request
  size limit, or changing established SSE subscription lifetime behavior.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `docs/project_state.md`
- This plan.

## Preconditions

- The two maintained `master` branches and local implementation checkpoint are
  aligned at `6195cb7a`.
- The prior Streamable HTTP operation-deadline implementation and exact-head
  hosted deployment chain are clean.
- Pre-change `bin/test-fast` must pass before implementation begins.

## Plan

1. Reproduce a non-JSON-encodable direct request opening the HTTP transport.
2. Serialize POST request bodies before opening the transport and prove local
   failure creates no request while a later valid call reuses the same client.
3. Run focused, fast, and full verification; update state; commit, push both
   maintained branches, and audit exact-head hosted evidence.

## Verification

- `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-06: Generic and typed direct helpers accept caller-provided JSON maps,
  so a nested unsupported object is a reachable local serialization failure.
  The current POST path opens the request and applies headers before encoding;
  serialization must therefore move ahead of request creation, not merely gain
  cleanup after failure.
- 2026-08-06: The focused regression failed before implementation because the
  counting caller-owned transport observed one `postUrl` call. After moving
  serialization, it observes zero calls, the endpoint sees no request, and a
  following valid direct ping succeeds through the same transport.
- 2026-08-06: Both maintained packages analyze cleanly; all 173 focused
  Streamable client cases and 14 public MCP IO-boundary cases pass. Post-change
  `bin/test-fast` passes 360 core, 95 MCP, 278 MCP/client, and 96 benchmark/live-
  router cases plus all neutral consumer, global-activation, CLI, and focused
  native/router follow-ups.
- 2026-08-06: Final `bin/verify` passes with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core,
  95 MCP, 278 MCP/client, 96 benchmark/live-router, and 387 router tests; all 13
  focused native-forwarding regressions; every neutral consumer package and
  CLI smoke; and Chrome Dart2Wasm WebSocket coverage.
- 2026-08-06: Implementation commit `674ffc0e` is on both maintained `master`
  branches. Exact-head Dart Package Publish Dry Run `31119882874`, Router Image
  dry run `31122235784`, and CI `31122235918` passed. CI uploaded coverage
  artifact `8974267783`; Router Image uploaded preview artifact `8974187315`
  and Docker build records `8974196215` and `8974196170`.
- 2026-08-06: GitHub Status reported an active Actions major outage while the
  WAMP workflow was retried. One attempt passed the cleartext and secure
  throughput artifact gates before GitHub canceled the next suite. A fresh
  exact-head recovery attempt, run `31125520838`, was then evicted after 17
  minutes with its only job cancelled before executing a step. The strict
  deployment-chain audit therefore exited one solely because the latest WAMP
  run was not green; CI/log scan, package dry run, relevant native-release
  evidence, Router Image/runtime smoke, branch protection, workflow visibility,
  and public package visibility were all ready. GitHub Status still reported
  Actions as a major outage with the incident under investigation.

## Handoff

- Implementation, push, and all non-WAMP verification are complete. Retry the
  exact-head WAMP Profile Benchmarks after the GitHub Actions incident clears,
  then rerun the comprehensive strict deployment-chain audit. Leave this
  hosted-evidence bookkeeping uncommitted until it can accompany the next
  implementation/configuration commit.
