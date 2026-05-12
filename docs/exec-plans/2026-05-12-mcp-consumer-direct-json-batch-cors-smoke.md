# Exec Plan: MCP Consumer Direct JSON Batch CORS Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can use batched direct JSON-RPC
requests over CORS without entering the Streamable HTTP session lifecycle.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes return CORS-readable JSON-RPC batch responses.
- Cover batched direct JSON catalog, API-description, resource, prompt, and
  pub/sub calls through raw browser-style requests.
- Keep asserting that direct JSON CORS batches do not create or mutate
  Streamable HTTP session state.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding raw direct JSON batch CORS coverage.
- Full local `bin/verify` passed on 2026-05-12.

## Handoff

Implementation is complete locally. Commit, push, hosted CI, and
deployment-chain audit evidence are pending.
