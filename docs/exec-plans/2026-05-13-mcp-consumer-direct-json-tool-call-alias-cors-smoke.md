# Exec Plan: MCP Consumer Direct JSON Tool-Call Alias CORS Smoke

Status: complete locally; hosted CI and deployment-chain evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Prove browser-style router-hosted MCP consumers can call route-visible tools
through both direct JSON Connectanum tool-call method names over CORS on public
and bearer-protected MCP routes.

## Scope

- Extend the neutral generated consumer package smoke for public and
  bearer-protected MCP routes.
- Cover the plural direct JSON `connectanum.tools.call` alias in addition to
  the singular `connectanum.tool.call` method for a real route-visible WAMP
  procedure.
- Cover a direct JSON batch that mixes `connectanum.tool.call` and
  `connectanum.tools.call`, proving both method names are usable without
  entering the Streamable HTTP session lifecycle.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-batch-cors-smoke.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-direct-json-tool-call-alias-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- Native router smoke support must be available locally, or the smoke must skip
  native router startup through the existing package hook path.

## Plan

1. Add a raw direct JSON CORS assertion for `connectanum.tools.call` on the
   same route-visible WAMP procedure already used for `connectanum.tool.call`.
2. Add a raw direct JSON batch assertion that calls the same procedure through
   both singular and plural Connectanum tool-call method names.
3. Run focused consumer smoke and full local verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after adding direct JSON tool-call alias CORS coverage.
- Full local `bin/verify` passed on 2026-05-13.
- Implementation commit and hosted CI/deployment-chain evidence are pending.

## Decision Log

- 2026-05-13: Chose this slice because raw direct JSON CORS coverage already
  proved `connectanum.tool.call`, WAMP API metadata, resources, prompts, and
  pub/sub, but browser-style consumer evidence had not yet pinned the supported
  plural `connectanum.tools.call` alias on public and bearer-protected routes.

## Handoff

Implementation is complete locally. Hosted CI, hosted log scan, and
deployment-chain audit evidence still need to be captured after the
implementation commit is pushed.
