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

The opt-in gateway, trusted original-caller lookup and independent AOT benchmark
participants are implemented. The 10-profile local diagnostic matrix completed
120 exact samples across both translations and four controls (including pinned
Mosquitto on CI). Full Linux baseline measurement precedes numeric budget locking.
New regressions reproduce/fix concurrent MQTT writes during flush, native CBOR
byte-string typing, and internal WAMP calls blocking CANCEL/GOODBYE. Scoped coverage passes 679/679 new gateway/shared executable lines, 758/758 MQTT
lines and 270/270 gateway lines. The worker includes post-disconnect router-state
checks, with refreshed source and CLI coverage passing. Slow-recipient regressions
pass for both origins. README results, numeric lifecycle budgets and strict hosted
gates remain required before completion. `bin/verify` found a stale state mutation
test inventory; the inventory is fixed and its 93-test regression passes. Full
verification is being rerun.

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
