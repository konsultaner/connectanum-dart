# Exec Plan: MCP Direct JSON Response Header Session Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Direct JSON MCP requests are lifecycle-free even when a client has an active
Streamable HTTP session. That boundary must cover response headers too: a
direct JSON success or HTTP error that carries `MCP-Session-Id` must not replace
or clear the active Streamable session id or SSE resume cursor. Session-bound
Streamable requests and Streamable `initialize` still own the session lifecycle
and continue to capture MCP session headers.

## Implementation Plan

1. Add a focused regression that initializes a Streamable MCP session, makes
   direct JSON success and HTTP-error calls whose responses include
   `MCP-Session-Id`, and proves the Streamable session remains usable.
2. Guard `McpStreamableHttpClient` response header capture so only
   session-bound requests and Streamable `initialize` capture MCP session
   headers.
3. Extend the neutral generated client-package smoke with direct JSON
   response-session-header coverage.
4. Run focused client tests, the generated client-package smoke,
   `bin/test-fast`, and `bin/verify`.
5. Push the implementation and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Fail-first focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded --plain-name "keeps direct JSON response session headers
  lifecycle-free"` failed because a direct JSON response `MCP-Session-Id`
  replaced the active Streamable session id.
- Focused direct JSON response-header regression passed after the guarded
  capture change.
- Focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded` passed.
- `bash -n bin/common.sh` passed.
- Focused `run_mcp_client_package_smoke` passed after adding the neutral
  generated-smoke response-header probe.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `a426fcf` (`fix: isolate mcp direct json response headers`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25627974549` completed successfully for `a426fcf` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25627974556` completed
  successfully for `a426fcf`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25627974555` completed successfully for
  `a426fcf`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence. The audit still reports the known
  operator-side release-hardening gaps: branch protection/required status
  checks are absent, `.github/workflows/router-image.yml` is not yet visible
  from the default branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- Direct JSON calls do not own Streamable HTTP lifecycle state, so they ignore
  MCP session response headers even when the server sends them accidentally.
- Streamable `initialize` keeps capturing response headers because it establishes
  the active Streamable HTTP session.
- Session-bound Streamable requests keep using the session-aware HTTP error path
  so stale sessions are still cleared on `401`, `403`, and `404`.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Audit findings are the known operator-side
release-hardening gaps.
