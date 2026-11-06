# Benchmark evidence

Current MQTT and WAMP results are published as tables in the
[benchmark package README](../../packages/connectanum_bench/README.md).
Full historical runs are archived separately; compact offline fixtures keep the
tables covered by regression tests.

## Archive

The [PR #128 benchmark archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-pr128-2026-10-30)
preserves 371 original benchmark and supporting documentation files from
`538e029cbbcb93156cabcd1c764d55d896c58077`, including failed runs and rejected trials.
The immutable tag also lets readers browse every original file.

| Download | Contents |
| --- | --- |
| [History archive](https://github.com/konsultaner/connectanum-dart/releases/download/benchmark-history-pr128-2026-10-30/pr128-benchmark-history-538e029c.tar.gz) | Original reports, raw samples, coverage traces and supporting docs |
| [Manifest](https://github.com/konsultaner/connectanum-dart/releases/download/benchmark-history-pr128-2026-10-30/pr128-benchmark-history-538e029c.manifest.json) | Source/base commits and each file's size and SHA-256 |
| [Checksums](https://github.com/konsultaner/connectanum-dart/releases/download/benchmark-history-pr128-2026-10-30/pr128-benchmark-history-538e029c.sha256) | Archive and manifest SHA-256 checksums |

Archive SHA-256: `0776d6e530b9c6f1016f27e8e5725c47395f680fd08ed88d5d1c5b101750fd32`.
Download verification compared all three uploaded assets byte for byte and checked
each extracted file against the manifest and original Git source.

## Gateway archive

[Gateway history](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-2026-11-01) preserves accepted raw samples, rejected/partial
runs, source/toolchain/host identities, exact payload/counter receipts,
coverage traces, regression logs and the native WS comparison. Its archive,
per-file SHA-256 manifest and checksum file are independently downloaded and
verified before publication. The [ARM64 supplement](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-arm64-2026-11-01) retains the second hardware-qualified reference and the rejected
x64 PR #135 candidates. Raw history stays outside Git. The [current performance and retention archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-retention-2026-11-02)
binds runtime `839bbf6e` to the complete [sixteen-shard campaign](https://github.com/konsultaner/connectanum-dart/actions/runs/41464161501),
all 1,304 benchmark and 264 secure samples, coverage, source snapshots and prior
rejected experiments.

## Performance gates

The [MQTT gate](../../tool/run_mqtt_benchmark_gate.py) checks exact payloads,
counts, ordering and duplicates before throughput, p95/p99 latency, broker CPU
and RSS budgets. The [WebSocket rate budget](../../tool/mqtt_native_ws_sustained_benchmark_budget.json),
[64 KiB CPU budget](../../tool/mqtt_native_64k_sustained_benchmark_budget.json)
and [GitHub Actions lane](../../.github/workflows/dart.yml) remain authoritative.
Archived measurements do not replace fresh CI gates.

Hardware qualification is required for absolute budgets. GitHub documents
[`ubuntu-24.04-arm` as a four-vCPU public runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
and [Arm documents Cobalt 100 / Neoverse N2 hardware](https://learn.arm.com/learning-paths/cross-platform/github-arm-runners/public-repos/).
The gateway workflow captures `lscpu` and `/proc/cpuinfo` before sampling. Numeric
acceptance must match the recorded architecture, CPU count and CPU identity;
the runner label alone is not a hardware guarantee. Keep the x64 snapshots and
their limits when establishing a separate ARM64 reference with the same policy.

If a runner identity changes, preserve the failed artifact and run the complete
[gateway release workflow](../../.github/workflows/mqtt-gateway-benchmarks.yml)
with `record_only: true` at the frozen workload. A different CPU class needs a
separate reviewed reference and README rows; retain prior limits and samples.

The published direct MQTT baseline passes all 20 hosted profiles on EPYC 7763. A matched
Intel 8370C comparison passes both WebSocket versions twice at unchanged limits,
where the baseline fails; both 64 KiB CPU comparisons also pass. Full values,
earlier misses and hardware provenance remain in the package README tables.
The current native TCP_NODELAY correction also passes all 12 sustained Linux
checks in [41322497967](https://github.com/konsultaner/connectanum-dart/actions/runs/41322497967)
without changing those limits.

WAMP results include JSON, MessagePack, CBOR and FlatBuffers. The
[WAMP profile contract](../wamp_profile_benchmarks.md) defines release acceptance.
MQTT↔WAMP translation uses explicit realm authorization. The
[gateway tables](../../packages/connectanum_bench/README.md#mqtt-and-wamp-gateway)
show the x64 reference and current ARM64 results, direct controls, per-process
memory and slow-consumer cases. The [current ARM64 campaign](https://github.com/konsultaner/connectanum-dart/actions/runs/41464161501)
passes all 1,304 performance/retention and 264 secure samples. The
[x64](https://github.com/konsultaner/connectanum-dart/actions/runs/41327609801)
and [ARM64](https://github.com/konsultaner/connectanum-dart/actions/runs/41341341988)
frozen reference fixtures and original numeric limits remain unchanged. Required smoke and sixteen
numeric release shards preserve the fixed rate/p99/CPU variation caps
0.20/0.75/0.35 and enforce absolute and matched-control budgets. Separate compact
[x64](../../tool/mqtt_gateway_benchmark_budgets.json) and
[ARM64](../../tool/mqtt_gateway_arm64_benchmark_budgets.json) budgets record each
limit and the same derivation policy. Required CI uses the ARM64 reference and
rejects a CPU signature mismatch before load. CI measures live paths; archived
results do not replace a fresh pass.

Default-runtime rate, latency, CPU and absolute RSS are measured separately
from the [Linux retention stress protocol](../mqtt.md#verification-and-performance).
The stress processes use an 8 MiB nursery limit and collection of unused memory;
their timings do not enter performance acceptance. All original numerical
limits remain in force.

## Running diagnostics

Main CI runs the required gateway smoke, sixteen numeric shards and coverage
checks on every PR. Manual captures use their own workflows:

| Workflow | Purpose |
| --- | --- |
| [MQTT CPU diagnostics](../../.github/workflows/mqtt-profile.yml) | Automatic profiling for relevant PRs; manual profile recovery or worker comparisons |
| [MQTT Gateway Benchmarks](../../.github/workflows/mqtt-gateway-benchmarks.yml) | Manual smoke or full gateway captures; numeric limits are enforced by default |
| [MQTT Intel hardware diagnostic](../../.github/workflows/mqtt-intel-profile.yml) | Manual 8370C availability and matched comparison with pinned userland |

```sh
gh workflow run mqtt-gateway-benchmarks.yml -f matrix=release
gh workflow run mqtt-intel-profile.yml
```

The Intel probe samples only matching 8370C hosts. Other hosts retain their CPU
identity and an explicit `benchmark_executed: false` result. Manual workflows
remain independent of PR profiler cancellation.

## Coverage

| Scope | Covered / executable lines |
| --- | ---: |
| Native MQTT added production lines | 979 / 979 |
| MQTT Dart sources | 772 / 772 |
| Gateway/shared Dart sources | 1,016 / 1,016 |
| Gateway component | 280 / 280 |
| MQTT benchmark gate Python, zero exclusions | 268 / 268 |
| Gateway tooling Python, zero exclusions | 1,084 / 1,084 |

The [native inventory](mqtt-native-added-line-coverage-ready-yield.json) records
exact line numbers and source hashes for six current production files. The
[Cargo LCOV](mqtt-native-added-line-coverage-ready-yield-cargo-unit.info.gz) and
[Dart FFI LCOV](mqtt-native-added-line-coverage-ready-yield-dart-ffi.info.gz)
allow independent recomputation of their union. Scope uses the Rust production
filter and patience diff against `73d840c9`; tests, comments and non-executable
lines are excluded. Collection platform is GNU Linux arm64 with `ffi-test`.
The proof matches current Rust source SHA-256 `fe3e816e…ba58c2f`; a tooling
regression verifies all six source hashes and the complete compressed union.
These are scoped executable-line counts, rather than whole-repository coverage.

Native regressions cover runtime transfer, bounded queues, shutdown and listener
failure, and the pinned WebSocket frame future across readiness polls, yield and
flush. Partial frames, once-Pending reads, large lengths, the 64 KiB bound,
consumer close and immediate sparse delivery are tested. Paho, Connectanum and
Mosquitto supply independent interoperability and delivery checks.

## Offline regression fixtures

[The fixture bundle](../../tool/fixtures/benchmark_readme.json) retains the seven
reports consumed by [README regression tests](../../tool/test_dart_package_publish_dry_run.py).
It records each archived source SHA-256 and retains every asserted field,
exact-delivery sample and measured WAMP run needed to recompute the table medians.
Unused logs and per-run metadata live in the archive. Tests run without downloads;
production gate code, numeric budgets and coverage scope are unchanged.
The [x64 gateway fixture](../../tool/fixtures/mqtt_gateway_readme.json) and
[ARM64 gateway fixture](../../tool/fixtures/mqtt_gateway_arm64_readme.json) each
retain 64 translation summaries, 32 matched control rates and four overload
summaries, with source/host hashes. Regression tests recompute every formatted
README cell and rescore every numeric limit. New raw runs stay in CI artifacts
or the archive; update the table fixtures only
when intentionally publishing new measurements.

Run `python3 tool/test_dart_package_publish_dry_run.py` for the table regressions
and `bin/verify` for the canonical repository verification.
