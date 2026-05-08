# Exec Plan: MCP Client Package Direct Generic Tool Method Smoke

Status: complete; hosted CI evidence clean
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
- Commit `54621c8`
  (`test: cover mcp direct generic tool client smoke`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25554720402` for `54621c8` completed successfully on
  2026-05-08 with `Fast Checks` (5m47s) and `Full Verify` (8m10s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports operator-side gaps: branch protection
  and required status checks are absent, `.github/workflows/router-image.yml`
  is not discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because generated client-only consumer smoke
  already proves Streamable lifecycle, direct resource/prompt helpers, WAMP API
  helpers, WAMP meta helpers, and pub/sub helpers, while the direct JSON generic
  tool API still needs consumer-package evidence for normal tool calls,
  `connectanum.tools.call`, and dotted tool-name method calls after an active
  Streamable session.

## Handoff

Implementation, local verification, push to both remotes, hosted GitHub CI,
and deployment-chain audit evidence are complete. Remaining strict deployment
findings are operator-owned release controls: branch protection and required
status checks, default-branch router image workflow visibility, and GHCR router
package visibility.
