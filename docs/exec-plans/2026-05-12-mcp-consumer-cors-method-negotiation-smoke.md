# Exec Plan: MCP Consumer CORS Method Negotiation Smoke

Status: implementation complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can negotiate Streamable HTTP
methods through CORS and can read method/`Accept` negotiation failures without
creating MCP session state.

## Scope

- Extend the neutral generated consumer package smoke so MCP CORS preflight is
  checked for `POST`, `GET`, and `DELETE`, not only the first direct JSON POST
  path.
- Add raw public and bearer-protected CORS checks for unsupported HTTP methods
  and invalid `Accept` headers, asserting readable JSON errors, `Allow` header
  coverage, and no accidental Streamable session state.
- Keep the existing disallowed-origin and secure missing-bearer checks intact.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after the implementation.
- Full local `bin/verify` passed on 2026-05-12.

## Handoff

Implementation and local verification are complete. Hosted CI and
deployment-chain evidence are pending until the implementation commit is pushed.
