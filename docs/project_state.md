# Project State

Last updated: 2026-04-28
Current branch: `add-router`
Last reviewed commit: `ad6412d` (`docs: correct router image release evidence`)
Active exec plan: `docs/exec-plans/2026-04-28-github-deployment-chain-readiness.md`

## Last Known Verification

- Current branch checkpoint `17697ae` is clean locally and hosted as of
  2026-04-28:
  - local CI-cleanup verification before commit `ce05721` covered shell syntax,
    focused Dart router/native tests, focused HTTP/3 ffi-test router tests,
    focused bench WAMP RawSocket integration, `bin/test-fast`, and
    `bin/verify`
  - commit `17697ae` updated the remaining artifact workflow actions to
    Node 24-backed `actions/upload-artifact@v7` and
    `actions/download-artifact@v8`
  - hosted GitHub push runs on `17697ae` completed successfully:
    `CI` `25039426534`, `kTLS Validation` `25039426508`,
    `WAMP Profile Diagnostics` `25039426526`, and
    `WAMP Profile Benchmarks` `25039426501`
  - kTLS validation log inspection confirmed the earlier Node 20 artifact
    deprecation warning is gone after the artifact action upgrade
  - `git status -sb` is clean on `add-router`
- Documentation checkpoint `649afcb` passed hosted GitHub `CI` run
  `25041573952`; `Fast Checks` and `Full Verify` completed successfully and
  `WAMP Profile Gates` were correctly skipped for the docs-only change.
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25042279631` completed
  successfully on clean head `649afcb` with isolated
  `h2_multiplexed_streams_s1`, `threads=4`:
  - result was decision-quality across 3 repeats
  - throughput delta span was `13.11pp`, with kTLS at `-47.86%..-34.75%`
  - p95 delta span was `22.98pp`, with kTLS at `-6.28%..+16.70%`
  - `response_headers_last_write_to_first_read` only moved materially in
    repeat 02, while the stable throughput gap stayed in
    `response_body_tail_read_avg_ms` after the first response-body chunk
- The bounded body-tail diagnostic split verifies locally:
  - `native/bench/src/bin/http_stream.rs` starts a second H2 client read probe
    after the first response-body chunk
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` summarize
    `response_body_tail_connection_read_wait_*` and
    `response_body_tail_connection_read_to_end_*`
  - `tool/ktls_http2_compare.py` and `tool/test_ktls_http2_compare.py` render
    and pin the new fields in the response-body diagnostics
  - local verification is green:
    `bin/test-fast`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `bin/verify`
- Commit `20dbc9a` passed the hosted GitHub push chain:
  - `CI` `25043856689`
  - `kTLS Validation` `25043856696`
  - `WAMP Profile Benchmarks` `25043856615`
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25044549578` completed
  successfully on `20dbc9a`, but was not decision-quality:
  - throughput delta span was `66.64pp`, with deltas `-53.21%`, `+13.43%`,
    and `-15.07%`
  - p95 delta span was within threshold at `25.96pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - repeat 01 showed kTLS body-side connection-read waits, repeat 02 was
    baseline-header-wait dominated, and repeat 03 was kTLS-header-wait
    dominated, so this hosted run is mixed noise rather than a clean answer
- The current follow-up slice makes those non-decision artifacts more readable:
  - `tool/ktls_http2_compare_repeats.py` adds a top-level
    `## Repeat Phase-Timing Focus` table
  - `tool/test_ktls_http2_compare.py` pins the new aggregate report fields
  - local focused verification is green:
    `bin/test-fast`,
    `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted run
    `25044549578`, and `bin/verify`
  - commit `d97d34f` (`tool: surface repeat phase timing focus`) passed
    hosted GitHub `CI` run `25045630570`
- The active autonomous focus is now the GitHub deployment chain. Continue H2
  or kTLS diagnosis only when it protects a deployment/release decision or after
  the GitHub release path is production-ready.
- Documentation commit `639c095` (`docs: prioritize github deployment chain`)
  passed hosted GitHub `CI` run `25046524665`; `Fast Checks` and
  `Full Verify` succeeded, while `WAMP Profile Gates` were correctly skipped
  for a docs-only push.
- The current deployment-chain implementation slice expands native release
  artifacts toward Windows:
  - `.github/workflows/native-artifacts.yml` adds a Windows x64 packaging
    runner and uses Bash for the packaging/signing shell steps
  - client/router build hooks now map Linux arm64 and Windows x64 release host
    triples
  - public deployment docs list Windows x64 as a release target
  - local checks are green for `bin/test-fast`, focused hook tests, workflow
    YAML parsing, and `git diff --check`
  - local macOS `cargo check --target x86_64-pc-windows-msvc` cannot complete
    because the Windows MSVC C headers/toolchain are unavailable locally; the
    GitHub Windows runner is the required validation signal
- Manual hosted `Native Artifacts` run `25047530571` on `9bfdee1` confirmed the
  Windows x64 job builds, packages, signs, and verifies the bundle, but failed
  in `actions/attest@v4` because the multiline `subject-path` was interpreted
  as one literal path on Windows. The current follow-up splits archive,
  checksum, and manifest attestations into separate single-subject steps.
- Manual hosted `Native Artifacts` run `25047880947` on `f26f358` confirmed the
  split attestation steps are valid on Linux and macOS, but Windows still could
  not resolve the Git Bash `/d/a/...` path inside the Node-based attestation
  action. The current follow-up keeps POSIX paths for shell/cosign and uses
  workspace-relative paths for `actions/attest` and `actions/upload-artifact`.
- Local `bin/verify` passed after the workspace-relative GitHub Actions path
  fix. The first local attempt failed only because the autonomous launchd runner
  held the shared native runtime lock during its own `bin/test-fast`; rerunning
  once the lock was released passed, including the Chrome browser-platform test.
- Hosted GitHub deployment-chain validation is clean on `86a4e7c`
  (`ci: use workspace-relative artifact paths`):
  - GitHub `CI` run `25048277995` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for this non-benchmark change as expected
  - manual `Native Artifacts` run `25048283917` passed all matrix legs:
    Linux x64, Linux arm64, macOS Apple Silicon, macOS Intel, and Windows x64
  - the Windows x64 leg now builds, packages, signs, verifies, attests, and
    uploads the `ct_ffi` bundle using workspace-relative paths for Node-based
    GitHub actions
- Documentation checkpoint `7a411e3`
  (`docs: record native artifact ci success`) passed hosted GitHub `CI` run
  `25049241654`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- The current deployment-chain slice adds a safe native-release dry-run path:
  - `.github/workflows/native-artifacts.yml` accepts manual
    `release_tag=<tag>` plus `dry_run=true`
  - dry-run publish jobs render the exact GitHub Release title, release notes,
    and asset list into a `native-release-preview` artifact, then exit before
    creating or updating a GitHub Release
  - `tool/render_native_release_notes.py` makes the release note body
    locally testable instead of depending on inline workflow shell only
  - focused local checks are green: `bin/test-fast`,
    `python3 -m py_compile tool/render_native_release_notes.py tool/test_render_native_release_notes.py`,
    `python3 tool/test_render_native_release_notes.py`,
    `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml')"`,
    a local render preview for `ct-ffi-v2026.04.28-preview`, and `bin/verify`
- Hosted GitHub validation is clean on `7b45ede`
  (`ci: add native release dry run`):
  - GitHub `CI` run `25050575954` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for this non-benchmark change as expected
  - manual `Native Artifacts` dry-run `25051217251` passed all native matrix
    legs: Linux x64, Linux arm64, macOS Apple Silicon, macOS Intel, and
    Windows x64
  - the dry-run publish job rendered the release metadata, uploaded
    `native-release-preview`, and stopped before release mutation
  - `gh release view ct-ffi-v2026.04.28-dry-run.7b45ede` returned
    `release not found`, confirming the dry-run path did not create or update a
    GitHub Release
- Documentation checkpoint `d3ecfd1`
  (`docs: record native release dry run validation`) passed hosted GitHub `CI`
  run `25051747670`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- The current installer-coverage slice aligns explicit `install_native.dart`
  host mapping with the hosted native release matrix:
  - `connectanum_client` and `connectanum_router` installer helpers now map
    Linux x64, Linux arm64, macOS x64, macOS arm64, and Windows x64 release
    triples
  - focused installer tests cover every hosted target mapping and unsupported
    host/architecture errors
  - local checks are green for `bin/test-fast`,
    `dart test packages/connectanum_client/test/hook/install_native_test.dart`,
    `dart test packages/connectanum_router/test/hook/install_native_test.dart`,
    and `bin/verify`
- Hosted GitHub validation is clean on `39e68b1`
  (`installer: cover native release artifact matrix`):
  - GitHub `CI` run `25052974513` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped inside the main CI workflow
  - GitHub `WAMP Profile Benchmarks` run `25052974498` passed the Linux
    canonical WAMP profile gate and uploaded its artifacts
- Documentation checkpoint `34cf2cd`
  (`docs: record installer ci success`) passed hosted GitHub `CI` run
  `25053975131`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- Native release/install validation is clean for validation prerelease
  `ct-ffi-v2026.04.28-validation.34cf2cd`:
  - manual GitHub `Native Artifacts` run `25054948537` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    `Publish GitHub Release` job
  - the release was created as a prerelease with the full hosted matrix asset
    set
  - direct source-checkout installer smoke validation passed on macOS arm64 via
    `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.34cf2cd`
- The validation exposed a public-instruction issue rather than a packaging
  failure: `dart run <package>:tool/install_native.dart` is not the reliable
  public install path because package runs invoke native build hooks before the
  helper can run. The current follow-up corrects README/deployment/release-note
  guidance to prefer `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for normal
  hook-managed downloads and direct `dart packages/.../tool/install_native.dart`
  only for source-checkout prefetches.
  - focused local checks passed:
    `python3 -m py_compile tool/render_native_release_notes.py tool/test_render_native_release_notes.py`,
    `python3 tool/test_render_native_release_notes.py`,
    `bash -n bin/validate-native-release-install`, `git diff --check`, and
    `bin/verify`
- Hosted GitHub validation is clean on `c925e1e`
  (`docs: clarify native release install path`):
  - GitHub `CI` run `25055877717` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped inside the main CI workflow
  - GitHub `WAMP Profile Benchmarks` run `25055877739` passed the Linux
    canonical WAMP profile gate and uploaded its artifacts
- Documentation checkpoint `51f7061`
  (`docs: record install path ci success`) passed hosted GitHub `CI` run
  `25056742848`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- Corrected native release notes and release publishing are validated on
  `51f7061`:
  - manual GitHub `Native Artifacts` dry-run `25057503370` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    preview publish job
  - the dry-run `native-release-preview` release notes documented
    `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for normal hook-managed downloads
    and direct `dart packages/.../tool/install_native.dart` commands only for
    source-checkout prefetches
  - `gh release view ct-ffi-v2026.04.28-dry-run.51f7061` returned
    `release not found`, confirming the dry-run path did not create or update a
    GitHub Release
  - manual GitHub `Native Artifacts` run `25057834597` created prerelease
    `ct-ffi-v2026.04.28-validation.51f7061` with 30 hosted matrix assets
  - the published prerelease targets commit
    `51f706179e9ec654639c19e170f38fd2d03573da`, is marked as prerelease, and
    contains the corrected public install instructions
  - source-checkout installer smoke validation passed via
    `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.51f7061`
- Native artifact publish-job log cleanliness is validated on `95837fb`
  (`ci: download native artifacts with gh`):
  - the publish job now downloads current-run `ct-ffi-*` artifacts through
    `gh run download` with explicit `actions: read` permission instead of
    `actions/download-artifact@v8`
  - the change removes the Node `Buffer()` deprecation warning previously
    emitted by the latest `actions/download-artifact` release during the
    `Download packaged artifacts` step
  - local checks passed: `bin/test-fast`, YAML parsing for
    `.github/workflows/native-artifacts.yml`, and `git diff --check`
  - hosted GitHub `CI` run `25059702813` passed `Fast Checks` and
    `Full Verify`; `WAMP Profile Gates` was skipped for the workflow-only push
  - manual GitHub `Native Artifacts` dry-run `25060480993` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    preview publish job using the `gh run download` path
  - the dry-run `native-release-preview` still listed all 30 expected release
    assets, and `gh release view ct-ffi-v2026.04.28-dry-run.95837fb` returned
    `release not found`
  - a hosted log scan found no `DeprecationWarning`, `warning:`, or
    `::warning` lines; the only match was a Cosign installer shell alias that
    contains the literal text `ERROR:`
- Documentation checkpoint `b63be66`
  (`docs: record native artifact warning cleanup`) passed hosted GitHub `CI`
  run `25061163684`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- The current release-safety slice adds an explicit pre-mutation gate for
  native GitHub Release publishing:
  - `.github/workflows/native-artifacts.yml` adds
    `stable_release_approval`, requiring manual non-prerelease release runs to
    type the `release_tag` exactly before any GitHub Release is created or
    updated
  - `tool/validate_native_release_intent.py` rejects malformed release tags,
    publishing of `-dry-run` tags, non-prerelease `-validation` publishes, and
    unapproved manual stable release publishes
  - focused local checks passed: `bin/test-fast`,
    `python3 -m py_compile tool/validate_native_release_intent.py tool/test_validate_native_release_intent.py`,
    `python3 tool/test_validate_native_release_intent.py`, workflow YAML
    parsing, representative validator CLI acceptance checks, `git diff --check`,
    and `bin/verify`
- Release-intent hosted validation is clean on `8dc966f`
  (`ci: guard manual stable native releases`):
  - GitHub `CI` run `25063769464` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for the workflow/tooling push
  - manual GitHub `Native Artifacts` dry-run `25063774771` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    preview publish job
  - the hosted `Validate release intent` step accepted
    `ct-ffi-v2026.04.28-dry-run.8dc966f` as `(native, dry-run)`
  - the preview metadata still listed all 30 expected native release assets,
    and `gh release view ct-ffi-v2026.04.28-dry-run.8dc966f` returned
    `release not found`
- The current CI-log cleanup slice suppresses expected rawsocket peer shutdown
  noise:
  - hosted CI on `8dc966f` exposed a passing-test line,
    `connection ConnectionId(...) io error: Connection reset by peer`, during
    the native RawSocket MsgPack cancel-cycle workload
  - `native/transport/ct_core/src/lib.rs` now uses the existing
    `is_benign_socket_shutdown` helper for rawsocket frame-reader IO errors,
    matching existing WebSocket shutdown classification for `UnexpectedEof`,
    `BrokenPipe`, `ConnectionReset`, and `ConnectionAborted`
  - focused local checks passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core websocket_io_disconnects_are_classified_as_peer_shutdowns -- --nocapture`
    and `bin/test-fast`; the local cancel-cycle fast-test segment no longer
    emitted the connection-reset line
- Rawsocket benign-shutdown log cleanup is hosted-clean on `6a6f036`
  (`native: quiet benign rawsocket shutdowns`):
  - local `bin/verify` passed end-to-end before commit
  - GitHub `CI` run `25065253852` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for this non-benchmark push path
  - GitHub `kTLS Validation` run `25065253836` passed
  - hosted log scanning found no `Connection reset by peer` or
    `connection ConnectionId` lines after the rawsocket reader started using
    `is_benign_socket_shutdown`
  - remaining `failed` matches were passing test names/result summaries, not
    failed checks
- CI-timeout hardening is hosted-clean on `ccb61f9`
  (`ci: bound github workflow runtimes`):
  - GitHub `CI` run `25066016309` passed `Fast Checks` but left
    `Full Verify` in progress for more than 30 minutes after the prior
    comparable full-verify job completed in about 9 minutes
  - the stale unbounded run was cancelled after the timeout-hardening slice
    started, so the next pushed head can provide the branch-cleanliness signal
  - the GitHub workflows now use job-level `timeout-minutes` so stuck runners
    fail closed instead of leaving branch status indefinitely pending
  - timeout budgets are intentionally generous relative to recent hosted runs:
    `Fast Checks` 20 minutes, `Full Verify` 45 minutes, WAMP/kTLS validation
    30-45 minutes, native artifact packaging 45 minutes, native publish 20
    minutes, and long manual image/kTLS benchmark jobs 120 minutes
  - local `bin/test-fast`, workflow YAML parsing, `git diff --check`, and
    `bin/verify` passed before commit
  - hosted GitHub push runs on `ccb61f9` passed:
    `CI` `25068442355`, `kTLS Validation` `25068442344`,
    `WAMP Profile Benchmarks` `25068442348`, and
    `WAMP Profile Diagnostics` `25068442381`
  - hosted log scanning found no `warning:`, `::warning`,
    `DeprecationWarning`, `Connection reset by peer`,
    `connection ConnectionId`, timeout, cancellation, or real error lines;
    remaining `failed` matches were passing test names or Rust test summaries
- Dart package publishing readiness is hosted-clean on `1b95c9d`
  (`docs: prepare dart package publishing`):
  - `bin/test-fast` passed before package metadata changes
  - every package now has a package-root MIT `LICENSE`, matching the repo
    license and satisfying pub.dev's mandatory package-root license check
  - package pubspecs now expose GitHub `homepage`, `repository`, and
    `issue_tracker` metadata for readable future package pages
  - `dart pub publish --dry-run` from `packages/connectanum_client` passes
    from a clean git state with `Package has 0 warnings`
  - `docs/dart_package_publishing.md` records the remaining product/deployment
    blocker: pub.dev currently returns `404` for both `connectanum_client` and
    `connectanum_core`, while `connectanum_client` depends on
    `connectanum_core: ^0.1.0`; real publishing still needs explicit package
    ownership, version, and publish-order decisions
  - local `bin/verify` passed after the package metadata/docs changes
  - hosted GitHub `CI` run `25071505471` passed and `WAMP Profile Benchmarks`
    run `25071505445` passed
  - hosted log scanning found no warnings, deprecations, rawsocket reset noise,
    timeouts, cancellations, or real errors; remaining matches were passing
    test names or Rust test summaries
- Documentation checkpoint `4b17fa6`
  (`docs: record package publish readiness ci`) passed hosted GitHub `CI` run
  `25072248218`:
  - `Fast Checks` and `Full Verify` completed successfully
  - `WAMP Profile Gates` was skipped because the docs-only push was not a
    manual benchmark dispatch
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were passing
    test names or Rust test summaries
- The current branch-protection/release-evidence slice adds a repeatable
  GitHub deployment-chain audit:
  - `bin/audit-github-deployment-chain --branch master --run-limit 4` reports
    that `master` is protected, requires one CODEOWNER review, disallows force
    pushes/deletions, has no repository rulesets, and currently has no required
    status checks
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 6`
    reports that `add-router` is unprotected and that the latest branch runs
    are hosted-clean through `CI` run `25072248218`
  - `docs/github_deployment_chain.md` records the branch-protection gap and the
    recommended minimum required checks: `Fast Checks` and `Full Verify`
  - no remote branch-protection setting was changed autonomously; applying
    required status checks remains an operator decision because it changes
    merge policy
  - local `bin/test-fast` passed before the audit script and evidence docs
    were added
  - local `bin/verify` passed after the audit script and evidence docs were
    added, including the Chrome browser-platform test
  - hosted GitHub `CI` run `25073711527` passed on `be37ec4`; `Fast Checks`
    and `Full Verify` succeeded, `WAMP Profile Gates` was skipped as expected
    for a non-manual run, and hosted log scanning found no real warnings,
    deprecations, rawsocket reset noise, timeouts, cancellations, or errors
- Documentation checkpoint `21a998d`
  (`docs: record github deployment audit ci`) passed hosted GitHub `CI` run
  `25074424163`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push. Hosted
  log scanning found no real warnings, deprecations, rawsocket reset noise,
  timeouts, cancellations, or errors.
- The current router-image release-evidence slice corrects an advertised
  public-artifact gap:
  - GitHub's workflow API does not expose `.github/workflows/router-image.yml`
    because the workflow file is not on the default branch
  - `gh workflow view router-image.yml --repo konsultaner/connectanum-dart`
    returns `404`, and the GitHub Packages API returns `404` for
    `ghcr.io/konsultaner/connectanum-router`
  - `README.md` and `docs/deployment.md` now describe the router image as a
    staged intended release target, not a currently published production
    artifact
  - `deploy/k8s/connectanum-router.yaml` now uses
    `ghcr.io/konsultaner/connectanum-router:replace-me` instead of `:latest`
    so the template no longer points at an unavailable floating production tag
  - `bin/audit-github-deployment-chain` now reports checked-in workflow
    visibility and GHCR router package visibility so this gap remains visible
    until the workflow/package are promoted and validated
  - focused checks passed: `bin/test-fast`, `bash -n
    bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --branch add-router --run-limit 2`,
    strict-mode failure smoke test for the known release-readiness gaps, and
    `git diff --check`
  - local `bin/verify` passed after the audit and public-documentation
    changes, including the Chrome browser-platform test
  - commit `ad6412d` (`docs: correct router image release evidence`) passed
    hosted GitHub `CI` run `25077069136`; `Fast Checks` and `Full Verify`
    succeeded, while `WAMP Profile Gates` was correctly skipped for the
    non-manual push. Hosted log scanning found no real warnings, deprecations,
    rawsocket reset noise, timeouts, cancellations, or errors; remaining
    matches were a passing bcrypt test name and Rust `0 failed` summaries.
- GitLab has not surfaced an `add-router` pipeline through the current API
  query, so GitHub Actions is the current visible hosted CI source for this
  branch.
- A same-workspace background process can still block local native-suite
  verification by holding the shared
  `${TMPDIR:-/tmp}/connectanum_native_runtime.lock` file.
  - The latest successful local `bin/verify` run required terminating a stale
    background Codex loop that was still running
    `packages/connectanum_bench/test/wamp_transport_integration_test.dart`
  - That was a local workspace-concurrency issue, not a repo regression
- Hosted GitHub push runs on `45fcba8` completed successfully:
  `CI` `24914678995`, `kTLS Validation` `24914678987`,
  `WAMP Profile Benchmarks` `24914678985`
- Hosted GitHub push runs on `1fa0c45` completed successfully:
  `CI` `24917321434`, `kTLS Validation` `24917321426`,
  `WAMP Profile Benchmarks` `24917321423`
- Hosted GitHub push runs on `4228983` completed successfully:
  `CI` `24919421672`, `kTLS Validation` `24919421664`,
  `WAMP Profile Benchmarks` `24919421657`
- Hosted GitHub push runs on `b551a6d` completed successfully:
  `CI` `24920276210`, `kTLS Validation` `24920276202`,
  `WAMP Profile Benchmarks` `24920276214`
- Hosted GitHub push runs on `355a117` completed successfully:
  `CI` `24921028426`, `kTLS Validation` `24921028397`,
  `WAMP Profile Benchmarks` `24921028403`
- Hosted GitHub push run on `5f79e40` completed successfully:
  `CI` `24921840775`
  - `kTLS Validation` and `WAMP Profile Benchmarks` were correctly skipped by
    their `push.paths` filters because `5f79e40` only changed report tooling
- Hosted GitHub push runs on `17697ae` completed successfully:
  `CI` `25039426534`, `kTLS Validation` `25039426508`,
  `WAMP Profile Diagnostics` `25039426526`, and
  `WAMP Profile Benchmarks` `25039426501`
  - `kTLS Validation` confirmed the artifact action warning is gone after the
    workflow action upgrade
- Hosted GitHub `CI` run `25041573952` completed successfully on `649afcb`.
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25042279631` completed
  successfully on `649afcb` and produced decision-quality isolated `s1`,
  `threads=4` evidence.
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24920655184` completed
  successfully on clean head `b551a6d`, but remained not decision-quality for
  isolated `h2_multiplexed_streams_s1`, `threads=4`:
  - throughput delta span `23.53pp` stayed within the stability threshold
  - p95 delta span `371.80pp` remained far above threshold and stayed on the
    kTLS side
  - the new header-path split narrowed the remaining gap to
    `response_headers_connection_read_wait`, while
    `response_headers_connection_read_to_headers`,
    `post_header_connection_read_wait`, and
    `connection_read_to_first_chunk` all stayed flat or nearly flat
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24921433741` completed
  successfully on clean head `355a117` and reached decision-quality for
  isolated `h2_multiplexed_streams_s1`, `threads=4`:
  - throughput delta span `20.81pp`
  - p95 delta span `15.55pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)` across all repeats
  - `response_headers_connection_write_wait` and
    `response_headers_connection_write_span` stayed small and flat enough that
    request-flush activity is no longer the lead suspect
- The current compare-report readability slice is green locally:
  - `bin/test-fast`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `tmpdir=$(mktemp -d /tmp/connectanum-ktls-rerender-XXXXXX) && python3 tool/ktls_http2_compare.py /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/baseline/bench_results.summary.json /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/ktls/bench_results.summary.json "$tmpdir/comparison.json" "$tmpdir/comparison.md"`
  - `bin/verify`
- The current isolated header-gap split is green locally:
  - `bin/test-fast`
  - `cargo test --manifest-path native/bench/Cargo.toml h2_last_write_to_first_read_gap_uses_last_write_boundary --bin http_stream -- --nocapture`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `tmpdir=$(mktemp -d /tmp/connectanum-ktls-rerender-XXXXXX) && python3 tool/ktls_http2_compare.py /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/baseline/bench_results.summary.json /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/ktls/bench_results.summary.json "$tmpdir/comparison.json" "$tmpdir/comparison.md"`
- The current workload-isolation methodology slice is green locally:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `python3 -m py_compile tool/filter_bench_scenario.py tool/test_filter_bench_scenario.py tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_filter_bench_scenario.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `python3 tool/filter_bench_scenario.py native/bench/scenarios/h2_ktls_multiplex_stability.toml /tmp/connectanum-ktls-filtered.toml h2_multiplexed_streams_s4,h2_multiplexed_streams_s8`
  - `bin/ktls-http2-bench --help | rg 'workloads|repeat-order|cooldown-seconds|repeat-count'`
  - `bin/verify`
- Hosted GitHub push run on `a2a66ea` completed successfully:
  `CI` `24913663589`
- Hosted GitHub push runs on `c0e9171` completed successfully:
  `CI` `24911914621`, `kTLS Validation` `24911914629`,
  `WAMP Profile Benchmarks` `24911914617`
- Hosted GitHub push runs on `d66a72d` completed successfully:
  `CI` `24910233897`, `kTLS Validation` `24910233859`,
  `WAMP Profile Benchmarks` `24910233901`
- Hosted GitHub push runs on `25b2b7a` completed successfully:
  `CI` `24902101047`, `WAMP Profile Benchmarks` `24902101976`
- Hosted GitHub push runs on `c21172f` completed successfully:
  `CI` `24903966470`, `kTLS Validation` `24903966478`,
  `WAMP Profile Benchmarks` `24903966456`
- Hosted GitHub push runs on `070b229` completed successfully:
  `CI` `24905612643`, `kTLS Validation` `24905612638`,
  `WAMP Profile Benchmarks` `24905612662`
- Hosted GitHub push runs on `a2e7f81` completed successfully:
  `CI` `24907299479`, `kTLS Validation` `24907299524`,
  `WAMP Profile Benchmarks` `24907299451`
- Manual hosted `kTLS HTTP/2 Benchmarks` reruns `24908173404` and
  `24908372116` both completed successfully on clean head `a2e7f81`, but they
  did not converge on a decision-quality result
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24906538797`
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24904942758`
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24903103241`

## Autonomous Priority

1. Keep the CI chain clean first. If local `bin/verify` is failing or the latest known branch CI is red, continuation work should switch to restoring green before new implementation or benchmark work.
2. Make the GitHub deployment chain the main project spine. Prefer GitHub
   Actions health, release workflow validation, multi-platform FFI artifacts,
   human-readable releases/artifacts, public package metadata, and branch
   protection/deployment evidence before speculative implementation work.
3. Prioritize production readiness of current functionality before exploratory expansion. That includes correctness, release/deployment behavior, observability, packaging, operational docs, and coverage for shipped paths.
4. Treat MCP support for downstream `groli/app` as the next product-readiness milestone once CI, GitHub deployment-chain blockers, and shipped-path blockers are clean. It outranks speculative H3, kTLS, E2EE, and benchmark exploration until the first usable MCP server/bridge path is designed, implemented, tested, and documented.
5. After the first usable MCP path is complete, make WAMP profile-related transport performance production-ready in the benchmark suite before returning to speculative transport work. That means canonical RawSocket/WebSocket WAMP scenarios, secure and cleartext coverage, serializer/profile coverage, explicit budgets/gates, and hosted CI evidence for release decisions.
6. With the first MCP path, the WAMP benchmark-readiness milestone, the
   host-supported WAMP transport-interop slice, and the worker-safe realm
   authorization milestone complete, use `ROADMAP_NEXT.md` to choose the next
   production-readiness task and keep prioritizing shipped-path correctness
   before speculative transport work.
7. Other benchmark and performance work stays important, but it should serve
   production readiness and release confidence rather than run ahead of it.

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
- GitHub Actions is the primary deployment-chain signal for autonomous work on
  this branch. Keep workflow warnings, skipped jobs, release artifacts, and
  public release metadata readable and intentional before returning to
  speculative transport diagnosis.
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
- Manual hosted rerun `24903103241` on clean head `25b2b7a` confirmed the
  main-isolate control-port optimization closed the old
  `direct_stream_request_queue_delay` hotspot on
  `h2_multiplexed_streams_s2`, `threads=1`.
- Manual hosted rerun `24920655184` on clean head `b551a6d` tightened the
  isolated `h2_multiplexed_streams_s1`, `threads=4` diagnosis:
  - repeat-level instability still sits in the client-side
    `response_headers_wait` path
  - the new header split showed the movement almost entirely in
    `response_headers_connection_read_wait`
  - `response_headers_connection_read_to_headers`,
    `response_body_post_header_connection_read_wait`, and
    `response_body_connection_read_to_first_chunk` stayed flat enough that
    header parsing and post-header body delivery are no longer the lead
    suspects
- Manual hosted rerun `24921433741` on clean head `355a117` resolved the
  write-side branch of that same isolated `s1` diagnosis:
  - the rerun is decision-quality instead of another noisy partial read
  - `response_headers_connection_write_wait` stayed around
    `0.04..0.07 ms`
  - `response_headers_connection_write_span` stayed around
    `0.18..0.19 ms`
  - those write-side metrics did not move with the repeat-level throughput or
    p95 deltas, so the remaining isolated `s1` gap is not explained by the
    client still flushing request bytes while waiting for response headers
- The bounded readability follow-up for that result is committed and
  CI-cleared as `5f79e40`:
  - `tool/ktls_http2_compare.py` renders the header-write metrics in
    `comparison.md`, not only in `comparison.json`
  - the phase focus lines now surface `response-header connection write` wait
    and span alongside the existing read-side diagnostics
  - the header diagnostics table now exposes those same fields so hosted
    artifacts are useful without opening raw JSON
- The next bounded split inside `response_headers_connection_read_wait` is
  committed and hosted-clean through `17697ae`:
  - the native bench summary records
    `response_headers_last_write_to_first_read_*`
  - that metric isolates the idle gap after the last request-side connection
    write and before the first response-side connection read during
    `response_headers_wait`
  - if the next isolated hosted `s1` rerun moves on that gap, the remaining
    instability is downstream of client flush completion and upstream of the
    first response read
- Manual hosted rerun `25042279631` on clean head `649afcb` showed that
  `response_headers_last_write_to_first_read` is not the stable throughput
  explanation:
  - repeat 02 moved on that header post-flush gap and on p95
  - repeats 01 and 03 stayed flat or improved on the header post-flush gap
  - the decision-quality throughput regression persisted across all repeats
    in `response_body_tail_read_avg_ms` after the first response-body chunk
- The bounded body-tail diagnostic split needed for the next hosted rerun is
  implemented and locally verified:
  - the bench records `response_body_tail_connection_read_wait_*`
  - the bench records `response_body_tail_connection_read_to_end_*`
  - the compare report renders both fields in the phase focus lines and the
    response-body diagnostics table
- That rerun also moved the remaining hotspot deeper into the HTTP/2 native
  response-stream path on `h2_multiplexed_streams_s8`, `threads=1`: server
  direct-stream timings improved, but client `response headers wait`,
  `response body first chunk wait`, and native
  `headers_to_first_connection_write` still regressed.
- The local HTTP/2 scheduler tuning lane reached a real hosted evidence limit
  on clean head `a2e7f81`.
- Two focused reruns on that same clean head produced different extreme
  outliers:
  - `24908173404` made `h2_multiplexed_streams_s4`, `threads=4` look like a
    huge kTLS win because baseline throughput collapsed to `868 Mbps`
  - `24908372116` instead made
    `h2_multiplexed_streams_s2`, `threads=4` the worst throughput and p95 row
- That means the next blocker is hosted benchmark stability, not another blind
  HTTP/2 scheduler tweak on top of `a2e7f81`.
- Manual hosted rerun `24904942758` on clean head `c21172f` showed the
  change was only half-right:
  - the old `h2_multiplexed_streams_s8`, `threads=1` hotspot improved sharply
    to `-13.12%` throughput / `+11.40%` p95
  - a new low-multiplex regression appeared on
    `h2_multiplexed_streams_s1`, `threads=1`
    with `-60.21%` throughput / `+124.86%` p95
  - that new worst row regressed on `response headers wait` while
    `response body first chunk wait` improved, which implicates the
    unconditional headers-side yield rather than the first-chunk yield
- That narrowed follow-up is now pushed as commit `070b229`
  (`perf(http2): keep yield on first streamed chunk only`), and its GitHub
  push chain completed successfully.
- Manual hosted rerun `24906538797` on clean head `070b229` showed the
  low-contention fix was real but incomplete:
  - `h2_multiplexed_streams_s1`, `threads=1` improved to
    `-14.98%` throughput / `+13.38%` p95
  - but `h2_multiplexed_streams_s2`, `threads=1` became the new worst
    throughput row at `-60.98%`
  - and `h2_multiplexed_streams_s16`, `threads=1` became the new worst p95 row
    at `+73.72%`
  - `h2_multiplexed_streams_s8`, `threads=1` regressed back to
    `-31.10%` throughput / `+42.83%` p95
- That outcome narrows the next local follow-up now on the working tree in
  `native/transport/ct_core/src/lib.rs`: keep the header-side yield only when
  multiple streamed responses have queued headers on the same HTTP/2
  connection, while still keeping the first-chunk yield.
- Focused local verification is green on that multiplex-aware follow-up:
  - `bin/test-fast`
  - `cargo test --manifest-path native/transport/ct_core/Cargo.toml http2_connection_write_tracker -- --nocapture`
  - `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
  - `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
  - `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
- That multiplex-aware follow-up is now pushed as commit `a2e7f81`
  (`perf(http2): yield on header contention only`).
- Its GitHub push chain completed successfully:
  - `CI` `24907299479`
  - `kTLS Validation` `24907299524`
  - `WAMP Profile Benchmarks` `24907299451`
- Manual hosted rerun `24908173404` completed successfully on the same head,
  but the result is not decision-quality:
  - `h2_multiplexed_streams_s4`, `threads=4` showed a baseline collapse to
    `868 Mbps` while adjacent rows stayed in-family
  - `h2_multiplexed_streams_s8`, `threads=4` inverted the other way with
    `-66.89%` throughput / `+423.33%` p95
  - that pattern is inconsistent with the prior hosted reruns and the local
    repro, so it is more likely host noise than a coherent regression shape
- Confirmatory rerun `24908372116` also completed successfully on clean head
  `a2e7f81`, but it shifted the outlier elsewhere instead of converging:
  - worst throughput row moved to
    `h2_multiplexed_streams_s2`, `threads=4` at `-83.11%`
  - worst p95 row also moved to
    `h2_multiplexed_streams_s2`, `threads=4` at `+1316.65%`
- The repeat-stability tooling is now pushed as commit `d66a72d`
  (`build(ktls): add repeat stability reporting`):
  - `bin/ktls-http2-bench` supports `--repeat-count <n>`
  - `.github/workflows/ktls-http2-benchmarks.yml` exposes the matching
    `repeat_count` input
  - `tool/ktls_http2_compare_repeats.py` aggregates repeated comparison files
    into a top-level repeat-stability report that marks the hosted evidence as
    decision-quality or not
- That commit's GitHub push chain completed successfully:
  - `CI` `24910233897`
  - `kTLS Validation` `24910233859`
  - `WAMP Profile Benchmarks` `24910233901`
- Focused manual hosted rerun `24911158486` completed successfully on the same
  clean head with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That repeat-stability artifact still marked the hosted evidence as not
  decision-quality:
  - worst throughput row changed across all three repeats
  - worst p95 row changed across all three repeats
  - `h2_multiplexed_streams_s4`, `threads=1` spanned `77.77pp` throughput
    delta
  - `h2_multiplexed_streams_s2`, `threads=1` spanned `1174.48pp` p95 delta
- The baseline side stayed relatively stable while the kTLS side did not:
  - `h2_multiplexed_streams_s2`, `threads=1` baseline throughput only spanned
    `470.25 Mbps`, while kTLS throughput spanned `3470.66 Mbps`
  - `h2_multiplexed_streams_s2`, `threads=1` baseline p95 only spanned
    `2.34 ms`, while kTLS p95 spanned `190.52 ms`
- The next bounded stabilization slice is now pushed as commit `c0e9171`
  (`build(ktls): add stability benchmark scenario`):
  - `native/bench/scenarios/h2_ktls_multiplex_stability.toml` keeps the same
    multiplex sweep but raises each workload to `48` iterations with
    `1000 ms` warmup for manual repeat runs
  - `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` stays unchanged as
    the quick diagnostic scenario
  - `native/bench/README.md` now separates quick diagnostic usage from
    decision-quality repeat usage
- Local verification was green before that push:
  - `bin/test-fast`
  - `bin/verify`
- Hosted GitHub push runs for `c0e9171` completed successfully:
  - `CI` `24911914621`
  - `kTLS Validation` `24911914629`
  - `WAMP Profile Benchmarks` `24911914617`
- Focused manual hosted rerun `24912748466` completed successfully on the same
  clean head with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That larger-sample rerun still did not reach decision quality, but it
  narrowed the instability sharply:
  - every remaining row that exceeded the stability thresholds used
    `native_runtime_threads=4`
  - the `native_runtime_threads=1` rows now fit within the current
    throughput/p95 span thresholds
  - `h2_multiplexed_streams_s16`, `threads=4` stayed the worst p95 row in
    `2/3` repeats, with p95 delta spanning `641.63pp`
  - `h2_multiplexed_streams_s4`, `threads=4` showed a baseline collapse in one
    repeat, producing a `228.53pp` throughput-delta span
- The next manual diagnostic step is therefore narrower than before:
  - rerun the same stability scenario with `native_runtime_thread_counts=4`
    only to determine whether the remaining instability is intrinsic to the
    `threads=4` lane or partly caused by mixing `1,4` in one hosted run
- Focused manual hosted rerun `24913116550` then completed successfully with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That isolated `threads=4` rerun still did not reach decision quality:
  - `h2_multiplexed_streams_s16`, `threads=4` remained the worst p95 row in
    `2/3` repeats, with p95 delta spanning `460.16pp`
  - `h2_multiplexed_streams_s2`, `threads=4` still showed a baseline collapse
    in one repeat, producing a `216.79pp` throughput-delta span
  - `h2_multiplexed_streams_s1`, `threads=4` also still showed baseline-side
    instability, with throughput delta spanning `124.79pp`
- The current blocker is now clearer:
  - isolating `threads=4` from `threads=1` did not make the hosted lane
    decision-quality
  - the next useful slice should change benchmark methodology or runner
    control, not the HTTP/2 transport path
- The current branch head now carries a bounded repeat-analysis slice on top of
  that blocker:
  - `tool/ktls_http2_compare_repeats.py` now labels each unstable row as
    baseline-side, kTLS-side, or mixed for throughput and p95 span sources
  - the repeat summary markdown now calls out the top instability-source
    highlights before the per-row table
  - `tool/test_ktls_http2_compare.py` pins that new classification and markdown
    output
- Local verification is green on that working tree:
  - `bin/test-fast`
  - focused Python compile/tests and repeat-summary rerenders against hosted
    runs `24912748466` and `24913116550`
  - `bin/verify`
- The new repeat-source labeling makes the hosted blocker more precise:
  - `h2_multiplexed_streams_s16`, `threads=4` is still primarily kTLS-side
  - `h2_multiplexed_streams_s2`, `threads=4` and `s1`, `threads=4` show
    baseline-side throughput instability
- That repeat-analysis slice is now pushed as commit `a2a66ea`
  (`build(ktls): label repeat instability sources`).
- The next branch-head slice now targets runner control rather than transport
  behavior:
  - `bin/ktls-http2-bench` now accepts `--repeat-order` and
    `--cooldown-seconds`
  - repeated runs now emit `repeat-plan.txt` so the artifact records the exact
    pass order and cooldown used for each repeat
  - the manual `kTLS HTTP/2 Benchmarks` workflow exposes the same controls and
    now defaults manual repeats to `repeat_order=alternating` and
    `cooldown_seconds=15`
  - `native/bench/README.md` documents those new runner-control defaults
- Local verification is green on that runner-control slice:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `bin/ktls-http2-bench --help | rg 'repeat-order|cooldown-seconds|repeat-count'`
  - `bin/verify`
- Manual hosted rerun `24915345703` then completed successfully on clean head
  `45fcba8` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=alternating`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That first controlled rerun did not become decision-quality, but it improved
  the throughput side materially versus `24913116550`:
  - largest throughput span dropped from `216.79pp` on
    `h2_multiplexed_streams_s2` to `47.32pp` on `s1`
  - the old `h2_multiplexed_streams_s16` p95 outlier disappeared
  - the only `ktls-first` repeat (`repeat-02`) was also the clear outlier,
    with `h2_multiplexed_streams_s8` jumping to `+457.45%` p95
- Manual hosted rerun `24915629218` then completed successfully on the same
  clean head with the same settings except `repeat_order=baseline-first`.
- That confirmation rerun still did not become decision-quality, but it
  narrowed the blocker further:
  - the prior `s8` and `s16` kTLS-side p95 instability disappeared
  - `h2_multiplexed_streams_s2` also stabilized
  - the remaining blocker is now concentrated in
    `h2_multiplexed_streams_s4`, where one baseline repeat spiked to
    `216.48 ms` p95 and drove a `119.62pp` p95 span plus `64.53pp`
    throughput span
  - `h2_multiplexed_streams_s1` still shows a kTLS-side throughput span of
    `51.18pp`
- The hosted runner-control picture is therefore clearer now:
  - alternating order exposed that `ktls-first` repeats were the worst shape
  - fixed `baseline-first` removed the earlier kTLS-side p95 explosion
  - the remaining instability is smaller and now split between a baseline-side
    `s4` spike and a kTLS-side `s1` throughput spread
- Manual hosted rerun `24916589841` then completed successfully on the same
  clean head with the same settings as `24915629218` except
  `cooldown_seconds=60`.
- That longer-cooldown rerun made the lane less stable again:
  - `h2_multiplexed_streams_s2` returned as the worst throughput and p95 row
    with a `76.69pp` throughput span and `981.77pp` p95 span, both kTLS-side
  - `h2_multiplexed_streams_s8` and `s16` also became unstable again on the
    baseline side
  - the result is materially worse than the `15s` baseline-first run, so
    simply increasing cooldown is not a monotonic fix
- The next useful step is therefore no longer "try a larger sleep":
  - simple runner timing knobs are exhausted enough to stop tuning them blindly
  - the next methodology slice should isolate repeats or hotspot workloads more
    structurally, rather than keep stretching one multi-repeat run on one
    runner
  - the hosted `threads=4` lane is therefore mixed-noise, not one clean
    transport regression shape
- The structural methodology slice is committed and CI-cleared as `1fa0c45`:
  - `tool/filter_bench_scenario.py` materializes a temporary focused scenario
    by keeping only named workloads from an existing checked-in scenario
  - `bin/ktls-http2-bench` now accepts `--workloads <csv>` and records both
    `scenario_source` and `scenario_effective` in `host-info.txt`
  - the manual `kTLS HTTP/2 Benchmarks` workflow exposes the same filter as the
    `workloads` input
  - `native/bench/README.md` now documents hotspot-isolated reruns instead of
    only full-scenario stability reruns
- Focused local verification is green on that slice:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `python3 -m py_compile tool/filter_bench_scenario.py tool/test_filter_bench_scenario.py tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_filter_bench_scenario.py`
  - `python3 tool/filter_bench_scenario.py native/bench/scenarios/h2_ktls_multiplex_stability.toml /tmp/connectanum-ktls-filtered.toml h2_multiplexed_streams_s4,h2_multiplexed_streams_s8`
  - `bin/ktls-http2-bench --help | rg 'workloads|repeat-order|cooldown-seconds|repeat-count'`
- Manual hosted rerun `24917873323` then completed successfully on clean head
  `1fa0c45` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `workloads=h2_multiplexed_streams_s1`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=baseline-first`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That isolated `s1` rerun still did not become decision-quality:
  - throughput delta spanned `46.95pp`, from `-62.63%` to `-15.68%`
  - p95 delta stayed within threshold at `42.53pp`, from `-12.50%` to
    `+30.02%`
  - the remaining spread was explicitly kTLS-side on throughput
  - there were still no non-zero transport counters, no connection churn, and
    server-emission timings improved while client-side first-chunk/body-read
    timings regressed
- Manual hosted rerun `24917876488` then completed successfully on the same
  clean head with the same settings except
  `workloads=h2_multiplexed_streams_s4`.
- That isolated `s4` rerun is decision-quality:
  - throughput delta stayed within `5.15pp`, from `-17.35%` to `-12.20%`
  - p95 delta stayed within `7.81pp`, from `+4.19%` to `+12.00%`
  - the stable regression shape includes `Backpressure events 71 -> 82 (+11)`,
    `Backpressure alerts 2 -> 3 (+1)`, and
    `response headers wait avg 17.55 -> 21.16 (+3.61)`
  - connections opened, samples per connection, and chunk shape all stayed
    flat, so the isolated `s4` result now looks like a real multiplex-path
    regression rather than runner noise
- Manual hosted rerun `24918088324` then ran the same isolated `s1` workload
  with `repeat_count=5`.
- That longer `s1` rerun failed in the benchmark step, but the uploaded
  artifact still sharpened the picture:
  - the completed repeats converged into decision-quality spans:
    throughput `11.85pp` and p95 `21.75pp`
  - repeat outputs exist for `repeat-01` through `repeat-04`, but
    `repeat-04` is partial and baseline-only summary output is missing
  - the partial comparison reports `baseline` elapsed wall time `308.65s`
    versus `9.17s` for the `kTLS` pass, which points to a long-repeat
    baseline stall rather than another wide spread in the completed samples
- The repeat-stability blocker is therefore narrow enough to stop broad
  methodology tuning:
  - `s4` is now a stable, decision-quality transport regression shape
  - `s1` is likely also a real low-contention regression shape, but the
    repeat-05 attempt exposed a separate long-repeat harness stall that should
    not be conflated with the transport deltas themselves
  - the next useful step is transport diagnosis on isolated `s1` / `s4`
    evidence, with the long-repeat baseline stall tracked as a harness issue
- The next bounded diagnosis slice for isolated `s1` is committed and
  CI-cleared as `4228983`:
  - `native/bench/src/bin/http_stream.rs` wraps the HTTP/2 client transport so
    the bench can see the first successful socket read after response headers
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` now
    summarize two new receive-side timings:
    `response_body_post_header_connection_read_wait_*` and
    `response_body_connection_read_to_first_chunk_*`
  - `tool/ktls_http2_compare.py` now renders those new fields in the
    response-body diagnostics table and focus lines
  - the new metric split should tell the next isolated hosted `s1` rerun
    whether the remaining gap appears before the first post-header connection
    read or after bytes have already reached the HTTP/2 client body path
- Manual hosted rerun `24919870963` then completed successfully on clean head
  `4228983` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `workloads=h2_multiplexed_streams_s1`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=baseline-first`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That rerun ruled out the post-header first-body hypothesis:
  - the worst throughput and p95 row stayed stable at
    `h2_multiplexed_streams_s1`, `threads=4`, but the result is still not
    decision-quality because throughput span stayed at `290.71pp` and p95 span
    at `1833.65pp`
  - the new post-header receive-side metrics stayed flat or improved in all
    repeats:
    `post-header connection read wait avg 1.08 -> 0.94`, `1.18 -> 0.72`,
    `1.22 -> 1.11`
  - `connection read-to-first-chunk avg` also stayed flat:
    `0.35 -> 0.31`, `0.39 -> 0.38`, `0.38 -> 0.44`
  - the instability remained in `response headers wait avg` instead:
    `4.31 -> 29.65`, `29.01 -> 3.47`, `8.33 -> 4.27`
- The next bounded diagnosis slice is committed and CI-cleared as `b551a6d`:
  - split `response_headers_wait` into
    `response_headers_connection_read_wait_*` and
    `response_headers_connection_read_to_headers_*`
  - the next isolated hosted `s1` rerun should decide whether the remaining
    instability appears before the first response connection read or between
    that read and header parsing
- GitLab has not surfaced an `add-router` pipeline for `1fa0c45` or the
  isolated manual rerun follow-ups through the current token-backed API query.
- `packages/connectanum_core` is approved as a design reference for MCP package
  shape: typed protocol models, serializer-independent boundaries, explicit
  errors, small barrel exports, and focused tests. Reuse the style, not WAMP
  semantics.
- The WAMP profile transport performance-readiness plan is complete. Hosted
  GitHub validation is green through commit `175ae0a`: commit `5a8b918`
  passed push `CI` (`24853368527`) and `WAMP Profile Benchmarks`
  (`24853368528`), and the follow-up docs checkpoint `175ae0a` passed push
  `CI` (`24853407962`).
- The most recent product-readiness plan is now complete too:
  `docs/exec-plans/2026-04-23-wamp-transport-interop-coverage.md` added
  host-supported live WAMP transport interop coverage for the pure Dart
  RawSocket client path and mixed RawSocket/WebSocket routing, so the shipped
  transport surface is now protected beyond serializer and router-state
  conformance alone.
- `packages/connectanum_router/test/publish_ack_test.dart` now covers the pure
  Dart RawSocket publish-ack path across JSON, MessagePack, and CBOR against a
  live router.
- `packages/connectanum_router/test/router_integration_websocket_test.dart`
  now covers mixed RawSocket/WebSocket publish, call, and error routing across
  rawsocket JSON + CBOR clients and a websocket MsgPack client on the current
  macOS-supported path.
- Hosted GitHub validation is green through commit `c97eff4`: push `CI` run
  `24858211416` and `WAMP Profile Benchmarks` run `24858211413` both completed
  successfully on the earlier branch head.
- Hosted GitHub validation is now also green through commit `8da3602`:
  push `CI` run `24860616844` and `WAMP Profile Benchmarks` run `24860616860`
  both completed successfully after the kTLS comparison-artifact readability
  follow-up was pushed to both remotes.
- Hosted GitHub validation is now also green through commit `7bf3d8a`:
  push `CI` run `24861886418`, `WAMP Profile Benchmarks` run `24861886401`,
  and `kTLS Validation` run `24861886408` all completed successfully after the
  kTLS resource-usage follow-up was pushed to both remotes.
- Hosted GitHub validation is now also green through commit `911b208`:
  push `CI` run `24862887602`, `kTLS Validation` run `24862887603`, and
  `WAMP Profile Benchmarks` run `24862887632` all completed successfully after
  the kTLS workflow-summary follow-up was pushed to both remotes.
- The worker-safe realm authorization follow-up is now complete on the local
  working tree. Router settings now carry top-level
  `authorization_providers` definitions plus per-realm
  `authorization_provider` selection, worker isolates resolve providers from
  serialized settings instead of relying on a single isolate-local
  `AuthorizationProviderRegistry` object, and the default router worker
  entrypoint is now public so custom worker bootstraps can register provider
  factories before delegating to the standard worker.
- The old dynamic-authorization gap is now covered by a focused live
  integration regression in
  `packages/connectanum_router/test/authorization_integration_test.dart`,
  which reproduces the real worker-isolate path instead of only the old
  in-process callback path.
- Local verification for the current realm-authorization follow-up is green:
  `bin/test-fast`, `cd packages/connectanum_router && dart test
  test/authorization_test.dart test/authorization_integration_test.dart
  test/router_config_loader_test.dart -r expanded`, and `bin/verify` all
  passed on 2026-04-23.
- The kTLS comparison-artifact readability follow-up is now complete on the
  local working tree. `bin/ktls-http2-bench` now delegates comparison
  rendering to `tool/ktls_http2_compare.py`, and both `comparison.json` and
  `comparison.md` now carry aggregate summary findings instead of only raw
  per-workload rows.
- The next active kTLS slice is to make the same manual HTTP/2 comparison
  artifacts capture and summarize per-pass resource usage, because the current
  kTLS decision gap is performance interpretation rather than missing
  correctness coverage.
- That resource-usage slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` now writes per-pass `resource-usage.txt` sidecars for
  the baseline and required-kTLS passes, and `tool/ktls_http2_compare.py` now
  folds CPU-total, wall-time, and max-RSS deltas into `comparison.json` and
  `comparison.md`.
- The next active kTLS slice is to publish the generated comparison directly in
  the manual GitHub Actions workflow summary, so the next hosted Linux rerun is
  readable from the Actions UI before anyone downloads `ktls-http2-bench`
  artifacts.
- That workflow-summary slice is now complete on the local working tree too.
  The manual `kTLS HTTP/2 Benchmarks` workflow now writes the generated
  `comparison.md` and `host-info.txt` content into the Actions job summary on
  `always()`, so future hosted reruns have a readable first-stop view in the
  run UI before artifact download.
- The next kTLS comparison-readability slice is now complete on the local
  working tree too. `tool/ktls_http2_compare.py` now rolls the comparison up
  by workload family and native runtime thread count, highlights the current
  investigation focus for both groupings, and correctly parses GNU `time -v`
  elapsed wall-time labels that include embedded colons.
- Hosted GitHub validation is now also green through commit `f2b5fe8`:
  push `kTLS Validation` run `24864087126`, `WAMP Profile Benchmarks` run
  `24864087127`, and `CI` run `24864087129` all completed successfully after
  the kTLS hotspot-rollup follow-up was pushed to both remotes.
- Manual workflow run `24864760931` (`kTLS HTTP/2 Benchmarks`) then failed on
  `add-router` only because the generic zero-counter artifact gate rejected the
  expected `h2_multiplexed_streams` backpressure counters after both baseline
  and required-kTLS passes completed and uploaded comparison artifacts.
- The active kTLS slice is therefore to scope `bin/ktls-http2-bench` to a
  checked-in `h2_ktls_benchmark` artifact policy, so the manual comparison
  workflow stays meaningful without weakening the stricter correctness contract
  that remains covered by `kTLS Validation`.
- That artifact-policy slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` validates both comparison passes against
  `native/bench/artifact_gate/h2_ktls_benchmark.json`, and `native/bench`
  now has focused regression coverage for thread-scoped policy matching.
- Local verification for the current kTLS artifact-policy follow-up is green on
  2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml artifact_gate_policy_allows_thread_scoped_thresholds
  -- --nocapture`, `bash -n bin/ktls-http2-bench`, and `bin/verify` all
  passed.
- Hosted GitHub validation is now green through commit `706d8b8` too:
  push `CI` run `24865318342`, push `kTLS Validation` run `24865318343`,
  push `WAMP Profile Benchmarks` run `24865318353`, and manual
  `kTLS HTTP/2 Benchmarks` run `24865337582` all completed successfully after
  the scoped `h2_ktls_benchmark` artifact-policy follow-up landed.
- Hosted GitHub validation is now also green through commit `6deaabe`:
  push `CI` run `24866820516` completed successfully after the hosted
  resource-usage parser fix landed.
- Hosted GitHub validation is now also green through commit `db2ff96`:
  push `CI` run `24868012745`, push `kTLS Validation` run `24868012749`, and
  push `WAMP Profile Benchmarks` run `24868012750` all completed successfully
  after the kTLS transport-delta comparison follow-up landed.
- Hosted GitHub validation is now also green through commit `2393a01`:
  push `CI` run `24868963261`, push `kTLS Validation` run `24868963265`, and
  push `WAMP Profile Benchmarks` run `24868963262` all completed successfully
  after the Linux TLS-stat follow-up landed.
- Hosted GitHub validation is now also green through commit `257f9aa`:
  push `CI` run `24870440483`, push `kTLS Validation` run `24870440482`, and
  push `WAMP Profile Benchmarks` run `24870440494` all completed successfully
  after the multiplex-diagnostic control follow-up landed.
- The latest hosted `ktls-http2-bench-artifacts` bundle from run `24865337582`
  also exposed a concrete summary bug: both per-pass `resource-usage.txt`
  sidecars were present, but the generated comparison still claimed they were
  missing because GNU `time -v` prefixes its fields with tabs on hosted Linux.
- That resource-usage parser slice is now complete on the local working tree
  too. `tool/ktls_http2_compare.py` now strips leading whitespace before
  matching GNU `time -v` field labels, so the hosted Linux tab-indented
  `resource-usage.txt` sidecars are summarized instead of being ignored.
- The corrected rerender of that hosted artifact shows required-kTLS still
  loses mainly on throughput and p95, not on gross CPU or memory blow-up:
  average throughput delta `-24.20%`, average p95 delta `+40.38%`,
  `cpu_total_seconds +2.26%`, `elapsed_seconds +1.71%`, and
  `max_rss_kib +0.57%`. The grouped hotspot is now
  `h2_sustained_transfer` by workload family and `threads=1` by native runtime
  thread count.
- The raw hosted per-workload summaries also show that current transport
  counters do not explain that hotspot directly: both `h2_sustained_transfer`
  rows stayed at zero for backpressure, alerts, throttles, and timeout/error
  counters in both baseline and required-kTLS passes, while only the
  `h2_multiplexed_streams` rows showed bounded backpressure differences.
- That transport-delta slice is now complete on the local working tree too.
  `tool/ktls_http2_compare.py` now renders transport-counter views for the
  worst throughput row, the worst p95 row, and each comparable workload row in
  both `comparison.json` and `comparison.md`.
- That Linux TLS-stat slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` now captures `/proc/net/tls_stat` before and after
  each pass when the proc file is readable, and
  `tool/ktls_http2_compare.py` now summarizes kernel TLS session-open plus
  decrypt/rekey deltas in both `comparison.json` and `comparison.md`.
- The current hosted rerender now makes the boundary explicit: the worst p95
  row (`h2_sustained_transfer`, `threads=1`) still shows no non-zero transport
  counters in either pass, while only the multiplexed rows expose bounded
  `backpressure_events` differences (`76 -> 70` at `threads=1`,
  `82 -> 97` at `threads=4`).
- Manual workflow run `24869856621` (`kTLS HTTP/2 Benchmarks`) then reran the
  updated helper on `2393a01` and changed the current boundary again:
  required-kTLS now clearly opens kernel software TX/RX sessions
  (`TlsTxSw/TlsRxSw 34/34`) with no decrypt/rekey anomalies, while the
  dominant regression shifts back to `h2_multiplexed_streams` rather than
  `h2_sustained_transfer`.
- That means the next bounded kTLS follow-up should enable focused diagnostic
  reruns around the multiplex case instead of adding more generic artifact
  formatting or treating the old sustained-transfer row as the primary
  hotspot.
- That diagnostic-control slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` now supports explicit `--artifact-policy` selection
  plus `--skip-artifact-gate`, the manual `kTLS HTTP/2 Benchmarks` workflow
  mirrors those controls as workflow inputs, and
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` now gives the next
  hosted rerun a checked-in HTTP/2 multiplex-only hotspot scenario without
  weakening the canonical `h2_ktls_benchmark` release-decision path.
- Manual workflow run `24870980724` then exercised that new focused scenario
  on `257f9aa` with `skip_artifact_gate=true`, and the result tightened the
  kTLS question again:
  every `h2_ktls_multiplex_scaling` row regressed under required-kTLS, the
  best row was still `-12.23%` throughput (`s2`, `threads=4`), the worst row
  was `-64.97%` throughput (`s4`, `threads=4`), and even
  `streams_per_connection=1` regressed by roughly `-50%` with zero transport
  counters in either pass.
- That rerun also confirms the old kernel-path question is closed for this
  scenario too: required-kTLS opened software TX/RX sessions cleanly
  (`TlsTxSw/TlsRxSw 66/66`) with no decrypt or rekey anomalies.
- That connection-usage instrumentation slice is now complete on the pushed
  branch head too. Commit `55f23d3` passed hosted push `CI`
  (`24872329789`), `kTLS Validation` (`24872329782`), and
  `WAMP Profile Benchmarks` (`24872329792`) before the focused manual rerun.
- Manual workflow run `24872903498` then exercised the same focused scenario
  with the new connection section enabled, and it ruled out connection churn:
  every comparable row held `connections_opened` flat at `4 -> 4 (+0)`, and
  every row held `samples_per_connection_avg` flat at
  `20.00 -> 20.00 (+0.00)`.
- That hosted rerun leaves the same workload shape as the unresolved hotspot:
  `h2_multiplexed_streams_s16` at `threads=4` is still the worst throughput
  row (`-65.14%`), and `h2_multiplexed_streams_s8` at `threads=4` is still the
  worst p95 row (`+423.24%`).
- That phase-timing instrumentation slice is now complete on the pushed branch
  head too. Commit `3d85b51` passed hosted push `CI` (`24873599372`),
  `kTLS Validation` (`24873599375`), and `WAMP Profile Benchmarks`
  (`24873599379`) before the next focused manual rerun.
- Manual workflow run `24874338657` then exercised the same focused scenario
  with the new phase-timing section enabled, and it ruled out stream-slot
  acquisition as the primary bottleneck:
  - stream acquire wait stayed effectively flat on the same hotspot rows
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4`
    (`stream acquire wait avg 0.00 -> 0.00`, `request round trip avg 18.20 -> 31.72`)
  - worst p95 row:
    `h2_multiplexed_streams_s8` at `threads=1`
    (`stream acquire wait p95 0.00 -> 0.12`, `request round trip p95 39.13 -> 70.01`)
- The next bounded kTLS slice is therefore deeper HTTP/2 request-path
  diagnostics, not more connection or acquire-wait instrumentation. The next
  active plan is to split the post-acquire path so the artifacts can show
  whether the regression is concentrated in request upload, response-header
  wait, or response-body drain.
- That deeper request-path split is now implemented on the local working tree
  too. The HTTP/2 bench path now records request enqueue, response-header
  wait, and response-body read timing alongside the existing acquire-wait and
  round-trip timing, and `tool/ktls_http2_compare.py` now renders those new
  sub-phases in the phase summary.
- Local verification for the request-path phase-split slice is green on
  2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted artifact
  `24874338657`, and `bin/verify`.
- That request-path phase-split slice is now complete on the pushed branch
  head too. Commit `a88a8b7` passed hosted push `CI` (`24874851886`),
  `kTLS Validation` (`24874851872`), and `WAMP Profile Benchmarks`
  (`24874851879`) before the next focused manual rerun.
- Manual workflow run `24875528924` then exercised the same focused scenario
  with the deeper request-path timing enabled, and it narrowed the remaining
  hotspot to the HTTP/2 response-body drain:
  - worst throughput row and worst p95 row both landed on
    `h2_multiplexed_streams_s8` at `threads=1`
  - `stream acquire wait avg` improved slightly (`0.05 -> 0.02`)
  - `request enqueue avg` stayed negligible (`0.04 -> 0.06`)
  - `response headers wait avg` stayed flat (`28.65 -> 28.52`)
  - `response body read avg` jumped from `7.86` to `58.91`
  - `response body read p95` jumped from `14.11` to `467.44`
- The next bounded kTLS slice is therefore response-body-drain diagnostics on
  the HTTP/2 client path. The next active plan is to separate first-body-byte
  wait from sustained body-drain time and capture the observed chunk shape so
  the next rerun can tell whether the regression is a first-chunk stall or a
  sustained read/flow-control problem.
- That response-body-drain instrumentation slice is now implemented on the
  local working tree too. The HTTP/2 bench path now records response-body
  first-chunk wait, post-first-chunk tail-read time, observed chunk count, and
  first-chunk bytes, and `tool/ktls_http2_compare.py` now renders those
  metrics in the worst-row phase views plus a dedicated
  `HTTP Response-Body Diagnostics` section.
- Historical hosted artifact `24875528924` rerenders cleanly with the updated
  helper, and the new response-body diagnostics correctly show `n/a` there
  because that bundle predates the new instrumentation fields.
- Local verification for the current response-body-drain instrumentation slice
  is green on 2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted artifact
  `24875528924`, and `bin/verify`.
- That response-body-drain slice is now complete on the pushed branch head
  too. Commit `ce55324` passed hosted push `kTLS Validation`
  (`24876283985`), `WAMP Profile Benchmarks` (`24876284006`), and `CI`
  (`24876283996`) before the next focused manual rerun.
- Manual workflow run `24876728695` then reran the same focused scenario with
  the new response-body diagnostics enabled, and it narrowed the remaining
  regression again:
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4`
  - worst p95 row:
    `h2_multiplexed_streams_s8` at `threads=1`
  - `response body chunks avg` stayed flat on the hotspot rows
  - `response body first chunk bytes avg` stayed flat on the hotspot rows
  - the first-body-byte gap dominated the added body timing:
    - throughput hotspot:
      `first chunk wait avg +2.57 ms` vs `tail read avg +0.99 ms`
    - p95 hotspot:
      `first chunk wait avg +16.98 ms` vs `tail read avg +2.90 ms`
- The next bounded kTLS slice is therefore header-to-first-body gap
  diagnostics, ideally on the server response-emission path rather than more
  client chunk-shape probing. The next active plan is to instrument where that
  first body delay is introduced.
- That first-body-gap instrumentation slice is now complete on the pushed
  branch head too. Commit `7755828` passed hosted push `kTLS Validation`
  (`24878452943`), `WAMP Profile Benchmarks` (`24878452920`), and `CI`
  (`24878452921`) before the next focused manual rerun.
- The historical rerender remained backward compatible: the new comparison now
  renders an `HTTP Server Emission Timing` section, and the old hosted bundle
  correctly reports no server-emission metrics because it predates the new
  counters.
- Manual workflow run `24879483421` then reran the same focused scenario on
  `7755828` with `skip_artifact_gate=true`, and it closed the current
  question:
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4`
    still showed `response headers wait avg +6.71 ms` and
    `first chunk wait avg +4.83 ms`
  - worst p95 row:
    `h2_multiplexed_streams_s1` at `threads=4`
    still showed `response body read avg +3.21 ms` and
    `request round trip p95 +14.95 ms`
  - every comparable row held the current server-emission boundary flat:
    - `headers_to_first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
    - `queue_to_first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
- That means the remaining gap still opens after the current
  `onFirstBodyWrite` callback point. The next bounded slice is now the
  post-write completion boundary, not more pre-write handler timing.
- That first-write-completion slice is now implemented on the local working
  tree too. `packages/connectanum_router` now exposes
  `onFirstBodyWriteCompleted`, `packages/connectanum_bench` records
  `first_body_write_completed`, `headers_to_first_body_write_completed`,
  `queue_to_first_body_write_completed`, and `first_body_write_call`,
  `native/bench` summarizes those counters into
  `http_server_emission_timing`, and `tool/ktls_http2_compare.py` now renders
  the new completion boundary in both hotspot focus lines and the server
  timing table.
- Focused local verification for that first-write-completion slice is green on
  2026-04-24: `bin/test-fast`, targeted Dart analyze/tests for the bench and
  router stream paths, `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted artifact
  `24879483421`, and the slice is ready for full `bin/verify`.
- Commit `b8645af` then passed the hosted push chain cleanly too:
  - `kTLS Validation` `24880362805`
  - `WAMP Profile Benchmarks` `24880362819`
  - `CI` `24880362829`
- Manual workflow run `24881249566` reran the same focused scenario on
  `b8645af` with `skip_artifact_gate=true`, and it moved the boundary again:
  - worst throughput and p95 hotspot:
    `h2_multiplexed_streams_s4`, `threads=4`
    - `response headers wait avg +8.38 ms`
    - `response body first chunk wait avg +19.33 ms`
    - `response body tail read avg +3.00 ms`
  - the completion boundary still stayed flat:
    - `headers_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `queue_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_call_avg_ms 0.00 -> 0.00 (+0.00)`
- That means the remaining delay still opens after the first native
  response-stream write returns. The next bounded slice is now native
  response-stream handoff timing, not more Dart-side write timing.
- That native response-stream handoff slice is now implemented on the local
  working tree too. `ct_core` timestamps streamed response frames and records
  cumulative first-chunk channel/dequeue/send-call counters, `ct_ffi` and
  `connectanum_router` expose them through the transport metrics snapshot,
  `native/bench` summarizes them into
  `http_native_response_stream_timing`, and
  `tool/ktls_http2_compare.py` now renders the new focus lines and markdown
  section.
- Focused local verification for the native response-stream handoff slice is
  green on 2026-04-24: `bin/test-fast`,
  `dart analyze packages/connectanum_router packages/connectanum_bench`,
  `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml
  http2_response_streaming_round_trip -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, and
  `python3 tool/test_ktls_http2_compare.py`.
- Full local verification for the native response-stream handoff slice is also
  green on 2026-04-24: `bin/verify`.
- That native response-stream handoff slice is now complete on the pushed
  branch head too. Commit `8ed8014` is now on both `origin` and `github`, and
  the hosted GitHub push chain completed cleanly:
  - `WAMP Profile Benchmarks` `24882795293`
  - `kTLS Validation` `24882795301`
  - `CI` `24882795327`
- GitLab has not surfaced a pipeline for `8ed8014` yet through the current
  token-backed pipeline query.
- Manual workflow run `24883756346` reran the same focused scenario on
  `8ed8014` with `skip_artifact_gate=true`, and it closed the current
  handoff-average question:
  - worst throughput and p95 hotspot:
    `h2_multiplexed_streams_s2`, `threads=1`
    - `response headers wait avg +2.21 ms`
    - `response body first chunk wait avg +13.64 ms`
    - `request round trip p95 +201.63 ms`
  - native handoff averages on that same row moved much less:
    - `native first chunk channel wait avg +0.41 ms`
    - `native headers-to-first-chunk-dequeue avg +0.50 ms`
    - `native first chunk send call avg -0.00 ms`
    - `native headers-to-first-chunk-send-call avg +0.50 ms`
- That means the native handoff averages are informative but still too coarse
  for the worst latency spike. The next bounded slice is native
  response-stream slow-path buckets, not more average-only timing.
- That native response-stream slow-path slice is now implemented on the local
  working tree too. `ct_core` records `>=1ms`, `>=5ms`, and `>=10ms` counters
  for channel wait, headers-to-first-chunk dequeue, and first send-call
  timings; `ct_ffi` and `connectanum_router` expose those counters through the
  transport metrics snapshot; `native/bench` summarizes them into
  `http_native_response_stream_slow_path`; and
  `tool/ktls_http2_compare.py` now renders dedicated slow-path focus lines and
  an `HTTP Native Response-Stream Slow Paths` section.
- Focused local verification for the native response-stream slow-path slice is
  green on 2026-04-24: `bin/test-fast`,
  `dart analyze packages/connectanum_router packages/connectanum_bench`,
  `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml
  http2_response_streaming_round_trip -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  and a rerender of hosted artifact `24883756346`.
- Full local verification for the native response-stream slow-path slice is
  also green on 2026-04-24: `bin/verify`.
- That native response-stream slow-path slice is now complete on the pushed
  branch head too. Commit `547d6e4` is now on both `origin` and `github`, and
  the hosted GitHub push chain completed cleanly:
  - `CI` `24884889546`
  - `WAMP Profile Benchmarks` `24884889549`
  - `kTLS Validation` `24884889561`
- GitLab has not surfaced a pipeline for `547d6e4` yet through the current
  token-backed pipeline query.
- Manual workflow run `24885834166` reran the same focused
  `h2_ktls_multiplex_scaling` scenario on clean head `547d6e4` with
  `skip_artifact_gate=true`, and it sharpened the boundary again:
  - worst throughput row:
    `h2_multiplexed_streams_s2`, `threads=4`
    - `Backpressure events 14 -> 25 (+11)`
    - `native first chunk channel wait >=1/5/10ms 0/0/0 -> 6/0/0`
    - `native first chunk send call >=1/5/10ms 1/0/0 -> 7/0/0`
  - worst p95 row:
    `h2_multiplexed_streams_s1`, `threads=4`
    - `request round trip p95 13.04 -> 24.95 (+11.90)`
    - `response body first chunk wait avg 1.37 -> 6.12 (+4.75)`
    - no `http_native_response_stream_*` metrics were present for that row
- The current local working tree now carries the next bounded diagnostic fix:
  `HttpResponseStream` exposes a completion future, and the bench handlers now
  await direct-stream completion before recording server-emission diagnostics.
  That fixes the measurement boundary that kept the `s1` rows out of the
  current native/direct-stream timing summaries.
- That direct-stream completion slice is now pushed too. Commit `a12227d`
  passed the visible hosted GitHub push chain:
  - `CI` `24886626863`
  - `WAMP Profile Benchmarks` `24886626856`
- `kTLS Validation` still has not surfaced for `a12227d` through the GitHub
  API, and GitLab also did not surface a pipeline for that head through the
  current token-backed query.
- Manual workflow run `24887510264` reran the same focused
  `h2_ktls_multiplex_scaling` scenario on clean head `a12227d` with
  `skip_artifact_gate=true`, and it closed the direct-stream question:
  - `h2_multiplexed_streams_s1` rows now appear in
    `HTTP Server Emission Timing`, so the earlier omission was a bench
    sampling bug rather than a transport-path gap
  - worst throughput row:
    `h2_multiplexed_streams_s8`, `threads=4`
    - `response headers wait avg 24.33 -> 37.67 (+13.34)`
    - `response body first chunk wait avg 7.40 -> 15.76 (+8.35)`
    - `server stream open avg 11.88 -> 14.12 (+2.24)`
    - `server first body write completed avg 11.93 -> 14.17 (+2.24)`
    - `native first chunk channel wait avg 0.22 -> 0.37 (+0.16)`
    - `native headers-to-first-chunk-dequeue avg 5.93 -> 8.59 (+2.66)`
    - `native first chunk send call avg 0.32 -> 0.87 (+0.54)`
    - `native headers-to-first-chunk-send-call avg 6.26 -> 9.46 (+3.20)`
- The next bounded diagnostic slice is now pushed too. Commit `fbc5566` is on
  both `origin` and `github`, and the visible GitHub push chain completed:
  - `CI` `24888660106`
  - `kTLS Validation` `24888660101`
  - `WAMP Profile Benchmarks` `24888660111`
- GitLab has not surfaced a pipeline for `fbc5566` through the current
  token-backed query.
- That checkpoint adds native response-stream header-dispatch timing:
  `stream_open_to_headers_send` plus `headers_send_call`, threaded through the
  router metrics snapshot, native bench artifact summaries, and comparison
  output as part of `http_native_response_stream_timing`.
- The headers-queued-to-first-connection-write slice is now pushed too.
  Commit `0a9c3c8` is on both `origin` and `github`, and the visible GitHub
  push chain completed:
  - `CI` `24893449385`
  - `kTLS Validation` `24893449381`
  - `WAMP Profile Benchmarks` `24893449378`
- GitLab has not surfaced a pipeline for `3f60a18` through the current
  token-backed query.
- Commit `d892676` is now on both `origin` and `github`, and the visible
  GitHub push chain completed:
  - `CI` `24895983686`
  - `kTLS Validation` `24895983707`
  - `WAMP Profile Benchmarks` `24895983693`
- Manual hosted rerun `24897078545` then completed successfully on clean head
  `d892676` with the focused multiplex scenario and `skip_artifact_gate=true`.
  It closed the direct-stream control split:
  - worst p95 row:
    `h2_multiplexed_streams_s8`, `threads=1`
    - `server direct-stream open round trip avg 12.19 -> 19.09 (+6.90)`
    - `server direct-stream request queue delay avg 5.46 -> 6.56 (+1.10)`
    - `server direct-stream reply delivery delay avg 6.70 -> 12.50 (+5.80)`
    - `native headers-to-first-chunk-dequeue avg 7.13 -> 13.50 (+6.37)`
  - worst throughput row:
    `h2_multiplexed_streams_s2`, `threads=1`
    - `server direct-stream open round trip avg 3.42 -> 2.29 (-1.13)`
    - `server direct-stream request queue delay avg 1.78 -> 0.94 (-0.84)`
    - `server direct-stream reply delivery delay avg 1.60 -> 1.32 (-0.28)`
- That rerun showed the worst p95 movement on the reply side of the
  direct-stream control path, while the worst throughput row still points at
  the native first-chunk path instead of the control handshake itself.
- The current local working tree therefore carries the next bounded slice:
  replacing the per-open direct-stream reply `ReceivePort` with a shared
  isolate-local reply channel keyed by request id.
- Local verification for the current shared-reply-channel slice is green on
  2026-04-24: `bin/test-fast`, `dart test
  packages/connectanum_router/test/direct_stream_reply_channel_test.dart
  -r expanded`, `dart test packages/connectanum_router/test/router_runtime_test.dart
  -r expanded`, `dart test packages/connectanum_bench/test/http_stream_handler_test.dart
  -r expanded`, `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `dart analyze packages/connectanum_router packages/connectanum_bench`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  and `bin/verify`.
- That shared-reply-channel slice is now pushed as commit `3f60a18`
  (`perf(router): reuse direct-stream reply channel`).
- The visible GitHub push chain for `3f60a18` completed successfully:
  - `CI` `24897944475`
  - `WAMP Profile Benchmarks` `24897944543`
- `kTLS Validation` still has not surfaced for `3f60a18` through the current
  public Actions query.
- Manual hosted rerun `24898979218` on clean head `3f60a18` then stayed
  `in_progress` well past the normal runtime while the benchmark job remained
  stuck in `Run HTTP/2 TLS vs kTLS benchmark`.
- A focused local repro on macOS using the same multiplex scenario without the
  Linux-only kTLS pass wrote its results successfully but left the
  `bench_main.dart` helper process alive, which isolated the regression to
  helper-process shutdown rather than workload execution.
- Root cause: the shared `DirectStreamReplyChannel` kept a top-level
  `RawReceivePort` open for the full isolate lifetime, so the helper isolate
  never became idle enough to exit after the benchmark completed.
- The current local working tree fixes that leak by opening the shared reply
  port lazily and closing it again automatically once the channel has no
  pending waiters, while preserving shared-port reuse during concurrent
  direct-stream opens.
- Focused local verification for that fix is green on 2026-04-24:
  `bin/test-fast`, `dart test
  packages/connectanum_router/test/direct_stream_reply_channel_test.dart
  -r expanded`, and a full local HTTP/2 multiplex bench run with
  `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release
  --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib
  native/transport/target/release/libct_ffi.dylib --scenario
  native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results
  /tmp/connectanum-h2-local-results.jsonl --artifact-dir
  /tmp/connectanum-h2-local-artifacts --router-worker-counts 1
  --native-runtime-thread-counts 1,4`, which now exits cleanly after writing
  the summary instead of hanging on helper shutdown.
- Local verification for that stream-open-to-headers-send slice is green on
  2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml summarize_report_computes_latency_and_deltas --
  --nocapture`, `cargo test --manifest-path
  native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip --
  --nocapture`, `dart analyze packages/connectanum_router
  packages/connectanum_bench`, `python3 -m py_compile
  tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, and `bin/verify`.
- Local verification for the current kTLS transport-delta follow-up is green
  on 2026-04-24: `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a rerender of the hosted `24865337582` artifact bundle, and `bin/verify` all
  passed.
- Local verification for the current kTLS resource-usage parser follow-up is
  green on 2026-04-24: `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a rerender of the hosted `24865337582` artifact bundle, and `bin/verify` all
  passed.
- Local verification for the current kTLS Linux TLS-stat follow-up is green on
  2026-04-24: `bin/test-fast`, `bash -n bin/ktls-http2-bench`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a focused synthetic `tool/ktls_http2_compare.py` run with
  `tls-stat-before.txt` / `tls-stat-after.txt` sidecars, and `bin/verify` all
  passed.
- Local verification for the current kTLS multiplex-diagnostic control slice
  is green on 2026-04-24: `bin/test-fast`, `bash -n bin/ktls-http2-bench`,
  `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ktls-http2-benchmarks.yml")'`,
  `bin/ktls-http2-bench --help`, and `bin/verify` all passed.
- Local verification for the current kTLS workflow-summary follow-up is green
  on 2026-04-24: `bin/test-fast`, YAML parsing of
  `.github/workflows/ktls-http2-benchmarks.yml`, and `bin/verify` all passed.
- Local verification for the current kTLS hotspot-rollup follow-up is green on
  2026-04-24: `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, a focused synthetic
  `tool/ktls_http2_compare.py` run with Linux-style `resource-usage.txt`
  sidecars, and `bin/verify` all passed.
- `docs/ktls_research.md` is now aligned with the current post-secure-WAMP
  state: secure WAMP coverage is complete, the remaining kTLS issue is
  performance rather than correctness, and the next kTLS-specific need is
  readable hosted comparison evidence before deeper Linux-only tuning.
- `packages/connectanum_router/test/authorization_integration_test.dart` is
  analyzer-clean again; the earlier worker-authorization slice no longer
  leaves avoidable info-level noise in the fast verification baseline.
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
  point for both local and hosted validation. It runs the three strict
  default-counter smoke gates (`wamp_smoke`, `wamp_secure_smoke`, and
  `wamp_control_smoke`) plus the policy-backed throughput gates
  (`wamp_transport_throughput`, `wamp_secure_throughput`, and
  `wamp_publish_fanout_throughput`). The first local Darwin arm64 run on
  2026-04-23 passed the original five-gate set with 64 workloads. In that
  run, the lowest cleartext throughput-gate result was `57.65 Mbps`
  (`websocket_pubsub_json_64k`) with max p95 `241.860 ms`, and the lowest
  secure throughput-gate result was `35.86 Mbps`
  (`rawsocket_secure_pubsub_json_64k`) with max p95 `389.237 ms`.
- GitHub Actions includes a dedicated `WAMP Profile Benchmarks` workflow that
  runs `bin/wamp-profile-validate` on hosted Ubuntu and uploads
  `wamp-profile-benchmark-artifacts`. Hosted run `24846498743` passed on
  commit `a2eef0f`, confirming the expanded smoke-plus-throughput WAMP
  release-gate entrypoint on Linux before fan-out promotion.
- `wamp_publish_fanout_throughput` now has a conservative checked-in artifact
  policy in `native/bench/artifact_gate/wamp_publish_fanout_throughput.json`.
  Local Darwin arm64 fan-out baselines on 2026-04-23 ranged from `24.49 Mbps`
  to `66.08 Mbps` with max p95 `508.916 ms`, while the first hosted Linux
  diagnostic run ranged from `46.19 Mbps` to `138.73 Mbps` with max p95
  `228.126 ms`. That makes fan-out stable enough to move from diagnostics into
  the canonical WAMP release-gate entrypoint without tightening the existing
  cleartext or secure transport floors yet.
- A fresh local Darwin arm64 rerun of
  `native/bench/scenarios/wamp_publish_fanout_throughput.toml` after the
  policy landed also passed the new gate. That rerun ranged from `23.05 Mbps`
  (`websocket_pubsub_cbor_64k_fanout8`) to `75.21 Mbps`
  (`rawsocket_pubsub_json_64k_fanout8`) with max p95 `485.628 ms`, so the
  checked-in fan-out floors still have healthy local headroom.
- `bin/wamp-profile-diagnostics` now stays focused on the remaining
  non-release-blocking diagnostic scenarios:
  `wamp_client_impl_throughput`, `wamp_payload_mode_throughput`,
  `wamp_mixed_serializer_throughput`, and
  `wamp_websocket_fragmentation_throughput`. Hosted run `24848746691` passed
  on commit `eb0aa5c`, and push `CI` run `24848746640` also passed on the same
  commit.
- A second full local rerun of the expanded canonical
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-rerun-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 60000`
  passed all six release gates on Darwin arm64 after commit `7d40433` was
  pushed. The earlier `wamp_secure_throughput` stall did not reproduce on that
  rerun, so the local release-gate entrypoint is currently green again.
- The bench orchestration path now fails fast instead of waiting indefinitely
  on two previously unbounded states: `native/bench/src/bin/http_stream.rs`
  now errors if `bench_main` does not print `READY` within the configured
  timeout, and `packages/connectanum_bench/lib/src/wamp_workload_runner.dart` now
  applies explicit WAMP session-open timeouts across workload modes while also
  cleaning up already-opened sessions if later opens fail. Targeted timeout
  tests and a full `bin/verify` run passed locally on the hardened working
  tree.
- The existing `CI` workflow also has a `workflow_dispatch`-only `WAMP Profile
  Gates` job. Use that path for branch-hosted WAMP evidence until the
  dedicated `WAMP Profile Benchmarks` workflow exists on the default branch
  and becomes directly dispatchable.
- The first hosted `WAMP Profile Benchmarks` run on `3acbf94` failed because
  the Rust bench control client negotiated HTTP/2 for `/bench/metrics`, and
  hosted Linux recorded occasional TLS close/protocol-error alerts from that
  control channel inside otherwise successful WAMP workloads. The control
  client now forces HTTP/1.1 so WAMP profile gates do not mix HTTP/2
  control-plane shutdown noise into WAMP transport-alert deltas.
- Local Darwin arm64 validation after forcing the Rust bench control client to
  HTTP/1.1 passed both canonical WAMP profile gates with
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-http1-control-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`.
- Final local handoff verification on 2026-04-23 passed with `bin/verify`.
  The first `bin/verify` attempt hit a transient
  `ct_ffi::tests::listen_flow::poll_connection_message_returns_payload`
  timeout; the test passed in isolation, the full `ct_ffi` suite then passed,
  and the full `bin/verify` rerun passed.
- GitHub Actions CI now runs through the canonical root `bin/*` entrypoints on branch pushes and PRs to `master`; GitHub Actions run `24732889424` for `2fac53b` completed successfully with both `Fast Checks` and `Full Verify`.
- The CI workflow now targets all branch pushes plus PRs to `master`, and it also exposes `workflow_dispatch` for manual runs.
- Hosted GitHub validation is now confirmed green through the latest pushed
  checkpoint. Commit `35b4cd1` passed `kTLS Validation`
  (`24852537007`), `WAMP Profile Benchmarks` (`24852537018`), and push `CI`
  (`24852537035`), and the follow-up docs checkpoint `9462ba1` also passed
  push `CI` (`24852585677`).
- The latest pushed WAMP readiness checkpoint is fully green on GitHub too.
  Commit `5a8b918` passed push `CI` (`24853368527`) and
  `WAMP Profile Benchmarks` (`24853368528`), and the follow-up docs commit
  `175ae0a` passed push `CI` (`24853407962`).
- The remaining WAMP control/setup timeout gaps are now hardened in
  `5a8b918`. `packages/connectanum_bench/lib/src/wamp_workload_runner.dart`
  now bounds the remaining publish/subscribe/register/close paths and applies
  cleanup timeouts during worker teardown, and
  `packages/connectanum_bench/test/wamp_workload_runner_test.dart` now covers
  RPC peer-registration stalls plus publish-ack, subscribe-cycle, and
  register-cycle timeout cases. `dart test
  packages/connectanum_bench/test/wamp_workload_runner_test.dart` and
  `bin/verify` passed locally on Darwin arm64 for this follow-up working tree.
- The next live WAMP correctness gap on the local macOS-supported path is now
  closed too. `cd packages/connectanum_router && dart test
  test/publish_ack_test.dart test/router_integration_websocket_test.dart -r
  expanded` passed after expanding the pure Dart RawSocket publish-ack smoke to
  JSON/MessagePack/CBOR and adding mixed RawSocket/WebSocket routing coverage
  in the websocket integration suite, and the full root `bin/verify` run also
  passed on the same working tree.
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
- `kTLS HTTP/2 Benchmarks` is now manual-only. The workflow remains available
  through `workflow_dispatch` for comparative hosted artifacts, but it no
  longer auto-runs on every `native/bench/**` push because it is a completed
  research benchmark and the strict `kTLS Validation` workflow is the CI
  correctness gate.
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

- 2026-04-23: `bin/test-fast`, `bash -n bin/wamp-profile-validate`,
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-smoke-release-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`,
  and `bin/verify` passed on Darwin arm64 after expanding the canonical WAMP
  release-gate entrypoint to include cleartext, secure, and control-plane
  smoke gates before the policy-backed throughput gates.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before changing
  `kTLS HTTP/2 Benchmarks` to manual-only so completed kTLS comparison
  benchmarking no longer blocks unrelated WAMP profile CI pushes.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml --bin http_stream http_endpoint_accepts_https_control_base -- --nocapture`,
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-http1-control-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`,
  and `bin/verify` passed on Darwin arm64 after forcing the Rust bench
  control client to HTTP/1.1 for WAMP profile gates.
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
  `docs/exec-plans/2026-04-28-github-deployment-chain-readiness.md`
- Paused benchmark-diagnosis plan:
  `docs/exec-plans/2026-04-25-h2-isolated-regression-diagnosis.md`
- Most recent completed product-readiness plan:
  `docs/exec-plans/2026-04-23-mcp-support-groli-app.md`
- Supporting research notes:
  - `docs/mcp_integration_research.md`
  - `docs/dart_package_publishing.md`
  - `docs/ktls_research.md`
  - `docs/e2ee_ppt_research.md`
- Most recent completed plan:
  `docs/exec-plans/2026-04-24-ktls-repeat-stability.md`
- Completed immediately before that:
  `docs/exec-plans/2026-04-24-h2-main-isolate-control-port-optimization.md`
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
