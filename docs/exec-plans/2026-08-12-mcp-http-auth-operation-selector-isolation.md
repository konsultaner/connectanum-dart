# MCP HTTP-Auth Operation Selector Isolation

Status: complete; implementation, publication, and hosted verification green

## Goal

Make the router-provided HTTP authentication endpoint reject requests that mix
a pending challenge `state` with a refresh or revocation `grant_type` before it
consumes challenge state or issues token state.

## Context

The auth bridge previously dispatched a non-empty `state` before it inspected
`grant_type`. A malformed request could therefore combine a valid pending
ticket challenge response with `grant_type=refresh_token`; the bridge ignored
the token operation, consumed the challenge, and issued a fresh access and
refresh grant. Challenge continuation and token operations are distinct request
selectors and must be mutually exclusive.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run the
   pre-change fast regression matrix from a dedicated feature branch.
2. Add a fail-first router regression that combines a valid pending challenge
   response with a refresh selector and proves the existing state remains
   usable after rejection.
3. Resolve both operation selectors before dispatch and return a state-free
   HTTP 400 with stable `conflicting_auth_operation` reason when both exist.
4. Extend the neutral installed-router consumer proof through the same conflict,
   pending-capacity retention, legitimate completion, and protected MCP paths.
5. Run focused analysis/tests, full `bin/verify`, update durable Serena/project
   state, publish the implementation checkpoint, and audit the exact-head
   GitHub deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes; local and both maintained
  `master` heads matched exact commit `f0f8b14d` with a clean hosted deployment
  chain.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: Symbol-aware inspection found that challenge state dispatch runs
  before grant-type dispatch. The fail-first regression started a ticket
  challenge, sent its valid response together with `grant_type=refresh_token`,
  and received HTTP 200 plus a fresh grant instead of a state-preserving HTTP
  400.
- 2026-08-12: The auth bridge now resolves both selectors before dispatch and
  rejects their combination with `conflicting_auth_operation`; the fail-first
  regression passes and completes the original state successfully afterward.
- 2026-08-12: Router analysis and all 15 auth-bridge runtime tests pass,
  preserving ticket, CRA, SCRAM, capacity, lockout, refresh concurrency,
  rotation, and revocation behavior. Shell syntax and the isolated neutral
  installed-router consumer smoke pass; the smoke reports
  `authSelectorIsolation: true`, proves the rejection is state/token-free and
  preserves pending capacity, then continues through protected MCP, direct
  JSON, pub/sub, refresh/revoke, and Streamable HTTP paths.
- 2026-08-12: Full `bin/verify` passes, including 432 router tests, all 6
  isolated remote-auth integrations, all 13 native follow-ups, and the
  Chrome/Dart2Wasm WebSocket check.
- 2026-08-12: Commit `8cbddf5f` is published to both maintained `master`
  branches. Exact-head GitHub CI `31543769528`, Dart Package Publish Dry Run
  `31543769544`, WAMP Profile Benchmarks `31543769533`, and dispatched Router
  Image dry run `31543775676` all pass. Retained artifacts are Dart VM coverage
  `9122123016`, WAMP evidence `9121862416`, Router Image preview `9121695965`,
  and Docker build records `9121801808` / `9121801287`. The comprehensive
  strict deployment-chain audit exits zero with clean exact-head CI logs and
  every required branch, workflow, package, publish-dry-run, image, and
  benchmark gate ready. RC creation remains an explicit release-approval
  action outside this checkpoint.
