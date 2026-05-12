# Exec Plan: MCP Consumer Raw Named CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Extend the neutral consumer package smoke so a browser-like application or
agent can prove router-hosted MCP access without SDK-only assumptions. Cover
raw direct JSON tool/meta/pubsub calls with CORS response metadata, and raw
Streamable HTTP named method calls that require public `Mcp-Name` and
`Mcp-Param-*` headers.

## Scope

- Keep all checked-in examples and state neutral; use consumer/downstream
  wording only.
- Extend the generated consumer smoke in `bin/common.sh`.
- Cover both public and bearer-protected router-hosted MCP endpoints.
- Avoid product-code churn unless the smoke exposes an implementation bug.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- Focused `bash -n bin/common.sh` passed on 2026-05-12.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-12.
- Post-change `bin/test-fast` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `e2210c3` (`test: cover mcp raw named cors access`) was pushed to
  both configured remotes on 2026-05-12.
- GitHub Actions `CI` run `25742676102` passed on `e2210c3`: `Fast Checks`
  completed successfully at 2026-05-12T15:00:46Z and `Full Verify` completed
  successfully at 2026-05-12T15:07:08Z.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, latest CI log scan
  clean, and a clean relevant Dart package publish dry-run; the dry-run remains
  relevant from `e35cab0` because no publish-sensitive paths changed.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Plan

1. Add raw direct JSON CORS assertions for `connectanum.tools.list`,
   `connectanum.tool.call`, `connectanum.api.list`, and pub/sub
   subscribe/publish/poll/unsubscribe.
2. Add raw Streamable HTTP POST/SSE assertions for `tools/call`,
   `resources/read`, and `prompts/get`.
3. Assert CORS preflight allows the concrete public MCP parameter headers used
   by the raw Streamable tool call.
4. Run focused smoke, fast regression, and full verification before handoff.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `e2210c3`.
The only remaining strict-audit gaps are operator-side release-hardening items.
