# Exec Plan: MCP Client Package Streamable Lifecycle Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the generated client-only consumer package smoke prove the public
`connectanum_mcp` IO client can handle Streamable HTTP session lifecycle edge
cases without relying on router internals or private project assumptions.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The real router-hosted consumer smoke and public router-hosted MCP example
  already prove Streamable lifecycle behavior against the router.
- The client-only generated smoke is the neutral package-boundary check for a
  consumer application using only public package imports, so it should also
  prove cursor, stale-session, and recovery behavior against a minimal endpoint.

## Scope

- Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
- Add neutral endpoint handling for GET/SSE event ids, `Last-Event-ID` resume,
  invalid cursor rejection, session DELETE, stale-session 404 responses, and
  reinitialization.
- Assert the public client preserves active session state after invalid
  `Last-Event-ID`, clears stale session state after 404, and can initialize and
  list tools again after recovery.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused generated client-only consumer package smoke passed on 2026-05-09
  with isolated `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Hosted GitHub `CI` run `25598397391` for `4647a8d` completed successfully
  on 2026-05-09 with `Fast Checks` and `Full Verify` green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence. The latest relevant
  `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
  it is still relevant because no publish-sensitive paths changed since that
  run.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- Keep the smoke neutral and generated because it proves a consumer application
  can depend on the public `connectanum_mcp` IO entrypoint without access to
  repository-private router helpers.

## Handoff

Implementation, local verification, push, and hosted CI/deployment-chain
evidence are complete. Remaining strict audit findings are operator-side
release gaps, not regressions from this smoke-test change.
