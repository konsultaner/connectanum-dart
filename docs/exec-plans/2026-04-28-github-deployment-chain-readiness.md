# GitHub Deployment Chain Readiness

Status: in_progress
Owner: Codex
Created: 2026-04-28
Last updated: 2026-04-28

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

## Handoff

- Next continuation should finish the public install-instructions correction:
  run full verification, commit and push the docs/tooling update, watch hosted
  GitHub CI, and then use the corrected release-note generator for the next
  native release dry-run or validation prerelease.
