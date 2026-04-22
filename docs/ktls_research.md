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
  distinction mattered directly here because the initial repo prototype used
  `tokio-rustls`'s buffered `ServerConnection`, and the current local kTLS
  handoff fix replaces that with an explicit unbuffered rustls server handshake
  on the Linux kTLS path.
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

Linux-only kTLS is still viable with the current Rust stack, and the deeper
server-handshake refactor is now the checked-in local direction. The repo did
not need a `rustls` or `tokio-rustls` version jump to move from the short-lived
dummy-session prototype to an unbuffered kernel-connection handoff.

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
3. Drive the Linux kTLS server path through rustls's unbuffered handshake API,
   then switch into `dangerous_into_kernel_connection()` only once the
   handshake is complete and any post-handshake plaintext has been buffered
   explicitly in userspace. The repo now has this local refactor checked in,
   and it avoids the hidden buffered state that the earlier
   `dangerous_extract_secrets()` / dummy-session handoff could not transfer
   cleanly.
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
artifact bundle with both baseline and required-kTLS per-pass summaries, and
GitHub Actions run `24773860158` later closed the benchmark milestone on the
corrected handoff path.

### What Improved

- Baseline TLS completed both HTTP/2 workloads cleanly for native runtime
  thread counts `1` and `4`.
- Required-kTLS now gets through the single-stream
  `h2_sustained_transfer` workload at native runtime thread count `1`, which
  confirmed the buffered-plaintext preservation step fixed at least one real
  part of the earlier handoff corruption before the repo moved on to the
  unbuffered server-handshake refactor.

### Baseline TLS Numbers From Run `24768909306`

- `h2_sustained_transfer`
  - native runtime threads `1`: `3994.58` Mbps, p95 `10.99` ms
  - native runtime threads `4`: `4247.40` Mbps, p95 `11.74` ms
- `h2_multiplexed_streams`
  - native runtime threads `1`: `5807.50` Mbps, p95 `36.30` ms
  - native runtime threads `4`: `5779.71` Mbps, p95 `38.51` ms

### Final Hosted Result

Follow-up hosted runs `24772627167` (`kTLS HTTP/2 Benchmarks`) and
`24772627180` (`kTLS Validation`) showed that the first unbuffered handoff
patch regressed earlier in the flow with
`received fatal alert: UnexpectedMessage` /
`got ApplicationData when expecting Handshake`.

A focused local repro against `rustls::server::UnbufferedServerConnection`
established two API constraints that matter directly for the Linux handoff:

- `EncodeTlsData` can be emitted multiple times before one `TransmitTlsData`
- `WriteTraffic` can coexist with a partial post-handshake TLS record prefix
  still buffered in the caller-owned TLS input slice

The final local fix therefore accumulates every encoded handshake fragment
until `TransmitTlsData` and keeps draining userspace TLS bytes until any
partial buffered record is completed or consumed before calling
`dangerous_into_kernel_connection()`.

Hosted confirmation on commit `6d18344` then closed the correctness side of the
milestone:

- `24773860109` (`CI`) passed
- `24773860116` (`kTLS Validation`) passed
- `24773860158` (`kTLS HTTP/2 Benchmarks`) passed

The final hosted comparison from run `24773860158` showed:

- `h2_multiplexed_streams`, native runtime threads `1`
  - baseline: `6357.68` Mbps, p95 `32.93` ms
  - required-kTLS: `5724.93` Mbps, p95 `37.46` ms
- `h2_multiplexed_streams`, native runtime threads `4`
  - baseline: `6565.00` Mbps, p95 `32.56` ms
  - required-kTLS: `2500.95` Mbps, p95 `220.07` ms
- `h2_sustained_transfer`, native runtime threads `1`
  - baseline: `4534.38` Mbps, p95 `9.94` ms
  - required-kTLS: `1968.00` Mbps, p95 `16.06` ms
- `h2_sustained_transfer`, native runtime threads `4`
  - baseline: `4793.49` Mbps, p95 `9.42` ms
  - required-kTLS: `2157.84` Mbps, p95 `16.53` ms

### Resulting Direction

- The earlier handshake regression is gone.
- The earlier multiplexed `EINVAL` / `EMSGSIZE` / `unexpected frame type`
  blocker is also gone.
- The remaining issue is performance tuning rather than correctness, especially
  for the 4-thread multiplexed required-kTLS shape.
- The next useful kTLS-specific benchmark step is secure WAMP TLS coverage:
  add a TLS WAMP listener to the bench router and measure secure RawSocket and
  secure WebSocket on the existing harness.

### What Not To Overclaim

- macOS results are irrelevant for kTLS itself.
- loopback or GitHub-hosted CI runs can measure software-kTLS behavior, but not
  meaningful NIC offload gains
- HTTP/3 is out of scope because QUIC does not use kTLS
- `TLS_TX_ZEROCOPY_RO` and similar zero-copy claims only become meaningful on a
  supported Linux host with device offload
- the current local kTLS path now uses rustls's unbuffered server handshake and
  `dangerous_into_kernel_connection()`, but it still is not the final
  production story for TLS 1.3 key-update handling, and it still keeps TLS 1.3
  session tickets suppressed until the refreshed hosted benchmark run confirms
  the new handoff path

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
