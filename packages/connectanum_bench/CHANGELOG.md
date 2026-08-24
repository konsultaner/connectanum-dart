# Changelog

## 3.0.0-beta.2

- Keep the benchmark tooling synchronized with the corrected hosted native
  package installation release.

## 3.0.0-beta.1

- Add strict production gates for 30 file-transfer, 24 large-frame, and 24
  WebSocket fragmentation profiles, including lifecycle throughput and
  zero-copy evidence.
- Exercise native and Dart transports in isolated workers with bounded
  cancellation, timeout, process-memory, and artifact accounting.

## 3.0.0-beta

- Release consumed native RPC and pub/sub payload buffers deterministically,
  preserving benchmark semantics while bounding repeated giant-frame RSS.
- Join the synchronized Connectanum 3.0 beta package graph.
- Add production gates for canonical WAMP profiles, progressive invocations,
  call timeouts, statistics Meta APIs, payload E2EE, and router-hosted MCP.

## 0.1.0

- Initial modular release of the Connectanum benchmark package, including the
  router benchmark CLI, WAMP workload runner, native worker helpers, HTTP auth
  harnesses, and smoke/throughput scenario support.
