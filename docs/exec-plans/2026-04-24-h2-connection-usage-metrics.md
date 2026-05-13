# HTTP/2 Connection Usage Metrics

Status: completed

## Context

- Commit `257f9aa` is green on the hosted push chain:
  - `CI` `24870440483`
  - `kTLS Validation` `24870440482`
  - `WAMP Profile Benchmarks` `24870440494`
- Manual hosted run `24870980724` (`kTLS HTTP/2 Benchmarks`) exercised
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` with
  `skip_artifact_gate=true`.
- That rerun showed:
  - every focused row regressed under required-kTLS
  - `h2_multiplexed_streams_s1` already loses about `50%` with zero transport
    counters in both passes
  - the worst throughput row is `h2_multiplexed_streams_s4`, `threads=4`
    (`-64.97%`)
  - required-kTLS still opens kernel software TX/RX sessions cleanly
    (`TlsTxSw/TlsRxSw 66/66`) with no decrypt/rekey anomalies
- The next plausible hypothesis is connection reuse/open behavior on the HTTP/2
- client path, but the current artifact summaries do not expose that.

## Goals

1. Add the smallest useful per-workload HTTP connection-usage metrics to the
   bench reports and artifact summaries.
2. Surface those metrics in the kTLS comparison output so focused reruns can
   confirm or rule out connection reuse/open churn before runtime tuning.
3. Preserve backward compatibility for existing artifact readers where
   practical, or document the schema change clearly if not.

## Planned Changes

1. Inspect the HTTP bench worker/client path and decide the minimal metric set
   that captures reuse/open behavior accurately.
2. Extend `WorkloadReport` / `WorkloadArtifactSummary` and the emitted summary
   outputs with those metrics.
3. Update `tool/ktls_http2_compare.py` to render the new connection-usage view
   alongside the existing throughput, latency, resource-usage, TLS-stat, and
   transport-counter summaries.
4. Add focused regression coverage and refresh `docs/project_state.md` plus
   `docs/ktls_research.md` once the new metrics are landed.

## Verification

- `bin/test-fast`
- focused Rust tests for the bench report/artifact changes
- focused Python tests for the comparison renderer
- `bin/verify`

## Outcome

- Added optional per-workload `http_connection_usage` capture to the native
  bench JSONL report path.
- Extended the artifact summary bundle with derived
  `samples_per_connection_avg` so comparison consumers do not need to
  reconstruct it.
- Updated the HTTP workload runner summaries and Prometheus export to expose
  connection-open counts alongside the existing throughput/latency and
  transport counters.
- Updated `tool/ktls_http2_compare.py` to render worst-row connection views and
  a dedicated `HTTP Connection Usage` section for comparable workloads.
- Added focused Rust and Python regression coverage for the new schema and
  comparison output.
