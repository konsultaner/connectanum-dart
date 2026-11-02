# MQTT support and routing contract

Connectanum provides an opt-in QoS 0 MQTT broker and client for MQTT 5.0 and
3.1.1 over TCP, TLS, WebSocket and secure WebSocket. Native listeners negotiate
MQTT alongside HTTP and WAMP. Anonymous MQTT listening is restricted to numeric
loopback addresses. The gateway assigns a configured MQTT principal and applies
realm authorization; MQTT credential authentication remains pending.

| Capability | Current status |
| --- | --- |
| QoS 0 pub/sub, filters, bounded framing and queues | Implemented and independently tested |
| TCP/TLS/WS/WSS; Paho and Connectanum clients; Mosquitto control | Implemented and benchmarked |
| Reversible MQTT-topic/WAMP-URI names | Implemented |
| Explicit authorized MQTT↔WAMP gateway | Implemented; configure a realm, MQTT principal and service role |
| Translation performance/memory acceptance | Live runner implemented; hosted baseline and numeric budgets in progress (#131) |
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
or failure. On Linux, plain MQTT TCP/WS sockets request a 128 KiB
unsent-data watermark so stalled peers encounter backpressure earlier while TCP
send-buffer autotuning remains enabled. TLS socket buffering keeps its platform defaults.
See the [Linux socket guidance](https://kernel.org/doc/html/latest/networking/ip-sysctl.html#tcp-notsent-lowat). Coalesced notifications wake Dart, with a 1 ms polling fallback.
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

For gateways with large WAMP messages, set the endpoint's
`outboundSendQueueCapacity: 64` to bound each native outbound queue to 64 frames.
The gateway benchmark uses that setting for translations and matched controls.
A full queue closes the slow connection; healthy recipients continue. Native
WAMP clients credit one receive batch at a time across isolates. Queue capacity
is a frame count, so size it together with the maximum permitted message size.

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

## Enable the gateway

Import `package:connectanum_router/mqtt.dart` and enable a gateway on a native
router binding. Configure both roles in the realm before calling this API:

```dart
final gateway = await binding.enableMqttGateway(
  realmUri: 'example',
  mqttAuthRole: 'mqtt',
  mqttAuthId: 'mqtt:anonymous',
  serviceAuthRole: 'mqtt-gateway',
);
```

| Role | Required permissions |
| --- | --- |
| MQTT principal (`mqtt`) | `publish`/`subscribe` on allowed mapped topic URIs |
| WAMP caller | `call` on `connectanum.mqtt.v1.publish` and `publish` on the requested mapped URI |
| Gateway service (`mqtt-gateway`) | `register`/`unregister` on `connectanum.mqtt.v1.publish`; `publish` on allowed mapped URIs |

Use exact, prefix or wildcard realm permissions, or a configured authorization
provider. An implicit allow-all realm is rejected. For multiple realms, assign
each MQTT listener explicitly with `options: {'realm': 'example'}`. Connections
and subscriptions remain isolated by that assignment. MQTT client IDs are
untrusted connection hints; they never select a role or authenticate a principal.

An authorized MQTT publication becomes a WAMP event on
`MqttTopicUriMapper.toWampUri(topic)`, with one binary argument. Event details
include `mqtt_topic`, `mqtt_origin`, `mqtt_gateway`, and the originating client
ID or verified WAMP caller ID. MQTT authorization completes before either MQTT
or WAMP delivery. Wildcard MQTT subscriptions also require permission on each
concrete delivered topic.

WAMP clients publish explicitly through the gateway:

```dart
await session.call(
  'connectanum.mqtt.v1.publish',
  arguments: ['sensors/temperature', Uint8List.fromList([0, 255, 17])],
).first;
```

The router resolves the original caller from trusted invocation/session state,
checks that caller's publication permission, and rejects malformed topics,
nonbinary payloads, keyword arguments and PPT on this API. Ordinary WAMP
publications in the mapped namespace cause no MQTT delivery. `ppt_scheme: mqtt`
remains opaque. The gateway never subscribes to its output, so forwarding does
not create a feedback loop.

The RPC result contains the WAMP publication ID. QoS 0 does not acknowledge
subscriber delivery, provide atomic delivery across protocols, or persist data
for offline subscribers. MQTT packet IDs/session state and WAMP sessions remain
owned by their respective protocols.

| Gateway bound | Default |
| --- | ---: |
| Pending API payload bytes / operations per realm | 8 MiB / 256 |
| Queued policy work per MQTT peer | 4 MiB / 256 tasks |
| Queued MQTT policy bytes across the broker | 16 MiB |
| Policy/state operation deadline | 5 s |
| MQTT publication packet size | 1 MiB |
| Cached topic mappings | 256 entries / 1 MiB |

Overflow closes the affected MQTT peer or rejects the API call. A policy timeout
closes gateway admission. Unresolved custom provider futures retain capacity
until they settle, including across gateway replacement. `gateway.metrics`
reports queue bytes/depth, policy futures, cache size, deliveries and errors.
`await gateway.close()` cancels pending work and disconnects its MQTT realm;
the realm stays deny-only until a replacement gateway is explicitly installed.

## Verification and performance

[README tables](../packages/connectanum_bench/README.md) show direct MQTT and
four-serializer WAMP results. [Benchmark evidence](benchmarks/README.md) links the
100% scoped coverage proof, unchanged CI budgets, compact fixtures and complete
historical archive. `tool/run_mqtt_gateway_benchmark.py` runs separate AOT broker,
publisher and subscriber processes for both translations, direct MQTT/WAMP
controls and a Mosquitto MQTT-leg control. It validates every payload and records
throughput, p50/p95/p99, CPU, each process's warm/peak/drained RSS and lifecycle
queue recovery. The [gateway tables](../packages/connectanum_bench/README.md#mqtt-and-wamp-gateway)
contain all 128 measured translation cases across x64 and ARM64, per-process
memory, direct controls and eight slow-consumer cases. Numeric gateway checks
require the recorded ARM64 architecture, CPU count and CPU signature before load.
Required CI smoke and sixteen profile shards enforce
exact delivery, complete coverage, latency/rate/CPU/RSS budgets and recovery.
Raw runs and rejected baselines are retained in the [verified history archive](https://github.com/konsultaner/connectanum-dart/releases/tag/benchmark-history-mqtt-gateway-2026-11-01).

`--retention` adds a separate Linux AOT retention stress matrix for diagnostic
runs. Strict budgets declare `retention_protocol: bounded_nursery_v1`. Default
runtime throughput, CPU and raw peak/drained RSS keep the accepted warm-up and
all frozen limits. The separate stress processes use an 8 MiB nursery semispace,
old-generation collection and unused allocator-cache release before/after load.
They cover normal traffic and stalled-consumer recovery. Raw RSS drift remains
available separately; stress timings are not performance results.

The internal test executable requires Dart 3.13.1 stable and qualified glibc
Linux. Dart's [verification API](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/include/dart_native_api.h)
restricts `gc-now` to tests. Its [implementation](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/vm/native_api_impl.cc)
collects the old generation; the SDK's [nursery metric](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/vm/metrics.cc)
reports capacity rather than live bytes, so the separate test bounds that
capacity instead of treating it as a leak. [GNU malloc trimming](https://sourceware.org/git/?p=glibc.git;a=blob;f=malloc/malloc.c)
releases unused native allocator pages without changing live allocations.
Startup verifies rooted and released 32 MiB managed/native controls. Every
collection checks a weak witness and the nursery bound. Missing samples,
unsupported hosts, failed controls or collection errors stop the run. SDK
collection hooks and nursery flags are restricted to the retention test worker.

The normal glibc Linux runtime checks for an empty connection registry 100 ms
after close and releases unused native allocator pages. Requests coalesce and
release runs at most once every two seconds, with no registry/limiter lock held.
Live buffers retain their owners; Dart VM settings stay at their defaults.

Manual gateway campaigns use unique [concurrency groups](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency), so a newer dispatch cannot replace queued or running benchmark evidence.

Large ordinary binary worker events use exact-size scratch buffers, capped at
four buffers and 1 MiB per worker. Oversized frames are not cached. The worker
finishes the synchronous `SendPort.send` call before reusing a buffer; Dart
[documents that mutable messages are copied during that call](https://api.dart.dev/dart-isolate/SendPort/send.html).
Real-isolate regressions overwrite inputs and reuse or evict buffers before
receiving the messages, checking every frame against the ordinary codec bytes.
