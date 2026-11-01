# Validated MQTT same-version forwarding

The broker decodes every incoming PUBLISH, rejects unsupported QoS/properties,
invalid UTF-8/topics and retained messages, then selects subscribed peers.
Previously it re-encoded the already validated topic for every publication.
The private same-version path now uses `MqttFrame.encode()` to create a fresh
owned packet from that validated body. It requires zero flags and retains the
standard 1 MiB wire cap. Other versions/flags use the existing generic encoder.
Per-version fanout memoization, outbound queues, backpressure and body copies
remain the same. The raw frame never escapes the synchronous validated handler.

The public codec prototype matches complete encoded bytes in 110 cases with
fresh output ownership. Focused broker tests cover same- and cross-version
packets, fragmented headers, caller-buffer mutation, multilingual topics,
64 KiB bodies and exact 1 MiB packets. Invalid UTF-8 (including overlong and
surrogate encodings), NUL, wildcards, DUP, retain and unsupported properties
must close the offending publisher before delivery.

The predeclared actual-public-broker component retains 32 rows / 3.2 million
freshly generated and fully verified publications. All eight pairs per version
improve elapsed time: median after/before 0.92247 for MQTT 5 and 0.91779 for 3.1.1.
The separate matched TCP/WS comparison retains all 30 rows / six million
verified deliveries with the original 200,000-message, 128-byte, window-512
workloads, five pairs, alternating order and unchanged compiled client/native
library. TCP 3.1.1 median throughput improves 1.05102x and broker CPU falls from
0.65 to 0.63 seconds. WebSocket median-rate ratios are 0.99902 / 0.98916 with
mixed paired results: this does **not** establish a WebSocket repair.

These are local Darwin diagnostic comparisons. They do not establish Linux
MQTT gates, RSS parity or complete FlatBuffers acceptance. Standard SDK,
allocator/GC policy, whole-body verification and ownership boundaries remain
unchanged. The candidate requires its own canonical verification and clean CI;
any final runtime also requires complete strict 48-/50-case acceptance.

[Retained comparison digests and every paired result](2026-11-01-mqtt-validated-forwarding-audit.json).
