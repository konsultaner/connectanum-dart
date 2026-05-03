# Exec Plan: Router MCP POST SSE Responses

Status: completed
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Close the remaining router-hosted MCP Streamable HTTP compatibility gap by
supporting request-scoped SSE response streams for stateful MCP `POST`
requests, without regressing direct JSON clients or the router-authenticated
session model.

## Scope

- Keep MCP hosted by router `type: mcp` HTTP routes.
- Use the existing route-authenticated WAMP principal and MCP HTTP session key.
- Keep `initialize` responses and JSON-only `POST` clients on the existing JSON
  response path.
- For stateful operation `POST` requests that advertise Streamable HTTP
  (`Accept: application/json, text/event-stream`), return an SSE response stream
  with a primer event and exactly one JSON-RPC response event for the request.
- Commit POST/SSE response events into the same bounded session history used by
  GET/SSE so `Last-Event-ID` can replay a request response event after a primer
  cursor without replaying unrelated messages.
- Preserve an explicit route option escape hatch for JSON-only POST responses.
- Add native router integration coverage for POST/SSE responses, resumable
  replay from the primer event, and JSON-only direct response compatibility.

## Verification

- `bin/test-fast`
- `dart analyze packages/connectanum_router packages/connectanum_mcp`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
- `dart test packages/connectanum_mcp -r expanded`
- `git diff --check`
- `bin/verify`
- Hosted GitHub Actions and deployment-chain audit after push

## Progress

- 2026-05-03: Started on top of `eb3d9e6` after the hosted deployment-chain
  evidence for router MCP SSE resumability was clean and a fresh pre-change
  `bin/test-fast` passed locally.
- 2026-05-03: Implemented automatic POST/SSE responses for stateful
  non-`initialize` MCP operation requests that opt into Streamable HTTP.
  JSON-only clients continue to receive JSON responses, and `initialize`
  remains JSON for straightforward session negotiation.
- 2026-05-03: Added native router integration coverage for POST/SSE response
  streams, primer-event replay via GET/SSE `Last-Event-ID`, and JSON-only
  request compatibility. Focused `dart analyze packages/connectanum_router
  packages/connectanum_mcp`, `dart test
  packages/connectanum_router/test/router_integration_native_test.dart -r
  expanded --name "MCP"`, `dart test packages/connectanum_mcp -r expanded`,
  and `git diff --check` passed.
- 2026-05-03: Full local `bin/verify` passed after the POST/SSE response
  implementation and docs updates. It included formatting, Rust native/FFI
  tests, Python package-artifact checks, MCP package tests, client/native
  tests, auth-server tests, bench integration tests, full router package tests
  including the updated MCP Streamable HTTP regression, zero-copy router
  checks, and Chrome Dart2Wasm WebSocket transport tests.
- 2026-05-03: Pushed commit `a84dcea`
  (`mcp: stream stateful post responses over sse`) to GitLab and GitHub.
  Hosted GitHub evidence is clean: `CI` run `25281129199`, `WAMP Profile
  Benchmarks` run `25281129184`, and `Dart Package Publish Dry Run` run
  `25281129192` all completed successfully. The strict add-router
  deployment-chain audit passed with a clean CI job set, clean CI log scan,
  clean relevant Dart package dry-run, and the existing Native Artifacts
  dry-run `25192553399` still relevant because no native-release-sensitive
  paths changed.

## Decision Log

- 2026-05-03: POST/SSE is automatic only for stateful operation requests that
  advertise the Streamable HTTP contract by accepting both JSON and SSE.
  `initialize` stays JSON so clients can read the negotiated session headers and
  result body without opening a response stream, and direct JSON clients can
  still force JSON by sending `Accept: application/json`.
- 2026-05-03: POST/SSE response events use the same bounded per-endpoint
  history as GET/SSE. That keeps resume behavior session-scoped and avoids a
  separate one-off stream store.

## Handoff

Complete. Remaining MCP work should be driven by concrete consumer integration
gaps after this Streamable HTTP session, GET/SSE, resume, and POST/SSE response
path.
