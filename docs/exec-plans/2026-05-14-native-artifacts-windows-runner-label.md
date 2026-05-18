# Native Artifacts Windows Runner Label

Status: complete

## Goal

Remove hosted release-chain annotation noise from the Native Artifacts Windows
x64 job by using GitHub's current Windows Server 2025 Visual Studio 2026 runner
label directly instead of relying on redirect behavior.

## Scope

- In scope: Native Artifacts workflow runner label and verification evidence.
- Out of scope: changing the native artifact matrix, release policy, artifact
  contents, or router image publishing behavior.

## Verification

- Native Artifacts dry-run #25835145241 passed on commit `c3a31d6`, but the
  Windows x64 job emitted a hosted runner-label redirect notice for
  `windows-2025`; that notice is the reason for this follow-up fix.
- Ruby YAML parsing passed for `.github/workflows/native-artifacts.yml`.
- `git diff --check` passed.
- `bin/test-fast` passed on 2026-05-14.
- `bin/verify` passed on 2026-05-14.
- GitHub CI #25835905426 and PR-triggered GitHub CI #25835906336 passed on
  `f7b13ef` with `Fast Checks` and `Full Verify` green.
- PR-triggered Dart Package Publish Dry Run #25835906345 passed on `f7b13ef`.
- Native Artifacts dry-run #25836267858 passed on `f7b13ef`; all five platform
  bundle jobs and the release-preview job passed, and the previous Windows
  runner-label redirect annotation was gone.
- The strict deployment-chain audit passed on `f7b13ef` with clean latest
  CI/logs, relevant Dart package dry-run, relevant Native Artifacts dry-run,
  relevant Router Image dry-run, relevant WAMP Profile Benchmarks, and router
  package visibility requirements enabled.
- `--require-rc-ready` failed only on expected release-promotion blockers:
  PR #79 still requires review/merge into `master`, the existing
  `v0.1.0-rc.1` tag/prerelease does not cover `f7b13ef`, and pub.dev release
  order remains intentionally deferred.

## Remaining

- No implementation work remains for this slice.
