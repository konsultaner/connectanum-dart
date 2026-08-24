<div align="center">

# Connectanum

**A high-performance WAMP v2 stack for Dart and Flutter.**

Build real-time applications with routed RPC and Pub/Sub, run an embeddable or
standalone router, and expose WAMP services to AI agents through MCP.

[![CI](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart.yml)
[![Coverage](https://codecov.io/gh/konsultaner/connectanum-dart/branch/master/graph/badge.svg)](https://app.codecov.io/gh/konsultaner/connectanum-dart)
[![WAMP Profile Benchmarks](https://github.com/konsultaner/connectanum-dart/actions/workflows/wamp-profile-benchmarks.yml/badge.svg?branch=master)](https://github.com/konsultaner/connectanum-dart/actions/workflows/wamp-profile-benchmarks.yml)
[![Package Dry Run](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart-package-publish.yml/badge.svg?branch=master)](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart-package-publish.yml)
[![Version](https://img.shields.io/badge/version-3.0.0--beta.2-f59e0b)](https://github.com/konsultaner/connectanum-dart)
[![Dart](https://img.shields.io/badge/Dart-%5E3.9.2-0175c2?logo=dart&logoColor=white)](https://dart.dev/)
[![WAMP](https://img.shields.io/badge/WAMP-v2-4b32c3)](https://wamp-proto.org/)
[![License](https://img.shields.io/badge/license-MIT-0f766e)](LICENSE)

[Getting started](docs/getting_started.md) · [Quick start](#quick-start) ·
[Documentation](docs/README.md) ·
[Examples](docs/examples.md) · [Feature matrix](docs/wamp_profile_support.md) ·
[Benchmarks](docs/wamp_profile_benchmarks.md)

</div>

> **3.0 beta:** all Connectanum Dart packages and native Rust crates move
> together at `3.0.0-beta.2`. The beta is intended for integration testing before
> the final `3.0.0` release.

## Why Connectanum?

| | |
| --- | --- |
| **One protocol, every role** | Publisher, Subscriber, Caller, Callee, Broker, and Dealer with the WAMP Basic Profile across WebSocket and RawSocket. |
| **Advanced RPC and Pub/Sub** | Progressive results and invocations, call timeouts and cancellation, pattern routing, shared registrations, publisher filtering, and authorization-aware Meta APIs. |
| **Secure application messaging** | TLS/mTLS, Ticket, WAMP-CRA, SCRAM, Cryptosign, realm ACLs, and payload E2EE with XSalsa20-Poly1305 or AES-256-GCM. |
| **Fast where it matters** | A Rust native transport runtime, JSON/MessagePack/CBOR serializers, lazy payload APIs, and opaque payload forwarding through the router. |
| **A router you can own** | Embed the router in a Dart process or run the packaged CLI with worker isolation, graceful drain, OpenMetrics, HTTP bridges, and native release bundles. |
| **WAMP for agents** | Router-hosted MCP over Streamable HTTP or direct JSON with tools, form elicitation, resources, prompts, Pub/Sub, WAMP Meta APIs, bearer auth, and session isolation. |

Connectanum implements the full WAMP Basic Profile flow used by its six roles
and a deliberately announced subset of the Advanced Profile. See the
[audited support matrix](docs/wamp_profile_support.md) for exact coverage and
known gaps.

## Quick Start

Run the router and the complete RPC + Pub/Sub demo from a source checkout:

```bash
git clone https://github.com/konsultaner/connectanum-dart.git
cd connectanum-dart
bin/bootstrap
bin/connectanum-router --config examples/quickstart/router.yaml
```

In a second terminal:

```bash
dart run examples/quickstart/client.dart
```

The client API keeps all four application roles close to the WAMP vocabulary:

```dart
final client = Client(
  realm: 'realm1',
  transport: WebSocketTransport(
    'ws://127.0.0.1:8080/ws',
    Serializer(),
    WebSocketSerialization.serializationJson,
  ),
);
final session = await client.connect().first;

final subscription = await session.subscribe('com.example.greeting');
subscription.eventStream!.listen(
  (event) => print(event.arguments!.first),
);

final registration = await session.register('com.example.add');
registration.onInvoke((invocation) {
  final numbers = invocation.arguments!.cast<num>();
  invocation.respondWith(arguments: [numbers[0] + numbers[1]]);
});

await session.publish(
  'com.example.greeting',
  arguments: ['Hello from Connectanum'],
  options: PublishOptions(excludeMe: false),
);
final result = await session.callSingle(
  'com.example.add',
  arguments: [2, 3],
);
print('2 + 3 = ${result.arguments!.first}');
```

The maintained [quick-start example](examples/quickstart/README.md) includes
shutdown handling and expected output. Continue with the
[example catalog](docs/examples.md) for progressive calls, cancellation,
payload E2EE, router hosting, authentication, and MCP.

## Transport Benchmark

Connectanum gates WAMP performance across transports, serializers, security
profiles, and workload shapes instead of publishing an isolated headline
number. The current complete production-gate snapshot covers 78 workloads and
passes every throughput, lifecycle, transport, and zero-copy policy. Each cell
below reports **sustained data-window / full-lifecycle throughput** in Gbit/s;
the lifecycle value includes connection, session, routing, and teardown costs.

### 64 MiB file transfer

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| Native RawSocket | 16.102 / 14.913 | 18.242 / 16.843 | 19.174 / 17.180 |
| Dart RawSocket, buffered | 5.292 / 4.804 | 9.491 / 8.013 | 12.007 / 9.630 |
| Native RawSocket TLS | 13.262 / 12.504 | 18.340 / 16.943 | 17.324 / 15.966 |
| Native WebSocket | 15.663 / 14.437 | 19.407 / 17.748 | 19.057 / 17.180 |
| Dart WebSocket, buffered | 2.351 / 2.239 | 9.430 / 7.697 | 9.370 / 7.483 |
| Native WebSocket TLS | 12.874 / 12.014 | 18.155 / 16.424 | 16.951 / 15.203 |
| Native RawSocket + E2EE | 8.725 / 8.397 | 20.843 / 19.131 | 21.182 / 19.303 |
| Native RawSocket TLS + E2EE | 8.592 / 8.244 | 18.097 / 16.777 | 17.853 / 16.487 |
| Native WebSocket + E2EE | 8.516 / 8.142 | 20.891 / 18.921 | 19.218 / 17.424 |
| Native WebSocket TLS + E2EE | 8.329 / 7.932 | 17.339 / 15.704 | 15.701 / 14.413 |

The file scenario uses 64 MiB files and 4 MiB binary chunks. Identity-preserving
clear RawSocket MessagePack and CBOR can use kernel `sendfile`; JSON, TLS,
WebSocket masking, and E2EE use bounded copy-minimized transformations.

### Large RPC frames

| Transport and path | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| Native RawSocket | 13.612 / 4.965 | 21.246 / 6.638 | 19.525 / 4.914 |
| Native WebSocket | 6.816 / 5.949 | 9.132 / 7.809 | 6.644 / 5.674 |
| Native RawSocket TLS | 8.820 / 4.146 | 11.417 / 5.150 | 10.798 / 4.067 |
| Native WebSocket TLS | 5.578 / 4.965 | 6.613 / 5.828 | 5.276 / 4.628 |
| Dart RawSocket | 2.411 / 1.851 | 19.749 / 6.547 | 18.651 / 4.810 |
| Dart WebSocket | 2.616 / 2.475 | 7.886 / 6.883 | 7.306 / 6.216 |
| Dart RawSocket TLS reference[^dart-tls] | 0.741 / 0.678 | 0.989 / 0.896 | 0.987 / 0.858 |
| Dart WebSocket TLS reference[^dart-tls] | 0.717 / 0.706 | 0.934 / 0.917 | 0.929 / 0.906 |

RawSocket frames are 64 MiB and WebSocket frames are 8 MiB. Native TLS and
WebSocket TLS are the production secure paths.

### WebSocket fragmentation and Pub/Sub

| Transport and workload | JSON (Gbit/s) | MessagePack (Gbit/s) | CBOR (Gbit/s) |
| --- | ---: | ---: | ---: |
| WebSocket RPC, contiguous | 18.156 / 14.364 | 26.577 / 19.089 | 12.631 / 10.154 |
| WebSocket RPC, 4 KiB fragments | 8.761 / 7.683 | 11.047 / 9.460 | 7.444 / 6.557 |
| WebSocket Pub/Sub, contiguous | 6.962 / 6.032 | 11.818 / 9.673 | 4.229 / 3.825 |
| WebSocket Pub/Sub, 4 KiB fragments | 6.706 / 5.884 | 7.232 / 6.363 | 4.515 / 4.090 |
| WebSocket TLS RPC, contiguous | 9.469 / 8.212 | 12.251 / 10.399 | 7.977 / 6.961 |
| WebSocket TLS RPC, 4 KiB fragments | 8.134 / 7.206 | 8.981 / 7.954 | 6.969 / 6.180 |
| WebSocket TLS Pub/Sub, contiguous | 3.472 / 3.208 | 4.715 / 4.265 | 2.725 / 2.540 |
| WebSocket TLS Pub/Sub, 4 KiB fragments | 3.635 / 3.363 | 4.620 / 4.215 | 2.517 / 2.355 |

Fragmentation workloads use 4 MiB payloads, 4 KiB continuation frames, and
four concurrent in-flight messages. The exact scenario definitions and gates
are checked in for [file transfer](native/bench/scenarios/wamp_file_transfer_throughput.toml),
[large frames](native/bench/scenarios/wamp_large_transport_frames_heavy.toml),
and [WebSocket fragmentation](native/bench/scenarios/wamp_websocket_fragmentation_throughput.toml).

The latest
[hosted `master` profile run](https://github.com/konsultaner/connectanum-dart/actions/runs/29580331118)
also passes progressive invocation, call-timeout, Meta API, transport-counter,
and performance policies. The full multi-gigabit matrix above is the local
completion artifact from 2026-08-24; exact-head hosted confirmation remains
pending until these implementation changes are pushed. Results describe the
measured configuration, not a cross-project comparison or a substitute for
workload-specific load testing. See the
[benchmark contract](docs/wamp_profile_benchmarks.md) for reproduction commands,
budgets, and limitations.

[^dart-tls]: Pure-Dart TLS is constrained by the Dart SDK's asynchronous 8/10 KiB TLS staging and is retained as an explicit reference, not a production-gated secure path.

## Packages

Every package in the 3.x line shares one version and is released as a
coordinated stack.

| Package | Use it for |
| --- | --- |
| [`connectanum_client`](packages/connectanum_client) | Dart and Flutter WAMP clients, including native transports and payload E2EE providers. |
| [`connectanum_router`](packages/connectanum_router) | Embeddable router, standalone CLI, HTTP bridges, metrics, and router-hosted MCP. |
| [`connectanum_mcp`](packages/connectanum_mcp) | MCP servers and clients, Streamable HTTP, direct JSON APIs, and WAMP delegation. |
| [`connectanum_auth_server`](packages/connectanum_auth_server) | Config-driven remote authentication services and reusable auth building blocks. |
| [`connectanum_core`](packages/connectanum_core) | Protocol messages, serializers, feature announcements, and shared E2EE contracts. |
| [`connectanum`](packages/connectanum) | Compatibility facade for existing `package:connectanum/...` client imports. |
| [`connectanum_bench`](packages/connectanum_bench) | Reproducible router, transport, profile, and release-feature benchmark scenarios. |

The synchronized `3.0.0-beta.2` package graph is available on
[pub.dev](https://pub.dev/packages/connectanum/versions/3.0.0-beta.2). Beta
testers can use the compatibility facade or select only the modular packages
their application needs.

## Documentation

Start at the [documentation index](docs/README.md), or jump directly to:

- [Installation and getting started](docs/getting_started.md)
- [Examples and runnable workflows](docs/examples.md)
- [WAMP Basic and Advanced Profile support](docs/wamp_profile_support.md)
- [Router deployment](docs/deployment.md)
- [Router authentication](docs/router_auth_credentials.md)
- [TLS and mTLS](docs/tls.md)
- [Metrics and operations](docs/router_metrics.md)
- [MCP package guide](packages/connectanum_mcp/README.md)
- [Benchmark methodology](docs/wamp_profile_benchmarks.md)

## Project Status

`3.0.0-beta.2` is feature-complete for the announced release profile and is
ready for controlled integration testing. The remaining path to final `3.0.0`
is broader soak, multi-worker, multi-runtime-thread, and downstream workload
evidence.

Connectanum is open source under the [MIT License](LICENSE). Issues and
interoperability reports are welcome in the
[GitHub issue tracker](https://github.com/konsultaner/connectanum-dart/issues).
