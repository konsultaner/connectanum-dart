# Exec Plan: MCP Deterministic Tool Catalog Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make router-hosted MCP tool catalogs deterministic for downstream agents and
consumer applications by sorting `tools/list` responses and proving the sorted,
unique catalog shape through package-level and generated consumer-package
smokes.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The official MCP stable protocol revision remains `2025-11-25`
  (`https://modelcontextprotocol.io/specification/2025-11-25/basic/transports`),
  which this repo already supports for Streamable HTTP lifecycle and
  protocol-version negotiation.
- The official MCP draft changelog
  (`https://modelcontextprotocol.io/specification/draft/changelog`) now calls
  out deterministic `tools/list` ordering as cache-friendly guidance. This slice
  adopts the stable behavioral property without depending on draft-only protocol
  changes.
- Router-hosted MCP tool catalogs may be backed by dynamic WAMP snapshots, so
  insertion order is not a durable consumer-facing contract.

## Scope

- Sort `McpToolRegistry.listPage()` results by tool name before pagination.
- Add package-level coverage that `tools/list` returns deterministic name
  ordering.
- Extend the generated neutral consumer package smoke to assert sorted unique
  tool names for direct JSON access.
- Extend the generated neutral consumer package smoke to assert sorted unique
  tool names for generic Streamable JSON-RPC access against a real
  router-hosted MCP endpoint.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `dart format packages/connectanum_mcp/lib/src/tools/tool.dart
  packages/connectanum_mcp/test/tools_test.dart` passed on 2026-05-10.
- `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `dart test packages/connectanum_mcp/test/tools_test.dart` passed on
  2026-05-10.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Commit `0ce6929` (`test: cover deterministic mcp tool catalogs`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25617167891` completed successfully for `0ce6929` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25617167890` completed
  successfully for `0ce6929`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Chose this slice because deterministic tool catalogs reduce
  downstream agent churn and align router-hosted MCP behavior with current MCP
  draft readiness guidance while staying compatible with the stable
  `2025-11-25` transport behavior.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
