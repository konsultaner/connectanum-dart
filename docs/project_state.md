# Project State

Last updated: 2026-11-01.
Current priority: [MQTT broker interoperability, milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2), explicitly prioritized by the user.
Active plan: [MQTT execution plan](exec-plans/2026-10-14-mqtt-broker-interoperability.md).
Branch: `codex/mqtt-wamp-gateway`, based on merged master `ef822e08`.

[PR #128](https://github.com/konsultaner/connectanum-dart/pull/128) merged as `ef822e08`.
It delivers direct QoS 0 MQTT 5/3.1.1 over TCP/TLS/WS/WSS with independent clients
and numeric CI gates. The broader milestone remains open: authenticated gateway
routing, translation benchmarks (#131), QoS 1/2, persistence, retain/wills and
release conformance still need implementation. The current task implements the
authorized gateway (#116/#117) and translation performance/memory gates (#131).
See the [MQTT contract](mqtt.md) and active plan.

The opt-in authorized gateway and process-isolated AOT benchmarks are implemented.
Coverage currently passes 744/744 gateway/shared Dart executable lines, 758/758
MQTT lines, 270/270 gateway component lines and 885/885 Python gate lines with
zero exclusions. Independent Paho/Connectanum MQTT checks pass all 102 tests;
56 benchmark/worker cases pass. The first clean sequential `bin/verify`, strict
publishing, 150 WAMP integration tests and 50 shutdown/restart cycles pass. A
fresh full verify also passes after adding publisher-disconnect observation.
An earlier overlapping verify failed; those WAMP cases pass in clean reruns.

Existing hosted direct MQTT and WAMP profile gates pass on `08c654c0`. Its
superseded baseline found a Paho trust-anchor error, now fixed to use the owned
CA. The corrected 16-profile hosted smoke passes on `ceb57d89`, including TLS/WSS
and both MQTT versions. The superseded release run
[41307802399](https://github.com/konsultaner/connectanum-dart/actions/runs/41307802399)
exposed Python byte-by-byte payload checking as a 64 KiB client bottleneck and
exceeded the load deadline. The identical byte formula now uses C-backed byte
construction/comparison; golden-byte and corruption regressions pass. Load
phases allow 300 seconds; startup/control deadlines remain 60 seconds. A fresh
immutable release baseline is required before freezing numeric limits.

Locally prepared strict CI wiring makes smoke and all four numeric shards
prerequisites of Full Verify; gate tests reject every missing/unsuccessful lane.
The numeric budget file and compact README fixture still await the complete
immutable Linux baseline. Keep this wiring uncommitted until those files exist.
Remaining work: verify all 960 normal and 12 overload samples, freeze budgets,
archive raw evidence, publish README tables, finish current-source local/hosted
checks and open the ready gateway PR. Do not close the broader MQTT milestone.

Merged-master CI [41105562746](https://github.com/konsultaner/connectanum-dart/actions/runs/41105562746),
publishing and the required WAMP profile benchmark pass. Local `bin/test-fast` passes. Focused gateway, worker and independent-peer checks are passing;
full current-head verification and hosted gateway acceptance remain pending. Two pre-existing auxiliary workflows
remain red and must stay visible: strict kTLS cannot set the Linux TLS ULP on its
runner, and WAMP diagnostics miss existing 2,000 Mbit/s floors on buffered Dart
file / heavy RawSocket paths. Neither budget is relaxed by gateway work.

The user requested slimming the PR: historical benchmark runs and working notes
are preserved in a [verified immutable archive](benchmarks/README.md#archive).
Current README tables, compact offline fixtures, implementation/tests, compressed
coverage proof and existing CI performance budgets stay in the source tree.
The preservation audit and README/gate tests passed for the merged cleanup.
The gateway extends production code, source coverage and CI while preserving
existing numeric budgets. Current-head acceptance is tracked in the active plan.

Last accepted production source is `f7235055` (full hash in the plan).
[CI 40968103538](https://github.com/konsultaner/connectanum-dart/actions/runs/40968103538)
passed all 37 jobs on pre-cleanup head `538e029c`. Full local verification,
strict package publishing and scoped native 882/882, Dart 651/651 and Python
268/268 coverage passed. All 20 hosted MQTT profiles passed on EPYC 7763;
matched Intel 8370C candidate runs also pass the unchanged WS/64 KiB limits.
The [PR checks](https://github.com/konsultaner/connectanum-dart/pull/128/checks)
are authoritative for the latest head; historical passes do not validate later edits.

Other project work is preserved: the separate
[`connectanum_objectbox_adapter` 3.0.0-beta.8](https://pub.dev/packages/connectanum_objectbox_adapter/versions/3.0.0-beta.8)
was published via [PR #133](https://github.com/konsultaner/connectanum-dart/pull/133).
The [FlatBuffers plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md)
remains reference/deferred work during this MQTT priority. Its performance
acceptance is distinct from the outer-envelope README measurements.
