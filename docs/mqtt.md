# MQTT support and routing contract

Connectanum provides an opt-in QoS 0 MQTT broker and client for MQTT 5.0 and
3.1.1 over TCP, TLS, WebSocket and secure WebSocket. Native listeners negotiate
MQTT alongside HTTP and WAMP. Anonymous MQTT listening is restricted to numeric
loopback addresses until principal authentication and authorization are implemented.

| Capability | Current status |
| --- | --- |
| QoS 0 pub/sub, filters, bounded framing and queues | Implemented and independently tested |
| TCP/TLS/WS/WSS; Paho and Connectanum clients; Mosquitto control | Implemented and benchmarked |
| Reversible MQTT-topic/WAMP-URI names | Implemented |
| Authorized MQTT↔WAMP gateway and translation benchmarks | Pending: #116–#117, #131 |
| QoS 1/2, persistence, retained publications, wills, full MQTT 5 properties | Pending: #118–#123 |

The [active plan](exec-plans/2026-10-14-mqtt-broker-interoperability.md) tracks the
remaining [MQTT milestone](https://github.com/konsultaner/connectanum-dart/milestone/2).

## Transport and ownership

Native classification validates a bounded CONNECT preamble: fixed byte `0x10`,
minimal one-to-four-byte Remaining Length, protocol name `MQTT`, and level 5 or 4.
It rejects malformed, overflowing, truncated or too-short preambles under one
handshake deadline, then replays consumed bytes exactly once. Packet-specific
validation remains in the bounded shared codec. See
[MQTT 5 §§2.1.4, 3.1](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html)
and [MQTT 3.1.1 §3.1](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html).

WebSocket upgrades require the `mqtt` subprotocol and binary frames. Packet
boundaries may span WebSocket messages or share one message. Native negotiation
validates the upgrade, replays prefetched bytes, handles fragments/control frames
and rejects text or malformed frames. MQTT and WAMP subprotocol selection remain
separate, following [MQTT 5 §6](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).

Native code owns sockets, TLS, WebSocket framing, connection IDs, deadlines and
bounded byte queues. Dart owns MQTT decoding, CONNECT acceptance, keep-alive,
subscriptions and broker state. Incoming queues hold at most 64 chunks; outbound
queues cap at 512 chunks and 8 MiB per peer. Byte credit is released after write
or failure. Coalesced notifications wake Dart, with a 1 ms polling fallback.
Dart retries full-queue writes in FIFO order with a 4 MiB bound, closes persistently
slow peers, and releases peer/queue state on close and listener drain.

QoS 0 `publish`/`publishBatch` completion means local write acceptance. The
[Socket](https://api.dart.dev/dart-io/Socket-class.html) and
[IOSink.flush](https://api.dart.dev/dart-io/IOSink/flush.html) APIs do not establish
subscriber delivery; integration tests and benchmarks check every callback.
The client defaults to TCP_NODELAY on Linux, permits an override, and keeps the
macOS native default. Batches cap at 512 packets and 1 MiB encoded bytes.

The provisional MQTT 5 CONNACK advertises Maximum QoS 0, Retain Available 0,
Maximum Packet Size 1 MiB, and no subscription identifiers or shared subscriptions.
Valid SUBSCRIBE requests at QoS 0/1/2 may receive a QoS 0 grant; QoS 1/2 PUBLISH
remains unsupported. MQTT 3.1.1 lacks these capability properties and its current
profile is explicitly limited. See [MQTT 5 §§3.2.2.3, 3.8.4](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).

## Reversible topic names

`MqttTopicUriMapper` maps each slash-delimited MQTT level to a WAMP URI component
under `connectanum.mqtt.v1.topic`: `s` followed by lowercase hexadecimal UTF-8.
An empty level becomes `s`.

| MQTT topic | WAMP URI |
| --- | --- |
| `a/b` | `connectanum.mqtt.v1.topic.s61.s62` |
| `a//b/` | `connectanum.mqtt.v1.topic.s61.s.s62.s` |
| `é` | `connectanum.mqtt.v1.topic.sc3a9` |

This preserves case, Unicode bytes, empty levels, slashes, dots and `$` topics.
Validation rejects wildcards, NUL, malformed UTF-8, noncanonical hex, encoded
slashes within components and names beyond MQTT's 65,535-byte UTF-8 limit.
See [MQTT 5 §4.7](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html)
and the [WAMP strict URI recommendation](https://wamp-proto.org/wamp_latest_ietf.pdf).

## Gateway boundary to implement

Mapping names does not grant access. A gateway must authorize the MQTT principal
and realm, then apply the WAMP ACL to the canonical URI. WAMP-originated gateway
publishes must preserve caller identity and pass the same topic policy.
Direct WAMP PUBLISH into this namespace does not trigger MQTT delivery.
`ppt_scheme: mqtt` stays opaque; an explicit authorized API will enable bridging.

MQTT wildcard semantics, including `$` and parent matching by `a/#`, must remain
intact. MQTT owns packet IDs, QoS, retain, wills and session state; WAMP owns its
sessions/subscriptions. Application publications carry raw bytes, topic,
principal/realm, properties and origin metadata. The gateway prevents loops and
avoids topic mapping work when no bridge recipient exists.

## Verification and performance

[README tables](../packages/connectanum_bench/README.md) show direct MQTT and
four-serializer WAMP results. [Benchmark evidence](benchmarks/README.md) links the
100% scoped coverage proof, unchanged CI budgets, compact fixtures and complete
historical archive. Gateway benchmarks must cover both translation directions,
matched direct controls, exact delivery, latency, CPU, RSS and queue/drain behavior
before release acceptance.
