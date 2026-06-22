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
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
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
path/to/router.yaml` resolves or builds the standard release `ct_ffi` library
and then delegates to the package executable with `--native-lib`. Use that
wrapper for local consumer-application smokes instead of copying native-runtime
bootstrap logic into each project.

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

## Graceful Drain And Health Checks

`RouterBinding.drain()` is the graceful shutdown entrypoint. It closes listener
sockets first, then lets workers finish session shutdown and GOODBYE/close
handling before the binding is torn down.

`RouterBinding.dispose()` already uses that same path, so a normal process
shutdown or CLI exit drains before the boss/runtime are released.

When the optional OpenMetrics HTTP server is enabled, `/healthz` returns:

- `200 ok` while the router is ready
- `503 starting` before the router is ready
- `503 draining` while `drain()` is in progress

OpenMetrics also exposes drain counters such as
`connectanum_router_drain_in_progress` and
`connectanum_router_last_drain_duration_ms`.

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
documented in [../../docs/deployment.md](../../docs/deployment.md).

## Related Packages

- shared protocol/model layer:
  [../connectanum_core/README.md](../connectanum_core/README.md)
- client package:
  [../connectanum_client/README.md](../connectanum_client/README.md)
- remote auth helpers:
  [../connectanum_auth_server/README.md](../connectanum_auth_server/README.md)
- benchmark harness:
  [../connectanum_bench/README.md](../connectanum_bench/README.md)
