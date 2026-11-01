# MQTT broker interoperability

Status: active; direct QoS 0 merged, authorized gateway implemented, translation
numeric baseline and final CI acceptance in progress.

## Goal and boundary

Accept standard MQTT clients, provide a Connectanum MQTT client, and route
explicitly authorized publications between MQTT and WAMP. Release requires
independent interoperability, 100% scoped executable-line coverage and live
numeric performance/memory gates. The [MQTT contract](../mqtt.md) defines the
supported profile; WAMP `ppt_scheme: mqtt` remains opaque.

## Gateway work (#116, #117, #131)

- [x] Opt-in realm-bound gateway with explicit MQTT principal/role and service role; client IDs never confer identity.
- [x] Authorize incoming publications before any delivery and concrete outgoing topics for wildcard recipients. Retain the synchronous direct-MQTT path without a gateway.
- [x] Explicit `connectanum.mqtt.v1.publish` RPC accepts topic/application bytes and derives the caller from trusted invocation state; reject unsupported arguments/metadata.
- [x] Bound per-peer/aggregate queues, cancel on disconnect/disposal, preserve ordering, expose counters and forward once with origin metadata.
- [x] Live Paho/Connectanum/WAMP regressions across both versions and TCP/TLS/WS/WSS: ACL/realm isolation, binary payloads, fan-out, spoofing, opaque PPT, loops, failures, slow peers and lifecycle.
- [x] Exact scoped coverage for gateway/shared Dart, MQTT Dart, changed native production lines and Python tooling.
- [x] Separate-process AOT benchmark: both directions and matched MQTT/WAMP/acknowledged-WAMP/Mosquitto controls; four WAMP serializers, 128 B/1 KiB/64 KiB, fan-out and credit windows.
- [x] Record rate, latency percentiles, active CPU, per-process warm/high-water/drained RSS, lifecycle growth, queue drain and overload recovery. Release allocation counters remain unavailable and are explicitly null.
- [ ] Accept a complete immutable Linux baseline, with unchanged rate/p99/CPU variation caps 0.20/0.75/0.35.
- [ ] Freeze numeric budgets, publish compact README tables/fixtures, externally archive raw evidence and rejected runs.
- [ ] Enable required smoke and four numeric shards as Full Verify prerequisites, alongside every existing regression gate.
- [ ] Finish local verification, strict publishing and exact-head hosted CI; open a ready PR. A new merge needs user authorization.

## Current verification and remaining measurement

Full `bin/verify` passes on `5b1e4a43`, including Rust, Dart VM and Chrome/Wasm.
Independent MQTT checks pass 104 tests and benchmark/worker checks pass 56.
Coverage is 744/744 gateway/shared Dart, 759/759 MQTT, 270/270 gateway component,
882/882 native added production lines and 910/910 Python lines (zero exclusions).
Native source SHA-256 is `1254e2279369f2d3e5f5b78236d5beeda58295e201f9ba2b2f3edbd52c93fc01`;
the retained compressed Cargo/Dart FFI union is source-hash checked by a test.

Measured failures produced fail-first fixes for the independent Python payload
oracle, MQTT peer-FIN socket retention, Paho TCP_NODELAY and native MQTT WS
TCP_NODELAY. Native WS acceptance passes all 12 sustained comparisons in
[41322497967](https://github.com/konsultaner/connectanum-dart/actions/runs/41322497967)
with every existing budget unchanged. All four artifacts from each superseded
complete/partial gateway run are preserved outside Git.

The complete [5b1e4a43 baseline](https://github.com/konsultaner/connectanum-dart/actions/runs/41323493587)
contains 960 normal samples and 12 overload/recovery cycles. Delivery, resource
cleanup and slow-client isolation pass, but the fastest direct MQTT control
fails the unchanged p99 variation cap. Its short 200-message warm-up is replaced
by at least 200 messages over one second. Actual counts/durations and cumulative
counter accounting are covered; all four real Paho links pass both directions.
No measured sample is discarded and no numeric cap is relaxed. A complete
hosted rerun remains required before publishing a budget or README fixture.

## Broader milestone

| Step | State |
| --- | --- |
| Codec/topic/coverage foundation, #110–#111 | Implemented; advertised full-protocol matrix remains a release prerequisite |
| Direct live QoS 0, #112–#115, #125–#127 | Merged in PR #128; 20 hosted profiles and matched Intel checks pass unchanged gates |
| Authorized gateway, #116–#117 | Implemented; current PR acceptance pending |
| Translation performance/memory, #131 | Harness/coverage implemented; numeric baseline and required CI pending |
| Complete protocol, #118–#123 | QoS 1/2, retained/wills, persistence, credential authentication and full properties remain open |
| Release, #124 | Close after all advertised protocol, recovery, coverage, performance and operations acceptance passes |

The [README tables](../../packages/connectanum_bench/README.md) and
[benchmark evidence](../benchmarks/README.md) retain prior accepted results,
misses and the verified PR #128 history archive. Keep raw history out of Git.
Auxiliary kTLS ULP and WAMP diagnostic throughput misses remain visible;
they do not validate or block unrelated gateway measurements. Their budgets
stay intact. PR #128 merged; do not close the broader milestone.

## Verification commands

Use `bin/test-fast` before substantial changes, focused unit/live/gate/README
checks during work, then `bin/verify` and
`bin/dart-package-publish-dry-run --strict-release-ready`. Live CI gates measure
the implementation; offline fixtures only verify published tables.
