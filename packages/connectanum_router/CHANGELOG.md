# Changelog

## 3.0.0-beta

- Join the synchronized Connectanum 3.0 beta package graph.
- Complete advanced WAMP routing for progressive invocations, timeouts,
  statistics Meta APIs, lifecycle events, and router-opaque payload E2EE.
- Add production router-hosted MCP endpoints, direct JSON access, auth/session
  isolation, pub/sub, Streamable HTTP compatibility, and operational metrics.
- Preserve router-hosted MCP sessions across HTTP-auth access and refresh-token
  rotation while continuing to reject the rotated credentials.
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

## 0.1.0

- Initial modular release of the Connectanum router package, including the
  native transport runtime bindings, router CLI, configurable HTTP routes,
  authentication providers, OpenMetrics support, and router-hosted MCP
  integration.
