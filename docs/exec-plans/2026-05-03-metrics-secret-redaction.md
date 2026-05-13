# Metrics Secret Redaction

Status: completed
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Prevent the router metrics snapshot from exposing configured OpenMetrics bearer
tokens while preserving useful exporter metadata for operators.

## Scope

- Replace secret-bearing exporter metadata with a boolean/auth-required signal.
- Add a regression proving `auth_token` is not present in metrics snapshot
  payloads when exporter authentication is configured.
- Update metrics documentation and roadmap/project state.

## Non-Goals

- Changing `/metrics` bearer-token enforcement.
- Changing WAMP permissions for the metrics realm.
- Introducing token hashing or token identifiers.

## Verification Plan

- Pre-change `bin/test-fast`.
- Focused router metrics service test.
- `dart analyze packages/connectanum_router`.
- `git diff --check`.
- Full `bin/verify` before handoff.
- Push and watch GitHub CI if committed.

## Progress

- 2026-05-03: Branch-head GitHub deployment audit passed at `2942a22` before
  starting this slice; hosted `CI`, `WAMP Profile Benchmarks`, and
  `Dart Package Publish Dry Run` are clean for the current head. Remaining
  audit findings are operator/default-branch items.
- 2026-05-03: Pre-change `bin/test-fast` passed.
- 2026-05-03: Added a fail-first regression proving the metrics snapshot
  exposed `exporter.auth_token` when OpenMetrics bearer auth was configured.
- 2026-05-03: Replaced the secret-bearing field with `auth_required`, updated
  metrics docs/roadmap notes, and passed focused checks:
  `dart test packages/connectanum_router/test/router_metrics_service_test.dart -r expanded`,
  `dart analyze packages/connectanum_router`, and `git diff --check`.
- 2026-05-03: Full local `bin/verify` passed after the redaction change,
  including Rust native/FFI tests, Dart package suites, bench integration
  coverage, full router tests, and Chrome/Dart2Wasm WebSocket transport tests.
