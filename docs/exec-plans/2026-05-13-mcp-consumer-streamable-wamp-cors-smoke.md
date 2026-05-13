# Exec Plan: MCP Consumer Streamable WAMP CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Prove browser-style router-hosted MCP consumers can use Streamable HTTP
`tools/call` requests over CORS for router-provided WAMP API metadata and
pub/sub helpers on both public and bearer-protected MCP routes.

## Scope

- Extend the neutral generated consumer package smoke for public and
  bearer-protected MCP routes.
- Cover Streamable HTTP WAMP API list and describe tool calls over raw
  POST/SSE responses.
- Cover Streamable HTTP pub/sub subscribe, publish, poll, and unsubscribe tool
  calls over raw POST/SSE responses.
- Cover Streamable HTTP MCP tool-result errors for missing WAMP API entries and
  unknown pub/sub handles.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- Native router smoke support must be available locally, or the smoke must skip
  native router startup through the existing package hook path.

## Plan

1. Reuse the raw Streamable HTTP POST/SSE helper path for MCP `tools/call`
   requests.
2. Add raw Streamable CORS checks for WAMP API metadata tool success and
   missing-entry tool-result errors.
3. Add raw Streamable CORS checks for pub/sub subscribe, publish, poll, and
   unsubscribe success plus unknown-handle tool-result errors.
4. Run focused consumer smoke and full local verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after adding Streamable WAMP CORS coverage.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `cc2640d` (`test: cover mcp streamable wamp cors`) was pushed to
  both configured remotes on 2026-05-13.
- GitHub `CI` run `25765942692` completed successfully for `cc2640d` with
  `Fast Checks` and `Full Verify` green.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-13. The audit found latest CI clean, hosted CI logs clean,
  and a clean relevant Dart package publish dry-run. The latest package dry-run
  remains relevant from `aa33384` because no publish-sensitive paths changed
  after that commit.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Decision Log

- 2026-05-13: Kept this as smoke harness coverage rather than a router code
  change because the router-hosted MCP endpoint already exposes the WAMP API
  and pub/sub tools; the gap was raw browser-compatible Streamable HTTP CORS
  evidence across public and bearer-protected routes.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `cc2640d`.
The only remaining strict-audit gaps are operator-side release-hardening items.
