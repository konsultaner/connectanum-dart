# Exec Plan: Router-Hosted MCP Resource Subscriptions

## Status

Complete.

## Goal

Let a consumer application read explicitly configured dynamic MCP resources
through a router-hosted WAMP procedure and receive Streamable HTTP
`notifications/resources/updated` messages when an explicitly mapped WAMP
topic says that resource should be read again.

## Scope

- Add transport-neutral `resources/subscribe` and `resources/unsubscribe`
  dispatch hooks to `McpServer`, with capability advertisement only when both
  lifecycle handlers are available.
- Add typed `McpStreamableHttpClient` helpers for resource subscribe and
  unsubscribe requests while keeping direct JSON helpers lifecycle-free.
- Extend configured router-hosted resources with explicit
  `read_procedure`/`readProcedure` and `update_topic`/`updateTopic` mappings.
- Pass the resource URI as the dynamic read procedure's first positional WAMP
  argument and return the final result as lossless JSON resource text.
- Authorize each delegated read and update-topic subscription through the
  route's authenticated WAMP principal.
- Scope WAMP update subscriptions to one MCP HTTP session, make duplicate
  subscribe/unsubscribe requests safe, and clean them up on session deletion.
- Queue `notifications/resources/updated` over the existing resumable SSE
  event path; update events carry the configured MCP resource URI and require
  the consumer to read the resource again.
- Prove package-local protocol behavior, public client API behavior, route
  option validation, native router delivery/unsubscribe/cleanup, and isolated
  consumer usability.

## Protocol Direction

- Resource subscription is an optional server resource capability and is
  available only for route-configured resources with an explicit update topic.
- Resource updates remain notifications rather than event-payload projection.
  WAMP event arguments are not trusted as MCP resource contents; the consumer
  re-reads the configured procedure-backed resource after notification.
- Direct JSON requests remain stateless catalog/read access and reject
  subscription lifecycle methods because there is no Streamable HTTP session
  to own server-push delivery or cleanup.
- Automatic resource discovery and application-data projection remain outside
  this slice. Operators choose every resource URI, read procedure, and update
  topic explicitly.

Primary MCP references:

- <https://modelcontextprotocol.io/specification/2025-11-25/schema>
- <https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle>

## Non-Goals

- Infer resources or update topics from live WAMP registrations.
- Embed WAMP event payloads directly in MCP update notifications.
- Add prompt completion, sampling, elicitation, or task support.
- Provide a persistent background resource cache.

## Verification

- Focused `connectanum_mcp` resource subscription regressions
- Focused `McpStreamableHttpClient` request/validation regressions
- Router option validation regressions
- Native router-hosted dynamic read and SSE update smoke
- Isolated MCP client/full consumer package smokes
- `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected this as the next concrete downstream-application MCP
  readiness slice after same-session HTTP-auth refresh completed. The existing
  router endpoint already owns authorized WAMP subscriptions, resumable SSE
  notification queues, and session-disposal cleanup; this plan adds an explicit
  resource mapping without introducing a second delivery channel.
- 2026-08-01: Pre-change `bin/test-fast` passed, including analysis, package
  tests, native integration shards, benchmark regressions, package activation,
  and router-hosted MCP consumer smokes.
- 2026-08-01: `McpServer` now validates paired resource-subscription handlers,
  advertises `resources.subscribe` only when both lifecycle callbacks exist,
  and dispatches validated absolute resource URIs. The Streamable HTTP client
  exposes typed subscribe/unsubscribe helpers without adding a sessionless
  direct-JSON shortcut.
- 2026-08-01: Router resource options now accept explicit
  `read_procedure`/`readProcedure` and `update_topic`/`updateTopic` mappings.
  Dynamic reads and WAMP update subscriptions use the route principal's call
  and subscribe permissions, direct JSON remains lifecycle-free, duplicate
  subscriptions are safe, pending URI updates coalesce, and DELETE/disposal
  releases the underlying WAMP subscription.
- 2026-08-01: Focused server, client, router-option, native delivery,
  authorization, unsubscribe, cleanup, and public IO-entrypoint regressions
  passed. Isolated server-only, client-only, and full consumer package smokes,
  workspace analysis, shell validation, and `git diff --check` also passed.
- 2026-08-01: Post-change `bin/test-fast` and complete local `bin/verify`
  passed. The full verifier covered formatting, 113 Rust core tests, 52 FFI
  tests, 360 core Dart tests, 91 MCP package tests, 178 client MCP tests, all
  96 benchmark tests, the complete 379-test router suite, isolated and globally
  activated package consumers, 13 focused native-router tests, and
  Chrome/Dart2Wasm.
