# Deployment (production)

This repo deploys as a Dart VM process + the native transport library (`libct_ffi.so` / `.dylib` / `.dll`) plus a router config file (YAML or JSON).

Deployment templates live in:

- `deploy/docker` (Dockerfile + compose example)
- `deploy/systemd` (systemd unit file)
- `deploy/k8s` (Kubernetes manifest)

## Build native transport

```sh
cargo build --manifest-path native/transport/Cargo.toml -p ct_ffi --release
```

The shared library ends up at:

- `native/transport/target/release/libct_ffi.so` (Linux)
- `native/transport/target/release/libct_ffi.dylib` (macOS)
- `native/transport/target/release/ct_ffi.dll` (Windows)

## Run the router

1. Create a router config file (see `docs/tls.md` for TLS settings).
2. Point the process at the native library (env var or CLI flag).

The router runner expects `CONNECTANUM_NATIVE_LIB` to point at the native shared library:

```sh
export CONNECTANUM_NATIVE_LIB=/absolute/path/to/native/transport/target/release/libct_ffi.so
dart run connectanum_router --config /etc/connectanum/router.yaml
```

During `dart run` / `dart test`, the package build hooks compile `ct_ffi`
automatically by default. If you already have a prebuilt library, export
`CONNECTANUM_NATIVE_LIB` before invoking Dart and the hook will bundle that
binary instead of running Cargo. If your environment installs `ct_ffi` on the
platform loader search path, set `CONNECTANUM_SKIP_NATIVE_BUILD=1` to suppress
Cargo entirely and let the runtime loader use the system library.

If you do not want to build Rust locally, the GitHub Actions
`Native Artifacts` workflow uploads prebuilt Linux/macOS bundles named
`ct-ffi-<host-triple>.tar.gz`, and release-tag runs publish the same assets to
GitHub Releases. Extract the archive for your host, then export
`CONNECTANUM_NATIVE_LIB` to the bundled library path before starting the
router. These prebuilt assets are not signed yet.

For production packaging you can compile the runner to a native executable:

```sh
dart compile exe packages/connectanum_router/bin/connectanum_router.dart -o connectanum_router
./connectanum_router --config /etc/connectanum/router.yaml
```

Example config starter: `docs/router_example.yaml`.

## OpenMetrics exporter

If the config sets `metrics.open_metrics.listen`, the router runner starts an
HTTP server on that address that serves:

- `GET /metrics` (OpenMetrics text)
- `GET /healthz` (200 OK)

If `metrics.open_metrics.auth_token` is set, `GET /metrics` requires
`Authorization: Bearer <token>`.

## TLS reload / certificate rotation

The production runner (`packages/connectanum_router/bin/connectanum_router.dart`) watches `SIGHUP`
and reloads TLS configuration (certificates and `client_auth`) from the configured YAML/JSON file.
This updates TLS settings for **new** connections (TCP + QUIC); existing connections keep using the
previous TLS session.

- systemd: `systemctl reload connectanum-router` (the unit uses `ExecReload=/bin/kill -HUP $MAINPID`)
- manual: `kill -HUP <pid>`

## systemd sketch

```ini
[Unit]
Description=Connectanum Router
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/connectanum-router
Environment=CONNECTANUM_NATIVE_LIB=/opt/connectanum-router/lib/libct_ffi.so
ExecStart=/usr/bin/dart run connectanum_router --config /etc/connectanum/router.yaml
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

## Operational notes

- Prefer running as a non-root user; bind privileged ports via a reverse proxy or `setcap cap_net_bind_service=+ep` on your launcher binary.
- Mount TLS private keys read-only and keep them out of the repo; rotate certificates via your standard PKI process.
- Expose metrics using the built-in OpenMetrics exporter (`metrics.open_metrics`) and scrape it with Prometheus.
