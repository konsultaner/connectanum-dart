# Connectanum Router Roadmap

## Transport & Runtime

- [x] Native Rust runtime (`ct_ffi`) with WAMP RawSocket support
- [x] Dart wrapper for native runtime (start/listen/poll/pollMessage)
- [x] Boss/worker isolate pipeline with zero-copy frame handling
- [x] Zero-copy PUB/SUB forwarding guarded by `CONNECTANUM_FORWARD_NATIVE_PUBLISH`, now overridable via env vars so router tests can exercise the native path without a compile-time define; boss telemetry sends are insulated from forwarding failures.
- [x] Router CLI example (`packages/connectanum_router/example`)
- [x] Config-driven router runner (`packages/connectanum_router/bin/connectanum_router.dart`) suitable for production deployments.
- [x] Deployment templates (`deploy/docker`, `deploy/systemd`, `deploy/k8s`) plus production config docs (`docs/deployment.md`, `docs/router_example.yaml`).
- [x] Packaging & build hooks for `ct_ffi` (Dart 3.10+ native assets build hook builds the Rust library during `dart run`/`dart test`, and the runtime loader discovers artifacts under `.dart_tool/hooks_runner`).
- [x] Native outbound client transports in `connectanum_client` (`NativeRawSocketTransport`, `NativeWebSocketTransport`) backed by `ct_ffi`, with a package-local build hook/runtime loader and a package-specific native-asset name to avoid collisions with `connectanum_router`.
- [x] Shared lazy WAMP payload contract across the native client and router internal sessions, including PPT-aware decode-on-demand that preserves encoded args/kwargs bytes after decode so backend-style consumers can still forward payload slices without forcing an eager `List`/`Map` materialization.
- [x] Preserve PPT metadata on the live CBOR path as well: CBOR `Publish` / `Call` / `Yield` serializers now emit `ppt_*` option fields, native zero-copy publish/invocation forwarding keeps those fields when re-encoding `EVENT` / `INVOCATION`, and already-decoded PPT `Event` / `Result` / `Invocation` objects now round-trip back into lazy payload views without attempting a second unpack.
- [x] Resource caps: configurable outbound send queue capacity (`outbound_send_queue_capacity`) for RawSocket/WebSocket connections.
- [x] Graceful drain: close native listeners before worker drain so no new accepts are queued; `/healthz` reports `draining`, and OpenMetrics exports drain counters.
- [ ] Native TLS offload & kTLS integration
  - [x] Native TCP TLS termination (rustls + SNI certificates) for RawSocket/WebSocket/HTTP1/2 listeners.
  - [x] Certificate reload/rotation hooks (ACME/secret updates) via `ct_reload_tls` + runner `SIGHUP`.
  - [x] mTLS (client cert auth) for native TLS endpoints (`tls.client_auth`).
  - [ ] kTLS / kernel offload exploration and benchmarks.
- [ ] WebSocket transport (WAMP over WebSocket)
  - [x] Route accepted WebSocket sessions into workers and poll WebSocket message handles in the boss loop so WAMP frames flow end-to-end.
  - [x] Add Dart worker regression coverage for WebSocket publish ACKs and missing-call errors to keep WAMP flows consistent with RawSocket.
  - [x] Enforce RFC 6455 client masking/control-frame rules in the native transport (reserved-bit checks, non-fragmented control frames, 125-byte control payload limit, UTF-8 close reasons) and flush graceful close echoes before teardown.
  - [x] Extend Rust `listen_flow` + Dart router integration coverage for WebSocket ping/pong, heartbeat pings, empty close echoes, and unmasked-frame rejection so upgrade/shutdown paths stay regression-tested.
  - [x] Replace per-frame WebSocket `Vec` allocation with pooled owner-backed buffers, keep single-frame WAMP payloads zero-copy through WAMP parse + FFI/Dart, keep continuation fragments as owned `Bytes` segments until the parse boundary, teach the native MsgPack/CBOR parser entrypoints to accept segmented websocket ingress without first coalescing the whole message, keep segmented raw frames in `ct_ffi` storage until a contiguous `ct_message_get` view is actually requested, and emit real RFC 6455 continuation frames for fragmented outbound sends instead of flattening or simulating fragmentation inside one frame. `ct_ffi` now also exposes `ct_message_peek` so native client messages can bind metadata + lazy payload slices without forcing `ct_message_get` to materialize a contiguous `frame_ptr` view first, and that metadata-only path now carries encoded detail-map bytes for richer `CHALLENGE` / `WELCOME` / `ABORT` / `EVENT` / `RESULT` / `INVOCATION` / `GOODBYE` / `ERROR` plus heartbeat/unknown edge shapes instead of only compact control metadata. The same peek-first path now covers the router runtime for the handled inbound request/control families too (`HELLO`, `AUTHENTICATE`, `PUBLISH`, `SUBSCRIBE`, `UNSUBSCRIBE`, `CALL`, `CANCEL`, `REGISTER`, `UNREGISTER`, `YIELD`, `HEARTBEAT`, and unknown fallback frames), scalar control option/detail maps on `PUBLISH` / `SUBSCRIBE` / `CALL` / `CANCEL` / `REGISTER` / `YIELD` / `UNSUBSCRIBED` rebuild directly from metadata, direct-bound custom control/detail maps now stay lazy in Dart instead of forcing eager detail-fragment decode, richer `HELLO` / `WELCOME` detail maps now keep auth/role state lazy on top of metadata bind, and client `CHALLENGE.extra` / router `AUTHENTICATE.extra` auth extras now decode on access instead of ingress. The remaining fallbacks are future unsupported shapes outside the current metadata contract. The masked native WebSocket writer also reuses one scratch buffer and chunks large contiguous sends through it instead of allocating one large masked buffer per frame, and the bench has explicit native WebSocket fragmentation and control-heavy WAMP scenarios instead of relying only on transport regressions.
- [ ] Serializer matrix (JSON, MessagePack, CBOR, UBJSON, FlatBuffers)
  - [x] Complete the router-side JSON/MessagePack/CBOR encode/decode path used by current WAMP benches (including MsgPack `RESULT` and the native CBOR binding path) and cover it with RawSocket/WebSocket integration tests plus serializer-specific bench scenarios.
  - [x] Arm client-side request/reply listeners before sending `CALL` / acknowledged `PUBLISH` / `SUBSCRIBE` / `UNSUBSCRIBE` / `REGISTER` / `UNREGISTER`, so fast RawSocket/WebSocket replies are no longer dropped on the broadcast session stream and serializer-aware WAMP benches stop hanging on successful transports.
  - [x] Preserve `WELCOME` realm/auth metadata in the MsgPack + CBOR serializers so non-JSON/native client transports see the same session details as JSON clients.
  - [x] Reuse matching lazy payload slices on outbound JSON/MessagePack/CBOR serialization and stop copying full detail maps on the common inbound `INVOCATION` / `RESULT` / `EVENT` decode paths; serializer regressions now pin custom-detail preservation for JSON, MessagePack, and CBOR.
  - [x] Trim the remaining serializer-side outbound churn on the hot same-serializer path: MessagePack now assembles WAMP frames with byte builders instead of repeated list concatenation, CBOR now splices already-encoded lazy payload fragments into outbound `CALL` / `YIELD` / `INVOCATION` / `PUBLISH` / `EVENT` / `RESULT` / `ERROR` arrays instead of decoding then re-encoding them, and focused serializer regressions now pin lazy `Result` reuse on both paths.
  - [x] Trim the decode side on the same hot path too: MessagePack and CBOR now scan the top-level WAMP array for inbound `INVOCATION` / `RESULT` / `EVENT` / `ERROR` frames, decode only the fixed header/detail fields eagerly, and retain raw args/kwargs payload slices as `LazyMessagePayload` bytes until a caller actually touches the materialized payload getters.
  - [x] Finish the remaining handled control/ack decode path on the same scanner: inbound MessagePack/CBOR `CHALLENGE` / `WELCOME` / `REGISTERED` / `UNREGISTERED` / `PUBLISHED` / `SUBSCRIBED` / `UNSUBSCRIBED` / `ABORT` / `GOODBYE` frames now rebuild from fragment decoders instead of full-array deserialization, while `WELCOME.details` still preserves auth methods and custom details and `CHALLENGE.extra` keeps `channel_binding`.
  - [x] Keep WAMP cancellation on the normal serializer path too: JSON / MessagePack / CBOR now serialize and deserialize `CANCEL` alongside `INTERRUPT`, so native and Dart control-cycle workloads stop depending on router-side native binders for cancellation traffic.
  - [x] CBOR outbound option serialization now includes PPT fields for `PUBLISH` / `CALL` / `YIELD`, fixing the live-router PPT benchmark path (`wamp_ppt_lazy_smoke`) and keeping RawSocket/WebSocket CBOR PPT traffic aligned with JSON/MessagePack semantics.
  - [x] Push the shared `LazyMessagePayload` contract through outbound `CALL` / `PUBLISH`, router internal-session forwarding, and PPT fragment serialization so mixed encoded/materialized args+kwargs survive end-to-end and matching serializers can forward pre-serialized JSON/MessagePack/CBOR payload bytes without decode+re-encode. The same path now preserves already-packed `pptScheme == 'wamp'` payload bytes across client outbound messages, invocation yields, internal-session routing, and lazy result/event/invocation views instead of forcing a placeholder E2EE decode/re-pack cycle.
  - [x] Make the non-PPT baseline explicit in the bench as well: `wamp_payload_mode_smoke.toml` now runs side-by-side plain versus PPT CBOR workloads across RawSocket/WebSocket, RPC/pubsub, and Dart/native client implementations.
  - [x] Keep the bench echo path honest for that baseline: the plain no-PPT RPC echo handler now reuses the incoming lazy payload directly instead of eagerly decoding it just to echo it back, and `wamp_payload_mode_throughput.toml` mirrors the same explicit plain-versus-PPT comparison at the 64 KiB throughput profile.
  - [x] Cross-serializer translation on the live router path so mixed clients (JSON ↔ MessagePack ↔ CBOR) can publish/call across encodings without data loss; live router regressions now cover EVENT, RESULT, and ERROR bridging, CBOR byte strings survive as `Uint8List`, and the native invocation/result/error fast path falls back to Dart forwarding when serializers differ.
  - [x] Extend the same cross-serializer handling to the remaining fast paths and bench it with real remote peers: WAMP workloads now accept `peer_serializer`, `wamp_mixed_serializer_throughput.toml` measures RawSocket/WebSocket RPC+pubsub across mixed encodings for both Dart and native clients, and the docs now spell out the zero-copy trade-off between same-serializer native forwarding and mixed-serializer Dart fallback.
  - [x] Finish the wrapped/custom-detail side of that bridge too: router native ingress now preserves custom option/detail fields instead of stripping them before the bridge sees them, outbound `Invocation` serializers now emit their real details instead of `{}`, JSON custom/detail maps normalize binary sentinel strings recursively, and live mixed WebSocket regressions now cover EVENT / INVOCATION / RESULT / ERROR paths with nested binary custom fields across JSON, MessagePack, and CBOR.
- [x] Backpressure / flow control between workers and native layer
- [ ] Multi-protocol listener stack (RawSocket/WebSocket/HTTP/1.1/HTTP/2/HTTP/3)
  - [ ] Implement a unified accept loop in the native runtime with ALPN + HTTP Upgrade negotiation so a single endpoint can downgrade/upgrade between RawSocket, WebSocket, and HTTP transports.
  - [ ] Maintain zero-copy buffers across all negotiated protocols (frame handles for RawSocket/WebSocket continuation frames, shared body handles for HTTP).
  - [x] Keep decoded HTTP/2/HTTP/3 request metadata byte-backed across `ct_core -> ct_ffi` instead of flattening headers into `String`s and then rebuilding handshake metadata for FFI; large H2 `CONTINUATION` coverage remains in `listen_flow`.
  - [ ] Integrate TLS/SNI/ALPN config so listeners advertise all supported protocols and fall back in a configurable order.
  - [ ] Finish HTTP/3 implementation: surface stream handles for request/response bodies, manage connection lifecycle, and document operational limits.
  - [ ] Evaluate and implement [WAMP-over-HTTP/3/WebTransport](https://github.com/wamp-proto/wamp-proto/issues/559) (RFC 9220) so browser clients can tunnel WAMP traffic over QUIC with datagram/bidi stream support.
  - [ ] Provide protocol-level metrics and backpressure hooks to the boss/worker pipeline.
    - [x] Track GOAWAY/backpressure/timeout stats per HTTP/2 and HTTP/3 connection inside `ct_core`, expose aggregated counters via `ct_router_metrics_snapshot`, and have `_RouterBoss` surface them through the metrics stream/OpenMetrics exporter.
    - [x] Split counters by listener/protocol and surface them through boss telemetry + the metrics exporter for Prometheus scraping.
    - [x] Boss-side backpressure/transport alerting with configurable thresholds (`metrics.backpressure` / `metrics.transport_alerts`) that can throttle accepts when GOAWAY/timeouts spike.
    - [x] Expose those alerts via the metrics/OpenMetrics exporter (per-reason + per-listener counters) once auth/token gating is in place.
    - [x] Export live alert snapshots (active throttle state, remaining cooldown, and last alert metadata) through the metrics JSON payload and OpenMetrics throttle gauges for external consumers.
  - [x] Surface HTTP/2 and HTTP/3 connection lifecycle events (GOAWAY, idle/body timeouts, backpressure) over FFI so Dart can drain connections deterministically and emit diagnostics.
  - [x] Assert GOAWAY reasons/details for HTTP/2 + HTTP/3 in both native `listen_flow` and Dart runtime tests.
  - [x] Expose negotiated protocol identifiers via FFI so Dart workers can route WebSocket/HTTP sessions (new `ct_connection_websocket_protocol`, Dart bindings, and boss/worker metadata forwarding).
  - [x] Add WebSocket frame streaming support (continuation aggregation, mask handling) with zero-copy forwarding.
    - [x] Tighten RFC 6455 control-frame semantics and regression coverage (mask enforcement, ping/pong, graceful close echo, malformed control-frame rejection) across native + Dart tests.
    - [x] Pool inbound frame storage in `ct_core`, keep single-frame WebSocket message handles slice-based through FFI/Dart, and stream outbound `Bytes` segments directly without a temporary `BytesMut` flatten step.
  - [ ] Add HTTP request/response streaming (header/state machines for HTTP/1.1, HTTP/2, HTTP/3) and surface body handles to Dart.
  - [ ] Stage native HTTP pipeline implementation:
    - [x] Bring up the HTTP/3 QUIC accept loop in `ct_core`: keep connections alive, parse requests via `h3`, match routes, queue `HttpRequestSummary` + response handles, and flush responses back along the same stream.
    - [x] Introduce shared streaming body/response handles in `ct_core` + `ct_ffi` (retain/release/read APIs) so large HTTP payloads stay in native buffers end-to-end.
    - [x] Apply explicit QUIC transport tuning on the router and bench client (stream/connection windows, send window, datagram buffers, keep-alive) instead of relying on Quinn defaults tuned for lower-bandwidth links; Rust tests now pin the config so HTTP/3 perf runs stay reproducible.
    - [x] Finish HTTP/1.1 early-error/status-only fast paths on top of the shared body-handle pipeline.
      - [x] Remove eager `Vec` copies from HTTP/1.1 ingress, keep buffered bodies as `Bytes` inside `HttpBodyHandle`, preserve prefetched bytes when handing off from the handshake parser to the streaming reader, and cover inline-vs-streaming bodies in Rust + Dart regressions.
      - [x] Reject malformed or unsupported HTTP/1.1 requests with native status-only responses (`400`, `413`, `501`) before the Dart bridge is involved, and cover the responses in `listen_flow`.
    - [ ] Bring up the dedicated HTTP/2 server (tokio + `h2`) with multi-stream routing, backpressure, and response writers backed by the shared handle abstraction.
      - [x] Apply explicit HTTP/2 transport tuning on the native server (`max_concurrent_streams`, flow-control windows, frame/header limits, send buffer) instead of relying on bare `h2` defaults.
      - [x] Extend Rust `listen_flow` with large-header `CONTINUATION` coverage plus same-connection multi-stream acceptance before the first response finishes.
    - [x] Align HTTP/3 request/response code with the new streaming primitives so QUIC uploads/downloads never copy into temporary Vecs, and expose stream IDs for diagnostics.
    - [x] Reuse inbound `Bytes` chunks directly in the HTTP/2 and HTTP/3 body readers so they feed `StreamingBodyState` without `Bytes -> Vec -> queue` copies.
    - [x] Implement the WebSocket upgrade pipeline (accept handshake, negotiate serializers, forward frames with continuation/mask handling, and boss/worker instrumentation).
    - [ ] Evaluate downgrade-to-RawSocket fallback paths where an HTTP/WebSocket listener can safely hand off to the RawSocket fast path after negotiation.
    - [x] Update `NativeHttpRequestBody`/`HttpInvocationContext`/`HttpResponseUtil` in Dart to default to streaming reads/writes while preserving snapshot/copy fallbacks for legacy handlers.
  - [ ] Add end-to-end tests (Rust ffi `listen_flow`, Dart router_runtime/integration) that exercise HTTP/1.1, HTTP/2, HTTP/3, and WebSocket flows (multi-MB uploads/downloads, pointer comparisons, frame forwarding, streaming timeouts) and clean up temp files during teardown.
    - [x] New Rust `listen_flow` coverage for HTTP/2 idle/body timeouts and HTTP/3 idle/body timeouts (QUIC path now closes the connection on timeout to avoid `h3-quinn` stop-sending races).
    - [x] Rust `listen_flow` coverage for HTTP/2 streaming responses (multi-chunk DATA frames flushed via `ct_http_response_stream_*` APIs).
    - [x] Rust `listen_flow` coverage for HTTP/1.1 streaming responses (chunked writer backed by `ct_http_response_stream_*` APIs).
  - [x] Rust `listen_flow` coverage for HTTP/3 streaming responses (QUIC writer exercising `ct_http_response_stream_*` pipelines).
  - [x] Rust `listen_flow` coverage for HTTP/3 request polling and streaming dispatch (`http3_stream_poll_returns_handle`).
  - [x] Rust `listen_flow` coverage for WebSocket WAMP round-trips (masked client frames with server replies).
  - [x] Rust `listen_flow` coverage for HTTP/3 handshake/multi-connection acceptance under QUIC ALPN (`http3_handshake_surfaced_via_ffi`, `http3_multiple_connections_handshake`).
    - [x] Router/Dart integration test for HTTP/1.1 streaming uploads/downloads (re-enabled “streams HTTP request and response payloads end-to-end” suite).
    - [x] Router boss/runtime + native integration coverage for HTTP/1.1 keep-alive reuse after streamed uploads/responses, so queued requests on an active socket are drained after the first handshake instead of stalling in the shared HTTP bridge.
    - [x] Router runtime tests verifying `_HttpResponseStream` plumbing for HTTP/2 and HTTP/3 handshakes (synthetic boss harness).
    - [x] Router/Dart integration tests for HTTP/2 + HTTP/3 streaming uploads/downloads (router_integration_native_test.dart now streams HTTPS and QUIC payloads via the native test client + TLS fixtures, running the HTTP/3 client on a dedicated isolate so the boss keeps draining requests).
    - [x] Multi-MB HTTP/2 and HTTP/3 streaming regressions that emit OpenMetrics snapshots for CI artifacts (`router_integration_native_test.dart` multi-MB suites gated by `CONNECTANUM_ARTIFACT_DIR`).
    - [x] Rust + Dart native runtime regressions assert HTTP/1.1 inline bodies remain directly viewable while oversized bodies stay on streaming handles without eager native buffering.
    - [x] Dedicated Dart WebSocket WAMP integration suite driving publish/call flows (continuation frames, large payloads, subprotocol + serializer negotiation).
    - [x] Pin the current upstream WAMP conformance vectors locally and gate them in CI for the handled single-message serializer matrix. `packages/connectanum_core/test/conformance/wamp_singlemessage_conformance_test.dart` now runs the vendored `wamp-proto/wamp-proto#557` snapshot (`fix_556` commit `59303fd`) across JSON, MessagePack, and CBOR in GitHub Actions.
    - [ ] Once the upstream suite is merged and broader interaction vectors stabilize, extend the gate from the pinned single-message subset to the official multi-message / multi-session transport matrix (RawSocket/WebSocket plus HTTP bridge coverage where applicable).
- [ ] HTTP bridge (general-purpose request handling)
  - [ ] Expose bridge configuration via listener protocols with pluggable pipelines (REST→RPC proxy, static asset serving, metrics scraping, custom handlers).
  - [x] Introduce shared `session_profiles` across WAMP listeners, HTTP listeners/routes, and `internal_realms`, so transport-specific ingress config can reference one common realm/auth/authz profile shape. Listeners can now inherit `auth.methods` from a profile, HTTP dispatch resolves route/listener session profiles before creating internal caller sessions, and internal sessions can derive `realm`, `auth_id`, `auth_role`, and role maps from the same shared profile definition.
  - [ ] Support translation tables that map HTTP path/method/protocol combinations to explicit WAMP realms and procedures, including per-method overrides and catch-all wildcards.
  - [ ] Provide reserved realm/namespace shorthand so routes can auto-map into a router-managed HTTP realm with deterministic URI derivation (e.g. `/` → `router.http.index`).
  - [ ] Allow namespace-based auto-mapping (path segments → URI prefixes) for teams already organising registrations by namespace.
  - [ ] Map incoming REST requests to internal router sessions through an in-memory transport so PHP/FCM or other external services can act as lightweight proxies.
  - [ ] Provide policy-driven routing (path → WAMP procedure/topic, file proxy, custom isolate handler) with per-route auth hooks aligned with realm permissions.
  - [x] Enforce method/protocol whitelists from the configuration; return 405/426 at the native layer before touching Dart, with native and Dart runtime regressions proving rejected requests are not dispatched into the WAMP-backed HTTP bridge.
  - [x] Keep HTTP payloads zero-copy by exposing request/response body handles over FFI and streaming through Rust.
  - [x] Support request/response streaming and file-backed payloads to preserve zero-copy semantics for large bodies.
  - [x] Surface structured responses (status, headers, trailers) back to the native runtime without materialising entire payloads in Dart.
  - [x] Land `HttpRequestContext`/`HttpResponseUtil` in Dart so HTTP routes can read bodies lazily, pipe uploads directly to disk, and send structured responses (status/headers/body) back through the boss without copies.
  - [x] Extend FFI to accept structured HTTP responses (status, headers, zero-copy body descriptors, streaming handles) and flush them to the native runtime.
  - [x] Provide zero-copy response helpers: in-memory slices, file-backed payloads, and streaming writers with back-pressure.
  - [x] Implement initial HTTP response FFI plumbing (status/headers/bytes) in `ct_core`/`ct_ffi` and patch Dart runtime to call it.
  - [x] Add OpenMetrics HTTP exporter (`metrics.open_metrics.listen`) for Prometheus scraping and cover with tests.
  - [x] Route HTTP bridge requests into internal sessions via borrowed native body descriptors instead of serializing request bytes into invocation payload maps.
  - [x] Forward streamed HTTP bridge response chunks across the internal-session isolate hop with transferable buffers so large progress payloads avoid repeated `Uint8List` copies.
  - [x] Bypass the per-chunk WAMP response envelope for streamed HTTP bridge responses: internal sessions now open borrowed native response-stream descriptors once, write chunks directly from the callee isolate, and emit only a final completion result back through the call lifecycle.
  - [x] Add end-to-end zero-copy HTTP regressions (large request/response plus descriptor-based internal-session routing) to ensure no stray serialization occurs in Dart.
  - [ ] Offer middleware hooks (logging, rate limiting, throttling) that run inside worker isolates while heavy I/O remains in Rust.
  - [ ] Introduce adapter pipeline support (static file handler, PHP-FPM/FastCGI bridge, reverse proxy stubs) configurable per route; document adapter contracts and lifecycle.
  - [ ] Add tests/doc coverage for the new HTTP call contract (Dart unit tests, router integration test asserting response round-trip, native tests validating file/stream paths).
- [ ] HTTP authentication & session tokens
  - [x] Shared `session_profiles` now provide the common auth/session config surface for WAMP listeners, HTTP listeners/routes, and public/internal profiles, including explicit public profiles (`auth.methods: []` or `anonymous`) and shared method declarations such as `ticket`, `scram`, and `wampcra`.
  - [x] Reuse endpoint authenticators (ticket, CRA, SCRAM, and any configured remote-backed method) to issue short-lived bearer tokens for HTTP clients; the bridge resolves target realm information from body/query/header and keeps public profiles on the current fast path.
  - [x] Provide a dedicated HTTP `auth` route action that fronts a configurable auth endpoint (commonly `/auth`) so clients can complete challenge/response methods over HTTP, receive bearer tokens for protected routes, refresh them with `grant_type=refresh_token`, and revoke access/refresh credentials with `grant_type=revoke`.
  - [x] Add config-driven HTTP bearer auth providers (`http_auth_providers`) on top of shared `session_profiles`, so protected HTTP routes can validate JWT/OIDC bearer tokens locally or OAuth access tokens through introspection and then map the result into the same internal auth context used by the WAMP-backed challenge bridge.
  - [x] Enforce cheap endpoint/route transport auth (TLS/mTLS/bearer presence plus protocol-gated routes) before the Dart bridge/session layer. Native HTTP/1.1/2/3 request handlers now reject clearly unauthorized routes directly from `transport_auth`, and the Dart binding mirrors the same checks for synthetic/runtime coverage.
  - [x] Implement refresh token handling (configurable TTL + rotation) directly on the HTTP auth bridge so protected HTTP clients can renew access without replaying the full handshake; revocation now invalidates linked access sessions too.
  - [x] Propagate auth context through the internal caller session created for protected HTTP requests, so downstream realm permissions are evaluated against the bearer-backed principal instead of a generic bridge identity.
- [ ] HTTP forwarding hooks for custom routing/handling in RPC implementations
  - [ ] Graceful shutdown (drain sessions, send GOODBYE/HTTP responses, stop listeners)
    - [ ] Provide unified HTTP bridge that can surface Prometheus/Grafana exporters alongside REST→WAMP translation.
    - [ ] Support structured metrics endpoints over HTTP/2 and HTTP/3 so observability stack can scrape without extra proxies.
- [x] Outbound frame bridge (`ct_send`/FFI) for CHALLENGE/WELCOME/EVENT delivery
- [ ] End-to-end payload encryption (E2EE) strategy
  - [x] Capture the current WAMP E2EE/PPT references and land the shared Dart-side phase-1 contract (`WampE2eeProvider`, `WampCborXsalsa20Poly1305Provider`, router passthrough, and client/core coverage) without forcing router-side decryption.
  - [ ] Evaluate keeping encryption off the Dart hot-path (Dart’s 64-bit object model vs native/Rust or dedicated isolates with binary messaging).
  - [ ] Prototype native encryption/decryption pipeline that preserves zero-copy semantics and works across serializers.
  - [ ] Define key-management interfaces and handshake flow (HELLO/CHALLENGE payload negotiation).
  - [ ] Add regression tests ensuring encrypted PUB/SUB and RPC payloads interoperate with unencrypted peers where allowed.

## Router State & Infrastructure

- [x] Central `RouterStateStore` (realms, sessions, subscriptions, registrations)
- [x] Realm snapshots & invalidation events for workers
- [x] Command API (async mutation/query from workers)
- [x] Persistent ID allocators (session/subscription/registration/publication/ invocation/request)
- [ ] Worker pool autoscaling
  - [ ] Collect per-worker load metrics (connection counts, pending handle depth, queue latency, host stats)
  - [ ] Implement hysteresis-based scale-up/scale-down policy with configurable thresholds
  - [ ] Reassign connections gracefully during scale-down using drain flow
  - [ ] Integrate load-aware connection assignment (least-busy/weighted policies)
  - [ ] Verify cross-worker parallelism with high-contention integration tests (parallel call/publish workloads)
- [x] Meta event dispatch plumbing (session/subscription/registration meta)
- [ ] Metrics counters / observability hooks

## Basic Profile (WAMP v2)

### Session & Realm Management

- [x] HELLO frame parsing in native layer
- [x] HELLO → WELCOME handshake & role negotiation (anonymous + challenge/response paths)
- [x] ABORT handling (capability or auth failure)
- [x] GOODBYE reception & realm cleanup
- [x] Router-initiated GOODBYE / graceful shutdown (drain sessions and propagate to clients)
- [x] Heartbeat / ping-pong / session timeout support

### Publish & Subscribe

- [x] SUBSCRIBE frame decoding
- [x] UNSUBSCRIBE frame decoding
- [x] Subscription tracking per session/realm
  - [x] Unit tests: subscribe/unsubscribe success, invalid/topic errors, session teardown cleanup
- [x] Topic publication routing (EVENT)
  - [x] Unit tests: publish with ack on/off, exclude/eligible filters, wildcard/prefix routing
- [x] Publication IDs / ACK handling
- [x] ERROR routing for SUBSCRIBE/UNSUBSCRIBE/PUBLISH
- [x] End-to-end zero-copy PUB/SUB dispatch (reuse native frame buffers across subscribers)
  - [x] FFI support for cloning publish frames with patched headers only
  - [x] Worker routing uses native handles instead of Dart re-serialization
  - [x] Tests ensure EVENT payload buffers are reused across recipients
  - [x] Multi-recipient native publish fan-out now transfers the original handle to the first external subscriber and only clones for the remaining recipients; tests cover clone-setup failure and mid-send release paths

### Remote Procedure Calls

- [x] REGISTER / UNREGISTER decoding
- [x] CALL / RESULT / ERROR decoding
- [x] Registration tracking per realm/session
  - [x] Unit tests: register/unregister success, duplicate/ownership enforcement, session cleanup
  - [x] Invocation dispatch + RESULT/ERROR forwarding
    - [x] Synthetic RawSocket integration harness (ffi-test mode) covering HELLO→CALL→progressive/final RESULT forwarding
    - [x] Unit tests: call→invocation→result, failing callee, timeouts, progressive results placeholder
- [x] ERROR handling for REGISTER/UNREGISTER/CALL
- [x] CALL cancellation (basic profile – CANCEL)
- [x] End-to-end zero-copy RPC dispatch (reuse native call payload buffers)
  - [x] FFI helper for cloning invocation frames without copying arguments
  - [x] Worker invocation/result/error forwarding now transfers the original native handle on one-recipient zero-copy paths, and native publish fan-out now uses the same transfer-first rule for the first subscriber before cloning only the extra recipients
  - [x] Tests ensure transferred/retained handles are released correctly on YIELD/ERROR success and boss-send failure paths

## Advanced Profile

### Pub/Sub Enhancements

- [x] Pattern-based subscriptions (prefix / wildcard with order/priority)
- [x] Subscription meta events (created, deleted, on/off subscribe)
- [x] Publisher options (exclude_me, eligible/exclude authid/authrole lists)
- [ ] Payload persist / retained events
- [ ] Throttle/debounce hooks driven by client-provided hashes in publish pipeline
  - Reference: [WAMP issue #391 comment](https://github.com/wamp-proto/wamp-proto/issues/391#issuecomment-998577967) for debounce/throttle semantics and hashing strategy.
  - Ensure serializers accept implementation-specific option/detail keys (spec allows `_foo` style; tolerate legacy non-underscore keys to interop with existing routers like Crossbar).

### RPC Enhancements

  - [x] Shared registrations with invocation policies (round-robin, random, load)
  - [x] Shared registration meta events
- [ ] Load-aware invocation balancing (collect CPU/RAM/remote metrics and select least-loaded callee)
- [x] Progressive call results (`progress=true`)
- [ ] Call cancellation modes (`kill`, `killnowait`, `killall`) — ensure cancellers can wait for cleanup so subsequent processing shuts down gracefully
  - [x] `killnowait`
  - [x] `kill`
  - [ ] `killall`
- [ ] Caller disclosure (`caller`, `caller_authid`, `caller_authrole`)
- [ ] Throttle/debounce hooks driven by client-provided hashes in call pipeline
  - Align behaviour with [WAMP issue #391 comment](https://github.com/wamp-proto/wamp-proto/issues/391#issuecomment-998577967) to allow routers to honour client-provided throttling keys.
  - Client/server serializers must preserve custom fields (prefer `_custom` naming per spec, but remain lenient to match existing implementations).
- [ ] Sharded registrations / invocation trust level (`trustlevel`)

### Authentication & Authorization

- [x] Challenge/response (`CHALLENGE`/`AUTHENTICATE`) flow
- [x] Router worker integrates authenticator registry with per-session state/tests
- [x] Anonymous/no-auth handshake (immediate WELCOME)
- [ ] Pluggable authenticators (shared client/router implementations):
  - [x] Static ticket
  - [x] WAMP-CRA (HMAC challenge/response)
  - [x] SCRAM (salted challenge/response)
  - [x] WAMP-cryptosign / ED25519
    - [x] Remote authentication executor (delegate auth decisions to external service)
      - [x] Document Java interoperability contract (realm `connectanum.authenticate`, procedures `authenticate.hello` / `authenticate.authenticate` / `authenticate.abort`), including expected payload shape and error semantics. See `docs/remote_auth_interop.md`.
      - [x] Implement router-side transaction nonce generator (cryptographically strong, per-session) with bounded TTL and automatic cleanup on client disconnect.
      - [x] Add realm-configurable policy to whitelabel permitted authroles/authproviders returned by delegate; abort if response violates policy.
      - [x] Support multiple remote authenticators per realm/listener with failover strategy and connection-state monitoring.
      - [x] Enforce rate limiting/backoff for remote auth RPC calls and integrate failures with `AuthSecurityTracker`.
      - [x] Introduce the worker-safe WAMP RPC delegate path so routers can call a real remote auth realm over RawSocket/WebSocket instead of only relying on isolate-local delegate registration. `connectanum_auth_server` now exposes `AuthServerProcedureBinding` for `authenticate.hello` / `authenticate.authenticate` / `authenticate.abort`, and the router supports config-driven `rpc` delegates plus shared-token validation on `HELLO` / `AUTHENTICATE` / `ABORT`.
      - [x] Restrict serialized payload to the minimal required auth fields and validate schema on both request and response before issuing `CHALLENGE`/`WELCOME`.
      - [x] Preserve fake-challenge behavior on remote rejection, keep pending transaction abort cleanup wired through worker disconnect/error paths, and continue logging audit details for operators.
      - [x] Add integration tests spinning up a stub remote service to verify success, malformed responses, timeout, and abort flows end-to-end.
      - [x] Introduce authenticated transport to the remote service with mutual TLS and automatic credential rotation hooks in addition to the current shared-token path. The remote WAMP delegate now supports file-backed shared tokens, service credentials, and TLS material, enforces secure transport by default, rebuilds TLS contexts from PEM files, and reconnects when transport/service-auth fingerprints change. Live coverage now exercises the secure RPC hop over TLS+mTLS plus token/credential rotation on the real router/auth-server path.
      - [x] Build a constrained remote-auth client stub in the bench orchestrator to fuzz HELLO/CHALLENGE/AUTHENTICATE flows without full WAMP clients (rawsocket frame pusher), and instrument latency/backpressure on remote auth RPCs. The Rust bench orchestrator now ships a dedicated `wamp_rawsocket_auth_frames` protocol plus `remote_auth_rawsocket_smoke.toml`, drives HELLO/CHALLENGE/AUTHENTICATE directly over RawSocket without `connectanum_client`, tolerates both fake-challenge and fail-closed ABORT paths under rate limiting, and records the normal router metrics deltas alongside per-iteration auth latency. `bench_main.dart` also starts a real auxiliary auth router plus `AuthServerProcedureBinding` whenever the bench config contains a rawsocket remote authenticator, so the frame-pusher path exercises the live router-to-auth-service RPC hop. A follow-up `remote_auth_rawsocket_cold_warm.toml` scenario now separates first-hit versus warmed remote-auth latency so the cost of establishing the router-to-auth-service session is visible instead of being hidden inside one mixed average. Router workers now also pre-spawn the configured minimum worker pool and best-effort warm remote WAMP delegates on isolate startup, which cut the first-hit remote-auth success case on the current localhost smoke path from roughly `268 ms` to `123 ms` while leaving the steady-state warmed path around `102 ms`, making it clear that the remaining latency sits in the live remote-auth RPC flow rather than in worker or auth-service session cold start.
    - [ ] Add internal transport support for router ↔ auth server chaining:
      - [ ] Design in-process frame transport (shared ring buffer / isolate message channel) with backpressure.
      - [ ] Embed an internal WAMP client inside the router to proxy authentication requests over the internal transport.
      - [ ] Auth server hosts a router instance plus internal client that drives credential providers.
      - [ ] Ensure configuration allows switching between TCP delegates and in-process delegates for testing.
      - [ ] Extend unit/integration tests to cover internal-transport authentication flow.
      - [ ] Prerequisite: RPC invocation and PUB/SUB dispatch must be implemented so the router can forward authentication RPCs end-to-end.
    - [ ] Add shared message-flow abstraction (PUB/SUB ~ REGISTER/CALL):
      - [ ] Extract reusable primitives for routing requests, tracking responders, and emitting replies/events.
      - [ ] Ensure new abstraction is covered by unit tests for both publish/event and call/result paths.
  - [ ] Interoperability with `connectanum-authentication` remote executor (Java auth server)
  - [ ] Survey community extensions (GitHub/routers) for additional mechanisms
- [x] Realm-level authorizers (permission checks before SUBSCRIBE/PUBLISH/etc.)
  - [x] Static `RoleSettings.permissions` now gate `SUBSCRIBE`, `UNSUBSCRIBE`, `PUBLISH`, `CALL`, `CANCEL`, `REGISTER`, and `UNREGISTER` on both external worker traffic and internal router sessions when a realm actually defines permission entries; legacy realms with no permission policy keep the prior allow-all behavior.
  - [x] Optional runtime `AuthorizationProviderRegistry` hooks can supplement the static realm policy for dynamic database/rule-engine decisions; static denies still win, configured permissioned realms default deny, and unconfigured legacy realms continue to allow by default.
  - [x] Remote-auth integration coverage now proves that post-auth realm permissions are enforced on authenticated client actions, not just on handshake success.
- [x] Static TLS cert/SNI configuration pipeline to native runtime (config loader + native TLS acceptor; see `docs/tls.md`).
- [ ] Intrusion detection (failed-auth rate limiting, account lockouts, anomaly alarms)

### Introspection & Testing

- [ ] WAMP meta API (session, subscription, registration listings)
- [ ] Caller tracing & diagnostic events
- [ ] Administrative control interface (pause/resume realm, drain connections)
- [ ] Replay/testing hooks (record & replay message streams)
- [x] FFI “test mode” harness for synthetic RawSocket integration tests (HELLO/CALL/YIELD flows)

## Tooling & Documentation

- [x] Router example CLI for local testing
- [x] Router runner binary + deployment docs (`packages/connectanum_router/bin/connectanum_router.dart`, `docs/deployment.md`).
- [ ] Developer docs for native runtime build pipeline
- [ ] Dart 3.10+ build hooks to compile `ct_ffi` during pub install/`dart pub get` (the current run/test hooks now honor cache-safe `hooks.user_defines` for `CONNECTANUM_NATIVE_LIB`, `CONNECTANUM_NATIVE_RELEASE_TAG`, and `CONNECTANUM_SKIP_NATIVE_BUILD`, and document prebuilt/system-library usage).
- [ ] Configuration reference (realm JSON schema, TLS modes, worker tuning)
  - [x] TLS configuration notes + example config (`docs/tls.md`, `docs/router_example.yaml`).
  - [ ] Document feature toggles in crossbar-compatible config (meta events, benchmark exporters, zero-copy assertions)
  - [ ] Allow per-listener/realm flags to disable optional subsystems without code changes
- [x] Crossbar-compatible configuration schema + validation tooling
- [ ] Example gallery for router features
  - [x] CLI demo covering hashed credentials, `CredentialRejection`, and remote delegates (`packages/connectanum_router/example`)
  - [ ] WebSocket transport demo (router and remote auth server)
  - [ ] Stub remote service integration (fake challenge parity)
- [ ] Comprehensive WAMP feature test suites (basic and advanced)
  - [ ] Basic profile: HELLO/WELCOME, PUB/SUB, RPC, error flows
  - [ ] Advanced profile: pattern subscriptions, shared registrations, cancellation, progressive results
- [x] Auth server scaffolding (`packages/connectanum_auth_server`) providing the same authenticator API for remote deployments
- [ ] Auth server CLI (config loader, RPC loop, health endpoints)
- [x] Remote auth secure transport (mTLS / signed tokens) and credential rotation
- [ ] Fake challenge parity & stub remote service integration tests
- [ ] Internal transport support for embedded router↔client flows
  - [ ] Define in-process transport abstraction (frame routing with backpressure)
  - [ ] Embed internal session inside edge router to speak RemoteAuthenticatorDelegate over the new transport
  - [ ] Auth server runs router instance + internal client that talks to credential providers
  - [ ] Wire configuration knobs for selecting internal vs TCP transports
  - [ ] Migrate existing delegate tests/examples to the internal transport once available
- [ ] End-to-end smoke tests (native runtime ↔ router ↔ client)
- [ ] Benchmarks (throughput/latency per worker configuration)
  - [x] Provide release-build workflow for `ct_ffi` (and document `CONNECTANUM_NATIVE_LIB` usage) dedicated to performance runs.
  - [ ] Implement a reusable load generator (multi-session HELLO/PUB/SUB/RPC workloads) to stress the router.
  - [ ] Expose lightweight instrumentation (per-worker queue depth, handle retention counts, throughput/latency timers) for benchmark reporting.
  - [ ] Add automation scripts that run warm-up + steady-state cycles and emit latency/throughput summaries.
  - [x] Added rawsocket publish+ACK regression test (`publish_ack_test.dart`) covering `bench.control` realm with `libct_ffi.so`.
  - [x] Ship the HTTP/2 streaming benchmark harness (`packages/connectanum_router/tool/http_stream_bench.dart`) that drives real uploads/downloads and reports router transport metric deltas via `binding.collectMetrics()`.
  - [x] Land the native bench orchestrator (Rust client + Dart router runner) outlined in `native/bench/README.md` so scenarios/scripts can be shared across CI and local perf runs.
    - [x] Bench runner exposes `/bench/*` HTTP control routes backed by internal RPC handlers (`bench_router.json`), and the Rust scaffold now pings `/bench/healthz`, `/bench/metrics`, and `/bench/stop` before shutting down.
    - [x] Orchestrator loads TOML scenarios (`native/bench/scenarios/h2_smoke.toml`, `full_stack.toml`), drives HTTP/2 workloads via a direct `h2` client (including same-connection multiplexing), captures router metrics snapshots before/after each workload, emits JSONL summaries (`bench_results.jsonl`), and enforces per-workload timeouts so hung runs fail fast instead of wedging CI.
  - [x] WAMP pub/sub benchmark stability: `wamp_smoke` now passes after fixing EVENT serialization (details/kwargs) and guarding malformed kwargs; bench runs no longer hang during pubsub.
  - [x] Extend WAMP bench coverage across both RawSocket and WebSocket, split the scenario protocols so transport results stay distinct, add a dedicated plain WAMP bench listener (`127.0.0.1:8081`) next to the HTTPS control listener, and ship `all_transports_smoke.toml` so RawSocket/WebSocket/HTTP/1.1/HTTP/2/HTTP/3 can be exercised in one run.
  - [x] Add serializer-aware WAMP bench scenarios (`serializer = json|msgpack|cbor`), expand `wamp_smoke.toml` and `wamp_transport_throughput.toml` to cover the full RawSocket/WebSocket × pub/sub/RPC × serializer matrix, keep `all_transports_smoke.toml` representative, and ship a dedicated `wamp_serializer_matrix.toml` for larger-payload RawSocket/WebSocket RPC sweeps.
  - [x] Add a comparable cross-transport/auth/authz smoke matrix in Mbps: WAMP workloads now accept explicit `realm`, `auth_method`, `auth_id`, and `auth_secret`, the bench runner can measure session setup via `mode = "authenticate"`, `bench_router.json` now exposes an ACL-off legacy realm (`bench.control`) alongside an ACL-on ticket realm (`bench.secure`), and `transport_mbit_matrix_smoke.toml` covers RawSocket/WebSocket RPC + pub/sub across representative payload sizes plus WebSocket continuation sizes together with HTTP/1.1/2/3 public/authenticated route probes.
  - [x] Promote the cross-transport/auth/authz matrix into a throughput-grade canonical scenario: `transport_mbit_matrix_throughput.toml` keeps the same auth/authz/public/protected topology, adds 64 KiB protected HTTP rows, and raises iterations/concurrency/in-flight depth/multiplexing so one run yields a stable Mbps table for CI/reporting.
  - [x] Fix RawSocket client-side benchmark latency by disabling Nagle (`tcpNoDelay`) and emitting each WAMP frame as a single socket write instead of splitting frame headers and payloads; recent `all_transports_smoke` runs in this environment moved RawSocket pub/sub latency from roughly `45 ms` down to roughly `6.7 ms` on loopback, much closer to the WebSocket path (`~3.6 ms`).
  - [x] Let WAMP workloads keep multiple operations in flight per hot session (`in_flight_per_session`), upgrade the pub/sub event buffer to support multiple concurrent waiters, and add a dedicated `wamp_transport_throughput.toml` scenario so RawSocket/WebSocket throughput sweeps stop behaving like single-outstanding-call latency tests.
  - [x] Reduce RawSocket client receive-path overhead by merging inbound chunks in one copy, keeping complete frame slices as `Uint8List.sublistView` views, and preserving coalesced handshake+payload bytes instead of dropping data when the server replies with the handshake and first frame in one TCP chunk.
  - [x] Stop probing RawSocket bench connections for HTTP/3 handshakes in `_RouterBoss`; the cross-transport WAMP bench no longer emits `ct_connection_take_http3_handshake ... unsupported protocol RawSocket` noise or pays the extra per-accept work on the dedicated RawSocket/WebSocket listener.
  - [x] Extend the bench to compare Dart and native `connectanum_client` implementations on the same WAMP workloads (`client_impl = dart|native`), add dedicated `wamp_client_impl_smoke.toml` / `wamp_client_impl_throughput.toml` scenarios, and prestart the helper worker so native workload timings no longer include process boot time.
  - [x] Move the native client inbound hot path off full-frame Dart deserialization: `Session` now routes replies/events/invocations via direct request-id maps, `ct_ffi` exports typed metadata for the common inbound `Published` / `Subscribed` / `Registered` / `Unregistered` / simple `Event` / simple `Result` / simple `Invocation` shapes, and `connectanum_client` binds those messages directly in Dart while keeping payload slices lazy. The same metadata-only path now also carries encoded detail-map bytes for richer `CHALLENGE` / `WELCOME` / `ABORT` / custom-detail `EVENT` / `RESULT` / `INVOCATION` / `GOODBYE` / `ERROR` messages, so normal control/custom-detail session traffic stays on `ct_message_peek` and full-frame decode is reserved for the remaining unsupported shapes. The native client also uses a dedicated receive isolate that blocks on `ct_wait_connection_message(...)` and batch-drains already-ready handles before forwarding them back to the main isolate. On top of that, the client now has a session-only native message envelope for hot `Event` / `Result` / `Invocation` traffic, plus a first-class `LazyMessagePayload` object for backend-style consumers that want borrowed encoded payload bytes before decode. Non-progressive RPC callers can now use `Session.callSingle(...)`, `Session.callSinglePayload()`, or `Session.callSingleLazyPayload()`, backend-style consumers can use `Session.subscribeHandler(...)` / `Session.subscribePayloadHandler(...)` / `Session.subscribeLazyPayloadHandler(...)` and `Session.registerHandler(...)` / `Session.registerPayloadHandler(...)` / `Session.registerLazyPayloadHandler(...)`, subscription events are decoded once on ingress instead of through a mapped stream, `Subscribed` / `Registered` lazily own their stream controllers so Flutter-style stream APIs stay intact without eager controller allocation for backend-style callers, `Subscribed.onEvent(...)` / `onEventPayload(...)` / `onLazyEventPayload(...)` now provide the direct callback fast paths for hot pub/sub consumers, and async callee failures now propagate back as WAMP `ERROR`s even when they happen after an `await`. The same `LazyMessagePayload` contract now underpins router internal sessions and worker-session forwarding: encoded args/kwargs plus serializer hints cross isolate hops intact, external same-serializer fallback routing for `PUBLISH` / `CALL` / `YIELD` / invocation `ERROR` now reuses transferred lazy payloads instead of touching `arguments` / `argumentsKeywords` just to rebuild replacement messages, internal `publish` / `call` / `event` / `invocation` / `result` paths can stay lazy until a handler actually asks for decoded Dart objects, already-packed `pptScheme == 'wamp'` payload bytes now survive outbound/inbound forwarding without being forced through the placeholder E2EE packer, and `Session.callSingle(...)` now rebuilds classic `Result` objects from the lazy result view instead of forcing an eager payload decode/re-wrap on the materialized RPC path. The bench RPC workloads now use the lazy-result path, the pub/sub workloads use the lazy event path, and the harness no longer wraps inbound events in an extra Dart bench object before matching them. Recent release-built client-implementation comparisons on this machine now land around `99 Mbps` native vs `53 Mbps` Dart for RawSocket 64 KiB RPC, `128 Mbps` vs `49 Mbps` for RawSocket 64 KiB pub/sub, `117 Mbps` vs `53 Mbps` for WebSocket 64 KiB RPC, and `128 Mbps` vs `47 Mbps` for WebSocket 64 KiB pub/sub.
  - [x] Extend the harness for HTTP/3/TLS runs, persist OpenMetrics snapshots after each scenario, and integrate the results with Prometheus dashboards.
    - [x] HTTP/3/TLS support landed in the orchestration CLI (QUIC prior-knowledge via `quinn`+`h3`, shared-port overrides, h3-only scenarios) so benchmarks can exercise both transports while capturing metrics deltas.
    - [x] `/bench/metrics` now returns both the router snapshot and the OpenMetrics payload, and the orchestrator serializes `open_metrics_before`/`open_metrics_after` fields per workload (`bench_results.jsonl` + docs updated).
    - [x] Bench results are transformed automatically into `bench_results.prom` + `bench_results.summary.json`, the Docker compose stack ingests the `.prom` output through the node-exporter textfile collector, and Prometheus/Grafana ship matching artifact rules + dashboards for per-workload regression surfacing.
    - [x] The orchestrator can now sweep router worker counts (`--router-worker-counts 1-8`), rewriting the bench router config per run, stamping JSONL/Prometheus artifact rows with `router_workers`, and printing a scaling summary so throughput plateaus are visible instead of being inferred from one-off runs.
    - [x] The orchestrator can now sweep native runtime thread counts (`--native-runtime-thread-counts 1-8`), exporting `native_runtime_threads` alongside `router_workers` in JSONL/Prometheus artifacts so HTTP throughput can be graphed against the actual transport-side scaling knob instead of inferring from router-worker changes.
    - [x] Bench workers now reuse HTTP/2 and HTTP/3 sessions by default, prebuild request payload buffers once per worker, and report both response-only and total payload throughput so sustained runs measure transport work instead of repeated handshakes.
    - [x] HTTP/2 bench workloads can now fan multiple concurrent streams through each reused connection (`streams_per_connection`), the runtime thread sweep now uses that knob for the H2 workload, and a dedicated `h2_multiplex_scaling.toml` scenario was added for focused same-connection transport sweeps.
    - [x] HTTP/3 bench workloads now use the same `streams_per_connection` knob, the runtime thread sweep drives H3 with 4 in-flight streams per reused connection, and a dedicated `h3_multiplex_scaling.toml` scenario plus overlap test coverage were added so the QUIC path is benchmarked under real same-connection multiplexing instead of serialized request loops.
    - [x] Worker-sweep regressions for the HTTP bench path were eliminated by moving streamed HTTP responses off per-chunk WAMP progress payloads; the sustained worker sweep no longer drops when `router_workers` increases on the default `/bench/stream` workload.
    - [x] `_RouterBoss` now paces its poll loop adaptively instead of always sleeping `pollInterval`, and the HTTP boss/binding hot paths no longer print per-request debug logs, so runtime-thread sweeps measure transport scaling instead of scheduler/logging tax.
    - [x] Release-built HTTP/3-only sweeps with the tuned QUIC transport now sustain roughly 3.9 Gbps at 1 native runtime thread and 4.6 Gbps at 2 threads in this environment; the earlier 6-thread collapse disappeared, so the remaining ceiling is treated as a workload/multiplexing limit rather than a broken thread-count setting.
    - [x] Release-built `h2_multiplex_scaling` sweeps now sustain roughly 3.64 Gbps at 1 native runtime thread and 5.90 Gbps at 4 threads in this environment, so the tuned HTTP/2 path scales monotonically once the bench drives multiple streams per reused connection instead of one hot request at a time.
    - [x] Release-built `h3_multiplex_scaling` sweeps now sustain roughly 3.14 Gbps at 1 native runtime thread and 4.35 Gbps at 4 threads in this environment, so the bench no longer measures serialized HTTP/3 request loops when `streams_per_connection > 1`.
  - [x] Ship Prometheus exporters and Grafana dashboards for benchmark metrics visualization.
  - [x] Provide docs/scripts to bootstrap a local Grafana/Prometheus stack alongside benchmarks.
- [ ] MCP (Model Context Protocol) server implementation for agentic AI integrations
  - [x] First usable local bridge path for downstream applications is complete:
    server core, stdio transport, and WAMP-backed tool delegation.
  - [x] Research the current official MCP lifecycle, transport, tools, prompts,
    and resources contracts, then record implementation decisions in checked-in
    docs before coding.
  - [x] Land the first narrow Dart API/server slice in `packages/connectanum_mcp`
    covering initialization, capability negotiation, tool discovery, tool
    calls, and clean shutdown/error behavior with focused tests.
  - [x] Add a stdio transport adapter and small CLI example.
  - [x] Add the WAMP-backed tool delegate for Connectanum procedure calls.
  - [x] Add router-hosted HTTP MCP integration for applications that need a
    network endpoint: `HttpRouteActionType.mcp` reuses the router internal
    session, auto-exposes exact WAMP registrations, WAMP meta API tools, and
    pub/sub helpers over JSON-RPC `POST`.
  - [x] Add the router-hosted Streamable HTTP foundation: explicit MCP session
    IDs, strict HTTP header validation, Origin policy, DELETE session
    termination, GET/SSE polling, server-to-client tool-list notifications, and
    bounded `Last-Event-ID` resume handling.
  - [x] Add POST-initiated SSE response streams for stateful operation
    requests that opt into Streamable HTTP, while preserving JSON responses for
    `initialize` and direct JSON-only clients.
  - [x] Add an IO-only Streamable HTTP client entrypoint in
    `packages/connectanum_mcp` so consumer applications can initialize
    router-hosted MCP sessions, send authenticated JSON-RPC requests, consume
    POST/SSE responses, poll GET/SSE events with resume cursors, and delete
    sessions without reimplementing the transport.
  - [x] Add configured router-hosted MCP resources, resource templates, and
    prompts so a router route can advertise read-only context and prompt
    templates without starting a separate MCP server.
- [x] WAMP profile transport benchmark production readiness
  - [x] Active after the first usable MCP path; use it to make
    RawSocket/WebSocket WAMP transport performance release-decision ready
    before speculative transport exploration resumes.
  - [x] Define the canonical WAMP benchmark gate set across cleartext/TLS,
    Dart/native clients, JSON/MessagePack/CBOR, RPC/pub/sub, auth/session
    setup, mixed serializer, PPT payload mode, fan-out, and control paths.
  - [x] Add scenario-specific throughput and latency budgets to the bench
    artifact gate and record local plus hosted Linux baselines.
  - [x] Make public-facing benchmark artifacts human-readable enough for users
    to understand what passed, what regressed, and which transport/profile owns
    the failure.
- [ ] Metrics & logging integration (Prometheus metrics, structured logs, CPU/RAM/throughput gauges)
  - [x] Always-on low-cost counters (native/Dart) exposed via on-demand snapshots for benchmark harnesses. `ct_router_metrics_snapshot` feeds `_RouterBoss` + `_MetricsService`, so the OpenMetrics payload now carries GOAWAY/backpressure/timeout totals.
  - [x] Prometheus/Grafana wiring documented; HTTP scrape regression added (metrics route bridged to `connectanum.metrics.openmetrics`) and CI now captures `CONNECTANUM_ARTIFACT_DIR` OpenMetrics/JSON snapshots from long-payload regressions.
  - [x] Bench stack ships Prometheus alert rules plus Grafana dashboards for transport alerts/throttle state, and the snapshot JSON now exposes current alert state for non-Prometheus consumers.
  - [x] Bench artifact outputs (`bench_results.jsonl`) now rewrite into Prometheus textfile metrics plus a summary JSON bundle, with alert rules over the transformed per-workload transport deltas so completed runs surface automatically in dashboards/alerts.
  - [x] Bound OpenMetrics scrape collection with `open_metrics.collection_timeout_ms` so stalled boss/worker metrics collection returns an explicit scrape failure instead of holding Prometheus connections indefinitely.
  - [x] Redact configured OpenMetrics bearer tokens from metrics snapshot exporter metadata; snapshots expose only a non-secret `auth_required` flag.
  - [x] Metrics exporter produces OpenMetrics-compatible output over a dedicated HTTP listener and bridges requests to snapshot RPCs on demand without background polling.
  - [x] Bind the metrics realm to a configurable HTTP endpoint so Prometheus scrapers can poll without a WAMP client, with optional non-empty bearer-token auth.
  - [ ] Configurable metrics exporter isolates (Prometheus) gated by crossbar-compatible config flags to avoid production overhead.
  - [ ] Sampling windows for high-cost histograms (latency, zero-copy reuse) triggered only during benchmarks.
  - [ ] Metrics realm configuration: expose internal realms via config (enable/disable, rename) and spin up embedded sessions automatically to serve metrics RPCs.
  - [ ] Include process/VM stats and native runtime counters in the snapshot so scraped data reflects full router health.
    - [x] Export router process PID plus current/max RSS in the JSON snapshot and OpenMetrics payload without background polling.
    - [ ] Add heap and CPU-delta gauges once there is a low-overhead sampling strategy.
  - [ ] Support zero-copy payload handling in all bridge interactions (lazy decode, file proxying, file-backed responses).

- [ ] HTTP/1.1, HTTP/2, HTTP/3 transport layer (long-polling, streaming WAMP)
  - [ ] HTTP bridge defined via listener configuration; translate REST ↔ WAMP using long-poll transport semantics while preserving zero-copy handles.
  - [ ] Provide authentication hooks for bridge (static tokens, mTLS, pluggable validators) and document OAuth proxy strategy for external scrapers.
