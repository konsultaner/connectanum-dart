# Exec Plan: HTTP FastCGI Route Action

## Status

Complete locally on 2026-05-16.

## Goal

Turn the already-configurable `fastcgi` HTTP adapter route into a usable
buffered runtime path for downstream applications that need PHP-FPM or another
FastCGI responder behind the router.

## Scope

- Dispatch `HttpRouteActionType.fastCgi` before generic WAMP HTTP bridge
  handling.
- Resolve upstream FastCGI endpoints from the existing adapter endpoint options.
- Connect to TCP-style targets (`fastcgi://`, `fcgi://`, `tcp://`, `host:port`)
  and Unix socket targets (`unix:/path` or absolute paths).
- Send one FastCGI responder request with CGI params and buffered stdin.
- Build standard CGI params including method, request URI, query string,
  script name, script filename, content headers, HTTPS state, and HTTP_* request
  headers.
- Parse FastCGI stdout headers/body into the native HTTP response path.
- Map invalid targets, upstream timeouts, oversized buffered responses,
  FastCGI protocol failures, and socket/upstream failures to structured JSON
  gateway responses.
- Keep Unix socket paths and full configured endpoint values out of telemetry.
- Add focused runtime coverage with a fake FastCGI responder.

## Out Of Scope

- Streaming FastCGI request or response bodies.
- FastCGI connection pooling or process management.
- Advanced PHP path splitting (`PATH_INFO`) and index-file resolution.
- Public adapter contract documentation beyond roadmap/state bookkeeping for
  this implementation slice.

## Verification

- `bin/test-fast` passed before editing.
- `dart analyze packages/connectanum_router` passed.
- Focused `router_runtime_test.dart` reverse proxy forwarding test passed.
- Focused `router_runtime_test.dart` FastCGI forwarding test passed.
- Full local `bin/verify` passed before handoff.

## Notes

- `strip_prefix` / `stripPrefix` removes the matched route prefix before
  deriving the default FastCGI `SCRIPT_NAME`.
- `document_root` / `documentRoot` / `root` combines with the derived script
  name to form `SCRIPT_FILENAME`; `script_filename` / `scriptFilename` can
  override it directly.
- `timeout_ms` / `timeoutMs` defaults to 30 seconds.
- `max_response_bytes` / `maxResponseBytes` defaults to 10 MiB for this buffered
  first slice; streaming can replace that cap in a follow-up.
