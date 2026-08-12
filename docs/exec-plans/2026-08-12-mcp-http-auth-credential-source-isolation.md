# MCP HTTP-Auth Credential Source Isolation

Status: complete; implementation, publication, and hosted verification green

## Goal

Make the router-provided HTTP authentication endpoint reject distinct realm,
authentication method, authentication identity, challenge signature, refresh
credential, revocation credential, or revocation hint values supplied through
different supported request sources before it allocates or consumes challenge
state or mutates a token lineage, while accepting identical duplicates.

## Context

The auth bridge already isolated operation selectors, but other security-
sensitive parameters still chose the first non-empty body, query, or header
value. Most critically, challenge continuation removed pending state before it
resolved a body signature ahead of a different header signature. Refresh and
revocation aliases could likewise disagree while the first credential or hint
silently controlled token mutation.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the Serena
   and overlap preflight, and establish a green pre-change fast matrix.
2. Add fail-first router regressions for initial auth parameters, challenge
   signatures, refresh aliases, revocation aliases and hints, legitimate retry
   preservation, and identical duplicate acceptance.
3. Resolve distinct non-empty values before authenticator state or token work
   and return a state/token-free HTTP 400 with stable
   `conflicting_auth_parameter` reason.
4. Extend the neutral installed-router consumer through conflicting signature
   rejection, pending-capacity retention, legitimate completion, and protected
   MCP paths.
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
- 2026-08-12: The fail-first regression supplied different explicit initial
  auth values in body and headers. The router proceeded to an HTTP 401
  challenge instead of returning the required fail-closed HTTP 400 before
  authenticator state allocation.
- 2026-08-12: Initial realm/method/identity, continuation signature, refresh
  credential aliases, revocation credential aliases, and revocation hints now
  require agreement across supported sources. Conflicts return
  `conflicting_auth_parameter` before mutation; identical challenge values
  remain valid and the preserved pending state completes normally.
- 2026-08-12: Router analysis and focused selector/signature, refresh, and
  revocation runtime regressions pass. Shell syntax and the isolated neutral
  installed-router consumer smoke pass; the smoke reports
  `authCredentialSourceIsolation: true`, proves a signature conflict is
  state/token-free and preserves pending capacity, then continues through
  protected MCP, direct JSON, pub/sub, refresh/revoke, and Streamable HTTP
  paths.
- 2026-08-12: Full `bin/verify` passes with zero formatting changes, clean
  analysis, 114 Rust core tests, 52 Rust FFI tests, the 360-case Dart core
  suite, 101 MCP package tests, the complete client/MCP matrix, all 96
  benchmark cases and 36 live WAMP workloads, all 433 router tests, six
  isolated remote-auth integrations, 13 native follow-ups, every neutral
  consumer and installed-command smoke, and Chrome/Dart2Wasm coverage.
- 2026-08-12: Commit `dfa0b97d` is published to both maintained `master`
  branches. Exact-head GitHub CI `31553032837`, Dart Package Publish Dry Run
  `31553032815`, WAMP Profile Benchmarks `31553032736`, and dispatched Router
  Image dry run `31553065280` all pass. Retained artifacts are Dart VM coverage
  `9125308797`, WAMP evidence `9125084054`, Router Image preview `9124965030`,
  and Docker build records `9125038671` / `9125038313`. The comprehensive
  strict deployment-chain audit exits zero with clean exact-head CI logs,
  loaded-image MCP runtime smoke, relevant native-release evidence, and every
  required branch, workflow, package, publish-dry-run, image, and benchmark
  gate ready. RC creation remains an explicit release-approval action outside
  this checkpoint.
