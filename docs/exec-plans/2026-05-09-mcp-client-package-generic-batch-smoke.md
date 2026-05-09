# Exec Plan: MCP Client Package Generic Batch Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the generated client-only consumer package smoke prove that a downstream
application can use the public `connectanum_mcp` IO client generic JSON-RPC
and batch APIs without relying on router-private helpers.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The generated client-only smoke already covers public typed helpers,
  direct JSON helper calls, WAMP meta/pub-sub helpers, and Streamable HTTP
  lifecycle behavior against a neutral fake endpoint.
- The remaining package-boundary gap was proving `McpStreamableHttpClient`
  generic `request(...)` and `postBatch(...)` calls from a generated consumer
  package shape.

## Scope

- Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
- Add generic direct JSON `request(...)` coverage for
  `connectanum.tools.list` and `connectanum.tool.call` without Streamable
  session headers.
- Add generic direct JSON `postBatch(...)` coverage for tool listing, tool
  calls, and dotted tool-name calls without Streamable session headers.
- Add Streamable `postBatch(...)` coverage for `ping` and `tools/list` while
  preserving the active Streamable session and SSE cursor state.
- Extend the neutral fake MCP endpoint with minimal batch handling and `ping`
  responses needed by the package smoke.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused generated client-only consumer package smoke passed on 2026-05-09
  with isolated `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Hosted GitHub `CI` run `25599395146` for `e26bf1c` completed successfully
  on 2026-05-09 with `Fast Checks` and `Full Verify` green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence. The latest relevant
  `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
  it is still relevant because no publish-sensitive paths changed since that
  run.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- Keep this as generated client-only smoke coverage instead of router
  integration coverage because the risk is consumer applications using the
  public IO client APIs directly from a normal package layout.

## Handoff

Implementation, local verification, push, and hosted CI/deployment-chain
evidence are complete. Remaining strict audit findings are operator-side
release gaps, not regressions from this smoke-test change.
