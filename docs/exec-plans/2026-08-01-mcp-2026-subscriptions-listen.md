# Exec Plan: MCP 2026 Request-Scoped Subscriptions

## Status

Complete.

## Goal

Make router-hosted MCP and the public Dart IO client support the
`2026-07-28` `subscriptions/listen` lifecycle over request-scoped SSE, including
resource-update delivery, tool-list change delivery, transport-close
cancellation, cleanup, and truthful `server/discover` capabilities.

## Scope

- Add a typed public client listener that sends one modern
  `subscriptions/listen` POST, waits for the required acknowledgment, validates
  subscription correlation metadata, streams matching notifications, and
  exposes local, graceful, and remote close outcomes.
- Cancel HTTP listeners by closing their individual response streams. Do not
  send `notifications/cancelled`, create an MCP session, retain an SSE replay
  cursor, or reconnect automatically.
- Add router request-scoped listener ownership independent of the existing
  `2025-*` session endpoint, including multiple concurrent listeners even when
  JSON-RPC request IDs repeat on separate HTTP streams.
- Reuse configured WAMP resource update topics with shared per-principal
  subscriptions and reference-counted cleanup. Deliver only explicitly granted
  notification types and tag every notification with the originating listen
  request ID.
- Acknowledge supported subsets of requested filters. Initially support dynamic
  tool-list changes and configured resource updates; configured prompt and
  resource catalogs remain static and therefore do not advertise list-change
  support.
- Preserve the complete legacy initialize/session/GET/resume/DELETE and
  `resources/subscribe` compatibility path unchanged.
- Extend focused tests and a neutral isolated consumer smoke so a downstream
  application proves discovery, listener acknowledgment, WAMP-backed resource
  update delivery, same-client ordinary calls, and explicit cancellation.

## Protocol Direction

- The official `2026-07-28` schema requires a `notifications` filter on
  `subscriptions/listen`; every notification type is opt-in and the server's
  first SSE message must be `notifications/subscriptions/acknowledged` with the
  supported subset.
- Every acknowledgment, delivered notification, and graceful completion result
  is correlated through `io.modelcontextprotocol/subscriptionId`, whose value
  is the original JSON-RPC request ID.
- HTTP cancellation is the client closing that request's SSE response. The
  server stops delivery and releases WAMP subscriptions when the transport is
  observed closed. There is no `Last-Event-ID` replay or protocol session state.
- A deliberate server shutdown sends the empty complete result for the listen
  request before closing the stream. An EOF without that result is an
  unexpected remote close and callers decide whether to listen again.

Primary MCP references:

- <https://modelcontextprotocol.io/specification/2026-07-28/schema>
- <https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http>
- <https://modelcontextprotocol.io/seps/2575-stateless-mcp>

## Non-Goals

- Add replay or automatic reconnect semantics to modern listeners.
- Replace or remove legacy Streamable HTTP resource subscriptions.
- Claim prompt/resource catalog list-change support without a mutable catalog
  source that can produce those changes.
- Implement MRTR, Tasks, cache metadata, or unrelated MCP extensions.
- Add a new native FFI ABI when the existing incremental HTTP response stream
  already provides the required transport primitive.

## Verification

- Focused client listener acknowledgment, notification, protocol-validation,
  graceful-close, remote-close, and local cancellation regressions.
- Focused router discovery, filter, multiple-listener, WAMP resource-update,
  authorization, and cancellation cleanup regressions.
- Public IO entrypoint and isolated consumer-package boundary checks.
- Real native router-hosted public and protected listener smoke.
- `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected from the completed stateless-core handoff and both
  roadmaps. Official schema, transport, and SEP research confirmed the
  request-scoped acknowledgment/correlation/cancellation contract above.
- 2026-08-01: Pre-change `bin/test-fast` passed, including workspace analysis,
  package tests, isolated consumers, the live WAMP benchmark integration, and
  every maintained router-hosted MCP smoke.
- 2026-08-01: Added the public listener/filter/close API with a dedicated HTTP
  client per active stream, incremental SSE parsing, acknowledgment/subset and
  correlation validation, explicit local/graceful/remote outcomes, and modern
  direct-JSON `Accept` compatibility.
- 2026-08-01: Added router request-scoped SSE listeners with truthful discovery,
  supported-subset acknowledgment, tool-list and configured-resource delivery,
  shared WAMP subscriptions, concurrent preparation reservations, heartbeats,
  graceful shutdown, and transport-failure cleanup.
- 2026-08-01: Focused VM and native tests pass for malformed filters,
  notification validation, concurrent listeners, public resource updates,
  bearer-neutral route behavior, same-client calls, and WAMP subscriber
  cleanup. The isolated public consumer package smoke passes for anonymous and
  bearer-authenticated listeners and records `subscriptionsListen` evidence.
- 2026-08-01: Post-change `bin/test-fast` passed, including workspace analysis,
  all package tests, consumer-package boundaries, the live WAMP benchmark
  integration, and maintained router-hosted MCP smokes.
- 2026-08-01: Full `bin/verify` passed, including Rust core and FFI suites,
  workspace formatting and analysis, 360 core tests, 185 client tests, 92 MCP
  tests, 96 benchmark tests, 380 router tests, isolated and globally activated
  consumer smokes, native zero-copy checks, and Chrome/Dart2Wasm coverage.
