# Exec Plan: ktls-linux-validation

Status: in_progress
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Turn the existing env-gated Linux kTLS prototype into a reproducibly validated
Linux milestone by adding a strict "require kTLS" path, a repeatable HTTP/2
validation runner, and a manual GitHub Actions workflow that can exercise the
prototype on an actual Linux host.

## Scope

- In scope:
  - Add an env-only strict validation mode that fails when the server cannot
    keep the kTLS path active.
  - Add a repo script that runs the targeted kTLS Rust coverage plus the
    existing HTTP/2 smoke bench with kTLS required.
  - Add a manual GitHub Actions workflow for the Linux validation run and its
    artifacts.
  - Refresh checked-in state/docs with the exact validation contract and
    results.
- Out of scope:
  - Adding a public router config field for kTLS.
  - Secure RawSocket / WebSocket TLS bench expansion.
  - Claiming NIC-offload gains from hosted CI.

## Files Expected To Change

- `native/transport/ct_core/src/ktls.rs`
- `native/transport/ct_core/src/lib.rs`
- `bin/common.sh` if the validation script benefits from shared helpers
- `bin/*.sh` or a new `bin/*` validation entrypoint
- `.github/workflows/*.yml`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-22-ktls-linux-validation.md`
- `docs/ktls_research.md` if the validation contract changes

## Preconditions

- `bin/test-fast` is green before changing the validation path.
- Existing non-Linux verification stays green after the change.

## Plan

1. Check in this active plan and point `docs/project_state.md` at it.
2. Add a strict env-gated validation mode plus a reproducible Linux runner for
   the existing kTLS HTTP/2 smoke path.
3. Add a manual GitHub Actions workflow, run it on `add-router`, and update
   the checked-in state with the resulting Linux validation status.

## Verification

- `bin/test-fast`
- Local syntax/entrypoint checks for the new validation script and workflow
- `bin/verify`
- One hosted Linux run of the new manual kTLS validation workflow on
  `add-router`

## Decision Log

- 2026-04-22: The next useful milestone is strict Linux validation, not more
  prototype expansion, because the main open question is whether the existing
  offload path actually holds on a real Linux runner.
