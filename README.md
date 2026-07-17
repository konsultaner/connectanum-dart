<div align="center">

# Connectanum

**A high-performance WAMP v2 stack for Dart and Flutter.**

Build real-time applications with routed RPC and Pub/Sub, run an embeddable or
standalone router, and expose WAMP services to AI agents through MCP.

[![CI](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart.yml)
[![WAMP Profile Benchmarks](https://github.com/konsultaner/connectanum-dart/actions/workflows/wamp-profile-benchmarks.yml/badge.svg?branch=master)](https://github.com/konsultaner/connectanum-dart/actions/workflows/wamp-profile-benchmarks.yml)
[![Package Dry Run](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart-package-publish.yml/badge.svg?branch=master)](https://github.com/konsultaner/connectanum-dart/actions/workflows/dart-package-publish.yml)
[![Version](https://img.shields.io/badge/version-3.0.0--beta-f59e0b)](https://github.com/konsultaner/connectanum-dart)
[![Dart](https://img.shields.io/badge/Dart-%5E3.9.2-0175c2?logo=dart&logoColor=white)](https://dart.dev/)
[![WAMP](https://img.shields.io/badge/WAMP-v2-4b32c3)](https://wamp-proto.org/)
[![License](https://img.shields.io/badge/license-MIT-0f766e)](LICENSE)

[Quick start](#quick-start) · [Documentation](docs/README.md) ·
[Examples](docs/examples.md) · [Feature matrix](docs/wamp_profile_support.md) ·
[Benchmarks](docs/wamp_profile_benchmarks.md)

</div>

> **3.0 beta:** all Connectanum Dart packages and native Rust crates move
> together at `3.0.0-beta`. The beta is intended for integration testing before
> the final `3.0.0` release.

## Why Connectanum?

| | |
| --- | --- |
| **One protocol, every role** | Publisher, Subscriber, Caller, Callee, Broker, and Dealer with the WAMP Basic Profile across WebSocket and RawSocket. |
| **Advanced RPC and Pub/Sub** | Progressive results and invocations, call timeouts and cancellation, pattern routing, shared registrations, publisher filtering, and authorization-aware Meta APIs. |
| **Secure application messaging** | TLS/mTLS, Ticket, WAMP-CRA, SCRAM, Cryptosign, realm ACLs, and payload E2EE with XSalsa20-Poly1305 or AES-256-GCM. |
| **Fast where it matters** | A Rust native transport runtime, JSON/MessagePack/CBOR serializers, lazy payload APIs, and opaque payload forwarding through the router. |
| **A router you can own** | Embed the router in a Dart process or run the packaged CLI with worker isolation, graceful drain, OpenMetrics, HTTP bridges, and native release bundles. |
| **WAMP for agents** | Router-hosted MCP over Streamable HTTP or direct JSON with tools, resources, prompts, Pub/Sub, WAMP Meta APIs, bearer auth, and session isolation. |

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

## Benchmarks

Connectanum gates WAMP performance in CI instead of publishing an isolated
headline number. The latest
[hosted `master` run](https://github.com/konsultaner/connectanum-dart/actions/runs/29580331118)
passed every transport-counter and performance policy.

Representative response-throughput ranges from that run:

| Workload family | Throughput | Observed p95 latency |
| --- | ---: | ---: |
| Cleartext RPC + Pub/Sub | **101.8-448.1 Mbps** | 33.1-137.7 ms |
| TLS RPC + Pub/Sub | **60.2-257.2 Mbps** | 46.1-247.8 ms |
| Pub/Sub fan-out to 8 subscribers | **106.7-138.4 Mbps** | 182.8-223.8 ms |
| Native payload E2EE | **21.9-53.1 Mbps** | 65.8-90.2 ms |

The same hosted gate verified progressive invocations at 16.1-19.6 ms p95,
50 ms call timeouts at 56.8-60.5 ms p95, and the full 15-procedure statistics
Meta API sweep at 29.2-51.0 ms p95.

These are short regression-gate measurements on GitHub-hosted Linux x64 with
one router worker, one native runtime thread, six-way concurrency, and 64 KiB
payloads. They are evidence for this measured configuration, not a
cross-project comparison or a substitute for workload-specific load testing.
The [benchmark contract](docs/wamp_profile_benchmarks.md) documents scenarios,
budgets, reproduction commands, and limitations.

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

The existing `connectanum` 2.x facade is available on
[pub.dev](https://pub.dev/packages/connectanum). The modular `3.0.0-beta`
packages are synchronized and publish-ready but are not yet public on pub.dev;
beta testers can use the Git workspace paths until the coordinated publish.

## Documentation

Start at the [documentation index](docs/README.md), or jump directly to:

- [Examples and runnable workflows](docs/examples.md)
- [WAMP Basic and Advanced Profile support](docs/wamp_profile_support.md)
- [Router deployment](docs/deployment.md)
- [Router authentication](docs/router_auth_credentials.md)
- [TLS and mTLS](docs/tls.md)
- [Metrics and operations](docs/router_metrics.md)
- [MCP package guide](packages/connectanum_mcp/README.md)
- [Benchmark methodology](docs/wamp_profile_benchmarks.md)

## Project Status

`3.0.0-beta` is feature-complete for the announced release profile and is
ready for controlled integration testing. The remaining path to final `3.0.0`
is broader soak, multi-worker, multi-runtime-thread, and downstream workload
evidence, followed by the coordinated public package release.

Connectanum is open source under the [MIT License](LICENSE). Issues and
interoperability reports are welcome in the
[GitHub issue tracker](https://github.com/konsultaner/connectanum-dart/issues).
