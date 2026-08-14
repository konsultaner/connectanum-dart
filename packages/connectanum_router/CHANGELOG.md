# Changelog

## 3.0.0-beta

- Join the synchronized Connectanum 3.0 beta package graph.
- Complete advanced WAMP routing for progressive invocations, timeouts,
  statistics Meta APIs, lifecycle events, and router-opaque payload E2EE.
- Add production router-hosted MCP endpoints, direct JSON access, auth/session
  isolation, pub/sub, Streamable HTTP compatibility, and operational metrics.
- Add a bounded `wamp_api_list_page_size` route option for deterministic,
  authorization-filtered WAMP procedure/topic catalog pagination.
- Let router resource templates use authorized WAMP read procedures through
  standard Streamable HTTP and direct JSON resource reads.
- Let legacy and modern MCP clients subscribe to concrete URIs produced by
  readable router resource templates with authorization-safe cleanup.
- Preserve every case-insensitive native HTTP header field value on router
  requests and negotiate split `Accept` fields as one list for router-hosted
  MCP JSON/SSE and Streamable HTTP selection.
- Combine split case-insensitive `Access-Control-Request-Headers` field values
  when answering router-hosted MCP CORS preflights, preserving the complete
  browser-requested allow-list without creating MCP session state.
- Reject repeated case-insensitive `Access-Control-Request-Method` fields on
  router-hosted MCP CORS preflights before method-specific action selection,
  authentication, rate limiting, or session state.
- Reject repeated case-insensitive `Mcp-Method`, `Mcp-Name`, and
  `Mcp-Param-*` request metadata fields before router-hosted MCP catalog refresh
  or WAMP dispatch while preserving auth and session-validation precedence.
- Require a JSON-compatible `Content-Type` on every router-hosted MCP POST,
  returning HTTP 415 for untyped bodies while preserving protected-route
  authentication and compatibility-session precedence.
- Label legacy router-hosted MCP requests that omit `MCP-Protocol-Version` as
  `2025-03-26` while preserving initialize negotiation, authentication, and
  claimed-session lookup.
- Add authorization-safe cache hints to every cacheable router-hosted MCP
  `2026-07-28` complete result, enabling strict official SDK clients to validate
  discovery, catalogs, resource reads, and ordinary WAMP-backed tool use.
- Preserve router-hosted MCP sessions across HTTP-auth access and refresh-token
  rotation while continuing to reject the rotated credentials.
- Enforce positive realm `max_pending_auth` limits on router HTTP-auth
  challenges with per-realm capacity, bounded retry metadata, authenticator
  cleanup, and recovery after the occupying challenge completes or expires.
- Apply realm failed-authentication lockouts to router HTTP-auth challenges,
  including pending-transaction races, bounded retry metadata, audit events,
  identity isolation, and successful-authentication reset behavior.
- Bound shared WAMP and router HTTP-auth failure records per realm with
  `max_failed_auth_records`, fixed-size internal identity digests,
  lockout-window expiry, fail-closed admission, bounded retry metadata, and
  successful-authentication capacity release.
- Bound successful router HTTP-auth grant lineages per realm with
  `max_http_auth_grants`, fail-closed challenge admission and completion,
  secret-free capacity telemetry, refresh-at-capacity support, and
  revocation/expiry recovery.
- Make router HTTP-auth refresh-token use linearizable across overlapping
  requests, preserve grant capacity while refresh is in flight, and let
  concurrent revocation prevent successor issuance without leaking token data.
- Bound router-hosted MCP POST bodies before UTF-8 and JSON decoding with a
  configurable raw-byte limit and authenticated-route precedence.
- Bound router-hosted MCP tool and dynamic-resource WAMP calls with a
  configurable protocol-level deadline and router-driven cancellation.
- Bound complete router-hosted MCP JSON and compatibility SSE response bodies
  by exact emitted bytes before opening the HTTP response stream.
- Bound each complete modern request-scoped MCP SSE event, rejecting an
  oversized acknowledgment before stream open and isolating later overflow to
  the affected listener.
- Bound compatibility Streamable HTTP replay history by encoded SSE bytes as
  well as event count, with a configurable route ceiling and oldest-first
  eviction.
- Preserve direct JSON and Streamable WAMP pub/sub handles while dynamic WAMP
  registrations refresh the router-hosted MCP tool catalog.
- Refresh router-hosted MCP WAMP procedure and topic metadata even when the
  live catalog changes without changing any MCP tool definition.
- Revoke in-flight router-hosted MCP resource-subscription ownership when a
  newer catalog refresh removes resource visibility or update-topic subscribe
  access, so compatibility requests cannot report stale success and modern
  listeners cannot acknowledge stale resource filters.
- Revoke pending router-hosted MCP WAMP pub/sub ownership when a compatibility
  Streamable HTTP session is deleted, reject pre-dispatch stale requests, and
  keep replacement sessions free of leaked broker subscribers.
- Prevent an allowed WAMP action authorization from resuming a router-hosted
  MCP publish, call, or subscription after its Streamable session is deleted.
- Reject a compatibility GET/SSE poll when its router-hosted MCP session is
  deleted during catalog refresh, before queued notifications can be replayed.
- Prefer compatibility session deletion over a concurrent router-hosted MCP
  catalog refresh failure for both GET and POST, returning a sessionless 404
  instead of a stale backend error that advertises the removed session.
- Reject unknown, terminated, cross-route, and cross-principal Streamable HTTP
  sessions before content-type, body-size, JSON, and standard-header
  validation, returning a sessionless 404 without changing direct JSON request
  behavior.
- Resolve a claimed compatibility session before GET SSE response negotiation,
  so unknown sessions return a sessionless 404 while live sessions retain the
  normal 406 response for an incompatible `Accept` header.

## 0.1.0

- Initial modular release of the Connectanum router package, including the
  native transport runtime bindings, router CLI, configurable HTTP routes,
  authentication providers, OpenMetrics support, and router-hosted MCP
  integration.
