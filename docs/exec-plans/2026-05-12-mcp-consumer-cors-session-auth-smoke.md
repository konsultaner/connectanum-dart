# Exec Plan: MCP Consumer CORS Session Auth Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers receive CORS-readable
Streamable HTTP session/auth failures that preserve active session context and
do not create accidental session state.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes reject missing Streamable session headers and
  invalid `Last-Event-ID` values with readable CORS JSON errors.
- Extend the same smoke so active secure Streamable sessions reject missing or
  invalid bearer tokens on raw POST/GET/DELETE paths while preserving the
  active `MCP-Session-Id`.
- Fix the router MCP route auth wrapper so route-level auth failures include
  the request `MCP-Session-Id` when present.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Initial focused generated consumer smoke caught the missing active-session
  header on secure MCP route auth failures.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after the router/session fix.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `aa33384` (`fix: preserve mcp session on cors auth failures`) was
  pushed to both configured remotes on 2026-05-12.
- GitHub Actions passed on `aa33384`: `CI` run `25751993094`,
  `Dart Package Publish Dry Run` run `25751993080`, and
  `WAMP Profile Benchmarks` run `25751993089` all completed successfully.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, hosted CI logs clean,
  and a clean relevant Dart package publish dry-run for `aa33384`.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, WAMP Profile Benchmarks, Dart package publish dry-run, and the
non-strict deployment-chain audit are clean for `aa33384`. The only remaining
strict-audit gaps are operator-side release-hardening items.
