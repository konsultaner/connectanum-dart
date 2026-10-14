# MQTT ↔ WAMP topic contract

Status: name mapping implemented; gateway routing and authorization pending.
Tracking: [MQTT milestone 2](https://github.com/konsultaner/connectanum-dart/milestone/2), [contract #110](https://github.com/konsultaner/connectanum-dart/issues/110).

## Reversible names

`MqttTopicUriMapper` maps an MQTT Topic Name to a strict WAMP URI under the versioned `connectanum.mqtt.v1.topic` namespace. Each slash-delimited MQTT level becomes one URI component: `s` followed by lowercase hexadecimal UTF-8 bytes. An empty level is `s`.

| MQTT topic | WAMP URI |
| --- | --- |
| `a/b` | `connectanum.mqtt.v1.topic.s61.s62` |
| `a//b/` | `connectanum.mqtt.v1.topic.s61.s.s62.s` |
| `é` | `connectanum.mqtt.v1.topic.sc3a9` |

The mapping preserves case, Unicode bytes, empty levels, slashes, dots and `$` topics without collision. It rejects wildcard characters, NUL, malformed UTF-8, noncanonical hex and names over MQTT's 65,535-byte UTF-8 limit. Encoded slash bytes within a component are rejected so one MQTT topic has one URI. The output uses only lowercase letters, digits and dots, consistent with the [WAMP strict URI recommendation](https://wamp-proto.org/wamp_latest_ietf.pdf); topic validation follows [OASIS MQTT 5 §4.7](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html).

## Routing boundary to implement

- Name mapping never grants publish or subscribe rights. The gateway must authorize the MQTT principal and realm before mapping an incoming publication, and the resulting WAMP publication must pass the realm's ACL on the canonical mapped URI. WAMP-originated gateway publishes must pass the same topic policy and preserve the caller identity.
- Direct WAMP `PUBLISH` into the mapped namespace must not trigger MQTT delivery. WAMP-to-MQTT delivery requires an explicit authorized gateway API. `ppt_scheme: mqtt` remains opaque WAMP payload metadata and does not execute an embedded MQTT packet.
- MQTT wildcard filters retain MQTT matching semantics. Do not translate `+` or `#` mechanically into WAMP prefix/wildcard subscriptions; `$` topic rules and `a/#` matching the parent topic must remain correct.
- The shared MQTT state owner handles retain, QoS, wills and sessions. The WAMP router handles WAMP subscriptions. The gateway carries origin metadata and prevents loops when a publication crosses either direction.
- Hot-path topic URI generation should be cached or skipped when no WAMP bridge recipient exists. The MQTT-only broker benchmark must continue to measure the unbridged path separately from a mixed MQTT/WAMP benchmark.
