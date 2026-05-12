# Exec Plan: MCP Consumer Streamable WAMP CORS Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Prove browser-style router-hosted MCP consumers can use Streamable HTTP
`tools/call` requests over CORS for router-provided WAMP API metadata and
pub/sub helpers on both public and bearer-protected MCP routes.

## Scope

- Extend the neutral generated consumer package smoke for public and
  bearer-protected MCP routes.
- Cover Streamable HTTP WAMP API list and describe tool calls over raw
  POST/SSE responses.
- Cover Streamable HTTP pub/sub subscribe, publish, poll, and unsubscribe tool
  calls over raw POST/SSE responses.
- Cover Streamable HTTP MCP tool-result errors for missing WAMP API entries and
  unknown pub/sub handles.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- Native router smoke support must be available locally, or the smoke must skip
  native router startup through the existing package hook path.

## Plan

1. Reuse the raw Streamable HTTP POST/SSE helper path for MCP `tools/call`
   requests.
2. Add raw Streamable CORS checks for WAMP API metadata tool success and
   missing-entry tool-result errors.
3. Add raw Streamable CORS checks for pub/sub subscribe, publish, poll, and
   unsubscribe success plus unknown-handle tool-result errors.
4. Run focused consumer smoke and full local verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after adding Streamable WAMP CORS coverage.
- Full local `bin/verify` passed on 2026-05-13.

## Decision Log

- 2026-05-13: Kept this as smoke harness coverage rather than a router code
  change because the router-hosted MCP endpoint already exposes the WAMP API
  and pub/sub tools; the gap was raw browser-compatible Streamable HTTP CORS
  evidence across public and bearer-protected routes.

## Handoff

Implementation is locally complete with focused consumer smoke and full
`bin/verify` clean. Commit, push, hosted CI, and deployment-chain evidence
remain.
