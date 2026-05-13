# Exec Plan: MCP Consumer Generic Streamable JSON-RPC Smoke

Status: complete; hosted CI evidence clean
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
- Commit `047928f` (`test: cover mcp generic streamable jsonrpc smoke`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25562441868` for `047928f` completed successfully
  on 2026-05-08 with `Fast Checks` (6m19s) and `Full Verify` (8m43s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports operator-side gaps: branch protection
  and required status checks are absent, `.github/workflows/router-image.yml`
  is not discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

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

Implementation, hosted GitHub CI, and the standard deployment-chain audit are
clean. Remaining strict deployment audit findings are release-operations gaps
outside this implementation slice.
