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
│    hyper/h2            │          │  • iterations, warmup       │
│  • drives HTTP/3 via   │          └─────────────────────────────┘
│    quinn + h3          │
│  • collects metrics    │─────► jsonl / stdout summaries
└────────────────────────┘
```

### Components

| Component                         | Description                                                                                   |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `bench_main.dart` (new target)   | Applies the bench router config, registers HTTP handlers, spins up internal bench sessions **and external clients** (RawSocket, WebSocket, `connectanum_client`), exposes a tiny control API (stdin + `/bench/*` HTTP routes) to signal readiness/shutdown, and serves metrics snapshots on demand. |
| Rust orchestrator binary         | Lives under `native/bench/src/bin/http_stream.rs`. Parses scenario files / CLI flags, spawns the Dart runner, waits for readiness, and then executes a list of workloads. |
| Scenario configuration           | Simple TOML/JSON describing iterations, upload/download bytes, chunk sizes, pauses, and parallel streams. Stored under `native/bench/scenarios/`. |
| Load generators                  | In-process clients: hyper/h2 for HTTP/2, quinn+h3 for HTTP/3, a plain `reqwest` fallback for HTTP/1.1 sanity checks, **and Dart-side WAMP clients (RawSocket/WebSocket) so the connectanum client stack is exercised**. Each generator reports status, latency, bytes, and optionally stream IDs. |
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
   - Implements HTTP/2 (hyper) and HTTP/3 (quinn) generators, plus optional HTTP/1.1 sanity checks.
   - Calls `/bench/metrics` before/after each workload to capture deltas, and serializes the embedded OpenMetrics payload next to the raw snapshot.
   - Writes stdout summaries and structured JSONL for downstream tooling.
3. **Scenario samples**
   - `h2_small.toml` (many short streams).
   - `h2_large.toml` (multi-MB uploads/downloads).
   - `h3_idle.toml` (deliberate pauses to trigger idle/body timeouts).
   - `wamp_rawsocket.toml` / `wamp_websocket.toml` (connectanum_client over RawSocket/WebSocket alongside HTTP traffic; future zero-copy client upgrades plug in here).
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

This directory will eventually house the orchestrator crate (`native/bench/Cargo.toml`), scenarios, and supporting scripts. For now, the README documents the agreed architecture so implementation can start iteratively.

## Bench Router Configuration & Control API

The Dart runner ships with a default `bench_router.json` that exposes a
multi-protocol listener on `127.0.0.1:8080` with HTTP/2 and a dedicated HTTP/3 port
(`8443`). The listener enables RawSocket + HTTP/2/HTTP/3 and maps the `/bench/*`
paths to internal RPC handlers:

| Path              | Method | Procedure            | Description                                |
|-------------------|--------|----------------------|--------------------------------------------|
| `/bench/healthz`  | GET    | `bench.http.healthz` | Liveness probe that returns `{"status":"ok"}`. |
| `/bench/metrics`  | GET    | `bench.http.metrics` | Snapshot of `binding.collectMetrics()` so orchestrators can diff counters between runs. |
| `/bench/stop`     | POST   | `bench.http.stop`    | Acknowledges the request and triggers the shutdown flow (mirrors the STOP stdin command). |
| `/bench/stream`   | POST   | `bench.http.stream`  | Streams the request payload (or a default token) back to the caller to validate HTTP routing/streaming. |

All handlers continue to be callable over WAMP, which keeps the YAML scenario
runner and existing integration tests working without changes. The Rust
orchestrator now pings `/bench/healthz`, fetches `/bench/metrics`, and issues a
POST to `/bench/stop` before waiting for the Dart process to exit, ensuring the
HTTP routes are live before real workloads are added.

### Scenario Format

Workloads are described in TOML under `native/bench/scenarios/`. Each scenario
declares a name plus a list of workloads. Every workload describes the
protocol, HTTP method/path, request/response byte counts, chunk sizes, warm-up
delays, and concurrency. Example (`h2_smoke.toml`):

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
request_bytes = 262144
response_bytes = 262144
request_chunk_bytes = 65536
response_chunk_bytes = 65536
```

The bench HTTP handler honors the `x-bench-response-bytes` and
`x-bench-response-chunk-bytes` headers so the orchestrator can request arbitrary
response sizes/chunking regardless of the inbound payload.

### Scenario Catalog

- `h2_smoke.toml` – short warm-up + load + HTTP/3 probe to validate plumbing after a
  build. Use this for quick sanity checks.
- `full_stack.toml` – extended matrix covering bulk uploads/downloads, latency spikes,
  idle soak phases, and both HTTP/2 and HTTP/3 transfers with higher concurrency.
- `wamp_smoke.toml` – lightweight PUB/SUB and RPC workloads powered by RawSocket clients
  to exercise the router’s WAMP routing path.
- `real_world_smoke.toml` – higher-connection smoke that mixes WAMP pubsub/RPC with HTTP/2
  and HTTP/3 fanout; roughly 2k WAMP RawSocket connections (1000 pub/sub workers) plus
  high-concurrency HTTP fanout/asset echoes to probe backpressure.

### TLS Setup & Running the Orchestrator

`bench_main.dart` expects a TLS/SNI bundle whenever HTTP/2 or HTTP/3 is enabled. We ship a
local self-signed pair for `localhost` under `native/bench/bench_tls.crt` and
`native/bench/bench_tls.key`. The default `bench_router.json` references those files via the
`certificate_chain_file`/`private_key_file` knobs, so no extra setup is required unless you want to
use your own certs.

1. Make sure the native runtime is rebuilt so the latest TLS/ALPN changes are in the shared library:
   ```sh
   cargo build --manifest-path native/transport/Cargo.toml -p ct_ffi --release
   ```
   This produces `native/transport/target/release/libct_ffi.so` (or `.dylib`/`.dll` on other
   platforms). Point the bench runner at that file via `--native-lib` or set
   `CONNECTANUM_NATIVE_LIB`.

2. Run the orchestrator:

Run whichever scenario you need by pointing `--scenario` at the desired file. For
example, the full-stack matrix:

```
cargo run --manifest-path native/bench/Cargo.toml -- \
  --router-config native/bench/bench_router.json \
  --scenario native/bench/scenarios/full_stack.toml \
  --control-base http://127.0.0.1:8080/bench \
  --h3-port 8443 \
  --native-lib native/transport/target/release/libct_ffi.so
```

The CLI will:

1. Spawn the Dart bench runner (`bench_main.dart`) with the supplied router
   config/native library.
2. Wait for the `READY` banner, poll `/bench/healthz`, and fetch `/bench/metrics`
   (which now returns both the JSON snapshot and the OpenMetrics text).
3. Execute each workload from the scenario file. HTTP/2 runs use `hyper` with
   prior knowledge while HTTP/3 workloads establish QUIC connections via
   `quinn` + `h3` (prior knowledge, ALPN `h3`), allowing the same benchmark to
   stress both transports.
4. Capture metrics snapshots (plus the accompanying OpenMetrics payload) before
   and after every workload, append a row to `bench_results.jsonl`, and print a
   human-readable summary with throughput, latency, and router counter deltas.
   The orchestrator also rewrites the cumulative JSONL into
   `bench_results.prom` and `bench_results.summary.json` after each workload so
   Prometheus/Grafana always see the latest run without a manual conversion
   step.
5. Issue `/bench/stop` (falling back to the stdin `STOP` command if needed) and
   wait for the Dart process to exit cleanly.

The JSONL output records per-workload metadata (router metrics snapshots,
OpenMetrics text, latency samples, total bytes) so downstream tooling
(Prometheus exporters, dashboards, regression detectors) can diff runs without
scraping stdout.

If you already have a JSONL file from CI or an earlier run, regenerate the
Prometheus/textfile bundle without rerunning the workloads:

```sh
cargo run --manifest-path native/bench/Cargo.toml --bin transform_results -- \
  --input native/bench/artifacts/bench_results.jsonl
```

To run the WAMP-only scenario:

```
cargo run --manifest-path native/bench/Cargo.toml -- \
  --router-config native/bench/bench_router.json \
  --scenario native/bench/scenarios/wamp_smoke.toml \
  --control-base http://127.0.0.1:8080/bench \
  --native-lib native/transport/target/release/libct_ffi.so
```

The `wamp_pubsub` workloads interpret `path` as the topic URI, while `wamp_rpc`
workloads use it as the procedure URI. `request_bytes` sets the payload size
sent in each publish/call (which is echoed back for RPC).

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
2. Run your scenario (`cargo run --manifest-path native/bench/Cargo.toml -- ...`)
3. Watch Grafana at <http://localhost:3000> while the workloads execute
4. Inspect `native/bench/artifacts/bench_results.prom` or
   `native/bench/artifacts/bench_results.summary.json` if you want the rendered
   artifact bundle directly from disk
5. `docker compose down` after the run (optional)

Because `/bench/metrics` now returns both the structured snapshot and the raw
OpenMetrics payload, every workload in `bench_results.jsonl` carries a verbatim
copy (`open_metrics_before` / `open_metrics_after`). That makes it trivial to
correlate historical runs with what Prometheus scraped during the same workload.
