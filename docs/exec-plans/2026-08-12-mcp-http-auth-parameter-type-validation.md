# MCP HTTP-Auth Parameter Type Validation

Status: complete

## Goal

Make the router-provided HTTP authentication endpoint reject explicitly
present JSON authentication parameters that are not strings before it
allocates or consumes challenge state or mutates a refresh/revocation lineage,
while preserving omission and operation-specific validation behavior.

## Context

Credential-source isolation compared distinct non-empty strings, but its
selector helper silently ignored non-string JSON values. A malformed body
value could therefore be treated as absent while a query or header alias drove
authentication, refresh rotation, or revocation. Explicit `null` had the same
problem because ordinary map lookup could not distinguish it from omission.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the Serena
   and overlap preflight, and establish a green pre-change fast matrix.
2. Add a fail-first router regression covering malformed initial parameters,
   challenge selectors/credentials, refresh inputs, and revoke inputs with
   legitimate retry and grant-preservation evidence.
3. Add presence-aware, operation-specific JSON string validation and return a
   state/token-free HTTP 400 with stable `invalid_auth_parameter` reason before
   mutation.
4. Extend the neutral installed-router consumer with malformed state rejection,
   pending-capacity retention, legitimate completion, and an explicit summary
   marker.
5. Run focused analysis/tests and full `bin/verify`, write durable Serena and
   project state, publish the implementation checkpoint, and audit the
   exact-head GitHub deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: The fail-first regression supplied a non-string initial realm
  alongside a valid realm header. The router proceeded to an HTTP 401
  challenge instead of returning the required fail-closed HTTP 400 before
  authenticator state allocation.
- 2026-08-12: Presence-aware validation now rejects explicit non-string or null
  operation selectors, initial realm/method/identity, challenge signatures,
  refresh aliases, revocation aliases, and revocation hints. Validation remains
  scoped to the selected operation and returns generic
  `invalid_auth_parameter` responses before state or token mutation.
- 2026-08-12: Router analysis and focused source-isolation, malformed-type,
  refresh, and revoke regressions pass. Shell syntax and the isolated neutral
  installed-router consumer smoke pass; the smoke reports
  `authParameterTypeValidation: true`, proves a malformed state source preserves
  pending capacity, and completes the legitimate challenge before continuing
  through protected MCP, direct JSON, pub/sub, refresh/revoke, and Streamable
  HTTP paths.
- 2026-08-12: Full `bin/verify` passes with zero formatting changes, clean
  analysis, 114 Rust core tests, 52 Rust FFI tests, the 360-case Dart core
  suite, 101 MCP package tests, the complete 280-case client/MCP matrix, all 96
  benchmark cases and 36 live WAMP workloads, all 434 router tests, six
  isolated remote-auth integrations, 13 native follow-ups, every neutral
  consumer and installed-command smoke, and Chrome/Dart2Wasm coverage.
- 2026-08-12: Commit `f988d873` is published to both maintained `master`
  branches. Exact-head GitHub CI `31557226313`, Dart Package Publish Dry Run
  `31557226228`, WAMP Profile Benchmarks `31557226245`, and dispatched Router
  Image dry run `31557247322` all pass. Retained artifacts are Dart VM coverage
  `9126725792`, WAMP evidence `9126537780`, Router Image preview `9126418018`,
  and Docker build records `9126508597` / `9126508047`. The comprehensive
  strict deployment-chain audit exits zero with clean exact-head CI logs,
  loaded-image MCP runtime smoke, relevant native-release evidence, and every
  required deployment gate ready. RC creation remains an explicit
  release-approval action outside this checkpoint.
