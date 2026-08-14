# Exec Plan: MCP Client Metadata Refresh Grant

Status: active; implementation and local verification complete; hosted evidence pending
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Make the preferred public Client ID Metadata Document path truthfully advertise
the refresh-token grant already supported by the MCP OAuth client, while
letting consumers explicitly opt out when they do not want refresh credentials.

## Scope

- In scope:
  - Advertise `refresh_token` alongside `authorization_code` by default in
    public Client ID Metadata Documents.
  - Expose immutable public state describing whether refresh credentials are
    requested.
  - Keep an explicit opt-out that publishes only `authorization_code`.
  - Prove the default and opt-out shapes through focused and public IO/package
    boundary coverage.
  - Record the stable MCP refresh-token guidance that determines the behavior.
- Out of scope:
  - Automatically requesting `offline_access` or changing consumer-selected
    scopes.
  - Changing token refresh, persistence, or revocation behavior.
  - Changing the existing Dynamic Client Registration request shape.

## Files Expected To Change

- Client metadata implementation and tests in `packages/connectanum_client`.
- Public IO/package smoke coverage in `packages/connectanum_mcp` and generated
  consumer-smoke tooling.
- Stable MCP authorization research, package changelogs, roadmap readiness,
  and project-state evidence.

## Preconditions

- Commit `89d5d8f5` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The only pre-existing working-tree changes are the completed authorization-
  response issuer plan and project-state hosted-evidence notes; they will be
  bundled with this implementation.
- The pre-change `bin/test-fast` gate must exit zero before implementation.

## Plan

1. Add fail-first metadata-document tests for default refresh advertisement and
   explicit opt-out.
2. Add a public immutable refresh-request flag and serialize the matching
   `grant_types` list.
3. Extend the neutral public IO and generated installed-package smoke contract.
4. Update durable protocol/readiness notes and run focused checks plus full
   repository verification.
5. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence required by the affected package paths.

## Verification

- Focused Client ID Metadata Document tests.
- Public IO entrypoint and generated installed-package consumer smoke.
- Affected package analysis and shell/Python validation.
- `bin/verify`.

## Decision Log

- 2026-08-14: Stable MCP refresh-token guidance says clients that desire refresh
  tokens should include `refresh_token` in their `grant_types` client metadata.
  The public client already exchanges, persists, rotates, and revokes refresh
  grants, and the fallback Dynamic Client Registration path already advertises
  this grant, while the preferred metadata-document path does not.
- 2026-08-14: Refresh advertisement will default on for parity with the shipped
  client and fallback registration path, with an explicit opt-out. The library
  will not add `offline_access` automatically because scopes remain a consumer
  least-privilege decision.

## Handoff

- The pre-change `bin/test-fast` gate exits zero, including 366 Dart core
  tests, 115 MCP tests, the 287-case MCP/client suite, 97 benchmark tests with
  all 37 live WAMP workloads, and maintained consumer/router package smokes.
- Fail-first coverage captured the missing constructor option and public state.
  Focused client and public IO tests pass with the default and opt-out metadata
  shapes, including immutable nested grant metadata.
- Affected package analysis, shell validation, all 15 verification-script
  regressions, and all 20 package publish-policy regressions pass. The generated
  path-dependency and globally activated client smoke passes with exact
  `authorization_code` plus `refresh_token` metadata.
- Full `bin/verify` exits zero with formatting unchanged, 114 Rust core tests,
  all 52 FFI tests, 366 Dart core tests, 116 MCP tests, the 288-case MCP/client
  suite, 97 benchmark tests including all 37 live WAMP workloads, the 442-case
  router suite, 6 remote-auth tests, 13 native follow-ups, every consumer
  smoke, Chrome, and Dart2Wasm green. Focused local review found no unresolved
  correctness, compatibility, security, or coverage issue.
- Publication, exact-head hosted workflows, and the strict deployment-chain
  audit remain.
