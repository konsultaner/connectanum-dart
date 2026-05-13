# Exec Plan: MCP resource read support

Status: completed
Owner: Codex
Created: 2026-05-02
Last updated: 2026-05-02

## Goal

Add a narrow, transport-independent MCP resource surface so downstream
applications can expose read-only context through `packages/connectanum_mcp`
without waiting for full Streamable HTTP, prompts, or router-hosted resource
projection.

## Scope

- In scope:
  - Recheck the current MCP resource and pagination spec shape.
  - Add package-local models and registry support for resources, resource
    contents, and resource templates.
  - Handle `resources/list`, `resources/read`, and
    `resources/templates/list` in `McpServer`.
  - Advertise the `resources` capability when resources or templates are
    configured.
  - Document the package-local resource surface and its remaining boundaries.
- Out of scope:
  - Resource subscriptions or list-change notifications.
  - Router-hosted resource projection.
  - Prompts, sampling, tasks, or full Streamable HTTP GET/SSE/session handling.
  - Filesystem access helpers or application-specific resource URI policy.

## Verification

- `bin/test-fast`
- `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`
- `dart analyze packages/connectanum_mcp`
- `dart test packages/connectanum_mcp -r expanded`
- `git diff --check`
- `bin/verify`

## Decision Log

- 2026-05-02: The GitHub deployment-chain audit is clean for autonomous CI/log,
  Dart package dry-run, and native release dry-run gates; remaining RC blockers
  are operator/deployment decisions. Continued with MCP usability because the
  resource surface is the next concrete downstream-application gap after tools.
- 2026-05-02: Rechecked the official MCP `2025-11-25` resources and pagination
  docs. The local slice intentionally implements list/read/template-list only;
  subscriptions and list-change notifications require application policy and
  are deferred.
- 2026-05-02: Pre-change `bin/test-fast` passed before MCP resource edits.
- 2026-05-02: Added the package-local MCP resource registry and server handlers.
  `McpServer` now advertises `resources` when resources or templates are
  configured, serves paginated `resources/list` and
  `resources/templates/list`, reads text/blob resource contents through
  `resources/read`, and returns the MCP resource-not-found error with URI data
  for unknown resources.
- 2026-05-02: Focused checks passed after the MCP resource edits:
  `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`,
  `dart analyze packages/connectanum_mcp`, and
  `dart test packages/connectanum_mcp -r expanded`.
- 2026-05-02: Full local `bin/verify` passed after the MCP resource support
  implementation and docs updates.
- 2026-05-02: Pushed commit `da6bb32` (`mcp: add resource read support`) to
  both remotes. Hosted GitHub `CI` run `25254927687` passed with `Fast Checks`
  in 5m37s and `Full Verify` in 7m53s. Hosted `Dart Package Publish Dry Run`
  run `25254927695` passed in 19s and covers the checked-out head. The clean
  deployment-chain audit then passed against `da6bb32`, including hosted CI log
  scan, fresh package dry-run relevance, and native release dry-run relevance.

## Handoff

- Completed locally and verified on hosted GitHub CI/package dry-run.
  Remaining MCP compatibility work is intentionally deferred until a downstream
  application needs it: resource subscriptions/list-change notifications,
  router-hosted resource projection, prompts, and full Streamable HTTP
  GET/SSE/session semantics.
