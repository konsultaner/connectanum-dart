# Exec Plan: MCP Router Direct Resource/Prompt Helper Smoke

Status: complete; hosted CI/log/dry-run evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

The router-hosted MCP public example already demonstrates direct JSON resource
and prompt operations, but those happy-path calls still use the generic
Streamable helper API with `directJson: true`. Consumer applications should be
able to copy the dedicated direct resource/prompt helper calls when they do not
want Streamable HTTP session state.

## Scope

- Move the example's direct resource and prompt happy paths to
  `listResourcesDirect`, `readResourceDirect`, and `getPromptDirect`.
- Move the direct pub/sub queue-overflow path to dedicated direct pub/sub
  helpers while preserving the shared Streamable coverage path.
- Preserve raw direct JSON batch/error-shape coverage where the example is
  intentionally proving JSON-RPC envelopes.

## Non-Goals

- Changing MCP route behavior or wire protocol semantics.
- Removing the generic helpers with `directJson: true`.
- Changing generated consumer-package smoke semantics.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Public router-hosted MCP example direct resource/prompt happy paths now use
  dedicated direct helper APIs.
- Direct pub/sub queue-overflow subscribe/unsubscribe paths now use dedicated
  direct helper APIs while preserving the shared Streamable path.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `dart format packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`
  passed on 2026-05-13.
- `git diff --check` passed on 2026-05-13.
- `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `4b87d11` (`mcp: use direct resource helpers in router example`) was
  pushed to both configured remotes.
- GitHub `CI` run `25789834356` completed successfully for `4b87d11` with
  `Fast Checks` and `Full Verify` green.
- GitHub `WAMP Profile Benchmarks` run `25789834286` completed successfully
  for `4b87d11`.
- GitHub `Dart Package Publish Dry Run` run `25789834310` completed
  successfully and covers the checked-out head.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed with clean latest CI, clean hosted CI logs, and a clean relevant Dart
  package publish dry-run.
- `bin/audit-github-deployment-chain --branch add-router --strict --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed the hosted CI, hosted CI log scan, and package dry-run checks, then
  failed only known operator-side release-hardening gaps: protected release
  branches do not require `Fast Checks` and `Full Verify`, and
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API. The audit also continues to report that the
  router GHCR package is not visible.

## Decision Log

- Public examples should favor dedicated direct helper methods for
  lifecycle-free direct JSON happy paths. Raw `post`/`request` calls remain
  appropriate where the smoke intentionally verifies raw JSON-RPC envelopes,
  batch isolation, or error response shape.

## Handoff

Implementation is pushed. Focused local checks, full local verification,
hosted CI, WAMP benchmark workflow, package publish dry-run, hosted CI log
scan, and the non-strict deployment-chain audit are clean for `4b87d11`.
