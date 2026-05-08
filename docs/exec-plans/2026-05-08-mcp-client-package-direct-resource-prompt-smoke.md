# Exec Plan: MCP Client Package Direct Resource Prompt Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated client-only consumer package that downstream
applications can use direct JSON resource and prompt helpers for the same
standard MCP context surfaces already covered by the Streamable helper path,
without requiring router or private project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
  - Exercise direct JSON `McpStreamableHttpClient.readResource`,
    `McpStreamableHttpClient.listResourceTemplates`, and
    `McpStreamableHttpClient.listPrompts` against the generated mock endpoint.
  - Keep existing direct JSON `resources/list` and `prompts/get` coverage.
  - Assert every direct resource/prompt helper omits `MCP-Session-Id` even
    after a Streamable session is initialized.
  - Bundle existing hosted-evidence docs updates from the previous MCP active
    resource/prompt detail auth smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Package publishing policy changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-client-package-direct-resource-prompt-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP active
  resource/prompt detail auth smoke plan.

## Preconditions

- Latest pushed implementation commit `6797337` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Add direct JSON resource read, resource template list, and prompt list calls
   to the generated client-only consumer package.
2. Extend the direct-helper no-session-header assertion so it covers
   `resources/list`, `resources/read`, `resources/templates/list`,
   `prompts/list`, and `prompts/get` together.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh bin/test-fast bin/test-all` passed on
  2026-05-08.
- Focused `git diff --check` passed on 2026-05-08.
- Focused generated client-only consumer smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit and hosted evidence are pending.

## Decision Log

- 2026-05-08: Chose this slice because the standalone consumer package smoke
  already covered Streamable resource reads/templates and direct JSON
  `resources/list`/`prompts/get`, but did not prove the full direct JSON
  resource/prompt helper surface without session headers.

## Handoff

Implementation passed focused syntax/generated client-only smoke checks,
post-change `bin/test-fast`, and full local `bin/verify` with isolated
`TMPDIR`. Commit and hosted evidence are pending.
