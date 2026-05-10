# Exec Plan: MCP Deterministic WAMP API Catalog Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make direct WAMP API metadata catalogs deterministic for downstream agents and
consumer applications by sorting `connectanum.api.list` procedure and topic
metadata before returning it, then proving the sorted, unique catalog shape
through package tests and the generated neutral consumer-package smoke.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Recent slices made `tools/list`, `resources/list`,
  `resources/templates/list`, and `prompts/list` deterministic.
- `connectanum.api.list` is the direct JSON and Streamable meta API that lets
  clients discover router-exposed WAMP procedures and topics without private
  project assumptions.
- Router-hosted WAMP snapshots can arrive in non-durable order, so meta API
  consumers should not see insertion-order churn.

## Scope

- Sort `connectanum.api.list` procedure metadata by procedure URI.
- Sort `connectanum.api.list` topic metadata by topic URI.
- Add package-level coverage for deterministic WAMP API procedure/topic
  metadata ordering.
- Extend the generated neutral consumer package smoke to assert sorted unique
  WAMP API metadata catalogs for typed Streamable helpers, typed direct JSON
  helpers, generic direct JSON-RPC access, and generic Streamable JSON-RPC
  access against a real router-hosted MCP endpoint.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- `dart format packages/connectanum_mcp/lib/src/tools/wamp_api.dart
  packages/connectanum_mcp/test/wamp_api_test.dart` passed on 2026-05-10.
- `bash -n bin/common.sh` passed on 2026-05-10.
- Focused `dart test packages/connectanum_mcp/test/wamp_api_test.dart` passed
  on 2026-05-10.
- Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
- Commit `eb8724a` (`test: cover deterministic mcp wamp api catalogs`) was
  pushed to `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25619083686` completed successfully for `eb8724a` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25619083679` completed
  successfully for `eb8724a`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-10: Chose this slice because direct WAMP meta API catalogs are the
  remaining downstream-facing MCP discovery surface that still depended on
  snapshot insertion order after standard MCP catalog determinism landed.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
