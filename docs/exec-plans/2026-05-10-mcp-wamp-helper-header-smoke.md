# Exec Plan: MCP WAMP Helper Header Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Context

Typed MCP helpers for ping, tools, direct JSON tool/meta access, resources, and
prompts already accept per-call consumer headers. The WAMP API, WAMP meta, and
pub/sub convenience helpers should expose the same surface so downstream
applications can attach trace, routing, or short-lived auth metadata without
dropping to generic JSON-RPC calls.

This plan keeps the helper API backward-compatible and proves that helper-level
headers work for initialized Streamable HTTP sessions and lifecycle-free direct
JSON calls.

## Implementation Plan

1. Add optional `headers` parameters to the WAMP helper extension methods:
   API list/describe, generic WAMP meta calls, standard WAMP meta convenience
   helpers, and WAMP pub/sub subscribe/publish/poll/unsubscribe helpers.
2. Forward those headers through the shared `_callStructuredTool(...)` helper
   into either Streamable `tools/call` or direct JSON
   `connectanum.tool.call`.
3. Extend focused client tests to assert Streamable WAMP helper headers are
   sent with the active MCP session and direct JSON helper headers are sent
   without `MCP-Session-Id`.
4. Extend the `connectanum_mcp` IO entrypoint test so the re-exported WAMP
   helper API compiles and forwards headers for API, meta, and pub/sub helpers.
5. Extend generated neutral package smokes and the router-hosted MCP public
   example so consumer code exercises WAMP helper headers against fake and
   router-hosted endpoints.
6. Run focused tests, generated package smokes, `bin/test-fast`, and
   `bin/verify`.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- `dart format packages/connectanum_client/lib/src/mcp/wamp_tools.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_mcp/test/io_client_export_test.dart packages/connectanum_router/example/router_hosted_mcp.dart` completed cleanly.
- `bash -n bin/common.sh` passed.
- Focused `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart` passed.
- Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed.
- Focused `run_mcp_client_package_smoke` passed.
- Focused `run_mcp_consumer_package_smoke` passed.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.
- Commit `b60bd77` (`test: cover mcp wamp helper headers`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-10.
- GitHub `CI` run `25625714931` completed successfully for `b60bd77` with
  `Fast Checks` and `Full Verify` green.
- GitHub `Dart Package Publish Dry Run` run `25625714942` completed
  successfully for `b60bd77`; the deployment-chain audit confirmed the dry run
  covers the checked-out head.
- GitHub `WAMP Profile Benchmarks` run `25625714945` completed successfully for
  `b60bd77`.
- Deployment-chain audit passed on 2026-05-10 with clean latest CI and clean
  Dart package publish dry-run evidence.
- Strict deployment-chain audit still reports only known operator-side
  release-hardening gaps: branch protection/required status checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and
  `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
- A final local `bin/verify` rerun after hosted-evidence notes also passed on
  2026-05-10.

## Decision Log

- Keep WAMP helper headers as optional per-call maps matching the existing
  generic request and typed MCP helper surface.
- Forward headers through the shared WAMP helper dispatch function instead of
  duplicating Streamable/direct JSON branching in each helper.

## Handoff

Implementation, full local verification, push, and hosted CI/deployment-chain
evidence are complete. Strict audit gaps remain operator-side release-hardening
work.
