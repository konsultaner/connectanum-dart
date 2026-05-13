# Exec Plan: MCP Router Direct Helper Example Smoke

Status: implementation complete; local verification clean; push/hosted evidence pending
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

The router-hosted MCP public example already proves direct JSON WAMP meta and
pub/sub behavior, but some example paths still use the generic Streamable
helper API with `directJson: true`. Consumer applications should be able to copy
the dedicated direct helper calls directly when they do not want Streamable
HTTP session state.

## Scope

- Move the example's direct WAMP API/topic metadata checks to
  `listWampApiDirect` and `describeWampApiDirect`.
- Move the example's direct pub/sub happy path to
  `subscribeWampTopicDirect`, `publishWampEventDirect`,
  `pollWampEventsDirect`, and `unsubscribeWampTopicDirect`.
- Preserve existing Streamable helper coverage and batch compatibility checks.

## Non-Goals

- Changing MCP route behavior or wire protocol semantics.
- Removing the generic helpers with `directJson: true`.
- Changing generated consumer-package smoke semantics.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Public router-hosted MCP example direct WAMP metadata and pub/sub paths now
  use dedicated direct helper APIs.

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

## Decision Log

- Public examples should favor dedicated direct helper methods when they are
  demonstrating lifecycle-free direct JSON usage. The generic `directJson: true`
  flag remains supported for callers that need one code path for both modes.

## Handoff

Implementation is locally verified and ready to push. After pushing, collect
hosted CI, package dry-run, log-scan, and strict audit evidence.
