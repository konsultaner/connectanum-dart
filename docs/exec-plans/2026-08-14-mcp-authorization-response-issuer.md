# Exec Plan: MCP Authorization Response Issuer

Status: active; implementation and local verification complete; hosted evidence pending
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Make the public MCP OAuth authorization flow enforce the stable MCP 2026-07-28
authorization-response issuer contract before accepting an authorization code
or surfacing authorization-server callback errors.

## Scope

- In scope:
  - Parse and persist the authorization-server metadata flag that advertises
    RFC 9207 authorization-response issuer support.
  - Preserve the validated issuer identifier for exact callback comparison.
  - Validate optional, required, mismatched, and duplicate `iss` callback
    parameters before consuming code or error response data.
  - Exercise the public IO/package boundary with an issuer-aware loopback OAuth
    flow and focused client regressions.
  - Record the stable protocol evidence that determines the behavior.
- Out of scope:
  - OIDC ID-token issuer validation or JWT processing.
  - Changes to authorization-server behavior outside the consumer client.
  - Other optional MCP 2026 extensions.

## Files Expected To Change

- OAuth authorization discovery, callback handling, and tests in
  `packages/connectanum_client`.
- Public IO/package OAuth smoke coverage in `packages/connectanum_mcp` and the
  generated consumer-smoke tooling.
- Stable MCP authorization research, package changelogs, roadmap readiness,
  and project-state evidence.

## Preconditions

- Commit `a92c301b` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The only pre-existing working-tree changes are the completed completion-plan
  and project-state hosted-evidence notes, which will be bundled here.
- The pre-change `bin/test-fast` gate must exit zero before implementation.

## Plan

1. Add fail-first metadata and callback tests for the RFC 9207 matrix.
2. Implement strict metadata parsing plus exact, pre-consumption issuer
   validation for success and error callbacks.
3. Extend the neutral IO/package and generated consumer smoke flow.
4. Update durable protocol and milestone notes, then run focused checks and
   full repository verification.
5. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence required by the affected package paths.

## Verification

- Focused authorization discovery and OAuth callback tests.
- Public IO entrypoint and generated installed-package consumer smoke.
- Affected package analysis and shell/Python validation.
- `bin/verify`.

## Decision Log

- 2026-08-14: The stable MCP 2026-07-28 authorization specification requires
  clients to validate the RFC 9207 `iss` callback parameter against the issuer
  recorded from authorization-server metadata. An advertised issuer parameter
  must be present; a present parameter must match even when not advertised.
- 2026-08-14: Comparison will use the exact validated metadata identifier,
  without URI normalization. Issuer failures will be raised before code or
  OAuth error handling and will not attach attacker-controlled callback data.

## Handoff

- The pre-change `bin/test-fast` gate exits zero, including 366 Dart core
  tests, 115 MCP tests, the 283-case MCP/client suite, 97 benchmark tests with
  all 37 live WAMP workloads, and maintained consumer smokes.
- Fail-first discovery and callback tests captured the missing public metadata
  and issuer-validation contract. Focused client VM tests and the public IO
  OAuth lifecycle test pass after implementation.
- The generated path-dependency and globally activated client smoke passes with
  advertised issuer support, persisted authorization metadata, and a matching
  loopback callback. Affected package analysis, verification-script tests,
  package dry-run policy tests, and shell validation pass.
- Full `bin/verify` exits zero with formatting unchanged, 114 Rust core tests,
  all 52 FFI tests, 366 Dart core tests, 115 MCP tests, the 287-case MCP/client
  suite, 97 benchmark tests including all 37 live WAMP workloads, the 442-case
  router suite, 6 remote-auth tests, 13 native follow-ups, every consumer
  smoke, Chrome, and Dart2Wasm green.
- Commit/push, exact-head hosted workflows, and the strict deployment-chain
  audit remain.
