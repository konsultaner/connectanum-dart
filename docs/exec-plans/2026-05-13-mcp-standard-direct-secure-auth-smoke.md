# Exec Plan: MCP Standard Direct Secure Auth Smoke

Status: complete; hosted CI/log/dry-run evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

Router-hosted MCP secure-route smokes had broad bearer and session coverage,
but some downstream-facing direct JSON auth checks still proved package-specific
aliases or non-tool methods before the standard MCP `tools/list` and
`tools/call` paths. Consumer applications and agents should be able to rely on
standard direct JSON tool methods for secure endpoints without inheriting
project-specific assumptions.

## Scope

- Make generated consumer-package missing-bearer coverage reject standard direct
  JSON `tools/list`, standard direct JSON `tools/call`, and a standard direct
  JSON batch containing both methods.
- Make generated consumer-package active-session rejected-bearer coverage reject
  standard direct JSON `tools/list`, `tools/call`, and a standard direct JSON
  batch while preserving the existing Streamable session state until a
  Streamable request is rejected.
- Update the public router-hosted MCP example smoke so missing-bearer,
  rotated-token, revoked-token, active-session rejection, and refreshed-grant
  success paths all prove standard direct JSON tool access.
- Keep WAMP meta/pubsub and compatibility alias coverage in their existing
  dedicated smoke paths.

## Non-Goals

- Removing Connectanum-specific compatibility aliases.
- Changing Streamable HTTP lifecycle or session header semantics.
- Changing auth token issuance, refresh, or revocation behavior.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Generated consumer-package secure missing-bearer checks now cover standard
  direct JSON single and batch tool methods.
- Generated consumer-package active rejected-bearer checks now cover standard
  direct JSON single and batch tool methods without losing the active
  Streamable session state.
- Router-hosted example secure auth smokes now demonstrate standard direct JSON
  tool listing, tool calling, and batch tool access for missing, invalidated,
  and refreshed bearer paths.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `dart format packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `git diff --check` passed on 2026-05-13.
- `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  passed on 2026-05-13.
- `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap >/tmp/connectanum-dart-workspace-bootstrap.log; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `b06cad6` (`mcp: cover standard direct secure auth`) was pushed to
  both configured remotes.
- GitHub `CI` run `25783336366` completed successfully for `b06cad6` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25783336354` completed successfully
  for `b06cad6`.
- GitHub `Dart Package Publish Dry Run` run `25783336374` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- `bin/audit-github-deployment-chain --branch add-router --strict --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed the hosted CI, hosted CI log scan, and package dry-run checks, then
  failed only known operator-side release-hardening gaps: branch protection /
  required checks are absent and `.github/workflows/router-image.yml` is not
  yet visible from the default branch through the Actions API. The audit also
  continues to report that the router GHCR package is not visible.

## Decision Log

- Standard direct JSON `tools/list` and `tools/call` are now the primary
  secure-route auth smoke surface because they are the protocol-level methods
  consumer applications can call without a Streamable session.
- Direct JSON active rejected-bearer checks intentionally preserve
  `sessionId`/`lastEventId`; Streamable rejected-bearer checks still clear them.

## Handoff

Implementation is pushed. Focused local checks, full local verification, hosted
CI, WAMP benchmark workflow, package publish dry-run, hosted CI log scan, and
the non-strict deployment-chain audit are clean for `b06cad6`.
