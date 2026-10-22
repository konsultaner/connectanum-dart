# Bench Artifact Gate

Summary: `/home/runner/work/connectanum-dart/connectanum-dart/out/wamp-profile-diagnostics/wamp_file_transfer_throughput/bench_results.summary.json`
Source results: `/home/runner/work/connectanum-dart/connectanum-dart/out/wamp-profile-diagnostics/wamp_file_transfer_throughput/bench_results.jsonl`
Workloads checked: 38

Gate failed. The transformed bench artifacts captured transport or performance regressions.

## Performance Findings

| Severity | Scenario | Workload | Protocol | Client | Router workers | Native runtime threads | Kind | Observed | Threshold | Rule |
| --- | --- | --- | --- | --- | ---: | ---: | --- | ---: | ---: | --- |
| warning | wamp_file_transfer_throughput | rawsocket_file_json_64m_dart_buffered | wamp_rawsocket_file_transfer | dart | 1 | 1 | lifecycle_throughput_mbps_min | 1955.814 | 2000.000 | min |
| warning | wamp_file_transfer_throughput | websocket_file_json_64m_dart_buffered | wamp_websocket_file_transfer | dart | 1 | 1 | throughput_mbps_min | 1141.258 | 2000.000 | min |
| warning | wamp_file_transfer_throughput | websocket_file_json_64m_dart_buffered | wamp_websocket_file_transfer | dart | 1 | 1 | lifecycle_throughput_mbps_min | 1096.214 | 2000.000 | min |
