## Goal

Extend the checked-in WAMP conformance gate beyond the current single-message
serializer subset by vendoring the one upstream router-level multi-session
vector that already exists and executing it against local router behavior.

## Scope

- vendor the upstream `publisher_exclusion_disabled` multi-session vector under
  `packages/connectanum_core/testdata/wamp_conformance`
- add a router-side conformance test harness that executes the vendored vector
  against `RouterStateStore` / worker-session handling
- make the harness tolerant of router-assigned IDs so the vector can use stable
  placeholder values while the implementation keeps generating real IDs
- refresh checked-in state/docs once the incremental conformance gate lands

## Non-goals

- pretending the upstream multi-message or multi-session suite is generally
  stable when the PR still only ships one router-level vector
- transport-level interop coverage on top of the vector contract
- implementing a fully generic runner for every future upstream sequence shape
  before those vectors actually exist

## Verification

- `bin/test-fast`
- focused `dart test` for the new router conformance file
- `bin/verify`

## Status

- completed

## Handoff

- Completed. The vendored WAMP conformance snapshot now includes the upstream
  router-level multi-session vector
  `multisession/advanced/publisher_exclusion_disabled.json`, and the router
  package now executes it through
  `test/conformance/wamp_multisession_conformance_test.dart` against local
  worker-session routing.
- The harness replays client-to-router steps, captures routed outbound
  messages, and matches router-assigned ids such as `subscription_id` and
  `publication_id` through stable placeholder bindings so the checked-in
  vector can stay deterministic while the implementation keeps generating real
  ids.
- Verification passed with `bin/test-fast`, focused `dart test` and
  `dart analyze` for the new conformance harness, and full `bin/verify`.
