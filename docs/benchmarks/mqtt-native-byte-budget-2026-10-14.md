# Native MQTT writer byte-budget checkpoint

Date: 2026-10-14. Source: `8adecfdb` on an Apple M3 Ultra. The source tree was clean when measured. This local comparison is not a cross-machine release claim.

Two hosted Linux runs with the original 64-slot native writer and Dart-side bounded retry delivered every MQTT 5 QoS 0 message but missed the unchanged throughput floor: ratios 0.732 and 0.693 against Mosquitto, with Connectanum consistently near 60,000 delivered/s. A previous candidate without retry had runs near 87,000/s but eventually disconnected. The [earlier checkpoint](mqtt-native-backpressure-2026-10-14.md) retains those links and its local raw samples.

The native writer now allows up to 512 queued chunks while an 8 MiB per-connection semaphore limits total queued and in-flight encoded bytes. Each queued chunk owns a byte permit until its socket write completes or fails. The Dart peer still keeps a separate 4 MiB bounded retry buffer for transient queue-full conditions. Three Rust tests cover the 512-slot window, byte exhaustion, and credit release on drain/closed channel. Paho 2.1.0 and Connectanum MQTT 5/3.1.1 TCP/TLS binary exchange passes with this native library.

Six process-isolated native-router profiles use the same AOT Connectanum benchmark client against Connectanum and Mosquitto. Each profile has five order-balanced pairs and validates exact payload bytes, order, counts and zero duplicates before applying its existing throughput, p95/p99, broker CPU and RSS limits. Sustained profiles publish 200,000 128-byte messages per run with a 512-message window; fan-out has four subscribers. TLS peers verify the checked-in test CA. All 60 raw broker/client rows are exact with zero duplicates, and summaries retain Git/native/AOT hashes and `git_dirty: false`.

| Profile | Connectanum delivered/s | Mosquitto delivered/s | Throughput ratio | p95 ratio | p99 ratio | CPU ratio | Peak Connectanum RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MQTT 5 TCP sustained | 400,612 | 408,483 | 0.981 | 1.033 | 1.039 | 2.000 | 40.9 MiB |
| MQTT 3.1.1 TCP sustained | 394,618 | 402,539 | 0.980 | 1.039 | 1.042 | 2.000 | 40.0 MiB |
| MQTT 5 TCP batch | 776,735 | 415,150 | 1.871 | 0.578 | 0.577 | 0.341 | 30.4 MiB |
| MQTT 5 TCP fan-out ×4 | 1,297,522 | 595,417 | 2.179 | 0.499 | 0.513 | 0.267 | 35.2 MiB |
| MQTT 5 TLS sustained | 388,475 | 74,648 | 5.204 | 0.123 | 0.112 | 0.800 | 31.3 MiB |
| MQTT 3.1.1 TLS sustained | 396,525 | 75,819 | 5.230 | 0.123 | 0.109 | 0.754 | 31.5 MiB |

Every profile passes its unchanged checked-in numeric budget locally. Hosted Linux evidence for this queue change is pending, as are controlled release measurements and the remaining MQTT transport and protocol profiles.

| Profile | Summary | Raw matched rows |
| --- | --- | --- |
| MQTT 5 TCP sustained | [summary](mqtt-native-budget-8adecfdb-native5-summary.json) | [raw](mqtt-native-budget-8adecfdb-native5-raw.jsonl) |
| MQTT 3.1.1 TCP sustained | [summary](mqtt-native-budget-8adecfdb-native311-summary.json) | [raw](mqtt-native-budget-8adecfdb-native311-raw.jsonl) |
| MQTT 5 TCP batch | [summary](mqtt-native-budget-8adecfdb-batch-summary.json) | [raw](mqtt-native-budget-8adecfdb-batch-raw.jsonl) |
| MQTT 5 TCP fan-out ×4 | [summary](mqtt-native-budget-8adecfdb-fanout-summary.json) | [raw](mqtt-native-budget-8adecfdb-fanout-raw.jsonl) |
| MQTT 5 TLS sustained | [summary](mqtt-native-budget-8adecfdb-tls5-summary.json) | [raw](mqtt-native-budget-8adecfdb-tls5-raw.jsonl) |
| MQTT 3.1.1 TLS sustained | [summary](mqtt-native-budget-8adecfdb-tls311-summary.json) | [raw](mqtt-native-budget-8adecfdb-tls311-raw.jsonl) |
