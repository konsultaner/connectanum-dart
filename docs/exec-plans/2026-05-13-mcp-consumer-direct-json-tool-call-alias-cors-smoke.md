# Exec Plan: MCP Consumer Direct JSON Tool-Call Alias CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Prove browser-style router-hosted MCP consumers can call route-visible tools
through both direct JSON Connectanum tool-call method names over CORS on public
and bearer-protected MCP routes.

## Scope

- Extend the neutral generated consumer package smoke for public and
  bearer-protected MCP routes.
- Cover the plural direct JSON `connectanum.tools.call` alias in addition to
  the singular `connectanum.tool.call` method for a real route-visible WAMP
  procedure.
- Cover a direct JSON batch that mixes `connectanum.tool.call` and
  `connectanum.tools.call`, proving both method names are usable without
  entering the Streamable HTTP session lifecycle.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-batch-cors-smoke.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-direct-json-tool-call-alias-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- Native router smoke support must be available locally, or the smoke must skip
  native router startup through the existing package hook path.

## Plan

1. Add a raw direct JSON CORS assertion for `connectanum.tools.call` on the
   same route-visible WAMP procedure already used for `connectanum.tool.call`.
2. Add a raw direct JSON batch assertion that calls the same procedure through
   both singular and plural Connectanum tool-call method names.
3. Run focused consumer smoke and full local verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after adding direct JSON tool-call alias CORS coverage.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `5e9647b` (`test: cover mcp direct json tool alias cors`) was pushed
  to both configured remotes on 2026-05-13.
- GitHub `CI` run `25769429169` completed successfully for `5e9647b` with
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

- 2026-05-13: Chose this slice because raw direct JSON CORS coverage already
  proved `connectanum.tool.call`, WAMP API metadata, resources, prompts, and
  pub/sub, but browser-style consumer evidence had not yet pinned the supported
  plural `connectanum.tools.call` alias on public and bearer-protected routes.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `5e9647b`.
The only remaining strict-audit gaps are operator-side release-hardening items.
