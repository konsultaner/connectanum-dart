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
  - [x] Replace per-frame WebSocket `Vec` allocation with pooled owner-backed buffers, keep single-frame WAMP payloads zero-copy through WAMP parse + FFI/Dart, reassemble continuations in pooled storage, and write outbound segmented frames without flattening.
- [ ] Serializer matrix (JSON, MessagePack, CBOR, UBJSON, FlatBuffers)
  - [ ] Cross-serializer translation so mixed clients (e.g. JSON ↔ MessagePack/CBOR) can publish/call across encodings without data loss; include regression tests for EVENT, RESULT, and ERROR bridging and document zero-copy fallbacks.
- [x] Backpressure / flow control between workers and native layer
- [ ] Multi-protocol listener stack (RawSocket/WebSocket/HTTP/1.1/HTTP/2/HTTP/3)
  - [ ] Implement a unified accept loop in the native runtime with ALPN + HTTP Upgrade negotiation so a single endpoint can downgrade/upgrade between RawSocket, WebSocket, and HTTP transports.
  - [ ] Maintain zero-copy buffers across all negotiated protocols (frame handles for RawSocket/WebSocket continuation frames, shared body handles for HTTP).
  - [ ] Handle HTTP/2 CONTINUATION frames and HTTP/3 header block fragments without copying (keep partial headers in native memory until complete).
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
    - [ ] Track upstream WAMP conformance suite (wamp-proto/wamp-proto#557) and integrate it into CI to validate RawSocket/WebSocket/HTTP/2/HTTP/3 transports and serializer combinations against the official test matrix.
- [ ] HTTP bridge (general-purpose request handling)
  - [ ] Expose bridge configuration via listener protocols with pluggable pipelines (REST→RPC proxy, static asset serving, metrics scraping, custom handlers).
  - [ ] Support translation tables that map HTTP path/method/protocol combinations to explicit WAMP realms and procedures, including per-method overrides and catch-all wildcards.
  - [ ] Provide reserved realm/namespace shorthand so routes can auto-map into a router-managed HTTP realm with deterministic URI derivation (e.g. `/` → `router.http.index`).
  - [ ] Allow namespace-based auto-mapping (path segments → URI prefixes) for teams already organising registrations by namespace.
  - [ ] Enforce method/protocol whitelists from the configuration; return 405/426 at the native layer before touching Dart.
  - [x] Keep HTTP payloads zero-copy by exposing request/response body handles over FFI and streaming through Rust.
  - [x] Surface structured responses (status, headers, trailers) back to the native runtime without materialising entire payloads in Dart.
  - [ ] Offer middleware hooks (logging, rate limiting, throttling) that run inside worker isolates while heavy I/O remains in Rust.
  - [x] Land `HttpRequestContext`/`HttpResponseUtil` in Dart so HTTP routes can read bodies lazily, pipe uploads directly to disk, and send structured responses (status/headers/body) back through the boss without copies.
  - [x] Extend FFI to accept structured HTTP responses (status, headers, zero-copy body descriptors, streaming handles) and flush them to the native runtime.
  - [x] Provide zero-copy response helpers: in-memory slices, file-backed payloads, and streaming writers with back-pressure.
  - [x] Implement initial HTTP response FFI plumbing (status/headers/bytes) in `ct_core`/`ct_ffi` and patch Dart runtime to call it.
  - [x] Add OpenMetrics HTTP exporter (`metrics.open_metrics.listen`) for Prometheus scraping and cover with tests.
  - [x] Route HTTP bridge requests into internal sessions via borrowed native body descriptors instead of serializing request bytes into invocation payload maps.
  - [x] Forward streamed HTTP bridge response chunks across the internal-session isolate hop with transferable buffers so large progress payloads avoid repeated `Uint8List` copies.
  - [x] Bypass the per-chunk WAMP response envelope for streamed HTTP bridge responses: internal sessions now open borrowed native response-stream descriptors once, write chunks directly from the callee isolate, and emit only a final completion result back through the call lifecycle.
  - [x] Add end-to-end zero-copy HTTP regressions (large request/response plus descriptor-based internal-session routing) to ensure no stray serialization occurs in Dart.
  - [ ] Introduce adapter pipeline support (static file handler, PHP-FPM/FastCGI bridge, reverse proxy stubs) configurable per route; document adapter contracts and lifecycle.
  - [ ] `Add tests/doc coverage for the new HTTP call contract` (Dart unit tests, router integration test asserting response round-trip, native tests validating file/stream paths).
- [ ] HTTP authentication & session tokens
  - [ ] Reuse endpoint authenticators (CRA, SCRAM, remote delegates) to issue short-lived access tokens for HTTP clients; tokens include target realm information from a header or query parameter.
  - [ ] Provide a configurable auth/refresh route (defaults to `/auth`) reserved inside the HTTP namespace so clients can obtain and refresh tokens.
  - [ ] Enforce endpoint-level transport auth (TLS/mTLS/ALPN) before route-level checks; reject unauthorised requests in the native layer.
  - [ ] Implement refresh token handling (configurable TTL, dedicated handler in reserved realm) with support for issuing new access tokens without replaying the full handshake.
  - [ ] Propagate auth context (`_authid`, `_authrole`, `_authmethod`) into the WAMP invocation details so downstream procedures honour existing router policies.
- [ ] HTTP bridge (general-purpose request handling)
  - [ ] Expose bridge configuration via listener protocols with pluggable pipelines (REST→RPC proxy, static asset serving, metrics scraping, custom handlers).
- [ ] HTTP bridge (general-purpose request handling)
  - [ ] Map incoming REST requests to internal router sessions through an in-memory transport so PHP/FCM or other external services can act as lightweight proxies.
  - [ ] Provide policy-driven routing (path → WAMP procedure/topic, file proxy, custom isolate handler) with per-route auth hooks aligned with realm permissions.
  - [x] Support request/response streaming and file-backed payloads to preserve zero-copy semantics for large bodies.
  - [x] Surface structured responses (status, headers, trailers) back to the native runtime without materialising entire payloads in Dart.
  - [ ] Offer middleware hooks (logging, rate limiting, throttling) that run inside worker isolates while heavy I/O remains in Rust.
- [ ] HTTP forwarding hooks for custom routing/handling in RPC implementations
  - [ ] Graceful shutdown (drain sessions, send GOODBYE/HTTP responses, stop listeners)
    - [ ] Provide unified HTTP bridge that can surface Prometheus/Grafana exporters alongside REST→WAMP translation.
    - [ ] Support structured metrics endpoints over HTTP/2 and HTTP/3 so observability stack can scrape without extra proxies.
- [x] Outbound frame bridge (`ct_send`/FFI) for CHALLENGE/WELCOME/EVENT delivery
- [ ] End-to-end payload encryption (E2EE) strategy
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
  - [x] Worker invocation forwarding uses cloned native handles
  - [x] Tests ensure YIELD/ERROR paths dispose clones correctly

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
      - [ ] Introduce authenticated transport to the remote service (mutual TLS and/or signed tokens) and automatic credential rotation hooks.
      - [ ] Restrict serialized payload to the minimal required auth fields; validate schema on both request and response before issuing `CHALLENGE`/`WELCOME`.
      - [ ] Preserve “fake challenge” behavior on remote rejection while logging audit details for operators.
      - [ ] Add integration tests spinning up a stub remote service to verify success, rejection, timeout, and abort flows end-to-end.
      - [ ] Build a constrained remote-auth client stub in the bench orchestrator to fuzz HELLO/CHALLENGE/AUTHENTICATE flows without full WAMP clients (rawsocket frame pusher), and instrument latency/backpressure on remote auth RPCs.
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
- [ ] Realm-level authorizers (permission checks before SUBSCRIBE/PUBLISH/etc.)
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
- [ ] Dart 3.10+ build hooks to compile `ct_ffi` during pub install/`dart pub get` (detect Rust toolchains, allow opting out for prebuilt/shared lib consumers, and document `CONNECTANUM_NATIVE_LIB` override).
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
- [ ] Remote auth secure transport (mTLS / signed tokens) and credential rotation
- [ ] Fake challenge parity & stub remote service integration tests
- [ ] Internal transport support for embedded router↔client flows
  - [ ] Define in-process transport abstraction (frame routing with backpressure)
  - [ ] Embed internal session inside edge router to speak RemoteAuthenticatorDelegate over the new transport
  - [ ] Auth server runs router instance + internal client that talks to credential providers
  - [ ] Wire configuration knobs for selecting internal vs TCP transports
  - [ ] Migrate existing delegate tests/examples to the internal transport once available
- [ ] End-to-end smoke tests (native runtime ↔ router ↔ client)
- [ ] Benchmarks (throughput/latency per worker configuration)
  - [ ] Provide release-build workflow for `ct_ffi` (and document `CONNECTANUM_NATIVE_LIB` usage) dedicated to performance runs.
  - [ ] Implement a reusable load generator (multi-session HELLO/PUB/SUB/RPC workloads) to stress the router.
  - [ ] Expose lightweight instrumentation (per-worker queue depth, handle retention counts, throughput/latency timers) for benchmark reporting.
  - [ ] Add automation scripts that run warm-up + steady-state cycles and emit latency/throughput summaries.
  - [x] Added rawsocket publish+ACK regression test (`publish_ack_test.dart`) covering `bench.control` realm with `libct_ffi.so`.
  - [x] Ship the HTTP/2 streaming benchmark harness (`packages/connectanum_router/tool/http_stream_bench.dart`) that drives real uploads/downloads and reports router transport metric deltas via `binding.collectMetrics()`.
  - [x] Land the native bench orchestrator (Rust client + Dart router runner) outlined in `native/bench/README.md` so scenarios/scripts can be shared across CI and local perf runs.
    - [x] Bench runner exposes `/bench/*` HTTP control routes backed by internal RPC handlers (`bench_router.json`), and the Rust scaffold now pings `/bench/healthz`, `/bench/metrics`, and `/bench/stop` before shutting down.
    - [x] Orchestrator loads TOML scenarios (`native/bench/scenarios/h2_smoke.toml`, `full_stack.toml`), drives HTTP/2 workloads via `hyper` with prior knowledge, captures router metrics snapshots before/after each workload, emits JSONL summaries (`bench_results.jsonl`), and enforces per-workload timeouts so hung runs fail fast instead of wedging CI.
  - [x] WAMP pub/sub benchmark stability: `wamp_smoke` now passes after fixing EVENT serialization (details/kwargs) and guarding malformed kwargs; bench runs no longer hang during pubsub.
  - [x] Extend the harness for HTTP/3/TLS runs, persist OpenMetrics snapshots after each scenario, and integrate the results with Prometheus dashboards.
    - [x] HTTP/3/TLS support landed in the orchestration CLI (QUIC prior-knowledge via `quinn`+`h3`, shared-port overrides, h3-only scenarios) so benchmarks can exercise both transports while capturing metrics deltas.
    - [x] `/bench/metrics` now returns both the router snapshot and the OpenMetrics payload, and the orchestrator serializes `open_metrics_before`/`open_metrics_after` fields per workload (`bench_results.jsonl` + docs updated).
    - [x] Bench results are transformed automatically into `bench_results.prom` + `bench_results.summary.json`, the Docker compose stack ingests the `.prom` output through the node-exporter textfile collector, and Prometheus/Grafana ship matching artifact rules + dashboards for per-workload regression surfacing.
    - [x] The orchestrator can now sweep router worker counts (`--router-worker-counts 1-8`), rewriting the bench router config per run, stamping JSONL/Prometheus artifact rows with `router_workers`, and printing a scaling summary so throughput plateaus are visible instead of being inferred from one-off runs.
    - [x] The orchestrator can now sweep native runtime thread counts (`--native-runtime-thread-counts 1-8`), exporting `native_runtime_threads` alongside `router_workers` in JSONL/Prometheus artifacts so HTTP throughput can be graphed against the actual transport-side scaling knob instead of inferring from router-worker changes.
    - [x] Bench workers now reuse HTTP/2 and HTTP/3 sessions by default, prebuild request payload buffers once per worker, and report both response-only and total payload throughput so sustained runs measure transport work instead of repeated handshakes.
    - [x] Worker-sweep regressions for the HTTP bench path were eliminated by moving streamed HTTP responses off per-chunk WAMP progress payloads; the sustained worker sweep no longer drops when `router_workers` increases on the default `/bench/stream` workload.
    - [x] `_RouterBoss` now paces its poll loop adaptively instead of always sleeping `pollInterval`, and the HTTP boss/binding hot paths no longer print per-request debug logs, so runtime-thread sweeps measure transport scaling instead of scheduler/logging tax.
    - [x] Release-built HTTP/3-only sweeps with the tuned QUIC transport now sustain roughly 3.9 Gbps at 1 native runtime thread and 4.6 Gbps at 2 threads in this environment; the earlier 6-thread collapse disappeared, so the remaining ceiling is treated as a workload/multiplexing limit rather than a broken thread-count setting.
  - [x] Ship Prometheus exporters and Grafana dashboards for benchmark metrics visualization.
  - [x] Provide docs/scripts to bootstrap a local Grafana/Prometheus stack alongside benchmarks.
- [ ] MCP (Model Context Protocol) server implementation for agentic AI integrations
- [ ] Metrics & logging integration (Prometheus metrics, structured logs, CPU/RAM/throughput gauges)
  - [x] Always-on low-cost counters (native/Dart) exposed via on-demand snapshots for benchmark harnesses. `ct_router_metrics_snapshot` feeds `_RouterBoss` + `_MetricsService`, so the OpenMetrics payload now carries GOAWAY/backpressure/timeout totals.
  - [x] Prometheus/Grafana wiring documented; HTTP scrape regression added (metrics route bridged to `connectanum.metrics.openmetrics`) and CI now captures `CONNECTANUM_ARTIFACT_DIR` OpenMetrics/JSON snapshots from long-payload regressions.
  - [x] Bench stack ships Prometheus alert rules plus Grafana dashboards for transport alerts/throttle state, and the snapshot JSON now exposes current alert state for non-Prometheus consumers.
  - [x] Bench artifact outputs (`bench_results.jsonl`) now rewrite into Prometheus textfile metrics plus a summary JSON bundle, with alert rules over the transformed per-workload transport deltas so completed runs surface automatically in dashboards/alerts.
  - [ ] Configurable metrics exporter isolates (Prometheus) gated by crossbar-compatible config flags to avoid production overhead.
  - [ ] Sampling windows for high-cost histograms (latency, zero-copy reuse) triggered only during benchmarks.
  - [ ] Metrics realm configuration: expose internal realms via config (enable/disable, rename) and spin up embedded sessions automatically to serve metrics RPCs.
  - [ ] Metrics exporter produces OpenMetrics-compatible output over a dedicated HTTP listener; bridge requests snapshot RPCs on demand (no background polling). (Current exporter returns OpenMetrics via WAMP; needs HTTP ingress + auth.)
  - [ ] Bind the metrics realm to a configurable HTTP endpoint so Prometheus scrapers can poll without a WAMP client (per-router session auth + optional tokens).
  - [ ] Include process/VM stats (RSS, heap, CPU deltas) and native runtime counters in the snapshot so scraped data reflects full router health.
  - [ ] Support zero-copy payload handling in all bridge interactions (lazy decode, file proxying, file-backed responses).

- [ ] HTTP/1.1, HTTP/2, HTTP/3 transport layer (long-polling, streaming WAMP)
  - [ ] HTTP bridge defined via listener configuration; translate REST ↔ WAMP using long-poll transport semantics while preserving zero-copy handles.
  - [ ] Provide authentication hooks for bridge (static tokens, mTLS, pluggable validators) and document OAuth proxy strategy for external scrapers.
