# Exec Plan: Router-Hosted MCP Direct Batch Error Isolation Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that router-hosted MCP direct JSON batches preserve JSON-RPC
error-isolation semantics for consumer applications: a failed request returns an
error response without hiding successful sibling responses or emitting a
notification response.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Existing router-hosted coverage proved successful direct JSON batches and
  invalid nested batches on the public MCP route.
- The remaining package-readiness gap was mixed success/error behavior inside a
  single direct JSON batch on the router-provided endpoint.

## Scope

- Extend `packages/connectanum_router/test/router_integration_native_test.dart`.
- Add a public `/mcp/public` direct JSON batch containing a valid
  `connectanum.api.list` request, an unknown MCP method request, and a
  notification-only `connectanum.tool.call`.
- Assert the route returns HTTP 200, keeps the successful result, returns the
  `-32601` unknown-method error for the failed request, and omits a response for
  the notification.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused
  `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "smoke tests MCP router RPC pubsub and route security"`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `82cb660` (`test: cover router mcp direct batch errors`) was pushed
  to `origin/add-router` and `github/add-router` on 2026-05-09.
- GitHub `CI` run `25611916466` completed successfully for `82cb660` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25611916436` completed
  successfully for `82cb660` and is clean/relevant.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-09: Chose this slice because direct JSON batch error isolation is part
  of the MCP downstream tool/meta API contract, and the router-hosted endpoint
  only had separate success and invalid-batch coverage.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
