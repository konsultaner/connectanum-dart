# Project State

Last updated: 2026-11-01.
Current priority: [MQTT broker interoperability, milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2), explicitly prioritized by the user.
Active plan: [MQTT execution plan](exec-plans/2026-10-14-mqtt-broker-interoperability.md).
Branch: `codex/mqtt-wamp-gateway`, based on merged master `ef822e08`.

[PR #128](https://github.com/konsultaner/connectanum-dart/pull/128) merged direct
QoS 0 MQTT 5/3.1.1 over TCP/TLS/WS/WSS, independent clients and numeric gates.
The current task adds the authorized gateway (#116/#117) and bidirectional
performance/memory gates (#131). The broader milestone remains open for QoS 1/2,
retained messages/wills, persistence, MQTT credential authentication and release
conformance. See the [MQTT contract](mqtt.md).

The opt-in gateway and separate-process AOT benchmark are implemented. Current
coverage passes 744/744 gateway/shared Dart lines, 759/759 MQTT lines, 270/270
gateway component lines, 882/882 native added production lines and 910/910
Python tooling lines, with zero Python exclusions. The native proof matches
current Rust source SHA-256 `1254e227…c93fc01`; a regression checks source hashes
and recomputes its compressed Cargo + Dart FFI LCOV union. Independent Paho /
Connectanum MQTT tests (104), benchmark/worker cases (56), and full `bin/verify`
pass, including VM and Chrome/WebAssembly. The full verification was on
`5b1e4a43`; subsequent changes are Python warm-up accounting and documentation.

The gateway baseline runs 32 profiles, all six translation/control paths and
five cycles: 960 normal samples plus 12 overload/recovery cycles. Earlier runs
exposed and reproduced Paho payload-oracle overhead, MQTT peer-FIN socket
retention and Nagle stalls. The fixes retain exact payload/counter checks,
zero-exit teardown, bounded queues and all existing numeric caps. The native
TCP_NODELAY correction passes all 12 Linux sustained checks in
[41322497967](https://github.com/konsultaner/connectanum-dart/actions/runs/41322497967):
WS ratios 0.807–0.868 against the unchanged 0.700 floor; 64 KiB CPU ratios
2.867–3.133 against 4.000.

The complete [5b1e4a43 run](https://github.com/konsultaner/connectanum-dart/actions/runs/41323493587)
passes delivery and recovery but is rejected for the fastest MQTT control's
p99 variation. Its 200-message warm-up lasted about 20 ms. The harness now
requires both 200 messages and one second, records the actual count/duration,
and checks cumulative publication counters against that count. All four real
Paho links pass both directions. Rerun the complete hosted matrix before
freezing numeric limits; do not accept samples from rejected runs.

Remaining work: validate the new immutable Linux baseline, freeze budgets,
publish compact README tables and externally archive raw evidence, enable the
prepared required smoke/four-shard CI chain, run current-source checks and open
a ready PR. Keep rate/p99/CPU variation caps at 0.20/0.75/0.35. No new merge is
authorized. The previous [history archive](benchmarks/README.md#archive) remains
available; new raw runs stay outside Git.

Merged-master required CI/publishing and the WAMP profile gate pass. Two
pre-existing auxiliary failures remain visible: strict kTLS lacks Linux TLS ULP
support, and WAMP diagnostics miss existing 2,000 Mbit/s floors on buffered Dart
file/heavy RawSocket paths. Their budgets remain unchanged.

Other work is preserved: separate [ObjectBox adapter PR #133](https://github.com/konsultaner/connectanum-dart/pull/133)
published 3.0.0-beta.8. The [FlatBuffers plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md)
remains deferred/reference work during this MQTT priority.
