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

## 0.1.0

- Initial modular release of the Connectanum router package, including the
  native transport runtime bindings, router CLI, configurable HTTP routes,
  authentication providers, OpenMetrics support, and router-hosted MCP
  integration.
