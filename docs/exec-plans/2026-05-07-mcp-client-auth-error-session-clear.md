# Exec Plan: MCP Client Auth Error Session Clear

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Make the public Streamable HTTP MCP client recover cleanly when an active
session becomes unusable because the server rejects the session with an auth or
authorization HTTP error.

## Scope

- In scope:
  - Clear cached Streamable HTTP session state on session-scoped HTTP 401 and
    403 responses, matching the existing stale-session 404 behavior.
  - Add focused `McpStreamableHttpClient` unit coverage for POST, GET/SSE, and
    DELETE session failures.
  - Extend the generated router-hosted consumer package smoke so rotated and
    revoked bearer sessions prove rejected POST, GET/SSE, and DELETE calls each
    clear stale session state.
- Out of scope:
  - Changing router auth policy or token issuance semantics.
  - Changing direct JSON JSON-RPC error handling.
  - Adding private downstream application references.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-participant-meta-smoke.md`
- `docs/exec-plans/2026-05-07-mcp-client-auth-error-session-clear.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Existing docs-only hosted-evidence updates for the participant-meta smoke
  remain uncommitted and should be bundled with this implementation commit.

## Plan

1. Clear client session state on HTTP 401/403/404 session-scoped failures.
2. Extend the client unit test fake endpoint to cover 401, 403, and 404 across
   POST, GET/SSE, and DELETE.
3. Extend the generated router-hosted consumer smoke to assert active protected
   sessions clear stale state after token rotation and revocation rejections.
4. Run focused client tests, generated consumer smoke, `bin/test-fast`, and
   `bin/verify`.
5. Commit implementation plus state updates, push both remotes, and inspect
   hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --chain-stack-traces`,
  `git diff --check`, and
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted GitHub evidence for `951ed89` is clean: `CI` run `25485027762`
  completed successfully with `Fast Checks` and `Full Verify`, both with zero
  annotations; Dart Package Publish Dry Run run `25485027779` completed
  successfully and covers the checked-out head; WAMP Profile Benchmarks run
  `25485027860` completed successfully.
- The deployment-chain audit
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed against `951ed89`; the strict variant correctly failed only on the
  known operator-owned deployment-chain gaps: `add-router` is unprotected, the
  router image workflow is not discoverable from the default branch, and the
  router container package is not visible.

## Decision Log

- 2026-05-07: Chose this slice because auth/session correctness is the current
  MCP readiness priority, and a consumer application should not retain a stale
  Streamable HTTP session id after the server rejects that session for auth or
  authorization reasons.

## Handoff

Complete with local and hosted evidence. The implementation was committed as
`951ed89` and pushed to both remotes. Keep the hosted-evidence docs update
uncommitted until it can be bundled with the next code or config change.
