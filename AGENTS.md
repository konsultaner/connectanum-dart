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

- Autonomous continuation priority order:
  1. Keep the CI chain clean. If local `bin/verify` is failing or the latest known branch CI is red, fix that before starting new feature or benchmark work.
  2. Make the GitHub deployment chain the main project spine. Prefer work that makes GitHub Actions, release publishing, multi-platform FFI artifacts, release notes, public package metadata, and branch protection/deployment evidence reliable and human-readable.
  3. Prioritize production readiness of already-shipped or partially-shipped functionality before exploratory work. That includes correctness, deployment behavior, release packaging, observability, operational docs, and test coverage.
  4. Treat MCP support for the downstream `groli/app` integration as the next product-readiness milestone after CI health, GitHub deployment-chain blockers, and current shipped-path blockers. It outranks speculative HTTP/3, kTLS, E2EE, and benchmark exploration until the first usable MCP server/bridge path is designed, implemented, tested, and documented.
  5. After the first usable MCP path is complete, make WAMP profile-related transport performance production-ready in the benchmark suite before returning to speculative transport work. That means canonical RawSocket/WebSocket WAMP scenarios, secure and cleartext coverage, serializer/profile coverage, explicit budgets/gates, and hosted CI evidence for release decisions.
  6. Treat other benchmark and performance work as production work only when it protects or improves a real shipped path, a CI gate, or a release decision. Do not let speculative benchmarking outrun product readiness.
- Do not knowingly leave the branch in a state that would break the clean CI chain without recording the blocker clearly in `docs/project_state.md` and the active exec plan.
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
