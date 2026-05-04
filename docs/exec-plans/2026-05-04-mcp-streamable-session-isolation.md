# Exec Plan: MCP Streamable Session Isolation

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Prove router-hosted MCP Streamable HTTP session IDs are bound to the
authenticated route principal and route path, so a consumer application cannot
reuse another bearer principal's MCP session ID or carry a secure session ID
onto a public route.

## Scope

In scope:

- Add a focused router integration regression for secure Streamable MCP session
  reuse attempts across bearer principals.
- Cover public-route reuse attempts with the same MCP session ID.
- Verify failed cross-principal GET/POST/DELETE attempts do not invalidate the
  original secure MCP session.

Out of scope:

- New auth provider behavior.
- New MCP transport semantics.
- Private downstream application references.

## Plan

1. Extend the MCP smoke ticket fixture with a second neutral member principal.
2. Initialize a bearer-protected Streamable MCP session as the first principal.
3. Assert the same `MCP-Session-Id` is rejected for POST, GET, and DELETE when
   presented by the second principal.
4. Assert the same `MCP-Session-Id` is rejected on the public route.
5. Confirm the original secure session still lists MCP tools and can be deleted
   normally.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused regression passed on 2026-05-04:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "isolates MCP Streamable HTTP sessions by route and bearer principal"`.
- Additional focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_router` and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
- Full local `bin/verify` passed on 2026-05-04.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
evidence are still pending.
