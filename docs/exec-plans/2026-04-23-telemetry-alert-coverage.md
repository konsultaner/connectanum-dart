## Goal

Keep the router telemetry coverage aligned with the shipped transport-alert
metrics by testing both sides of the contract: the native `ct_ffi` router
metrics snapshot binding and the Dart boss/exporter alert derivation.

## Scope

- add focused `ct_router_metrics_snapshot` coverage in `native/transport/ct_ffi`
- expand Dart router metrics/exporter tests beyond the current `go_away`-only
  assertions
- verify OpenMetrics and metrics snapshot payloads for the non-GOAWAY alert
  reasons already emitted by the boss loop
- refresh checked-in project state when the milestone lands

## Non-goals

- changing router alert thresholds or alerting semantics
- adding new transport metrics fields to the native/Dart contracts
- changing Prometheus naming or dashboard structure
- adding new bench scenarios in this slice

## Verification

- `bin/test-fast`
- focused `ct_ffi` router metrics tests
- focused Dart router metrics/exporter tests
- `bin/verify`

## Status

- completed

## Handoff

- Native snapshot mapping and Dart alert derivation are now both pinned for the
  current alert reasons: `go_away`, `idle_timeout`, `body_timeout`,
  `protocol_error`, and `internal_error`.
- The native snapshot regression is feature-gated because it injects synthetic
  transport events through the `ffi-test` helper surface; `bin/test-all` now
  runs that focused test explicitly with `--features ffi-test` on
  native-runtime hosts.
- Keep the FFI assertions at the snapshot boundary and the Dart assertions at
  the emitted payload / OpenMetrics boundary so future alert changes fail near
  the actual contract break.
- There is no active exec plan now. The next session should choose the next
  unfinished milestone from `ROADMAP_NEXT.md`.
