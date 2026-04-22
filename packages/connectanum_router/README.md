# connectanum_router

`connectanum_router` is the Connectanum WAMP router package.

It combines:

- the Dart router, boss/worker, and config layer
- the Rust `ct_ffi` native transport runtime
- CLI and library entrypoints for running the router locally or in production

Status: active development. The package is used throughout this repository, but
it is not yet published as a stable public package.

## Run The Router

Install or point at a native runtime bundle:

```bash
export CONNECTANUM_NATIVE_LIB="$(
  dart run connectanum_router:tool/install_native.dart --tag <release-tag>
)"
```

Then start the router:

```bash
dart run connectanum_router --config path/to/router.yaml
```

The CLI also accepts `--native-lib <path>` when you do not want to rely on an
environment variable.

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

For fuller examples, see [example/](example).

## Native Runtime Packaging

During `dart run` and `dart test`, the build hook can compile `ct_ffi`
automatically when a Rust toolchain is available.

For prebuilt deployments, the same env contract as the repo root applies:

- `CONNECTANUM_NATIVE_LIB`
- `CONNECTANUM_NATIVE_RELEASE_TAG`
- `CONNECTANUM_NATIVE_RELEASE_REPOSITORY`
- `CONNECTANUM_SKIP_NATIVE_BUILD=1`

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
