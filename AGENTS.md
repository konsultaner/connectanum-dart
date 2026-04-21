# Instructions for Codex agents

## Resume order

1. Read `docs/project_state.md`.
2. If there is an active plan under `docs/exec-plans/`, read that next.
3. Use `ROADMAP_NEXT.md` to choose the next milestone only when no active plan exists.
4. Use `ROADMAP.md` and `STRUCTURE.md` as reference material, not as mandatory startup reading for every task.

## Canonical commands

- `bin/bootstrap` validates the local toolchain and fetches workspace dependencies.
- `bin/test-fast` runs the fastest useful regression set before or during a task.
- `bin/test-all` runs the full Rust + Dart verification flow and builds `ct_ffi` in `ffi-test` mode.
- `bin/verify` checks formatting and then runs `bin/test-all`.

If the native library already exists in the standard release location, the root scripts auto-detect it and export `CONNECTANUM_NATIVE_LIB`.

## Working rules

- Reproduce blocking issues with a unit test or minimal repro before changing behavior.
- Keep one active execution plan in `docs/exec-plans/` for any task that spans packages, native code, deployment, or multiple working sessions.
- Update `docs/project_state.md` when the active milestone, blockers, or last-known verification status changes.
- Update `ROADMAP.md`, `ROADMAP_NEXT.md`, and `STRUCTURE.md` only when the implementation or project shape materially changes.
- Capture external spec research in checked-in docs when it changes implementation direction; do not rely on transient chat context alone.
- Stop and ask only for product decisions, secrets or credentials, or deployment access that cannot be inferred safely.

## Verification expectations

- Before a substantial change: `bin/test-fast`
- Before handoff: `bin/verify`
- If Chrome or Chromium is unavailable locally, `bin/test-all` and `bin/verify` skip browser-platform tests and print a warning.
