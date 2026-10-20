# Bench Artifact Gate

Summary: `/home/runner/work/connectanum-dart/connectanum-dart/out/wamp-profile-diagnostics/wamp_websocket_fragmentation_throughput/bench_results.summary.json`
Source results: `/home/runner/work/connectanum-dart/connectanum-dart/out/wamp-profile-diagnostics/wamp_websocket_fragmentation_throughput/bench_results.jsonl`
Workloads checked: 24

Gate failed. The transformed bench artifacts captured transport or performance regressions.

## Performance Findings

| Severity | Scenario | Workload | Protocol | Client | Router workers | Native runtime threads | Kind | Observed | Threshold | Rule |
| --- | --- | --- | --- | --- | ---: | ---: | --- | ---: | ---: | --- |
| warning | wamp_websocket_fragmentation_throughput | websocket_pubsub_json_4m_native_fragmented_4k | wamp_websocket_pubsub | native | 1 | 1 | lifecycle_throughput_mbps_min | 1978.336 | 2000.000 | min |
| warning | wamp_websocket_fragmentation_throughput | websocket_tls_pubsub_json_4m_native_contiguous | wamp_websocket_pubsub | native | 1 | 1 | throughput_mbps_min | 1887.182 | 2000.000 | min |
| warning | wamp_websocket_fragmentation_throughput | websocket_tls_pubsub_json_4m_native_contiguous | wamp_websocket_pubsub | native | 1 | 1 | lifecycle_throughput_mbps_min | 1763.123 | 2000.000 | min |
| warning | wamp_websocket_fragmentation_throughput | websocket_tls_pubsub_json_4m_native_fragmented_4k | wamp_websocket_pubsub | native | 1 | 1 | lifecycle_throughput_mbps_min | 1919.110 | 2000.000 | min |
| warning | wamp_websocket_fragmentation_throughput | websocket_tls_pubsub_cbor_4m_native_contiguous | wamp_websocket_pubsub | native | 1 | 1 | throughput_mbps_min | 1999.049 | 2000.000 | min |
| warning | wamp_websocket_fragmentation_throughput | websocket_tls_pubsub_cbor_4m_native_contiguous | wamp_websocket_pubsub | native | 1 | 1 | lifecycle_throughput_mbps_min | 1820.673 | 2000.000 | min |
| warning | wamp_websocket_fragmentation_throughput | websocket_tls_pubsub_cbor_4m_native_fragmented_4k | wamp_websocket_pubsub | native | 1 | 1 | throughput_mbps_min | 1776.978 | 2000.000 | min |
| warning | wamp_websocket_fragmentation_throughput | websocket_tls_pubsub_cbor_4m_native_fragmented_4k | wamp_websocket_pubsub | native | 1 | 1 | lifecycle_throughput_mbps_min | 1650.007 | 2000.000 | min |
