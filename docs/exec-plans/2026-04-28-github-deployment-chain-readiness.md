# GitHub Deployment Chain Readiness

Status: paused
Owner: Codex
Created: 2026-04-28
Last updated: 2026-04-30

## Goal

Make GitHub the primary deployment and release chain for the project: every
continuation should prefer green branch CI, reliable release publishing,
multi-platform native artifacts, readable public release metadata, and clear
operator evidence over speculative feature or benchmark work.

## Scope

- In scope:
  - GitHub Actions health, warnings, skipped-test visibility, and branch CI
    cleanliness.
  - Release workflow validation and GitHub release publishing for Dart packages
    and native FFI artifacts.
  - Multi-platform FFI artifact production, naming, checksums, signatures, and
    install/download behavior.
  - Human-readable release notes, artifact names, workflow summaries, and public
    package metadata.
  - Documentation that lets autonomous continuation loops identify deployment
    blockers without chat-only context.
- Out of scope:
  - New speculative transport features unless they are required to ship or
    validate the deployment chain.
  - Additional kTLS/H2 diagnosis beyond keeping existing benchmark workflows
    green and understandable.

## Files Expected To Change

- `.github/workflows/`
- `bin/`
- `tool/`
- `docs/project_state.md`
- `docs/exec-plans/`
- Package metadata and public docs when release presentation changes.

## Preconditions

- GitHub remote `github` points at `konsultaner/connectanum-dart`.
- `origin` remains the GitLab remote, but GitHub Actions is the visible hosted
  deployment signal for this branch.
- Do not read `.token` contents into context. Use existing credential helpers or
  GitHub connector access without printing secrets.

## Plan

1. Establish the latest GitHub branch status as the deployment-chain source of
   truth and keep `docs/project_state.md` current.
2. Audit GitHub workflows for release/deployment readiness: warnings, skipped
   jobs, path filters, artifact names, release summaries, and native matrix
   coverage.
3. Prioritize the next deployability gap: multi-platform FFI artifacts and
   release publishing before more speculative benchmark work.
4. Add or tighten verification so skipped tests and warning-prone jobs are
   visible, intentional, and documented.
5. Push each deployment-chain slice, watch GitHub Actions, and update the plan
   with run IDs and remaining blockers.

## Progress

- Promoted this plan to the active autonomous milestone and paused the H2
  isolated regression diagnosis plan.
- Paused this plan on 2026-04-29 after the deployment-chain evidence refreshed
  cleanly on `b338d58` and the remaining blockers became explicit
  operator/product/deployment decisions rather than code-ready autonomous work.
- Reactivated this plan on 2026-04-30 after the H2 transport-counter artifact
  guardrail reached a clean checkpoint:
  - branch head `0da1030` passed GitHub `CI` run `25163209719`
    (`Fast Checks` 5m35s, `Full Verify` 8m24s)
  - the deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `0da1030`
  - manual H2/kTLS run `25163851551` was log-clean with no transport-counter
    issues in focus rows, but remained non-decision-quality due baseline-side
    benchmark noise, so H2 is no longer the default continuation path
  - repeat confirmation run `25164322244` was also log-clean with no
    transport-counter issues in focus rows; it remained non-decision-quality
    from kTLS-side repeat instability, confirming the artifact guardrail is
    working and that additional H2 work should be scoped to benchmark
    repeat-stability evidence
  - the next autonomous priority is RC/deployment readiness around branch
    protection evidence, router workflow/package publication evidence, native
    release/RC tag evidence, Dart package release-order readiness, and
    human-readable release/package surfaces
- Refreshed native release dry-run evidence for the current branch head:
  - branch head `1d999ea` passed GitHub `CI` run `25164892705`
    (`Fast Checks` 5m25s, `Full Verify` 8m04s) and the clean-CI/log audit
    passed
  - manual `Native Artifacts` dry-run `25165578557` passed all hosted Linux,
    macOS, and Windows `ct_ffi` artifact jobs plus the `Publish GitHub
    Release` preview job
  - `native-release-preview` was uploaded, the dry-run intent accepted
    `ct-ffi-v2026.04.30-dry-run.1d999ea`, no GitHub Release was created for
    that tag, and `--require-clean-native-release-dry-run` now passes for the
    checked-out head
- Started public native-release-note wording polish:
  - the generated notes now describe `ghcr.io/konsultaner/connectanum-router`
    as a separately released router image target that must be confirmed in the
    deployment guide before production use, rather than implying the GHCR image
    is already published
  - pre-change `bin/test-fast` passed locally, and focused renderer checks
    passed after the wording change
- Completed hosted validation for the native release-note wording polish:
  - commit `7098c54` (`release: clarify native release links`) passed GitHub
    `CI` run `25166045940` with `Fast Checks` in 5m38s and `Full Verify` in
    8m09s
  - the branch-head deployment-chain audit passed with
    `--require-clean-latest-ci` and `--require-clean-latest-ci-logs`; latest
    CI logs contained no high-signal warning, skipped-test, panic,
    broken-pipe, reset, timeout, or connection-noise matches
  - manual `Native Artifacts` dry-run `25166714340` passed Linux x64, Linux
    arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    `Publish GitHub Release` preview job
  - the dry-run accepted `ct-ffi-v2026.04.30-dry-run.7098c54`, uploaded
    `native-release-preview`, did not create a GitHub Release for that tag,
    and the preview notes contain the corrected separately released router
    image wording
- Refreshed Dart package publish-readiness evidence for the current branch
  head:
  - local `bin/dart-package-publish-dry-run --show-release-plan` passed for
    `connectanum_client 2.2.6` with `Package has 0 warnings`
  - manual GitHub `Dart Package Publish Dry Run` run `25167072611` passed on
    `7098c54`, and hosted log scanning found no warning, skipped-test, panic,
    broken-pipe, reset, or package-warning patterns
  - the remaining Dart package blocker is still non-code release policy:
    decide whether and when to publish `connectanum_core 0.1.0` before
    `connectanum_client 2.2.6`, plus pub.dev ownership and final public
    version choices
- Recorded the latest documentation/deployment evidence checkpoint:
  - branch head `e8a0438` (`docs: record deployment chain evidence`) passed
    GitHub `CI` run `25167510955` with `Fast Checks` in 5m56s and
    `Full Verify` in 8m04s
  - the branch-head deployment-chain audit passed with
    `--require-clean-latest-ci` and `--require-clean-latest-ci-logs`; latest
    CI logs contained no high-signal warning, skipped-test, panic,
    broken-pipe, reset, timeout, or connection-noise matches
  - hosted GitHub `Dart Package Publish Dry Run` run `25167510967` passed on
    `e8a0438`, and the latest native release dry-run remains clean and
    relevant because no native-release-sensitive paths changed after
    `7098c54`
  - `docs/github_deployment_chain.md` now has a short RC promotion checklist
    that keeps branch protection, router image/GHCR publication, RC tagging,
    and Dart package ownership/release order explicit operator decisions
- Removed generated production output from version control:
  - commit `0b5cdfd` (`chore: stop tracking production out artifacts`) removed
    the previously tracked `out/production` tree from the Git index while
    leaving local generated files ignored by `/out/`
  - branch head `0b5cdfd` passed GitHub `CI` run `25169497644` with
    `Fast Checks` in 5m51s and `Full Verify` in 8m00s
  - the branch-head deployment-chain audit passed with
    `--require-clean-latest-ci` and `--require-clean-latest-ci-logs`; latest
    CI logs contained no high-signal warning, skipped-test, panic,
    broken-pipe, reset, timeout, or connection-noise matches
  - hosted Dart package dry-run `25168519708` and native release dry-run
    `25166714340` remain clean and relevant because the cleanup changed no
    package-publish-sensitive or native-release-sensitive inputs
- Refreshed hosted validation for the generated-output cleanup checkpoint and
  hardened audit lookup behavior:
  - documentation checkpoint `a4818c8`
    (`docs: record out artifact cleanup evidence`) passed GitHub `CI` run
    `25170846499`; `Fast Checks` completed in 5m39s and `Full Verify`
    completed in 8m17s
  - hosted GitHub `Dart Package Publish Dry Run` run `25170846455` passed on
    `a4818c8` and covers the checked-out head
  - the branch-head clean-CI/log audit passed for `a4818c8`, and hosted logs
    contained no high-signal warning, skipped-test, panic, broken-pipe, reset,
    timeout, or connection-noise matches
  - native release dry-run `25166714340` remains clean and relevant because no
    native-release-sensitive inputs changed after `7098c54`
  - the audit script now falls back from GitHub's workflow-filtered run list to
    the unfiltered branch run list when a just-completed workflow is visible
    only in the branch run feed, avoiding a transient false negative in the
    package/native evidence gates
  - pre-change `bin/test-fast` passed locally before the audit fallback change
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`,
    `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 10 --require-clean-latest-ci --require-clean-latest-ci-logs`,
    `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 10 --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`,
    and `git diff --check`
  - implementation commit `c8b6a13`
    (`ci: harden workflow run audit lookup`) passed local `bin/verify`,
    including native Rust/FFI, Dart package, MCP, bench, router,
    `remote_auth_integration_test`, and Chrome/Dart2Wasm browser coverage
  - `c8b6a13` passed hosted GitHub `CI` run `25172656687`;
    `Fast Checks` completed in 5m37s and `Full Verify` completed in 8m10s
  - the branch-head clean-CI/log audit passed for `c8b6a13`, with no
    high-signal warning, skipped-test, panic, broken-pipe, reset, timeout, or
    connection-noise matches
  - hosted Dart package dry-run `25170846455` remains clean and relevant for
    `c8b6a13` because no package-publish-sensitive paths changed after
    `a4818c8`; native release dry-run `25166714340` likewise remains clean and
    relevant because no native-release-sensitive paths changed after `7098c54`
  - RC readiness remains blocked only on operator/release actions: branch
    protection, default-branch visibility for `router-image.yml`, visible
    GHCR router package evidence, RC tag/prerelease selection, and the Dart
    package release-order/pub.dev ownership decision
- Confirmed pushed documentation head `639c095` passed GitHub `CI` run
  `25046524665`:
  - `Fast Checks`: success
  - `Full Verify`: success
  - `WAMP Profile Gates`: skipped as expected for docs-only changes
- Started the first deployment-chain implementation slice:
  - add Windows x64 to the `Native Artifacts` matrix
  - make the native release install/build hooks resolve Linux arm64 and Windows
    x64 release triples
  - update public release-target docs to include Windows x64
- Completed hosted validation for the Windows native artifact slice:
  - `Native Artifacts` run `25048283917` on `86a4e7c` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, and Windows x64 packaging,
    signing, sigstore attestation, and artifact upload
  - GitHub `CI` run `25048277995` on `86a4e7c` passed `Fast Checks` and
    `Full Verify`; `WAMP Profile Gates` was skipped for this non-benchmark
    change as expected
- Started the release-publishing dry-run slice:
  - `.github/workflows/native-artifacts.yml` adds a `dry_run` manual input for
    release-tag preview runs
  - `tool/render_native_release_notes.py` renders the human-readable native
    release notes outside inline workflow shell, with unit coverage
  - dry-run publish jobs write `release-notes.md` and `release-metadata.txt`
    into a `native-release-preview` artifact and stop before any GitHub
    Release mutation
- Completed hosted validation for the release dry-run slice:
  - commit `7b45ede` (`ci: add native release dry run`) passed GitHub `CI` run
    `25050575954`
  - manual `Native Artifacts` dry-run `25051217251` passed all Linux, macOS,
    and Windows native artifact legs, then rendered and uploaded
    `native-release-preview`
  - `gh release view ct-ffi-v2026.04.28-dry-run.7b45ede` returned
    `release not found`, confirming the dry-run path did not mutate GitHub
    Releases
- Recorded the docs-only validation checkpoint:
  - commit `d3ecfd1` (`docs: record native release dry run validation`) passed
    GitHub `CI` run `25051747670`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was skipped
    as expected for a docs-only push
- Started installer coverage for hosted multi-platform native artifacts:
  - `connectanum_client` and `connectanum_router` explicit installer helpers
    now map the same release target triples as the hosted artifact matrix:
    Linux x64, Linux arm64, macOS x64, macOS arm64, and Windows x64
  - focused installer tests cover the hosted matrix mapping and unsupported
    host/architecture errors
- Completed hosted validation for the installer-coverage slice:
  - commit `39e68b1` (`installer: cover native release artifact matrix`) passed
    GitHub `CI` run `25052974513`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was skipped
    inside the main CI workflow
  - GitHub `WAMP Profile Benchmarks` run `25052974498` passed the Linux
    canonical WAMP profile gate and uploaded its artifacts
- Recorded the docs-only validation checkpoint:
  - commit `34cf2cd` (`docs: record installer ci success`) passed GitHub `CI`
    run `25053975131`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was skipped
    as expected for a docs-only push
- Completed the first real GitHub Release install validation:
  - manual `Native Artifacts` run `25054948537` passed all Linux, macOS, and
    Windows native artifact legs plus `Publish GitHub Release`
  - the workflow created prerelease
    `ct-ffi-v2026.04.28-validation.34cf2cd`
  - source-checkout installer smoke validation passed on macOS arm64 with
    `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.34cf2cd`
- Started the public install-instructions correction:
  - release-note generation and public docs now prefer
    `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for hook-managed downloads
  - direct `dart packages/.../tool/install_native.dart` commands are described
    as source-checkout prefetch helpers, not package `dart run` executables
  - `bin/validate-native-release-install` codifies the release install smoke
    test for future validation tags
- Completed hosted validation for the public install-instructions correction:
  - commit `c925e1e` (`docs: clarify native release install path`) passed
    GitHub `CI` run `25055877717`
  - GitHub `WAMP Profile Benchmarks` run `25055877739` passed the Linux
    canonical WAMP profile gate
- Recorded the docs-only validation checkpoint:
  - commit `51f7061` (`docs: record install path ci success`) passed GitHub
    `CI` run `25056742848`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was skipped
    as expected for a docs-only push
- Completed corrected release-note validation:
  - manual `Native Artifacts` dry-run `25057503370` passed all Linux, macOS,
    and Windows native artifact legs, rendered `native-release-preview`, and
    did not create `ct-ffi-v2026.04.28-dry-run.51f7061`
  - the rendered preview documented
    `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for normal hook-managed downloads
    and direct `dart packages/.../tool/install_native.dart` commands only for
    source-checkout prefetches
- Completed a real corrected validation prerelease:
  - manual `Native Artifacts` run `25057834597` created prerelease
    `ct-ffi-v2026.04.28-validation.51f7061`
  - the prerelease contains 30 hosted matrix assets for Linux x64, Linux arm64,
    macOS Apple Silicon, macOS Intel, and Windows x64
  - source-checkout installer smoke validation passed with
    `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.51f7061`
- Removed an upstream action warning from the native publish job:
  - commit `95837fb` (`ci: download native artifacts with gh`) replaced
    `actions/download-artifact@v8` with `gh run download` in the
    `Publish GitHub Release` job
  - the job now uses explicit `actions: read` permission and flattens
    downloaded `ct-ffi-*` artifact files into `out/github-release`
  - GitHub `CI` run `25059702813` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped as expected for the workflow-only push
  - manual `Native Artifacts` dry-run `25060480993` passed all Linux, macOS,
    and Windows native artifact legs plus the preview publish job
  - hosted log scanning confirmed the previous Node `Buffer()` deprecation from
    `actions/download-artifact` is gone
- Added a pre-mutation release-intent safety gate for native GitHub Release
  publishing:
  - manual non-prerelease workflow dispatches now require
    `stable_release_approval` to exactly match `release_tag`
  - `tool/validate_native_release_intent.py` rejects malformed release tags,
    publishing of `-dry-run` tags, non-prerelease `-validation` publishes, and
    unapproved manual stable release publishes before the workflow reaches
    `gh release create` or `gh release edit`
  - this keeps dry-run and validation release work autonomous while making a
    stable non-validation release require an explicit operator/product decision
- Completed hosted validation for the release-intent safety gate:
  - commit `8dc966f` (`ci: guard manual stable native releases`) passed GitHub
    `CI` run `25063769464`
  - manual `Native Artifacts` dry-run `25063774771` passed all Linux, macOS,
    and Windows native artifact legs plus the preview publish job
  - the hosted `Validate release intent` step accepted
    `ct-ffi-v2026.04.28-dry-run.8dc966f` as `(native, dry-run)`
  - the dry-run preview still listed all 30 expected native release assets and
    did not create a GitHub Release
- Started a CI-log cleanup slice from the final `8dc966f` hosted log scan:
  - the branch was green, but `Fast Checks` printed a passing-test rawsocket
    reader line containing `io error: Connection reset by peer` during the
    native RawSocket MsgPack cancel-cycle workload
  - the rawsocket frame reader now uses `is_benign_socket_shutdown` so expected
    peer shutdowns are quiet, matching the existing WebSocket shutdown
    classification
- Completed hosted validation for the rawsocket benign-shutdown log cleanup:
  - commit `6a6f036` (`native: quiet benign rawsocket shutdowns`) passed GitHub
    `CI` run `25065253852`
  - GitHub `kTLS Validation` run `25065253836` passed
  - hosted log scanning found no `Connection reset by peer` or
    `connection ConnectionId` lines on the cleaned-up run
- Started a CI-timeout hardening slice after docs checkpoint `d0afe06` left
  GitHub `CI` run `25066016309` with `Full Verify` in progress for more than
  30 minutes:
  - the previous comparable hosted full-verify job completed in about
    9 minutes, so this is being treated as a stalled runner/status issue
  - the stale unbounded run was cancelled after the timeout-hardening slice
    started, so the next pushed head can provide the branch-cleanliness signal
  - all GitHub workflows now use job-level `timeout-minutes` so a stuck job
    fails closed instead of leaving the branch indefinitely pending
  - timeout budgets remain generous relative to recent hosted runs: 20 minutes
    for fast checks, 45 minutes for full verify and native packaging,
    30-45 minutes for validation/gate jobs, and 120 minutes for long manual
    image or kTLS benchmark jobs
- Completed hosted validation for the CI-timeout hardening slice:
  - commit `ccb61f9` (`ci: bound github workflow runtimes`) passed GitHub
    `CI` run `25068442355`
  - GitHub `kTLS Validation` run `25068442344` passed
  - GitHub `WAMP Profile Benchmarks` run `25068442348` passed
  - GitHub `WAMP Profile Diagnostics` run `25068442381` passed
  - hosted log scanning found no warnings, deprecations, rawsocket reset noise,
    timeouts, cancellations, or real errors; remaining `failed` matches were
    passing test names or Rust test summaries
- Started the Dart package publishing readiness slice:
  - added package-root MIT `LICENSE` files to every workspace package so future
    pub archives satisfy the mandatory license check
  - added GitHub `homepage`, `repository`, and `issue_tracker` metadata across
    package pubspecs
  - `dart pub publish --dry-run` now passes locally for
    `packages/connectanum_client` with `Package has 0 warnings`
  - `docs/dart_package_publishing.md` records the remaining blocker: pub.dev
    currently returns `404` for `connectanum_client` and `connectanum_core`,
    while `connectanum_client` depends on `connectanum_core: ^0.1.0`
  - no package publish, package-name claim, or `publish_to: none` removal has
    been attempted; those still require an explicit operator/product decision
- Completed a clean-CI recovery slice after documentation checkpoint `cb55b1f`
  left GitHub `CI` run `25095210918` red in `Full Verify`:
  - hosted failure:
    `tests::listen_flow::poll_connection_message_returns_payload` timed out
    waiting for a RawSocket connection
  - local reproduction reached the same polling path and failed because the
    client stream could close before the message was visible to
    `ct_poll_connection_message`
  - the test now keeps the client alive with an explicit release signal while
    the polling side waits for the message
  - the hosted Linux kTLS dead-code warning is being fixed by using
    `server_runtime_required` for optional-vs-required kTLS failure logging,
    not by deleting the helper
  - local focused checks, `bin/test-fast`, and `bin/verify` passed after the
    fix
  - commit `cf77754` (`native: stabilize rawsocket polling test`) passed
    hosted GitHub `CI` run `25096329599`; `Fast Checks` completed in 5m28s and
    `Full Verify` completed in 7m53s
  - companion hosted runs also passed on `cf77754`: `kTLS Validation`
    `25096329602` and `WAMP Profile Benchmarks` `25096329606`
  - the GitHub deployment-chain audit with `--require-clean-latest-ci` passed
    against `cf77754`, and hosted log scanning found no real warnings,
    deprecations, rawsocket reset noise, connection ID noise, or skipped-test
    output
- Completed hosted validation for the Dart package publishing readiness slice:
  - commit `1b95c9d` (`docs: prepare dart package publishing`) passed GitHub
    `CI` run `25071505471`
  - GitHub `WAMP Profile Benchmarks` run `25071505445` passed
  - hosted log scanning found no warnings, deprecations, rawsocket reset noise,
    timeouts, cancellations, or real errors; remaining matches were passing
    test names or Rust test summaries
- Recorded the Dart package publishing docs checkpoint and started branch
  protection/release evidence:
  - commit `4b17fa6` (`docs: record package publish readiness ci`) passed
    GitHub `CI` run `25072248218`
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were passing
    test names or Rust test summaries
  - `bin/audit-github-deployment-chain` now provides a repeatable read-only
    audit of repository metadata, branch protection, rulesets, active
    workflows, and recent branch runs
  - `docs/github_deployment_chain.md` records the current GitHub controls,
    release evidence policy, and the branch-protection gap: `master` is
    protected but has no required status checks
  - no remote branch protection was changed autonomously
- Completed hosted validation for the branch-protection/release-evidence audit:
  - commit `be37ec4` (`docs: add github deployment audit`) passed GitHub `CI`
    run `25073711527`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was
    skipped as expected for a non-manual CI run
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were passing
    test names or Rust test summaries
- Recorded the deployment-audit docs checkpoint:
  - commit `21a998d` (`docs: record github deployment audit ci`) passed
    GitHub `CI` run `25074424163`
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were passing
    test names or Rust test summaries
- Started the router-image release-evidence cleanup:
  - GitHub does not currently expose `.github/workflows/router-image.yml`
    through the workflow API because that workflow is not on the default branch
  - `gh workflow view router-image.yml` returns `404`, and GitHub Packages
    returns `404` for `ghcr.io/konsultaner/connectanum-router`
  - `README.md` and `docs/deployment.md` now describe the router image as a
    staged intended release target instead of a published artifact
  - `deploy/k8s/connectanum-router.yaml` now uses a `replace-me` image tag
    instead of the unavailable floating `latest` tag
  - `bin/audit-github-deployment-chain` now reports checked-in workflow
    visibility and GHCR router package visibility
- Completed hosted validation for the router-image release-evidence cleanup:
  - commit `ad6412d` (`docs: correct router image release evidence`) passed
    GitHub `CI` run `25077069136`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was
    skipped as expected for a non-manual CI run
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a passing
    bcrypt test name and Rust `0 failed` summaries
- Recorded the router-image evidence docs checkpoint and started publish-safety
  hardening:
  - commit `391590d` (`docs: record router image evidence ci`) passed GitHub
    `CI` run `25077810300`
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a passing
    bcrypt test name and Rust `0 failed` summaries
  - `.github/workflows/router-image.yml` now defaults manual dispatch to a
    dry-run build and requires `publish_approval` to exactly match the primary
    image tag for manual GHCR publishes
  - `tool/render_router_image_metadata.py` makes router image tag/label and
    publish-intent resolution locally testable
  - local `bin/verify` passed after the workflow, tool, and documentation
    changes, including the Chrome browser-platform test
- Completed hosted validation for the router-image publish-safety hardening:
  - commit `be29fe6` (`ci: gate router image manual publishes`) passed GitHub
    `CI` run `25080054856`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was
    skipped as expected for a normal push
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a passing
    bcrypt test name and Rust `0 failed` summaries
- Recorded the router-image publish-safety docs checkpoint:
  - commit `b6d05ca` (`docs: record router image publish gate ci`) passed
    GitHub `CI` run `25080633807`
  - `Fast Checks` and `Full Verify` succeeded; `WAMP Profile Gates` was
    skipped as expected for a docs-only push
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a passing
    bcrypt test name and Rust `0 failed` summaries
- Started the Dart package publish dry-run evidence slice:
  - `bin/dart-package-publish-dry-run` discovers publishable workspace
    packages, skips `publish_to: none` packages by default, and runs
    `dart pub publish --dry-run` for every publishable package
  - `.github/workflows/dart-package-publish.yml` runs the dry-run on package
    metadata/docs/license/changelog changes and manual dispatch
  - this keeps pub.dev archive validation hosted and repeatable without
    publishing packages or changing package ownership/version policy
- Completed hosted validation for the Dart package publish dry-run evidence:
  - commit `d9cbd81` (`ci: add dart package publish dry run`) passed GitHub
    `CI` run `25082475062`
  - the new `Dart Package Publish Dry Run` workflow run `25082475073` passed
    and validated `connectanum_client` with `dart pub publish --dry-run`
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a passing
    bcrypt test name and Rust `0 failed` summaries
- Started Dart package release-readiness blocker enforcement:
  - `bin/dart-package-publish-dry-run` now reports publishable packages that
    depend on private workspace packages
  - default mode keeps archive validation green while surfacing the blocker
  - `--strict-release-ready` exits non-zero on the current
    `connectanum_client` -> private `connectanum_core` dependency until the
    package release plan is approved and resolved
- Completed hosted validation for Dart package release-readiness blocker
  reporting:
  - commit `ee32ad3` (`ci: report dart package release blockers`) passed
    GitHub `CI` run `25084695576`
  - GitHub `Dart Package Publish Dry Run` run `25084695572` passed and
    surfaced the current private-workspace dependency blocker without
    publishing to pub.dev
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a passing
    bcrypt test name and Rust `0 failed` summaries
- Completed hosted validation for the clean-latest-CI audit gate:
  - commit `1769982` (`ci: audit latest ci job cleanliness`) passed GitHub
    `CI` run `25087405841`
  - `Fast Checks` and `Full Verify` completed successfully, with no skipped,
    pending, failed, missing, or unexpected main `CI` jobs
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a passing
    bcrypt test name and Rust `0 failed` summaries
- Started branch-protection operator-plan hardening:
  - `bin/audit-github-deployment-chain --branch master
    --show-required-checks-plan` prints the minimal required-status-check
    payload for `Fast Checks` and `Full Verify`
  - the audit remains read-only and does not apply branch protection; remote
    policy mutation remains blocked on explicit operator approval
- Completed hosted validation for the branch-protection operator plan:
  - commit `a3ae4a3` (`ci: print branch protection check plan`) passed GitHub
    `CI` run `25088676567`
  - `Fast Checks` and `Full Verify` completed successfully, with no skipped,
    pending, failed, missing, or unexpected main `CI` jobs
  - the read-only `master` audit prints the required-status-check operator
    payload for `Fast Checks` and `Full Verify`, while still leaving the
    actual branch-protection mutation blocked on explicit operator approval
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, skipped jobs, or errors; remaining matches
    were a passing bcrypt negative-auth test name and Rust `0 failed` summaries
- Completed hosted validation for the branch-protection audit docs checkpoint:
  - commit `3db2bbe` (`docs: record branch protection audit ci`) passed GitHub
    `CI` run `25089948391`
  - `Fast Checks` and `Full Verify` completed successfully, with no skipped,
    pending, failed, missing, or unexpected main `CI` jobs
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, skipped jobs, or errors; remaining matches
    were a passing bcrypt negative-auth test name and Rust `0 failed` summaries
- Started the public deployment-evidence refresh:
  - `docs/github_deployment_chain.md` now directs volatile branch-head status
    checks to the live clean-CI audit command
  - the same page lists pinned deployment-chain checkpoints so public release
    evidence stays readable without requiring a self-referential update after
    every docs-only checkpoint
- Started the router package release-readiness audit gate:
  - `bin/audit-github-deployment-chain --require-router-package` now fails
    independently when `ghcr.io/konsultaner/connectanum-router` is not visible
    through the GitHub Packages API
  - the gate is intentionally non-mutating and keeps the router image publish
    blocker visible without dispatching, publishing, or changing repository
    settings
  - focused local checks passed: `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`, `git diff --check`,
    `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 2 --require-clean-latest-ci`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 2 --require-router-package`
    failed as expected because the GHCR router package is not published or
    visible yet
  - final local `bin/verify` passed, including full router coverage,
    `remote_auth_integration_test`, bench WAMP transport coverage, and Chrome
    Dart2Wasm browser websocket coverage
- Completed hosted validation for the router package audit-gate slice:
  - commit `c061ae3` (`ci: gate router package visibility audit`) passed
    GitHub `CI` run `25092705443`
  - `Fast Checks` completed successfully in 5m38s
  - `Full Verify` completed successfully in 7m55s
  - the clean-CI audit passed against `c061ae3`, confirming no skipped,
    pending, failed, missing, or unexpected main `CI` jobs
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, skipped jobs, or errors; remaining matches
    were a passing bcrypt negative-auth test name and Rust `0 failed` summaries
- Started the workflow visibility audit gate:
  - `bin/audit-github-deployment-chain --require-workflows-visible` now fails
    independently when any checked-in `.github/workflows/*.yml` or `.yaml`
    file is not discoverable through the GitHub Actions API
  - the gate is intentionally non-mutating and keeps the router image
    default-branch promotion blocker visible without changing repository
    settings or publishing images
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - focused local checks passed: `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`, `git diff --check`,
    `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 2 --require-clean-latest-ci`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 2 --require-workflows-visible`
    failed as expected because `.github/workflows/router-image.yml` is not
    discoverable through the GitHub Actions API yet
  - final local `bin/verify` passed, including full router coverage,
    `remote_auth_integration_test`, bench WAMP transport coverage, and Chrome
    Dart2Wasm browser websocket coverage
- Completed hosted validation for the workflow visibility audit-gate slice:
  - commit `55e9dc0` (`ci: gate workflow visibility audit`) passed GitHub
    `CI` run `25094700697`
  - `Fast Checks` completed successfully in 5m33s
  - `Full Verify` completed successfully in 8m10s
  - the clean-CI audit passed against `55e9dc0`, confirming no skipped,
    pending, failed, missing, or unexpected main `CI` jobs
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, skipped jobs, or errors; remaining matches
    were a passing bcrypt negative-auth test name and Rust `0 failed` summaries
- Started the repeatable hosted CI log-scan gate:
  - `bin/audit-github-deployment-chain --scan-latest-ci-logs` now prints
    high-signal warning, deprecation, skipped-test, rawsocket reset, and
    connection-noise matches from the latest hosted `CI` run
  - `--require-clean-latest-ci-logs` exits non-zero on those matches or when
    the latest `CI` logs are not a complete green signal
  - the release-evidence policy now uses
    `--require-clean-latest-ci --require-clean-latest-ci-logs` as the
    repeatable clean branch-head gate instead of relying on manual log scans
  - focused local checks passed against latest hosted GitHub `CI` run
    `25096910826` on `869bb7f`, including the clean job audit and the new
    clean log-scan audit
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
- Completed hosted validation for the repeatable CI log-scan audit gate:
  - commit `bd99fcc` (`ci: audit hosted ci logs`) passed GitHub `CI` run
    `25099086900`
  - `Fast Checks` completed successfully in 5m48s
  - `Full Verify` completed successfully in 8m9s
  - the combined clean branch-head audit passed:
    `bin/audit-github-deployment-chain --branch add-router --run-limit 4 --require-clean-latest-ci --require-clean-latest-ci-logs`
  - the new log scan found no high-signal warning, deprecation, skipped-test,
    rawsocket reset, or connection-noise matches
- Started Dart package publish warning-gate hardening:
  - `bin/dart-package-publish-dry-run` now requires each publishable
    `dart pub publish --dry-run` to report `Package has 0 warnings`
  - the default local dry-run still passes for `connectanum_client`, reports
    the current private `connectanum_core` dependency blocker, and now prints
    `All Dart package publish dry-runs reported zero warnings`
  - `--strict-release-ready` still fails as expected on the current
    release-order blocker until the Dart package publish plan is approved
  - pre-change `bin/test-fast` passed locally
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
- Completed hosted validation for the Dart package publish warning gate:
  - commit `1131e7e` (`ci: require zero-warning dart publish dry runs`) passed
    GitHub `CI` run `25102015230`
  - `Fast Checks` completed successfully in 5m30s
  - `Full Verify` completed successfully in 8m14s
  - hosted `Dart Package Publish Dry Run` run `25102015241` passed and logged
    `Package has 0 warnings` plus
    `All Dart package publish dry-runs reported zero warnings`
  - the combined clean branch-head audit passed:
    `bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs`
  - the audit log scan found no high-signal warning, deprecation,
    skipped-test, rawsocket reset, or connection-noise matches
- Started release-candidate readiness audit hardening:
  - `bin/audit-github-deployment-chain` now has `--show-rc-readiness` and
    `--require-rc-ready` modes so RC status is checked repeatably against
    clean hosted CI/logs, baseline branch protection, workflow visibility,
    router package visibility, RC tag/GitHub prerelease evidence, and strict
    Dart package dry-run readiness
  - pre-change `bin/test-fast` passed locally
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain` and
    `bin/audit-github-deployment-chain --help`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`
    completed successfully and reported the current branch as not RC-ready
    without failing the command
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-rc-ready`
    failed as expected: hosted CI/log gates are clean, while the actual RC
    blockers remain branch protection, router workflow/package publication,
    missing RC tag/prerelease evidence, and the strict Dart package
    release-order blocker
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
- Completed hosted validation for release-candidate readiness audit hardening:
  - commit `b747033` (`ci: add release candidate readiness audit`) passed
    GitHub `CI` run `25105031469`
  - `Fast Checks` completed successfully in 5m53s
  - `Full Verify` completed successfully in 8m01s
  - the clean branch-head audit passed:
    `bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs`
  - the hosted log scan found no high-signal warning, deprecation,
    skipped-test, rawsocket reset, or connection-noise matches
- Started Dart package release-order plan surfacing:
  - latest clean branch-head audit/log scan passed against documentation
    checkpoint `578a3f8`, confirming the hosted `CI` chain remains green
    before the next slice
  - `bin/dart-package-publish-dry-run --show-release-plan` now prints the
    current non-mutating public package order:
    `connectanum_core 0.1.0` before `connectanum_client 2.2.6`
  - `bin/audit-github-deployment-chain --show-rc-readiness` includes that
    package release-order plan when the strict Dart package gate blocks RC
    readiness, keeping the blocker actionable from the primary audit command
  - final local `bin/verify` passed after the script and documentation changes
  - no package was made publishable and no pub.dev publish was attempted
- Completed hosted validation for Dart package release-order plan surfacing:
  - commit `700ea74` (`ci: explain dart package release order`) passed GitHub
    `CI` run `25107394525`
  - `Fast Checks` completed successfully in 5m28s
  - `Full Verify` completed successfully in 7m55s
  - hosted `Dart Package Publish Dry Run` run `25107394513` passed on the same
    commit
  - the clean branch-head audit passed:
    `bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs`
  - the hosted log scan found no high-signal warning, deprecation,
    skipped-test, rawsocket reset, or connection-noise matches
- Started Dart package hosted dry-run audit hardening:
  - commit `a67b86d` passed GitHub `CI` run `25109971104` with
    `Fast Checks` in 5m18s and `Full Verify` in 8m14s
  - branch-head deployment audit passed for `a67b86d` with clean main `CI`,
    clean hosted `CI` logs, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - documentation checkpoint `47c3948` passed GitHub `CI` run `25108057451`
    with `Fast Checks` in 5m29s and `Full Verify` in 7m55s
  - `bin/audit-github-deployment-chain --show-dart-package-publish-dry-run`
    now prints the latest dedicated `Dart Package Publish Dry Run` workflow,
    expected `Publish Dry Run` job status, and whether that run still covers
    the checked-out package-publishing inputs
  - `--require-clean-dart-package-publish-dry-run` fails when the dedicated
    hosted package dry-run is missing, not green, has skipped/unexpected jobs,
    or is older than the checked-out package-sensitive inputs
  - `--show-rc-readiness` and `--require-rc-ready` include this hosted package
    dry-run gate before the strict local Dart package release-order gate
- Started router image attestation hardening:
  - commit `449b218` (`ci: attest router image publishes`) passed GitHub
    `CI` run `25112417559`; `Fast Checks` and `Full Verify` succeeded
  - branch-head deployment audit passed for `449b218` with clean main `CI`,
    clean hosted `CI` logs, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - documentation checkpoint `f946e18` passed GitHub `CI` run `25110768881`
    and the branch-head audit passed with clean main `CI`, clean hosted `CI`
    logs, and clean/relevant hosted `Dart Package Publish Dry Run` evidence
  - the router image metadata helper now emits explicit provenance/SBOM
    settings so publish builds request `provenance=mode=max` and `sbom=true`
    while dry-run cache-only builds keep image attestations disabled
- Started router image dry-run preview hardening:
  - commit `8fe3749` (`ci: upload router image dry-run preview`) passed
    GitHub `CI` run `25116155461`; `Fast Checks` completed in 5m26s and
    `Full Verify` completed in 7m58s
  - branch-head deployment audit passed for `8fe3749` with clean main `CI`,
    clean hosted `CI` logs, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - commit `a8260b5` (`docs: record router image attestation ci`) passed
    GitHub `CI` run `25113406609`; `Fast Checks` and `Full Verify` succeeded
  - branch-head deployment audit passed for `a8260b5` with clean main `CI`,
    clean hosted `CI` logs, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - manual router image dry-runs now write
    `out/router-image-preview/router-image-metadata.md`, append that content
    to the Actions step summary, and upload it as `router-image-preview`
  - deployment-chain docs describe the downloadable dry-run preview artifact
    alongside the existing non-mutating publish gate and attestation behavior
- Started native release dry-run audit hardening:
  - commit `bf79824` (`docs: record router image preview ci`) passed GitHub
    `CI` run `25116939802`; `Fast Checks` completed in 5m26s and
    `Full Verify` completed in 8m12s
  - branch-head deployment audit passed for `bf79824` with clean main `CI`,
    clean hosted `CI` logs, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - `bin/audit-github-deployment-chain` now exposes
    `--show-native-release-dry-run` and
    `--require-clean-native-release-dry-run`
  - the native gate checks the expected hosted Linux, macOS, and Windows
    `ct_ffi` artifact jobs, verifies the preview publish job, checks accepted
    native dry-run intent and `native-release-preview` upload, confirms the
    dry-run tag did not create a GitHub Release, and reports
    native-release-sensitive changes since the latest dry-run
  - the prior latest hosted `Native Artifacts` dry-run was correctly marked
    stale until a fresh dry-run covered native release changes after `8dc966f`
  - commit `d4e6fda` (`ci: audit native release dry runs`) passed GitHub
    `CI` run `25119596673`; `Fast Checks` completed in 5m40s and
    `Full Verify` completed in 8m19s
  - manual `Native Artifacts` dry-run `25119602651` passed all hosted Linux,
    macOS, and Windows `ct_ffi` artifact jobs plus `Publish GitHub Release`
    on `d4e6fda`
  - the fresh dry-run accepted
    `ct-ffi-v2026.04.29-dry-run.d4e6fda`, uploaded
    `native-release-preview`, did not create a GitHub Release for that tag,
    and now satisfies the required native dry-run audit gate for the
    checked-out head
- Refreshed branch-head deployment evidence after the native audit checkpoint:
  - documentation checkpoint `a358f43`
    (`docs: record native release dry run audit ci`) passed GitHub `CI` run
    `25120747925`; `Fast Checks` completed in 5m37s and `Full Verify`
    completed in 8m15s
  - fresh manual `Dart Package Publish Dry Run` run `25122605506` passed on
    `a358f43`; `Publish Dry Run` completed in 20s and covers the checked-out
    package-publishing inputs
  - branch-head deployment audit passed for `a358f43` with clean main `CI`,
    clean hosted `CI` logs, clean/relevant hosted
    `Dart Package Publish Dry Run` evidence, and clean/relevant hosted
    `Native Artifacts` dry-run evidence

## Verification

- `bin/test-fast` before substantial implementation changes.
- `bin/verify` before handoff when local code or workflow behavior changes.
- Hosted GitHub Actions run IDs for every pushed deployment-chain slice.
- Current Windows artifact slice local checks:
  - `bin/test-fast`
  - `dart test packages/connectanum_client/test/hook/build_hook_test.dart`
  - `dart test packages/connectanum_router/test/hook/build_hook_test.dart`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml')"`
  - `git diff --check`
  - `rustup target add x86_64-pc-windows-msvc && cargo check --manifest-path native/transport/Cargo.toml -p ct_ffi --target x86_64-pc-windows-msvc` was attempted locally, but macOS lacks the Windows MSVC C toolchain/headers needed by `ring`; hosted Windows validation is the required signal.
- Manual hosted `Native Artifacts` run `25047530571` on `9bfdee1` proved the
  new Windows x64 leg can build, package, sign, and verify `ct_ffi`, but it
  failed in `actions/attest@v4` because Windows treated the multiline
  `subject-path` as one literal path. The follow-up workflow fix splits archive,
  checksum, and manifest attestations into separate single-subject steps.
- Manual hosted `Native Artifacts` run `25047880947` on `f26f358` proved the
  split attestation steps work on Linux and macOS, but Windows still could not
  resolve the Git Bash `/d/a/...` path inside the Node-based attestation action.
  The follow-up workflow fix keeps POSIX paths for shell/cosign and uses
  workspace-relative paths for `actions/attest` and `actions/upload-artifact`.
- Local `bin/verify` passed on macOS after the workspace-relative GitHub
  Actions path fix. An earlier local `bin/verify` attempt failed because the
  autonomous launchd runner was holding the shared native runtime lock during
  its own `bin/test-fast`; rerunning after the lock was released passed.
- GitHub-hosted deployment-chain validation is clean for the Windows native
  artifact slice:
  - `CI` run `25048277995` passed on `86a4e7c`
  - manual `Native Artifacts` run `25048283917` passed on `86a4e7c`
- Current release-dry-run slice focused local checks:
  - `bin/test-fast`
  - `python3 -m py_compile tool/render_native_release_notes.py tool/test_render_native_release_notes.py`
  - `python3 tool/test_render_native_release_notes.py`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml')"`
  - `python3 tool/render_native_release_notes.py --release-tag ct-ffi-v2026.04.28-preview --repository konsultaner/connectanum-dart --server-url https://github.com --commit HEAD --workflow-ref konsultaner/connectanum-dart/.github/workflows/native-artifacts.yml@refs/heads/add-router --owner konsultaner`
  - `bin/verify`
- Hosted release-dry-run checks:
  - GitHub `CI` run `25050575954` passed on `7b45ede`
  - manual `Native Artifacts` run `25051217251` passed on `7b45ede` with
    artifacts `native-release-preview`,
    `ct-ffi-x86_64-pc-windows-msvc`, `ct-ffi-x86_64-apple-darwin`,
    `ct-ffi-aarch64-apple-darwin`, `ct-ffi-x86_64-unknown-linux-gnu`, and
    `ct-ffi-aarch64-unknown-linux-gnu`
- Documentation checkpoint `d3ecfd1` passed hosted GitHub `CI` run
  `25051747670`.
- Current installer-coverage slice focused local checks:
  - `bin/test-fast`
  - `dart test packages/connectanum_client/test/hook/install_native_test.dart`
  - `dart test packages/connectanum_router/test/hook/install_native_test.dart`
  - `bin/verify`
- Hosted installer-coverage checks on `39e68b1`:
  - GitHub `CI` run `25052974513`
  - GitHub `WAMP Profile Benchmarks` run `25052974498`
- Documentation checkpoint `34cf2cd` passed hosted GitHub `CI` run
  `25053975131`.
- Native release/install checks:
  - GitHub `Native Artifacts` run `25054948537`
  - `bash -n bin/validate-native-release-install`
  - `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.34cf2cd`
- Current public install-instructions focused local checks:
  - `python3 -m py_compile tool/render_native_release_notes.py tool/test_render_native_release_notes.py`
  - `python3 tool/test_render_native_release_notes.py`
  - `git diff --check`
  - `bin/verify`
- Hosted public install-instructions checks on `c925e1e`:
  - GitHub `CI` run `25055877717`
  - GitHub `WAMP Profile Benchmarks` run `25055877739`
- Documentation checkpoint `51f7061` passed hosted GitHub `CI` run
  `25056742848`.
- Corrected native release-note dry-run checks:
  - GitHub `Native Artifacts` dry-run `25057503370`
  - inspected `native-release-preview/release-notes.md`
  - `gh release view ct-ffi-v2026.04.28-dry-run.51f7061` returned
    `release not found`
- Corrected validation prerelease checks:
  - GitHub `Native Artifacts` run `25057834597`
  - `gh release view ct-ffi-v2026.04.28-validation.51f7061` confirmed a
    prerelease targeting `51f706179e9ec654639c19e170f38fd2d03573da` with 30
    assets
  - `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.51f7061`
- Native artifact publish-job warning cleanup checks:
  - `bin/test-fast`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml')"`
  - `git diff --check`
  - GitHub `CI` run `25059702813`
  - GitHub `Native Artifacts` dry-run `25060480993`
  - inspected `native-release-preview/release-metadata.txt` and confirmed all
    30 expected release assets remain present
  - `gh release view ct-ffi-v2026.04.28-dry-run.95837fb` returned
    `release not found`
  - hosted log scan found no `DeprecationWarning`, `warning:`, or `::warning`
    lines after replacing `actions/download-artifact@v8`; the only match was a
    Cosign installer shell alias containing the literal text `ERROR:`
- Release-intent safety gate checks:
  - `bin/test-fast`
  - `python3 -m py_compile tool/validate_native_release_intent.py tool/test_validate_native_release_intent.py`
  - `python3 tool/test_validate_native_release_intent.py`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml')"`
  - accepted-intent CLI smoke checks for dry-run, validation prerelease, and
    explicitly approved manual stable native release inputs
  - `git diff --check`
  - `bin/verify`
- Hosted release-intent safety gate checks:
  - GitHub `CI` run `25063769464`
  - GitHub `Native Artifacts` dry-run `25063774771`
  - `gh release view ct-ffi-v2026.04.28-dry-run.8dc966f` returned
    `release not found`
- Rawsocket benign-shutdown log cleanup checks:
  - `cargo test --manifest-path native/transport/Cargo.toml -p ct_core websocket_io_disconnects_are_classified_as_peer_shutdowns -- --nocapture`
  - `bin/test-fast`
  - `bin/verify`
  - GitHub `CI` run `25065253852`
  - GitHub `kTLS Validation` run `25065253836`
  - hosted log scan for `Connection reset by peer`,
    `connection ConnectionId`, warnings, and deprecations
- Current CI-timeout hardening checks:
  - `bin/test-fast`
  - workflow YAML parsing across `.github/workflows/*.yml`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25068442355`
  - GitHub `kTLS Validation` run `25068442344`
  - GitHub `WAMP Profile Benchmarks` run `25068442348`
  - GitHub `WAMP Profile Diagnostics` run `25068442381`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
- Current Dart package publishing readiness checks:
  - `bin/test-fast`
  - `dart pub publish --dry-run` from `packages/connectanum_client`
  - pub.dev API probes for `connectanum_client` and `connectanum_core`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25071505471`
  - GitHub `WAMP Profile Benchmarks` run `25071505445`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
- Current branch-protection/release-evidence checks:
  - GitHub `CI` run `25072248218`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
  - `bin/test-fast`
  - `bin/audit-github-deployment-chain --branch master --run-limit 4`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 6`
  - strict-mode smoke test confirming the known `master` required-check gap
    exits non-zero
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25073711527`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
- Current router-image release-evidence checks:
  - GitHub `CI` run `25074424163`
  - GitHub `CI` run `25077810300`
  - `bin/test-fast`
  - `bash -n bin/audit-github-deployment-chain`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 2`
  - strict-mode smoke test confirming known release-readiness gaps exit
    non-zero
  - `git diff --check`
  - `bin/verify`
- Current router-image publish-safety checks:
  - `bin/test-fast`
  - `python3 -m py_compile tool/render_router_image_metadata.py tool/test_render_router_image_metadata.py`
  - `python3 tool/test_render_router_image_metadata.py`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml')"`
  - CLI smoke render for a stable tag-push metadata set
  - CLI smoke rejection for a manual publish without matching
    `publish_approval`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 2`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25080054856`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
- Current Dart package publish dry-run checks:
  - GitHub `CI` run `25080633807`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
  - `bin/test-fast`
  - `bash -n bin/dart-package-publish-dry-run`
  - workflow YAML parsing for `.github/workflows/dart-package-publish.yml`
  - `bin/dart-package-publish-dry-run`
  - expected failing `bin/dart-package-publish-dry-run --strict-release-ready`
    blocker check
  - `bin/verify`
  - GitHub `CI` run `25082475062`
  - GitHub `Dart Package Publish Dry Run` run `25082475073`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
  - GitHub `CI` run `25084695576`
  - GitHub `Dart Package Publish Dry Run` run `25084695572`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
- Current Dart package release-order plan checks:
  - `bin/test-fast`
  - `bash -n bin/dart-package-publish-dry-run`
  - `bash -n bin/audit-github-deployment-chain`
  - `bin/dart-package-publish-dry-run --help`
  - `bin/dart-package-publish-dry-run --show-release-plan`
  - expected failing
    `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`
  - `git diff --check`
  - `bin/verify`
- Current Dart package hosted dry-run audit checks:
  - `bin/test-fast`
  - `bash -n bin/audit-github-deployment-chain`
  - `bin/audit-github-deployment-chain --help`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --show-dart-package-publish-dry-run`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-dart-package-publish-dry-run`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 2 --show-rc-readiness`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25109971104`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
- Current router image attestation checks:
  - `bin/test-fast`
  - `python3 -m py_compile tool/render_router_image_metadata.py tool/test_render_router_image_metadata.py`
  - `python3 tool/test_render_router_image_metadata.py`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml'); puts 'yaml_ok'"`
  - `python3 tool/render_router_image_metadata.py --owner konsultaner --repository konsultaner/connectanum-dart --sha 0123456789abcdef0123456789abcdef01234567 --ref-type branch --ref-name add-router --event-name workflow_dispatch --dry-run true`
  - `python3 tool/render_router_image_metadata.py --owner konsultaner --repository konsultaner/connectanum-dart --sha 0123456789abcdef0123456789abcdef01234567 --ref-type tag --ref-name v1.2.3 --event-name push --dry-run false`
  - expected failing manual publish rejection smoke:
    `python3 tool/render_router_image_metadata.py --owner konsultaner --repository konsultaner/connectanum-dart --sha 0123456789abcdef0123456789abcdef01234567 --ref-type branch --ref-name add-router --event-name workflow_dispatch --input-image-tag validation-abc1234 --dry-run false --publish-approval wrong-tag`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25112417559`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
- Current router image dry-run preview checks:
  - `bin/test-fast`
  - `python3 -m py_compile tool/render_router_image_metadata.py tool/test_render_router_image_metadata.py`
  - `python3 tool/test_render_router_image_metadata.py`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml'); puts 'yaml_ok'"`
  - `python3 tool/render_router_image_metadata.py --owner konsultaner --repository konsultaner/connectanum-dart --sha 0123456789abcdef0123456789abcdef01234567 --ref-type branch --ref-name add-router --event-name workflow_dispatch --dry-run true --summary /tmp/router-image-metadata.md`
  - `test -s /tmp/router-image-metadata.md`
  - `python3 tool/render_router_image_metadata.py --owner konsultaner --repository konsultaner/connectanum-dart --sha 0123456789abcdef0123456789abcdef01234567 --ref-type tag --ref-name v1.2.3 --event-name push --dry-run false`
  - expected failing manual publish rejection smoke:
    `python3 tool/render_router_image_metadata.py --owner konsultaner --repository konsultaner/connectanum-dart --sha 0123456789abcdef0123456789abcdef01234567 --ref-type branch --ref-name add-router --event-name workflow_dispatch --input-image-tag validation-abc1234 --dry-run false --publish-approval wrong-tag`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25116155461`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`
- Current native release dry-run audit checks:
  - `bin/test-fast`
  - `bash -n bin/audit-github-deployment-chain`
  - `bin/audit-github-deployment-chain --help`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-native-release-dry-run`
  - expected failing stale-evidence check:
    `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-native-release-dry-run`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25119596673`
  - GitHub `Native Artifacts` dry-run `25119602651`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-native-release-dry-run`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`
- Current deployment-chain evidence refresh checks:
  - GitHub `CI` run `25120747925`
  - GitHub `CI` run `25123037462`
  - GitHub `Dart Package Publish Dry Run` run `25122605506`
  - `GH_BIN=/Users/konsultaner/bin/gh bin/audit-github-deployment-chain --branch add-router --run-limit 8 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`
- Current main-CI skipped-gate cleanup checks:
  - GitHub `CI` run `25085322707`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
  - `bin/test-fast`
  - workflow YAML parsing for `.github/workflows/dart.yml` and
    `.github/workflows/wamp-profile-benchmarks.yml`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25086102543`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
- Current latest-CI audit gate checks:
  - `bin/test-fast`
  - `bash -n bin/audit-github-deployment-chain`
  - `bin/audit-github-deployment-chain --help`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 2
    --require-clean-latest-ci`
  - `bin/verify`
  - GitHub `CI` run `25087405841`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, and real error lines
- Current branch-protection operator-plan checks:
  - `bin/test-fast`
  - `bash -n bin/audit-github-deployment-chain`
  - `bin/audit-github-deployment-chain --help`
  - `bin/audit-github-deployment-chain --branch master --run-limit 2
    --show-required-checks-plan`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 4
    --require-clean-latest-ci`
  - `bin/audit-github-deployment-chain --branch master --run-limit 1
    --show-required-checks-plan`
  - `git diff --check`
  - `bin/verify`
  - GitHub `CI` run `25088676567`
  - hosted log scan for warnings, deprecations, rawsocket reset noise, timeout,
    cancellation, skipped jobs, and real error lines
  - follow-up local `bin/test-fast` before recording the hosted checkpoint
- Current public deployment-evidence refresh checks:
  - `bin/test-fast`
  - `git diff --check`
  - `bin/verify`
- Current release-candidate readiness audit checks:
  - `bin/test-fast`
  - `bash -n bin/audit-github-deployment-chain`
  - `bin/audit-github-deployment-chain --help`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 1
    --show-rc-readiness`
  - expected failing
    `bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-rc-ready`
  - `bin/verify`
  - GitHub `CI` run `25105031469`
  - hosted clean branch-head CI/log audit:
    `bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs`

## Decision Log

- 2026-04-28: User clarified that the project should mainly focus on the
  GitHub deployment chain. Paused the H2 isolated regression plan and promoted
  this plan to the active autonomous milestone.
- 2026-04-28: Latest pushed head `d97d34f` passed GitHub `CI` run
  `25045630570`.
- 2026-04-28: Chose Windows x64 as the next native artifact target because
  Linux/macOS publishing already exists, install helpers already understand the
  Windows `.dll` filename, and GitHub-hosted Windows runners can provide the
  MSVC C toolchain that local macOS cross-checks cannot.
- 2026-04-28: Kept shell/cosign paths as `bin/package-native-artifact` outputs
  and used workspace-relative paths for Node-based GitHub actions. This avoids
  Windows Git Bash `/d/a/...` paths in `actions/attest` and `upload-artifact`
  while preserving working POSIX paths for Bash and cosign.
- 2026-04-28: Added a GitHub release dry-run mode before publishing any new
  validation tags. This keeps the deployment chain testable without creating
  throwaway releases when the only thing being reviewed is release metadata.
- 2026-04-28: Kept normal package consumption on
  `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` rather than documenting
  `dart run <package>:tool/install_native.dart`. Package `dart run` invokes
  native build hooks before the helper can complete, while the direct
  source-checkout helper path is repeatable for maintainer prefetch smoke
  tests.
- 2026-04-28: Validated the corrected native release notes in both dry-run and
  real prerelease modes. The native asset publish path is now ready for a
  non-validation release once the canonical release version/tag is chosen.
- 2026-04-28: Replaced `actions/download-artifact@v8` in the native publish job
  because the latest official release still emitted a Node `Buffer()`
  deprecation warning. `gh run download` keeps the job on GitHub APIs while
  removing the warning from hosted logs.
- 2026-04-28: Added a manual stable release approval token instead of choosing
  the canonical stable release version autonomously. Dry-runs and validation
  prereleases remain self-service; stable non-validation release publishing now
  fails closed until the operator intentionally confirms the exact tag.
- 2026-04-28: Treated rawsocket `ConnectionReset` during cancel-cycle shutdown
  as benign CI log noise, not a behavior failure. The fix reuses the existing
  `is_benign_socket_shutdown` policy rather than deleting diagnostics
  wholesale.
- 2026-04-28: Added job-level GitHub Actions timeouts after a docs-only
  `Full Verify` run stayed pending far beyond recent normal duration. This
  keeps the clean-CI rule enforceable because future runner hangs become
  bounded failures instead of indefinite pending checks.
- 2026-04-28: Kept Dart package publishing blocked behind an explicit
  operator/product decision. Local client package validation now passes, but a
  real publish still needs pub.dev ownership and dependency publish-order
  decisions because `connectanum_client` depends on private
  `connectanum_core`.
- 2026-04-28: Treated GitHub branch protection changes as an operator decision
  instead of silently mutating repository settings. The current evidence shows
  `master` is protected and requires one CODEOWNER review, but required status
  checks are unset. The recommended minimum required checks are `Fast Checks`
  and `Full Verify`.
- 2026-04-28: Treated the router image as staged rather than published because
  GitHub cannot currently dispatch or view `router-image.yml` from the default
  branch and no `ghcr.io/konsultaner/connectanum-router` package is visible.
  Public docs now avoid promising an unavailable artifact.
- 2026-04-28: Added a router image dry-run/manual approval gate before the
  workflow is promoted to the default branch. This keeps validation builds
  non-mutating by default and requires an explicit tag match before a manual
  GHCR publish.
- 2026-04-29: Added a dedicated Dart package publish dry-run workflow rather
  than folding pub.dev archive checks into `bin/verify`. Package publishing has
  network-facing release semantics and known product blockers, so it should
  produce hosted deployment evidence without slowing every local verification
  run or publishing anything.
- 2026-04-29: Removed the duplicate manual-only `WAMP Profile Gates` job from
  the main `CI` workflow instead of leaving a permanently skipped job on normal
  pushes. Canonical WAMP profile gates remain covered by the dedicated
  `WAMP Profile Benchmarks` workflow, which runs on relevant path changes and
  manual dispatch.
- 2026-04-29: Added an opt-in clean-latest-CI audit mode so future
  continuations can fail fast on skipped, pending, failed, missing, or
  unexpected main `CI` jobs without relying on manual Actions UI inspection.
- 2026-04-29: Added an opt-in branch-protection operator plan instead of
  applying required checks autonomously. The plan prints the minimal
  required-status-check payload for `Fast Checks` and `Full Verify`, while the
  actual GitHub policy mutation remains an explicit operator decision.
- 2026-04-29: Added a repeatable hosted CI log-scan audit instead of broad
  manual log grepping. The scan intentionally targets high-signal warning,
  deprecation, skipped-test, rawsocket reset, and connection-noise patterns
  while leaving broad `error`/`failed` handling to job status because passing
  test names and Rust summaries contain benign failed/failure words.
- 2026-04-29: Tightened Dart package publish dry-runs to require pub's
  explicit zero-warning result. This keeps public package release evidence
  stricter than process success alone, while still leaving real package
  publishing blocked on package ownership, version, and publish-order
  decisions.
- 2026-04-29: Kept Dart package publishing non-mutating but made the
  release-order blocker explicit in both the package dry-run and the RC audit.
  The current operator decision is whether `connectanum_core 0.1.0` is approved
  public API and should be published before `connectanum_client 2.2.6`.
- 2026-04-29: Added a dedicated hosted Dart package publish dry-run gate to
  the deployment audit instead of assuming main `CI` covers package archive
  evidence. Docs-only checkpoints may reuse the latest successful package
  dry-run only when no package-publish-sensitive inputs changed since that run.
- 2026-04-29: Made router image manual dry-runs produce a downloadable
  `router-image-preview` artifact. This keeps the staged GHCR path
  non-mutating while preserving the exact resolved image tags, labels, publish
  mode, provenance setting, and SBOM setting as operator-readable evidence.
- 2026-04-29: Added a native release dry-run audit gate instead of treating old
  `Native Artifacts` workflow runs as indefinitely valid. This keeps native
  matrix artifacts and release-preview evidence explicit, non-mutating, and
  freshness-checked before release decisions.
- 2026-04-29: Refreshed the hosted Dart package publish dry-run on the current
  branch head even though the older run was still input-relevant. This keeps
  package release evidence current and removes avoidable staleness from the
  deployment audit without publishing to pub.dev.
- 2026-04-29: Paused autonomous deployment-chain work after clean hosted
  evidence on `b338d58`. Remaining deployment-chain work needs explicit
  operator/product decisions: required branch-protection mutation, default
  branch router-image promotion/GHCR package publication, RC tag/prerelease
  selection, and Dart package public ownership/release order.
- 2026-05-01: Removed the obsolete root `.travis.yml` config as a public
  deployment-surface cleanup. GitHub Actions remains the only maintained hosted
  CI/deployment chain, and the historical changelog entry about old Travis
  builds stays untouched as release history rather than active configuration.
  Pre-change `bin/test-fast` and post-change `bin/verify` passed locally.

## Handoff

- Next continuation should keep hosted GitHub CI clean. Resume this plan only
  when the operator approves branch protection, default-branch router image
  promotion/GHCR publication, an RC tag/prerelease, or Dart package
  ownership/release order. Do not publish a stable non-validation release tag,
  router image, or Dart package without an explicit product/version/ownership
  decision.
