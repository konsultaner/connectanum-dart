# Exec Plan: MCP Deterministic Resource Prompt Catalog Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make the remaining MCP catalog surfaces deterministic for downstream agents and
consumer applications by sorting resources, resource templates, and prompts
before pagination and proving the sorted, unique catalog shape through package
tests and the generated neutral consumer-package smoke.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The previous slice made `tools/list` deterministic for cache-friendly agent
  catalog use.
- `resources/list`, `resources/templates/list`, and `prompts/list` still
  depended on insertion order even though router-hosted MCP catalogs can be
  assembled from dynamic route/config/WAMP snapshots.
- Stable ordering should be based on each surface's public identifier: resource
  URI, resource template URI template, and prompt name.

## Scope

- Sort `McpResourceRegistry.listPage()` results by resource URI before
  pagination.
- Sort `McpResourceRegistry.listTemplatePage()` results by resource template
  URI template before pagination.
- Sort `McpPromptRegistry.listPage()` results by prompt name before pagination.
- Add package-level coverage for deterministic resource, resource template, and
  prompt list ordering.
- Extend the generated neutral consumer package smoke to assert sorted unique
  resource, resource template, and prompt catalogs for direct JSON and generic
  Streamable JSON-RPC access against a real router-hosted MCP endpoint.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `dart format packages/connectanum_mcp/lib/src/resources/resource.dart
  packages/connectanum_mcp/lib/src/prompts/prompt.dart
  packages/connectanum_mcp/test/resources_test.dart
  packages/connectanum_mcp/test/prompts_test.dart` passed on 2026-05-10.
- `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `dart test packages/connectanum_mcp/test/resources_test.dart
  packages/connectanum_mcp/test/prompts_test.dart` passed on 2026-05-10.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Commit `c92f6bc` (`test: cover deterministic mcp resource catalogs`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25618101175` completed successfully for `c92f6bc` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25618101186` completed
  successfully for `c92f6bc`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Chose this slice because after tool catalog determinism, resource
  and prompt catalogs were the remaining MCP list surfaces where downstream
  applications could see non-deterministic ordering from dynamic source
  snapshots.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
