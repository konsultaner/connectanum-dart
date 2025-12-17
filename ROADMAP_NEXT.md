# Next Session Overview

Fresh state:
- PUB/SUB has non-blocking ACK handling with `worker_publish_routed` tracing; the standalone rawsocket publish+ACK test now passes (`publish_ack_test.dart` against `libct_ffi.so`).
- WAMP bench/pubsub hangs fixed: EVENT serialization now includes details/kwargs and guards malformed kwargs, so `wamp_smoke` completes cleanly (pubsub + rpc) with 4 publishers/subscribers.
- RPC flow supports full invocation lifecycle, including `CANCEL` modes and zero-copy RESULT/ERROR forwarding with buffer-release tests.
- Zero-copy publish forwarding can be toggled at runtime via `CONNECTANUM_FORWARD_NATIVE_PUBLISH` (env or compile-time); boss telemetry sends no longer block the forwarding path, and the skipped PUB/SUB native tests now run with the flag set.
- GOAWAY detail assertions now cover HTTP/2 and HTTP/3 in both native `listen_flow` and Dart runtime suites.
- Negotiated WebSocket subprotocol/serializer surfaces over FFI (`ct_connection_websocket_protocol`) and flows into boss/worker metadata, so listeners and workers can trace/route WebSocket WAMP sessions consistently.
- Boss-side metrics now track listener backpressure and transport lifecycle spikes with configurable thresholds (`metrics.backpressure` / `metrics.transport_alerts`), throttling accepts and emitting alerts when GOAWAY/timeout deltas jump.
- Analyzer still reports info-level issues isolated to `packages/connectanum_auth_server`; production packages are clean.
- JSON/MessagePack/CBOR serializers preserve custom option/detail fields; HTTP/2 and HTTP/3 responses stream directly from Rust into Dart (`context.streamResponse`) without buffering multi-MB payloads.

Focus for the next session:
1. **Boss Telemetry Stream & Prometheus Exporter**
   - ✅ `ct_router_metrics_snapshot` aggregates GOAWAY/backpressure/timeout counters, `_RouterBoss` now polls it each loop, and `_MetricsService` renders the HTTP stats inside the OpenMetrics payload/tests.
   - ✅ Snapshot now splits by listener/protocol, caches in the boss telemetry stream, and the metrics realm HTTP endpoint (with optional auth/token) exposes the per-listener counters for Prometheus without a WAMP client.
   - ✅ Boss emits listener backpressure/transport alerts (GOAWAY, idle/body timeouts, protocol/internal errors) based on configurable thresholds and throttles accepts during spikes; tests now assert GOAWAY details and alert emission. OpenMetrics exporter now surfaces those alert counters per reason/listener, and the config knobs are documented in `docs/router_metrics.md`.
   - Next up: add Prometheus rules/dashboards for alert counters, and pipe alert snapshots into the metrics JSON payload so external consumers can inspect the current throttle state.

2. **HTTP/2 + HTTP/3 Deadline Enforcement**
   - Enforce the remaining idle/body deadlines for HTTP/2/HTTP/3 readers, emit GOAWAY with explicit reasons, and extend `listen_flow.rs` to cover the new timeout branches.
   - Mirror those scenarios in Dart (`router_runtime_test.dart`, worker/boss suites) so regressions get caught before Prometheus/benchmark runs.

3. **HTTP Streaming Regression Coverage**
- ✅ HTTP/1.1 chunked writers + `_HttpResponseStream` plumbing are live, `listen_flow::http_response_streaming_round_trip` covers the native writer, router integration tests stream 60 KB uploads/downloads, `listen_flow::http3_response_streaming_round_trip` exercises the QUIC path, boss/runtime tests cover HTTP/2+HTTP/3 streaming, the new `tool/http_stream_bench.dart` CLI drives real HTTP/2 transfers while reporting router transport metric deltas, the bench runner exposes `/bench/*` HTTP control routes, and the Rust orchestrator now loads TOML scenarios (`h2_smoke`, `full_stack`) to drive HTTP/2 workloads via `hyper` and HTTP/3 workloads via `quinn`/`h3`, recording router metrics snapshots + JSONL summaries before stopping the Dart runner. Per-workload timeouts ensure hung regressions self-abort, the Dart bench process now always exits cleanly after `/bench/stop`, and every `/bench/metrics` call returns the OpenMetrics payload which is stored as `open_metrics_before`/`open_metrics_after` in `bench_results.jsonl`. Native `listen_flow` now covers HTTP/3 handshakes, stream polling, and multi-connection scenarios end-to-end under QUIC with ALPN `h3` after fixing the client verifier/ALPN wiring, and the Dart router integration harness now drives HTTPS + HTTP/3 streaming end-to-end via the new native test client helper and bundled TLS fixtures.
  - Next: publish the captured OpenMetrics blobs to a Prometheus/Grafana stack (either by scraping the embedded exporter or transforming the JSONL output), then wire the harness into CI so regressions surface before release.
  - ✅ Dedicated zero-copy HTTP regression harness (Rust listen_flow + Dart router/integration) now runs HTTPS and QUIC streaming scenarios against `router_integration_native_test.dart`; expand it with multi-MB permutations before Prometheus/bench CI absorbs it.
  - [ ] Adopt the upstream WAMP conformance suite (wamp-proto/wamp-proto#557) once merged, and run it against our RawSocket/WebSocket/HTTP/2/HTTP/3 transports and serializer matrix in CI to validate protocol compliance alongside our bespoke regressions.
  - ✅ HTTP/3 streaming integration test now runs its QUIC client on a dedicated isolate using the ffi-test helper and bundled CA/cert/key, so the Dart boss remains responsive while the native client drains the stream (timeout regression fixed).

4. **WebSocket Transport Completion**
   - ✅ Frame read/write loops are live; new `listen_flow::websocket_wamp_round_trip` drives masked client frames into the native reader and asserts the server writer replies with WAMP payloads, covering the end-to-end WebSocket transport path.
   - ✅ Dart boss/runtime now exercises subprotocol selection in tests (`router_runtime_test.dart` covers accept + reject paths via synthetic WebSocket handshakes); `ct_connection_websocket_protocol` + Dart bindings surface the negotiated subprotocol so boss/worker metadata and telemetry include it. Next: tighten continuation aggregation/mask handling/ping-pong/close coverage.
   - ✅ Route accepted WebSocket connections into workers as standard WAMP transports, poll WebSocket message handles in the boss loop, and cover the end-to-end dispatch with runtime tests.
   - ✅ Add worker-session regression tests that ensure WebSocket connections receive publish ACKs and CALL errors, keeping WAMP flows aligned with RawSocket behaviour.
   - Add Rust + Dart regression suites to ensure WebSocket clients can publish/call via WAMP end-to-end, including large payloads and continuation frames.
   - Plan zero-copy slices: refactor `ct_core` WebSocket storage to use a pooled slab (no per-frame Vec alloc), keep parsed WAMP frames as slices (offset/len) into that pool, expose slice-based handles via FFI (separate WebSocket handle store from RawSocket), and extend Dart bindings to retain/release those slices and decode directly without copying. Add tests to verify pool reuse, lifetime safety across FFI, and mixed RawSocket/WebSocket flows.

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
   - Draft the benchmarking plan (release build workflow, load generator scaffold, metrics hooks, automation scripts) and land the initial harness pieces.

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
   - Add Dart 3.10+ build hooks that compile the Rust `ct_ffi` backend during pub get/install so consumers no longer need manual `cargo build` steps; gate platform detection and allow opting out for prebuilt/shared-lib setups.

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
