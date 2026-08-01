# Exec Plan: MCP 2026 Stateless Core Compatibility

## Status

Completed.

## Goal

Make router-hosted MCP and the public Dart HTTP client interoperate with the
`2026-07-28` stateless protocol core for discovery and ordinary tool, resource,
and prompt requests while preserving the existing `2025-*` Streamable HTTP
session implementation unchanged.

## Scope

- Add `2026-07-28` as a distinct supported protocol era rather than treating it
  as another initialize-negotiated session version.
- Add public client identity/capability metadata and a typed `server/discover`
  helper.
- For `2026-07-28`, attach the required
  `_meta.io.modelcontextprotocol/*` request envelope, mirror the protocol
  version into the HTTP header, omit session/resume headers, and keep each
  ordinary request usable without `initialize`.
- Make the router validate the modern protocol header against request `_meta`,
  require one JSON-RPC message per POST, reject modern GET/DELETE traffic, and
  return modern protocol errors without minting a session.
- Serve authenticated `server/discover` plus existing tool, resource, prompt,
  direct JSON/meta, and WAMP-backed operations through the route principal.
- Stamp modern successful results with `resultType: complete` and server-info
  metadata while retaining legacy response shapes for `2025-*` clients.
- Prove the public client against a real router endpoint from an isolated
  consumer package, including protected requests and absence of
  `Mcp-Session-Id` / `Last-Event-ID` state.

## Protocol Direction

- `2026-07-28` removes `initialize`, protocol-level sessions, standalone GET,
  DELETE session termination, and `Last-Event-ID` replay. Those mechanisms
  remain available only when a client explicitly uses a supported `2025-*`
  revision.
- Every modern request is self-contained: protocol version, client identity,
  and client capabilities travel in request `params._meta`; HTTP headers mirror
  the method, name, and protocol version and must match the body.
- `server/discover` advertises the modern version and the route-filtered server
  capabilities. Authorization still applies independently to every request.
- `subscriptions/listen`, request-scoped SSE cancellation, MRTR, and modern
  cache metadata are follow-up milestones. This slice must return an honest
  method-not-found/unsupported response for unimplemented modern operations.

Primary MCP references:

- <https://modelcontextprotocol.io/specification/2026-07-28/basic/index>
- <https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning>
- <https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http>
- <https://modelcontextprotocol.io/specification/2026-07-28/server/discover>

## Non-Goals

- Remove or weaken `2025-*` Streamable HTTP session, SSE resume, resource
  subscription, or compatibility coverage.
- Implement `subscriptions/listen`, MRTR input requests, Tasks, Apps, or the
  extension framework in this first compatibility slice.
- Claim full `2026-07-28` conformance before the follow-up notification and
  request-stream work is complete.

## Verification

- Focused protocol constant and client HTTP regressions
- Focused router JSON/header/auth regressions
- Native router-hosted stateless discovery and tool/resource/prompt smoke
- Isolated public client and router CLI consumer package smokes
- Backward-compatibility regressions for `2025-*` initialize/session/poll/delete
- `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected this as the next MCP readiness milestone after rechecking
  the official specification. The stable `2026-07-28` revision replaces the
  connection/session lifecycle with per-request metadata, so durable handoff
  work for the legacy session model was deliberately not started.
- 2026-08-01: Pre-change `bin/test-fast` passed, including workspace analysis,
  package tests, isolated consumers, the live WAMP benchmark integration, and
  router-hosted MCP consumer smokes.
- 2026-08-01: Added explicit public stateless client construction, auth-grant
  construction, typed discovery, per-request metadata, modern result-type
  validation, and local guards for removed batches, GET polling, and DELETE
  session termination while keeping all default session-era constructors on
  `2025-11-25`.
- 2026-08-01: Added router request-era selection, required modern metadata and
  mirrored-header validation, reserved `HeaderMismatch` and
  `UnsupportedProtocolVersion` errors, `server/discover`, successful-result
  stamping, unknown-method HTTP 404, and suppression of protocol session and
  resume state for modern traffic. Route-filtered capability discovery does
  not advertise legacy change/subscription flags.
- 2026-08-01: Focused client, MCP-package, native-router, boundary, and real
  router CLI consumer-package tests pass. The isolated consumer proves public
  discovery/resources/tools/WAMP pub/sub and protected discovery/resources/
  tools through a real issued bearer grant, with `stateless2026` evidence and
  no private project assumptions.
- 2026-08-01: Post-change `bin/test-fast` and complete local `bin/verify`
  passed. The final verifier covered formatting (393 files), Rust core and FFI
  tests, 360 core Dart tests, 182 client tests, 92 MCP tests, 96 benchmark
  tests, 380 router tests, the Chrome/Dart2Wasm websocket test, and every
  isolated consumer and live router-hosted MCP smoke. The milestone is
  complete; `subscriptions/listen` is the next modern compatibility layer.
