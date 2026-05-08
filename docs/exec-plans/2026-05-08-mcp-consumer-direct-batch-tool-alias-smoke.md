# Exec Plan: MCP Consumer Direct Batch Tool Alias Smoke

Status: complete locally; full local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can use the plural `connectanum.tools.call` direct JSON-RPC alias
inside JSON-RPC batches against a real router-provided MCP endpoint, both before
and after Streamable HTTP session initialization, without changing Streamable
session state.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add successful `connectanum.tools.call` batch entries to the direct JSON
    batch smoke.
  - Add batch error-isolation coverage proving the plural alias still succeeds
    when a sibling batch entry returns a JSON-RPC error.
  - Keep the existing direct JSON batch session/cursor invariants.
  - Bundle existing docs-only hosted-evidence updates from the previous MCP
    consumer direct tool API smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Package publishing policy changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-direct-tool-api-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-direct-batch-tool-alias-smoke.md`

## Preconditions

- Latest pushed implementation commit `a27172e` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Add plural `connectanum.tools.call` success assertions to direct JSON batch
   coverage.
2. Add plural alias success coverage to direct JSON batch error-isolation.
3. Run focused syntax/generated consumer smoke checks, post-change
   `bin/test-fast`, and full `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh bin/test-fast bin/test-all` and
  `git diff --check` passed on 2026-05-08.
- Focused generated router-hosted consumer package smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit and hosted evidence are pending.

## Decision Log

- 2026-05-08: Chose this slice because direct single-call coverage now proves
  the singular helper, plural alias, and dotted method against a real
  router-hosted MCP endpoint, while JSON-RPC batch coverage still only proves
  the singular helper and dotted tool method shapes.

## Handoff

Implementation passed focused syntax/generated consumer smoke checks,
post-change `bin/test-fast`, and full local `bin/verify`; commit and hosted
evidence are pending.
