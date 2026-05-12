# Exec Plan: MCP Consumer Direct JSON Error CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-style router-hosted MCP consumers can observe direct JSON-RPC
error responses over CORS across tool calls, resources, prompts, WAMP API
metadata, and pub/sub helpers without entering the Streamable HTTP session
lifecycle.

## Scope

- Extend the neutral generated consumer package smoke for public and
  bearer-protected MCP routes.
- Cover direct JSON JSON-RPC errors for missing tools, resources, and prompts.
- Cover direct JSON MCP tool-result errors for missing WAMP API entries and
  unknown pub/sub handles.
- Cover mixed direct JSON batches that combine successful responses,
  JSON-RPC errors, MCP tool-result errors, and a notification.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-12-mcp-consumer-direct-json-error-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- Native router smoke support must be available locally, or the smoke must skip
  native router startup through the existing package hook path.

## Plan

1. Add raw direct JSON CORS checks for single request error payloads and MCP
   tool-result errors.
2. Add raw direct JSON CORS checks for mixed error batches and recovery
   responses.
3. Run focused consumer smoke and full local verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12 after adding direct JSON error CORS coverage.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `74b86c0` (`test: cover mcp direct json error cors`) was pushed to
  both configured remotes on 2026-05-12.
- GitHub `CI` run `25763989367` completed successfully for `74b86c0` with
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

## Decision Log

- 2026-05-12: Kept this as smoke harness coverage rather than a router code
  change because the existing direct JSON endpoints already return the correct
  error classes; the gap was downstream browser-consumer evidence across
  public and bearer-protected routes.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `74b86c0`.
The only remaining strict-audit gaps are operator-side release-hardening items.
