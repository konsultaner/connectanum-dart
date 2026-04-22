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
- `rustls 0.23` exposes `dangerous_extract_secrets()` on the buffered
  `ServerConnection` / `ClientConnection` types and exposes
  `dangerous_into_kernel_connection()` on the unbuffered connection types. That
  distinction matters here because `tokio-rustls 0.26` hands the repo back a
  buffered `ServerConnection`, not an unbuffered one.
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

Linux-only kTLS is still viable with the current Rust stack, but the current
`tokio-rustls` integration limits how far the prototype can go without a deeper
handshake refactor. The repo does not need a `rustls` or `tokio-rustls` version
jump just to validate a short-lived HTTP/2 smoke path.

### What Is Already Good Enough

- `rustls 0.23.38` is new enough to expose extracted traffic secrets and the
  kernel-handoff APIs on its unbuffered connection types.
- `tokio-rustls 0.26.4` is new enough to hand the underlying `TcpStream` and
  buffered `rustls` connection back after handshake.
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
   `into_inner()`. With the current buffered `ServerConnection` API, the
   practical prototype path is `dangerous_extract_secrets()` plus a dummy
   server-side kTLS session for short-lived validation traffic; a full kernel
   connection handoff would require moving the server handshake onto rustls's
   unbuffered API or another lower-level integration. As long as that dummy
   session path remains in place, the server should not advertise TLS 1.3
   session tickets on kTLS-enabled listeners.
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

## Hosted HTTP/2 Benchmark Findings

GitHub Actions run `24768909306` on Ubuntu 24.04 provided the first hosted
artifact bundle with both baseline and required-kTLS per-pass summaries.

### What Improved

- Baseline TLS completed both HTTP/2 workloads cleanly for native runtime
  thread counts `1` and `4`.
- Required-kTLS now gets through the single-stream
  `h2_sustained_transfer` workload at native runtime thread count `1`, which
  confirms the buffered-plaintext drain added ahead of `ktls_stream::new_dummy`
  fixed at least one real part of the earlier handoff corruption.

### Baseline TLS Numbers From Run `24768909306`

- `h2_sustained_transfer`
  - native runtime threads `1`: `3994.58` Mbps, p95 `10.99` ms
  - native runtime threads `4`: `4247.40` Mbps, p95 `11.74` ms
- `h2_multiplexed_streams`
  - native runtime threads `1`: `5807.50` Mbps, p95 `36.30` ms
  - native runtime threads `4`: `5779.71` Mbps, p95 `38.51` ms

### Current Required-kTLS Blocker

- The same hosted run completed only `h2_sustained_transfer` under
  required-kTLS, and only at native runtime thread count `1`
  (`1911.93` Mbps, p95 `18.85` ms, two protocol-error events).
- The multiplexed HTTP/2 workload still fails under
  `CONNECTANUM_ENABLE_KTLS=1` plus `CONNECTANUM_REQUIRE_KTLS=1` with:
  - `http/2 handshake failed ... Invalid argument (os error 22)`
  - `http/2 handshake failed ... Message too long (os error 90)`
  - intermittent `Failed to set TLS ULP: Transport endpoint is not connected (os error 107)`
  - downstream HTTP/2 send failures reported as `unexpected frame type`
  - client-visible `connection reset`

### Resulting Direction

- The next useful kTLS task is no longer proving that the Linux handoff can
  start at all; that is now true for the single-stream sustained-transfer case.
- The remaining blocker is the multiplexed HTTP/2 path under required-kTLS.
- The same hosted log also shows intermittent required-kTLS handshake failures
  in the nominally simpler single-stream workload, which is consistent with the
  current dummy-session path still exposing unsupported post-handshake TLS 1.3
  behavior. The current mitigation is to suppress server-side TLS 1.3 session
  tickets whenever that handoff path is active.
- Benchmark artifact generation should stay resilient to partial pass failure,
  because hosted runs can now produce baseline plus partial kTLS summaries even
  when the full comparison does not complete successfully.

### What Not To Overclaim

- macOS results are irrelevant for kTLS itself.
- loopback or GitHub-hosted CI runs can measure software-kTLS behavior, but not
  meaningful NIC offload gains
- HTTP/3 is out of scope because QUIC does not use kTLS
- `TLS_TX_ZEROCOPY_RO` and similar zero-copy claims only become meaningful on a
  supported Linux host with device offload
- the current `tokio-rustls` server path does not yet provide production-ready
  TLS 1.3 key-update or ticket handling for kTLS, because the validated
  prototype uses `dangerous_extract_secrets()` plus a dummy server session, and
  therefore now suppresses TLS 1.3 session tickets on that path

## Recommended Next Milestone

Land a Linux-only prototype with these rules:

- opt-in build/runtime path
- graceful fallback to the current `tokio-rustls` implementation when kernel,
  cipher, or stream-setup prerequisites are not met
- explicit acknowledgement that the current validated prototype is for
  short-lived HTTP/2 smoke traffic, not final TLS 1.3 key-update/ticket
  handling
- benchmark HTTP/2 first
- delay secure WAMP benchmarks until the bench router has a TLS WAMP listener

That is the smallest milestone that produces a real answer instead of more
research churn.
