# connectanum_bench

`connectanum_bench` contains the Dart-side benchmark harness for the
Connectanum router.

It is used together with the Rust orchestrator under
[`native/bench`](../../native/bench/README.md) to run:

- HTTP/1.1, HTTP/2, and HTTP/3 workloads
- RawSocket and WebSocket WAMP workloads
- auth, authz, and transport comparison scenarios
- router metrics capture through the bench control endpoints

This package is an internal workspace tool, not an end-user runtime package.

## Main Entry Point

The Dart bench runner lives at:

```bash
dart run packages/connectanum_bench/tool/bench_main.dart
```

In practice it is usually started by the Rust orchestrator and scenario files
under `native/bench/scenarios/`.

## Related Docs

- orchestrator overview: [../../native/bench/README.md](../../native/bench/README.md)
- repo overview: [../../README.md](../../README.md)
