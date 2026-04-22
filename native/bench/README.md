# Native Bench Orchestrator

`native/bench` contains the Rust-side benchmark orchestrator used to drive the
Connectanum router under repeatable HTTP and WAMP workloads.

It works together with:

- `packages/connectanum_bench/tool/bench_main.dart`
  The Dart control-plane runner that boots the router and exposes `/bench/*`
  endpoints.
- `native/bench/scenarios/*.toml`
  Scenario files that define concrete workloads.

Secure WAMP scenarios use the same workload format with one extra selector:
set `secure_transport = true` and point the workload at `bench.secure` ticket
auth if it should run through the TLS WAMP listener in
`native/bench/bench_router.json`.

`native/bench/scenarios/wamp_secure_throughput.toml` is the throughput-grade
secure WAMP baseline. It mirrors the existing 64 KiB cleartext transport sweep
but routes through the TLS WAMP listener and `bench.secure` ticket auth.

## What It Measures

- HTTP/1.1, HTTP/2, and HTTP/3 throughput and latency
- RawSocket and WebSocket WAMP workloads
- auth and authz paths
- router metrics deltas and OpenMetrics snapshots
- scaling sweeps across router workers and native runtime threads

## Typical Usage

```bash
cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- \
  --scenario native/bench/scenarios/h2_smoke.toml
```

The direct CLI now defaults its control plane to `https://127.0.0.1:8080/bench`
so local runs target the shipped IPv4 TLS listener consistently on dual-stack
hosts. Override `--control-base` only if you intentionally move the bench
control plane elsewhere.

For the kTLS comparison runner, use the repo helper:

```bash
bin/ktls-http2-bench
```

## Outputs

Bench runs emit:

- `bench_results.jsonl`
- `native/bench/artifacts/bench_results.prom`
- `native/bench/artifacts/bench_results.summary.json`
- `native/bench/artifacts/bench_results.gate.json`
- `native/bench/artifacts/bench_results.gate.md`
- optional before/after OpenMetrics payloads

Validate a transformed summary directly with:

```bash
bin/check-bench-artifacts \
  --summary native/bench/artifacts/bench_results.summary.json
```

## Main Components

- `native/bench/src/bin/http_stream.rs`
  Rust orchestrator binary
- `native/bench/bench_router.json`
  Default router config for bench runs
- `native/bench/scenarios/`
  Workload catalog
- `packages/connectanum_bench/tool/bench_main.dart`
  Dart-side runner and control API

## Control API

The Dart bench runner exposes:

- `GET /bench/healthz`
- `GET /bench/metrics`
- `POST /bench/stop`
- `POST /bench/auth`
- `POST /bench/secure`
- `POST /bench/secure-jwt`
- `POST /bench/stream`

These paths are how the orchestrator coordinates startup, metrics collection,
shutdown, and auth or streaming workloads.

## Related Docs

- repo overview: [../../README.md](../../README.md)
- deployment guide: [../../docs/deployment.md](../../docs/deployment.md)
- Dart bench package: [../../packages/connectanum_bench/README.md](../../packages/connectanum_bench/README.md)
