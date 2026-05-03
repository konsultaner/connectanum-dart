# Exec Plan: MCP Participant Meta Scope

Status: locally complete; hosted evidence pending
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Finish the router-hosted MCP direct JSON meta API scoping so participant
metadata cannot leak service/internal session ids through registration or
subscription meta calls.

## Scope

- Scope `wamp.registration.list_callees` and
  `wamp.registration.count_callees` to sessions visible to the current MCP
  route session.
- Scope `wamp.subscription.list_subscribers` and
  `wamp.subscription.count_subscribers` the same way.
- Extend the native MCP smoke fixture with service-side callees/subscribers so
  public and bearer-authenticated routes prove they can see their own route
  subscriber session while not seeing the fixture service session.
- Keep registration/subscription discovery and details visible only through
  the existing route authorizer.

## Progress

- 2026-05-03: Added failing native MCP smoke assertions showing public direct
  JSON `wamp.registration.list_callees` exposed the internal service session id.
- 2026-05-03: Scoped registration callee and subscription subscriber meta
  lists/counts through the same visible-session set already used by
  `wamp.session.count/list/get`.
- 2026-05-03: Focused checks passed:
  `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`,
  `dart test packages/connectanum_client/test/mcp -r expanded`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
  `bash -n bin/test-fast bin/test-all`, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the participant meta scope
  and Streamable HTTP client package-boundary move.

## Decision Log

- 2026-05-03: Registration and subscription meta remain discoverable according
  to route authorization, but attached peer session ids are treated as session
  metadata and are therefore scoped to the route's visible session set.

## Handoff

Pending commit, push, and hosted GitHub evidence.
