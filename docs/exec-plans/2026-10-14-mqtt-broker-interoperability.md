# MQTT broker interoperability

Status: active; direct QoS 0 PR ready, broader milestone incomplete.
Owner: Codex. Started: 2026-10-14. Updated: 2026-10-30.
Tracking: [milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2),
[PR #128](https://github.com/konsultaner/connectanum-dart/pull/128).

## Goal and contract

Accept standard MQTT clients, provide a Connectanum MQTT client, and route
explicitly authorized publications between MQTT and WAMP. Release requires
independent interoperability, 100% scoped executable-line coverage, complete
regression rows and numeric live-path performance gates.
The [MQTT contract](../mqtt.md) defines supported transports, ownership, topic
mapping and the still-pending gateway boundary. WAMP `ppt_scheme: mqtt` remains opaque.

## Milestone steps

| Step | State and acceptance |
| --- | --- |
| Contract and coverage foundation, #110–#111 | Bounded codec, topic mapper and scoped coverage implemented; full advertised protocol matrix remains a release prerequisite |
| Live QoS 0, #112–#117, #125–#126 | Native TCP/TLS/WS/WSS, Connectanum/Paho/Mosquitto integration implemented; authorized WAMP gateway remains open |
| Direct MQTT performance, #127 | 20 hosted profiles, exact delivery and unchanged latency/CPU/RSS/rate gates pass on accepted source; matched Intel improvement measured |
| MQTT↔WAMP translation, #131 after #116–#117 | Pending live gateway; require both directions and direct controls, throughput, p95/p99, CPU, peak/steady/post-drain RSS, allocations/queue growth and connect/drain cycles |
| Complete protocol, #118–#123 | QoS 1/2, retained publications/wills, persistence, authentication/authorization and full version-specific properties remain open |
| Release, #124 | Close only after every advertised version/transport/QoS/direction, negative/recovery, coverage, performance and package/operations acceptance passes |

## Accepted evidence

[Package README tables](../../packages/connectanum_bench/README.md) preserve current
results and earlier misses. [Benchmark evidence](../benchmarks/README.md) contains
coverage receipts and the complete archive. Accepted native source SHA-256 is
`f723505558d8ba530aef92f6e9373fc4831f4670517706d917942fa85159cf17`.

Before this cleanup, [CI 40968103538](https://github.com/konsultaner/connectanum-dart/actions/runs/40968103538)
passed all 37 jobs on `538e029c`. Full local `bin/verify`, strict package publishing,
882/882 native added production lines, 651/651 MQTT Dart lines and 268/268 gate
Python lines (zero exclusions) passed. These are scoped coverage counts.

The matched Intel 8370C baseline fails both WS versions twice; the accepted
candidate passes twice with lower CPU. EPYC 7763 passes all 20 profiles. Numeric
budgets are unchanged. Further optimization needs an actual measured failure.

## PR slimming evidence

- [x] Publish, download and independently verify original history, checksums and per-file manifest at the immutable archival tag.
- [x] Retain README tables, compact offline regression inputs, code/tests and current compressed coverage proof; consolidate the contract and working notes.
- [x] Pass focused README/gate regressions, independently compare every fixture field with its archived source, and recompute 882/882 native coverage from the retained traces.

Handoff requires `bin/verify`, strict publishing and green GitHub Actions on the
exact cleanup head. The [PR checks](https://github.com/konsultaner/connectanum-dart/pull/128/checks)
record current hosted acceptance. Keep PR ready; do not merge or close the broader milestone.

## Verification commands

Run `bin/test-fast` before substantial changes, focused README/gate regressions
during cleanup, then `bin/verify` and `bin/dart-package-publish-dry-run --strict-release-ready`.
CI must retain its existing performance and 100% scoped coverage gates.
Do not replace raw gate inputs with historical fixtures: fixtures check published
tables; CI benchmarks measure the live implementation.
