# Exec Plan: MCP Consumer Generic Streamable Meta Template Smoke

Status: complete locally; full local verification clean; commit pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can use generic Streamable JSON-RPC calls for router-provided WAMP
API/meta tools and configured resource templates, not only standard tool calls,
resources, prompts, and pub/sub helpers.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add generic Streamable JSON-RPC coverage for `connectanum.api.describe`.
  - Add generic Streamable JSON-RPC coverage for WAMP session and registration
    meta tools reached through standard MCP `tools/call`.
  - Add generic Streamable JSON-RPC coverage for `resources/templates/list`.
  - Assert the initialized Streamable session id remains stable and the SSE
    cursor advances after each generic Streamable POST response.
  - Bundle the previous docs-only hosted-evidence state updates from the
    generic Streamable JSON-RPC smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Direct JSON helper changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-jsonrpc-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-meta-template-smoke.md`

## Preconditions

- Latest pushed implementation commit `047928f` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Extend the generated consumer smoke helper for generic Streamable JSON-RPC
   with WAMP API describe, WAMP meta, and resource template calls.
2. Run focused syntax/generated consumer smoke checks, post-change
   `bin/test-fast`, and full `bin/verify` with isolated `TMPDIR`.
3. Commit implementation plus bundled state updates, push both remotes, and
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

- 2026-05-08: Chose this slice because generic Streamable JSON-RPC consumer
  smoke already covers core tool/resource/prompt/pub/sub paths, while router
  WAMP API/meta and resource-template access are the next public surfaces a
  downstream application or agent is likely to use through the generic client
  APIs.

## Handoff

Implementation passed focused syntax/generated consumer smoke checks,
post-change `bin/test-fast`, and full local `bin/verify`; commit and hosted
evidence are pending.
