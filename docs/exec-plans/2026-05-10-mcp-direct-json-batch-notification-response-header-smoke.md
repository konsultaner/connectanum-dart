# Exec Plan: MCP Direct JSON Batch And Notification Response Header Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Direct JSON MCP requests are lifecycle-free even when the same client also owns
an active Streamable HTTP session. The previous response-header fix covered
direct JSON success and HTTP-error responses. Downstream agents can also use
JSON-RPC batches and notification-only calls, so those response shapes must be
covered as well: a direct JSON batch response or accepted notification response
that carries `MCP-Session-Id` must not replace or clear the active Streamable
session id or SSE resume cursor.

## Implementation Plan

1. Extend the focused Streamable HTTP client regression with direct JSON batch,
   direct notification, and notification-only batch responses that inject
   `MCP-Session-Id` response headers while an active Streamable session exists.
2. Teach the fake MCP endpoints used by tests and generated smokes to attach
   test response-session headers to accepted no-body responses, not just JSON
   responses.
3. Extend the neutral generated client-package smoke with batch and notification
   response-header probes that prove consumer applications can use direct JSON
   calls without inheriting private session lifecycle assumptions.
4. Run focused client tests, the generated client-package smoke,
   `bin/test-fast`, and `bin/verify`.
5. Push the implementation and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded --plain-name "keeps direct JSON response session headers
  lifecycle-free"` passed after adding batch and notification response-header
  probes.
- Full focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded` passed.
- `bash -n bin/common.sh` passed.
- Focused `run_mcp_client_package_smoke` passed after adding the neutral
  generated-smoke batch and notification response-header probes.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `72b6240` (`test: cover mcp direct json response header variants`)
  was pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25628970062` completed successfully for `72b6240` with
  `Fast Checks` and `Full Verify` green, and the hosted CI log scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25628970072` completed
  successfully for `72b6240` and covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25628970064` completed successfully
  for `72b6240`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean
  hosted CI logs, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- No client behavior change was needed for this slice because response-header
  capture is already restricted to Streamable lifecycle owners. This slice makes
  that contract explicit for direct JSON batches, direct single notifications,
  and notification-only batches.
- Accepted no-body fake responses now honor the smoke-only
  `x-test-response-session-id` header so tests can prove the lifecycle boundary
  even when the HTTP response has no JSON body.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side
release-hardening work.
