# Exec Plan: MCP Router Direct Resource/Prompt Helper Smoke

Status: implementation complete; local verification clean; push/hosted evidence pending
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

## Decision Log

- Public examples should favor dedicated direct helper methods for
  lifecycle-free direct JSON happy paths. Raw `post`/`request` calls remain
  appropriate where the smoke intentionally verifies raw JSON-RPC envelopes,
  batch isolation, or error response shape.

## Handoff

Implementation is locally verified and ready to push. After pushing, collect
hosted CI, package dry-run, log-scan, and strict audit evidence.
