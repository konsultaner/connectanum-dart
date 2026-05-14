# HTTP Bridge Design Draft

## Goals

- Deliver a general-purpose HTTP listener that can serve everything from REST
  APIs to static assets and metrics exporters without building a specialised,
  one-off stack for Prometheus.
- Maintain the zero-copy promise end-to-end. Large request bodies should not be
  materialised in Dart; responses should stream directly from the native layer
  or from memory-mapped files.
- Support HTTP/1.1 (keep-alive), HTTP/2 (multiplexing), and HTTP/3/QUIC so the
  bridge can front modern browsers, gRPC-style workloads, or bespoke services.
- Allow flexible routing: map URLs to WAMP RPC calls, publish events, serve
  static content, or proxy to internal sessions (e.g., a PHP FPM adapter that
  talks to the router via a client session).
- Share infrastructure with other listeners (TLS certificates, SNI handling,
  observability) so operators configure everything through the existing
  crossbar-compatible schema.

## Architecture Overview

```
          ┌──────────────────────────┐
          │ Native Runtime (Rust)    │
          │  • Listener accept loop  │
          │  • Protocol negotiator   │
          │  • RawSocket/WebSocket/  │
          │    HTTP parsers          │
          │  • Zero-copy body store  │
          └─────────────┬────────────┘
                        │
                (FFI events / handles)
                        │
          ┌─────────────▼────────────┐
          │ Router Boss Isolate      │
          │  • Connection registry   │
          │  • State store access    │
          │  • Route lookup cache    │
          └─────────────┬────────────┘
                        │
               (commands / handles)
                        │
          ┌─────────────▼────────────┐
          │ Worker Isolates          │
          │  • Route dispatch        │
          │  • Bridge handlers       │
          │  • Internal session RPC  │
          └─────────────┬────────────┘
                        │
           (in-process session API)
                        │
          ┌─────────────▼────────────┐
          │ Internal Router Sessions │
          │  • Router services       │
          │  • Integrator handlers   │
          └──────────────────────────┘
```

### Native Runtime Responsibilities

- Accept TCP/QUIC connections through a single listener abstraction and perform
  protocol negotiation:
  - ALPN decides between RawSocket, WebSocket, HTTP/1.1, HTTP/2, and HTTP/3.
  - HTTP Upgrade headers allow switching to WebSocket or RawSocket when ALPN
    support is absent.
  - Negotiation preference is configurable per listener (e.g. prefer RawSocket,
    then WebSocket, then HTTP).
- Parse frames/requests for the negotiated protocol while keeping payload
  buffers in shared memory (same handle semantics across transports). RawSocket
  and WebSocket continuation frames stay in native buffers until complete, and
  HTTP header fragments are coalesced without Dart copies.
- Provide streaming APIs so workers can pull body slices or forward handles to
  internal sessions without copying. Responses return through the runtime,
  which handles WebSocket continuation frames, chunked encoding, HTTP/2
  DATA/CONTINUATION frames, or HTTP/3 STREAM fragments without rebuilding
  header blocks on the Dart side.

### Boss & Worker Responsibilities

- Boss augments the existing connection registry with HTTP metadata (method,
  path, headers, protocol, request body handle).
- Route lookup happens in the worker: each request is mapped against a
  configured pipeline. Results can:
  - invoke a WAMP procedure via the state store,
  - publish or subscribe using the internal session API,
  - hand off to a static responder (serve files via `mmap`),
  - forward to a custom Dart handler running inside the worker isolate,
  - proxy to a long-poll transport session.
- Workers must keep route handlers non-blocking. Long-running operations hand
  control to asynchronous calls via the internal session, and the worker streams
  results back as they arrive.

### Internal Sessions

- Expose a “bridge session” API that mirrors the client session interface.
  Handlers call `session.call`, `session.publish`, or respond to invocations
  exactly as a regular client would. This keeps custom logic reusable across
  router and external applications.
- Provide utilities for building HTTP responses: status code, header map,
  streaming body writer that accepts zero-copy handles or file descriptors.
- Offer helper adapters for common patterns:
  - RPC proxy: map `POST /api/foo` to `call('com.example.foo')`.
  - Event proxy: map `POST /events/{topic}` to `publish(topic)`.
  - Static file server: fetch from host FS or a user-supplied asset bundle,
    returning `sendFile` handles so the runtime can stream without Dart copies.
  - Metrics exporter: call `connectanum.metrics.openmetrics` and write the
    result as text/plain.

## Configuration Surface

```yaml
router:
  session_profiles:
    - name: public-wamp
      auth:
        methods: [anonymous]

    - name: public-http
      auth:
        methods: []

    - name: http-auth
      realm: realm1
      auth:
        methods: [ticket, scram, wampcra]
        auth_id: http-gateway
        auth_role: internal

    - name: http-jwt
      realm: realm1
      auth:
        methods: [jwt]
        http_provider: edge-jwt

  http_auth_providers:
    edge-jwt:
      type: jwt
      options:
        issuer: https://issuer.example
        audience: [connectanum-http]
        hmac_secret: ${HTTP_JWT_SECRET}

  listeners:
    - endpoint: 0.0.0.0:8080
      protocols:
        - rawsocket
        - websocket
        - http
      session_profile: public-wamp
      rawsocket:
        max_rawsocket_size_exponent: 16
      websocket:
        path: /ws
        serializer_fallback: json
      http:
        alpn: [h2, http/1.1]
        http3:
          enabled: true
          port: 8443
        session_profile: public-http
        routes:
          - match:
              path: /auth
              methods: [POST]
            action:
              type: auth
              session_profile: http-auth
              token_ttl_ms: 600000
              refresh_token_ttl_ms: 3600000
              rotate_refresh_tokens: true
          - match:
              prefix: /api/
            action:
              type: rpc
              procedure: "com.example.api.{path}"
              serializer: msgpack
              session_profile: http-auth
          - match:
              path: /api/jwt
            action:
              type: rpc
              procedure: "com.example.api.jwt"
              session_profile: http-jwt
          - match:
              path: /metrics
            action:
              type: internal_call
              procedure: "connectanum.metrics.openmetrics"
              content_type: "text/plain; version=0.0.4"
          - match:
              prefix: /static/
            action:
              type: file
              directory: /var/www/static
              cache_control: "public, max-age=3600"
          - match:
              path: /fcm
            action:
              type: session_proxy
              delegate: "php_fcm_bridge"
```

- `session_profiles` now provide the common realm/auth identity layout across WAMP listeners, HTTP listeners/routes, and internal sessions.
- Public HTTP profiles can set `auth.methods: []` to declare “no auth required” explicitly.
- `type: auth` is the dedicated HTTP auth bridge action. It reuses the configured WAMP authenticators for `ticket`, `wampcra`, `scram`, or remote-backed methods, then issues short-lived bearer tokens plus refresh tokens for the protected HTTP routes that reference the same session profile.
- Declaring `ticket`, `scram`, or `wampcra` on an HTTP-facing profile is now operational: clients authenticate against the reserved auth route, then present `Authorization: Bearer <token>` on the protected routes that reference that profile.
- The same auth route also accepts `grant_type=refresh_token` with `refresh_token` to rotate bearer credentials and `grant_type=revoke` with `token`/`token_type_hint` to invalidate access or refresh credentials without replaying the full challenge handshake.
- `http_auth_providers` let protected HTTP routes validate bearer tokens without using the challenge bridge. `jwt` and `oidc` profiles currently perform local HS256 verification plus issuer/audience checks, and `oauth` profiles call a configured introspection endpoint. All three map their result into the same internal auth context as the bridge-issued bearer tokens.
- Protected routes now derive cheap transport-auth gates from the same config surface before full auth runs:
  - `session_profiles` with protected auth methods or `auth.http_provider` imply `require_bearer` and `require_tls` for non-`auth` routes.
  - `type: auth` routes imply `require_tls` by default so challenge/response login is not exposed over plain HTTP unless a route explicitly opts into `allow_insecure_transport`.
  - Route action options can tighten this further with `require_mtls: true`, `require_tls: true`, or `require_bearer: true`.
  - Route matches can now declare `protocols: [...]` directly instead of relying on the older undocumented extra-map hook.

- `session_proxy` routes create or reuse an internal session specified in
  `internal_realms`. This enables wiring to a PHP FPM-based bridge or any other
  custom processor running in a dedicated isolate.
- `file` routes serve files relative to the configured `directory`. The router
  rejects empty/unsafe path segments and symlink escapes outside that directory;
  successful responses include `Content-Length`, and `HEAD` returns the same
  metadata as `GET` without a file body. Directory listings, index rewrites,
  range requests, and conditional caching are intentionally outside the first
  static-file slice.
- Translator shorthands:
  - `type: reserved_realm` automatically targets the router-managed
    `router.http` realm. Use `namespace` (optional) to prepend static segments
    and `append_method_suffix` (default `true`) to reuse the HTTP method as the
    trailing path component.
  - `type: namespace` maps requests into an arbitrary realm-controlled namespace
    by concatenating the configured namespace with the HTTP path (and optional
    method suffix). This keeps REST-style URIs aligned with WAMP procedure names
    without writing custom translation handlers.
- Routes specify preferred serializers. When forwarding to WAMP, the bridge
  will translate JSON request bodies into the target serializer, leaning on the
  serializer interceptors already in `connectanum_core`.

## Zero-Copy Considerations

- Request bodies are kept in native buffers. Workers obtain slices via handle
  IDs, and internal sessions receive either the same handles or `ByteData`
  views if they insist on Dart access.
- File responses use the file-backed response helper at the bridge contract
  boundary. Native `sendfile`/`splice` remains a future optimization for the
  runtime path where the Dart side currently may still materialize bytes.
- For dynamic responses, handlers can stream using `Stream<List<int>>` backed by
  `Uint8List.view` on the original native buffers to avoid reallocation.

## Performance & Observability

- Native layer tracks per-connection metrics (latency, response sizes) and
  exposes them through the metrics snapshot/exporter so operators can see HTTP
  activity alongside WAMP stats.
- Benchmarks will include mixed HTTP + WAMP workloads to validate parallelism,
  buffer reuse, and backpressure.
- Logging is routed through the existing leveled logger hooks; high-volume
  access logs can be toggled off in production.

## Next Steps

1. The auth bench now covers ticket, WAMP-CRA, and SCRAM challenge-response flows plus the dedicated JWT and OAuth bearer-provider baselines; the next expansion is remote-provider latency beyond those local baselines.
2. Extend local bearer validation beyond the current HS256 baseline where required (for example JWK-backed RSA/EC verification or OIDC discovery helpers) without breaking the shared session-profile model.
3. Decide whether additional transport gates should become fully typed config fields instead of living under `HttpRouteAction.options` overrides.
