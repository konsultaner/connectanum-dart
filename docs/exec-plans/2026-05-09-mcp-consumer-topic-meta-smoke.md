# Exec Plan: MCP Consumer Topic Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the generated consumer package smoke prove that a consumer application can
discover configured WAMP topic metadata, including describe-time event schema
and publish/subscribe capabilities, through both lifecycle-free direct JSON and
initialized Streamable HTTP MCP requests.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The public router-hosted MCP example now covers topic metadata discovery.
- The generated consumer package smoke already proves topic catalog visibility,
  but it does not yet describe the configured topic or assert the schema and
  capability fields a consumer application would use for pub/sub planning.

## Scope

- Add schema and metadata to the generated consumer package route topic.
- Extend generated consumer smoke WAMP API metadata checks to call
  `connectanum.api.describe` for the configured topic through direct JSON and
  Streamable HTTP helpers.
- Preserve existing session-state guarantees for lifecycle-free direct JSON
  calls made while Streamable HTTP is active.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused generated consumer package smoke passed on 2026-05-09 with isolated
  `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `4f4bf19` (`test: cover consumer mcp topic metadata`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25594498968` for `4f4bf19` completed successfully
  on 2026-05-09 with `Fast Checks` (4m12s) and `Full Verify` (5m41s) green.
- No new WAMP profile or Dart package publish dry-run workflow was created for
  `4f4bf19`; deployment-chain audit reports the latest Dart package publish
  dry-run, `25593496098` at `a87e872`, remains clean and relevant because no
  publish-sensitive paths changed.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- Keep this as generated consumer package smoke coverage so package consumers
  prove the metadata path without relying on private project configuration.

## Handoff

Implementation, local verification, hosted CI, and standard deployment-chain
audit evidence are clean for `4f4bf19`. Remaining strict audit failures are
operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.
