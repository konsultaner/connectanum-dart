# Installation And Getting Started

This guide takes a new router installation from zero to a working WAMP RPC and
Pub/Sub example. A Connectanum router deployment has three parts:

1. Dart 3.9.2 or newer and the `connectanum_router` package.
2. The `ct_ffi` native transport library for the target platform.
3. A YAML or JSON router configuration file.

## Beta Availability

The workspace is synchronized at `3.0.0-beta.1`, but the modular Dart packages
and matching `v3.0.0-beta.1` native release assets are not public yet. Use the
[source-checkout path](#run-the-current-beta-from-source) for current beta
testing. The [package path](#install-the-published-package) is the installation
contract to use after the coordinated beta is published.

Do not combine a package from one release with a native library from another.
The Dart packages, Rust crates, and native release assets move together.

## Supported Native Binaries

The native release workflow builds these host bundles:

| Platform | Release archive | Library |
| --- | --- | --- |
| Linux x64 | `ct-ffi-x86_64-unknown-linux-gnu.tar.gz` | `libct_ffi.so` |
| Linux arm64 | `ct-ffi-aarch64-unknown-linux-gnu.tar.gz` | `libct_ffi.so` |
| macOS Apple Silicon | `ct-ffi-aarch64-apple-darwin.tar.gz` | `libct_ffi.dylib` |
| macOS Intel | `ct-ffi-x86_64-apple-darwin.tar.gz` | `libct_ffi.dylib` |
| Windows x64 | `ct-ffi-x86_64-pc-windows-msvc.tar.gz` | `ct_ffi.dll` |

The package build hooks select the correct archive, verify its published
SHA-256 checksum, extract it, and bundle the library. No manual platform check
is needed on a supported host.

## Run The Current Beta From Source

Install [Dart](https://dart.dev/get-dart) and a stable
[Rust toolchain](https://rustup.rs/), then run:

```bash
git clone https://github.com/konsultaner/connectanum-dart.git
cd connectanum-dart
bin/bootstrap
bin/connectanum-router --config examples/quickstart/router.yaml
```

The source-checkout wrapper reuses an existing release library or builds
`ct_ffi` from the checked-out Rust source, then starts the router on
`ws://127.0.0.1:8080/ws`.

In a second terminal, run the four-role client example:

```bash
dart run examples/quickstart/client.dart
```

Expected output:

```text
Pub/Sub: Hello from Connectanum
RPC: 2 + 3 = 5
```

Stop the router with `Ctrl+C`.

## Install The Published Package

After `3.0.0-beta.1` is available on pub.dev and the matching GitHub Release is
published, create a small Dart runner project. Its `pubspec.yaml` should pin
the package version and configure both native-asset hooks with the same release
tag:

```yaml
name: my_connectanum_router
publish_to: none

environment:
  sdk: ^3.9.2

dependencies:
  connectanum_router: 3.0.0-beta.1

hooks:
  user_defines:
    connectanum_client:
      CONNECTANUM_NATIVE_RELEASE_TAG: v3.0.0-beta.1
    connectanum_router:
      CONNECTANUM_NATIVE_RELEASE_TAG: v3.0.0-beta.1
```

`connectanum_router` depends on `connectanum_client`, and both packages expose a
native-asset hook. Configuring both prevents either transitive hook from trying
to find the monorepo's Rust workspace.

Plain `dart pub get` resolves Dart packages but does not run native build hooks.
The first `dart run` downloads and bundles the matching host library.

## Create `router.yaml`

Save this local-development configuration as `router.yaml`. The maintained
copy is [examples/quickstart/router.yaml](../examples/quickstart/router.yaml)
and is parsed by the router test suite.

```yaml
router:
  realms:
    - name: realm1
      auth:
        authmethods: [anonymous]
      roles:
        - name: anonymous
          permissions:
            - uri: com.example.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]

  listeners:
    - endpoint: 127.0.0.1:8080
      authmethods: [anonymous]
      protocols: [websocket]
      tls:
        mode: disabled
      websocket:
        path: /ws
        subprotocols: [wamp.2.json, wamp.2.msgpack, wamp.2.cbor]

  worker_pool:
    min_workers: 1

  authenticators:
    anonymous:
      type: anonymous
```

This deliberately binds to localhost, allows anonymous sessions, and grants
access only below `com.example.`. Add authentication and TLS before exposing a
listener outside a development machine.

Start the installed router with:

```bash
dart pub get
dart run connectanum_router --config router.yaml
```

The executable also accepts `--native-lib /absolute/path/to/libct_ffi` and
`--verbose`.

## Native Library Alternatives

The release-download hook is the recommended package installation path. Two
explicit alternatives are available:

- Set `CONNECTANUM_NATIVE_LIB` for both packages under
  `hooks.user_defines` when an application already has a compatible shared
  library. The path may be absolute or relative to the application pubspec.
- Set `CONNECTANUM_SKIP_NATIVE_BUILD: true` for both packages when the
  deployment installs `ct_ffi` in the platform loader search path. This is an
  advanced packaging option; the application is responsible for installing
  the exact matching library.

From a repository checkout, the host-native bundle can also be downloaded and
checksum-verified explicitly:

```bash
export CONNECTANUM_NATIVE_LIB="$(
  dart packages/connectanum_router/tool/install_native.dart \
    --tag <matching-release-tag>
)"
bin/connectanum-router --config router.yaml
```

The direct installer helper is a source-checkout tool, not a public package
executable. Package consumers should use hook user-defines instead.

## Next Steps

- Run the complete [quick-start example](../examples/quickstart/README.md).
- Choose client and router workflows from the [example catalog](examples.md).
- Add [router authentication](router_auth_credentials.md) and
  [TLS or mTLS](tls.md).
- Configure [OpenMetrics and health checks](router_metrics.md).
- Follow the [production deployment guide](deployment.md) for compiled runners,
  containers, systemd, Kubernetes, native verification, and graceful drain.
- Check the [WAMP profile support matrix](wamp_profile_support.md) before using
  Advanced Profile features.
