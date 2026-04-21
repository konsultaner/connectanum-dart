# Exec Plan: ci-alignment

Status: completed
Owner: Codex
Created: 2026-04-21
Last updated: 2026-04-21

## Goal

Align GitHub Actions with the canonical root `bin/*` workflow so CI enforces the same bootstrap, fast-check, and full verification contract used for local autonomous work.

## Scope

- In scope: workflow consolidation around `bin/bootstrap`, `bin/test-fast`, and `bin/verify`, Linux CI environment setup for Rust and Chromium, and startup-state documentation.
- Out of scope: redesigning the roadmap, changing release/publish strategy, or reintroducing bespoke coverage reporting that diverges from the root workflow.

## Files Expected To Change

- `.github/workflows/dart.yml`
- `bin/test-all`
- `docs/project_state.md`

## Preconditions

- Ubuntu GitHub runners can install a Chrome/Chromium executable for browser-platform tests.
- The root `bin/*` scripts remain the supported contract for bootstrap and verification.

## Plan

1. Inspect the existing workflow drift against the root `bin/*` scripts and decide the smallest CI shape that preserves signal while removing bespoke direct test commands.
2. Update the GitHub workflow to provision Dart, Rust, and Chromium, then run the canonical root entrypoints instead of ad hoc package commands.
3. Re-run the root verification flow locally, then refresh the checked-in project state with the new active milestone and verification status.

## Verification

- `bin/test-fast`
- `bin/verify`
- Additional targeted commands:
  - `sed -n '1,260p' .github/workflows/dart.yml`

## Decision Log

- 2026-04-21: Chose to collapse CI onto the root `bin/*` entrypoints rather than preserve job-specific direct `dart test` commands, because the repo now treats those root scripts as the canonical contract for both humans and Codex.
- 2026-04-21: The Codex heartbeat sandbox can reuse the local pub cache with a temporary writable `HOME`, but it still blocks loopback socket binds, so local `bin/test-fast` re-runs in automation can fail inside socket-heavy integration tests even when the same suite passes in an unrestricted shell or CI.
- 2026-04-21: The CI workflow patch is already committed on `add-router` (`293edf1 update dart workflow`) and pushed to both configured remotes; the remaining validation step is observing GitHub-side workflow execution from an environment with working network/plugin transport access.
- 2026-04-21: The workflow was still filtered to `push.branches: [master]`, which prevented branch pushes like `add-router` from starting Actions at all; widened `push` to all branches and added `workflow_dispatch` for manual fallback.
- 2026-04-21: The first branch-triggered Ubuntu run exposed a bench integration assumption that `tool/wamp_client_main.dart` was launched from the bench package root; fixed that by resolving the helper from either the package or repo root (`ed78222 test(bench): resolve worker tool path from repo root`).
- 2026-04-21: After the bench-path fix, GitHub `Fast Checks` passed, but `Full Verify` still failed in Linux `cargo test -p ct_core` because `connection_runtime_config_exposes_rawsocket_settings` could drop its client connection before reading the runtime config, and the shared Rust test guard then poisoned the rest of the suite; fixed both issues in `28830f2 test(ct_core): stabilize runtime tests`.
- 2026-04-21: GitHub run `24730190112` showed the remaining Linux failure was no longer in Rust; `remote_auth_integration_test.dart` was colliding with the process-global native runtime because `bin/test-all` invoked `dart test packages/connectanum_router/test` from the repo root, which bypassed the router package's checked-in `dart_test.yaml` (`concurrency: 1`).
- 2026-04-21: Switched `bin/test-all` to run the router suite from `packages/connectanum_router`, which restores the package-local serial test contract on both Linux and macOS and also brings `publish_ack_test.dart` plus `remote_auth_integration_test.dart` into root verification on Darwin.
- 2026-04-21: Cleaned up the remaining tracked Rust dead-code warnings in `2fac53b chore(native): trim dead-code warnings`; local `cargo test -p ct_core`, `cargo test -p ct_ffi`, and `bin/verify` are green again, so the only unresolved part of this plan is GitHub-side confirmation.
- 2026-04-21: The rerun after the router-package fix (`24732311355`) completed with failure, but the current heartbeat sandbox cannot inspect remote logs or confirm whether the subsequent run for `2fac53b` (`24732889424`) has cleared the remaining CI issue.
- 2026-04-21: Confirmed from a network-capable interactive run that GitHub Actions run `24732889424` for `2fac53b` completed successfully, with both `Fast Checks` and `Full Verify` green, so the CI-alignment goal is complete.

## Handoff

- CI should exercise the same bootstrap and verification surface that local autonomous work uses.
- If coverage reporting is still desired later, it should be reintroduced behind the root scripts instead of bypassing them.
- The workflow patch now covers branch pushes as well as PRs to `master`, and local verification is aligned with that contract again.
- This plan is complete. Choose the next milestone from `ROADMAP_NEXT.md`.
