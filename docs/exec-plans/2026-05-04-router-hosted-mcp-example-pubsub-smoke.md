# Exec Plan: Router-Hosted MCP Example Pub/Sub Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the runnable router-hosted MCP example prove the same pub/sub helper path
that consumer applications and agents use, not only tool, resource, and prompt
access.

## Scope

In scope:

- Extend `packages/connectanum_router/example/router_hosted_mcp.dart` smoke
  coverage to subscribe, publish, poll, and unsubscribe from a router-provided
  WAMP topic.
- Prove both lifecycle-free direct JSON and initialized Streamable MCP helper
  access on the public endpoint.
- Prove the same direct JSON and Streamable MCP pub/sub helper access on the
  bearer-protected endpoint.

Out of scope:

- New MCP transport semantics.
- New auth providers or token issuance flows.
- Private downstream application references.

## Plan

1. Reuse the example's existing `example.events.task` topic declaration.
2. Add direct JSON pub/sub smoke assertions before MCP initialization.
3. Add Streamable MCP pub/sub smoke assertions after initialization.
4. Run the example smoke, focused router MCP integration smoke, and full
   workspace verification.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`,
  `dart analyze packages/connectanum_router`, and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- Full local `bin/verify` passed on 2026-05-04.

## Handoff

Implementation and local verification are complete. Hosted evidence is pending
for the implementation commit.
