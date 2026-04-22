# Project State

Last updated: 2026-04-22
Current branch: `add-router`
Last reviewed commit: `1448315` (`feat(e2ee): apply negotiated runtime defaults`)
Active exec plan: none currently; choose the next milestone from `ROADMAP_NEXT.md`

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
- GitHub Actions CI now runs through the canonical root `bin/*` entrypoints on branch pushes and PRs to `master`; GitHub Actions run `24732889424` for `2fac53b` completed successfully with both `Fast Checks` and `Full Verify`.
- The CI workflow now targets all branch pushes plus PRs to `master`, and it also exposes `workflow_dispatch` for manual runs.
- The root router verification now runs from `packages/connectanum_router` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host.
- The root bench verification now runs from `packages/connectanum_bench` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host, matching the process-global native runtime constraint already enforced in the router package.
- The bench WAMP integration tests now resolve their worker helper from either the bench package root or the repo root so Linux CI and local root-script runs share the same path contract.
- The bench now ships `native/bench/scenarios/transport_mbit_matrix_throughput.toml` as the throughput-grade counterpart to the cross-transport/auth/authz smoke matrix, preserving the same auth/authz/public/protected row shape while raising sustained-workload settings for one canonical Mbps artifact set.
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
- `packages/connectanum_router/test/router_worker_auth_test.dart` no longer has the old 1-in-256 false-success path in `Cryptosign authenticator rejects wrong signature`; the test now always mutates the first signature byte instead of sometimes regenerating the same `ff...` prefix and leaving the signature unchanged.
- `connectanum_core` now exposes a typed `WampE2eeProvider` contract plus an explicit `WampE2eeProviderUnavailableException`, so `ppt_scheme = "wamp"` payloads no longer silently materialize empty args/kwargs when no decryptor is available.
- The Dart client/session path now threads an optional `e2eeProvider` through outbound publish/call/yield packing, materialized inbound messages, and native direct-result/event/invocation payload views while preserving the existing packed-byte passthrough behavior for matching lazy WAMP payloads.
- The first Dart-side WAMP E2EE prototype is now implemented. `connectanum_core` ships `WampCborXsalsa20Poly1305Provider`, explicit unsupported-cipher / missing-key / invalid-payload / decryption failure types, and a focused provider regression test.
- Client and router coverage now prove the full phase-1 path: outbound WAMP payloads populate `ppt_cipher` + `ppt_keyid`, inbound native direct result/event/invocation paths decrypt through the configured provider, and router internal-session forwarding preserves ciphertext bytes plus `ppt_*` metadata without forcing router-side decryption.
- The phase-2 E2EE design is now captured in `docs/e2ee_ppt_research.md`: native/off-Dart parity should happen at the client boundary rather than the router boundary, and negotiated session state should ride one optional `authextra.e2ee` object across `HELLO`, `CHALLENGE`, `AUTHENTICATE`, and `WELCOME`.
- The first phase-2 Dart handshake slice is now landed too: `Client.authExtra` reaches `HELLO`, `CHALLENGE.extra` preserves custom `e2ee` metadata across JSON/MsgPack/CBOR/native binding, and `Session.negotiatedE2ee` exposes typed `WELCOME.authextra.e2ee` state without changing payload behavior yet.
- The next phase-2 Dart slice is now landed too: `Session` wraps attached `WampE2eeProvider` instances with negotiated `WELCOME.authextra.e2ee` defaults, so outbound and inbound `ppt_scheme = "wamp"` payloads can inherit session-selected serializer/cipher/key ids without per-message key-id plumbing.
- The session-backed E2EE provider lane is now landed on the Dart client path too: `Client.e2eeProviderResolver` can resolve a concrete provider per session from `WELCOME`/auth context, `Session.e2eeProvider` now surfaces the resolved provider, and the negotiated runtime-defaults wrapper still sits on top of that resolved provider for outbound and inbound `ppt_scheme = "wamp"` flows.
- The next concrete E2EE implementation slice is now `ct_ffi` keyring/session parity on that same negotiated contract; router-side decryption is still intentionally out of scope.
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
- GitHub Actions now exposes a dedicated `Native Artifacts` workflow that runs `bin/package-native-artifact` on Linux and macOS and uploads the resulting tarball, checksum, and manifest as workflow artifacts for the existing `CONNECTANUM_NATIVE_LIB` deployment path.
- The `Native Artifacts` workflow is now configured to publish those same Linux/macOS bundles to GitHub Releases on release-tag runs, and manual dispatches can publish/update a release when given an explicit tag name.
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
- 2026-04-22: `bin/verify` passed on Darwin arm64 after fixing the unbuffered-handshake byte aggregation/pending-record bug and refreshing the kTLS benchmark plan/research/state docs.
- 2026-04-22: GitHub Actions runs `24773860109` (`CI`), `24773860116` (`kTLS Validation`), and `24773860158` (`kTLS HTTP/2 Benchmarks`) all passed on `add-router` for commit `6d18344`, closing the HTTP/2 kTLS correctness milestone on hosted Linux.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before the package-level public-surface docs cleanup pass.
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

## Active Plan

- Active plan: none currently; choose the next milestone from `ROADMAP_NEXT.md`
- Supporting research notes:
  - `docs/ktls_research.md`
  - `docs/e2ee_ppt_research.md`
- Most recent completed plan: `docs/exec-plans/2026-04-22-e2ee-session-provider-lane.md`
- Completed immediately before that: `docs/exec-plans/2026-04-22-e2ee-runtime-defaults.md`

## Known Follow-Ups

- The current kTLS prototype keeps default/non-Linux runs on `tokio-rustls`,
  disables future kTLS attempts after socket-setup or handoff failures in one
  process in try-mode, and still is not the final production story for TLS 1.3
  key-update handling.
- The secure WAMP throughput expansion is now closed on both local Darwin and
  hosted Ubuntu baselines. The next session should pick a new roadmap item
  instead of extending this benchmark plan.
- The next E2EE implementation work should add `ct_ffi` keyring/session handles
  and native encrypt/decrypt parity on top of the now-landed negotiated
  session-provider contract.

## Update Checklist

- Refresh this file when the active milestone, blockers, or last-known verification status changes.
- Record the exact commands that most recently passed.
- Link the active execution plan and any follow-up docs created during external research.
