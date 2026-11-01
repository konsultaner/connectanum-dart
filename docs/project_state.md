# Project State

Last updated: 2026-11-01.
Current priority: [MQTT milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2), explicitly prioritized by the user.
Active plan: [MQTT interoperability](exec-plans/2026-10-14-mqtt-broker-interoperability.md).
Branch: `codex/mqtt-wamp-gateway`, based on merged master `ef822e08`.

[PR #128](https://github.com/konsultaner/connectanum-dart/pull/128) merged direct
QoS 0 MQTT 5/3.1.1 over TCP/TLS/WS/WSS. The current gateway implements #116/#117:
opt-in realm authorization, trusted WAMP caller identity, binary application
publications, bounded queues and cancellation. Ordinary MQTT PPT stays opaque.
The [contract](mqtt.md) has configuration and client examples.

The complete [63a897a5 hosted baseline](https://github.com/konsultaner/connectanum-dart/actions/runs/41327609801) passes 32 profiles, six paths,
five cycles, 960 normal samples and 12 overload/recovery cycles: 11.55 million
exact deliveries including 3.85 million translations, zero duplicates, 24,576
healthy overload deliveries and 768 recovery deliveries. Fixed rate/p99/CPU
variation caps remain 0.20/0.75/0.35. All 64 translation and four overload rows
pass the frozen budgets. README tables include every direction/profile result,
per-process CPU and warm/peak/drained RSS, direct controls and memory growth.

Coverage passes 744/744 gateway/shared Dart lines, 759/759 MQTT lines, 270/270
gateway component lines, 882/882 native added production lines and 910/910
Python tooling lines, with zero Python exclusions. The source-hash regression
recomputes the compressed native Cargo + Dart FFI union for current Rust source
SHA-256 `1254e227…c93fc01`. Fresh full `bin/verify` passes on the current
production code, including VM, consumer smoke, Chrome and WebAssembly.
Offline tests validate every new README cell and the exact budget policy.

Required GitHub Actions smoke and four numeric shards are Full Verify
prerequisites. Missing, failed, skipped and cancelled lanes fail closed;
diagnostic record-only runs remain explicit. The
[current branch checks](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart.yml?query=branch%3Acodex%2Fmqtt-wamp-gateway)
are authoritative for exact-head CI acceptance before merge. Historical passes
do not validate later edits. A new merge requires user authorization.

Raw accepted/rejected runs, toolchain/host identities, coverage traces and
regression logs live in the [gateway history archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-2026-11-01), with archive
checksums and a per-file manifest. Source retains compact fixtures, README
tables, numeric budgets and current compressed coverage proof. The
[PR #128 archive](benchmarks/README.md#archive) remains available.

The broader milestone stays open for QoS 1/2, retained messages/wills,
persistence, credential authentication and release conformance. #131's
controlled-hardware release sign-off also remains open: no GitHub self-hosted
runner is registered, and the available GitLab Linux runners are general/shared
without a confirmed exclusive benchmark reservation. Hosted regression gates
remain on GitHub Actions.

Two pre-existing auxiliary failures remain visible: strict kTLS lacks Linux TLS
ULP support, and WAMP diagnostics miss existing 2,000 Mbit/s floors on buffered
Dart file/heavy RawSocket paths. Their budgets stay unchanged. The native
TCP_NODELAY correction passes all 12 Linux sustained comparisons in
[41322497967](https://github.com/konsultaner/connectanum-dart/actions/runs/41322497967).
Other work is preserved: [ObjectBox PR #133](https://github.com/konsultaner/connectanum-dart/pull/133)
published 3.0.0-beta.8; the [FlatBuffers plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md)
remains deferred/reference work during this MQTT priority.
