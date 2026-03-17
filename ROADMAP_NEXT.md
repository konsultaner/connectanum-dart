# Next Session Overview

Fresh state:
- Native transport heartbeat/ping-pong is enforced (RawSocket + WebSocket), and router sessions can be closed on `session_idle_ms` from the boss; coverage includes Rust `listen_flow` heartbeat + close tests and Dart router runtime idle-session enforcement.
- Native outbound send queues are bounded (RawSocket + WebSocket); when saturated, `ct_send_message` surfaces a backpressure error instead of growing unbounded memory.
- PUB/SUB has non-blocking ACK handling with `worker_publish_routed` tracing; the standalone rawsocket publish+ACK test now passes (`publish_ack_test.dart` against `libct_ffi.so`).
- WAMP bench/pubsub hangs fixed: EVENT serialization now includes details/kwargs and guards malformed kwargs, so `wamp_smoke` completes cleanly (pubsub + rpc) with 4 publishers/subscribers.
- RPC flow supports full invocation lifecycle, including `CANCEL` modes and zero-copy RESULT/ERROR forwarding with buffer-release tests.
- Zero-copy publish forwarding can be toggled at runtime via `CONNECTANUM_FORWARD_NATIVE_PUBLISH` (env or compile-time); boss telemetry sends no longer block the forwarding path, and the skipped PUB/SUB native tests now run with the flag set.
- GOAWAY detail assertions now cover HTTP/2 and HTTP/3 in both native `listen_flow` and Dart runtime suites.
- Negotiated WebSocket subprotocol/serializer surfaces over FFI (`ct_connection_websocket_protocol`) and flows into boss/worker metadata, so listeners and workers can trace/route WebSocket WAMP sessions consistently.
- Boss-side metrics now track listener backpressure and transport lifecycle spikes with configurable thresholds (`metrics.backpressure` / `metrics.transport_alerts`), throttling accepts and emitting alerts when GOAWAY/timeout deltas jump.
- Analyzer still reports info-level issues isolated to `packages/connectanum_auth_server`; production packages are clean.
- JSON/MessagePack/CBOR serializers preserve custom option/detail fields; HTTP/2 and HTTP/3 responses stream directly from Rust into Dart (`context.streamResponse`) without buffering multi-MB payloads.
- Dart WebSocket integration suite now drives WAMP publish/call flows over WebSocket (continuation frames, large payloads) and asserts negotiated subprotocol/serializer on acceptance.
- Multi-MB HTTP/2 + HTTP/3 streaming regressions landed with optional OpenMetrics artifact dumps (`CONNECTANUM_ARTIFACT_DIR`) and a Prometheus scrape regression targeting the metrics HTTP route.
- Bench JSONL results now rewrite automatically into `native/bench/artifacts/bench_results.prom` + `bench_results.summary.json`; the bundled Prometheus stack ingests them through node-exporter textfile collection and loads dedicated alert rules/dashboard panels for post-run transport regressions.
- Bench runs can now sweep router worker counts (`--router-worker-counts 1-8`) and native runtime thread counts (`--native-runtime-thread-counts 1-8`), and every JSONL / transformed Prometheus row is labeled with `router_workers` plus `native_runtime_threads` so scaling limits are visible directly in the artifact dashboards.
- `_RouterBoss` no longer injects a fixed `pollInterval` sleep after busy passes, and the HTTP boss/binding hot paths no longer emit per-request debug prints; focused runtime-thread reruns now show the earlier “extra parallelism regresses HTTP/3” result was largely scheduler/logging noise rather than a deterministic worker-count bug.
- Dart 3.10+ build hooks now compile `ct_ffi` automatically during `dart run`/`dart test` via `packages/connectanum_router/hook/build.dart`, and the runtime loader prefers artifacts under `.dart_tool/hooks_runner`.
- RawSocket/WebSocket outbound send queues are now configurable via `outbound_send_queue_capacity` to cap memory usage under slow readers (still surfaces backpressure via `SendQueueFull`).
- Router shutdown/drain now closes native listeners up-front (`ct_listener_close`) so no new accepts are queued while workers drain; `/healthz` reports `draining` during shutdown and OpenMetrics exports drain counters.

Focus for the next session:
1. **Boss Telemetry Stream & Prometheus Exporter**
   - ✅ `ct_router_metrics_snapshot` aggregates GOAWAY/backpressure/timeout counters, `_RouterBoss` now polls it each loop, and `_MetricsService` renders the HTTP stats inside the OpenMetrics payload/tests.
   - ✅ Snapshot now splits by listener/protocol, caches in the boss telemetry stream, and the metrics realm HTTP endpoint (with optional auth/token) exposes the per-listener counters for Prometheus without a WAMP client.
   - ✅ Boss emits listener backpressure/transport alerts (GOAWAY, idle/body timeouts, protocol/internal errors) based on configurable thresholds and throttles accepts during spikes; tests assert GOAWAY details and alert emission. OpenMetrics exporter surfaces alert counters per reason/listener, including backpressure reason labels and throttled counts; config knobs + threshold examples are documented in `docs/router_metrics.md`.
   - ✅ Metrics JSON payloads now export live alert snapshots (active throttles, remaining cooldown, last alert metadata), and OpenMetrics adds throttle gauges for Prometheus consumers.
   - ✅ Bench assets now include `native/bench/connectanum_router_alerts.yml` plus a provisioned Grafana dashboard for transport alerts/throttle state.
   - Next up: keep `listen_flow` + router runtime coverage in sync as the alert metrics evolve, and add CI gating so transformed bench artifacts can fail runs automatically on transport regressions.

2. **HTTP/2 + HTTP/3 Deadline Enforcement**
   - ✅ Enforced idle/body deadlines for HTTP/2 + HTTP/3 request-body readers; HTTP/3 timeouts now close the QUIC connection to avoid `h3-quinn` stop-sending races while still emitting lifecycle events with explicit details.
   - ✅ Extended native `listen_flow.rs` coverage for HTTP/2 idle timeouts plus HTTP/3 idle/body timeouts, and mirrored the body-timeout lifecycle mapping in Dart (`router_runtime_test.dart`).

3. **HTTP Streaming Regression Coverage**
- ✅ HTTP/1.1 chunked writers + `_HttpResponseStream` plumbing are live, `listen_flow::http_response_streaming_round_trip` covers the native writer, router integration tests stream 60 KB uploads/downloads, `listen_flow::http3_response_streaming_round_trip` exercises the QUIC path, boss/runtime tests cover HTTP/2+HTTP/3 streaming, the new `tool/http_stream_bench.dart` CLI drives real HTTP/2 transfers while reporting router transport metric deltas, the bench runner exposes `/bench/*` HTTP control routes, and the Rust orchestrator now loads TOML scenarios (`h2_smoke`, `full_stack`, `throughput_smoke`) to drive HTTP/2 workloads via `hyper` and HTTP/3 workloads via `quinn`/`h3`, recording router metrics snapshots + JSONL summaries before stopping the Dart runner. Per-workload timeouts ensure hung regressions self-abort, the Dart bench process now always exits cleanly after `/bench/stop`, every `/bench/metrics` call returns the OpenMetrics payload which is stored as `open_metrics_before`/`open_metrics_after` in `bench_results.jsonl`, and the default HTTPS control plane (`https://localhost:8080/bench`) plus bundled self-signed TLS cert now work out of the box for both the control endpoints and TLS-backed HTTP/2 smoke workloads. Bench workers now keep HTTP/2 and HTTP/3 sessions hot across iterations by default and reuse the same request payload buffers, so throughput runs are less dominated by repeated handshakes. Native `listen_flow` now covers HTTP/3 handshakes, stream polling, and multi-connection scenarios end-to-end under QUIC with ALPN `h3` after fixing the client verifier/ALPN wiring, and the Dart router integration harness now drives HTTPS + HTTP/3 streaming end-to-end via the new native test client helper and bundled TLS fixtures. Multi-MB HTTP/2/HTTP/3 integration suites now run in `router_integration_native_test.dart`, dump OpenMetrics/JSON snapshots when `CONNECTANUM_ARTIFACT_DIR` is set, and the new CI job builds `ct_ffi` + uploads those artifacts.
  - ✅ Bench artifacts are transformed alongside `bench_results.jsonl` into Prometheus textfile metrics and a summary JSON bundle; the bench compose stack loads matching alert rules and a Grafana dashboard so regressions surface automatically after each run.
  - ✅ Dedicated zero-copy HTTP regression harness (Rust listen_flow + Dart router/integration) now runs HTTPS and QUIC streaming scenarios against `router_integration_native_test.dart`; expand it with multi-MB permutations before Prometheus/bench CI absorbs it.
  - ✅ Internal-session HTTP bridge calls now pass borrowed native request-body descriptors instead of copied byte arrays, streamed response chunks cross the isolate hop via transferable buffers, and the bench `/bench/stream` handler drains/echoes bodies without forcing `request.body` materialization first.
  - ✅ Streamed HTTP bridge responses now request a native response-stream descriptor once, write chunks directly from the internal-session isolate, and emit only a final completion result through the shared call lifecycle. The sustained worker sweep no longer regresses when `router_workers` increases on the default bench workload.
  - [ ] Adopt the upstream WAMP conformance suite (wamp-proto/wamp-proto#557) once merged, and run it against our RawSocket/WebSocket/HTTP/2/HTTP/3 transports and serializer matrix in CI to validate protocol compliance alongside our bespoke regressions.
  - ✅ HTTP/3 streaming integration test now runs its QUIC client on a dedicated isolate using the ffi-test helper and bundled CA/cert/key, so the Dart boss remains responsive while the native client drains the stream (timeout regression fixed).

4. **WebSocket Transport Completion**
   - ✅ Frame read/write loops are live; new `listen_flow::websocket_wamp_round_trip` drives masked client frames into the native reader and asserts the server writer replies with WAMP payloads, covering the end-to-end WebSocket transport path.
   - ✅ Dart boss/runtime exercises subprotocol selection in tests (`router_runtime_test.dart` covers accept + reject paths via synthetic WebSocket handshakes); `ct_connection_websocket_protocol` + Dart bindings surface the negotiated subprotocol/serializer so boss/worker metadata and telemetry include it.
   - ✅ Dart WebSocket integration suite (real WebSocket transport) drives publish/call flows with continuation frames + multi-MB payloads and asserts the negotiated subprotocol/serializer.
   - ✅ Route accepted WebSocket connections into workers as standard WAMP transports, poll WebSocket message handles in the boss loop, and cover the end-to-end dispatch with runtime tests.
   - ✅ Add worker-session regression tests that ensure WebSocket connections receive publish ACKs and CALL errors, keeping WAMP flows aligned with RawSocket behaviour.
   - ✅ Tightened RFC 6455 control-frame handling: client masking is enforced, reserved bits / fragmented controls / oversized control payloads are rejected with protocol close frames, close reasons must be valid UTF-8, and empty close frames echo without leaking reserved code `1005`.
   - ✅ Rust `listen_flow` now covers client ping -> server pong, server heartbeat ping -> client pong, empty close echoes, and unmasked-frame rejection; Dart `router_integration_websocket_test.dart` mirrors ping/pong + close behavior on the real boss/runtime path.
   - ✅ `ct_core` now uses pooled owner-backed buffers for inbound WebSocket frames; single-frame WAMP payloads stay zero-copy through WAMP parse + FFI/Dart, fragmented messages reassemble in pooled storage, and the writer streams existing `Bytes` segments without flattening.
   - ✅ Added Rust pool/writer regressions plus Dart `native_runtime_test.dart` coverage that polls a real WebSocket message handle and verifies args/kwargs slice pointers stay inside the native frame buffer.
   - ✅ HTTP/1.1 ingress now parses with `BytesMut`, keeps buffered bodies as `Bytes` inside `HttpBodyHandle`, preserves prefetched bytes across the handshake/body-reader handoff, and Dart/native regressions cover inline vs streaming request bodies on the real runtime path.
   - ✅ HTTP/2 and HTTP/3 body readers now enqueue inbound `Bytes` directly into `StreamingBodyState` instead of cloning each chunk into a temporary `Vec`.
  - Next: keep widening the native-runtime thread-count sweep now that boss pacing/logging no longer distort it, profile the remaining HTTP/3-specific scaling ceiling beyond 4 threads, then shrink the remaining small buffered-prefix copy at the `BufReader` handoff and move on to HTTP/2 header-fragment / multi-stream server completion work.

5. **Pattern Routing & Shared Registrations**
   - Implement wildcard/prefix ordering + priority handling and un-skip the advanced-profile placeholder test.
   - Introduce shared registration policies (round-robin/first/last) and wire invocation dispatch to respect them.

6. **Authrole Filters & Analyzer Hygiene**
   - Enforce authrole include/exclude lists when broadcasting EVENTs and extend tests accordingly.
   - Resolve remaining analyzer warnings by fixing `packages/connectanum_auth_server` dependencies/imports or documenting follow-up tasks.

7. **Remote Authentication Hardening & HTTP Auth Bridge**
   - Wire authenticated transport to the remote auth service (mTLS or signed tokens) with rotation hooks.
   - Validate remote auth request/response schema strictly; keep payload minimal before issuing `CHALLENGE`/`WELCOME`.
   - Preserve “fake challenge” behaviour on remote rejection; add integration tests with a stub remote service (success/rejection/timeout/abort) for WAMP HELLO/CHALLENGE/AUTHENTICATE.
   - Add a constrained rawsocket frame pusher in the bench orchestrator to fuzz remote auth without full WAMP clients and collect latency/backpressure metrics.
   - Design the HTTP auth bridge: reserved `/auth` route to delegate CRA/SCRAM-to-token, realm selection via header/query, endpoint-level auth defaults for HTTP.
   - Deliver HTTP response helpers and keep metrics plumbing ready for the auth bridge.

8. **Benchmark Readiness**
   - ✅ Bench harness pieces are in place: Dart runner, Rust orchestrator, TOML scenarios, transformed Prometheus/summary artifacts, default HTTPS/TLS smoke runs over HTTP/2 + HTTP/3, and sustained-transfer scenarios that reuse hot transport sessions.
   - Next: add CI gating over the transformed artifacts, and keep extending the runtime-thread sweep scenarios so HTTP benchmarks chart the real transport-side scaling axis alongside router worker isolates without scheduler/logging skew from the Dart boss path.

9. **Documentation & Examples**
   - Update router/auth docs to capture cancellation semantics, drain behaviour, and zero-copy guarantees.
   - Expand the example gallery (progressive results + cancellation walkthrough) to help integrators.

10. **Serializer Interop Bridge**
   - Add translation pipelines so mixed clients (JSON ↔ MessagePack ↔ CBOR) can exchange EVENT/RESULT/ERROR frames seamlessly, with fallbacks that keep zero-copy semantics where possible.
   - Extend serializer/router tests to cover cross-encoding publish/call scenarios.

11. **E2EE Research Spike**
   - Outline options for end-to-end payload encryption without incurring Dart 64-bit object overhead (e.g. offloading to Rust FFI or dedicated binary isolates).
   - Identify handshake/key-management changes required in HELLO/CHALLENGE and how they interact with zero-copy routing.

12. **Packaging & Build Hooks**
   - ✅ Add Dart 3.10+ build hook that compiles the Rust `ct_ffi` backend during `dart run`/`dart test` (native assets build hooks).
   - Next: add a publishable packaging story (prebuilt artifacts per platform or vendoring Rust sources inside a publishable package), plus opt-out knobs for deployments that provide a system/shared library.

13. **TLS & Deployment Hardening**
   - ✅ Native TCP TLS termination (rustls + SNI) is live.
   - ✅ mTLS client certificate auth is supported for native TLS endpoints (`tls.client_auth`).
   - ✅ TLS reload hooks are available via `ct_reload_tls`; the runner reloads certs/CA on `SIGHUP`.
   - ✅ Router runner exposes an OpenMetrics HTTP endpoint when `metrics.open_metrics.listen` is set (`/metrics` + `/healthz`).
   - ✅ Deployment templates added under `deploy/` (Docker/systemd/K8s) plus updated production docs/configs.
   - Next: CI packaging for prebuilt `ct_ffi` artifacts (and multi-arch container images), plus kTLS exploration/benchmarks.

Regression / validation to run after changes:
- `dart test packages/connectanum_router/test/router_worker_session_test.dart --chain-stack-traces`
- `dart test packages/connectanum_router/test/router_worker_auth_test.dart`
- `dart test packages/connectanum_router`
- `dart test packages/connectanum_core/test/serializer/json/serializer_test.dart`
- `dart analyze`
- `cargo test -p ct_ffi listen_flow`
