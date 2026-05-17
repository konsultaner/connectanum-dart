# Router Worker Scale-Down Reassignment

Status: transfer implementation is pushed as `f2aeb6d` with clean hosted
evidence. Follow-up state-store metadata preservation coverage is complete
locally; commit/push and hosted evidence refresh are pending.

## Goal

Complete the remaining worker-pool autoscaling production-readiness item:
scale-down should be able to retire an idle excess worker that still owns open
WAMP sessions by moving those connections to another worker, instead of only
retiring already-connectionless workers.

## Plan

- Restrict scale-down reassignment to idle workers with open, transferable
  WAMP sessions.
- Add a worker transfer handshake: source exports connection state, target
  adopts it, boss updates connection ownership, then source forgets its copy.
- Update state-store session ownership so router meta APIs report the new
  worker after migration.
- Add focused runtime coverage proving a scaled-down worker can transfer an
  active connection and that later messages for that connection are processed
  by the surviving worker.

## Verification

- `bin/test-fast`: passed before edits on 2026-05-17.
- `dart analyze packages/connectanum_router`: passed.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "transfers open sessions before scale-down worker shutdown" --chain-stack-traces`: passed.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "scale" --chain-stack-traces`: passed.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --chain-stack-traces`: passed.
- `bin/test-fast`: passed after edits on 2026-05-17.
- `git diff --check`: passed.
- Private-name/local-path scan on touched docs: passed.
- `bin/verify`: passed on 2026-05-17.
- Hosted evidence for `f2aeb6d`: push CI #25985038143, PR CI #25985039174,
  push/PR Dart Package Publish Dry Runs #25985038144/#25985039176, Router Image
  dry-run #25985357233, and WAMP Profile Benchmarks #25985358235 passed; strict
  audit enforcement gates were clean.
- Follow-up metadata coverage extends the transfer runtime test to verify
  transferred session ownership, auth identity, subscription subscriber, and
  procedure callee state after scale-down; focused local test passed on
  2026-05-17.
- Follow-up local verification on 2026-05-17: focused transfer coverage,
  scale-focused runtime coverage, full `router_runtime_test`,
  `dart analyze packages/connectanum_router`, post-edit `bin/test-fast`,
  `git diff --check`, private-name/local-path scan on touched files, and
  full `bin/verify` passed.

## Remaining

- Commit and push the follow-up coverage with this state update.
- Refresh hosted CI/package-dry-run evidence for the pushed checkpoint.
