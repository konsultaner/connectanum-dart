# Exec Plan: MCP Consumer CORS POST Body Error Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers receive CORS-readable raw POST
body negotiation errors without accidental session creation, and that the same
errors preserve an active Streamable HTTP session after initialization.

## Scope

- Extend the neutral generated consumer package smoke so public and
  bearer-protected MCP routes reject unsupported POST `Content-Type` values
  with CORS-readable JSON errors.
- Extend the same smoke so malformed JSON POST bodies return CORS-readable
  JSON-RPC parse errors.
- Cover both lifecycle-free requests and active Streamable HTTP sessions, with
  a post-error `tools/list` recovery check for initialized sessions.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding the raw POST body error coverage.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `de467ac` (`test: cover mcp cors post body errors`) was pushed to
  both configured remotes on 2026-05-12.
- GitHub `CI` run `25754419353` completed successfully for `de467ac` with
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
log scan, and the non-strict deployment-chain audit are clean for `de467ac`.
The only remaining strict-audit gaps are operator-side release-hardening items.
