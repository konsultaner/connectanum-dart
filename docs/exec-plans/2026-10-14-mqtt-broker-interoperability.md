# MQTT broker interoperability

Status: active; direct QoS 0 merged, authorized gateway and hosted translation
benchmarks implemented. Current PR review and controlled release acceptance
remain separate from the broader protocol milestone.

Current blocker: candidate `d1ab2132` fails retained-memory checks in six ARM64
64 KiB rows across CBOR, FlatBuffers and JSON. Absolute RSS, CPU, rate, latency
and overload pass. Preserve the complete candidate and frozen limits. A
25-cycle trace eventually reclaims accumulated RSS; full workload warm-up alone
does not fix the failing profiles. Validate a separate collection-normalized
retention pass without changing default-runtime performance or numerical caps.
The SDK-pinned Linux test adapter verifies live/released witnesses and a bounded nursery before sampling.
Local AOT checks pass 32 complete SDK/Paho lifecycles over all links/codecs;
Python is 1,084/1,084 and the changed worker 308/308. Hosted diagnostics, current
whole-gateway coverage and final exact-commit CI remain acceptance blockers.

Required CI now uses a separate hardware-qualified ARM64 reference with the
same workload and frozen policy. Architecture, CPU count and CPU signature must
match before sampling. Earlier x64 values and rejected cross-CPU candidates
remain intact. Per-publication reply-port experiments were inconclusive and
are excluded from production code.

## Gateway contract and completed implementation

The [MQTT contract](../mqtt.md) documents the opt-in realm-bound gateway,
explicit `connectanum.mqtt.v1.publish` API, application bytes and origin tracing.
Client IDs do not confer identity; ordinary `ppt_scheme: mqtt` remains opaque.

- [x] Authorize incoming publications before delivery and concrete outgoing topics for wildcard recipients; retain the synchronous direct path without a gateway.
- [x] Derive WAMP caller identity from trusted invocation state and recheck cancellation after asynchronous authorization.
- [x] Bound per-peer/aggregate policy queues, pending API work and topic cache; preserve ordering, cancellation and teardown.
- [x] Live Connectanum/Paho/WAMP regressions for both MQTT versions and TCP/TLS/WS/WSS, including ACL/realm isolation, binary payloads, spoofing, loops, failures and lifecycle.
- [x] Exact scoped coverage for all new gateway/benchmark sources and changed shared executable lines; preserve existing MQTT/WAMP gates.
- [x] Separate AOT processes for both translations, matched MQTT/WAMP/acknowledged-WAMP/Mosquitto controls, all four WAMP serializers, three payload sizes, fan-out and credit windows.
- [x] Record throughput, latency, active CPU, per-process warm/high-water/drained RSS, lifecycle growth, queue drain and overload recovery. Allocation counters remain unavailable and explicitly null.
- [x] Accept the complete hosted baseline at unchanged rate/p99/CPU variation caps 0.20/0.75/0.35; freeze numeric budgets and every-cell README regressions.
- [x] Require secure-peer smoke and sixteen profile shards before Full Verify, rejecting omitted or unsuccessful lanes.

## Accepted evidence and verification

The [x64 reference](https://github.com/konsultaner/connectanum-dart/actions/runs/41327609801)
and [ARM64 reference](https://github.com/konsultaner/connectanum-dart/actions/runs/41341341988) each contain 960 normal samples and 12 overload
cycles. Combined: 23.1 million exact deliveries, including 7.7 million
translations, zero duplicates, 49,152 healthy overload deliveries and 1,536
recovery deliveries. All 128 direction/profile results and eight overload cases
pass their separate [x64](../../tool/mqtt_gateway_benchmark_budgets.json) and
[ARM64](../../tool/mqtt_gateway_arm64_benchmark_budgets.json) budgets. The
[README tables](../../packages/connectanum_bench/README.md#mqtt-and-wamp-gateway)
include direct controls and every per-process memory result. All four ARM64
shards and their secure smoke match the recorded CPU signature.

Last accepted reference coverage passes 744/744 gateway/shared Dart, 759/759 MQTT, 270/270 gateway
component, 882/882 native added production and 947/947 Python lines (zero
exclusions). Native source SHA-256 is
`1254e2279369f2d3e5f5b78236d5beeda58295e201f9ba2b2f3edbd52c93fc01`;
source hashes and the retained compressed Cargo/Dart FFI union are test-checked.
Fresh full `bin/verify` passes, including Rust, Dart VM, consumers and Chrome/Wasm.
Independent MQTT checks pass 104 tests; benchmark/worker checks pass 56.

Fail-first fixes cover payload-oracle overhead, MQTT peer-FIN socket retention,
Paho/native MQTT WS TCP_NODELAY, native receive credit and slow-peer queue
saturation. Current native WS acceptance passes all 12 sustained checks in
[41322497967](https://github.com/konsultaner/connectanum-dart/actions/runs/41322497967)
with every existing budget intact. A minimum one-second/200-message warm-up
records actual counts and durations; all measured cycles remain in acceptance.

The [gateway archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-2026-11-01) retains accepted and rejected raw runs,
provenance, coverage traces, regression logs and reproduction helpers outside
Git. Compact offline fixtures validate every table cell and frozen policy.
The [ARM64 supplement](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-arm64-2026-11-01) also retains the rejected cross-CPU PR #135 candidates.
The earlier [PR #128 archive](../benchmarks/README.md#archive) remains available.

## Remaining milestone and release work

| Step | State |
| --- | --- |
| Codec/topic/coverage, #110–#111 | Implemented; full-protocol conformance remains a release prerequisite |
| Direct live QoS 0, #112–#115, #125–#127 | Merged in PR #128, with existing numeric gates preserved |
| Authorized gateway, #116–#117 | Implemented; ready for current PR review and exact-head CI acceptance |
| Translation performance/memory, #131 | Hosted results/budgets implemented; controlled-hardware release sign-off remains open |
| Complete protocol, #118–#123 | QoS 1/2, retained/wills, persistence, credential authentication and full properties remain open |
| Release, #124 | Requires all advertised protocol, recovery, coverage, performance and operational acceptance |

No GitHub self-hosted runner is registered. Available GitLab Linux runners are
general/shared, without a confirmed exclusive benchmark reservation. Keep
hosted CI on GitHub Actions and retain controlled-hardware release sign-off as
an explicit open criterion in #131. Auxiliary kTLS ULP and WAMP diagnostic
throughput misses remain visible; their budgets are unchanged.

Use `bin/test-fast` before substantial changes, focused live/gate/README checks
during work, then `bin/verify` and
`bin/dart-package-publish-dry-run --strict-release-ready`. The current branch's
GitHub checks determine exact-head CI acceptance before merge; fixtures do not
replace live measurements. A new merge requires user authorization.
