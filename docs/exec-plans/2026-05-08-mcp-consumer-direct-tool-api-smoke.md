# Exec Plan: MCP Consumer Direct Tool API Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can use every public generic direct JSON tool-call shape against a
real router-provided MCP endpoint, both before and after Streamable HTTP session
initialization, without changing Streamable session state.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Exercise `callConnectanumToolDirect` against the route-exposed application
    tool.
  - Exercise the plural `connectanum.tools.call` direct JSON alias through the
    raw direct-method helper.
  - Exercise dotted tool-name direct JSON invocation through
    `callConnectanumMethodDirect`.
  - Assert the generic direct JSON tool API leaves active Streamable session
    and event cursor state unchanged.
  - Bundle existing docs-only hosted-evidence updates from the previous MCP
    client package direct generic tool method smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Package publishing policy changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-client-package-direct-generic-tool-method-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-direct-tool-api-smoke.md`

## Preconditions

- Latest pushed implementation commit `54621c8` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Add a generated consumer smoke helper for the direct tool helper, plural
   alias, and dotted-method direct tool invocation.
2. Run that helper in direct-JSON-only coverage and again after Streamable
   initialization.
3. Assert each direct tool API call preserves Streamable session/cursor state.
4. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
5. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh bin/test-fast bin/test-all` passed on
  2026-05-08.
- Focused generated router-hosted consumer package smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit `a27172e` (`test: cover router mcp direct tool api smoke`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25557107785` for `a27172e` completed successfully on
  2026-05-08 with `Fast Checks` (6m0s) and `Full Verify` (8m26s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports operator-side gaps: branch protection
  and required status checks are absent, `.github/workflows/router-image.yml`
  is not discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because the client-only smoke proves the
  generic direct JSON tool API against a mock endpoint, while the generated
  router-hosted consumer smoke still needs real endpoint proof for the public
  direct tool helper, plural alias, and dotted tool method after an active
  Streamable session.

## Handoff

Implementation passed focused syntax/generated consumer smoke checks,
post-change `bin/test-fast`, full local `bin/verify`, hosted GitHub CI, and the
standard deployment-chain audit. The remaining strict-audit findings are
release-operations configuration gaps outside this implementation slice.
