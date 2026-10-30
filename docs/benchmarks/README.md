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

## Performance gates

The [MQTT gate](../../tool/run_mqtt_benchmark_gate.py) checks exact payloads,
counts, ordering and duplicates before throughput, p95/p99 latency, broker CPU
and RSS budgets. The [WebSocket rate budget](../../tool/mqtt_native_ws_sustained_benchmark_budget.json),
[64 KiB CPU budget](../../tool/mqtt_native_64k_sustained_benchmark_budget.json)
and [GitHub Actions lane](../../.github/workflows/dart.yml) remain authoritative.
Archived measurements do not replace fresh CI gates.

The accepted native source passes all 20 hosted profiles on EPYC 7763. A matched
Intel 8370C comparison passes both WebSocket versions twice at unchanged limits,
where the baseline fails; both 64 KiB CPU comparisons also pass. Full values,
earlier misses and hardware provenance remain in the package README tables.

WAMP results include JSON, MessagePack, CBOR and FlatBuffers. The
[WAMP profile contract](../wamp_profile_benchmarks.md) defines release acceptance.
MQTT↔WAMP translation remains unimplemented and has no accepted benchmark;
[issue #131](https://github.com/konsultaner/connectanum-dart/issues/131) tracks both
directions, direct-path controls and memory/queue measurements.

## Coverage

| Scope | Covered / executable lines |
| --- | ---: |
| Native MQTT added production lines | 882 / 882 |
| MQTT Dart sources | 651 / 651 |
| MQTT benchmark gate Python, zero exclusions | 268 / 268 |

The [native inventory](mqtt-native-added-line-coverage-ready-yield.json) records
exact line numbers and source hashes for five current production files. The
[Cargo LCOV](mqtt-native-added-line-coverage-ready-yield-cargo-unit.info.gz) and
[Dart FFI LCOV](mqtt-native-added-line-coverage-ready-yield-dart-ffi.info.gz)
allow independent recomputation of their union. Scope uses the Rust production
filter and patience diff against `73d840c9`; tests, comments and non-executable
lines are excluded. Collection platform is macOS arm64 with `ffi-test`.
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
New raw runs stay in CI artifacts or the archive; update the table fixtures only
when intentionally publishing new measurements.

Run `python3 tool/test_dart_package_publish_dry_run.py` for the table regressions
and `bin/verify` for the canonical repository verification.
