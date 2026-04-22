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

Secure WAMP scenarios are selected explicitly with `secure_transport = true`
in the workload definition; the Dart bench runner keeps separate cleartext and
TLS listener targets so secure workloads do not silently fall back to the
cleartext WAMP listener.

When the shipped bench router config includes `oauth` HTTP auth providers, the
Dart runner also starts a local introspection endpoint for them. That keeps the
HTTP bearer-provider scenarios self-contained instead of depending on an
external OAuth service during local or CI bench runs.

The shipped HTTP auth bridge smoke scenario now also covers challenge-response
login for `ticket`, `wampcra`, and `scram`, so the Rust orchestrator exercises
both multi-step HTTP auth bridge flows and the separate bearer-provider route
path from the same checked-in bench config.

## Related Docs

- orchestrator overview: [../../native/bench/README.md](../../native/bench/README.md)
- repo overview: [../../README.md](../../README.md)
