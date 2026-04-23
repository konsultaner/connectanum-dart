# Exec Plan: ci-artifact-cleanup-and-native-matrix

## Goal

Keep the main CI workflow verification-only and make the real published native
artifacts clearer by removing low-value raw metrics uploads from `CI` while
expanding the `Native Artifacts` workflow to an explicit four-platform
`ct_ffi` release matrix.

## Scope

- remove the generic `ci-artifacts` upload from `.github/workflows/dart.yml`
- keep raw metrics snapshot dumps available only for explicit local/debug runs
  through `CONNECTANUM_ARTIFACT_DIR`
- expand `.github/workflows/native-artifacts.yml` from implicit host-native
  Linux/macOS coverage to explicit Linux x64, Linux arm64, macOS arm64, and
  macOS Intel runners
- refresh release/deployment docs so users are directed to GitHub Releases and
  the `Native Artifacts` workflow rather than generic `CI` debug output
- update checked-in repo state and roadmap notes to match the new artifact
  policy

## Non-goals

- redesigning the bundle format or install-helper contract
- adding Windows `ct_ffi` bundles in this pass
- changing bench artifact or bench gate formats

## Verification

- `bin/test-fast`
- workflow YAML parse checks for touched workflows
- `bin/verify`

## Status

- completed

## Findings

- GitHub Actions run `24823387475` on commit `06f3b43` restored a clean branch
  CI baseline, so the previous native-client fast-check repair can close.
- The main `CI` workflow's low-signal `ci-artifacts` upload is now removed
  locally. Raw per-test OpenMetrics and JSON snapshots from
  `router_integration_native_test.dart` remain available only for explicit
  local/debug runs that set `CONNECTANUM_ARTIFACT_DIR`.
- The meaningful public artifact path is the `Native Artifacts` workflow plus
  GitHub Releases, and the workflow is now widened locally from implicit
  Linux/macOS coverage to an explicit Linux x64, Linux arm64, macOS arm64,
  and macOS Intel matrix.
- GitHub's hosted-runner reference currently lists `ubuntu-24.04`,
  `ubuntu-24.04-arm`, `macos-15`, and `macos-15-intel` as standard labels for
  public repositories, which matches the desired four-platform `ct_ffi`
  release matrix.
- Local verification is green for the workflow/doc change set: `bin/test-fast`,
  workflow YAML parsing, and `bin/verify` all pass.
- GitHub Actions run `24824613232` on commit `7049801` confirmed the branch
  `CI` chain stayed green after the generic metrics artifact upload was
  removed.
- GitHub Actions run `24825770571` (`Native Artifacts`, `workflow_dispatch`)
  confirmed the expanded hosted bundle matrix on Linux x64, Linux arm64, macOS
  arm64, and macOS Intel. The `Publish GitHub Release` job skipped as expected
  because no release tag was supplied for the validation dispatch.
