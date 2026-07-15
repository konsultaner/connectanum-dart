# WAMP Profile Benchmark Contract

This document defines which WAMP benchmark artifacts are release-decision
inputs and which ones are diagnostic support material. The goal is to keep
public benchmark outputs understandable: a user should know whether a result is
a smoke check, a production performance gate, or an exploratory comparison.

## Release Gates

These scenarios are the minimum production-readiness signal for WAMP transport
performance. They should be run locally before changing WAMP transport behavior
and on hosted Linux before declaring a release-ready performance baseline.

| Scenario | Role | Coverage | Gate policy |
| --- | --- | --- | --- |
| `wamp_transport_throughput` | Cleartext throughput gate | RawSocket and WebSocket, RPC and pub/sub, JSON/MsgPack/CBOR, 64 KiB payloads, Dart client | `native/bench/artifact_gate/wamp_transport_throughput.json` |
| `wamp_secure_throughput` | TLS throughput gate | Same transport/profile/serializer shape as `wamp_transport_throughput`, routed through the secure WAMP listener and `bench.secure` ticket auth | `native/bench/artifact_gate/wamp_secure_throughput.json` |
| `wamp_publish_fanout_throughput` | Pub/sub fan-out throughput gate | Native RawSocket and WebSocket pub/sub with eight subscribers per publisher session across JSON/MsgPack/CBOR at 64 KiB payloads | `native/bench/artifact_gate/wamp_publish_fanout_throughput.json` |
| `wamp_e2ee_throughput` | Payload E2EE throughput gate | RawSocket/WebSocket RPC and pub/sub with 64 KiB CBOR payloads, Dart/native clients, and XSalsa20-Poly1305/AES-256-GCM | `native/bench/artifact_gate/wamp_e2ee_throughput.json` |
| `wamp_final_release_features` | Final Advanced-feature gate | Progressive invocations, 50 ms timeout lifecycles, and full 15-procedure statistics Meta API sweeps over RawSocket/WebSocket and Dart/native clients | `native/bench/artifact_gate/wamp_final_release_features.json` |
| `wamp_smoke` | Cleartext smoke gate | Fast RawSocket/WebSocket RPC and pub/sub coverage across JSON/MsgPack/CBOR | Default zero transport-counter gate |
| `wamp_secure_smoke` | TLS smoke gate | Fast secure RawSocket/WebSocket RPC and pub/sub coverage | Default zero transport-counter gate |
| `wamp_control_smoke` | Control-plane smoke gate | Publish acknowledgements, subscribe cycles, register cycles, and cancel/interrupt cycles across RawSocket/WebSocket and all supported serializers | Default zero transport-counter gate |
| `wamp_e2ee_smoke` | Payload E2EE correctness smoke | Both release ciphers across transports, messaging patterns, client implementations, and mixed outer serializers | Default zero transport-counter gate |

The throughput policies are deliberately conservative release floors, not
performance targets. They are based on the first local Darwin arm64 baseline
captured on 2026-04-23 plus the already recorded hosted Linux secure-WAMP
baseline. Raising them should happen only after we have repeatable hosted
evidence.

## Diagnostic Scenarios

These scenarios are useful for explaining regressions after a release gate
fails, but they should not be treated as standalone release evidence until they
have explicit policies and hosted baselines.

Run the full diagnostic set with `bin/wamp-profile-diagnostics`. The runner
writes one artifact directory per scenario and applies the default
transport-counter gate only. Diagnostic throughput numbers are trend data, not
release blockers, until repeated local and hosted baselines justify explicit
policies.

| Scenario | Use |
| --- | --- |
| `wamp_client_impl_throughput` | Compares Dart and native client hot-session throughput on the same CBOR workloads. Useful for deciding whether a regression is in the router path or native client path. |
| `wamp_payload_mode_throughput` | Compares plain versus PPT payload handling for Dart and native clients. Useful when PPT or lazy-payload changes move CPU or allocation cost. |
| `wamp_mixed_serializer_throughput` | Exercises cross-serializer peer paths, especially conversion overhead between client and callee/subscriber serializers. |
| `wamp_websocket_fragmentation_throughput` | Compares contiguous WebSocket payloads with explicit continuation-frame sends. Useful for WebSocket framing regressions. |
| `transport_mbit_matrix_throughput` | Cross-transport Mbps table that includes representative WAMP auth, ACL, payload-size, and WebSocket-fragmentation rows alongside HTTP. Useful as a broad comparison artifact, not the focused WAMP release gate. |
| `wamp_serializer_matrix` | Older serializer-focused RPC sweep. Prefer `wamp_transport_throughput` for release gating because it includes pub/sub and the current 64 KiB workload shape. |

## Smoke-Only Scenarios

Smoke scenarios should stay cheap and strict. They validate that the benchmark
harness and supported WAMP paths still execute cleanly, while performance
budgets live in the throughput policies.

| Scenario | Use |
| --- | --- |
| `all_transports_smoke` | Quick mixed HTTP/WAMP sanity check. |
| `transport_mbit_matrix_smoke` | Small version of the cross-transport Mbps matrix. |
| `wamp_client_impl_smoke` | Fast Dart/native client comparison. |
| `wamp_payload_mode_smoke` | Fast plain/PPT comparison. |
| `wamp_ppt_lazy_smoke` | Focused lazy PPT handling check. |
| `wamp_control_custom_smoke` | Control-plane smoke with custom option/detail fields for richer native direct-bind coverage. |

## Current Local Baseline

The first local Darwin arm64 baseline was captured on 2026-04-23 with
`router_workers=1` and `native_runtime_threads=1`.

| Scenario | Lowest throughput floor observed | Highest p95 observed | Transport counters |
| --- | ---: | ---: | --- |
| `wamp_transport_throughput` | 48.79 Mbps (`websocket_pubsub_json_64k`) | 264.493 ms (`rawsocket_pubsub_json_64k`) | Default gate passed: no backpressure, transport alerts, or active throttles |
| `wamp_secure_throughput` | 32.48 Mbps (`websocket_secure_pubsub_json_64k`) | 450.015 ms (`rawsocket_secure_pubsub_json_64k`) | Default gate passed: no backpressure, transport alerts, or active throttles |

The expanded release-gate entrypoint was revalidated locally on Darwin arm64 on
2026-04-23 with the same worker settings. The first five-gate run passed
before fan-out promotion, and the next slice promotes fan-out into that same
canonical release path with conservative policy floors based on the local and
first hosted Linux baselines.

| Scenario | Workloads | Lowest throughput observed | Highest p95 observed | Gate policy |
| --- | ---: | ---: | ---: | --- |
| `wamp_smoke` | 12 | 0.76 Mbps (`rawsocket_pubsub_json`) | 11.151 ms (`rawsocket_pubsub_json`) | Default transport-counter gate |
| `wamp_secure_smoke` | 4 | 0.22 Mbps (`rawsocket_secure_pubsub_cbor`) | 9.268 ms (`websocket_secure_pubsub_cbor`) | Default transport-counter gate |
| `wamp_control_smoke` | 24 | Not meaningful for zero-payload control workloads | 345.534 ms (`rawsocket_cancel_cycle_json`) | Default transport-counter gate |
| `wamp_transport_throughput` | 12 | 57.65 Mbps (`websocket_pubsub_json_64k`) | 241.860 ms (`websocket_pubsub_json_64k`) | `native/bench/artifact_gate/wamp_transport_throughput.json` |
| `wamp_secure_throughput` | 12 | 35.86 Mbps (`rawsocket_secure_pubsub_json_64k`) | 389.237 ms (`rawsocket_secure_pubsub_json_64k`) | `native/bench/artifact_gate/wamp_secure_throughput.json` |
| `wamp_publish_fanout_throughput` | 6 | 24.49 Mbps (`websocket_pubsub_json_64k_fanout8`) | 508.916 ms (`rawsocket_pubsub_cbor_64k_fanout8`) | `native/bench/artifact_gate/wamp_publish_fanout_throughput.json` |

The final-feature gates were added and validated locally on Darwin arm64 on
2026-07-15 with the same one-worker, one-native-thread topology:

| Scenario | Workloads | Throughput / latency evidence | Gate policy |
| --- | ---: | --- | --- |
| `wamp_e2ee_throughput` | 16 | 1.77-13.90 Mbps response throughput; 262.73-2824.47 ms p95 | `native/bench/artifact_gate/wamp_e2ee_throughput.json` |
| `wamp_final_release_features` | 12 | Progressive: 0.45-1.79 Mbps and 8.12-25.41 ms p95; timeout: 55.38-59.49 ms p95; full Meta sweep: 11.17-33.22 ms p95 | `native/bench/artifact_gate/wamp_final_release_features.json` |

Both gates passed with zero transport, backpressure, protocol, or internal
error counters. Hosted Linux evidence remains required after push.

The diagnostic runner was also validated locally on Darwin arm64 on 2026-04-23
with `router_workers=1` and `native_runtime_threads=1`. All diagnostic artifact
bundles passed the default transport-counter gate with zero findings. These
numbers are baselines for comparison, not performance floors.

| Scenario | Workloads | Lowest throughput observed | Highest p95 observed |
| --- | ---: | ---: | ---: |
| `wamp_client_impl_throughput` | 8 | 9.74 Mbps (`websocket_pubsub_cbor_64k_native`) | 255.423 ms (`rawsocket_pubsub_cbor_64k_dart`) |
| `wamp_payload_mode_throughput` | 16 | 7.94 Mbps (`rawsocket_pubsub_cbor_ppt_native`) | 816.177 ms (`rawsocket_pubsub_cbor_ppt_native`) |
| `wamp_mixed_serializer_throughput` | 8 | 11.39 Mbps (`rawsocket_pubsub_msgpack_to_cbor_native`) | 371.637 ms (`rawsocket_pubsub_msgpack_to_cbor_native`) |
| `wamp_websocket_fragmentation_throughput` | 8 | 11.51 Mbps (`websocket_pubsub_cbor_64k_native_fragmented_4k`) | 221.649 ms (`websocket_pubsub_cbor_64k_native_fragmented_4k`) |

The first hosted Linux diagnostic run on 2026-04-23 also passed with zero
transport-counter findings. Its fan-out results were materially stronger than
the local Darwin arm64 baseline, which is why `wamp_publish_fanout_throughput`
is now conservative enough to move into the canonical release-gate set rather
than stay diagnostic-only. The lowest hosted fan-out throughput was
`46.19 Mbps` (`rawsocket_pubsub_cbor_64k_fanout8`) and the highest hosted p95
was `228.126 ms` on the same workload.

## Running The Gates

Run the canonical WAMP profile release gates together:

```bash
bin/wamp-profile-validate \
  --out-dir out/wamp-profile-validation \
  --router-worker-counts 1 \
  --native-runtime-thread-counts 1
```

The same command is used by the hosted Linux `WAMP Profile Benchmarks`
workflow. Its artifact bundle is `wamp-profile-benchmark-artifacts`, with one
subdirectory per release gate and a top-level `host-info.txt` that records the
runner/toolchain inputs. The smoke-gate subdirectories use the default
transport-counter gate; the throughput-gate subdirectories also include
scenario-specific performance policy reports.

Use the direct bench command only when iterating on a single scenario or
capturing a focused local baseline.

Run a canonical scenario and write transformed artifacts:

```bash
CONNECTANUM_NATIVE_LIB=native/transport/target/release/libct_ffi.dylib \
  cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- \
    --scenario native/bench/scenarios/wamp_transport_throughput.toml \
    --results out/wamp-transport/bench_results.jsonl \
    --artifact-dir out/wamp-transport \
    --router-worker-counts 1 \
    --native-runtime-thread-counts 1
```

Validate the artifact bundle against the WAMP policy:

```bash
bin/check-bench-artifacts \
  --summary out/wamp-transport/bench_results.summary.json \
  --policy native/bench/artifact_gate/wamp_transport_throughput.json
```

For secure WAMP, switch the scenario and policy to
`wamp_secure_throughput.toml` and `wamp_secure_throughput.json`.

Run the diagnostic WAMP scenarios together when a release gate needs more
context:

```bash
bin/wamp-profile-diagnostics \
  --out-dir out/wamp-profile-diagnostics \
  --router-worker-counts 1 \
  --native-runtime-thread-counts 1
```

The hosted Linux `WAMP Profile Diagnostics` workflow uses the same command and
uploads `wamp-profile-diagnostic-artifacts`.
