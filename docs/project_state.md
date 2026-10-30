# Project State

Last updated: 2026-10-30.
Current priority: [MQTT broker interoperability, milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2), explicitly prioritized by the user.
Active plan: [MQTT execution plan](exec-plans/2026-10-14-mqtt-broker-interoperability.md).
Branch: `codex/mqtt-broker-interoperability`, incorporating master `78f2b32b`.

[PR #128](https://github.com/konsultaner/connectanum-dart/pull/128) is ready for review.
It delivers direct QoS 0 MQTT 5/3.1.1 over TCP/TLS/WS/WSS with independent clients
and numeric CI gates. The broader milestone remains open: authenticated gateway
routing, translation benchmarks (#131), QoS 1/2, persistence, retain/wills and
release conformance still need implementation. See the [MQTT contract](mqtt.md).

The user requested slimming the PR: historical benchmark runs and working notes
are preserved in a [verified immutable archive](benchmarks/README.md#archive).
Current README tables, compact offline fixtures, implementation/tests, compressed
coverage proof and existing CI performance budgets stay in the source tree.
The preservation audit and focused README/gate tests pass; production, budgets,
CI and coverage policies are byte-identical. Canonical verification and hosted
acceptance are tracked on the PR checks under the active plan.

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
