# MQTT wire and routing boundary

Date: 2026-10-14
Status: implementation research; the advertised profile is not yet shipped
Tracking: [MQTT milestone](https://github.com/konsultaner/connectanum-dart/milestone/2), [contract #110](https://github.com/konsultaner/connectanum-dart/issues/110), [codec #111](https://github.com/konsultaner/connectanum-dart/issues/111), [benchmarks #127](https://github.com/konsultaner/connectanum-dart/issues/127)

## Source-backed wire rules

- MQTT 5 and 3.1.1 control packets start with a packet type and flag nibble, followed by a Remaining Length variable-byte integer. The integer uses one to four bytes and has a maximum value of 268,435,455. MQTT 5 explicitly requires the shortest encoding; the shared decoder currently applies that strict rule to both versions. The configured packet cap applies to the whole packet, including the fixed header. See [MQTT 5 §1.5.5 and §2.1](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) and [MQTT 3.1.1 §2.2](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html).
- The PUBREL, SUBSCRIBE and UNSUBSCRIBE fixed-header flags are `0b0010`; the other non-PUBLISH packet flags are zero. PUBLISH encodes DUP, QoS and RETAIN in its low nibble; QoS `3` and DUP with QoS `0` are malformed. Validate these before exposing a frame to the packet parser. See [MQTT 5 §2.1.2 and §3.3.1](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).
- Frame extraction alone does not make a packet valid. The next codec layer must validate CONNECT-first sequencing, protocol name/version, packet-specific lengths, UTF-8, properties, packet IDs and capability limits before broker state changes. MQTT 3.1.1 packets have no MQTT 5 property-length fields. See the [MQTT 5 packet chapters](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) and [MQTT 3.1.1 packet chapters](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html).
- MQTT topic filters use `/`, `+`, `#` and special `$` matching rules. A dot substitution into WAMP URIs is not reversible; explicit topic mapping and ACL evaluation are required. See [MQTT 5 §4.7](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).

### Provisional MQTT 5 capability response

MQTT 5's absent CONNACK Maximum QoS property defaults to QoS 2; a server limited to QoS 0 **must** send property `0x24` with value `0`. Absent Retain Available defaults to supported, so the current no-retain listener sends `0x25` with value `0`. Its 1 MiB input-frame cap is advertised as Maximum Packet Size `0x27`. Subscription Identifiers and Shared Subscriptions default to supported if their availability properties are absent, so the listener sends `0x29=0` and `0x2a=0`. Wildcard subscriptions remain enabled by default. The fixed topic-alias default is zero. See [MQTT 5 §3.2.2.3.4–13](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).

Even when the server's Maximum QoS is zero, MQTT 5 requires it to accept SUBSCRIBE requests with requested QoS 0, 1 or 2. It may grant a lower maximum QoS in SUBACK, so the provisional broker grants QoS 0 for all valid filters. This is distinct from accepting QoS 1/2 PUBLISH packets, which remain unsupported. See [MQTT 5 §3.2.2.3.4](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) and [§3.8.4](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html). MQTT 3.1.1 has no corresponding CONNACK capability properties; its provisional listener profile remains explicitly limited until full QoS/session behavior is implemented.

## Boundary decisions

1. MQTT control packets stay in the MQTT adapter. The shared broker sees authorized application publications with raw payload bytes, topic, principal/realm, QoS, retain/properties and origin metadata; it does not see CONNECT, SUBSCRIBE or acknowledgement packets as WAMP events.
2. MQTT session state, packet IDs, QoS handshakes, retained publications, wills and persistence have one owner. The WAMP router continues to own WAMP sessions. The gateway checks both protocol ACLs and prevents publication loops.
3. WAMP `ppt_scheme: mqtt` is opaque payload metadata. The router must not execute a wrapped MQTT packet merely because that scheme is present. A separate authorized gateway API defines WAMP-to-MQTT publication.
4. Begin with a bounded shared packet codec and a live QoS 0 interoperability path that can be measured. A dedicated listener can serve as an early reference harness; milestone completion requires the negotiated native listener and MQTT-over-WebSocket binding. Decisions to move framing across FFI depend on measured live-path bottlenecks, including copy and queue costs.

## Performance evidence to collect early

The first live QoS 0 path needs a pinned Connectanum baseline and a matched local Mosquitto reference before tuning. Count successfully delivered publications and exact bytes, then report messages/s, payload MiB/s, p50/p95/p99 publish-to-delivery latency, CPU seconds per million deliveries, RSS, allocations/copies, queue depth and losses. Keep setup and steady-state windows separate. Extend the same scenarios over TCP/TLS, WebSocket, QoS 1/2, fan-out, mixed MQTT/WAMP and overload; check in numeric budgets and raw artifact provenance before claiming a performance result.

## Open implementation choices

- The [versioned reversible topic contract](../mqtt-topic-contract.md) fixes the mapping. Principal/realm policy and the MQTT 5 property profile still require gateway implementation and conformance evidence.
- Session storage format, recovery ordering and version-specific reason-code policy belong to #118–#123. No current codec work establishes those behaviors.
