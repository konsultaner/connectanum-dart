# Exec Plan: HTTP Adapter Route Stubs

## Status

Complete locally on 2026-05-14.

## Goal

Continue the HTTP route adapter-pipeline milestone after static file routes by
making reverse proxy and FastCGI route actions first-class, configurable route
types. This slice intentionally does not implement proxying or FastCGI
transport I/O; it prevents unknown-action config failures and accidental WAMP
dispatch by returning explicit `501 Not Implemented` responses until the real
adapters are implemented.

## Scope

- Add `reverse_proxy` / `reverseProxy` / `proxy` and
  `fastcgi` / `fast_cgi` / `fastCgi` / `fastCGI` action aliases.
- Preserve adapter endpoint options through config parsing and settings codec
  round-trips.
- Validate configured adapter endpoint intent when building native route
  configuration.
- Enqueue matched adapter routes through native HTTP routing into the Dart
  binding, then return structured `501 Not Implemented` responses with adapter
  telemetry instead of dispatching to WAMP.
- Add focused parser, native config, and runtime tests.

## Out Of Scope

- Implementing reverse proxy request forwarding.
- Implementing FastCGI framing, PHP-FPM process management, or response
  streaming.
- Public documentation beyond roadmap/state bookkeeping for this code slice.

## Verification

- `bin/test-fast` passed before editing.
- Focused `router_config_loader_test.dart`, `router_json_test.dart`, and
  `router_runtime_test.dart` adapter-stub tests passed.
- `dart analyze packages/connectanum_router` passed.
- `bin/verify` passed on 2026-05-14.

## Notes

- Adapter endpoints are accepted from `action.delegate` or common option keys:
  `target`, `target_url`, `targetUrl`, `upstream`, `upstream_url`,
  `upstreamUrl`, `socket`, `socket_path`, and `socketPath`.
- The runtime response deliberately does not echo the endpoint value, avoiding
  accidental credential disclosure in proxy target URLs.
- Follow-up work on 2026-05-16 made `reverse_proxy` operational for buffered
  HTTP forwarding, and a later 2026-05-16 slice made `fastcgi` operational for
  buffered FastCGI responder requests.
