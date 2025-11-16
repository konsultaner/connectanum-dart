# Next Session Overview

Fresh state:
- PUB/SUB has non-blocking ACK handling with `worker_publish_routed` tracing; the standalone rawsocket publish+ACK test now passes (`publish_ack_test.dart` against `libct_ffi.so`).
- WAMP bench/pubsub hangs fixed: EVENT serialization now includes details/kwargs and guards malformed kwargs, so `wamp_smoke` completes cleanly (pubsub + rpc) with 4 publishers/subscribers.
- RPC flow supports full invocation lifecycle, including `CANCEL` modes and zero-copy RESULT/ERROR forwarding with buffer-release tests.
- Analyzer still reports info-level issues isolated to `packages/connectanum_auth_server`; production packages are clean.
- JSON/MessagePack/CBOR serializers preserve custom option/detail fields; HTTP/2 and HTTP/3 responses stream directly from Rust into Dart (`context.streamResponse`) without buffering multi-MB payloads.

Focus for the next session:
1. **Boss Telemetry Stream & Prometheus Exporter**
   - ✅ `ct_router_metrics_snapshot` aggregates GOAWAY/backpressure/timeout counters, `_RouterBoss` now polls it each loop, and `_MetricsService` renders the HTTP stats inside the OpenMetrics payload/tests.
   - Next up: break the snapshot down by listener/protocol, cache it inside the boss telemetry stream, and expose it via the metrics realm’s HTTP endpoint (configurable auth/token) so Prometheus can scrape without a WAMP client.
   - Follow-on: document the boss telemetry stream, update STRUCTURE/ROADMAP once the HTTP exporter is wired, and keep listen_flow + router runtime coverage in sync.

2. **HTTP/2 + HTTP/3 Deadline Enforcement**
   - Enforce the remaining idle/body deadlines for HTTP/2/HTTP/3 readers, emit GOAWAY with explicit reasons, and extend `listen_flow.rs` to cover the new timeout branches.
   - Mirror those scenarios in Dart (`router_runtime_test.dart`, worker/boss suites) so regressions get caught before Prometheus/benchmark runs.

3. **HTTP Streaming Regression Coverage**
  - ✅ HTTP/1.1 chunked writers + `_HttpResponseStream` plumbing are live, `listen_flow::http_response_streaming_round_trip` covers the native writer, router integration tests stream 60 KB uploads/downloads, `listen_flow::http3_response_streaming_round_trip` exercises the QUIC path, boss/runtime tests cover HTTP/2+HTTP/3 streaming, the new `tool/http_stream_bench.dart` CLI drives real HTTP/2 transfers while reporting router transport metric deltas, the bench runner exposes `/bench/*` HTTP control routes, and the Rust orchestrator now loads TOML scenarios (`h2_smoke`, `full_stack`) to drive HTTP/2 workloads via `hyper` and HTTP/3 workloads via `quinn`/`h3`, recording router metrics snapshots + JSONL summaries before stopping the Dart runner. Per-workload timeouts ensure hung regressions self-abort, the Dart bench process now always exits cleanly after `/bench/stop`, and every `/bench/metrics` call returns the OpenMetrics payload which is stored as `open_metrics_before`/`open_metrics_after` in `bench_results.jsonl`.
   - Next: publish the captured OpenMetrics blobs to a Prometheus/Grafana stack (either by scraping the embedded exporter or transforming the JSONL output), then wire the harness into CI so regressions surface before release.
   - Add the dedicated zero-copy HTTP regression harness the user requested (Rust listen_flow + Dart router/integration) so Prometheus exporters and perf scripts can rely on multi-MB streaming tests before each run.

4. **WebSocket Transport Completion**
   - Finish native WebSocket processing: accept/deny is in place, but we still need frame read/write loops that translate WebSocket frames into RawSocket WAMP messages (continuation aggregation, mask handling, ping/pong, close). Surface selected serializer/subprotocol back over FFI.
   - Wire up Dart boss/runtime: expose `takeWebSocketHandshake`, implement subprotocol selection and `acceptWebSocket`/`rejectWebSocket`, then route accepted connections to workers as standard WAMP transports. Add router runtime/integration tests that cover successful upgrades, unsupported subprotocols, and connection shutdown.
   - Add Rust + Dart regression suites to ensure WebSocket clients can publish/call via WAMP end-to-end, including large payloads and continuation frames.

5. **Pattern Routing & Shared Registrations**
   - Implement wildcard/prefix ordering + priority handling and un-skip the advanced-profile placeholder test.
   - Introduce shared registration policies (round-robin/first/last) and wire invocation dispatch to respect them.

6. **Authrole Filters & Analyzer Hygiene**
   - Enforce authrole include/exclude lists when broadcasting EVENTs and extend tests accordingly.
   - Resolve remaining analyzer warnings by fixing `packages/connectanum_auth_server` dependencies/imports or documenting follow-up tasks.

7. **HTTP Routing & Auth Pipeline**
   - Design the HTTP route translation table (path/method/protocol → realm/procedure) plus the reserved realm/namespace shortcuts.
   - Implement the reserved auth/refresh route (default `/auth`) with configurable overrides and build the CRA/SCRAM-to-token bridge.
   - Enforce endpoint-level auth defaults for HTTP, including realm selection via header/query parameter and short-lived access tokens.
   - Deliver HTTP response utilities (status/headers/body helpers) and metrics endpoint plumbing atop the new FFI path; include `HttpResponseUtil`/`HttpRequestContext` helpers for router sessions so handlers can choose between inline bodies and zero-copy file/stream adapters.
   - Capture adapter extensibility in the plan (static assets, PHP-FPM/FastCGI, reverse proxies) so the translation table can bind routes to pluggable responders once the zero-copy primitives land.

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

Regression / validation to run after changes:
- `dart test packages/connectanum_router/test/router_worker_session_test.dart --chain-stack-traces`
- `dart test packages/connectanum_router/test/router_worker_auth_test.dart`
- `dart test packages/connectanum_router`
- `dart test packages/connectanum_core/test/serializer/json/serializer_test.dart`
- `dart analyze`
- `cargo test -p ct_ffi listen_flow`
