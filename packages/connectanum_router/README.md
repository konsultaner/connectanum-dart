# connectanum_router

`connectanum_router` is the Connectanum WAMP router package.

It combines:

- the Dart router, boss/worker, and config layer
- the Rust `ct_ffi` native transport runtime
- CLI and library entrypoints for running the router locally or in production

Status: active development. The package is used throughout this repository, but
it is not yet published as a stable public package.

## Run The Router

Tell the build hook which published native bundle to use from the application
`pubspec.yaml`. The router depends on `connectanum_client`, so configure both
native-asset hooks with the same release tag:

```yaml
hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_NATIVE_RELEASE_TAG: <release-tag>
    connectanum_router:
      CONNECTANUM_NATIVE_RELEASE_TAG: <release-tag>
```

Then start the router:

```bash
dart run connectanum_router --config path/to/router.yaml
```

The CLI also accepts `--native-lib <path>` when you do not want to rely on an
environment variable.

When running from this repository checkout, `bin/connectanum-router --config
path/to/router.yaml` or the executable-compatible alias
`bin/connectanum_router --config path/to/router.yaml` resolves or builds the
standard release `ct_ffi` library and then delegates to the package executable
with `--native-lib`. Use either wrapper for local consumer-application smokes
instead of copying native-runtime bootstrap logic into each project.

From a source checkout, you can prefetch the current host bundle explicitly and
use the printed path as a `CONNECTANUM_NATIVE_LIB` hook user define:

```bash
dart packages/connectanum_router/tool/install_native.dart --tag <release-tag>
```

## Library Usage

```dart
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main() async {
  final runtime = NativeTransportRuntime()..start();

  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 8080,
          webSocketPath: '/ws',
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
  );

  final binding = router.start(runtime);

  // Keep the process alive, then dispose binding/runtime on shutdown.
  await Future<void>.delayed(const Duration(hours: 1));
  await binding.dispose();
  runtime.shutdown();
  runtime.dispose();
}
```

For fuller examples, see:

- [example/main.dart](example/main.dart) - local router with demo credential
  providers and multiple auth methods
- [example/remote_websocket.dart](example/remote_websocket.dart) - WebSocket
  listener plus in-process remote auth delegate
- [../../docs/router_example.yaml](../../docs/router_example.yaml) - minimal
  config starter
- [../../docs/examples.md](../../docs/examples.md) - curated repo-level example
  gallery
- [../../docs/router_embedding.md](../../docs/router_embedding.md) - multiple
  logical routers sharing one native engine, scoped TLS reload and current
  isolation boundaries

## Graceful Drain And Health Checks

`RouterBinding.drain()` is the graceful shutdown entrypoint. It closes listener
sockets first, then lets workers finish session shutdown and GOODBYE/close
handling before the binding is torn down.

`RouterBinding.dispose()` already uses that same path, so a normal process
shutdown or CLI exit drains before the boss/runtime are released.

When the optional router-native OpenMetrics HTTP routes are enabled,
`/healthz` returns:

- `200 ok` while the router is ready
- `503 starting` before the router is ready
- `503 draining` while `drain()` is in progress

OpenMetrics also exposes drain counters such as
`connectanum_router_drain_in_progress` and
`connectanum_router_last_drain_duration_ms`.

## MQTT QoS 0 Benchmark Checkpoint

The current MQTT broker path supports anonymous loopback QoS 0 pub/sub for
MQTT 5 and 3.1.1 over TCP, TLS, WebSocket, and secure WebSocket. The
[October 2026 hosted benchmark](../../docs/benchmarks/mqtt-hosted-intel-58016dc8-2026-10-16.md)
compares the native router with Mosquitto 2.0.18 on the same Ubuntu 24.04
GitHub Actions Intel Xeon Platinum 8573C runner. Each sustained profile uses
five runs per broker; rates below are median delivered messages per second.
The CPU ratio compares broker CPU seconds, and peak RSS is the Connectanum
broker's Linux `VmHWM`.

| QoS 0 workload | Connectanum/s | Mosquitto/s | Throughput ratio | Broker CPU ratio | Peak RSS | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| MQTT 5 TCP, 128 B, window 512 | 151,508 | 110,233 | 1.374 | 1.488 | 36.1 MiB | Pass |
| MQTT 3.1.1 TCP, 128 B, window 512 | 152,374 | 122,126 | 1.248 | 1.472 | 36.4 MiB | Pass |
| MQTT 5 WebSocket, 128 B, window 512 | 72,010 | 80,820 | 0.891 | 1.632 | 23.2 MiB | Pass |
| MQTT 3.1.1 WebSocket, 128 B, window 512 | 72,490 | 79,645 | 0.910 | 1.610 | 23.4 MiB | Pass |
| MQTT 5 TCP, 64 KiB, window 32 | 4,148 | 4,691 | 0.884 | **4.294** | 55.1 MiB | **Fail: CPU cap 4.0** |
| MQTT 5 WSS, 128 B, batch 64 | 104,604 | 20,995 | 4.982 | 0.376 | 23.2 MiB | Pass |

Across these finite runs, all 192 matched samples received the 29,114,000
expected QoS 0 deliveries without duplicates. Nineteen of twenty profile
gates passed; the 64 KiB CPU ratio made
[that MQTT CI job](https://github.com/konsultaner/connectanum-dart/actions/runs/38816345739/job/116703874967)
red. A previous same-source AMD EPYC 9V74 run passed all twenty, so the
release performance margin remains open. The [full report and raw
rows](../../docs/benchmarks/mqtt-hosted-intel-58016dc8-2026-10-16.json)
include p95/p99 latency, broker CPU seconds, peak RSS, inputs, and provenance.
These are direct MQTT→MQTT measurements; WAMP↔MQTT translation and its memory
gate have no result yet.

## Lazy Payload And Forwarding Boundaries

The router keeps payload bytes lazy when the route stays on a supported
same-serializer or native-forward path. That matters for:

- internal-session call/event/result forwarding
- native fast-path WAMP routing
- PPT / E2EE payload forwarding where the router should stay blind to the
  wrapped payload

That is still a conditional optimization, not a blanket promise. Mixed
serializers or unsupported metadata shapes may materialize payloads in Dart
before re-encoding.

## Native Runtime Packaging

During `dart run` and `dart test`, the build hook can compile `ct_ffi`
automatically when a Rust toolchain is available.

For prebuilt deployments, configure hook inputs under `hooks.user_defines` for
the `connectanum_router` package:

- `CONNECTANUM_NATIVE_LIB`
- `CONNECTANUM_NATIVE_RELEASE_TAG`
- `CONNECTANUM_NATIVE_RELEASE_REPOSITORY`
- `CONNECTANUM_SKIP_NATIVE_BUILD`

The full deployment path, container image, and release-artifact flow are
documented in the
[installation guide](https://github.com/konsultaner/connectanum-dart/blob/master/docs/getting_started.md)
and
[deployment guide](https://github.com/konsultaner/connectanum-dart/blob/master/docs/deployment.md).

## Related Packages

- shared protocol/model layer:
  [../connectanum_core/README.md](../connectanum_core/README.md)
- client package:
  [../connectanum_client/README.md](../connectanum_client/README.md)
- remote auth helpers:
  [../connectanum_auth_server/README.md](../connectanum_auth_server/README.md)
- benchmark harness:
  [../connectanum_bench/README.md](../connectanum_bench/README.md)
