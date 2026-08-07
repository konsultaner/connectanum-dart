# MCP Router WAMP Subscription Capacity

Status: completed; local and hosted verification clean

## Goal

Bound router-hosted MCP WAMP subscription state so direct JSON, maintained
Streamable HTTP, and configured dynamic-resource paths cannot retain an
unbounded number of subscription owners or client-selected event queues.

## Scope

- In scope: positive snake/camel route options, safe defaults, aggregate
  admission across preparation and active subscription lifetimes on one HTTP
  listener and route, a per-subscription queue ceiling, bearer and route
  isolation, continued use of admitted subscriptions and unrelated MCP
  protocols, failure cleanup, unsubscribe and session-delete recovery, and
  local plus exact-head hosted verification.
- Out of scope: WAMP realm-wide subscription quotas, distributed limits across
  router processes, changing broker subscription sharing semantics, retained
  events, per-principal quotas, and transport payload-size policy.

## Preconditions

- Both maintained `master` branches and the local branch start at `425b9b6d`.
- The preceding request-scoped listener-capacity checkpoint passed local
  verification, exact-head hosted workflows, and the comprehensive strict
  deployment audit.
- The preceding checkpoint's hosted-evidence bookkeeping is intentionally
  uncommitted and will accompany this implementation.

## Plan

1. Run the pre-change fast gate and add fail-first route-validation and native-
   router regressions showing that subscription count and queue size are
   unbounded.
2. Add positive `max_wamp_subscription_count` /
   `maxWampSubscriptionCount` and `max_wamp_subscription_queue_limit` /
   `maxWampSubscriptionQueueLimit` route options with bounded defaults.
3. Reserve route capacity across in-flight and active WAMP subscription owners,
   reject queue requests above the configured ceiling before broker admission
   or buffering any events, and release capacity on setup failure, unsubscribe,
   session cleanup, and endpoint disposal.
4. Prove public and protected direct/Streamable behavior, missing-bearer and
   route isolation, admitted-subscription continuity, session-state integrity,
   concurrent admission, and cleanup-driven recovery.
5. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- `dart analyze packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_json_test.dart`
- focused `router_integration_native_test.dart` regressions
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Source audit found that router-hosted WAMP subscription event
  buffers are bounded only by the caller-provided positive `queueLimit`, while
  the number of retained logical subscription owners is unbounded. Direct JSON
  uses a long-lived route endpoint, and compatibility endpoints retain the same
  state until explicit unsubscribe, session deletion/expiry, or router
  shutdown.
- 2026-08-07: The route limit will aggregate in-flight preparations and active
  WAMP subscription owners across authenticated/stateless endpoint instances
  for the same listener and route. The default count is 1024. The default queue
  ceiling is 100, preserving the existing default queue size while requiring an
  explicit route decision for larger buffers.
- 2026-08-07: The pre-change `bin/test-fast` gate passed. Fail-first route
  validation then accepted zero and string values for the new snake/camel
  options, while the focused native router accepted a queue of three events
  despite a configured ceiling of two.
- 2026-08-07: MCP routes now validate positive snake/camel subscription-count
  and queue-ceiling options. Admission runs after WAMP authorization and counts
  preparations plus active subscription owners on the same HTTP listener and
  route across endpoint instances. Setup failure releases the reservation and
  best-effort releases any broker subscription; explicit unsubscribe and
  endpoint disposal converge through the existing owner cleanup.
- 2026-08-07: Focused router analysis, all route JSON tests, and the native
  capacity regression pass. Coverage proves queue rejection, admitted-event
  delivery, aggregate direct JSON and compatibility ownership, protected-route
  bearer precedence and isolation, distinct-principal accounting, concurrent
  admission, explicit-unsubscribe recovery, and compatibility DELETE cleanup.
- 2026-08-07: Post-change `bin/test-fast` exited zero across 360 core tests, 95
  MCP tests, the complete 280-case MCP/client suite, all 96 benchmark tests
  including 36 live WAMP workloads, generated and globally activated consumer
  smokes, Router CLI coverage, and the focused native/auth/session follow-ups.
- 2026-08-07: Full `bin/verify` exited zero across formatting, 113 Rust core
  tests, 52 Rust FFI tests plus the focused metrics check, 360 Dart core tests,
  all 95 MCP tests, the complete 280-case MCP/client suite, all 96 benchmark
  tests including 36 live WAMP workloads, every generated and globally
  activated consumer smoke, the complete 389-case router suite, the 6-case
  remote-auth process, the 13-case native follow-up, and Chrome/Dart2Wasm
  WebSocket coverage.
- 2026-08-07: Implementation commit `c344b5c4` is on both maintained `master`
  branches. Exact-head GitHub CI `31199355333` passed Fast Checks, Full Verify,
  Dart VM Coverage, Codecov upload, clean hosted-log inspection, and coverage
  artifact `9002605026`. Dart Package Publish Dry Run `31199355388` and WAMP
  Profile Benchmarks `31199355228` with artifact `9002352086` passed on their
  first attempts. Router Image dry run `31200891491` passed the loaded-image
  MCP smoke, skipped GHCR login, completed the non-publishing multi-
  architecture build, and uploaded preview artifact `9002765139` plus Docker
  build records `9002910559` and `9002909609`. The comprehensive strict
  deployment-chain audit exited zero with exact-head CI/log, package, relevant
  native-release, Router Image, WAMP artifact, protected-branch, workflow-
  visibility, and public router-package gates ready.

## Handoff

- Complete. Implementation, local verification, both maintained `master`
  branches, exact-head hosted workflows, and the comprehensive strict
  deployment-chain audit are clean.
