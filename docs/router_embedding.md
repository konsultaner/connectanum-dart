# Embedding Multiple Routers

Use one `NativeTransportRuntime` engine and one `RouterBinding` per logical
router. The engine owns the Tokio thread pool; a binding owns its listeners,
router workers, realms and sessions.

Independent operating-system processes may each run their own engine, even
with the same temporary directory. The runtime ownership lock includes the PID
and never serializes unrelated router processes. The native startup guard still
permits only one engine within a process. File locks are not a portable isolate
mutex: on Linux/macOS, multiple isolates can acquire the same exclusive file
lock. See Dart's [file-lock semantics](https://api.dart.dev/dart-io/RandomAccessFile/lock.html).

```dart
final runtime = NativeTransportRuntime()..start();
final first = firstRouter.start(runtime, activateListeners: false);
final second = secondRouter.start(runtime);
first.activateListeners();

// Stops only the first binding. The second keeps its own listener sockets.
await first.dispose();
final restarted = firstRouter.start(runtime);

await restarted.dispose();
await second.dispose();
runtime.shutdown();
runtime.dispose();
```

`firstRouter` and `secondRouter` are separately configured `Router` instances.
With a native library exporting `ct_listen_router_endpoint` and
`ct_reload_router_tls`, listener activation takes the binding's immutable native
configuration snapshot. Starting another router cannot replace that snapshot.
Separate `127.0.0.1:0` listeners remain distinguishable even when each router's
endpoint has index zero. Fixed ports still must be available; this does not add
socket-port sharing.

## TLS Reload

Use `binding.reloadTls()` to rebuild that binding's TLS configuration. For
certificate or TLS-policy rotation, build a replacement `Router` configuration
containing the updated PEM data. Serialize it with
`replacementRouter.buildNativeConfigJson()` and pass it as
`binding.reloadTls(configuration: replacementBytes)`. Keep the endpoint order,
configured hosts/ports, TLS mode and HTTP/3 enablement unchanged. Supply the
updated certificate/key PEM contents, not file paths. Changes requiring socket
or worker reconfiguration should restart the binding instead.

All requested listener IDs, endpoint mappings and TLS/QUIC identities are
validated before any listener is updated. A validation failure leaves the
running configuration and the binding's saved snapshot unchanged. This is
failure atomicity, not a stop-the-world multi-listener cutover. Existing
connections retain their negotiated state. A disposed or inactive binding
rejects reload and cannot reactivate after disposal.

The legacy `runtime.applyRouterConfig()`, `listen()` and
`listenConfiguredEndpoint()` APIs retain their default-config behavior.
`runtime.reloadTls()` reloads only those legacy listeners; it never reloads
router-scoped listeners. Older native binaries still load using the legacy
activation path, but cannot guarantee multi-router configuration isolation.
The binding's scoped TLS reload fails explicitly on those binaries instead of
falling back to a global reload. Upgrade Dart and native components together.

## Remaining Boundaries

This is listener/configuration isolation, not complete independent native
runtime contexts. Constructing a second `NativeTransportRuntime` is still
unsupported. Runtime shutdown stops the shared engine and all its listeners;
dispose individual bindings first. Native metrics, callback registration and
some event queues remain process-scoped. Do not treat multiple bindings as
process or security isolation. Independent runtime ownership, callback/event
dispatch and metrics are the next embedding phase.

For natural process exit, await `binding.dispose()`, close any application-owned
clients, timers, signal subscriptions and receive ports, and call
`runtime.shutdown()` and `runtime.dispose()`. A forced `exit(0)` is not a substitute for cleanup. The
process regression starts two live WAMP routers in the same temporary directory
and requires both to return from `main` and exit without a forced exit.

Disposal also accounts for internal-session and metrics bootstrap already in
flight. New starts and unpublished late starts fail with `StateError` once
disposal begins. Concurrent callers await the same disposal result. A failing
owned cleanup callback does not skip the other binding owners; its first error
is reported after cleanup is attempted. Keep runtime shutdown in application
`finally` cleanup even when binding disposal reports an error. Subprocess tests
cover startup/disposal overlap and owner-cleanup failure without `exit(0)`.
The public router CLI cancels all of its signal subscriptions and returns
naturally after SIGINT/SIGTERM cleanup; it does not use forced exit to hide
an unused signal listener. Its SIGHUP path uses binding-scoped TLS reload.
