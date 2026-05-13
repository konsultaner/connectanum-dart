# Exec Plan: MCP Consumer Streamable WAMP Batch CORS Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Prove browser-style router-hosted MCP consumers can use raw Streamable HTTP
JSON-RPC batches over CORS for router-provided WAMP API metadata and pub/sub
tools on both public and bearer-protected MCP routes.

## Scope

- Extend the neutral generated consumer package smoke for public and
  bearer-protected MCP routes.
- Cover raw Streamable HTTP batch `tools/call` requests for WAMP API list and
  describe helpers, including a missing-entry MCP tool-result error.
- Cover raw Streamable HTTP batch `tools/call` requests for pub/sub subscribe,
  publish, poll, and unsubscribe helpers, including an unknown-handle MCP
  tool-result error.
- Validate CORS, Streamable session headers, and SSE batch responses on the
  same public and bearer-protected routes a consumer application would use.
- Keep private downstream application names and local paths out of docs and
  generated package metadata.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-cors-smoke.md`
- `docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-batch-cors-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` must be clean.
- Native router smoke support must be available locally, or the smoke must skip
  native router startup through the existing package hook path.

## Plan

1. Add raw JSON-RPC batch request helpers for Streamable HTTP POST/SSE
   responses in the generated consumer package smoke.
2. Add batch WAMP API metadata assertions for list, procedure describe, topic
   describe, and missing-entry tool-result errors.
3. Add batch pub/sub assertions for subscribe, service-side event delivery,
   publish acknowledgement, poll, unsubscribe, and unknown-handle tool-result
   errors.
4. Run focused consumer smoke and full local verification before handoff.

## Verification

- Initial pre-change `bin/test-fast` on 2026-05-13 hit a transient
  non-completion in
  `packages/connectanum_bench/test/wamp_transport_integration_test.dart`
  (`native WebSocket MsgPack cancel-cycle control workload runs against a real
  router`); focused rerun of that test passed.
- Second pre-change `bin/test-fast` passed on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- Focused
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
  passed on 2026-05-13 after adding raw Streamable WAMP batch CORS coverage.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `654e8a9` (`test: cover mcp streamable wamp batch cors`) was pushed
  to both configured remotes on 2026-05-13.
- GitHub `CI` run `25767908996` completed successfully for `654e8a9` with
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

- 2026-05-13: Kept this as generated consumer package smoke coverage because
  the router-hosted MCP endpoint already serves the WAMP API and pub/sub tools;
  the missing evidence was raw browser-compatible JSON-RPC batch behavior
  across public and bearer-protected routes.
- 2026-05-13: Batch requests intentionally use no `Mcp-Method` or `Mcp-Name`
  request header because a JSON-RPC batch has no single method or name to
  summarize; the smoke validates CORS and Streamable session behavior through
  HTTP response headers and SSE batch payload parsing.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `654e8a9`.
The only remaining strict-audit gaps are operator-side release-hardening items.
