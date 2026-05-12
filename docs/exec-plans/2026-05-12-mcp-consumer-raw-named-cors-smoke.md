# Exec Plan: MCP Consumer Raw Named CORS Smoke

Status: implementation complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Extend the neutral consumer package smoke so a browser-like application or
agent can prove router-hosted MCP access without SDK-only assumptions. Cover
raw direct JSON tool/meta/pubsub calls with CORS response metadata, and raw
Streamable HTTP named method calls that require public `Mcp-Name` and
`Mcp-Param-*` headers.

## Scope

- Keep all checked-in examples and state neutral; use consumer/downstream
  wording only.
- Extend the generated consumer smoke in `bin/common.sh`.
- Cover both public and bearer-protected router-hosted MCP endpoints.
- Avoid product-code churn unless the smoke exposes an implementation bug.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- Focused `bash -n bin/common.sh` passed on 2026-05-12.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12.
- Post-change `bin/test-fast` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.

## Plan

1. Add raw direct JSON CORS assertions for `connectanum.tools.list`,
   `connectanum.tool.call`, `connectanum.api.list`, and pub/sub
   subscribe/publish/poll/unsubscribe.
2. Add raw Streamable HTTP POST/SSE assertions for `tools/call`,
   `resources/read`, and `prompts/get`.
3. Assert CORS preflight allows the concrete public MCP parameter headers used
   by the raw Streamable tool call.
4. Run focused smoke, fast regression, and full verification before handoff.

## Handoff

Implementation and local verification are complete. Hosted CI and
deployment-chain evidence are pending until the implementation commit is pushed.
