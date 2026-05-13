# Exec Plan: MCP Consumer Direct JSON Ping CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Prove browser-style router-hosted MCP consumers can probe public and
bearer-protected MCP routes with `ping` over both lifecycle-free direct JSON
and stateful Streamable HTTP CORS paths.

## Scope

- Add direct JSON router support for `ping` without requiring Streamable HTTP
  session initialization.
- Extend the generated neutral consumer package smoke so public and protected
  MCP routes validate direct JSON `ping`, direct JSON batch `ping`,
  Streamable POST/SSE `ping`, and Streamable batch `ping`.
- Keep private downstream application names and local paths out of checked-in
  docs and generated package metadata.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-direct-json-ping-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- The previous direct JSON tool-call alias CORS smoke remains complete and
  hosted clean at branch checkpoint `5e9647b`.

## Plan

1. Add `ping` to the router direct JSON method classifier and dispatcher.
2. Extend the generated consumer package CORS smoke to verify direct JSON and
   Streamable `ping` on public and bearer-protected routes.
3. Run the focused generated consumer package smoke, then full local
   verification before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-13.
- First focused generated consumer package smoke failed because direct JSON
  `ping` was still routed through the initialized MCP server path instead of
  the lifecycle-free direct JSON dispatcher.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after adding the router direct JSON `ping` classifier
  and dispatcher support.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `e156708` (`mcp: support direct json ping`) was pushed to both
  configured remotes.
- GitHub `CI` run `25771050652` completed successfully for `e156708` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25771050659` completed successfully
  for `e156708`.
- GitHub `Dart Package Publish Dry Run` run `25771050658` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant
  Dart package publish dry-run.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
  is not visible in GitHub Packages.

## Decision Log

- 2026-05-13: Chose this slice because raw direct JSON CORS coverage already
  proved catalog, tool calls, resources, prompts, WAMP metadata, pub/sub, and
  error paths, but endpoint liveness probing via `ping` was only covered by
  client helper tests and initialized Streamable semantics.

## Handoff

Implementation is pushed. Focused local smoke, full local verification, hosted
CI, WAMP benchmark workflow, package publish dry-run, hosted CI log scan, and
the non-strict deployment-chain audit are clean for `e156708`.
