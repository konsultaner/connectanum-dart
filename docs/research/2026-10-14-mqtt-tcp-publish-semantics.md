# MQTT QoS 0 TCP publication timing

Status: implementation evidence for the provisional TCP QoS 0 profile, 2026-10-14.

The [Dart `Socket` API](https://api.dart.dev/dart-io/Socket-class.html) states that writes may be delayed unless `SocketOption.tcpNoDelay` is set. [`IOSink.flush`](https://api.dart.dev/dart-io/IOSink/flush.html) waits until buffered data is accepted by the underlying consumer; it does not guarantee an operating-system flush or peer delivery. QoS 0 has no application acknowledgment, so Connectanum's `publish` future has only local write acceptance semantics.

The first hosted Linux AOT sustained run at `b8bc66e7` delivered all messages but measured 28,893 Connectanum versus 107,651 Mosquitto delivered/s, with recurring 40–80 ms tail stalls. Broker-side TCP_NODELAY plus microtask coalescing restored about 400,000 delivered/s on local macOS without reducing its throughput. The next [hosted Linux run](https://github.com/konsultaner/connectanum-dart/actions/runs/38562503210/job/115847851646) at `81fb08a4` still measured 31,673 versus 76,008 delivered/s and about 40 ms p95, so the remaining delay is on the client publication path. Both attempts had exact ordered delivery. The numeric budget has not been reduced.

The public client now uses TCP_NODELAY to keep sequential QoS 0 writes responsive. It also offers `publishBatch`, limited to 512 packets and 1 MiB of encoded wire bytes, so sustained users can write many packets together and flush once. The benchmark keeps its original sequential single-publish profile and adds a separately named 512-message batch profile against both brokers. This preserves the earlier baseline and makes the offered-load difference explicit. An `await publish` or `await publishBatch` still does not prove remote delivery; the benchmark waits for and validates every subscriber callback separately.

Local macOS AOT candidate runs pass both profiles with complete payload/order checks: sequential 208,660 versus 195,103 delivered/s; batch 814,077 versus 411,518. These runs occurred during broader local verification and have dirty-tree provenance, so hosted clean-head evidence is required before accepting the change.
