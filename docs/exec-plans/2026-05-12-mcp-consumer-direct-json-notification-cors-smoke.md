# Exec Plan: MCP Consumer Direct JSON Notification CORS Smoke

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can send notification-only
direct JSON-RPC requests over CORS without entering the Streamable HTTP session
lifecycle or receiving a JSON-RPC response body.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes return CORS-readable `202 Accepted` responses for
  single direct JSON notifications and notification-only direct JSON batches.
- Keep asserting that direct JSON notification-only requests do not create
  `MCP-Session-Id` state and expose the standard MCP headers for browser
  callers.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding raw direct JSON notification-only CORS
  coverage.
- Full local `bin/verify` passed on 2026-05-12.
- Hosted CI and deployment-chain audit pending after commit/push.

## Handoff

Implementation is locally verified. Commit/push, hosted CI, and
deployment-chain evidence are pending.
