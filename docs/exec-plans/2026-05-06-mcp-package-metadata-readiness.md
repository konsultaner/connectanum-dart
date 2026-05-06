# Exec Plan: MCP Package Metadata Readiness

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-06
Last updated: 2026-05-06

## Goal

Make the public `connectanum_mcp` package metadata and opening README language
match the currently shipped MCP surface for consumer applications: local MCP
server primitives plus router-hosted Streamable HTTP client access.

## Scope

- In scope:
  - `connectanum_mcp` pub package description.
  - `connectanum_mcp` README introduction.
  - Local and hosted package/readiness verification evidence.
- Out of scope:
  - MCP protocol behavior changes.
  - Package version changes.
  - Dependency publishing-order changes.

## Files Expected To Change

- `packages/connectanum_mcp/pubspec.yaml`
- `packages/connectanum_mcp/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-06-mcp-package-metadata-readiness.md`

## Preconditions

- Existing hosted-evidence updates for the prior MCP router integration IO
  entrypoint checkpoint are docs-only and must be bundled with this package
  metadata implementation commit.
- Pre-change `bin/test-fast` passed on 2026-05-06.

## Plan

1. Update package metadata so `connectanum_mcp` is no longer described as
   server-only or tied to a specific application shape.
2. Update the README introduction to mention both local MCP servers and
   router-hosted Streamable HTTP endpoints for consumer applications.
3. Run focused package analysis/tests, package publish dry-run validation,
   `bin/test-fast`, and `bin/verify`; then push and collect hosted evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- `dart analyze packages/connectanum_mcp` passed on 2026-05-06.
- `dart test packages/connectanum_mcp` passed on 2026-05-06.
- `bin/dart-package-publish-dry-run --include-private packages/connectanum_mcp`
  passed on 2026-05-06 with zero warnings after the package files were
  committed locally.
- `rg -n "server primitives for Connectanum apps|first production shapes needed by Connectanum apps|private downstream|local downstream|/Users/konsultaner|Guten|guten" packages/connectanum_mcp/pubspec.yaml packages/connectanum_mcp/README.md docs/project_state.md docs/exec-plans/2026-05-06-mcp-package-metadata-readiness.md`
  returned no matches on 2026-05-06.
- Post-change `bin/test-fast` passed on 2026-05-06.
- Full local `bin/verify` passed on 2026-05-06.
- Pending: hosted GitHub evidence after push.

## Decision Log

- 2026-05-06: Chose this slice because the public MCP package now exposes a
  consumer-facing IO entrypoint and router-hosted Streamable HTTP helpers, while
  the package metadata still described only server primitives for application
  integrations.

## Handoff

- MCP package metadata readiness is complete locally. Push the implementation
  commit and collect hosted GitHub evidence.
