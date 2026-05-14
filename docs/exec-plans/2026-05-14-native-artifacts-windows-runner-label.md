# Native Artifacts Windows Runner Label

Status: active

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

## Remaining

- Push the runner-label fix.
- Watch PR CI for the pushed head.
- Dispatch Native Artifacts dry-run and confirm the Windows runner annotation is
  gone.
- Rerun the strict deployment-chain audit.
