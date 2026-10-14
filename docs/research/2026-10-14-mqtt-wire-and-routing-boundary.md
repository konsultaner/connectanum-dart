# MQTT wire and routing boundary

Date: 2026-10-14
Status: implementation research; the advertised profile is not yet shipped
Tracking: [MQTT milestone](https://github.com/konsultaner/connectanum-dart/milestone/2), [contract #110](https://github.com/konsultaner/connectanum-dart/issues/110), [codec #111](https://github.com/konsultaner/connectanum-dart/issues/111), [benchmarks #127](https://github.com/konsultaner/connectanum-dart/issues/127)

## Source-backed wire rules

- MQTT 5 and 3.1.1 control packets start with a packet type and flag nibble, followed by a Remaining Length variable-byte integer. The integer uses one to four bytes and has a maximum value of 268,435,455. MQTT 5 explicitly requires the shortest encoding; the shared decoder currently applies that strict rule to both versions. The configured packet cap applies to the whole packet, including the fixed header. See [MQTT 5 §1.5.5 and §2.1](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) and [MQTT 3.1.1 §2.2](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html).
- The PUBREL, SUBSCRIBE and UNSUBSCRIBE fixed-header flags are `0b0010`; the other non-PUBLISH packet flags are zero. PUBLISH encodes DUP, QoS and RETAIN in its low nibble; QoS `3` and DUP with QoS `0` are malformed. Validate these before exposing a frame to the packet parser. See [MQTT 5 §2.1.2 and §3.3.1](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).
- Frame extraction alone does not make a packet valid. The next codec layer must validate CONNECT-first sequencing, protocol name/version, packet-specific lengths, UTF-8, properties, packet IDs and capability limits before broker state changes. MQTT 3.1.1 packets have no MQTT 5 property-length fields. See the [MQTT 5 packet chapters](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) and [MQTT 3.1.1 packet chapters](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html).
- MQTT topic filters use `/`, `+`, `#` and special `$` matching rules. A dot substitution into WAMP URIs is not reversible; explicit topic mapping and ACL evaluation are required. See [MQTT 5 §4.7](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).

## Boundary decisions

1. MQTT control packets stay in the MQTT adapter. The shared broker sees authorized application publications with raw payload bytes, topic, principal/realm, QoS, retain/properties and origin metadata; it does not see CONNECT, SUBSCRIBE or acknowledgement packets as WAMP events.
2. MQTT session state, packet IDs, QoS handshakes, retained publications, wills and persistence have one owner. The WAMP router continues to own WAMP sessions. The gateway checks both protocol ACLs and prevents publication loops.
3. WAMP `ppt_scheme: mqtt` is opaque payload metadata. The router must not execute a wrapped MQTT packet merely because that scheme is present. A separate authorized gateway API defines WAMP-to-MQTT publication.
4. Begin with a bounded shared packet codec and a live QoS 0 interoperability path that can be measured. A dedicated listener can serve as an early reference harness; milestone completion requires the negotiated native listener and MQTT-over-WebSocket binding. Decisions to move framing across FFI depend on measured live-path bottlenecks, including copy and queue costs.

## Performance evidence to collect early

The first live QoS 0 path needs a pinned Connectanum baseline and a matched local Mosquitto reference before tuning. Count successfully delivered publications and exact bytes, then report messages/s, payload MiB/s, p50/p95/p99 publish-to-delivery latency, CPU seconds per million deliveries, RSS, allocations/copies, queue depth and losses. Keep setup and steady-state windows separate. Extend the same scenarios over TCP/TLS, WebSocket, QoS 1/2, fan-out, mixed MQTT/WAMP and overload; check in numeric budgets and raw artifact provenance before claiming a performance result.

## Open implementation choices

- Exact reversible topic mapping, principal/realm policy and MQTT 5 property profile belong to the checked-in contract for #110 before gateway implementation.
- Session storage format, recovery ordering and version-specific reason-code policy belong to #118–#123. No current codec work establishes those behaviors.
