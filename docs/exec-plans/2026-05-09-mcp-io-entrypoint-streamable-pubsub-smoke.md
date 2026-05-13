# Exec Plan: MCP IO Entrypoint Streamable Pub/Sub Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Prove that a consumer application depending on `connectanum_mcp` can import
only `package:connectanum_mcp/connectanum_mcp_io.dart` and use the public
Streamable HTTP client for WAMP-backed MCP pub/sub helpers without reaching
through private package internals.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The generated external client-only package smoke already covers public
  pub/sub helpers and direct JSON batches from a generated package.
- The checked-in `connectanum_mcp` IO entrypoint test proved direct WAMP helper
  exports plus Streamable resource/prompt helpers, but it did not yet prove
  Streamable pub/sub helper usage through the same package boundary.

## Scope

- Extend `packages/connectanum_mcp/test/io_client_export_test.dart`.
- Reuse a neutral fake MCP HTTP endpoint that returns initialized Streamable
  session headers, SSE response events, direct JSON responses, and JSON-RPC
  batch responses.
- Cover public `subscribeWampTopic`, `publishWampEvent`, `pollWampEvents`, and
  `unsubscribeWampTopic` helpers imported through `connectanum_mcp_io.dart`.
- Cover direct JSON pub/sub helper calls without session headers while an
  initialized Streamable session remains active.
- Cover lifecycle-free direct JSON batch pub/sub tool calls with neighboring
  success entries and a recoverable tool-level missing-subscription result.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `da31835` (`test: cover mcp io streamable pubsub`) pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- GitHub CI run `25604475522` completed successfully for `da31835` on
  2026-05-09 with expected jobs `Fast Checks` and `Full Verify` both green.
- GitHub Dart Package Publish Dry Run `25604475505` completed successfully for
  `da31835` on 2026-05-09 with `Publish Dry Run` green.
- `bin/audit-github-deployment-chain --branch add-router --run-limit 1
  --require-clean-latest-ci --show-dart-package-publish-dry-run
  --require-clean-dart-package-publish-dry-run` passed on 2026-05-09.
- Strict audit was rerun on 2026-05-09 and failed only on known operator-side
  release-hardening gaps: branch protection/required checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.

## Decision Log

- 2026-05-09: Chose this slice because package-boundary IO coverage had
  already reached resources/prompts, while pub/sub helpers still relied on
  lower-level client-package tests and generated consumer smokes.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit still reports only known operator-side
release-hardening gaps.
