# Exec Plan: MCP Consumer Generic Streamable JSON-RPC Smoke

Status: complete locally; full local verification clean; commit pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can use the public generic `McpStreamableHttpClient.request(...)`
and `post(...)` APIs against a real router-provided MCP Streamable HTTP
session, without relying on private project assumptions or typed helper
shortcuts.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add generic Streamable JSON-RPC single-request coverage for standard
    `tools/list`, `tools/call`, `resources/list`, `resources/read`,
    `prompts/list`, and `prompts/get`.
  - Add generic Streamable `tools/call` coverage for router-provided WAMP API
    and pub/sub helper tools.
  - Assert the initialized Streamable session id remains stable and the SSE
    cursor advances for generic Streamable POST responses.
  - Bundle the previous docs-only hosted-evidence state updates from the
    direct batch tool alias smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Direct JSON helper changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-direct-batch-tool-alias-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-jsonrpc-smoke.md`

## Preconditions

- Latest pushed implementation commit `ecac196` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Add a generated consumer smoke helper for generic Streamable JSON-RPC
   `request(...)` and `post(...)` calls.
2. Cover standard MCP tool/resource/prompt methods plus router-provided WAMP
   API and pub/sub helper tools.
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

- 2026-05-08: Chose this slice because direct JSON generic APIs and typed
  Streamable helpers are already covered, while an app using the public generic
  Streamable JSON-RPC APIs should also be proven against the real router-hosted
  MCP endpoint.
- 2026-05-08: The first focused smoke attempt exposed that raw single-message
  `post(...)` calls for tools with `x-mcp-header` input fields must provide the
  corresponding `Mcp-Param-*` headers explicitly. The smoke now proves that
  public generic path by passing those headers itself.

## Handoff

Implementation passed focused syntax/generated consumer smoke checks,
post-change `bin/test-fast`, and full local `bin/verify`; commit and hosted
evidence are pending.
