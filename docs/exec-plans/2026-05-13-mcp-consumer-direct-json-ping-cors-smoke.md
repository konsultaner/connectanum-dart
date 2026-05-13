# Exec Plan: MCP Consumer Direct JSON Ping CORS Smoke

Status: complete; local verification clean, hosted evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Prove browser-style router-hosted MCP consumers can probe public and
bearer-protected MCP routes with `ping` over both lifecycle-free direct JSON
and stateful Streamable HTTP CORS paths.

## Scope

- Add direct JSON router support for `ping` without requiring Streamable HTTP
  session initialization.
- Extend the generated neutral consumer package smoke so public and protected
  MCP routes validate direct JSON `ping`, direct JSON batch `ping`,
  Streamable POST/SSE `ping`, and Streamable batch `ping`.
- Keep private downstream application names and local paths out of checked-in
  docs and generated package metadata.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-direct-json-ping-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- The previous direct JSON tool-call alias CORS smoke remains complete and
  hosted clean at branch checkpoint `5e9647b`.

## Plan

1. Add `ping` to the router direct JSON method classifier and dispatcher.
2. Extend the generated consumer package CORS smoke to verify direct JSON and
   Streamable `ping` on public and bearer-protected routes.
3. Run the focused generated consumer package smoke, then full local
   verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- First focused generated consumer package smoke failed because direct JSON
  `ping` was still routed through the initialized MCP server path instead of
  the lifecycle-free direct JSON dispatcher.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after adding the router direct JSON `ping` classifier
  and dispatcher support.
- Full local `bin/verify` passed on 2026-05-13.
- The local implementation commit contains this change. Hosted CI and
  deployment-chain evidence are pending.

## Decision Log

- 2026-05-13: Chose this slice because raw direct JSON CORS coverage already
  proved catalog, tool calls, resources, prompts, WAMP metadata, pub/sub, and
  error paths, but endpoint liveness probing via `ping` was only covered by
  client helper tests and initialized Streamable semantics.

## Handoff

Implementation is complete locally. Focused local smoke and full local
verification are clean; hosted deployment-chain evidence remains pending.
