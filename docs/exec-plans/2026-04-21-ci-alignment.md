# Exec Plan: ci-alignment

Status: active
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

## Handoff

- CI should exercise the same bootstrap and verification surface that local autonomous work uses.
- If coverage reporting is still desired later, it should be reintroduced behind the root scripts instead of bypassing them.
- The workflow patch now covers branch pushes as well as PRs to `master`, but the final post-change `bin/verify` confirmation still needs either CI itself or an unrestricted local environment.
