# Exec Plan: MCP Active Session Auth Invalidation Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Extend the generated router-hosted consumer package smoke so a consumer
application proves protected Streamable MCP sessions do not remain usable after
their bearer credentials are rotated or revoked.

## Scope

- In scope:
  - Expand `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use only public `connectanum_mcp` / `connectanum_router` / MCP client APIs
    from the generated consumer package.
  - Open a protected Streamable MCP session with the initial ticket bearer,
    rotate that bearer, then assert the still-active session is rejected.
  - Open a protected Streamable MCP session with the refreshed bearer, revoke
    that grant, then assert the still-active session is rejected.
  - Local and hosted verification evidence.
- Out of scope:
  - Router auth bridge behavior changes.
  - Public API changes.
  - Package publishing policy changes.

## Plan

1. Add a small generated-app helper that initializes a protected Streamable MCP
   session and keeps its session id active.
2. In the existing auth refresh/revoke smoke, assert the active old-token
   session receives `401 Unauthorized` after refresh rotation.
3. Assert an active refreshed-token session receives `401 Unauthorized` after
   revocation.
4. Run focused smoke checks, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- `bash -n bin/common.sh bin/test-fast bin/test-all` passed on 2026-05-07.
- Focused consumer smoke passed on 2026-05-07:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted GitHub `CI` run `25472416302` for `abf60f9` completed
  successfully with `Fast Checks` and `Full Verify`, both with zero
  annotations.
- The Dart Package Publish Dry Run workflow did not trigger for `abf60f9`
  because no publish-sensitive paths changed. The latest relevant package
  dry-run remains `25463696541` for `3a0bbf0`, which completed successfully.
- The deployment-chain audit
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed against `abf60f9`; the strict variant correctly failed only on the
  known operator-owned gaps: `add-router` branch protection, router image
  workflow visibility from the default branch, and GHCR router package
  visibility.

## Handoff

- Implementation and hosted CI evidence are clean. Remaining strict audit
  findings are operator-owned deployment-chain gaps.
