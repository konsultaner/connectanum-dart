# Exec Plan: MCP Direct JSON HTTP-Error Session Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Direct JSON MCP requests are intentionally lifecycle-free: they omit
`MCP-Session-Id` even when a consumer also has an initialized Streamable HTTP
session. HTTP `401`, `403`, and `404` failures from those lifecycle-free direct
requests should surface as typed HTTP exceptions without clearing the active
Streamable session id or SSE resume cursor. Session-bound Streamable requests
and Streamable `initialize` failures must still clear stale session state where
appropriate.

## Implementation Plan

1. Add a focused client regression that opens a Streamable session, forces
   direct JSON HTTP `401`, `403`, and `404` failures without session headers,
   and proves the Streamable session remains usable.
2. Adjust `McpStreamableHttpClient` HTTP-error handling so only session-bound
   POSTs, plus the Streamable `initialize` lifecycle request, clear cached MCP
   session state on session-status failures.
3. Extend the generated neutral client-package smoke with the same
   lifecycle-free direct HTTP-error behavior.
4. Run focused package tests, the generated client-package smoke,
   `bin/test-fast`, and `bin/verify`.
5. Push the implementation and gather hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Fail-first focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded --plain-name "keeps active Streamable session state after direct JSON
  HTTP failures"` failed because direct JSON `401` cleared `sessionId`.
- `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
  completed cleanly.
- `bash -n bin/common.sh` passed.
- Focused direct HTTP-error regression passed.
- Focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart` passed.
- Focused `run_mcp_client_package_smoke` passed.
- Focused `run_mcp_consumer_package_smoke` passed after aligning protected
  direct JSON auth failures with the lifecycle-free session contract.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `86b94a5` (`fix: preserve mcp direct json session state`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25626971782` completed successfully for `86b94a5` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25626971768` completed
  successfully for `86b94a5`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25626971771` completed successfully for
  `86b94a5`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence. The audit still reports the known
  operator-side release-hardening gaps: branch protection/required status
  checks are absent, `.github/workflows/router-image.yml` is not yet visible
  from the default branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- Keep direct JSON HTTP failures lifecycle-free by using the non-session HTTP
  error path when `includeSession` is false.
- Preserve stale-session cleanup for session-bound POSTs and Streamable
  `initialize`, because those requests define or depend on the Streamable MCP
  session lifecycle.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Audit findings are the known operator-side
release-hardening gaps.
