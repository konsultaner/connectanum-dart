# Exec Plan: MCP OAuth Step-Up Authorization Request

Status: complete; implementation, local verification, and hosted evidence green
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Let a downstream application safely turn a runtime MCP
`insufficient_scope` response into a resource-bound OAuth authorization
request without reconstructing challenge validation or scope-union rules.

## Scope

- In scope:
  - Add a public fail-closed helper on `McpStreamableHttpClient` for a real
    HTTP 403 Bearer `insufficient_scope` response.
  - Bind the request to the current grant's MCP resource, authorization
    server, and client identifier.
  - Preserve all previously granted/requested scopes and add the authoritative
    challenge scopes once, with OAuth scope-token validation.
  - Keep authorization launch, retry limits, token exchange, grant replacement,
    and operation retry under consumer control.
  - Prove the helper through focused, public IO, and isolated installed-package
    live HTTP coverage without private project assumptions.
- Out of scope:
  - Automatically opening a browser or retrying a failed MCP operation.
  - Replacing the active grant before the consumer completes authorization and
    token exchange.
  - Changing router challenge generation or Streamable HTTP session ownership.

## Preconditions

- Commit `499f5bf1` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The two pre-existing hosted-evidence notes are docs-only and will be bundled
  with this implementation.
- Pre-change `bin/test-fast` exits zero across the maintained repository and
  consumer-smoke matrix.

## Plan

1. Add fail-first live HTTP coverage for resource-bound step-up request
   construction and unchanged Streamable session state.
2. Implement the public helper with redacted, fail-closed challenge validation.
3. Extend the public IO and generated installed-package consumer smokes.
4. Update durable protocol/readiness notes and run focused checks plus full
   repository verification.
5. Commit and push the implementation, then collect the exact-head hosted and
   strict deployment-chain evidence required by the affected package paths.

## Verification

- Focused `McpStreamableHttpClient` tests, including malformed and ambiguous
  challenge rejection.
- Public MCP IO entrypoint test and generated installed-package consumer smoke.
- Affected package analysis and shell/Python validation.
- `bin/verify`.

## Decision Log

- 2026-08-14: Stable MCP `2026-07-28` guidance makes the runtime 403 challenge
  scopes authoritative and requires a step-up request to include their union
  with the scopes from the previous authorization request. The existing client
  preserves session state and accepts a broader replacement grant, but every
  consumer still has to validate the response and rebuild the authorization
  request manually.
- 2026-08-14: The helper will create an authorization request only. It will not
  launch user interaction, exchange or install credentials, or retry the
  original operation, so consumers retain explicit retry bounds and control.

## Handoff

- Pre-change `bin/test-fast` exits zero across the maintained repository and
  consumer-smoke matrix. Fail-first coverage reproduced the missing public
  request builder against a live HTTP 403 response.
- `createStepUpAuthorizationRequest(...)` now rejects non-403, absent,
  ambiguous, wrongly typed, metadata-invalid, scope-invalid, and resource-
  mismatched contexts through a redacted exception. Valid requests preserve
  current and caller-supplied scopes, add authoritative challenge scopes once,
  bind issuer/client/resource to the validated grant, use S256 PKCE by default,
  and leave active client state unchanged.
- The focused client tests, full 178-case Streamable client file, all 14 public
  IO tests, affected package analysis, Bash syntax, 22 generated-source
  boundary tests, 15 verification-script regressions, 20 package publish-policy
  regressions, four public-artifact regressions, and the path-dependency plus
  globally activated client smoke pass. Focused local review found no confirmed
  correctness, security, compatibility, or coverage defect.
- Full `bin/verify` exits zero with formatting unchanged, 114 Rust core tests,
  all 52 FFI tests, 366 Dart core tests, 116 MCP tests, the 289-case MCP/client
  suite, 97 benchmark tests including all 37 live WAMP workloads, the 442-case
  router suite, six remote-auth tests, 13 native follow-ups, every maintained
  consumer smoke, Chrome, and Dart2Wasm green.
- Commit `a27be47e` is published to both maintained `master` branches.
  Exact-head CI `31838314806`, Dart Package Publish Dry Run `31838314825`,
  WAMP Profile Benchmarks `31838314801`, and Router Image dry run
  `31838358184` all pass. CI retains coverage artifact `9233814644`; WAMP
  retains benchmark artifact `9233507415`; Router Image retains preview
  artifact `9233338677` and Docker build records `9233444885` and
  `9233444329`.
- The comprehensive strict deployment-chain audit exits zero with clean
  exact-head CI logs, relevant package evidence, the loaded-image MCP smoke,
  skipped GHCR login, relevant retained native-release evidence, WAMP
  artifacts, and every required package, workflow, registry, and protected-
  branch gate clean. No RC tag was selected.
