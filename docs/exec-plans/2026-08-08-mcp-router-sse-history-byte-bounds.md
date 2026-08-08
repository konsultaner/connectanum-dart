# MCP Router SSE History Byte Bounds

Status: completed; implementation published, full local verification,
exact-head hosted evidence, and strict deployment-chain audit green

## Goal

Bound compatibility-era Streamable HTTP replay history by encoded SSE wire
bytes per router-hosted MCP endpoint while preserving one complete maximum-size
response batch, newest-event replay, endpoint reuse, and sessionless direct
JSON access for consumer applications.

## Scope

- In scope: encoded SSE history byte accounting, oldest-event eviction, a
  validated route ceiling with snake_case and camelCase spellings, a default
  derived from the route response ceiling, direct JSON and compatibility
  session recovery coverage, public example configuration, and generated
  consumer configuration coverage.
- Out of scope: changing the existing 128-event history count ceiling,
  persisting replay history outside the process, changing `Last-Event-ID`
  unknown-cursor semantics, or making WAMP event polling transactional across
  HTTP delivery failures.

## Preconditions

- Local head and both maintained `master` branches start at `d0fbbfd3`.
- The preceding WAMP subscription byte-bound milestone passed local
  verification, exact-head hosted workflows, and the strict deployment-chain
  audit.
- Its hosted-evidence bookkeeping is intentionally carried into this
  implementation commit.
- The only other live Codex work at startup is in an unrelated repository; the
  scheduled wrapper and live lock belong to this run.

## Plan

1. Run pre-change `bin/test-fast`.
2. Add fail-first route validation for positive
   `max_sse_history_bytes` / `maxSseHistoryBytes` and require the configured
   ceiling to hold one full `max_response_bytes` batch.
3. Add a fail-first native-router regression that commits multiple large
   POST/SSE responses, observes oldest-cursor eviction before the 128-event
   count ceiling, replays the newest cursor, and proves compatibility session
   plus direct JSON reuse.
4. Track encoded SSE history bytes per endpoint and evict the oldest events
   until both the count and byte ceilings hold, cleaning obsolete stream
   sequence reservations with the existing ownership rule.
5. Align public example and generated consumer route configuration with the
   bounded replay policy.
6. Run focused, fast, and full verification; commit and push both maintained
   branches; then audit exact-head hosted evidence.

## Verification

- `bin/test-fast` (pre-change) — passed on 2026-08-08
- focused router option-validation test — passed
- focused native compatibility replay-history regression — passed
- `python3 -m unittest tool.test_mcp_consumer_package_boundary` — 19 passed
- `dart analyze packages/connectanum_router` — passed
- `bin/test-fast` (post-change) — passed
- `bin/verify` — passed on 2026-08-08; formatting was unchanged, Rust
  transport/FFI tests passed, all Dart and consumer matrices passed, the
  benchmark suite passed all 96 cases including 36 live WAMP workloads, the
  router suite passed all 393 cases, remote-auth and native follow-ups passed,
  and Chrome/Dart2Wasm passed

## Decision Log

- 2026-08-08: The existing 128-event ceiling bounds history cardinality but
  not retained memory. Near-limit POST/SSE responses could retain roughly 128
  times `max_response_bytes` per compatibility endpoint.
- 2026-08-08: The default byte ceiling equals the route response ceiling. This
  bounds memory while retaining at least the latest complete response batch;
  explicit smaller history ceilings are rejected because they would make a
  valid maximum-size response immediately unreplayable.
- 2026-08-08: Fail-first option validation accepted a zero byte ceiling, and
  the native router retained the oldest cursor after four large POST/SSE
  responses (eight events, well below the 128-event limit). The implemented
  route rejects invalid or undersized ceilings, accounts the exact encoded SSE
  representation, evicts oldest events, rejects an evicted cursor, replays the
  newest retained response, and preserves compatibility session plus direct
  JSON reuse.
- 2026-08-08: Implementation commit `db50a3f7` was pushed to both maintained
  `master` branches. Exact-head CI `31234999618`, Dart Package Publish Dry Run
  `31234999638`, WAMP Profile Benchmarks `31234999624`, and Router Image dry
  run `31235013230` all passed without a retry. CI uploaded coverage artifact
  `9015292310`; WAMP uploaded artifact `9015148217`; Router Image uploaded
  preview artifact `9015070572` plus Docker build records `9015126948` and
  `9015126567`.
- 2026-08-08: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs, clean package, WAMP, and loaded-image
  Router Image evidence, and relevant Native Artifacts dry-run evidence from
  `d4f42076` because no native-release-sensitive paths changed afterward. Its
  non-gating RC summary remains intentionally not ready because no approved RC
  tag points at this implementation commit.

## Handoff

- Compatibility Streamable replay history is now count- and byte-bounded with
  validated configuration, exact encoded-byte accounting, oldest-first
  eviction, and consumer recovery evidence. Implementation, complete local
  verification, dual-remote publication, exact-head hosted workflows, and the
  comprehensive strict audit are green. Select the next router-hosted MCP or
  downstream-readiness implementation gap from the roadmaps.
