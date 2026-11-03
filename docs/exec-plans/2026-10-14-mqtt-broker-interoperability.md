# MQTT broker interoperability

Status: active CI follow-up. PR #135 merged on 2026-11-03 as `ef1479d6`.
Gateway functionality, both-direction performance/memory qualification and the
downloaded history/CI archives are complete. Final publication CI `41493246321`
passes 59 checks. The current task separates two manual diagnostic entry points
from PR-triggered profiling, preserving every mandatory gate.

The working branch contains runtime `839bbf6e`. Runtime and benchmark gate inputs
match its frozen source; the non-benchmark macOS ownership lane now explicitly
selects Intel. Coverage is 1,016/1,016 Dart, 979/979 added native
lines and 1,084/1,084 gateway tooling statements with zero exclusions. Payload
lifetime, shared isolate snapshots, bounds, ordering, profile acceptance and
per-recipient failures have fail-first/live regressions and local review.

[Complete qualification 41464161501](https://github.com/konsultaner/connectanum-dart/actions/runs/41464161501)
passes all sixteen shards: 1,304 performance/retention samples, 64 translation
and four overload results. All 264 independent secure samples pass. Every
original rate, latency, CPU, peak/drained RSS and retained-growth cap is unchanged;
zero duplicates are recorded. Clean frozen-source full Rust/Dart/Chrome/Wasm
verification passed at 14:40 UTC without source drift.

- [x] Qualify the final source against all sixteen strict shards and secure smoke.
- [x] Promote the exact runtime and refresh source-matched 100% coverage.
- [x] Publish friendly README tables and test every displayed cell.
- [x] Finish canonical verification on the working branch, including Chrome/Wasm and zero source drift.
- [x] Publish complete accepted/rejected history with downloaded checksum verification.
- [x] Synchronize fan-out fixture worker registration; preserve exact batching assertions and pass all 55 cases under VM coverage.
- [x] Verify the fixture/runner follow-up without runtime or numeric budget drift.
- [x] Pass the complete exact-head GitHub Actions chain before handoff.
- [x] Add a regression for automatic PR jobs registering only applicable checks.
- [x] Keep CPU profiling automatic, route manual gateway runs through their existing workflow, and move the Intel probe to its own manual workflow.
- [x] Preserve hardware qualification, recovery/comparison modes, coverage and every numeric/required gate.
- [ ] Run local verification and publish the CI routing follow-up for fresh PR checks.

The routing reproducer fails against the merged workflow and passes after the
split. All 19 CI-contract tests and 12 native comparison/Intel hardware tests pass;
Actionlint 1.7.12 accepts the three diagnostic workflows. `bin/test-fast` passes.
Profiler steps and Intel comparison/artifact steps match the merged source, and
main CI, gateway recorder, coverage validators and all MQTT budgets are unchanged.

Use [project state](../project_state.md) for current verification status. The
[README](../../packages/connectanum_bench/README.md#mqtt-and-wamp-gateway) contains
164 current default-runtime rows and 68 separate retained-memory rows. Frozen
references and all numeric policies remain unchanged. Stress-only collection
uses bounded nursery capacity and verified managed/native negative controls;
its timing is excluded from performance acceptance.

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

The [paired comparison](https://github.com/konsultaner/connectanum-dart/actions/runs/41460290435)
independently verifies all twenty samples and 400,000 exact deliveries. For
64 KiB FlatBuffers fan-out, broker drained RSS falls from 56–62 MiB to 34–40 MiB;
broker CPU seconds per million deliveries falls from 249.7–251.7 to 214.4–220.1.
The former failing profile drains at 31.07 MiB in the full campaign, below 54 MiB.
Strict pilot, WSS recovery, both-direction controls and all complete-matrix gates
pass. The original native proof-assembly failure lacked shallow Git history;
its complete raw GNU reports reconstruct 979/979 coverage with all 93 inputs
verified. No measurements were repeated or discarded during recovery.

The [history archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-retention-2026-11-02)
retains every complete/partial/rejected campaign, source snapshots, coverage,
raw reports and reproduction helpers outside Git. Earlier gateway, ARM64 and
PR #128 evidence remains linked from the [archive index](../benchmarks/README.md#archive).
Final source and exact-head CI records must remain separately attributable.

Publication run `41477975179` exposed a test topology race: `minWorkers` permits
additional workers while the prestarted pool is pending. Fan-out cases now wait
for `worker_registered` before opening clients and still require one shared graph
per configured worker. GitHub also cancelled the ownership lane without assigning
a runner, with explicit macOS ARM64 capacity annotations. The follow-up uses the
[documented Intel macOS 15 label](https://github.com/actions/runner-images#available-images)
for the same GuardMalloc checks. This changes neither ARM64 benchmark hardware nor
any measurement budget. Preserve the first run's failed/cancelled records and raw
benchmark samples alongside the final CI supplement. All sixteen numeric shards
pass in that first run; all 264 secure samples were independently audited, and
all 53 artifacts were captured with verified GitHub digests. That first run remains
recorded as failed; the final follow-up passes all required checks in
[41493246321](https://github.com/konsultaner/connectanum-dart/actions/runs/41493246321).

## Remaining milestone and release work

| Step | State |
| --- | --- |
| Codec/topic/coverage, #110–#111 | Implemented; full-protocol conformance remains a release prerequisite |
| Direct live QoS 0, #112–#115, #125–#127 | Merged in PR #128, with existing numeric gates preserved |
| Authorized gateway, #116–#117 | Merged in PR #135, with final CI and independently verified archives |
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
