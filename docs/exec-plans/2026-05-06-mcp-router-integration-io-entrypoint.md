# Exec Plan: MCP Router Integration IO Entrypoint

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-06
Last updated: 2026-05-06

## Goal

Make router-hosted MCP integration coverage use the public
`package:connectanum_mcp/connectanum_mcp_io.dart` consumer entrypoint instead
of the lower-level client MCP barrel.

## Scope

- In scope:
  - Router MCP integration test imports.
  - Stale roadmap-next consumer entrypoint wording.
  - Local and hosted verification evidence.
- Out of scope:
  - MCP protocol behavior changes.
  - Package dependency redesign.
  - Public API redesign.

## Files Expected To Change

- `packages/connectanum_router/test/router_integration_native_test.dart`
- `ROADMAP_NEXT.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-06-mcp-router-integration-io-entrypoint.md`

## Preconditions

- Existing hosted-evidence updates for the prior MCP public example IO
  entrypoint checkpoint are docs-only and must be bundled with this
  implementation commit.
- Pre-change `bin/test-fast` passed on 2026-05-06.

## Plan

1. Switch the router-hosted MCP integration test import to
   `package:connectanum_mcp/connectanum_mcp_io.dart`.
2. Align `ROADMAP_NEXT.md` consumer-entrypoint wording with the public IO
   entrypoint.
3. Run focused analysis/tests, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`
  passed on 2026-05-06.
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name MCP`
  passed on 2026-05-06.
- `rg -n 'package:connectanum_client/mcp.dart' packages/connectanum_router/test/router_integration_native_test.dart ROADMAP_NEXT.md packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_mcp/README.md`
  returned no matches on 2026-05-06.
- Post-change `bin/test-fast` passed on 2026-05-06.
- Full local `bin/verify` passed on 2026-05-06.
- Pending: hosted GitHub evidence after push.

## Decision Log

- 2026-05-06: Chose this slice because the public example and generated
  consumer smoke already prove the intended IO entrypoint, but the router MCP
  integration suite still imported the lower-level client package directly.

## Handoff

- Router integration IO entrypoint work is complete locally. Push the
  implementation commit and collect hosted GitHub evidence.
