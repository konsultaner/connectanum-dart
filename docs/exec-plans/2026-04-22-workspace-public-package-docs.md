# Exec Plan: workspace-public-package-docs

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Bring the remaining public-facing package and benchmark docs up to the same
standard as the already-polished root README and release metadata.

## Scope

- In scope:
  - Rewrite stale package-level README files so they read like current
    user-facing docs instead of historical project notes.
  - Add concise README files for public package folders that currently have no
    top-level overview.
  - Rewrite `native/bench/README.md` so it documents the implemented
    orchestrator instead of presenting itself as a design draft.
  - Refresh `docs/project_state.md` and the exec-plan set so the active plan
    matches this docs milestone and the finished kTLS benchmark work is closed.
- Out of scope:
  - Renaming packages, binaries, tags, or published asset filenames.
  - Deep API redesign or example rewrites beyond what the docs need.
  - Broad package-level README work for testdata or other non-user-facing
    subtrees.

## Files Expected To Change

- `packages/*/README.md`
- `native/bench/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-ktls-http2-benchmarks.md`
- `docs/exec-plans/2026-04-22-workspace-public-package-docs.md`
- `docs/ktls_research.md`

## Preconditions

- `bin/test-fast` is green before changing the checked-in docs set.
- The hosted kTLS benchmark result is confirmed before closing the prior active
  benchmark plan.

## Plan

1. Close the stale kTLS HTTP/2 benchmark plan in the checked-in state using the
   confirmed hosted success runs and their remaining performance caveats.
2. Rewrite the stale public README files and add the missing top-level package
   README set for the public workspace folders.
3. Run full verification, then checkpoint the updated docs state and leave the
   next technical follow-up explicit.

## Verification

- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-04-22: The root README and release metadata are already much cleaner,
  but the package-level public surface still looks inconsistent because some
  package folders have no README and `connectanum_client` still reads like the
  old pre-monorepo project.
- 2026-04-22: The finished kTLS HTTP/2 hosted milestone should be closed in
  docs before starting another technical kTLS task, otherwise resume state will
  keep pointing at a resolved blocker.
- 2026-04-22: The public package doc set should favor concise, conventional
  package-level README files over deep internal notes. The root README and the
  deployment guide remain the place for broader monorepo and release-process
  detail.

## Handoff

- Validation is complete: `bin/test-fast` and `bin/verify` both passed after
  rewriting the package-level public docs and the `native/bench` overview.
- The next technical follow-up remains the secure WAMP TLS benchmark path: add
  a TLS WAMP listener to the bench router and measure secure RawSocket and
  secure WebSocket on the existing harness.
