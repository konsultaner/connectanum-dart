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
- The shipped bench router config now exposes both the TLS-enabled HTTP
  listener on `127.0.0.1:8080` and secure WAMP listeners alongside the
  existing cleartext WAMP listeners, so the harness can already measure both
  HTTP/2 and secure RawSocket / WebSocket shapes on Linux.

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

### Current Blockers

1. The remaining kTLS issue is performance rather than correctness.
   - Hosted Linux validation is green, but required-kTLS still trails baseline
     TLS in the HTTP/2 comparison benchmark, especially in the 4-thread
     multiplexed workload.
2. The benchmark workflow is manual-only.
   - That keeps routine CI lean, but it also means performance follow-ups need
     clear comparison artifacts so one hosted run is easy to interpret without
     re-reading raw per-workload rows.
   - The repo now summarizes throughput, latency, CPU-total, wall-time, and
     max-RSS deltas in the comparison bundle, and hosted rerun `24865337582`
     on commit `706d8b8` now gives the current decision point directly.
   - That rerun showed modest gross resource deltas
     (`cpu_total_seconds +2.26%`, `elapsed_seconds +1.71%`,
     `max_rss_kib +0.57%`) while throughput still regressed by `24.20%` on
     average and p95 latency still rose by `40.38%` on average. That keeps the
     remaining problem firmly in request-path performance rather than obvious
     CPU or memory blow-up.
   - The old `Resource usage: no per-pass usage artifacts were present.` line
     turned out to be a parser bug, not a missing-artifact problem: GNU
     `time -v` prefixes its fields with tabs on hosted Linux. The comparison
     tool now strips leading whitespace so future summaries surface those
     resource deltas directly.
3. This macOS workstation still cannot execute the runtime path itself.
   - Any real kTLS verification or tuning step still has to land through Linux
     hosts or hosted workflow runs.

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
2. Reuse the existing WAMP transport target machinery, but make secure-target
   selection explicit with `secure_transport = true` so secure workloads do not
   silently fall back to the higher-scored cleartext listener.
3. Add secure RawSocket / WebSocket scenarios only after the HTTP prototype is
   stable.

Reason:

- The benchmark harness already knew how to dial secure WAMP transports, but
  it needed an explicit secure selector once both cleartext and TLS listeners
  existed at the same time.
- The resulting scenario contract is now straightforward: keep the existing
  WAMP protocol names, add `secure_transport = true`, and point secure
  workloads at the `bench.secure` ticket-auth realm.

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
- Secure WAMP TLS coverage is now complete too, so the next useful kTLS step
  was to keep the hosted comparison artifacts readable enough that future Linux
  reruns can answer "is required-kTLS improving or regressing?" quickly.
- That readability slice now also includes per-pass resource-usage summaries,
  so future hosted reruns can show whether required-kTLS is paying its penalty
  in CPU, wall time, or memory footprint instead of only raw throughput/p95.
- The same comparison bundle now also rolls those deltas up by workload family
  and native runtime thread count, and it correctly parses GNU `time -v`
  elapsed wall-time labels even though that label includes embedded colons.
  The first read can now answer where the penalty clusters on the latest hosted
  rerun instead of falling back to stale assumptions.
- The same comparison bundle now also renders per-workload transport-counter
  deltas, so the first read can distinguish transport-visible pressure from a
  hotspot that stays invisible to the current bench telemetry.
- The next Linux-side signal is now narrower and lower-overhead than ptrace or
  perf: the manual comparison helper captures `/proc/net/tls_stat` before and
  after each pass and summarizes the delta, so hosted runs can show whether
  required-kTLS is actually opening software/device TX/RX sessions and whether
  decrypt/rekey counters stay quiet while the throughput/p95 gap persists.

### Latest Hosted Comparison

The latest hosted rerun landed on commit `2393a01` as workflow run
`24869856621` (`kTLS HTTP/2 Benchmarks`). Its artifact bundle showed:

- `h2_multiplexed_streams`, native runtime threads `1`
  - baseline: `5752.19` Mbps, p95 `38.83` ms
  - required-kTLS: `3822.66` Mbps, p95 `59.07` ms
- `h2_multiplexed_streams`, native runtime threads `4`
  - baseline: `5835.55` Mbps, p95 `38.15` ms
  - required-kTLS: `4831.84` Mbps, p95 `47.67` ms
- `h2_sustained_transfer`, native runtime threads `1`
  - baseline: `1766.02` Mbps, p95 `23.25` ms
  - required-kTLS: `2015.28` Mbps, p95 `21.09` ms
- `h2_sustained_transfer`, native runtime threads `4`
  - baseline: `3901.68` Mbps, p95 `12.95` ms
  - required-kTLS: `3477.14` Mbps, p95 `14.27` ms

The same rerun also showed:

- CPU total: baseline `29.97s`, required-kTLS `29.93s`, delta `-0.13%`
- Elapsed wall time: baseline `19.37s`, required-kTLS `19.22s`, delta `-0.77%`
- Max RSS: baseline `528.32 MiB`, required-kTLS `523.09 MiB`, delta `-0.99%`
- Linux TLS session opens:
  - baseline: software TX/RX `0/0`, device TX/RX `0/0`
  - required-kTLS: software TX/RX `34/34`, device TX/RX `0/0`
- Linux TLS anomalies: no non-zero decrypt/rekey counters in either pass

That rerun changes the interpretation boundary again:

- workload-family hotspot: `h2_multiplexed_streams`
- runtime-thread hotspot: `threads=4`
- `h2_sustained_transfer` is no longer the problem statement:
  - `threads=1` improved under required-kTLS
  - `threads=4` regressed modestly, but nowhere near the multiplex penalty

The transport-delta view still says the slowdown is not already explained by
the current router counters alone:

- worst throughput row: `h2_multiplexed_streams` at `threads=1`
  - `backpressure_events 79 -> 76`
  - `backpressure_alerts 3 -> 3`
  - `max_backpressure_depth_after 4 -> 4`
- `h2_sustained_transfer` rows remain all-zero for the current
  transport/backpressure telemetry

That means the Linux TLS-stat slice answered one question cleanly: required
kTLS is staying on the kernel software TX/RX path without obvious decrypt or
rekey anomalies. The remaining question is now much narrower: why multiplexed
HTTP/2 streams regress materially once concurrency is layered onto that clean
kTLS path.

### Focused Multiplex Scaling Rerun

The first targeted rerun of that hypothesis landed on commit `257f9aa` as
workflow run `24870980724` (`kTLS HTTP/2 Benchmarks`) with:

- `scenario = native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
- `skip_artifact_gate = true`

That run made three points explicit:

1. The regression is not limited to deep multiplexing.
   - `h2_multiplexed_streams_s1`, `threads=1`: `3947.58 -> 1985.47` Mbps
     (`-49.70%`), p95 `12.22 -> 20.62` ms (`+68.80%`)
   - `h2_multiplexed_streams_s1`, `threads=4`: `3947.58 -> 1906.50` Mbps
     (`-51.70%`), p95 `13.93 -> 22.69` ms (`+62.88%`)
2. The worst throughput row still sits in the reused-connection HTTP/2 path,
   but it is not the highest stream count:
   - `h2_multiplexed_streams_s4`, `threads=4`: `6100.81 -> 2137.22` Mbps
     (`-64.97%`)
3. The old explanations are still not showing up.
   - required-kTLS again stayed on the kernel software path cleanly:
     `TlsTxSw/TlsRxSw 66/66`, no decrypt/rekey anomalies
   - `h2_multiplexed_streams_s1` stayed at zero transport counters in both
     passes, so the large `s1` regression is not already explained by the
     current backpressure/alert telemetry

That narrowed the next question further: the bench needed better visibility
into HTTP connection reuse/open behavior per workload row before another
runtime change would be justified.

### Connection Usage Instrumentation

That visibility slice is now landed locally:

- the native HTTP bench path records optional `http_connection_usage` in
  per-workload JSONL rows
- transformed artifact bundles now expose `connections_opened`,
  `streams_per_connection`, and derived
  `samples_per_connection_avg`
- the comparison helper now renders worst-row connection views plus a dedicated
  `HTTP Connection Usage` section for comparable rows

That means the next hosted rerun can answer a narrower question than before:
whether required-kTLS is opening materially more HTTP connections than the
baseline pass, or whether the regression persists even when the new
connection-usage metrics stay flat.

### Hosted Connection Usage Result

That rerun has now landed as workflow run `24872903498` on commit `55f23d3`,
and it closed the connection-churn hypothesis:

- every comparable row held `connections_opened` flat at `4 -> 4 (+0)`
- every comparable row held `samples_per_connection_avg` flat at
  `20.00 -> 20.00 (+0.00)`
- the dominant hotspot stayed on the same reused-connection HTTP/2 multiplex
  rows:
  - worst throughput row:
    `h2_multiplexed_streams_s16`, `threads=4` (`-65.14%`)
  - worst p95 row:
    `h2_multiplexed_streams_s8`, `threads=4` (`+423.24%`)

That means the current regression is not explained by extra HTTP connection
opens or weaker connection reuse under required-kTLS.

### Phase Timing Instrumentation

The next visibility slice is now landed locally too:

- the native HTTP bench path records optional per-sample HTTP phase timing on
  the HTTP/2 client path
- transformed artifact summaries now carry aggregate
  `stream_acquire_wait_*` and `request_round_trip_*` timing
- the comparison helper now renders worst-row phase views plus a dedicated
  `HTTP Phase Timing` section

That sets up the next hosted rerun to answer a sharper question than either
the transport counters or the connection section could answer:
whether the remaining hotspot is dominated by stream-slot acquisition or by
the post-acquire request round trip.

### Hosted Phase Timing Result

That rerun has now landed as workflow run `24874338657` on commit `3d85b51`,
and it closed the stream-acquire hypothesis:

- stream acquire wait stayed effectively flat on the same hotspot rows:
  - worst throughput row:
    `h2_multiplexed_streams_s4`, `threads=4`
    (`stream acquire wait avg 0.00 -> 0.00`, `stream acquire wait p95 0.00 -> 0.00`)
  - worst p95 row:
    `h2_multiplexed_streams_s8`, `threads=1`
    (`stream acquire wait avg 0.01 -> 0.01`, `stream acquire wait p95 0.00 -> 0.12`)
- the visible regression sits in the post-acquire request path instead:
  - worst throughput row:
    `h2_multiplexed_streams_s4`, `threads=4`
    (`request round trip avg 18.20 -> 31.72`, `request round trip p95 27.11 -> 29.99`)
  - worst p95 row:
    `h2_multiplexed_streams_s8`, `threads=1`
    (`request round trip avg 32.49 -> 49.68`, `request round trip p95 39.13 -> 70.01`)

That means the next useful instrumentation slice is inside the HTTP/2 request
path itself, not in connection reuse or stream-slot acquisition.

### Request-Path Phase Split Instrumentation

That next visibility slice is now landed locally too:

- the HTTP/2 bench path now records request enqueue timing
- it separately records response-header wait and response-body drain timing
- the comparison helper now renders those deeper request-path sub-phases in
  the `HTTP Phase Timing` section and worst-row phase views

That sets up the next hosted rerun to answer the remaining narrow question:
whether the post-acquire regression is concentrated in request upload,
response-header wait, or response-body drain.

### Hosted Request-Path Phase Split Result

That rerun has now landed as workflow run `24875528924` on commit `a88a8b7`,
and it narrowed the regression to the HTTP/2 response-body drain:

- the same row is now both the worst throughput and worst p95 hotspot:
  `h2_multiplexed_streams_s8`, `threads=1`
- the non-body phases stayed effectively flat there:
  - `stream acquire wait avg 0.05 -> 0.02`
  - `request enqueue avg 0.04 -> 0.06`
  - `response headers wait avg 28.65 -> 28.52`
- the body-drain portion exploded instead:
  - `response body read avg 7.86 -> 58.91`
  - `response body read p95 14.11 -> 467.44`
  - `request round trip p95 52.96 -> 512.05`

That means the next useful slice is not another generic phase split. It is a
response-body-drain probe that can separate first-body-byte delay from the
tail of the body read and capture the chunk shape the client actually sees.

### Response-Body Drain Instrumentation

That next probe is now landed locally too:

- the HTTP/2 bench path now records:
  - response-body first-chunk wait
  - post-first-chunk tail-read time
  - observed body chunk count
  - observed first-chunk bytes
- the comparison helper now renders those signals in the worst-row phase view
  and a dedicated `HTTP Response-Body Diagnostics` section
- rerendering historical hosted artifact `24875528924` stays backward
  compatible; the new fields show `n/a` there because that bundle predates the
  added metrics

That means the next hosted rerun can finally distinguish a first-body-byte
stall from a sustained drain-tail regression and also show whether the client
observes a materially different chunk shape under required-kTLS.

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
  session tickets suppressed while the prototype remains intentionally narrow

## Recommended Next Milestone

Keep the current Linux-only prototype stable and target the now-confirmed
HTTP/2 multiplex hotspot with more focused diagnostic reruns instead of adding
blind generic instrumentation:

- preserve the existing opt-in runtime path and strict Linux validation gate
- keep secure WAMP coverage as supplemental evidence, but use the HTTP/2
  comparison run as the primary required-kTLS performance signal
- keep the generated benchmark artifacts summarizing headline wins, losses,
  worst regressions, grouped workload/runtime hotspots, CPU / wall-time / RSS
  deltas, and transport-counter deltas so one hosted run answers the tuning
  question directly
- use run `24869856621` as the baseline for any deeper Linux-side
  instrumentation or tuning, then use focused run `24870980724` as the first
  workload-shape baseline for `h2_multiplexed_streams`
- keep the comparison helper capturing `/proc/net/tls_stat` sidecars and
  summarizing the Linux TLS session-open and decrypt/rekey deltas, because
  that is the cheapest hosted-run signal for "did required-kTLS actually stay
  on the kernel path cleanly?" before escalating to heavier diagnostics
- use the new manual diagnostic controls and
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` for the next hosted
  rerun, with an explicit scenario policy once thresholds are understood or
  `skip_artifact_gate=true` while the run is still purely investigative
- rerun the focused multiplex-scaling workflow on a clean head with the now
  landed response-body-drain diagnostics so the comparison can separate
  first-body wait from sustained body drain and record the observed chunk
  shape on the worst rows

That is the smallest next milestone that improves decision quality without
pretending the remaining kTLS work is already a clear runtime bug.
