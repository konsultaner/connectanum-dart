# Exec Plan: MCP Consumer Single Error Smoke

Status: complete locally; hosted CI evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that router-hosted MCP
single-request JSON-RPC errors surface through public client APIs as typed,
recoverable `McpJsonRpcException` values for both lifecycle-free direct JSON
and initialized Streamable HTTP clients.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use public consumer-facing `McpStreamableHttpClient` direct JSON and
    Streamable HTTP helper APIs.
  - Assert direct JSON missing-tool calls throw `McpJsonRpcException` with the
    expected id, method, and error body while leaving active Streamable session
    state unchanged.
  - Assert initialized Streamable missing-tool calls throw
    `McpJsonRpcException`, keep the MCP session id stable, advance the SSE
    cursor, and recover with a follow-up tool-list request.
  - Exercise both public and bearer-protected router-hosted MCP endpoints
    through the generated consumer package smoke.
- Out of scope:
  - Changing router error semantics.
  - Changing public client APIs.
  - Adding private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-batch-error-smoke.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-single-error-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Existing docs-only hosted-evidence updates for the batch error smoke remain
  uncommitted and should be bundled with this implementation commit.

## Plan

1. Add direct JSON single-error assertions to the generated consumer package
   smoke.
2. Add initialized Streamable HTTP single-error and recovery assertions.
3. Run focused smoke and formatting checks.
4. Run `bin/verify`, commit implementation plus state updates, push both
   remotes, and inspect hosted CI evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`,
  `git diff --check`, and
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted CI evidence is pending until this implementation is committed and
  pushed.

## Decision Log

- 2026-05-07: Chose this slice because prior consumer package smoke coverage
  proved successful direct JSON, Streamable, batch, auth, and session
  behavior, but did not prove that single JSON-RPC errors surface through
  public consumer APIs as typed exceptions while preserving recoverable
  session state.

## Handoff

Complete locally. Hosted CI and deployment-chain audit evidence should be
captured after the implementation commit is pushed.
