# Exec Plan: MCP Consumer Package Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Prove that a consumer application can resolve and analyze the public MCP,
client, and router package entrypoints from outside the workspace without
depending on repo-private source imports or application-specific assumptions.

## Scope

In scope:

- Add a root verification helper that creates a temporary Dart package outside
  the workspace.
- Resolve the local workspace packages through public package dependencies and
  dependency overrides, mirroring a downstream application checkout.
- Analyze a small public-entrypoint program that imports
  `package:connectanum_client/mcp.dart`,
  `package:connectanum_mcp/connectanum_mcp.dart`, and
  `package:connectanum_router/connectanum_router.dart`.
- Wire the smoke into `bin/test-fast` and `bin/test-all`.

Out of scope:

- Running another router instance from the temporary package; runtime
  router-hosted MCP behavior remains covered by the canonical example smoke.
- Changing public package publishability or release order.
- Adding consumer-application-specific references.

## Plan

1. Reproduce the external package-resolution shape with a temporary consumer
   package.
2. Add a shared `bin/common.sh` helper for the consumer package smoke.
3. Wire the helper into fast and full root verification.
4. Run the focused helper, `bin/test-fast`, and `bin/verify`.
5. Push and collect hosted GitHub CI evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused helper check passed on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-04 and included the new
  temporary consumer package smoke after the router-hosted MCP example gate.
- Full local `bin/verify` passed on 2026-05-04. It included formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  smoke, the new consumer package smoke, full router package tests including
  `remote_auth_integration_test`, zero-copy router checks, and Chrome
  Dart2Wasm WebSocket transport tests.
- Commit `e9c689c` was pushed to both remotes. Hosted GitHub `CI` run
  `25327138243` completed successfully with `Fast Checks` and `Full Verify`.
  The deployment-chain audit with required clean latest CI and clean hosted CI
  logs passed for branch head `e9c689c`. `Dart Package Publish Dry Run` and
  `WAMP Profile Benchmarks` did not trigger for this script/docs change because
  their workflow path filters exclude the touched files; the latest relevant
  runs remain clean on `c754772`. The remaining audit findings are the existing
  operator/deployment items around branch protection, default-branch router
  workflow visibility, and GHCR router package visibility.

## Handoff

Implementation, local verification, and hosted GitHub CI evidence are complete.
