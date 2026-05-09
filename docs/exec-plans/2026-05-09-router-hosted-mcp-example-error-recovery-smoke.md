# Exec Plan: Router-Hosted MCP Example Error Recovery Smoke

Status: complete; local verification clean; commit and hosted evidence pending
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can recover from JSON-RPC errors without corrupting direct JSON or initialized
Streamable HTTP MCP session state.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Generated consumer smokes already covered single and batch JSON-RPC error
  isolation. The public example still needed matching proof for operators and
  downstream application developers running the example directly.
- Direct JSON calls must remain lifecycle-free. Initialized Streamable calls
  must keep the same MCP session id while advancing the SSE cursor for
  response-producing operations, including errors.

## Scope

- Extend `packages/connectanum_router/example/router_hosted_mcp.dart` with
  direct JSON error/recovery checks for missing tools, resources, and prompts.
- Add direct JSON batch error isolation with neighboring successful tool/API
  responses and a notification entry that must not produce a response.
- Add initialized Streamable HTTP error/recovery checks for missing tools,
  resources, and prompts.
- Add initialized Streamable HTTP batch error isolation with neighboring
  successful `tools/list` and `prompts/get` responses.
- Keep the same checks running on both public and bearer-protected MCP routes.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke passed on 2026-05-09 with isolated
  `TMPDIR`:
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- Validate expected error identifiers against the full JSON-RPC error object,
  not only `error.message`, because missing resources carry the requested URI
  in structured `error.data.uri`.

## Handoff

Implementation, focused example smoke, fast verification, and full local
verification are clean. Commit, push, and hosted evidence remain pending.
