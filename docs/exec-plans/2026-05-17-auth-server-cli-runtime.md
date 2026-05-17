# Auth Server CLI Runtime

Status: implemented with clean local verification; commit/push and hosted
evidence are pending.

## Goal

Make the `connectanum_auth_server` executable useful for consumer and operator
smoke tests by starting a real native router runtime, binding the remote-auth
WAMP procedures, and reporting readiness instead of only constructing an
`AuthServer` instance.

## Plan

- Replace the CLI placeholder with runtime wiring that loads router settings,
  derives auth service endpoints from configured listeners, starts
  `NativeTransportRuntime`, starts the router, creates an internal session on
  the service realm, and binds `AuthServerProcedureBinding`.
- Add CLI options for native library selection, service realm/internal session
  identity, and a `--check` mode that starts, binds, reports readiness, and
  exits for deployment smoke tests.
- Add auth-server package smoke coverage that runs the executable against a
  temporary service config and proves procedure binding readiness.
- Bundle the pending hosted-evidence bookkeeping from the completed Dart
  package dry-run slice with this implementation commit.

## Verification

- `bin/test-fast`: initial pre-edit run hit a native runtime lock held by an
  overlapping `bin/test-fast` process; no code changes were made from that
  result.
- `bin/test-fast`: passed on isolated rerun on 2026-05-17.
- `dart test packages/connectanum_auth_server/test`: passed after CLI edits on
  2026-05-17.
- `bin/test-fast`: passed after edits on 2026-05-17.
- `git diff --check`: passed.
- Private-name/local-path scan on touched public docs/package paths: passed.
- `bin/verify`: passed on 2026-05-17.

## Remaining

- Commit, push, and collect hosted evidence if the local gates pass.
