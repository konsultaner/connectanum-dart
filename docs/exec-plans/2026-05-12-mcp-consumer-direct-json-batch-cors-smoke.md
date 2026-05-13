# Exec Plan: MCP Consumer Direct JSON Batch CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can use batched direct JSON-RPC
requests over CORS without entering the Streamable HTTP session lifecycle.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes return CORS-readable JSON-RPC batch responses.
- Cover batched direct JSON catalog, API-description, resource, prompt, and
  pub/sub calls through raw browser-style requests.
- Keep asserting that direct JSON CORS batches do not create or mutate
  Streamable HTTP session state.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding raw direct JSON batch CORS coverage.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `4eb6376` (`test: cover mcp direct json batch cors`) was pushed to
  both configured remotes on 2026-05-12.
- GitHub `CI` run `25759765256` completed successfully for `4eb6376` with
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
log scan, and the non-strict deployment-chain audit are clean for `4eb6376`.
The only remaining strict-audit gaps are operator-side release-hardening items.
