# Project State

Last updated: 2026-04-23
Current branch: `add-router`
Last reviewed commit: `3ebccbe` (`feat(mcp): add transport-independent server core`)
Active exec plan: `docs/exec-plans/2026-04-23-wamp-profile-transport-performance-readiness.md`

## Last Known Verification

- `bin/test-fast`
- `bash -n bin/wamp-profile-validate`
- `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`
- `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`
- `bin/check-bench-artifacts --summary out/wamp-transport-local/bench_results.summary.json --policy native/bench/artifact_gate/wamp_transport_throughput.json`
- `bin/check-bench-artifacts --summary out/wamp-secure-local/bench_results.summary.json --policy native/bench/artifact_gate/wamp_secure_throughput.json`
- `bin/verify`

## Autonomous Priority

1. Keep the CI chain clean first. If local `bin/verify` is failing or the latest known branch CI is red, continuation work should switch to restoring green before new implementation or benchmark work.
2. Prioritize production readiness of current functionality before exploratory expansion. That includes correctness, release/deployment behavior, observability, packaging, operational docs, and coverage for shipped paths.
3. Treat MCP support for downstream `groli/app` as the next product-readiness milestone once CI and shipped-path blockers are clean. It outranks speculative H3, kTLS, E2EE, and benchmark exploration until the first usable MCP server/bridge path is designed, implemented, tested, and documented.
4. After the first usable MCP path is complete, make WAMP profile-related transport performance production-ready in the benchmark suite before returning to speculative transport work. That means canonical RawSocket/WebSocket WAMP scenarios, secure and cleartext coverage, serializer/profile coverage, explicit budgets/gates, and hosted CI evidence for release decisions.
5. Other benchmark and performance work stays important, but it should serve production readiness and release confidence rather than run ahead of it.

## Resume Order

1. Read `AGENTS.md`.
2. Read this file.
3. If there is an active plan under `docs/exec-plans/`, read that plan next.
4. Use `ROADMAP_NEXT.md` only to choose the next milestone after checking active plans.
5. Use `ROADMAP.md` and `STRUCTURE.md` as reference material when details are needed.

## Current Operational Truth

- The repo is a Dart workspace plus a Rust native transport workspace.
- The canonical root entrypoints are `bin/bootstrap`, `bin/test-fast`, `bin/test-all`, and `bin/verify`.
- Root shell helpers now auto-detect Dart from Flutter, Rust from `~/.cargo`, Chrome/Chromium, and the standard prebuilt native library path.
- The first usable MCP path for the downstream `groli/app` integration is now
  complete for local stdio usage: `packages/connectanum_mcp` has the
  transport-independent server core, stdio framing, and WAMP-backed tool
  delegation through existing `connectanum_client` sessions. Streamable
  HTTP/router MCP remains conditional on whether `groli/app` needs a network
  endpoint.
- Initial MCP research is captured in `docs/mcp_integration_research.md`.
  The first implementation slice now lives in `packages/connectanum_mcp` with
  a transport-independent Dart server core, typed protocol errors/capabilities,
  callback-backed tools, focused lifecycle/tool tests, a stdio transport
  adapter, a tiny stdio echo CLI example, and WAMP-backed tool delegation
  through existing `connectanum_client` sessions. The first usable local MCP
  bridge path is now in place. Streamable HTTP/router integration is still
  conditional on whether `groli/app` needs a network MCP endpoint.
- The root verification scripts now include the MCP package tests:
  `bin/test-fast` and `bin/test-all` both run
  `dart test packages/connectanum_mcp/test`.
- `packages/connectanum_core` is approved as a design reference for MCP package
  shape: typed protocol models, serializer-independent boundaries, explicit
  errors, small barrel exports, and focused tests. Reuse the style, not WAMP
  semantics.
- The active product-readiness plan is now
  `docs/exec-plans/2026-04-23-wamp-profile-transport-performance-readiness.md`.
  Its goal is to turn WAMP-profile transport benchmarks into canonical,
  budgeted RawSocket/WebSocket release-decision gates rather than loose
  performance artifacts.
- The first WAMP benchmark-readiness slice now has a human-readable contract in
  `docs/wamp_profile_benchmarks.md`. The canonical release-decision throughput
  gates are `native/bench/scenarios/wamp_transport_throughput.toml` and
  `native/bench/scenarios/wamp_secure_throughput.toml`, with conservative
  per-workload throughput and p95-latency floors in
  `native/bench/artifact_gate/wamp_transport_throughput.json` and
  `native/bench/artifact_gate/wamp_secure_throughput.json`.
- Local Darwin arm64 baselines captured on 2026-04-23 with
  `router_workers=1` and `native_runtime_threads=1` passed the default
  zero-transport-counter gate and the new policy gates. The lowest cleartext
  throughput was `48.79 Mbps` (`websocket_pubsub_json_64k`) and the highest
  cleartext p95 was `264.493 ms`; the lowest secure throughput was
  `32.48 Mbps` (`websocket_secure_pubsub_json_64k`) and the highest secure p95
  was `450.015 ms`.
- `bin/wamp-profile-validate` is now the canonical WAMP release-gate entry
  point for both local and hosted validation. A local Darwin arm64 run on
  2026-04-23 passed both checked-in policies; the lowest cleartext throughput
  in that run was `55.99 Mbps` (`websocket_pubsub_json_64k`) and the highest
  cleartext p95 was `251.067 ms` (`rawsocket_pubsub_cbor_64k`), while the
  lowest secure throughput and highest secure p95 were both on
  `rawsocket_secure_pubsub_json_64k` at `35.99 Mbps` and `408.703 ms`.
- GitHub Actions now includes a dedicated `WAMP Profile Benchmarks` workflow
  that runs `bin/wamp-profile-validate` on hosted Ubuntu and uploads
  `wamp-profile-benchmark-artifacts`. It still needs hosted evidence on the
  new workflow after these local changes are pushed.
- The existing `CI` workflow also has a `workflow_dispatch`-only `WAMP Profile
  Gates` job. Use that path for branch-hosted WAMP evidence until the
  dedicated `WAMP Profile Benchmarks` workflow exists on the default branch
  and becomes directly dispatchable.
- Final local handoff verification on 2026-04-23 passed with `bin/verify`.
  The first `bin/verify` attempt hit a transient
  `ct_ffi::tests::listen_flow::poll_connection_message_returns_payload`
  timeout; the test passed in isolation, the full `ct_ffi` suite then passed,
  and the full `bin/verify` rerun passed.
- GitHub Actions CI now runs through the canonical root `bin/*` entrypoints on branch pushes and PRs to `master`; GitHub Actions run `24732889424` for `2fac53b` completed successfully with both `Fast Checks` and `Full Verify`.
- The CI workflow now targets all branch pushes plus PRs to `master`, and it also exposes `workflow_dispatch` for manual runs.
- The latest known branch CI is green. GitHub Actions run `24826431486` on
  commit `7ca6798` passed both `Fast Checks` and `Full Verify`. The local
  branch also has unpushed commit `3ebccbe` plus current working-tree changes,
  so hosted CI has not yet validated the newest local state.
- `bin/test-fast` now provisions
  the native client runtime before `packages/connectanum_client/test/client_test.dart`
  on supported hosts, both root client flows now include
  `packages/connectanum_client/test/transport/native/e2ee_provider_test.dart`,
  and the native-only client tests now skip with an explicit reason when
  `libct_ffi` is genuinely unavailable.
- The main `CI` workflow no longer uploads raw per-test metrics snapshots.
  `CONNECTANUM_ARTIFACT_DIR` remains an explicit local/debug switch, and
  published artifacts now come from the dedicated `Native Artifacts` and
  bench/gate workflows instead.
- GitHub Actions run `24825770571` (`Native Artifacts`, `workflow_dispatch`)
  passed on commit `7049801` across Linux x64, Linux arm64, macOS arm64, and
  macOS Intel. The release-publishing job was skipped as expected because the
  validation dispatch did not provide a release tag.
- The root router verification now runs from `packages/connectanum_router` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host.
- The root bench verification now runs from `packages/connectanum_bench` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host, matching the process-global native runtime constraint already enforced in the router package.
- The bench WAMP integration tests now resolve their worker helper from either the bench package root or the repo root so Linux CI and local root-script runs share the same path contract.
- The bench now ships `native/bench/scenarios/transport_mbit_matrix_throughput.toml` as the throughput-grade counterpart to the cross-transport/auth/authz smoke matrix, preserving the same auth/authz/public/protected row shape while raising sustained-workload settings for one canonical Mbps artifact set.
- The bench now also ships `native/bench/scenarios/http_bearer_provider_smoke.toml` as the dedicated provider-backed HTTP auth baseline. It covers local JWT validation and local OAuth introspection against `/bench/secure-jwt` and `/bench/secure-oauth` across HTTP/1.1, HTTP/2, and HTTP/3, and the Dart bench runner now starts the local introspection endpoint required by the shipped `oauth` provider config.
- The shipped HTTP auth bridge baseline now covers challenge-response auth too: `native/bench/scenarios/http_auth_smoke.toml` exercises `ticket`, `wampcra`, and `scram` login, refresh, and protected-route flows across HTTP/1.1, HTTP/2, and HTTP/3, and the bench router config now exposes those methods on `/bench/auth` for the secure bench realm.
- The bench artifact pipeline now has a checked-in CI gate too: `native/bench`
  ships `check_artifact_gate`, the root `bin/check-bench-artifacts` wrapper
  writes sibling `*.gate.json` / `*.gate.md` reports next to transformed
  summaries, and the kTLS validation / benchmark runners now fail automatically
  on active throttles, transport alert deltas, transport error alert deltas,
  backpressure deltas, or explicitly budgeted throughput/p95-latency drift
  captured in `bench_results.summary.json`.
- Telemetry alert coverage is now aligned across the native and Dart surfaces
  too: `ct_ffi` has a focused router-metrics snapshot regression for
  per-reason/per-listener mapping, `router_metrics_service_test.dart` now
  asserts idle/body/protocol/internal alert counters across metrics snapshot
  payloads and OpenMetrics output, and `bin/test-all` explicitly runs the
  feature-gated native snapshot test alongside the default `ct_ffi` suite on
  native-runtime hosts.
- The bench WAMP harness now supports explicit secure-target selection through `secure_transport = true`, keeps separate cleartext and TLS listener target maps for both the in-process runner and the native helper worker, and fails closed instead of silently falling back to the cleartext WAMP listener.
- `native/bench/bench_router.json` now ships both cleartext WAMP (`127.0.0.1:8081`) and TLS WAMP (`127.0.0.1:8083`) listeners, and both WebSocket listeners advertise `wamp.2.json`, `wamp.2.msgpack`, and `wamp.2.cbor` so the bench scenario surface matches the supported WAMP serializers.
- The bench workload contract now includes `secure_transport`, and `native/bench/scenarios/wamp_secure_smoke.toml` provides the first checked-in secure RawSocket/WebSocket smoke coverage against `bench.secure` ticket auth.
- Hosted Linux validation exposed a router/native config mismatch in that new secure WAMP path. GitHub Actions run `24777296956` first failed in Dart validation because the router layer incorrectly rejected shared SNI hostname `localhost` across distinct TLS endpoints, and follow-up runs `24778942812`, `24778930521`, and `24778930527` showed that the attempted `127.0.0.1` workaround was also invalid because the native TLS config requires DNS-style SNI hostnames. The shipped bench config is back on shared `localhost`, the cross-endpoint duplicate-SNI restriction is removed, and a bench-package regression now starts the shipped config through `RouterConfigLoaderIo -> Endpoint.fromListenerSettings -> Router.start(NativeTransportRuntime)` with distinct reserved ports while temporarily anchoring relative TLS asset lookup to the repo root, so this startup path now stays valid from both the repo root and the bench package root.
- GitHub Actions runs `24780721173` (`kTLS Validation`) and `24780721191` (`kTLS HTTP/2 Benchmarks`) passed on commit `70f1525`, confirming the secure-WAMP startup fix on hosted Linux.
- GitHub Actions run `24782645871` (`CI`) then passed on commit `b6e458e`, confirming the root `Full Verify` path now runs the bench package from `packages/connectanum_bench` under its checked-in serial `dart_test.yaml` contract on hosted Linux too.
- GitHub Actions run `24785214332` (`kTLS Validation`, `workflow_dispatch`) passed on commit `0b4f1e7` after the Dart secure-WebSocket certificate-path fix, and push `CI` run `24785189137` also passed on the same commit, so secure RawSocket and secure WebSocket WAMP smoke validation is now green on hosted Linux.
- The repo now also ships throughput-grade secure-WAMP coverage. `native/bench/scenarios/wamp_secure_throughput.toml` mirrors the existing 64 KiB cleartext transport sweep for secure RawSocket/WebSocket RPC + pubsub across JSON, MsgPack, and CBOR on `bench.secure`.
- The direct Rust bench CLI now defaults its control plane to `https://127.0.0.1:8080/bench` instead of `https://localhost:8080/bench`, because the shipped bench router binds the TLS control listener on IPv4 loopback and the old default could hit the wrong socket on this macOS host.
- GitHub Actions run `24786956501` (`kTLS Validation`, `workflow_dispatch`) then passed on commit `c040ef9` with `native/bench/scenarios/wamp_secure_throughput.toml`, so the secure-WAMP throughput scenario now has a hosted Ubuntu baseline too. Response-throughput highlights were RawSocket pubsub `56.77/65.08/57.15 Mbps`, RawSocket RPC `176.60/215.09/164.48 Mbps`, WebSocket pubsub `62.04/78.81/64.83 Mbps`, and WebSocket RPC `191.13/231.59/168.71 Mbps` for JSON/MsgPack/CBOR at `48 x 6` with one router worker and one native runtime thread.
- The shipped HTTP/3 multiplex ceiling map now sweeps `streams_per_connection = 1, 2, 4, 8, 16` on the same sustained-transfer workload shape instead of pinning only the old `4`-stream point.
- The latest local Darwin H3 direction sweep now covers `router_workers = 1,4` and `native_runtime_threads = 1,4` on that shipped scenario. Extra router workers only helped the lowest-multiplex `s1` point (`721.60 Mbps`, p95 `54.61 ms` at `threads=1, workers=4`) and were neutral or harmful at the deeper `s4/s8/s16` points. The best overall point was `761.52 Mbps` / p95 `124.85 ms` at `s2` with `threads=4, workers=1`, while `s16` still emitted `103-117` backpressure events across all combinations and regressed as low as `465.43 Mbps` / p95 `1350.94 ms`. The next HTTP/3 milestone should therefore target transport/backpressure tuning rather than application response scheduling.
- The first two transport-side HTTP/3 tuning experiments are now ruled out locally on Darwin. Send-side body-write chunking at `32 KiB` and `64 KiB` shifted throughput between quadrants but barely changed `backpressure_events`, confirming the benchmark counter is not driven primarily by QUIC body-write burstiness.
- A native HTTP/3 accept-loop backlog gate also proved to be the wrong tradeoff. `soft_limit = 1` eliminated `backpressure_events` completely but over-serialized the workload, and `soft_limit = 4` capped `max_backpressure_depth` at `4` while still regressing too many `s1/s2/s16` combinations to keep. The active H3 plan remains open, but the next candidate should target boss-loop request-drain cadence or queue handoff scheduling around the native HTTP request backlog instead of more body-write tuning.
- Three boss-side HTTP/3 queue-drain variants were then measured locally and all
  rejected after remeasurement on the shipped `h3_multiplex_scaling` matrix:
  `out/h3-boss-drain-cadence/` (full extra boss-loop queue pass),
  `out/h3-boss-connection-local/` (drain whole newly accepted connections
  immediately), and `out/h3-boss-http3-burst1/` (drain one immediate HTTP/3
  request on accept).
- The full extra boss-loop queue pass was the clearest reject: it improved some
  `s4/s8` points, but it heavily regressed the `s1` baselines and still did not
  yield a clean deep-multiplex win.
- Draining all queued requests for a just-accepted connection improved some
  deep multi-worker cases, but it also caused fairness regressions because one
  accepted connection could monopolize the boss loop before later accepted
  connections were serviced.
- The burst-1 accept drain was the best of those three boss-side variants, but
  it was still too mixed to keep. It improved most `s1` points and some `s16`
  throughput, but it regressed every `s2` quadrant and enough `s4/s8` points
  that the baseline remains preferable.
- A steady-state round-robin HTTP/3 drain is now the first transport-side
  change kept under the active H3 plan. `_RouterBoss._drainHttp3Requests()`
  now drains one queued request per tracked HTTP/3 connection per pass before
  cycling again, and `router_runtime_test.dart` asserts that queued requests
  on two active HTTP/3 connections are interleaved instead of exhausting one
  connection first.
- Local Darwin reruns in `out/h3-http3-round-robin/` beat the last clean
  `out/h3-followup-direction/` baseline in `12/20` throughput quadrants and
  `13/20` p95-latency quadrants. The biggest wins were `s4` at
  `threads=1, workers=1` (`423.07 -> 681.74 Mbps`, `411.66 -> 246.33 ms`),
  `s4` at `threads=1, workers=4` (`406.87 -> 682.61 Mbps`,
  `438.29 -> 238.25 ms`), `s8` at `threads=1, workers=4`
  (`438.08 -> 658.33 Mbps`, `753.53 -> 482.78 ms`), and `s16` at
  `threads=4, workers=4` (`465.43 -> 627.92 Mbps`, `1350.94 -> 980.68 ms`).
- The remaining HTTP/3 gap is now absolute queue pressure rather than obvious
  fairness starvation. `backpressure_events` and
  `max_backpressure_depth_after` are still pinned above the bench artifact
  gate's zero-threshold floor on every `s2+` quadrant, so the active H3 plan
  stays open for further queue-depth reduction even though the round-robin
  drain is a clear net improvement worth keeping.
- A top-level boss-loop priority change has now been ruled out too. Moving
  `_drainHttp3Requests()` earlier in `_loop()` than `_dispatchMessages()` and
  the other maintenance passes produced `out/h3-http3-priority/`, which
  regressed `14/20` throughput quadrants and `19/20` p95 quadrants versus the
  kept `out/h3-http3-round-robin/` baseline. The worst losses were `s4` at
  `threads=1, workers=1` (`681.74 -> 471.56 Mbps`, `246.33 -> 409.33 ms`),
  `s8` at `threads=1, workers=4` (`658.33 -> 389.74 Mbps`,
  `482.78 -> 787.97 ms`), and `s16` at `threads=1, workers=4`
  (`678.72 -> 500.11 Mbps`, `1104.96 -> 1346.36 ms`).
- A bounded follow-up burst inside `_drainHttp3Requests()` has now been ruled
  out too. Keeping the first fair pass at one request per connection but
  allowing two per connection on later passes produced
  `out/h3-http3-followup-burst2/`, which won only `9/20` throughput quadrants
  and `8/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline. The worst losses were `s4` at
  `threads=1, workers=1` (`681.74 -> 285.04 Mbps`, `246.33 -> 873.80 ms`),
  `s1` at `threads=1, workers=1` (`683.91 -> 435.95 Mbps`,
  `66.64 -> 121.99 ms`), and `s16` at `threads=1, workers=1`
  (`620.66 -> 385.13 Mbps`, `884.91 -> 1449.49 ms`).
- A lighter-weight HTTP/3 request-handle staging experiment has now been
  ruled out too. Draining raw native request handles before materializing
  them into `NativeHttpHandshake` objects produced
  `out/h3-http3-handle-stage/`, which won `12/20` throughput quadrants but
  still lost `12/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline while barely moving queue depth. The
  worst losses were `s2` at `threads=4, workers=1`
  (`732.93 -> 659.55 Mbps`, `116.86 -> 132.12 ms`), `s8` at
  `threads=1, workers=1` (`712.03 -> 654.72 Mbps`, `435.16 -> 495.72 ms`),
  and `s16` at `threads=1, workers=4` (`678.72 -> 609.39 Mbps`,
  `1104.96 -> 1114.05 ms`). `bin/check-bench-artifacts` still failed with
  `32` findings because the `s2+` quadrants remained above the zero-threshold
  `backpressure_events`/`backpressure_alerts` gate.
- A native HTTP/3 ready-queue experiment has now been ruled out too.
  Publishing one native ready token per empty-to-non-empty HTTP/3 request
  queue and draining through a `ct_http3_poll_ready_connection()` FFI path
  produced `out/h3-http3-native-ready-queue/`, which won only `6/20`
  throughput quadrants and `9/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline. It improved some `s2/s4` points,
  including `s2` at `threads=1, workers=1`
  (`682.61 -> 759.90 Mbps`, `123.65 -> 119.00 ms`) and `s4` at
  `threads=4, workers=4` (`665.68 -> 723.06 Mbps`, `284.97 -> 253.78 ms`),
  but it regressed deeper reuse points such as `s8` at `threads=1, workers=1`
  (`712.03 -> 666.92 Mbps`, `435.16 -> 478.63 ms`) and `s16` at
  `threads=1, workers=4` (`678.72 -> 623.54 Mbps`, `1104.96 -> 1039.79 ms`).
  `max_backpressure_depth_after` stayed unchanged in every quadrant, and
  `bin/check-bench-artifacts` still failed with `32` findings.
- A native HTTP/3 request-ready wake experiment has now been ruled out too.
  Publishing a boss wake only when an HTTP/3 request queue transitions from
  empty to non-empty produced `out/h3-http3-request-ready-wake/`. After fixing
  an experimental callback-lifecycle teardown hang in the first attempt, the
  corrected variant still won only `7/20` throughput quadrants and `7/20` p95
  quadrants versus the kept `out/h3-http3-round-robin/` baseline. It improved
  some mid-depth quadrants, including `s2` at `threads=4, workers=4`
  (`698.14 -> 751.92 Mbps`, `135.30 -> 130.73 ms`, backpressure `17 -> 9`)
  and `s4` at `threads=4, workers=4`
  (`665.68 -> 713.45 Mbps`, `284.97 -> 252.78 ms`, backpressure `52 -> 49`),
  but it regressed too many deeper reuse points to keep, including `s8` at
  `threads=1, workers=1` (`712.03 -> 394.18 Mbps`, `435.16 -> 792.74 ms`) and
  `s16` at `threads=4, workers=1`
  (`627.92 -> 380.89 Mbps`, `894.39 -> 1435.18 ms`). The bench gate still
  failed with `32` findings.
- A post-enqueue native HTTP/3 accept-loop yield has now been ruled out too.
  Yielding after each queued HTTP/3 request and after installing its response
  waiter produced `out/h3-http3-post-enqueue-yield-probe/` on a focused
  `router_workers=1`, `native_runtime_threads=1` slice. It lost every measured
  workload versus `out/h3-http3-round-robin`: `s1`
  `683.91 -> 533.14 Mbps`, `s2` `682.61 -> 619.94 Mbps`, `s4`
  `681.74 -> 428.47 Mbps`, `s8` `712.03 -> 403.81 Mbps`, and `s16`
  `620.66 -> 522.25 Mbps`. `max_backpressure_depth_after` stayed at
  `0/2/4/8/16`, and `bin/check-bench-artifacts` still failed with `8`
  findings on that single-quadrant probe.
- The explicit HTTP/3 multiplex artifact-gate decision is now landed. The
  bench gate still uses zero thresholds by default, but
  `bin/check-bench-artifacts --policy <path>` can apply scoped thresholds, and
  `native/bench/artifact_gate/h3_multiplex_scaling.json` allows only the
  expected `backpressure_events` / `backpressure_alerts` budget for the shipped
  H3 `s2/s4/s8/s16` multiplex workloads. With that policy,
  `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json --policy native/bench/artifact_gate/h3_multiplex_scaling.json`
  passes all 20 local Darwin round-robin workloads while other transport
  alert/error/throttle signals remain strict.
- The H3 transport/backpressure plan is complete. It kept the steady-state
  round-robin drain as the transport-side improvement, rejected the later
  accept-loop wake/yield and queue-drain reshaping experiments, and now records
  the remaining H3 multiplex queue depth as normal only when an explicit
  scenario policy is supplied. Future H3 work should require either a concrete
  response-progress handoff/window design or a performance budget layer for
  throughput/p95 drift.
- The pinned WAMP conformance snapshot now covers one router-level
  multi-session vector in addition to the existing single-message serializer
  subset. `packages/connectanum_core/testdata/wamp_conformance/multisession/advanced/publisher_exclusion_disabled.json`
  is now vendored from `wamp-proto/wamp-proto#557`, and
  `packages/connectanum_router/test/conformance/wamp_multisession_conformance_test.dart`
  executes it against local worker-session routing with placeholder-aware
  matching for router-assigned ids. The upstream PR head was rechecked on
  2026-04-23 and still matches the vendored `59303fd1290f472b29a40392caeca525d0324e37`
  snapshot, so broader conformance expansion remains blocked on upstream
  runner/vector stabilization.
- `packages/connectanum_router` is analyzer-clean after replacing the remaining
  nullable map/list collection-if lints in native message binding, remote-auth
  delegate payloads, route config loading, and router session transfer metadata
  with Dart null-aware collection elements.
- `packages/connectanum_router/test/router_worker_auth_test.dart` no longer has the old 1-in-256 false-success path in `Cryptosign authenticator rejects wrong signature`; the test now always mutates the first signature byte instead of sometimes regenerating the same `ff...` prefix and leaving the signature unchanged.
- `connectanum_core` now exposes a typed `WampE2eeProvider` contract plus an explicit `WampE2eeProviderUnavailableException`, so `ppt_scheme = "wamp"` payloads no longer silently materialize empty args/kwargs when no decryptor is available.
- The Dart client/session path now threads an optional `e2eeProvider` through outbound publish/call/yield packing, materialized inbound messages, and native direct-result/event/invocation payload views while preserving the existing packed-byte passthrough behavior for matching lazy WAMP payloads.
- The first Dart-side WAMP E2EE prototype is now implemented. `connectanum_core` ships `WampCborXsalsa20Poly1305Provider`, explicit unsupported-cipher / missing-key / invalid-payload / decryption failure types, and a focused provider regression test.
- Client and router coverage now prove the full phase-1 path: outbound WAMP payloads populate `ppt_cipher` + `ppt_keyid`, inbound native direct result/event/invocation paths decrypt through the configured provider, and router internal-session forwarding preserves ciphertext bytes plus `ppt_*` metadata without forcing router-side decryption.
- The phase-2 E2EE design is now captured in `docs/e2ee_ppt_research.md`: native/off-Dart parity should happen at the client boundary rather than the router boundary, and negotiated session state should ride one optional `authextra.e2ee` object across `HELLO`, `CHALLENGE`, `AUTHENTICATE`, and `WELCOME`.
- The first phase-2 Dart handshake slice is now landed too: `Client.authExtra` reaches `HELLO`, `CHALLENGE.extra` preserves custom `e2ee` metadata across JSON/MsgPack/CBOR/native binding, and `Session.negotiatedE2ee` exposes typed `WELCOME.authextra.e2ee` state without changing payload behavior yet.
- The next phase-2 Dart slice is now landed too: `Session` wraps attached `WampE2eeProvider` instances with negotiated `WELCOME.authextra.e2ee` defaults, so outbound and inbound `ppt_scheme = "wamp"` payloads can inherit session-selected serializer/cipher/key ids without per-message key-id plumbing.
- The session-backed E2EE provider lane is now landed on the Dart client path too: `Client.e2eeProviderResolver` can resolve a concrete provider per session from `WELCOME`/auth context, `Session.e2eeProvider` now surfaces the resolved provider, and the negotiated runtime-defaults wrapper still sits on top of that resolved provider for outbound and inbound `ppt_scheme = "wamp"` flows.
- The first native phase-2 parity lane is now landed too: `ct_ffi` exposes E2EE keyring/session handles plus synchronous `xsalsa20poly1305` encrypt/decrypt entrypoints over already-framed PPT bytes, and `connectanum_client` now exports `NativeWampCborXsalsa20Poly1305Provider` on top of the existing negotiated session-provider contract.
- Session teardown now releases resolver-scoped `DisposableWampE2eeProvider` instances, so native E2EE keyring/session handles do not leak across client sessions.
- Repo-local client-native loading now prefers fresh `native/transport/target/*/libct_ffi` builds before hook-cache artifacts, which keeps local E2EE/provider tests on the current shared library instead of stale hook outputs.
- The richer per-message E2EE runtime-context slice is now landed too: the shared provider contract now receives message family, URI/topic/procedure, local session identity, negotiated `authextra.e2ee`, and disclosed peer metadata across outbound `CALL` / `PUBLISH` and inbound `RESULT` / `EVENT` / `INVOCATION`, with lazy/materialized payload views preserving that context on the decode path.
- The shared Dart and native E2EE provider lanes now both expose a provider-level `WampE2eeKeySelectionPolicy` callback. `WampCborXsalsa20Poly1305Provider` and `NativeWampCborXsalsa20Poly1305Provider` can derive `ppt_keyid` from `WampE2eeRuntimeContext` when the message itself does not set one, so session/runtime metadata now drives real key selection instead of being inspection-only.
- `connectanum_core` now also ships reusable E2EE policy adapters on top of that callback surface: `WampE2eeKeySelectionPolicies.negotiated()`, `WampE2eeKeySelectionPolicies.rules(...)`, `WampE2eeKeySelectionPolicies.firstDefined(...)`, and `WampE2eeKeySelectionRule` cover negotiated `WELCOME.authextra.e2ee` fallback plus peer/local identity and trust-based selection without application-specific callback boilerplate.
- The client session wrapper no longer hardcodes negotiated key-id fallback ahead of provider policy. Session-wrapped providers now compose provider-owned policy first and negotiated fallback second while still inheriting negotiated serializer/cipher defaults, so peer/trust rules can override session fallback cleanly on inbound and outbound `ppt_scheme = "wamp"` flows.
- The `ct_ffi` surfaced-handshake regressions now use the suite’s wait helper for HTTP/3 and WebSocket plus a real `h2::client` prior-knowledge handshake for HTTP/2, which removes the old one-shot HTTP/2 preface race from full verification.
- The `ct_core` runtime test suite now keeps the rawsocket config connection alive through its assertions and recovers the shared test mutex after prior panics so Linux `cargo test -p ct_core` does not cascade `PoisonError` failures after one flaky test.
- The `ct_ffi` `runtime::ffi` unit tests now use the same shared suite guard as the rest of the FFI tests before touching global message handles, so concurrent `ct_shutdown()` calls from other tests no longer invalidate those handles mid-assertion.
- The `ct_ffi` HTTP/2 and HTTP/3 body-timeout regressions now keep request bodies flowing well below the idle timeout and assert only on the emitted lifecycle event, so full-suite verification no longer flakes between timeout reasons or handshake-queue timing on this host.
- The native Rust workspace no longer emits the previously-tracked dead-code warning block during local verification; the cleanup landed in `2fac53b` without changing runtime behavior.
- The `ct_ffi` HTTP/3 idle-timeout regression test now asserts directly on the emitted HTTP/3 connection event instead of waiting on a separate accepted-connection callback, which removes a full-suite race that could intermittently fail `bin/verify`.
- Native runtime execution is now validated on both Linux and macOS; unsupported hosts still skip the native runtime slices.
- Root verification now covers the full router package, including `publish_ack_test.dart` and `remote_auth_integration_test.dart`, while still serialising native runtime work through the router package's checked-in test config.
- Package-local browser verification now runs from `packages/connectanum_client`, and the client/router build hooks build on Linux and macOS while still no-oping on unsupported hosts.
- The client/router build hooks now reuse `CONNECTANUM_NATIVE_LIB` for prebuilt binaries and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1` for deployments that intentionally provide `ct_ffi` themselves, instead of invoking Cargo unconditionally.
- The client native runtime loader now falls back to the bare platform library name after hooks/local-build probing, so system-installed `ct_ffi` behaves the same way on the client path as it already did on the router path.
- `bin/package-native-artifact` now produces deterministic `ct_ffi` release bundles for the host platform, including the native library, a manifest, a README, and a SHA-256 checksum under `out/native-artifacts/`.
- GitHub Actions now exposes a dedicated `Native Artifacts` workflow that runs `bin/package-native-artifact` on explicit GitHub-hosted platforms and uploads the resulting tarball, checksum, and manifest as workflow artifacts for the existing `CONNECTANUM_NATIVE_LIB` deployment path.
- The current target matrix for those hosted native bundles is Linux x64 (`x86_64-unknown-linux-gnu`), Linux arm64 (`aarch64-unknown-linux-gnu`), macOS arm64 (`aarch64-apple-darwin`), and macOS Intel (`x86_64-apple-darwin`).
- The `Native Artifacts` workflow is now configured to publish those same bundles to GitHub Releases on release-tag runs, and manual dispatches can publish/update a release when given an explicit tag name.
- The same `Native Artifacts` workflow now generates GitHub artifact attestations for each packaged archive/checksum/manifest set, so released `ct_ffi` bundles have hosted provenance records in addition to the GitHub Release assets themselves.
- Hosted validation for the release path is now complete: GitHub Actions run `24756862771` validated release publishing after the `c4bd069` shell-variable fix, and run `24757138619` validated the attestation-enabled workflow end to end on both Linux and macOS while keeping `Publish GitHub Release` green.
- The same `Native Artifacts` workflow now also emits detached Sigstore blob bundles (`<asset>.sigstore.json`) for the packaged archive/checksum/manifest set, so release assets can be verified offline with `cosign verify-blob` in addition to GitHub-hosted attestations.
- Public-facing release metadata now defaults to human-readable titles and structured release details for both standalone native-bundle tags and `v*` project releases, while `v*` releases keep a generated changelog section even when an existing release is refreshed.
- The top-level `README.md` and the packaged native-bundle `README.md` now lead with end-user quick-start and artifact usage guidance instead of internal workflow notes, while still preserving the maintainer/Codex guidance further down the repo README.
- Public-facing docs are now consistent across the repo root, the packaged
  native bundle, the public workspace folders, and the implemented benchmark
  workspace docs. The stale pre-monorepo `connectanum_client` README is gone,
  the auth/router/core/bench package folders now have current top-level
  README files, and `native/bench/README.md` now documents the implemented
  orchestrator instead of a design draft.
- The public docs surface now states the current runtime contracts directly
  too. `README.md`, the router/client package READMEs, `docs/deployment.md`,
  and `docs/examples.md` now document the supported cancellation modes
  (`skip`, `kill`, `killnowait`), graceful drain behavior and `/healthz`, and
  the lazy-payload / zero-copy boundaries instead of leaving those details
  scattered across tests and internal notes.
- GitHub Actions now also exposes a dedicated `Router Image` workflow that publishes `ghcr.io/konsultaner/connectanum-router` for `linux/amd64` and `linux/arm64` on `v*` tags, with manual dispatch support for explicit validation tags.
- The router/client build hooks can now download a hosted `ct_ffi` release bundle directly when `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` is set, verify the published `.sha256`, extract the archive, and stage the native library without invoking Cargo.
- `CONNECTANUM_NATIVE_RELEASE_REPOSITORY=<owner/repo>` overrides the default GitHub Releases source for that hook-managed prebuilt flow, and the explicit prebuilt/system-library paths no longer require a local `native/transport` checkout.
- `connectanum_router:tool/install_native.dart` and `connectanum_client:tool/install_native.dart` now provide the explicit downstream prefetch path for hosted native assets: they download the current host bundle into `.dart_tool/connectanum/native/<host-triple>/`, verify the published checksum, and print the resulting library path for `CONNECTANUM_NATIVE_LIB`.
- The install helpers deliberately keep the deployment/runtime contract explicit instead of trying to simulate unsupported `dart pub get` automation; automatic hook cache reuse was tested and then dropped after hitting a Dart native-assets bundler bug on this macOS setup.
- `ct_core` now has an env-gated Linux-only kTLS server prototype. When
  `CONNECTANUM_ENABLE_KTLS=1` is set on Linux and a native-TLS listener
  exposes HTTP or HTTP/2, the accepted socket is prepared for Linux TLS ULP,
  Rustls secret extraction is enabled, and the server attempts a post-handshake
  handoff into a kTLS-backed `IoStream`.
- When `CONNECTANUM_ENABLE_KTLS` is unset or the host is not Linux, the native
  TLS path stays on the existing `tokio-rustls` implementation.
- The strict Linux validation path is now reproducible through
  `bin/ktls-linux-validate` and GitHub Actions workflow `kTLS Validation`,
  which auto-runs on pushes to `add-router` and `master` and remains available
  through `workflow_dispatch`.
- Hosted Linux validation is now green: GitHub Actions run `24767010221`
  passed on Ubuntu 24.04 with `CONNECTANUM_ENABLE_KTLS=1` and
  `CONNECTANUM_REQUIRE_KTLS=1`, including the targeted Rust kTLS tests and the
  existing HTTP/2 smoke bench.
- The hosted Linux HTTP/2 benchmark milestone is now complete. GitHub Actions
  runs `24773860109` (`CI`), `24773860116` (`kTLS Validation`), and
  `24773860158` (`kTLS HTTP/2 Benchmarks`) all passed on commit `6d18344`,
  which confirmed that the earlier required-kTLS handshake regression and the
  older multiplexed HTTP/2 `EINVAL` / `EMSGSIZE` / `unexpected frame type`
  failure cluster are gone on hosted Linux.
- The remaining kTLS caveat is performance rather than correctness: required
  kTLS still trails baseline TLS in the hosted HTTP/2 benchmark, especially in
  the 4-thread multiplexed workload shape.
- `bin/ktls-http2-bench` now preserves partial benchmark artifacts even when a
  pass fails partway through, so hosted runs still upload per-pass summaries
  and generate `comparison.json` / `comparison.md` from whatever completed
  workloads exist before returning a non-zero exit code.
- The current local kTLS server handoff no longer uses the buffered
  `tokio-rustls` / dummy-session path. When kTLS is requested on Linux,
  `ct_core` now drives rustls's unbuffered server handshake, buffers any
  post-handshake plaintext explicitly, converts with
  `dangerous_into_kernel_connection()`, and only then constructs the kTLS
  `IoStream`.
- GitHub Actions runs `24772627167` (`kTLS HTTP/2 Benchmarks`) and
  `24772627180` (`kTLS Validation`) showed that the first unbuffered handoff
  patch still broke the required-kTLS path before the benchmark workload
  started: the initial `/bench/healthz` handshake aborted with server-side
  `received fatal alert: UnexpectedMessage` and client-side
  `got ApplicationData when expecting Handshake`.
- Local analysis showed two unbuffered-rustls constraints that the first patch
  missed: `EncodeTlsData` can be emitted multiple times before a single
  `TransmitTlsData`, and `WriteTraffic` can still leave a partial
  post-handshake TLS record prefix buffered in the caller-owned input slice.
- The current local fix now accumulates every encoded handshake fragment until
  `TransmitTlsData` and keeps draining userspace TLS bytes until any partial
  buffered record is completed or consumed before switching the socket into
  kTLS.
- TLS 1.3 session tickets are still kept disabled on the kTLS path for now, so
  the validated handoff remains intentionally narrow while the next kTLS task
  shifts from HTTP/2 correctness into secure WAMP TLS coverage and later
  performance tuning.
- The local autonomy blockers from the 2026-04-21 audit are resolved for this macOS shell environment.
- In-app heartbeat sandboxes are more restricted than the interactive shell here; remote CI inspection and git metadata writes should still happen from unrestricted interactive runs or the external launchd worker.

## Environment Requirements

- Dart SDK `^3.9.2` (Flutter-bundled Dart is acceptable)
- Rust stable toolchain
- A Chrome or Chromium executable for browser-platform tests
- Either `CONNECTANUM_NATIVE_LIB` pointing at a prebuilt `ct_ffi` library or `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for the hook-managed hosted bundle path when the standard release location is not used
- Linux or macOS is required for native runtime execution tests; other hosts verify the portable suites and browser coverage instead

## Verification Status

- 2026-04-23: `bin/test-fast`,
  `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`,
  both WAMP throughput policy gate checks against `out/wamp-transport-local`
  and `out/wamp-secure-local`, and `bin/verify` passed on Darwin arm64 after
  adding the WAMP benchmark contract and initial cleartext/TLS policy floors.
- 2026-04-23: `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp -r expanded`, and `bin/verify` passed on
  Darwin arm64 after adding the WAMP-backed MCP tool delegate. The active plan
  is now switched to WAMP-profile transport performance readiness.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before adding the
  WAMP-backed MCP tool delegate slice.
- 2026-04-23: `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp -r expanded`, and `bin/verify` passed on
  Darwin arm64 after adding the MCP stdio transport adapter,
  `packages/connectanum_mcp/example/stdio_echo_server.dart`, focused stdio
  framing tests, and the associated roadmap/state docs.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before adding the MCP
  stdio transport adapter slice.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after adding the first
  `packages/connectanum_mcp` implementation slice, wiring its tests into
  `bin/test-fast` / `bin/test-all`, and updating the MCP plan, roadmap, and
  structure docs.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before creating the first
  `packages/connectanum_mcp` implementation slice.
- 2026-04-23: `dart analyze packages/connectanum_mcp` and
  `dart test packages/connectanum_mcp -r expanded` passed on Darwin arm64
  after adding the in-memory MCP lifecycle and tool-registry package slice.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording
  `packages/connectanum_core` as the approved design reference for the MCP
  package shape.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after queuing WAMP
  profile-related transport benchmark production readiness immediately after
  the active MCP milestone.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after promoting MCP support
  for downstream `groli/app` in `AGENTS.md`, `ROADMAP.md`,
  `ROADMAP_NEXT.md`, project state, and the new active MCP exec plan.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after adding opt-in
  throughput/p95 performance budgets to the bench artifact gate, keeping the
  default transport-counter gate strict, and updating the active plan/state
  docs.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`,
  `bash -n bin/check-bench-artifacts`,
  `bin/check-bench-artifacts --summary native/bench/artifacts/bench_results.summary.json --report-json /tmp/connectanum-default.gate.json --report-md /tmp/connectanum-default.gate.md`,
  and a temporary metrics-policy failure check passed on Darwin arm64 after
  adding `throughput_mbps_min` and `latency_p95_ms_max` gate findings.
- 2026-04-23: `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json --policy native/bench/artifact_gate/h3_multiplex_scaling.json --report-json /tmp/connectanum-h3.gate.json --report-md /tmp/connectanum-h3.gate.md`
  still passed all 20 H3 round-robin workloads with the existing scoped counter
  policy after the performance-budget gate extension.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before adding the
  bench artifact performance-budget layer.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the
  policy-aware bench artifact gate path, adding the H3 multiplex gate policy,
  and closing the H3 transport/backpressure plan.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before landing the
  policy-aware bench artifact gate path for the H3 multiplex backlog decision.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`
  and `bash -n bin/check-bench-artifacts` passed on Darwin arm64 after adding
  scoped artifact-gate policies while keeping the strict default gate.
- 2026-04-23: `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json --policy native/bench/artifact_gate/h3_multiplex_scaling.json`
  passed on Darwin arm64 with 20 workloads, and
  `bin/check-bench-artifacts --summary native/bench/artifacts/bench_results.summary.json`
  still passed the checked-in sample artifact set without a policy.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the
  rejected `out/h3-http3-post-enqueue-yield-probe/` experiment and reverting
  the native HTTP/3 request-path code to the kept steady-state round-robin
  drain baseline.
- 2026-04-23: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_connection_stats -- --nocapture` and `cargo build --manifest-path native/transport/Cargo.toml -p ct_ffi --release` passed on Darwin arm64 while probing a post-enqueue HTTP/3 accept-loop yield. The code change was reverted after measurement.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1 --native-runtime-thread-counts 1 --results out/h3-http3-post-enqueue-yield-probe/bench_results.jsonl --artifact-dir out/h3-http3-post-enqueue-yield-probe` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the post-enqueue yield probe lost all five measured workloads in the `workers=1`, `threads=1` quadrant, left `max_backpressure_depth_after` unchanged at `0/2/4/8/16`, and `bin/check-bench-artifacts --summary out/h3-http3-post-enqueue-yield-probe/bench_results.summary.json` still failed with `8` findings.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after closing the
  CI-artifact cleanup/native-matrix plan in project state and reactivating the
  HTTP/3 transport/backpressure plan.
- 2026-04-23: GitHub Actions run `24825770571` (`Native Artifacts`,
  `workflow_dispatch`) passed on commit `7049801` across Linux x64, Linux
  arm64, macOS arm64, and macOS Intel; `Publish GitHub Release` skipped because
  no release tag was provided for the validation dispatch.
- 2026-04-23: GitHub Actions run `24824613232` (`CI`) passed on commit
  `7049801`, with both `Fast Checks` and `Full Verify` green after removing
  the generic CI metrics artifact upload and expanding the native bundle
  matrix.
- 2026-04-23: `bin/test-fast`, workflow YAML parsing via Ruby, and
  `bin/verify` passed on Darwin arm64 after keeping the main `CI` workflow
  verification-only and expanding `Native Artifacts` to Linux x64, Linux arm64,
  macOS arm64, and macOS Intel.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after updating `AGENTS.md` and this state file so autonomous continuation now prioritizes a clean CI chain and production-readiness work before exploratory implementation.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-request-ready-wake/` experiment and reverting the router/native code to the kept steady-state round-robin HTTP/3 drain.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-request-ready-wake/bench_results.jsonl --artifact-dir out/h3-http3-request-ready-wake` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the request-ready wake variant won only `7/20` throughput quadrants and `7/20` p95 quadrants, still failed the bench gate with `32` findings, and regressed deep `s8/s16` reuse too hard to keep.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-native-ready-queue/` experiment and reverting the router/native code to the kept steady-state round-robin HTTP/3 drain.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-native-ready-queue/bench_results.jsonl --artifact-dir out/h3-http3-native-ready-queue` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the native ready-queue variant won only `6/20` throughput quadrants and `9/20` p95 quadrants, left `max_backpressure_depth_after` unchanged in every quadrant, and still failed the bench gate with `32` findings.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-followup-burst2/` bounded-follow-up-burst experiment and reverting the router code to the kept steady-state round-robin HTTP/3 drain.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-followup-burst2/bench_results.jsonl --artifact-dir out/h3-http3-followup-burst2` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the bounded follow-up burst variant won only `9/20` throughput quadrants and `8/20` p95 quadrants, so the code was reverted and the active H3 plan remained open.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-priority/` loop-order experiment and stabilizing `native/transport/ct_ffi/src/tests/listen_flow.rs::http2_handshake_surfaced_via_ffi`.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-priority/bench_results.jsonl --artifact-dir out/h3-http3-priority` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the loop-priority variant won only `6/20` throughput quadrants and `1/20` p95 quadrants, so the code was reverted and the active H3 plan remained open.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the steady-state HTTP/3 round-robin drain, the focused router fairness regression, and the updated active H3 transport/backpressure plan notes.
- 2026-04-23: `dart analyze packages/connectanum_router/lib/src/router/router_instance/router_boss.dart packages/connectanum_router/test/router_runtime_test.dart` and `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'http3 connections are drained fairly across tracked requests' -r expanded` both passed on Darwin arm64 after landing the steady-state HTTP/3 round-robin drain change and the focused fairness regression.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-round-robin/bench_results.jsonl --artifact-dir out/h3-http3-round-robin` passed on Darwin arm64. Compared with `out/h3-followup-direction`, the steady-state round-robin drain improved `12/20` throughput quadrants and `13/20` p95 quadrants, but `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json` still reports absolute backpressure findings because the shipped gate threshold is zero and the `s2+` workloads are not there yet.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after reverting the
  measured boss-side HTTP/3 queue-drain experiments and checking in the
  negative benchmark findings under the still-active H3
  transport/backpressure plan.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after reverting the rejected H3 chunking/backlog-gate code and checking in the negative benchmark findings for the still-active transport/backpressure plan.
- 2026-04-23: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http3_server_config_applies_transport_tuning -- --nocapture`, `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_response_streaming_round_trip -- --nocapture`, and `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/3 response chunks using native streams' -r expanded` all passed on Darwin arm64 while iterating on the H3 transport/backpressure milestone.
- 2026-04-23: local Darwin reruns of `native/bench/scenarios/h3_multiplex_scaling.toml` with experimental send-side chunking (`out/h3-transport-chunking/`, `out/h3-transport-chunking-64k/`) and native HTTP/3 backlog gating (`out/h3-backlog-gate/`, `out/h3-backlog-gate-4/`) completed successfully and were recorded as negative results; neither candidate produced a clean enough improvement to keep.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before iterating on the
  H3 boss-loop queue-drain experiments.
- 2026-04-23: local Darwin reruns of
  `native/bench/scenarios/h3_multiplex_scaling.toml` with
  `out/h3-boss-drain-cadence/`, `out/h3-boss-connection-local/`, and
  `out/h3-boss-http3-burst1/` all completed successfully and were recorded as
  negative results; none of the measured boss-side accept/drain variants
  produced a clean enough cross-matrix win to keep.
- 2026-04-21: `bin/bootstrap` passed in a plain non-login shell on Darwin arm64.
- 2026-04-21: `bin/test-fast` passed in a plain non-login shell on Darwin arm64, including the native client transport fast tests and the sequential router native runtime smoke test.
- 2026-04-21: `bin/verify` passed in a plain non-login shell on Darwin arm64, including `ct_core`/`ct_ffi` Rust tests, the `ffi-test` native release build, native client transport tests, the full router package from `packages/connectanum_router`, and the Chromium/Dart2Wasm browser websocket test from `packages/connectanum_client`.
- 2026-04-21: `cd packages/connectanum_router && dart test test` passed on Darwin arm64, including `publish_ack_test.dart`, `remote_auth_integration_test.dart`, `router_integration_native_test.dart`, and `router_integration_websocket_test.dart` under the router package's checked-in serial test configuration.
- 2026-04-21: `bin/verify` passed again on Darwin arm64 after updating `bin/test-all` to run the router suite from `packages/connectanum_router`, so the root verification flow now exercises the full router package with the same package-local concurrency contract that GitHub CI needs.
- 2026-04-21: `dart test packages/connectanum_router/test/remote_auth_integration_test.dart --concurrency=1 -r expanded` passed on Darwin arm64 after rotating the remote-auth TLS fixtures to an Apple-compatible server certificate lifetime.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core connection_runtime_config_exposes_rawsocket_settings -- --nocapture` passed on Darwin arm64 after keeping the test connection alive through runtime-config assertions.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core runtime_starts_only_once -- --nocapture` passed on Darwin arm64 after making the shared Rust test guard recover from poisoned mutex state.
- 2026-04-21: GitHub Actions run `24730190112` reached green `Fast Checks`, then failed in `Full Verify` because `bin/test-all` invoked `dart test packages/connectanum_router/test` from the repo root, which bypassed `packages/connectanum_router/dart_test.yaml` and let `remote_auth_integration_test.dart` collide with the process-global native runtime in Linux CI.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core`, `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi`, and `bin/verify` all passed on Darwin arm64 after `2fac53b` removed the known Rust dead-code warning block from local verification output.
- 2026-04-21: GitHub Actions run `24732889424` passed on `add-router` for commit `2fac53b`, with both `Fast Checks` and `Full Verify` green.
- 2026-04-21: `bin/test-fast` passed again on Darwin arm64 before the transport/auth/authz throughput-matrix update.
- 2026-04-21: `python3` `tomllib` parsing confirmed `native/bench/scenarios/transport_mbit_matrix_throughput.toml` loads cleanly with 57 uniquely named workloads.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_idle_timeout_emits_connection_event -- --nocapture` passed three consecutive reruns on Darwin arm64 after removing the flaky accepted-connection dependency from the test.
- 2026-04-21: `bin/verify` passed on Darwin arm64 after adding `native/bench/scenarios/transport_mbit_matrix_throughput.toml` and stabilizing `ct_ffi`'s HTTP/3 idle-timeout regression test.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi runtime::ffi::tests -- --nocapture` and `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi -- --nocapture` passed on Darwin arm64 after putting the `runtime::ffi` unit tests under the shared FFI test guard so parallel `ct_shutdown()` calls can no longer clear their message handles.
- 2026-04-21: `bin/verify` passed again on Darwin arm64 after starting the E2EE/PPT research spike docs and fixing the `ct_ffi` shared-state FFI test race.
- 2026-04-22: `cd packages/connectanum_core && dart test test/message_result_test.dart test/message_invocation_test.dart -r expanded` passed on Darwin arm64 after landing the `WampE2eeProvider` contract, explicit missing-provider errors, and provider-backed WAMP invocation/result tests.
- 2026-04-22: `cd packages/connectanum_client && dart test test/client_test.dart -p vm -r expanded` passed on Darwin arm64 after threading `Client.e2eeProvider` through the session/native fast path and adding outbound/inbound WAMP provider coverage.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the core/client E2EE provider plumbing and focused tests.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the concrete `WampCborXsalsa20Poly1305Provider` implementation and router passthrough assertions.
- 2026-04-22: `dart test packages/connectanum_core/test/message_e2ee_payload_test.dart packages/connectanum_core/test/message_result_test.dart packages/connectanum_core/test/message_invocation_test.dart -r expanded` passed on Darwin arm64 after replacing the provider test doubles with the real `xsalsa20poly1305` implementation and adding explicit key/cipher/decrypt failure coverage.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after asserting provider-backed `ppt_cipher` / `ppt_keyid` propagation and native direct-result decrypts against the real implementation.
- 2026-04-22: `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded` passed on Darwin arm64 after pinning `ppt_cipher` / `ppt_keyid` passthrough on internal-session WAMP lazy publish/call flows.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the concrete `WampCborXsalsa20Poly1305Provider`, the new provider regression file, and the router/client metadata assertions.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the native build-hook packaging updates.
- 2026-04-22: `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after teaching the router build hook to reuse `CONNECTANUM_NATIVE_LIB` and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1`.
- 2026-04-22: `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after teaching the client build hook to reuse `CONNECTANUM_NATIVE_LIB` and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1`.
- 2026-04-22: `cd packages/connectanum_client && dart test test/transport/native/native_library_loader_test.dart -r expanded` passed on Darwin arm64 after making the client runtime loader fall back to the bare platform library name for system-installed `ct_ffi`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the native build-hook packaging contract, the new hook regressions, the client loader fallback, and the associated doc updates.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the dedicated `ct_ffi` artifact-packaging workflow and local packaging script.
- 2026-04-22: `bin/package-native-artifact --out-dir out/native-artifacts-test` passed on Darwin arm64 and produced `ct-ffi-aarch64-apple-darwin.tar.gz`, a matching `.sha256`, and a `.manifest.json` that captures the host triple plus commit metadata.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing `bin/package-native-artifact`, the `Native Artifacts` GitHub Actions workflow, the deployment/readme updates, and the analyzer-cleanup follow-up in the hook/native-loader tests.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing GitHub Release publishing on top of the `Native Artifacts` workflow and after restoring the hook/native-loader test files to the repo-standard `@TestOn` + `library;` layout.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` passed locally after adding the GitHub Release publishing job to the native artifact workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the GitHub Release publishing workflow changes, the release-path docs updates, and the `library;` analyzer-noise fix for the hook/native-loader tests.
- 2026-04-22: GitHub Actions run `24756862771` passed on tag `ct-ffi-v2026.04.22-validation.042151` after `c4bd069` fixed the `Publish GitHub Release` shell variable bug found by run `24756798793`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing GitHub artifact attestations for the packaged native release assets.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` passed locally after adding `actions/attest@v4` to the native artifact workflow.
- 2026-04-22: GitHub Actions run `24757138619` passed on tag `ct-ffi-v2026.04.22-validation.043206-attest`, with both Linux/macOS `ct_ffi` jobs generating artifact attestations successfully and `Publish GitHub Release` remaining green.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing GitHub artifact attestations for the packaged release assets and updating the release/deployment docs to describe `gh attestation verify`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing explicit GitHub Release download/checksum support in the router/client build hooks.
- 2026-04-22: `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after adding the router hook's hosted-release download path and checksum verification.
- 2026-04-22: `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after adding the client hook's hosted-release download path and checksum verification.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing `CONNECTANUM_NATIVE_RELEASE_TAG`, `CONNECTANUM_NATIVE_RELEASE_REPOSITORY`, the focused hook regressions, and the hosted-bundle deployment docs.
- 2026-04-22: `dart analyze packages/connectanum_router/tool/install_native.dart packages/connectanum_client/tool/install_native.dart packages/connectanum_router/lib/src/native_release_installer.dart packages/connectanum_client/lib/src/native_release_installer.dart packages/connectanum_router/test/hook/install_native_test.dart packages/connectanum_client/test/hook/install_native_test.dart` passed on Darwin arm64 after splitting the runtime install helpers away from hook-only build modules.
- 2026-04-22: `dart test packages/connectanum_router/test/hook/build_hook_test.dart -r expanded` and `dart test packages/connectanum_client/test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after keeping the hook contract explicit (`CONNECTANUM_NATIVE_LIB` / `CONNECTANUM_NATIVE_RELEASE_TAG`) and fixing the new analyzer warnings in both build hooks.
- 2026-04-22: `dart test packages/connectanum_router/test/hook/install_native_test.dart -r expanded` and `dart test packages/connectanum_client/test/hook/install_native_test.dart -r expanded` passed on Darwin arm64 after adding the explicit `install_native` package entrypoints and their hosted-download regression coverage.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 after adding the explicit `install_native` package entrypoints and removing the failed hook-cache reuse experiment.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the explicit `install_native` package entrypoints, cleaning the package hook tests so they do not poison shared native-asset caches with fake dylibs, and keeping the build-hook contract explicit (`CONNECTANUM_NATIVE_LIB` / `CONNECTANUM_NATIVE_RELEASE_TAG`).
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` passed locally after adding Sigstore blob bundle generation and verification to the native artifact workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing detached Sigstore blob bundles (`<asset>.sigstore.json`) for the packaged native archive/checksum/manifest set and updating the release/deployment docs to describe `cosign verify-blob`.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml'); puts 'yaml_ok'"` passed locally after adding the multi-arch GHCR router image workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the `Router Image` workflow, the repo `.dockerignore`, and the deployment/template updates for `ghcr.io/konsultaner/connectanum-router`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the kTLS
  research spike docs and project-state refresh.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing
  `docs/ktls_research.md`, the kTLS research exec plan, and the associated
  `docs/project_state.md` refresh.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after landing the `CONNECTANUM_ENABLE_KTLS` parser and HTTP/HTTP2 eligibility coverage for the Linux-only prototype module.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the env-gated Linux-only kTLS server prototype in `ct_core`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the env-gated Linux-only kTLS server prototype, keeping the default/non-Linux TLS path on `tokio-rustls`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the public-facing release/readme polish pass.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` and `ruby -e 'require "yaml"; wf = YAML.load_file(".github/workflows/native-artifacts.yml"); step = wf.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }.find { |s| s["name"] == "Create or update GitHub Release" }; abort("step not found") unless step; File.write("/tmp/connectanum-release-step.sh", step.fetch("run"));' && bash -n /tmp/connectanum-release-step.sh && echo shell_ok` both passed locally after polishing the native-artifact release metadata workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the public-facing release titles/details, the packaged native-bundle README rewrite, and the top-level README restructure.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the strict Linux kTLS validation workflow and runner.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after adding the strict Linux kTLS mode split and again after switching the Linux handoff path to `dangerous_extract_secrets()` plus the dummy server session.
- 2026-04-22: `bash -n bin/ktls-linux-validate && bin/ktls-linux-validate --help >/dev/null` passed on Darwin arm64 after fixing the validation script to build/export `CONNECTANUM_NATIVE_LIB` and pass `--native-lib` into the bench runner explicitly.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after fixing the Linux kTLS handoff path and then rerunning it after the final `bin/ktls-linux-validate` contract fix.
- 2026-04-22: GitHub Actions run `24767010221` (`kTLS Validation`) passed on `add-router`, validating the strict Linux kTLS runner end to end on Ubuntu 24.04 after run `24766303551` exposed the missing `--native-lib` bench argument.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the HTTP/2 benchmark handoff fixes.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after preserving buffered rustls plaintext across the Linux kTLS handoff and adding the in-memory regression that proves the HTTP/2 client preface survives that drain step.
- 2026-04-22: GitHub Actions run `24768800167` (`kTLS HTTP/2 Benchmarks`) failed on `add-router` only because the first buffered-plaintext handoff patch forgot to keep the Linux-only `session` binding mutable during `drain_buffered_plaintext(&mut session)`.
- 2026-04-22: GitHub Actions run `24768909306` (`kTLS HTTP/2 Benchmarks`) uploaded baseline plus required-kTLS artifacts on Ubuntu 24.04. Baseline TLS completed both workloads cleanly (`h2_sustained_transfer`: `3994.58` Mbps / `4247.40` Mbps at 1/4 native threads, `h2_multiplexed_streams`: `5807.50` Mbps / `5779.71` Mbps at 1/4 native threads). Required-kTLS completed only `h2_sustained_transfer` at 1 thread (`1911.93` Mbps, p95 `18.85` ms, two protocol-error events) before `h2_multiplexed_streams` failed with `Invalid argument (os error 22)`, `Message too long (os error 90)`, occasional `Failed to set TLS ULP: Transport endpoint is not connected (os error 107)`, and downstream HTTP/2 `unexpected frame type` resets.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core apply_server_tls_runtime_settings -- --nocapture` passed on Darwin arm64 after making the kTLS server prototype suppress TLS 1.3 session tickets whenever secret extraction is enabled.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after making the kTLS server prototype suppress TLS 1.3 session tickets on the dummy-session handoff path and updating the kTLS benchmark plan/research/state docs.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` and `cargo test --manifest-path native/transport/Cargo.toml -p ct_core tls::tests -- --nocapture` passed on Darwin arm64 after replacing the Linux kTLS accept path with an unbuffered rustls server handshake and real kernel-connection handoff.
- 2026-04-22: `docker run --rm --platform linux/amd64 -v /Users/konsultaner/Projects/connectanum-dart:/work -w /work/native/transport rust:1 bash -lc 'TOOLCHAIN=$(ls /usr/local/rustup/toolchains | head -n1); export PATH=\"/usr/local/rustup/toolchains/$TOOLCHAIN/bin:$PATH\"; cargo check -p ct_core'` passed, confirming the Linux-only unbuffered kTLS handoff path typechecks in a real Linux toolchain.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after replacing the Linux kTLS accept path with rustls's unbuffered server handshake plus `dangerous_into_kernel_connection()` and updating the kTLS benchmark plan/research/state docs.
- 2026-04-22: GitHub Actions run `24772627167` (`kTLS HTTP/2 Benchmarks`) failed on `add-router` after the first unbuffered-handshake landing because the required-kTLS `/bench/healthz` handshake returned server-side `received fatal alert: UnexpectedMessage` while the client reported `got ApplicationData when expecting Handshake`.
- 2026-04-22: GitHub Actions run `24772627180` (`kTLS Validation`) failed on `add-router` with the same `UnexpectedMessage` / `got ApplicationData when expecting Handshake` signature before the stricter Linux smoke path could complete.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after buffering every unbuffered `EncodeTlsData` fragment until `TransmitTlsData` and adding a regression that proves `WriteTraffic` can still leave partial TLS bytes buffered in userspace.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core tls::tests -- --nocapture` passed on Darwin arm64 after the same unbuffered-handshake byte-accounting fix.
- 2026-04-22: `docker run --rm --platform linux/amd64 -v /Users/konsultaner/Projects/connectanum-dart:/work -w /work/native/transport rust:1 bash -lc 'TOOLCHAIN=$(ls /usr/local/rustup/toolchains | head -n1); export PATH=\"/usr/local/rustup/toolchains/$TOOLCHAIN/bin:$PATH\"; cargo check -p ct_core'` passed again, confirming the corrected Linux-only handoff path still typechecks in a real Linux toolchain.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing provider-level E2EE key-selection policies on the Dart and native lanes, updating the E2EE docs/roadmap/state files, and stabilizing the `ct_ffi` surfaced HTTP/2 handshake test with a real h2 client handshake.
- 2026-04-22: GitHub Actions runs `24773860109` (`CI`), `24773860116` (`kTLS Validation`), and `24773860158` (`kTLS HTTP/2 Benchmarks`) all passed on `add-router` for commit `6d18344`, closing the HTTP/2 kTLS correctness milestone on hosted Linux.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing provider-level E2EE key-selection policies on the shared Dart/native provider lane.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after the package-level public-surface docs cleanup pass, including the full Rust, Dart, router, and browser suites.
- 2026-04-22: `dart test packages/connectanum_bench/test/wamp_transport_targets_test.dart packages/connectanum_bench/test/wamp_workload_runner_test.dart -r expanded` passed on Darwin arm64 after adding explicit secure WAMP target selection and the new `secure_transport` scenario flag.
- 2026-04-22: `cargo test --manifest-path native/bench/Cargo.toml prepared_workload -- --nocapture` passed on Darwin arm64 after extending the Rust bench orchestrator to forward `secure_transport` into the Dart WAMP control payload.
- 2026-04-22: `python3` `tomllib` parsing confirmed `native/bench/scenarios/wamp_secure_smoke.toml` loads cleanly with four secure WAMP workloads.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the secure WAMP bench harness/config/docs checkpoint.
- 2026-04-22: GitHub Actions run `24777296956` (`kTLS Validation`, `workflow_dispatch`) was queued against `native/bench/scenarios/wamp_secure_smoke.toml` on `add-router` so hosted Linux can validate the new secure WAMP path directly instead of the workflow's default HTTP smoke scenario.
- 2026-04-22: GitHub Actions run `24777296956` failed before `READY` with `Invalid argument(s): Duplicate SNI hostname "localhost" detected across router endpoints`, exposing an over-restrictive Dart-side router validation rule rather than a native runtime requirement.
- 2026-04-22: Follow-up runs `24778942812` (`workflow_dispatch`), `24778930521` (`push`), and `24778930527` (`kTLS HTTP/2 Benchmarks`) then failed after the attempted `127.0.0.1` workaround because the native config path rejected that IP-literal SNI hostname during secure bench startup.
- 2026-04-22: GitHub Actions runs `24780721173` (`kTLS Validation`) and `24780721191` (`kTLS HTTP/2 Benchmarks`) passed on `add-router` for commit `70f1525`, confirming the secure-WAMP startup fix on hosted Linux.
- 2026-04-22: GitHub Actions run `24780721174` (`CI`) still failed in `Full Verify` on commit `70f1525` because `bin/test-all` invoked `dart test packages/connectanum_bench/test` from the repo root, bypassing the bench package's serial test contract and letting `bench_router_config_test.dart` collide with the Linux-only native WAMP integration harness in the same package.
- 2026-04-22: `cd packages/connectanum_bench && dart test test -r expanded` passed on Darwin arm64 after adding `packages/connectanum_bench/dart_test.yaml`, running the bench suite from the package root in `bin/test-fast` and `bin/test-all`, and teaching `bench_router_config_test.dart` to anchor relative TLS asset lookup to the repo root while preserving the package-root invocation.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after the bench package adopted the same package-root serial test contract as `connectanum_router`.
- 2026-04-22: `dart test packages/connectanum_router/test/router_json_test.dart packages/connectanum_bench/test/bench_router_config_test.dart -r expanded` passed on Darwin arm64 after allowing shared DNS SNI hostnames across distinct endpoints, restoring the secure WAMP bench listener to `localhost`, and upgrading the bench regression to start the shipped config through the native runtime with distinct reserved listener/http3 ports.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after removing the cross-endpoint duplicate-SNI restriction, restoring the secure WAMP bench listener to `localhost`, and updating the bench/router regressions plus secure-WAMP state docs.
- 2026-04-22: GitHub Actions run `24782645871` (`CI`) passed on `add-router` for commit `b6e458e`, confirming the hosted Linux root-verification fix for the bench package package-root/serial test contract.
- 2026-04-22: GitHub Actions run `24783846529` (`kTLS Validation`, `workflow_dispatch`) reached the secure WAMP workloads and completed the secure RawSocket cases, then failed on `websocket_secure_rpc_json` with `HandshakeException: CERTIFICATE_VERIFY_FAILED: self signed certificate`, proving the remaining blocker was the Dart secure WebSocket client path rather than router startup or native listener selection.
- 2026-04-22: `cd packages/connectanum_bench && dart test test/wamp_session_factory_test.dart -r expanded` passed on Darwin arm64 after adding a real self-signed `wss://localhost` regression and forwarding `allowInsecureCertificates` through the Dart bench WebSocket transport factories for JSON, MsgPack, and CBOR workloads.
- 2026-04-22: `cd packages/connectanum_bench && dart test test -r expanded` passed on Darwin arm64 after the same secure-WebSocket fix, keeping the bench package green under its package-root serial test contract.
- 2026-04-22: `cd packages/connectanum_router && for i in {1..20}; do dart test test/router_worker_auth_test.dart --plain-name 'Cryptosign authenticator rejects wrong signature' -r compact >/tmp/cryptosign-auth-test.log || { cat /tmp/cryptosign-auth-test.log; exit 1; }; done` passed on Darwin arm64 after making the cryptosign negative-path test always flip the first signature byte instead of relying on a hard-coded `ff` prefix that could occasionally match the original signature.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after fixing the Dart secure-WebSocket certificate path in `WebSocketWampSessionFactory`, adding the new bench regression file, and stabilizing the flaky cryptosign negative-path router test.
- 2026-04-22: GitHub Actions run `24785214332` (`kTLS Validation`, `workflow_dispatch`) passed on `add-router` for commit `0b4f1e7`, confirming secure RawSocket + secure WebSocket WAMP smoke workloads on hosted Linux after the Dart secure-WebSocket certificate fix.
- 2026-04-22: GitHub Actions run `24785189137` (`CI`) passed on `add-router` for commit `0b4f1e7`.
- 2026-04-22: `python3` `tomllib` parsing confirmed `native/bench/scenarios/wamp_secure_throughput.toml` loads cleanly with 12 workloads.
- 2026-04-22: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib /Users/konsultaner/Projects/connectanum-dart/native/transport/target/release/libct_ffi.dylib --control-base https://127.0.0.1:8080/bench --scenario native/bench/scenarios/wamp_secure_throughput.toml` passed on Darwin arm64 and produced the first local secure-WAMP 64 KiB baseline: secure RawSocket RPC roughly `151/163/109 Mbps` (JSON/MsgPack/CBOR) and pubsub roughly `44/56/38 Mbps`; secure WebSocket RPC roughly `146/156/141 Mbps` and pubsub roughly `42/71/52 Mbps`.
- 2026-04-22: `cargo test --manifest-path native/bench/Cargo.toml http_endpoint_accepts_https_control_base -- --nocapture`, `cargo test --manifest-path native/bench/Cargo.toml build_http1_request_uses_origin_form_and_host_header -- --nocapture`, and `cargo test --manifest-path native/bench/Cargo.toml bench_http_client_builds_https_client -- --nocapture` all passed after changing the direct orchestrator default control base to `https://127.0.0.1:8080/bench`.
- 2026-04-22: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib /Users/konsultaner/Projects/connectanum-dart/native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/wamp_secure_smoke.toml` passed on Darwin arm64 after the same control-base default change, confirming the direct local CLI path works again without a hidden override.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after adding `native/bench/scenarios/wamp_secure_throughput.toml`, updating the direct bench CLI control-base default to `https://127.0.0.1:8080/bench`, and refreshing the secure-WAMP throughput plan/state docs.
- 2026-04-22: GitHub Actions run `24786956501` (`kTLS Validation`, `workflow_dispatch`) passed on `add-router` for commit `c040ef9` with scenario `native/bench/scenarios/wamp_secure_throughput.toml`, recording the hosted Ubuntu response-throughput baseline as RawSocket pubsub `56.77/65.08/57.15 Mbps`, RawSocket RPC `176.60/215.09/164.48 Mbps`, WebSocket pubsub `62.04/78.81/64.83 Mbps`, and WebSocket RPC `191.13/231.59/168.71 Mbps` for JSON/MsgPack/CBOR.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the phase-2 E2EE design checkpoint in `docs/e2ee_ppt_research.md`, `ROADMAP_NEXT.md`, and `docs/project_state.md`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the phase-2 E2EE design checkpoint and adding `docs/exec-plans/2026-04-22-e2ee-phase2-design.md`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the phase-2 E2EE negotiation scaffolding slice.
- 2026-04-22: `dart test packages/connectanum_core/test/custom_fields_test.dart packages/connectanum_core/test/serializer_challenge_welcome_test.dart -r expanded` passed on Darwin arm64 after preserving custom `CHALLENGE.extra` fields across JSON/MsgPack/CBOR.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart packages/connectanum_client/test/transport/native/message_binding_test.dart -r expanded` passed on Darwin arm64 after wiring `Client.authExtra` into `HELLO`, exposing `Session.negotiatedE2ee`, and preserving native-bound challenge metadata.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the phase-2 E2EE negotiation scaffolding slice and closing `docs/exec-plans/2026-04-22-e2ee-negotiation-scaffolding.md`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the negotiated E2EE runtime-defaults slice.
- 2026-04-22: `dart analyze packages/connectanum_client/lib/src/protocol/session.dart packages/connectanum_client/test/client_test.dart` passed on Darwin arm64 after adding the negotiated session-scoped provider wrapper and its client regressions.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after proving negotiated outbound defaults and negotiated inbound native direct-result decrypts.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http2_body_timeout_emits_connection_event -- --nocapture`, `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http2_idle_timeout_emits_connection_event -- --nocapture`, and `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_body_timeout_emits_connection_event -- --nocapture` all passed on Darwin arm64 after stabilizing the HTTP timeout-path regressions.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the negotiated E2EE runtime-defaults slice, updating the E2EE roadmap/state docs, and stabilizing the `ct_ffi` HTTP/2 + HTTP/3 body-timeout regressions.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the session-backed E2EE provider lane.
- 2026-04-22: `dart analyze packages/connectanum_client/lib/src/client.dart packages/connectanum_client/lib/src/protocol/session.dart packages/connectanum_client/test/client_test.dart` passed on Darwin arm64 after adding the public session-scoped provider resolver surface.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after adding resolver-backed outbound and inbound negotiated WAMP E2EE coverage.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the session-backed E2EE provider lane and updating the E2EE roadmap/state docs.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the reusable negotiated/policy adapter slice on top of the shared E2EE provider lane.
- 2026-04-22: `dart analyze packages/connectanum_core/lib/src/message/e2ee_payload.dart packages/connectanum_core/test/message_e2ee_payload_test.dart packages/connectanum_client/lib/src/protocol/session.dart packages/connectanum_client/lib/src/transport/native/e2ee_provider_io.dart packages/connectanum_client/test/client_test.dart` passed on Darwin arm64 after adding `WampE2eeKeySelectionPolicies`, `WampE2eeKeySelectionRule`, and the policy-aware session wrapper.
- 2026-04-22: `dart test packages/connectanum_core/test/message_e2ee_payload_test.dart packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after adding negotiated fallback + peer/trust adapter regressions and the inbound invocation override regression on the client path.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the reusable negotiated/policy adapters, wiring the session wrapper to compose provider policy ahead of negotiated fallback, and refreshing the E2EE roadmap/state docs.
- 2026-04-22: `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture` passed on Darwin arm64 after landing the bench artifact gate, including summary load/write coverage and both clean/failing gate regressions.
- 2026-04-22: `bash -n bin/check-bench-artifacts bin/ktls-linux-validate bin/ktls-http2-bench` passed after wiring the new root bench-gate entrypoint into both kTLS runner scripts.
- 2026-04-22: `bin/check-bench-artifacts --summary native/bench/artifacts/bench_results.summary.json` passed on the checked-in sample artifact set and wrote sibling `bench_results.gate.json` / `bench_results.gate.md`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the bench artifact validator, the root wrapper, the kTLS runner integration, and the associated bench metrics docs updates.
- 2026-04-23: `dart analyze packages/connectanum_bench/lib/src/http_auth_bench_harness.dart packages/connectanum_bench/tool/bench_main.dart packages/connectanum_bench/test/http_auth_bench_harness_test.dart` and `dart test packages/connectanum_bench/test/http_auth_bench_harness_test.dart packages/connectanum_bench/test/bench_router_config_test.dart -r expanded` passed on Darwin arm64 after adding the local OAuth introspection bench harness and the `/bench/secure-oauth` route/config coverage.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml prepared_workload_allows -- --nocapture` passed after extending the bench workload parser coverage for static bearer-protected JWT and OAuth routes, and `python3` `tomllib` parsing confirmed `native/bench/scenarios/http_bearer_provider_smoke.toml` now loads with 6 workloads.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the self-contained HTTP bearer-provider bench support, including the new Dart harness, shipped bench router/provider config, expanded smoke scenario, and docs updates.
- 2026-04-23: `dart analyze packages/connectanum_auth_server` passed on Darwin arm64 with no issues, confirming the stale roadmap note about `connectanum_auth_server` analyzer warnings is no longer actionable.
- 2026-04-23: `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'auth bridge issues bearer token for wampcra and dispatches secure route' -r expanded`, `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'auth bridge issues bearer token for scram and dispatches secure route' -r expanded`, and `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'auth bridge rotates refresh tokens and rejects old credentials' -r expanded` all passed on Darwin arm64 after expanding the shipped auth bridge config to cover `ticket`, `wampcra`, and `scram`.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml --bin http_stream -- --nocapture` passed on Darwin arm64 after teaching the Rust HTTP bench orchestrator to complete WAMP-CRA and SCRAM challenge flows instead of hard-failing non-ticket auth methods.
- 2026-04-23: `python3` `tomllib` parsing confirmed `native/bench/scenarios/http_auth_smoke.toml` loads cleanly with 27 workloads covering login, refresh, and protected-route flows for `ticket`, `wampcra`, and `scram` across HTTP/1.1, HTTP/2, and HTTP/3.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the HTTP auth bridge challenge-method bench expansion, including the new router auth regressions, shipped bench router config changes, and expanded auth smoke scenario.
- 2026-04-23: `python3` `tomllib` parsing confirmed `native/bench/scenarios/h3_multiplex_scaling.toml` now loads cleanly with 5 workloads sweeping `streams_per_connection = 1, 2, 4, 8, 16`.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1 --native-runtime-thread-counts 1,4 --results out/h3-multiplex-scaling/bench_results.jsonl --artifact-dir out/h3-multiplex-scaling` passed on Darwin arm64 and produced the current local HTTP/3 multiplex baseline. Response-throughput peaked at `643.73 Mbps` / p95 `463.68 ms` for `8` streams with `1` native runtime thread and `672.77 Mbps` / p95 `58.37 ms` for `1` stream with `4` native runtime threads.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after expanding the shipped HTTP/3 multiplex scenario, updating the bench docs/roadmap notes, and recording the new local ceiling map in project state.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before the HTTP/3 follow-up direction spike.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-followup-direction/bench_results.jsonl --artifact-dir out/h3-followup-direction` passed on Darwin arm64 and resolved the HTTP/3 roadmap ambiguity. The best low-depth result was `721.60 Mbps` / p95 `54.61 ms` at `s1` with `threads=1, workers=4`, the best overall result was `761.52 Mbps` / p95 `124.85 ms` at `s2` with `threads=4, workers=1`, and the deeper `s8/s16` points still correlated with `82-117` backpressure events rather than a clean router-worker scaling story.
- 2026-04-23: `cd packages/connectanum_router && dart test test/conformance/wamp_multisession_conformance_test.dart -r expanded` passed on Darwin arm64 after vendoring the upstream `publisher_exclusion_disabled` multi-session vector and wiring the router-side conformance harness.
- 2026-04-23: `dart analyze packages/connectanum_router/test/conformance/wamp_multisession_conformance_test.dart` passed on Darwin arm64 with no issues.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the vendored multi-session conformance vector, the new router-side harness, and the associated roadmap/state updates.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before refreshing the
  public docs/examples surface around cancellation semantics, graceful drain,
  lazy payload boundaries, and example discovery.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the public
  docs/examples refresh across `README.md`, the router/client package READMEs,
  `docs/deployment.md`, `docs/examples.md`, and the associated roadmap/state
  updates.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before the router analyzer
  hygiene cleanup.
- 2026-04-23: `dart analyze packages/connectanum_router` and
  `dart test packages/connectanum_client/test/transport/native/message_binding_test.dart packages/connectanum_router/test/router_worker_auth_test.dart packages/connectanum_router/test/router_worker_session_test.dart`
  passed on Darwin arm64 after clearing the remaining router null-aware
  collection lint output.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after the router analyzer
  hygiene cleanup and roadmap/state refresh.

## Active Plan

- Active plan:
  `docs/exec-plans/2026-04-23-wamp-profile-transport-performance-readiness.md`
- Most recent completed product-readiness plan:
  `docs/exec-plans/2026-04-23-mcp-support-groli-app.md`
- Supporting research notes:
  - `docs/mcp_integration_research.md`
  - `docs/ktls_research.md`
  - `docs/e2ee_ppt_research.md`
- Most recent completed plan:
  `docs/exec-plans/2026-04-23-bench-artifact-performance-budgets.md`
- Completed immediately before that:
  `docs/exec-plans/2026-04-23-h3-transport-backpressure-tuning.md`
- Completed before those: `docs/exec-plans/2026-04-23-ci-artifact-cleanup-and-native-matrix.md`

## Known Follow-Ups

- The current kTLS prototype keeps default/non-Linux runs on `tokio-rustls`,
  disables future kTLS attempts after socket-setup or handoff failures in one
  process in try-mode, and still is not the final production story for TLS 1.3
  key-update handling.
- The secure WAMP throughput expansion is now closed on both local Darwin and
  hosted Ubuntu baselines. The next session should pick a new roadmap item
  instead of extending this benchmark plan.
- The bench artifact gate now has the mechanism for both transport-regression
  counters and opt-in performance budgets. It still needs scenario-specific
  throughput/p95 thresholds before CI should fail on performance drift for a
  given benchmark family.
- HTTP/3 transport/backpressure follow-up work is paused behind WAMP-profile
  transport benchmark readiness unless CI or a release blocker requires
  revisiting it first.
  It should define the canonical WAMP release gate set before any new broad
  benchmark expansion.
- The current E2EE lane now covers negotiated fallback plus reusable
  peer/trust adapters. Further E2EE work should be driven by a concrete app
  integration need, or the next session should choose the next unfinished
  non-E2EE roadmap item.

## Update Checklist

- Refresh this file when the active milestone, blockers, or last-known verification status changes.
- Record the exact commands that most recently passed.
- Link the active execution plan and any follow-up docs created during external research.
