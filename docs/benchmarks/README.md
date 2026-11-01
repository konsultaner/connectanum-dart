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
verified before publication. Raw history stays outside Git.

## Performance gates

The [MQTT gate](../../tool/run_mqtt_benchmark_gate.py) checks exact payloads,
counts, ordering and duplicates before throughput, p95/p99 latency, broker CPU
and RSS budgets. The [WebSocket rate budget](../../tool/mqtt_native_ws_sustained_benchmark_budget.json),
[64 KiB CPU budget](../../tool/mqtt_native_64k_sustained_benchmark_budget.json)
and [GitHub Actions lane](../../.github/workflows/dart.yml) remain authoritative.
Archived measurements do not replace fresh CI gates.

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
report 64 measured direction/profile cases, direct controls, per-process memory
and four overload cases from [source `63a897a5`](https://github.com/konsultaner/connectanum-dart/actions/runs/41327609801). Required smoke and four
numeric release shards preserve the fixed rate/p99/CPU variation caps
0.20/0.75/0.35 and enforce absolute and matched-control budgets. The compact
[budget file](../../tool/mqtt_gateway_benchmark_budgets.json) records each limit
and its derivation policy. CI measures live paths; archived results do not
replace a fresh pass.

## Coverage

| Scope | Covered / executable lines |
| --- | ---: |
| Native MQTT added production lines | 882 / 882 |
| MQTT Dart sources | 759 / 759 |
| Gateway/shared Dart sources | 744 / 744 |
| Gateway component | 270 / 270 |
| MQTT benchmark gate Python, zero exclusions | 268 / 268 |
| Gateway tooling Python, zero exclusions | 910 / 910 |

The [native inventory](mqtt-native-added-line-coverage-ready-yield.json) records
exact line numbers and source hashes for five current production files. The
[Cargo LCOV](mqtt-native-added-line-coverage-ready-yield-cargo-unit.info.gz) and
[Dart FFI LCOV](mqtt-native-added-line-coverage-ready-yield-dart-ffi.info.gz)
allow independent recomputation of their union. Scope uses the Rust production
filter and patience diff against `73d840c9`; tests, comments and non-executable
lines are excluded. Collection platform is macOS arm64 with `ffi-test`.
The proof matches current Rust source SHA-256 `1254e227…c93fc01`; a tooling
regression verifies all five source hashes and the complete compressed union.
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
The [gateway fixture](../../tool/fixtures/mqtt_gateway_readme.json) retains the
64 current translation summaries, 32 matched control rates and four overload
summaries, with source/host hashes. Regression tests recompute every formatted
README cell and rescore every numeric limit. New raw runs stay in CI artifacts
or the archive; update the table fixtures only
when intentionally publishing new measurements.

Run `python3 tool/test_dart_package_publish_dry_run.py` for the table regressions
and `bin/verify` for the canonical repository verification.
