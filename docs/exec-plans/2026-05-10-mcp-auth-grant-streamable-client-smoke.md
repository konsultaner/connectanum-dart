# Exec Plan: MCP Auth Grant Streamable Client Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Router-hosted MCP consumers can already issue HTTP auth bridge grants and pass
bearer tokens into `McpStreamableHttpClient.withBearerToken`. That still leaves
consumer applications manually copying grant fields into MCP clients and
skipping token-type validation. Protected Streamable HTTP sessions should accept
the auth bridge grant directly so consumers can hand off the bridge response to
the MCP transport without private project assumptions.

This slice adds an auth-grant constructor for the Streamable HTTP client, rejects
unsupported grant token types before opening a session, and tightens refresh and
revoke token validation on the HTTP auth bridge client.

## Implementation Plan

1. Add `McpStreamableHttpClient.withAuthGrant` for `ConnectanumHttpAuthGrant`
   values and keep the Authorization header owned by the grant handoff.
2. Reject non-Bearer grants locally and reuse existing bearer-token trimming and
   empty-token validation.
3. Reject empty refresh and revoke tokens in `ConnectanumHttpAuthClient` before
   sending bridge requests.
4. Extend focused client tests, the public IO entrypoint smoke, and the neutral
   generated consumer package smoke so consumer code proves the grant handoff
   compiles and runs.
5. Run focused tests, generated consumer smoke, `bin/test-fast`, and
   `bin/verify`.
6. Push the implementation and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/http_auth_client_test.dart
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded` passed after adding auth-grant handoff and token validation.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart
  -r expanded --plain-name "IO entrypoint re-exports HTTP auth helpers for MCP
  sessions"` passed after switching the IO smoke to `withAuthGrant`.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed after switching the neutral generated consumer smoke to
  `withAuthGrant`.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `2ace2a8` (`feat: wire mcp auth grants into streamable clients`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25632291307` completed successfully for `2ace2a8` with
  `Fast Checks` (4m27s) and `Full Verify` (6m17s) green, and the hosted CI log
  scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25632291310` completed
  successfully for `2ace2a8` and covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25632291313` completed successfully
  for `2ace2a8` with `Linux WAMP profile gates` green (7m53s).
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean
  hosted CI logs, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- `withAuthGrant` only accepts Bearer grants because the current router-hosted
  MCP HTTP authorization path is bearer-token based.
- The grant constructor applies caller headers first and then writes
  `Authorization`, matching `withBearerToken` so stale caller Authorization
  headers cannot override the grant.
- Refresh and revoke tokens are trimmed and rejected when empty so malformed
  bridge lifecycle calls fail locally.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side
release-hardening work.
