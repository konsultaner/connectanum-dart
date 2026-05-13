# Exec Plan: MCP Consumer Direct JSON Notification CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can send notification-only
direct JSON-RPC requests over CORS without entering the Streamable HTTP session
lifecycle or receiving a JSON-RPC response body.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes return CORS-readable `202 Accepted` responses for
  single direct JSON notifications and notification-only direct JSON batches.
- Keep asserting that direct JSON notification-only requests do not create
  `MCP-Session-Id` state and expose the standard MCP headers for browser
  callers.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding raw direct JSON notification-only CORS
  coverage.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `edfcdcd` (`test: cover mcp direct json notification cors`) was
  pushed to both configured remotes on 2026-05-12.
- GitHub `CI` run `25761942671` completed successfully for `edfcdcd` with
  `Fast Checks` and `Full Verify` green.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, hosted CI logs clean,
  and a clean relevant Dart package publish dry-run. The latest package dry-run
  remains relevant from `aa33384` because no publish-sensitive paths changed
  after that commit.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `edfcdcd`.
The only remaining strict-audit gaps are operator-side release-hardening items.
