# Native router MQTT QoS 0 benchmark checkpoint

Date: 2026-10-14. Status: local diagnostic; clean-tree and hosted evidence pending.

The benchmark runs a Dart AOT router process on the native `ct_ffi` MQTT TCP listener and a separate Dart AOT client process. Five order-balanced Connectanum/Mosquitto pairs use the same ports, client executable and 128-byte payload. Every run checks exact payload bytes, order, per-subscriber counts and zero duplicates before considering speed. The reported throughput is delivered messages per second; p95/p99 measure client publish-to-delivery latency. Broker process CPU time and high-water RSS are measured separately. The native library and both AOT binaries are hashed in each summary. Run with `--native-router` and `CONNECTANUM_NATIVE_LIB`; the existing Dart-only broker gate remains independent.

The first native implementation used 1 ms periodic polling and failed the sustained MQTT 5 budget at 0.441 throughput ratio and 2.487 p95 ratio despite 0.756 broker CPU ratio. A continuously spinning poll reached 0.924 throughput ratio but used 3.452 times Mosquitto's broker CPU. The implemented native read notification wakes Dart only when its bounded read queue has new work and coalesces notifications until Dart drains it. This is the measured reason for using event-driven wakeups rather than a tighter timer.

| Dirty-tree local Apple M3 Ultra diagnostic | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | CPU ratio | Connectanum RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 sequential, 200,000/run, window 512 | 401,914 | 433,318 | 0.928 | 1.093 | 1.065 | 2.125 | 46.0 MB |
| MQTT 3.1.1 sequential, 200,000/run, window 512 | 387,054 | 404,777 | 0.956 | 1.069 | 1.160 | 2.023 | 42.3 MB |
| MQTT 5 batch, 200,000/run, window 512 | 785,870 | 412,737 | 1.904 | 0.578 | 0.609 | 0.341 | 32.2 MB |
| MQTT 5 fan-out, 50,000 publications/200,000 deliveries per run | 1,261,551 | 582,759 | 2.165 | 0.514 | 0.522 | 0.290 | 31.2 MB |

The sequential native CPU limit is provisionally 2.5× Mosquitto because the local FFI path consumes about 2.1× CPU while meeting the 0.75 throughput floor and 2.0/2.25 p95/p99 bounds. The batch and fan-out profiles retain their existing stricter budgets. All five profiles, including a 2,000-message correctness burst, are wired to the hosted MQTT lane with exact Python benchmark-runner executable-line coverage. These local numbers are diagnostic because the source tree was dirty; they are not release evidence or a cross-machine speedup claim. The controlled release runner, TLS/WebSocket, mixed WAMP traffic, overload and longer CPU/RSS samples remain open.
