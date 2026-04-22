# kTLS Research

## Why This Exists

The deployment hardening roadmap now needs a bounded answer to one question:
whether the native transport can realistically adopt Linux kTLS without
destabilizing the existing `rustls` + `tokio-rustls` runtime model. This note
captures that answer and the resulting benchmark order.

## Current Repo Baseline

- `native/transport/ct_core/src/tls.rs` builds the native TLS acceptor and
  client connector with `rustls` and `tokio-rustls`.
- `native/transport/ct_core/src/lib.rs` performs the TLS handshake eagerly on
  accept/connect and immediately wraps the resulting `tokio_rustls` stream into
  `IoStream`.
- `native/transport/ct_core/src/io_stream.rs` currently supports only three
  runtime variants:
  - plain `TcpStream`
  - `tokio_rustls::server::TlsStream<TcpStream>`
  - `tokio_rustls::client::TlsStream<TcpStream>`
- `native/transport/ct_core/Cargo.toml` currently depends on `rustls = 0.23`
  and `tokio-rustls = 0.26`, but there is no `ktls` / `ktls-stream`
  dependency yet.
- The shipped bench router config already exposes a TLS-enabled HTTP listener
  on `127.0.0.1:8080` for HTTP/1.1, HTTP/2, and HTTP/3, but the WAMP listener
  on `127.0.0.1:8081` is currently cleartext only. That means the existing
  bench harness can measure HTTPS / HTTP/2 immediately, but not secure
  RawSocket / WebSocket yet.

## External References

- Linux kTLS is a record-layer replacement, not a full TLS stack. The Linux
  kernel docs say the kernel kTLS implementation handles the TLS record
  subprotocol but not the TLS handshake, so handshake setup still belongs to a
  userspace TLS library or agent:
  <https://www.kernel.org/doc/html/next/networking/tls-handshake.html>
- The Linux kTLS docs also say TLS 1.3 key updates require userspace to push
  new `TLS_TX` / `TLS_RX` key material into the kernel; reads can fail with
  `EKEYEXPIRED` until the new receive key is installed:
  <https://docs.kernel.org/networking/tls.html>
- The same Linux docs describe kTLS as a replacement for the userspace TLS
  record layer and note that true `sendfile()` zero-copy is only available for
  device offload, not generic loopback/software-only runs:
  <https://docs.kernel.org/networking/tls.html>
- `rustls 0.23` exposes `ExtractedSecrets`, documented specifically as the
  post-handshake material used to configure kTLS:
  <https://docs.rs/rustls/latest/rustls/struct.ExtractedSecrets.html>
- `rustls 0.23` also exposes `dangerous_extract_secrets()` and
  `dangerous_into_kernel_connection()`. The crate source marks
  `dangerous_extract_secrets()` as deprecated for kTLS-style use because it does
  not cover session tickets or key updates; the recommended path is
  `dangerous_into_kernel_connection()`.
- `tokio-rustls 0.26` exposes `into_inner()` on both client and server TLS
  streams, which means the repo can recover both the raw socket and the
  `rustls` connection state after handshake without replacing the TLS library.
- `ktls-stream` documents the expected integration order clearly:
  configure the TLS ULP on the socket, perform the handshake with a userspace
  TLS library, extract secrets, then replace the socket with a kTLS-backed
  stream. It also recommends Linux `6.6` LTS or newer for better support:
  <https://docs.rs/ktls-stream/latest/ktls_stream/>

## Feasibility Assessment

### Bottom Line

Linux-only kTLS looks viable with the current Rust stack. The repo does not
need a `rustls` or `tokio-rustls` version jump just to prototype it.

### What Is Already Good Enough

- `rustls 0.23.38` is new enough to expose the kernel-handoff APIs and extracted
  traffic secrets.
- `tokio-rustls 0.26.4` is new enough to hand the underlying `TcpStream` and
  `rustls` connection back after handshake.
- The current bench tooling already has a TLS-enabled HTTP path, so the first
  Linux benchmark does not need new benchmark infrastructure.

### Repo-Local Blockers

1. Secret extraction is disabled today.
   - `rustls` client/server builders default `enable_secret_extraction` to
     `false`.
   - `native/transport/ct_core/src/tls.rs` builds configs through those
     defaults and never overrides them.
2. `IoStream` has no post-handshake Linux kTLS variant.
   - The current stream model assumes either plain TCP or an always-attached
     `tokio-rustls` session object.
3. There is no kTLS dependency or capability probe in the native workspace.
4. The benchmark router does not yet expose a TLS WAMP listener, so secure
   RawSocket / WebSocket cannot be measured on the shipped bench config.
5. This macOS workstation cannot execute the runtime path even after it exists.
   - Any real kTLS verification has to happen on Linux.

## Recommended Implementation Order

### Phase 1: Linux-Only HTTP Prototype

1. Add a Linux-only kTLS dependency (`ktls-stream` or equivalent) behind a
   target-gated build path.
2. Extend the server/client TLS builders in `native/transport/ct_core/src/tls.rs`
   so the Linux kTLS path can set `enable_secret_extraction = true`.
3. After TLS handshake completion, convert the `tokio-rustls` stream with
   `into_inner()`, then use `dangerous_into_kernel_connection()` rather than
   the deprecated `dangerous_extract_secrets()` helper.
4. Add a Linux-only `IoStream` variant for the offloaded socket and keep the
   existing `tokio-rustls` path as the default fallback when probing or setup
   fails.
5. Scope the first prototype to HTTPS / HTTP/2 only.

Reason:

- kTLS does not apply to QUIC / HTTP/3.
- The repo already ships a TLS-enabled HTTP benchmark path.
- This keeps the first prototype focused on one transport where TLS record work
  is heavy and benchmarkable.

### Phase 2: Secure WAMP Coverage

1. Add a TLS-enabled RawSocket / WebSocket listener to `native/bench/bench_router.json`.
2. Reuse the existing WAMP transport target machinery, which already switches
   to `wss://` when the endpoint is marked secure.
3. Add secure RawSocket / WebSocket scenarios only after the HTTP prototype is
   stable.

Reason:

- The benchmark harness already knows how to target secure WAMP transports.
- The missing piece is the TLS-enabled WAMP listener, not a new benchmark
  runner.

## Benchmark Plan

### Metrics To Compare

- end-to-end throughput
- average latency and p95 latency
- CPU usage on the Linux host
- kernel version and whether the run stayed on software kTLS or used NIC
  offload

### Stage A: Existing HTTPS / HTTP/2 Path

Use the current TLS bench listener on `127.0.0.1:8080` and compare:

- baseline `tokio-rustls`
- Linux kTLS enabled with graceful fallback disabled for the test host

This should be the first benchmark because the repo already has the required
listener and the result is not confounded by QUIC / HTTP/3.

### Stage B: Secure WAMP Transports

After adding a TLS WAMP listener, compare:

- RawSocket over TLS
- WebSocket over TLS

Do this for both small control-heavy shapes and the larger throughput shapes
already used in the bench suite.

### What Not To Overclaim

- macOS results are irrelevant for kTLS itself.
- loopback or GitHub-hosted CI runs can measure software-kTLS behavior, but not
  meaningful NIC offload gains
- HTTP/3 is out of scope because QUIC does not use kTLS
- `TLS_TX_ZEROCOPY_RO` and similar zero-copy claims only become meaningful on a
  supported Linux host with device offload

## Recommended Next Milestone

Land a Linux-only prototype with these rules:

- opt-in build/runtime path
- graceful fallback to the current `tokio-rustls` implementation when kernel,
  cipher, or stream-setup prerequisites are not met
- benchmark HTTP/2 first
- delay secure WAMP benchmarks until the bench router has a TLS WAMP listener

That is the smallest milestone that produces a real answer instead of more
research churn.
