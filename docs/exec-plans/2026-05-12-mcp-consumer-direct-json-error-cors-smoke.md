# Exec Plan: MCP Consumer Direct JSON Error CORS Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can observe direct JSON-RPC
error responses over CORS across tool calls, resources, prompts, WAMP API
metadata, and pub/sub helpers without entering the Streamable HTTP session
lifecycle.

## Scope

- Extend the neutral generated consumer package smoke for public and
  bearer-protected MCP routes.
- Cover direct JSON JSON-RPC errors for missing tools, resources, and prompts.
- Cover direct JSON MCP tool-result errors for missing WAMP API entries and
  unknown pub/sub handles.
- Cover mixed direct JSON batches that combine successful responses,
  JSON-RPC errors, MCP tool-result errors, and a notification.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-12-mcp-consumer-direct-json-error-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- Native router smoke support must be available locally, or the smoke must skip
  native router startup through the existing package hook path.

## Plan

1. Add raw direct JSON CORS checks for single request error payloads and MCP
   tool-result errors.
2. Add raw direct JSON CORS checks for mixed error batches and recovery
   responses.
3. Run focused consumer smoke and full local verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding direct JSON error CORS coverage.
- Full local `bin/verify` passed on 2026-05-12.

## Decision Log

- 2026-05-12: Kept this as smoke harness coverage rather than a router code
  change because the existing direct JSON endpoints already return the correct
  error classes; the gap was downstream browser-consumer evidence across
  public and bearer-protected routes.

## Handoff

Implementation is locally complete with focused consumer smoke and full
`bin/verify` clean. Commit, push, hosted CI, and deployment-chain evidence
remain.
