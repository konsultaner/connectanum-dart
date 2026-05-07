# Exec Plan: MCP Client Package Helper Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Extend the client-only consumer package smoke so a consumer application or
agent proves the public `connectanum_mcp` IO entrypoint can drive resources,
prompts, WAMP API/meta helpers, and pub/sub helpers without declaring router or
lower-level client packages as direct dependencies.

## Scope

- In scope:
  - Expand `run_mcp_client_package_smoke` in `bin/common.sh`.
  - Keep the temporary package direct dependency limited to `connectanum_mcp`.
  - Cover Streamable and lifecycle-free direct JSON helper calls against a
    local mock endpoint.
  - Local and hosted verification evidence.
- Out of scope:
  - Router-hosted MCP runtime behavior changes.
  - Package publishing policy changes.
  - Replacing the real router-hosted consumer package smoke.

## Plan

1. Extend the mock endpoint with resources, resource templates, prompts,
   WAMP API metadata, WAMP meta procedure, and pub/sub tool responses.
2. Extend the generated consumer package main program to call those helpers via
   `package:connectanum_mcp/connectanum_mcp_io.dart`.
3. Assert direct JSON helper calls omit `MCP-Session-Id` even after a
   Streamable session is initialized.
4. Run focused smoke checks, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- `bash -n bin/common.sh bin/test-fast bin/test-all` passed on 2026-05-07.
- `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_client_package_smoke'`
  passed on 2026-05-07 after the smoke expansion.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted GitHub `CI` run `25467715044` for `8116786` completed successfully
  with `Fast Checks` and `Full Verify`, both with zero annotations.
- The Dart Package Publish Dry Run workflow did not trigger for `8116786`
  because no publish-sensitive paths changed. The latest relevant package
  dry-run remains `25463696541` for `3a0bbf0`, which completed successfully.
- The deployment-chain audit
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed against `8116786`; the strict variant correctly failed only on the
  known operator-owned gaps: `add-router` branch protection, router image
  workflow visibility from the default branch, and GHCR router package
  visibility.

## Handoff

- Implementation and hosted CI evidence are clean. Remaining strict audit
  findings are operator-owned deployment-chain gaps.
