# Exec Plan: MCP Controlled Request Header Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Consumer applications can attach constructor-wide and per-call headers to MCP
HTTP requests for auth, tracing, and routing metadata. The MCP transport also
has client-owned request headers: `Accept`, `MCP-Protocol-Version`,
`MCP-Session-Id`, and `Last-Event-ID`. Those headers define direct JSON versus
Streamable HTTP semantics, session ownership, and SSE resume state, so caller
header maps must not override them or leak stale session state into lifecycle
boundaries.

This slice keeps those controlled headers owned by
`McpStreamableHttpClient` and proves the behavior through focused tests and the
neutral generated client-package smoke.

## Implementation Plan

1. Filter controlled MCP request headers from constructor defaults and per-call
   header maps before applying client-owned transport/session headers.
2. Add focused client coverage for initialize, direct JSON, Streamable POST, and
   poll calls where caller-supplied controlled headers must be ignored while
   ordinary consumer metadata still passes through.
3. Extend the neutral generated client-package smoke with direct JSON and poll
   probes that simulate stale caller MCP session/cursor headers.
4. Run focused client tests, the generated client-package smoke,
   `bin/test-fast`, and `bin/verify`.
5. Push the implementation and collect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded --plain-name "owns MCP protocol and session headers despite caller
  headers"` passed after the request-header ownership change.
- Full focused `dart test
  packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
  expanded` passed.
- `bash -n bin/common.sh` passed.
- Focused `run_mcp_client_package_smoke` passed after adding the neutral
  generated-smoke controlled-request-header probes.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `1ee7109` (`fix: keep mcp protocol headers client-owned`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25630084040` completed successfully for `1ee7109` with
  `Fast Checks` and `Full Verify` green, and the hosted CI log scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25630084020` completed
  successfully for `1ee7109` and covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25630084014` completed successfully
  for `1ee7109`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI, clean
  hosted CI logs, and clean Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- Controlled request headers are filtered case-insensitively from consumer
  header maps before the client applies its own values. This preserves public
  header extensibility for auth/trace metadata while keeping MCP protocol,
  session, and resume semantics deterministic.
- Direct JSON requests remain lifecycle-free even when caller headers include
  stale `MCP-Session-Id` or `Last-Event-ID` values.
- The generated poll smoke temporarily clears and restores `lastEventId` so the
  stale caller cursor probe does not perturb later Streamable lifecycle checks.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side
release-hardening work.
