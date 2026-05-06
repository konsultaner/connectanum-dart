# Exec Plan: MCP Client Package Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove that a consumer application or agent can use the public
`connectanum_mcp` IO entrypoint without declaring `connectanum_router` or
lower-level client packages as direct dependencies.

## Scope

- In scope:
  - A generated client-only consumer package smoke in `bin/common.sh`.
  - Fast/full verification script coverage for the new smoke.
  - Local and hosted verification evidence.
- Out of scope:
  - Changing package publishing policy or removing `publish_to: none`.
  - Router-hosted MCP runtime behavior changes.
  - Replacing the existing router-hosted consumer smoke.

## Files Expected To Change

- `bin/common.sh`
- `bin/test-fast`
- `bin/test-all`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-client-package-smoke.md`

## Preconditions

- Existing hosted-evidence updates for the prior MCP package metadata readiness
  checkpoint are docs-only and must be bundled with this implementation commit.
- Pre-change `bin/test-fast` passed on 2026-05-07.

## Plan

1. Add a temporary package smoke that depends directly only on
   `connectanum_mcp`, with local path overrides only for workspace resolution.
2. Exercise the public `package:connectanum_mcp/connectanum_mcp_io.dart`
   entrypoint against a local mock Streamable HTTP endpoint, covering
   initialization, typed tool helpers, lifecycle-free direct JSON access,
   GET/SSE polling, and session deletion.
3. Run focused shell/smoke checks, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- `bash -n bin/common.sh bin/test-fast bin/test-all` passed on 2026-05-07.
- `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_client_package_smoke'`
  passed on 2026-05-07.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted GitHub `CI` run `25465909291` for `ebce710` completed successfully
  with `Fast Checks` and `Full Verify`, both with zero annotations.
- The Dart Package Publish Dry Run workflow did not trigger for `ebce710`
  because no publish-sensitive paths changed. The latest relevant package
  dry-run remains `25463696541` for `3a0bbf0`, which completed successfully.
- The deployment-chain audit
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed against `ebce710`; the strict variant correctly failed only on the
  known operator-owned gaps: `add-router` branch protection, router image
  workflow visibility from the default branch, and GHCR router package
  visibility.

## Decision Log

- 2026-05-07: Chose this slice because the existing generated consumer package
  smoke proves the real router-hosted MCP route but necessarily depends on
  `connectanum_router` to host the router in process. A separate client-only
  smoke proves the agent/application side can use `connectanum_mcp` without
  taking router as a direct dependency.

## Handoff

- Implementation and hosted CI evidence are clean. Remaining strict audit
  findings are operator-owned deployment-chain gaps.
