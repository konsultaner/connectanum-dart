# Exec Plan: MCP Client Package Direct Generic Tool Method Smoke

Status: complete locally; full local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated client-only consumer package that downstream
applications can use the generic direct JSON Connectanum tool API after a
Streamable HTTP session is active, without leaking Streamable session headers or
relying on router/private project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
  - Exercise `callConnectanumToolDirect` against a normal application tool.
  - Exercise the plural `connectanum.tools.call` direct JSON alias through the
    raw direct-method helper.
  - Exercise dotted tool-name direct JSON invocation through
    `callConnectanumMethodDirect`.
  - Assert `connectanum.tools.list`, `connectanum.tool.call`,
    `connectanum.tools.call`, and the application tool method all arrive
    without `MCP-Session-Id` after Streamable initialization.
  - Bundle existing docs-only hosted-evidence updates from the previous MCP
    client package direct WAMP meta helper smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Package publishing policy changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-client-package-direct-wamp-meta-helper-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-client-package-direct-generic-tool-method-smoke.md`

## Preconditions

- Latest pushed implementation commit `86f59f6` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Add generic direct JSON tool API calls to the generated client-only consumer
   package smoke.
2. Extend the mock MCP endpoint so generic direct tool-call, plural alias, and
   dotted tool-name direct method calls return structured tool results.
3. Assert each generic direct JSON tool API shape remains lifecycle-free after
   Streamable initialization.
4. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
5. Commit implementation plus bundled state updates, push both remotes, and
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
- First full local `bin/verify` attempt on 2026-05-08 hit a transient
  `ct_ffi` HTTP/3 handshake timeout in
  `tests::listen_flow::http3_handshake_surfaced_via_ffi`; the focused
  `cargo test -p ct_ffi tests::listen_flow::http3_handshake_surfaced_via_ffi`
  rerun passed immediately.
- Full local `bin/verify` rerun passed on 2026-05-08 with isolated `TMPDIR`.
- Commit and hosted evidence are pending.

## Decision Log

- 2026-05-08: Chose this slice because generated client-only consumer smoke
  already proves Streamable lifecycle, direct resource/prompt helpers, WAMP API
  helpers, WAMP meta helpers, and pub/sub helpers, while the direct JSON generic
  tool API still needs consumer-package evidence for normal tool calls,
  `connectanum.tools.call`, and dotted tool-name method calls after an active
  Streamable session.

## Handoff

Implementation passed focused syntax/generated client-only smoke checks,
post-change `bin/test-fast`, and full local `bin/verify`; commit and hosted
evidence are pending.
