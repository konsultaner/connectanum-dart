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

## Handoff

- Next continuation should inspect the GitHub workflows and release-related
  exec plans, then choose the smallest deployment-chain gap that moves the
  project closer to production releases with multi-platform FFI artifacts.
