# Exec Plan: MCP Consumer CORS Method Negotiation Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can negotiate Streamable HTTP
methods through CORS and can read method/`Accept` negotiation failures without
creating MCP session state.

## Scope

- Extend the neutral generated consumer package smoke so MCP CORS preflight is
  checked for `POST`, `GET`, and `DELETE`, not only the first direct JSON POST
  path.
- Add raw public and bearer-protected CORS checks for unsupported HTTP methods
  and invalid `Accept` headers, asserting readable JSON errors, `Allow` header
  coverage, and no accidental Streamable session state.
- Keep the existing disallowed-origin and secure missing-bearer checks intact.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after the implementation.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `636a773` (`test: cover mcp cors method negotiation`) was pushed to
  both configured remotes on 2026-05-12.
- GitHub Actions `CI` run `25749366742` passed on `636a773`: `Fast Checks` and
  `Full Verify` completed successfully, and the hosted CI log scan was clean.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, latest CI log scan
  clean, and a clean relevant Dart package publish dry-run. The publish dry-run
  remains relevant from `59a8e79` because no publish-sensitive paths changed.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `636a773`.
The only remaining strict-audit gaps are operator-side release-hardening items.
