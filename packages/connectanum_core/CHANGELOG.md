## 3.0.0-beta.1

- Move SCRAM Argon2id13 and PBKDF2 key derivation behind asynchronous native
  isolate and browser Worker implementations with cancellation, timeout,
  disposal, reconnect fencing, and unchanged wire vectors.
- Require constant-time SCRAM server-signature verification before reporting
  authentication success.
- Preserve lazy binary payload ownership across high-throughput serializers,
  native file delivery, and payload E2EE paths.

## 3.0.0-beta

- Correct standard WAMP session-closing reason URIs to `wamp.close.*` and add
  normal and administratively killed close constants.
- Join the synchronized Connectanum 3.0 beta package graph.
- Add the final WAMP wire models for progressive invocations, call timeouts,
  statistics Meta APIs, payload passthrough, and the versioned E2EE profile.
- Use UTF-8 for CRA and SCRAM authentication strings by default while retaining
  an explicit UTF-16 compatibility mode for legacy peers.
- Preserve binary SCRAM channel-binding data without an invalid byte-to-string
  cast.
- Add a public bounded RFC 6570 Level 1 MCP resource-URI-template utility with
  decoded matching and UTF-8 percent-encoded expansion.

## 0.1.0

- Initial modular release of the shared Connectanum WAMP protocol, serializer,
  authentication, payload passthrough, and E2EE primitives used by the client
  and router packages.
