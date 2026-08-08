# MCP Router Failed SSE Sequence Rollback

Status: completed; implementation published, full local verification,
exact-head hosted evidence, and strict deployment-chain audit green

## Goal

Keep compatibility-era router-hosted MCP SSE replay state bounded and
transactional when a GET/SSE or POST/SSE response cannot be opened or written.
Uncommitted sequence reservations must roll back without losing queued
notifications, disturbing committed replay history, or creating duplicate
event identifiers during overlapping attempts.

## Scope

- In scope: per-stream sequence reservations made while assembling GET/SSE and
  POST/SSE responses, failed-send rollback, POST-to-JSON fallback, conditional
  rollback under overlapping reservations, queued-notification restoration,
  and focused plus full local/hosted verification.
- Out of scope: changing the 128-event replay-history window, changing the SSE
  event identifier format, changing successful Last-Event-ID replay semantics,
  or adding a new route option.

## Preconditions

- Local head and both maintained `master` branches start at `d4f42076`.
- The preceding notification-coalescing milestone passed local verification,
  exact-head hosted workflows, and the comprehensive strict deployment-chain
  audit.
- The preceding milestone's hosted-evidence bookkeeping is intentionally
  uncommitted and will accompany this implementation.
- Pre-change `bin/test-fast` passed on 2026-08-08.

## Plan

1. Add a fail-first state-machine regression proving failed reservations leave
   fresh stream entries and do not restore a prior committed sequence.
2. Record the previous and final reserved sequence for every stream represented
   by an uncommitted SSE batch.
3. On failed delivery, restore queued notifications and conditionally roll the
   sequence back only when the failed batch still owns the current reservation.
4. Route failed POST/SSE delivery through the same rollback path before its
   existing JSON response fallback.
5. Preserve committed history eviction, successful delivery, and concurrent
   reservation monotonicity.
6. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- focused SSE sequence-reservation regression
- `dart analyze packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-08: `_sseStreamSequences` is normally bounded indirectly by replay
  history eviction, but only committed events enter replay history. GET/SSE
  send failure restores pending messages without reverting its sequence entry,
  while POST/SSE send failure falls back to JSON without calling restoration.
  Repeated disconnected consumers can therefore retain one fresh stream key
  per failed response for the lifetime of an otherwise valid MCP session.
- 2026-08-08: Rollback must compare the batch's final reservation with the
  current sequence before changing state. This lets reverse-order failures
  restore exactly while an older failure cannot overwrite a newer overlapping
  reservation.
- 2026-08-08: A fail-first state-machine regression reproduced the retained
  fresh stream entry before implementation. GET/SSE and POST/SSE batches now
  carry their previous and final sequence reservations; failed delivery rolls
  back only a reservation the batch still owns, and POST/SSE performs that
  rollback before its existing JSON fallback. The regression covers fresh and
  existing streams, stale overlapping failures, and exact reverse-order
  unwind.
- 2026-08-08: Focused sequence-state coverage, router analysis, and native
  integration regressions for notification coalescing and bounded/recoverable
  Streamable polling pass. Post-change `bin/test-fast` and `bin/verify` pass;
  full verification includes 392 router tests, 36 live WAMP workloads, all
  generated and globally activated consumer smokes, remote-auth isolation,
  native follow-ups, and Chrome/Dart2Wasm.
- 2026-08-08: Commit `435eb5a9` was pushed to both maintained `master`
  branches. Exact-head CI `31226447158`, Dart Package Publish Dry Run
  `31226447111`, WAMP Profile Benchmarks `31226447125`, and Router Image dry
  run `31226466999` all passed. CI uploaded coverage artifact `9012574232`;
  WAMP uploaded artifact `9012389165`; Router Image uploaded preview artifact
  `9012261197` plus Docker build records `9012358200` and `9012357649`.
- 2026-08-08: The comprehensive strict deployment-chain audit passes with a
  clean exact-head CI job set and log scan, clean exact-head package, Router
  Image, and WAMP evidence, and relevant native dry-run evidence from
  `d4f42076` because this commit changed no native-release-sensitive paths.

## Handoff

- Failed compatibility SSE deliveries no longer retain uncommitted stream
  sequence state, and overlapping failures preserve newer reservations.
  Implementation, local verification, dual-remote publication, exact-head
  hosted workflows, and the comprehensive strict audit are green. Select the
  next router-hosted MCP or downstream-readiness implementation gap from the
  roadmaps.
