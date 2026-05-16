# Exec Plan: HTTP Reverse Proxy Route Action

## Status

Complete locally on 2026-05-16.

## Goal

Turn the already-configurable `reverse_proxy` HTTP adapter route into a usable
runtime path for downstream applications, while keeping FastCGI as an explicit
`501 Not Implemented` adapter until its framing and process model are designed.

## Scope

- Dispatch `HttpRouteActionType.reverseProxy` before generic WAMP HTTP bridge
  handling.
- Resolve upstream targets from the existing adapter endpoint options.
- Forward buffered HTTP requests to `http` / `https` upstreams with request
  method, body, query string, route-prefix stripping, and filtered headers.
- Return upstream status, headers, and body through the native HTTP response
  path.
- Add timeout, bounded-response, and upstream-error responses with structured
  JSON bodies and access-log outcomes.
- Keep hop-by-hop headers and configured upstream URLs out of telemetry.
- Add focused runtime tests for forwarding behavior and the remaining FastCGI
  `501` stub.

## Out Of Scope

- Streaming reverse-proxy request or response bodies.
- Connection pooling across routed requests beyond `dart:io` defaults.
- WebSocket upgrade proxying.
- FastCGI / PHP-FPM framing or worker lifecycle.

## Verification

- `bin/test-fast` passed before editing.
- Focused `router_runtime_test.dart` reverse proxy forwarding test passed.
- Focused `router_runtime_test.dart` FastCGI adapter-stub test passed.
- `dart analyze packages/connectanum_router` passed.
- Full local `bin/verify` passed.

## Notes

- `strip_prefix` / `stripPrefix` removes the matched route prefix before
  joining the request path to the configured upstream base path.
- `timeout_ms` / `timeoutMs` defaults to 30 seconds.
- `max_response_bytes` / `maxResponseBytes` defaults to 10 MiB for this buffered
  first slice; streaming can replace that cap in a follow-up.
