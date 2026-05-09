# Exec Plan: MCP Server Package Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp.dart` and host a basic MCP server
without private project internals or router dependencies.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Existing generated package smokes covered the public IO client entrypoint and
  router-hosted MCP consumer path, but not the server-side public
  `connectanum_mcp.dart` entrypoint from a fresh package.
- This slice keeps package-boundary evidence in the normal fast/full
  verification path.

## Scope

- Add `run_mcp_server_package_smoke` to `bin/common.sh`.
- Generate a temporary neutral package that depends on `connectanum_mcp` with
  local dependency overrides.
- Import only `package:connectanum_mcp/connectanum_mcp.dart` in the generated
  smoke.
- Exercise `McpServer.handleMessage` lifecycle, tools, resources, resource
  templates, prompts, JSON-RPC batch behavior, notification omission, shutdown
  state, and `McpStdioTransport` line/batch handling.
- Wire the smoke into `bin/test-fast` and `bin/test-all` before the existing
  MCP client/router consumer package smokes.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `run_mcp_server_package_smoke` passed on 2026-05-09 with isolated
  `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `c5de8cb` (`test: add mcp server package smoke`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- GitHub `CI` run `25611002819` completed successfully for `c5de8cb` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25609860588` remains clean and
  relevant because no publish-sensitive paths changed since `f4bb186`.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-09: Chose this slice because downstream package-readiness evidence
  already covered MCP clients and router-hosted endpoints, while the public
  server entrypoint still lacked a generated consumer package smoke.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
