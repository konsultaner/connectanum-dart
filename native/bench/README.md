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

The focused WAMP release-decision contract is documented in
`docs/wamp_profile_benchmarks.md`. In short, `wamp_transport_throughput` and
`wamp_secure_throughput` are the canonical throughput gates; the broader
WAMP/client/PPT/fan-out/fragmentation scenarios are diagnostic until they have
their own hosted baselines and artifact policies.

`native/bench/scenarios/http_auth_smoke.toml` is the dedicated HTTP auth-bridge
baseline. It exercises `ticket`, `wampcra`, and `scram` login, refresh, and
protected-route flows across HTTP/1.1, HTTP/2, and HTTP/3.

`native/bench/scenarios/http_bearer_provider_smoke.toml` is the companion
HTTP bearer-provider baseline. It exercises both local JWT validation and local
OAuth introspection-backed protected routes across HTTP/1.1, HTTP/2, and
HTTP/3.

`native/bench/scenarios/h3_multiplex_scaling.toml` is the focused HTTP/3
multiplex ceiling map. It holds the sustained-transfer workload shape steady
while sweeping `streams_per_connection = 1, 2, 4, 8, 16` on reused QUIC
connections. The latest local worker/thread direction sweep on that scenario
showed the next H3 follow-up should target transport/backpressure tuning:
extra router workers only helped the lowest-multiplex point, while the deeper
`s8/s16` cases still correlated with heavy backpressure counters.

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

That helper writes per-pass benchmark artifacts under `baseline/` and `ktls/`,
including `resource-usage.txt` sidecars from GNU `time -v`, and a top-level
`comparison.json` / `comparison.md` pair that now summarizes throughput,
latency, CPU-total, wall-time, and max-RSS deltas between the two passes.
Those comparison artifacts also roll up the deltas by workload family and
native runtime thread count, then surface compact transport-counter deltas for
each comparable row. That means a hosted rerun can now show whether a hotspot
already correlates with backpressure/alert telemetry or whether the slowdown is
still invisible to the current transport counters. The helper also captures
`/proc/net/tls_stat` before and after each pass when that
Linux proc file is readable, writes `tls-stat-before.txt` /
`tls-stat-after.txt` sidecars, and summarizes the resulting kernel TLS
session-open plus decrypt/rekey deltas in `comparison.json` / `comparison.md`.
That gives the next hosted rerun a direct answer to "did required-kTLS
actually open kernel TLS sessions cleanly?" before moving on to heavier
diagnostics. The hosted `kTLS HTTP/2 Benchmarks` workflow now mirrors that summary into the GitHub
Actions job summary as well, so the first read can happen in the run UI before
downloading `ktls-http2-bench-artifacts`. The helper also validates each pass
against the scoped `native/bench/artifact_gate/h2_ktls_benchmark.json` policy
rather than the generic zero-counter gate, because the comparison scenario
intentionally exercises multiplexing hard enough to produce bounded
backpressure counters.

Focused diagnostic reruns can now override that behavior. Pass
`--artifact-policy <path>` to use a scenario-specific gate, or
`--skip-artifact-gate` when the goal is to inspect a targeted hotspot rather
than uphold the canonical release-decision contract. The manual workflow
exposes the same controls through `artifact_policy` and
`skip_artifact_gate` inputs.

When a hosted rerun needs decision-quality evidence rather than a single
baseline-vs-kTLS sample, pass `--repeat-count <n>`. The helper then writes
per-repeat artifacts under `repeats/repeat-XX/` and turns the top-level
`comparison.json` / `comparison.md` pair into an aggregate repeat-stability
report. It also writes `repeat-plan.txt`, which records the exact pass order
used for each repeat plus the configured cooldown. The manual workflow exposes
the same controls through `repeat_count`, `repeat_order`, and
`cooldown_seconds` inputs. For manual reruns, the workflow now defaults to
`repeat_order=alternating` and `cooldown_seconds=15` so repeated hosted runs do
not always benchmark `baseline -> kTLS` back-to-back on a warming runner.

For the current HTTP/2 multiplex hotspot, the quick diagnostic scenario is:

```bash
bin/ktls-http2-bench \
  --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml \
  --skip-artifact-gate
```

When the goal is hosted repeat stability rather than a fast spot check, use
the dedicated stability scenario with a larger sample set:

```bash
bin/ktls-http2-bench \
  --scenario native/bench/scenarios/h2_ktls_multiplex_stability.toml \
  --repeat-count 3 \
  --repeat-order alternating \
  --cooldown-seconds 15 \
  --skip-artifact-gate
```

For the canonical WAMP release gates, use the WAMP profile helper. It builds
the release FFI library, runs the cleartext and secure WAMP throughput
scenarios, and validates both artifact bundles against their checked-in
policies:

```bash
bin/wamp-profile-validate
```

Hosted Linux runs use the same command through the `WAMP Profile Benchmarks`
GitHub Actions workflow.

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

The artifact gate uses zero transport-counter thresholds and no performance
budgets unless a policy is provided. Scoped policies can document expected
counters for a specific scenario while leaving all other transport regression
signals strict, and can also add explicit performance budgets:

```json
{
  "thresholds": [
    {
      "kind": "backpressure_events",
      "threshold": 80,
      "scenario": "h3_multiplex_scaling",
      "workload": "h3_multiplexed_streams_s4"
    }
  ],
  "metrics": [
    {
      "kind": "throughput_mbps_min",
      "threshold": 600.0,
      "scenario": "h3_multiplex_scaling"
    },
    {
      "kind": "latency_p95_ms_max",
      "threshold": 350.0,
      "scenario": "h3_multiplex_scaling"
    }
  ]
}
```

Metric policy kinds are `throughput_mbps_min` and `latency_p95_ms_max`.

```bash
bin/check-bench-artifacts \
  --summary out/h3-http3-round-robin/bench_results.summary.json \
  --policy native/bench/artifact_gate/h3_multiplex_scaling.json
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
- `POST /bench/secure-oauth`
- `POST /bench/stream`

These paths are how the orchestrator coordinates startup, metrics collection,
shutdown, and auth or streaming workloads.

## Related Docs

- repo overview: [../../README.md](../../README.md)
- deployment guide: [../../docs/deployment.md](../../docs/deployment.md)
- Dart bench package: [../../packages/connectanum_bench/README.md](../../packages/connectanum_bench/README.md)
