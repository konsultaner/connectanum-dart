# Exec Plan: MCP Consumer CORS POST Body Error Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers receive CORS-readable raw POST
body negotiation errors without accidental session creation, and that the same
errors preserve an active Streamable HTTP session after initialization.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes reject unsupported POST `Content-Type` values
  with CORS-readable JSON errors.
- Extend the same smoke so malformed JSON POST bodies return CORS-readable
  JSON-RPC parse errors.
- Cover both lifecycle-free requests and active Streamable HTTP sessions, with
  a post-error `tools/list` recovery check for initialized sessions.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding the raw POST body error coverage.
- Full local `bin/verify` passed on 2026-05-12.

## Handoff

Implementation is complete locally. Commit, push, hosted CI, and
deployment-chain audit evidence are pending.
