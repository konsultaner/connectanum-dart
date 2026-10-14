# MQTT native listener boundary

Date: 2026-10-14
Status: opt-in MQTT 5/3.1.1 TCP negotiation and bounded FFI byte dispatch implemented for [#112](https://github.com/konsultaner/connectanum-dart/issues/112); TLS, WebSocket and WAMP routing remain open

## Wire contract

The native listener must identify MQTT from a bounded CONNECT preamble, not from byte `0x10` alone. CONNECT has fixed-header byte `0x10`, a one-to-four-byte Remaining Length, a two-byte protocol-name length, the four bytes `MQTT`, and protocol level `5` or `4` for the advertised MQTT 5.0 and 3.1.1 profiles. It must reject non-minimal or overflowing Remaining Length encodings, a length too short for the version's variable header, a wrong protocol name, and a truncated preamble within one listener handshake deadline shared by the initial protocol peek and the MQTT preamble read. Every byte read for classification must be replayed exactly once to the MQTT packet decoder. Packet and CONNECT-field validation remains with the bounded shared MQTT codec. See [MQTT 5 §2.1.4 and §3.1](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html) and [MQTT 3.1.1 §3.1](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html).

For MQTT over WebSocket, the client must offer and the server must select `mqtt`. MQTT data uses binary frames. WebSocket frame boundaries do not imply MQTT packet boundaries: one frame may contain part of a packet or multiple packets. Text data frames must close the connection. These are [MQTT 5 §6 requirements](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html). WAMP WebSocket subprotocol selection stays separate.

## Ownership and dispatch

The native listener owns accepted TCP/TLS streams, WebSocket framing, handshake deadlines, connection IDs, drain and bounded inbound/outbound byte queues. It reports an MQTT connection and byte chunks through dedicated FFI operations. The Dart MQTT adapter owns CONNECT acceptance, authentication, keep-alive, subscriptions, packet IDs, QoS state and broker publications. It feeds native chunks into the existing bounded `MqttFrameDecoder` and writes encoded MQTT bytes through the native queue. No MQTT packet is converted to a WAMP frame during transport negotiation.

The first end-to-end slice is opt-in MQTT 5/3.1.1 TCP on a mixed native listener, with exact preamble replay and a Paho/Connectanum exchange. The next slice adds TLS and `mqtt` WebSocket upgrades using the same Dart session owner. Disabled MQTT listeners reject MQTT preambles without changing HTTP, RawSocket or WAMP WebSocket handling. Native close and listener drain must release both queue ends and the Dart peer state.

The implemented TCP slice uses 64 bounded inbound read chunks per connection and caps the configured outbound queue at 64 chunks for MQTT. A native read notification wakes the Dart router loop and is coalesced until Dart drains the queue; unregistering or closing a connection waits for any in-flight native callback before Dart releases it. The 1 ms periodic poll remains a fallback. A mixed MQTT/HTTP listener, CONNECT byte replay, real Paho and Connectanum pub/sub, and the callback path have focused integration tests. The listener accepts anonymous MQTT only on numeric loopback until authentication and authorization are implemented.

## Performance and regression gates

Keep the current AOT process-isolated MQTT 5 and 3.1.1 QoS 0 sequential, bounded-batch and four-subscriber fan-out profiles as the unbridged baseline. Add a matched native-listener profile before retiring the provisional loopback listener. Require exact bytes, order, counts and duplicate checks, then throughput, p95/p99 publish-to-delivery latency, broker CPU and RSS budgets against Mosquitto on the same host. Preserve raw rows and source provenance. Include TLS, WebSocket, mixed WAMP traffic, backpressure and overload profiles before the release gate. The FFI handoff must be measured; a new queue or copy is not presumed faster.
