## 3.0.0-beta

- Join the synchronized Connectanum 3.0 beta package graph.
- Add the final WAMP wire models for progressive invocations, call timeouts,
  statistics Meta APIs, payload passthrough, and the versioned E2EE profile.
- Use UTF-8 for CRA and SCRAM authentication strings by default while retaining
  an explicit UTF-16 compatibility mode for legacy peers.
- Preserve binary SCRAM channel-binding data without an invalid byte-to-string
  cast.

## 0.1.0

- Initial modular release of the shared Connectanum WAMP protocol, serializer,
  authentication, payload passthrough, and E2EE primitives used by the client
  and router packages.
