# Native Bench Orchestrator (Design Draft)

This document captures the architecture for the upcoming benchmarking helper that
will drive HTTP/2 and HTTP/3/QUIC workloads against the Dart router while
recording transport metrics deltas.

## Goals

1. **End-to-end realism** – benchmarks must exercise the shipping stack (Dart
   boss/workers + native runtime). The orchestrator only drives traffic and
   gathers metrics, it never replaces the router.
2. **Deterministic scenarios** – every run specifies payload sizes, chunking
   patterns, pauses, and concurrency so regressions are reproducible and easy to
   diff.
3. **Metrics first** – before and after each scenario the orchestrator captures
   `ct_router_metrics_snapshot` (via the Dart binding) and, when enabled,
   downloads the Prometheus/OpenMetrics payload. Throughput numbers are always
   coupled with transport counters (GOAWAY, idle/body timeouts, backpressure).

## High-level Architecture

```
┌────────────────────────┐
│ dart run bench_main.dart│  (spawns RouterBinding, registers handlers,
│  • loads config         │   exposes metrics gRPC/WAMP/HTTP)
│  • exposes metrics port │
└────────────┬───────────┘
             │ start/stop via CLI args / stdin control channel
             ▼
┌────────────────────────┐          ┌─────────────────────────────┐
│ Rust orchestrator CLI  │          │ Scenario config (JSON/TOML) │
│  native/bench/src/bin  │ <──────> │  • payload sizes            │
│  • spawns Dart router  │          │  • chunk patterns           │
│  • drives HTTP/2 via   │          │  • pauses, concurrency      │
│    h2                  │          │  • iterations, warmup       │
│  • multiplexes H2/H3   │          │  • streams per connection   │
│  • drives HTTP/3 via   │          └─────────────────────────────┘
│    quinn + h3          │
│  • collects metrics    │─────► jsonl / stdout summaries
└────────────────────────┘
```

### Components

| Component                         | Description                                                                                   |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `bench_main.dart` (new target)   | Applies the bench router config, registers HTTP handlers, spins up internal bench sessions **and external clients** (RawSocket, WebSocket, `connectanum_client`), exposes a tiny control API (stdin + `/bench/*` HTTP routes) to signal readiness/shutdown, and serves metrics snapshots on demand. |
| Rust orchestrator binary         | Lives under `native/bench/src/bin/http_stream.rs`. Parses scenario files / CLI flags, can sweep router worker counts and native runtime thread counts, spawns the Dart runner, waits for readiness, and then executes a list of workloads. |
| Scenario configuration           | Simple TOML/JSON describing iterations, upload/download bytes, chunk sizes, pauses, and parallel streams. Stored under `native/bench/scenarios/`. |
| Load generators                  | In-process clients: direct `h2` for HTTP/2, quinn+h3 for HTTP/3, a plain `reqwest` fallback for HTTP/1.1 sanity checks, **and Dart-side WAMP clients (RawSocket/WebSocket) so the connectanum client stack is exercised**. Each generator reports status, latency, bytes, and optionally stream IDs. |
| Metrics collectors               | Before/after every scenario the orchestrator calls the router-served `/bench/metrics` endpoint (backed by `binding.collectMetrics()` + the OpenMetrics exporter), capturing both the JSON snapshot delta and the full OpenMetrics text so Prometheus-ready output is archived alongside throughput stats. |

## Execution Flow

1. `cargo run -p ct_ffi --bin http_stream_bench -- --scenario scenarios/h3_long.toml`
2. Orchestrator spawns `dart run packages/connectanum_router/tool/bench_main.dart --config …` and waits for a “ready” line on stdout.
3. Capture baseline metrics (`/metrics/snapshot` endpoint).
4. For each configured workload:
   1. Run warm-up iterations (optional).
   2. Fire upload/download streams using the selected protocol client(s).
   3. Record per-iteration latency/throughput.
5. Capture post-run metrics, compute deltas, and emit both a human-readable summary and structured JSON lines.
6. Tell the Dart process to shut down and exit once it stops.

## Telemetry to Record Per Run

| Metric                                 | Source                                                                               |
|----------------------------------------|--------------------------------------------------------------------------------------|
| Bytes uploaded / downloaded            | In-process client (counts chunks)                                                    |
| Latency / throughput                   | In-process client stopwatch                                                         |
| GOAWAY / protocol errors               | `RouterTransportMetrics` delta (via `/metrics/snapshot`)                             |
| Idle/body timeout counts               | `RouterTransportMetrics` delta                                                       |
| Backpressure events + max depth        | `RouterTransportMetrics` delta                                                       |
| Prometheus/OpenMetrics payload (opt)   | HTTP GET against the metrics exporter configured by `bench_main.dart`                |

## Implementation Plan

1. **Dart bench runner**
   - Live in `packages/connectanum_bench/tool/bench_main.dart`.
   - Flags/config for listeners, HTTP routes, control realm auth, response chunk sizes.
   - Starts router, registers HTTP handlers, spins up required internal sessions, and launches external `connectanum_client` instances for RawSocket/WebSocket mass tests.
   - Exposes `/bench/healthz`, `/bench/metrics`, `/bench/stop`, `/bench/reload` via the router’s HTTP stack. Also prints `READY` to stdout and listens for `STOP` on stdin.
2. **Rust orchestrator (native/bench crate)**
   - New crate under `native/bench/` with binaries like `http_stream.rs`.
   - Parses scenario files (TOML/JSON), spawns the Dart bench runner, waits for `/bench/healthz`, and coordinates workloads.
   - Implements HTTP/2 (`h2`) and HTTP/3 (`quinn`) generators, plus optional HTTP/1.1 sanity checks.
   - Calls `/bench/metrics` before/after each workload to capture deltas, and serializes the embedded OpenMetrics payload next to the raw snapshot.
   - Writes stdout summaries and structured JSONL for downstream tooling.
3. **Scenario samples**
   - `h2_small.toml` (many short streams).
   - `h2_large.toml` (multi-MB uploads/downloads).
   - `h3_idle.toml` (deliberate pauses to trigger idle/body timeouts).
   - `wamp_smoke.toml` / `all_transports_smoke.toml` (transport-aware connectanum_client workloads over RawSocket and WebSocket alongside HTTP traffic).
   - `mass_connections.toml` (thousands of short-lived sessions to stress connect/disconnect paths; later extended with “remote auth” when that feature lands).
   - `mass_auth.toml` (remote authenticator heavy-load scenario to validate CRA/SCRAM/remote delegates once implemented).
4. **Output format**
   - `bench_results.jsonl` capturing per-iteration numbers + metric deltas.
   - `native/bench/artifacts/bench_results.prom` rendered from the JSONL so the
     Prometheus textfile collector can ingest workload summaries automatically.
   - `native/bench/artifacts/bench_results.summary.json` with the same
     per-workload rollups in a diff-friendly JSON bundle.
   - Human summary printed to stdout (similar to the current Dart tool).
5. **CI integration**
   - Add a smoke scenario to the router integration suite (guarded by feature flag) once the orchestrator is committed.
   - Track the follow-up task to migrate the connectanum clients to zero-copy once the client package supports it.
   - Plan for “mass connection / mass authentication” scenarios to be part of CI once remote auth and the reconnect logic are fully wired.

The orchestrator crate, scenarios, and supporting scripts now live here; the remaining work is mainly scenario growth, better scaling studies, and CI gating.

## Bench Router Configuration & Control API

The Dart runner ships with a default `bench_router.json` that exposes an HTTPS
control listener on `127.0.0.1:8080` with HTTP/2 and a dedicated HTTP/3 port
(`8443`), plus a separate plain WAMP listener on `127.0.0.1:8081` for
RawSocket/WebSocket transport benchmarks. The control listener maps the
`/bench/*` paths to internal RPC handlers:

| Path              | Method | Procedure            | Description                                |
|-------------------|--------|----------------------|--------------------------------------------|
| `/bench/healthz`  | GET    | `bench.http.healthz` | Liveness probe that returns `{"status":"ok"}`. |
| `/bench/metrics`  | GET    | `bench.http.metrics` | Snapshot of `binding.collectMetrics()` so orchestrators can diff counters between runs. |
| `/bench/stop`     | POST   | `bench.http.stop`    | Acknowledges the request and triggers the shutdown flow (mirrors the STOP stdin command). |
| `/bench/stream`   | POST   | `bench.http.stream`  | Drains/generated-responses or echoes the request body through `HttpRequestSnapshot.nativeBody`, so HTTP routing and the internal-session bridge stay on the streamed/descriptor path. |

All handlers continue to be callable over WAMP, which keeps the YAML scenario
runner and existing integration tests working without changes. The Rust
orchestrator now pings `/bench/healthz`, fetches `/bench/metrics`, and issues a
POST to `/bench/stop` before waiting for the Dart process to exit, ensuring the
HTTP routes are live before real workloads are added.

### Scenario Format

Workloads are described in TOML under `native/bench/scenarios/`. Each scenario
declares a name plus a list of workloads. Every workload describes the
protocol, HTTP method/path, request/response byte counts, chunk sizes, warm-up
delays, concurrency, and whether transport sessions should be reused across
iterations (`reuse_connections`, default `true`). WAMP workloads also accept a
`serializer` field (`json`, `msgpack`, `cbor`; default `json`) so the same
transport bench can compare serializer overhead directly, an optional
`peer_serializer` field so the caller/publisher can talk to a real remote
callee/subscriber using a different serializer, plus an `in_flight_per_session`
knob (default `1`) that keeps multiple publishes/calls outstanding on each hot
WAMP session. Native WebSocket WAMP workloads also accept
`websocket_fragment_size` so a single encoded message can be sent as deliberate
RFC 6455 continuation frames and benchmarked on the live router path. Example
(`h2_smoke.toml`):

```toml
name = "h2_smoke"
description = "Minimal HTTP/2 streaming echo workload used for harness bring-up."

[[workloads]]
name = "warmup"
protocol = "h2"
path = "/bench/stream"
method = "POST"
iterations = 2
concurrency = 1
request_bytes = 65536
response_bytes = 65536
request_chunk_bytes = 32768
response_chunk_bytes = 32768
warmup_ms = 500

[[workloads]]
name = "load"
protocol = "h2"
path = "/bench/stream"
method = "POST"
iterations = 4
concurrency = 2
streams_per_connection = 2
request_bytes = 262144
response_bytes = 262144
request_chunk_bytes = 65536
response_chunk_bytes = 65536
```

The bench HTTP handler honors the `x-bench-response-bytes` and
`x-bench-response-chunk-bytes` headers so the orchestrator can request arbitrary
response sizes/chunking regardless of the inbound payload. When those headers
are present, the handler drains the request body through the native body stream
first instead of materializing `request.body`, which keeps the benchmark aligned
with the router’s descriptor-based HTTP bridge. Streamed responses now open one
native response-stream descriptor per request and write chunks directly from the
internal-session isolate, so the benchmark no longer pays a per-chunk WAMP
progress envelope on `/bench/stream`.

When `reuse_connections = true`, each worker keeps a hot HTTP/2 or HTTP/3
session across iterations and reuses the same prebuilt request payload buffer.
HTTP/1.1 workloads now use the same knob for keep-alive reuse on the shared
router bridge. Set it to `false` if you explicitly want a handshake-heavy
benchmark.

`streams_per_connection` controls how many concurrent HTTP/2 or HTTP/3 request
streams a worker keeps in flight on each reused connection. The default is `1`.
Set it above `1` when you want to stress same-connection multiplexing; it
requires `reuse_connections = true`. HTTP/1.1 still rejects values above `1`
because the bench path does not pipeline H1 requests.

### Scenario Catalog

- `h2_smoke.toml` – short warm-up + load + HTTP/3 probe to validate plumbing after a
  build. Use this for quick sanity checks.
- `h1_smoke.toml` – HTTP/1.1 keep-alive streaming smoke used to verify that reused
  sockets continue draining requests across the boss/runtime bridge.
- `throughput_smoke.toml` – sustained-transfer scenario that keeps sessions hot across
  iterations and is a better fit for rough throughput checks than `h2_smoke`.
- `worker_scaling.toml` – sustained-transfer scenario intended for `--router-worker-counts`
  sweeps so you can sanity-check that changing the router worker pool does not
  introduce regressions on the HTTP bench path.
- `runtime_thread_scaling.toml` – sustained-transfer scenario intended for
  `--native-runtime-thread-counts` sweeps. This is the real scaling axis for
  HTTP/2 and HTTP/3 because request execution stays centered on the boss plus
  the native Tokio runtime rather than the router worker pool. Recent router
  pacing cleanup removed a fixed busy-loop sleep and per-request HTTP debug
  logging from the Dart hot path, so these sweeps now reflect transport scaling
  much more closely than the earlier worker-count-only runs. The H2 and H3
  workloads in this scenario now drive `4` concurrent streams per reused
  connection so the thread sweep measures actual multiplexing instead of only
  one hot request at a time.
- `h2_multiplex_scaling.toml` – focused H2-only sustained-transfer scenario that
  drives `4` streams per reused connection. Use this when you want a clean
  same-connection HTTP/2 throughput sweep without the H3 workload in the same
  run.
- `h3_multiplex_scaling.toml` – focused H3-only sustained-transfer scenario that
  drives `4` streams per reused connection. Use this when you want a clean
  same-connection HTTP/3 throughput sweep without the H2 workload in the same
  run.
- `full_stack.toml` – extended matrix covering bulk uploads/downloads, latency spikes,
  idle soak phases, and both HTTP/2 and HTTP/3 transfers with higher concurrency.
- `wamp_smoke.toml` – lightweight PUB/SUB and RPC workloads over both RawSocket and
  WebSocket, now covering the full mode/serializer matrix (`json`, `msgpack`,
  `cbor`) on both transports so smoke runs can catch serializer-specific
  regressions on either RPC or pub/sub paths.
- `wamp_serializer_matrix.toml` – larger-payload RawSocket/WebSocket RPC sweep
  that runs JSON, MessagePack, and CBOR side by side to compare serializer
  overhead without HTTP traffic in the same run. The current version enables
  `in_flight_per_session = 4` so it behaves like a throughput sweep instead of
  one outstanding call per session.
- `wamp_transport_throughput.toml` – larger-payload RawSocket/WebSocket pub/sub
  plus RPC sweep covering JSON, MsgPack, and CBOR on both transports so
  hot-session throughput comparisons stay apples-to-apples across modes and
  serializers.
- `wamp_client_impl_smoke.toml` – small-payload RawSocket/WebSocket RPC + pub/sub
  comparison between Dart and native `connectanum_client` implementations on
  the same workloads.
- `wamp_client_impl_throughput.toml` – 64 KiB RawSocket/WebSocket RPC + pub/sub
  comparison between Dart and native `connectanum_client` implementations on
  the same hot-session workloads. The current native path keeps PPT-wrapped
  args/kwargs on shared `LazyMessagePayload` views until a workload actually
  asks for decoded payloads, so backend-style pass-through workloads are not
  forced through eager Dart `List`/`Map` materialization first.
- `wamp_ppt_lazy_smoke.toml` – focused RawSocket/WebSocket CBOR PPT workload for
  both Dart and native clients. Use this when you want to sanity-check that
  live router traffic still preserves `ppt_*` options, lazy payload bytes, and
  decoded inner args/kwargs across the full transport path.
- `wamp_mixed_serializer_throughput.toml` – 64 KiB RawSocket/WebSocket RPC +
  pub/sub sweep that uses `peer_serializer` to open a real remote
  callee/subscriber with a different serializer, so JSON/MessagePack/CBOR
  bridge costs can be compared directly for both Dart and native clients.
- `wamp_websocket_fragmentation_throughput.toml` – 64 KiB native WebSocket
  MsgPack/CBOR RPC + pub/sub sweep that compares contiguous sends against
  explicit continuation-frame workloads (`websocket_fragment_size = 4096`) on
  the same live router path, so the segmented native WebSocket
  parser/storage path and contiguous masked-writer path are both measured
  directly instead of only pinned by transport regressions.
- `all_transports_smoke.toml` – quick cross-transport smoke covering RawSocket,
  WebSocket, HTTP/1.1, HTTP/2, and HTTP/3 in one run. The WAMP side now mixes
  JSON, MessagePack, and CBOR across RawSocket/WebSocket workloads so serializer
  regressions show up in the default cross-transport run.
- `real_world_smoke.toml` – higher-connection smoke that mixes RawSocket and
  WebSocket WAMP pubsub/RPC with HTTP/2 and HTTP/3 fanout; roughly 2k
  RawSocket WAMP connections plus a smaller WebSocket comparison load and
  high-concurrency HTTP fanout/asset echoes to probe backpressure.

### TLS Setup & Running the Orchestrator

`bench_main.dart` expects a TLS/SNI bundle whenever HTTP/2 or HTTP/3 is enabled. We ship a
local self-signed pair for `localhost` under `native/bench/bench_tls.crt` and
`native/bench/bench_tls.key`. The default `bench_router.json` references those files via the
`certificate_chain_file`/`private_key_file` knobs, so no extra setup is required unless you want to
use your own certs. The Rust orchestrator now accepts that bundled self-signed cert for its HTTPS
control plane and TLS-backed HTTP/2 workloads, so the default smoke/full-stack scenarios run
without extra trust-store setup as long as you target `https://localhost:8080/bench`.

1. Make sure the native runtime is rebuilt so the latest TLS/ALPN changes are in the shared library:
   ```sh
   cargo build --manifest-path native/transport/Cargo.toml -p ct_ffi --release
   ```
   This produces `native/transport/target/release/libct_ffi.so` (or `.dylib`/`.dll` on other
   platforms). Point the bench runner at that file via `--native-lib` or set
   `CONNECTANUM_NATIVE_LIB`.

2. Run the orchestrator:

Run whichever scenario you need by pointing `--scenario` at the desired file. For
example, the full-stack matrix. For a more representative hot-session throughput
sample, point it at `native/bench/scenarios/throughput_smoke.toml` instead of the
handshake-oriented `h2_smoke.toml`. To study scaling, use
`native/bench/scenarios/runtime_thread_scaling.toml` together with
`--native-runtime-thread-counts`, `h2_multiplex_scaling.toml` or
`h3_multiplex_scaling.toml` when you want a focused same-connection transport
multiplex sweep, or `worker_scaling.toml` with `--router-worker-counts` when
you only want a router-worker sanity check.
Use `cargo run --release` for throughput work; the debug/profile-default
orchestrator is fine for harness development, but HTTP/3 numbers in particular
are noisy enough in debug builds to mislead scaling conclusions.

```
cargo run --release --manifest-path native/bench/Cargo.toml -- \
  --router-config native/bench/bench_router.json \
  --scenario native/bench/scenarios/full_stack.toml \
  --control-base https://localhost:8080/bench \
  --h3-port 8443 \
  --native-lib native/transport/target/release/libct_ffi.so
```

The CLI will:

1. Spawn the Dart bench runner (`bench_main.dart`) with the supplied router
   config/native library.
2. Wait for the `READY` banner, poll `/bench/healthz`, and fetch `/bench/metrics`
   (which now returns both the JSON snapshot and the OpenMetrics text).
3. Execute each workload from the scenario file. With the default
   `bench_router.json`, HTTP/2 runs negotiate TLS + ALPN `h2` against the
   bundled self-signed cert, while HTTP/3 workloads establish QUIC connections
   via `quinn` + `h3` (ALPN `h3`), allowing the same benchmark to stress both
   transports. If you point `--control-base` at plain `http://...`, the
   orchestrator falls back to cleartext HTTP/2 prior-knowledge mode.
4. Capture metrics snapshots (plus the accompanying OpenMetrics payload) before
   and after every workload, append a row to `bench_results.jsonl`, and print a
   human-readable summary with latency, response throughput, total payload
   throughput, connection reuse state, and router counter deltas.
   The orchestrator also rewrites the cumulative JSONL into
   `bench_results.prom` and `bench_results.summary.json` after each workload so
   Prometheus/Grafana always see the latest run without a manual conversion
   step.
5. Issue `/bench/stop` (falling back to the stdin `STOP` command if needed) and
   wait for the Dart process to exit cleanly.

The JSONL output records per-workload metadata (router metrics snapshots,
OpenMetrics text, effective `router_workers`, effective `native_runtime_threads`,
latency samples, and total bytes) so downstream tooling
(Prometheus exporters, dashboards, regression detectors) can diff runs without
scraping stdout.

### Worker Sweep Runs

Use `--router-worker-counts` to rerun the same scenario against multiple router
worker-pool sizes. The flag accepts comma-separated values and inclusive ranges:

```sh
cargo run --release --manifest-path native/bench/Cargo.toml -- \
  --router-config native/bench/bench_router.json \
  --scenario native/bench/scenarios/worker_scaling.toml \
  --router-worker-counts 1-8 \
  --control-base https://localhost:8080/bench \
  --h3-port 8443 \
  --native-lib native/transport/target/release/libct_ffi.so
```

Each sweep point starts a fresh bench runner with `router.worker_pool.min_workers`
overridden to the requested value, appends labeled rows to `bench_results.jsonl`,
and rewrites the artifact bundle. Prometheus labels every workload series with
`router_workers`, and the CLI prints a compact scaling summary after the run so
it is obvious where throughput stops improving.

### Native Runtime Thread Sweep Runs

Use `--native-runtime-thread-counts` to rerun the same scenario against multiple
Tokio runtime thread counts. This flag accepts comma-separated values, inclusive
ranges, and `auto`:

```sh
cargo run --release --manifest-path native/bench/Cargo.toml -- \
  --router-config native/bench/bench_router.json \
  --scenario native/bench/scenarios/runtime_thread_scaling.toml \
  --router-worker-counts 1 \
  --native-runtime-thread-counts 1-4 \
  --control-base https://localhost:8080/bench \
  --h3-port 8443 \
  --native-lib native/transport/target/release/libct_ffi.so
```

Each sweep point starts a fresh bench runner with
`CONNECTANUM_NATIVE_RUNTIME_THREADS` set for that process. JSONL rows,
Prometheus textfile artifacts, and the CLI scaling summary all include
`native_runtime_threads` so HTTP throughput can be graphed against the actual
transport-side scaling knob.

For HTTP/2, the orchestrator can now drive multiple in-flight streams through a
single reused connection. Recent release-built `h2_multiplex_scaling` sweeps in
this environment held roughly `3.64 Gbps` at `1` native runtime thread and
`5.90 Gbps` at `4` threads, with throughput increasing monotonically once the
bench stopped measuring only one hot H2 request stream per connection.

HTTP/3 now uses the same per-connection multiplexing knob. Recent
release-built `h3_multiplex_scaling` sweeps in this environment held roughly
`3.14 Gbps` at `1` native runtime thread and `4.35 Gbps` at `4` threads, so the
bench no longer under-reports H3 by serializing request loops on each reused
connection.

The router and the Rust HTTP/3 bench client now both apply explicit Quinn
transport tuning (stream windows, send window, datagram buffers, keep-alive)
instead of relying on the library defaults tuned for a much lower-bandwidth
link. In this environment, recent release-built H3-only sweeps held roughly
`3.9 Gbps` at `1` native runtime thread and `4.6 Gbps` at `2` threads, with the
older pathological `6`-thread collapse no longer reproducing.

If you already have a JSONL file from CI or an earlier run, regenerate the
Prometheus/textfile bundle without rerunning the workloads:

```sh
cargo run --release --manifest-path native/bench/Cargo.toml --bin transform_results -- \
  --input native/bench/artifacts/bench_results.jsonl
```

To run the WAMP-only scenario:

```
cargo run --release --manifest-path native/bench/Cargo.toml -- \
  --router-config native/bench/bench_router.json \
  --scenario native/bench/scenarios/wamp_smoke.toml \
  --control-base https://localhost:8080/bench \
  --native-lib native/transport/target/release/libct_ffi.so
```

The WAMP workloads use transport-specific protocol labels:

- `wamp_rawsocket_pubsub`
- `wamp_rawsocket_rpc`
- `wamp_websocket_pubsub`
- `wamp_websocket_rpc`

`path` is interpreted as the topic URI for `*_pubsub` workloads and as the
procedure URI for `*_rpc` workloads. `request_bytes` sets the payload size sent
in each publish/call (which is echoed back for RPC). The legacy
`wamp_pubsub` / `wamp_rpc` labels still map to RawSocket for backward
compatibility.

Recent `all_transports_smoke` runs in this environment exposed and then fixed a
major RawSocket client-side latency issue: the Dart RawSocket transport now
disables Nagle (`tcpNoDelay`) and writes WAMP frames as a single socket write
instead of splitting frame headers and payloads into separate writes. After
that change, the same smoke scenario moved RawSocket pub/sub latency from about
`45 ms` down to about `6.7 ms` on loopback, much closer to the WebSocket path
(`~3.6 ms` here).

The same cross-transport bench also exposed a router-side inefficiency: the
boss loop was probing dedicated RawSocket accepts for HTTP/3 handshakes even
though `connectionProtocol()` had already resolved them as RawSocket. That
probe is gone now, so RawSocket/WebSocket transport runs no longer emit
`ct_connection_take_http3_handshake ... unsupported protocol RawSocket` noise.

The bench harness now also exercises MessagePack and CBOR over the live router
instead of only JSON. Router-side outbound MsgPack `RESULT` serialization and
the native CBOR decode/encode path were completed so RawSocket/WebSocket WAMP
benchmarks can run the same HELLO/CALL/RESULT flow across all three serializers.

The serializer matrix also exposed a client-side correctness bug: several
request/reply APIs were sending `CALL` / acknowledged `PUBLISH` / `SUBSCRIBE` /
`UNSUBSCRIBE` / `REGISTER` / `UNREGISTER` before arming the matching listener on
the session broadcast stream. Fast RawSocket/WebSocket replies could therefore
be dropped even though the router succeeded. That race is fixed now, so
`wamp_serializer_matrix.toml` completes reliably instead of hanging on the
successful RawSocket/CBOR path.

The PPT-focused smoke run then exposed a live CBOR correctness gap: outbound
CBOR `PUBLISH` / `CALL` / `YIELD` frames were not serializing `ppt_*` option
fields, so the router could not preserve PPT metadata on the real wire path
even though the lazy/native paths worked in isolation. That is fixed now, and
the shared lazy payload layer also keeps track of already-decoded PPT payloads
so materialized `Event` / `Result` / `Invocation` objects can be converted back
into lazy views without a second unpack attempt. `wamp_ppt_lazy_smoke.toml`
now completes for both Dart and native clients over RawSocket and WebSocket.

The newer larger-payload WAMP runs also exposed two transport-side issues on
the Dart client path. First, the pub/sub matcher only supported one pending
waiter, which meant larger-payload pub/sub sweeps quietly serialized on one
outstanding event even when the scenario asked for more pipelining. The
`WampEventBuffer` now supports multiple concurrent waiters, and WAMP scenarios
accept `in_flight_per_session` to keep several publishes/calls outstanding per
hot session. Second, the RawSocket client was still concatenating inbound bytes
with two copies and could drop the first WAMP frame when the server replied
with the handshake and initial payload in one TCP chunk. The receive path now
merges bytes in one copy, uses `Uint8List.sublistView` for complete frame
slices, and preserves any handshake remainder for normal frame parsing.

On the latest release-built `all_transports_smoke` run in this environment, the
transport comparison landed roughly at:

- RawSocket pub/sub (JSON): `4.99 ms` average latency
- RawSocket RPC (MsgPack): `3.44 ms`
- RawSocket RPC (CBOR): `3.95 ms`
- WebSocket pub/sub (JSON): `3.40 ms`
- WebSocket RPC (MsgPack): `3.30 ms`
- WebSocket RPC (CBOR): `3.28 ms`
- HTTP/1.1: `226.72 Mbps` response throughput
- HTTP/2: `932.07 Mbps`
- HTTP/3: `524.29 Mbps`

That leaves one obvious transport follow-up: on this shared smoke workload,
HTTP/3 still trails HTTP/2 materially even after the recent QUIC tuning and
multiplexing work.

On focused release-built WAMP throughput runs in this environment, the newer
hot-session path now lands roughly at:

- `wamp_serializer_matrix.toml`: RawSocket about `72-94 Mbps`, WebSocket about
  `81-110 Mbps` depending on serializer (`json`, `msgpack`, `cbor`) on the 16
  KiB RPC matrix.
- `wamp_transport_throughput.toml`: RawSocket about `92-131 Mbps`, WebSocket
  about `104-138 Mbps` across the 64 KiB pub/sub + RPC sweep.
- `wamp_client_impl_smoke.toml`: native still wins the small-message RPC and
  pub/sub smoke workloads in this environment after `ct_ffi` started
  exporting direct-bind metadata for common inbound WAMP messages, the
  metadata-only set expanded to carry encoded detail-map bytes for richer
  `CHALLENGE` / `WELCOME` / `ABORT` / `EVENT` / `RESULT` / `INVOCATION` /
  `GOODBYE` / `ERROR` messages, the
  dedicated waitable-FFI receive isolate started batch-draining already-ready
  handles per connection before sending them back to the main isolate, and
  `Session.callSingle(...)` stopped rebuilding materialized `Result` objects
  from already-decoded payload views. Outbound `CALL` / `PUBLISH` now reuse
  matching lazy payload fragments as well, so the same release run shape now
  lands around `2.65 Mbps` native vs `2.09 Mbps` Dart on RawSocket JSON RPC,
  `2.07 Mbps` native vs `0.68 Mbps` Dart on RawSocket CBOR pub/sub,
  `3.56 Mbps` native vs `2.96 Mbps` Dart on WebSocket JSON RPC, and
  `3.34 Mbps` native vs `3.01 Mbps` Dart on WebSocket CBOR pub/sub.
- `wamp_client_impl_throughput.toml`: native is materially ahead on the 64 KiB
  hot-session path, landing around `98.98/128.07 Mbps` on RawSocket RPC/pubsub
  and `116.51/127.91 Mbps` on WebSocket RPC/pubsub versus roughly
  `53.49/48.54 Mbps` and `52.90/47.28 Mbps` respectively for the Dart client on
  this machine.
- `wamp_ppt_lazy_smoke.toml`: the live CBOR PPT lazy path completes for both
  Dart and native clients after the serializer/PPT fixes and currently lands
  around `2.17/2.02 Mbps` on RawSocket RPC/pubsub and `3.74/3.15 Mbps` on
  WebSocket RPC/pubsub for the native client, versus roughly `1.17/1.59 Mbps`
  and `1.80/2.18 Mbps` for the Dart client on this machine.
- `wamp_payload_mode_smoke.toml`: explicit side-by-side no-PPT versus PPT
  comparison for the same RawSocket/WebSocket, RPC/pubsub, Dart/native CBOR
  workloads so payload-wrapping overhead is visible in one run instead of being
  inferred from separate scenarios.
- `wamp_payload_mode_throughput.toml`: the same explicit no-PPT versus PPT
  comparison shape at the 64 KiB throughput profile, so plain-mode regressions
  are easier to distinguish from smoke-run noise.
- `wamp_mixed_serializer_throughput.toml`: explicit mixed-serializer 64 KiB
  throughput comparison against real remote peers. On this machine it currently
  lands around `126.14/302.29 Mbps` Dart/native for RawSocket JSON->MessagePack
  RPC, `75.46/95.33 Mbps` for RawSocket MessagePack->CBOR pub/sub,
  `180.40/426.54 Mbps` for WebSocket JSON->CBOR RPC, and `41.70/116.91 Mbps`
  for WebSocket CBOR->JSON pub/sub.

Those WAMP numbers are still end-to-end Dart-client numbers, not pure native
transport ceilings. The current bench deliberately exercises
`connectanum_client`, not just the wire protocol. The native-client path is now
substantially leaner because common inbound native messages now cross the FFI
boundary as typed metadata instead of forcing Dart to re-decode every full
frame, payload slices stay lazy, and the dedicated receive isolate blocks on
`ct_wait_connection_message(...)` while batch-draining ready handles instead of
spin-polling from the main isolate. The native client now also has a
session-only envelope for hot `Event` / `Result` / `Invocation` traffic plus a
`LazyMessagePayload` object, so backend-style paths can keep borrowed encoded
args/kwargs bytes around until they actually need decode. The router’s own
internal-session bridge now uses the same lazy payload contract, so internal
publish/call forwarding preserves encoded args/kwargs bytes and serializer
hints across isolate hops instead of eagerly materializing `List` / `Map`
payloads. The RPC workloads now use `Session.callSingleLazyPayload()` so
non-progressive calls avoid `Result` allocation on the native fast path and can
still forward encoded payload bytes, backend-oriented callees and subscribers
can now use
`Session.registerLazyPayloadHandler(...)`,
`Session.subscribeLazyPayloadHandler(...)`, and
`Subscribed.onLazyEventPayload(...)` to stay off the object/stream path
entirely, while the older
`Session.registerHandler(...)`, `Session.subscribeHandler(...)`, and
`Subscribed.onEvent(...)` APIs remain for consumers that prefer message
objects. Subscription and registration streams are still allocated lazily only
when callers actually use the stream-oriented API, async callee failures still
flow back as WAMP `ERROR`s after `await`, and the bench no longer wraps inbound
pub/sub events in an extra Dart object before matching them. Full-frame decode
remains as a fallback for custom-detail message shapes that are not safe to
represent in the direct-bind metadata. Mixed-serializer runs now also use real
remote peers instead of synthetic bridge-only tests: the orchestrator can open
the publisher/caller with one serializer and the subscriber/callee with
`peer_serializer`, while the router keeps the same-serializer native fast path
for matching peers and falls back to the Dart bridge when serializers differ.
The wrapped/custom-detail side of that bridge is now covered too: router native
ingress preserves custom option/detail fields, outbound `INVOCATION` details no
longer collapse to `{}`, JSON custom/detail maps normalize binary sentinel
strings recursively, and live mixed WebSocket regressions now cover nested
binary custom values on `EVENT`, `INVOCATION`, `RESULT`, and `ERROR` routing
across JSON, MessagePack, and CBOR.
The same-serializer Dart fallback path in the router is now aligned with that
lazy bridge too: when native forwarding is unavailable, worker-session
`PUBLISH` / `CALL` / `YIELD` / invocation-`ERROR` forwarding reuses the
transferred lazy payload directly instead of touching the source message
decoders just to prepare fallback arguments or kwargs.
The serializer-specific hot path is leaner as well: MessagePack outbound WAMP
messages now assemble with byte builders instead of repeated list
concatenation, and CBOR same-serializer outbound payloads now splice retained
lazy fragments directly instead of decoding and re-encoding them first.
The inbound side now follows the same rule on the hottest payload-bearing
frames: MessagePack and CBOR `INVOCATION`, `RESULT`, `EVENT`, and `ERROR`
messages scan only the top-level WAMP array, eagerly decode the fixed header
and detail fields, and keep args/kwargs as lazy encoded slices until benchmark
or application code actually touches the materialized payload getters.
The same scanner now covers the handled control/ack path too: MessagePack/CBOR
`CHALLENGE`, `WELCOME`, `REGISTERED`, `UNREGISTERED`, `PUBLISHED`,
`SUBSCRIBED`, `UNSUBSCRIBED`, `ABORT`, and `GOODBYE` rebuild from fragment
decoders instead of paying a full-array decode first. That change matters more
for control-heavy smoke workloads than for large steady-state payload sweeps,
so use `wamp_smoke.toml` or the client-implementation smoke scenarios when you
want to see the direct effect.
The native metadata-peek path now reaches both sides of the Dart boundary:
client runtimes and the router runtime can bind common request/control WAMP
messages from `ct_message_peek` metadata + encoded detail bytes without asking
`ct_message_get` for a contiguous frame first. On the router side that now
includes metadata-only `UNSUBSCRIBE`, so the remaining fallbacks are only the
still-unsupported message shapes outside the handled request/control set.
The same lazy path now keeps already-packed `pptScheme == 'wamp'` payload bytes
intact across client outbound sends, invocation yields, and router
internal-session event/result/invocation forwarding, so the benchmark no longer
pays the placeholder E2EE decode/re-pack tax on those wrapped paths. Treat the
numbers as relative
comparisons on the same machine, not product claims.

Treat those as relative loopback signals, not product claims. They are useful
for before/after comparisons on the same machine and now reflect actual
per-session pipelining instead of a single-outstanding-operation workload.

## Prometheus & Grafana (docker-compose)

Use the bundled `native/bench/docker-compose.yml` to spin up Prometheus +
Grafana pointed at the bench router’s OpenMetrics exporter:

```
cd native/bench
docker compose up -d
```

- Prometheus binds `http://localhost:9090` using `prometheus.yml`, scraping
  `http://host.docker.internal:8080/metrics`. On Linux the compose stack adds
  `host.docker.internal` → `host-gateway` automatically. The `/metrics` route
  is served by the router itself via HTTP→WAMP bridging into
  `connectanum.metrics.openmetrics`, so no sidecar HTTP server is needed. The
  compose stack also loads `connectanum_router_alerts.yml` for live router
  state, `connectanum_bench_artifact_alerts.yml` for transformed benchmark
  regressions, and a `node-exporter` textfile collector that scrapes
  `native/bench/artifacts/*.prom`.
- Grafana binds `http://localhost:3000` (default `admin` / `admin`). The compose
  file auto-provisions a Prometheus datasource and ships a “Connectanum Bench
  Summary” dashboard, a “Connectanum Router Alerts” dashboard that charts
  transport alert counters and the current throttle gauges, and a
  “Connectanum Bench Artifacts” dashboard for transformed workload summaries
  and alert deltas. Open Grafana, open the “Benchmarks” folder, and you’re
  ready to watch the metrics live while the bench runs and review the captured
  artifacts afterwards.

When you are done benchmarking:

```
docker compose down
```

Typical workflow:

1. `docker compose up -d`
2. Run your scenario (`cargo run --release --manifest-path native/bench/Cargo.toml -- ...`)
3. Watch Grafana at <http://localhost:3000> while the workloads execute
4. Inspect `native/bench/artifacts/bench_results.prom` or
   `native/bench/artifacts/bench_results.summary.json` if you want the rendered
   artifact bundle directly from disk
5. `docker compose down` after the run (optional)

Because `/bench/metrics` now returns both the structured snapshot and the raw
OpenMetrics payload, every workload in `bench_results.jsonl` carries a verbatim
copy (`open_metrics_before` / `open_metrics_after`). That makes it trivial to
correlate historical runs with what Prometheus scraped during the same workload.
