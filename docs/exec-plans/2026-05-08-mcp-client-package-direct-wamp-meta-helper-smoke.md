# Exec Plan: MCP Client Package Direct WAMP Meta Helper Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated client-only consumer package that downstream
applications can use direct JSON WAMP session, registration, and subscription
meta convenience helpers after a Streamable HTTP session is active, without
leaking Streamable session headers or relying on router/private project
assumptions.

## Scope

- In scope:
  - Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
  - Exercise direct JSON WAMP session list/get helpers in the generated
    package.
  - Exercise direct JSON WAMP registration list/lookup/match/get/callee
    helpers in the generated package.
  - Exercise direct JSON WAMP subscription list/lookup/match/get/subscriber
    helpers in the generated package.
  - Assert each direct WAMP meta helper tool name is observed without
    `MCP-Session-Id` after Streamable initialization.
  - Bundle existing docs-only hosted-evidence updates from the previous MCP
    client package direct WAMP helper smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Package publishing policy changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-client-package-direct-wamp-helper-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-client-package-direct-wamp-meta-helper-smoke.md`

## Preconditions

- Latest pushed implementation commit `be335d8` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Add direct JSON WAMP session list/get helper calls to the generated
   client-only consumer package smoke.
2. Add direct JSON WAMP registration and subscription meta helper calls to the
   generated package smoke.
3. Extend the mock MCP endpoint so each WAMP meta helper returns structured
   results that match the client helper parsers.
4. Assert direct WAMP meta helper tool names all remain lifecycle-free after
   Streamable initialization.
5. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
6. Commit implementation plus bundled state updates, push both remotes, and
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
- Commit `86f59f6` (`test: cover mcp direct wamp meta client smoke`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25552420753` for `86f59f6` completed successfully on
  2026-05-08 with `Fast Checks` (6m18s) and `Full Verify` (8m45s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports only operator-side gaps: branch
  protection is absent, `.github/workflows/router-image.yml` is not
  discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because generated client-only consumer smoke
  already proved direct WAMP API, one WAMP session-count meta helper, and
  pub/sub helpers after Streamable initialization, while the published client
  package exposes broader WAMP session/registration/subscription meta helper
  families that should be proven from the same consumer-package harness.

## Handoff

Implementation, local verification, push to both remotes, hosted GitHub CI,
and deployment-chain audit evidence are complete. Remaining strict deployment
findings are operator-owned release controls: branch protection, default-branch
router image workflow visibility, and GHCR router package visibility.
