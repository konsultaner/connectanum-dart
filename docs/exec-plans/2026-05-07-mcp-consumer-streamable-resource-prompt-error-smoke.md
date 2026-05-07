# Exec Plan: MCP Consumer Streamable Resource And Prompt Error Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that initialized
Streamable HTTP MCP sessions report standard missing resource and missing
prompt errors correctly, keep the session usable, and recover through normal
resource and prompt list calls.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Exercise `McpStreamableHttpClient.readResource(...)` and `getPrompt(...)`
    through an initialized Streamable MCP session.
  - Assert missing `resources/read` and `prompts/get` calls throw typed
    `McpJsonRpcException` values with the expected JSON-RPC id and method.
  - Assert missing resource/prompt errors keep the Streamable session id stable
    and advance the SSE cursor.
  - Prove recovery with `resources/list` and `prompts/list` over the same
    Streamable session.
  - Bundle existing hosted-evidence docs updates from the previous MCP
    resource/prompt error smoke checkpoint.
- Out of scope:
  - Router protocol behavior changes.
  - New public API methods.
  - Private downstream application references.
  - Documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-streamable-resource-prompt-error-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP
  resource/prompt error smoke plan.

## Preconditions

- Latest pushed implementation commit `89da29d` has clean hosted CI evidence.
- The default system temp native runtime lock was previously held by an
  existing long-lived router process outside this task, so local validation
  that starts a native runtime uses an isolated `TMPDIR`.
- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.

## Plan

1. Add a Streamable MCP resource/prompt error helper to the generated neutral
   consumer package.
2. Call it after successful initialized Streamable resource/prompt access.
3. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
  with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-07 with isolated `TMPDIR`.
- Hosted GitHub evidence pending after push.

## Decision Log

- 2026-05-07: Chose this slice because generic direct JSON-RPC resource and
  prompt errors are now covered, while initialized Streamable sessions still
  only had missing-tool error/recovery coverage.

## Handoff

Local implementation and verification complete. Hosted evidence pending after
push.
