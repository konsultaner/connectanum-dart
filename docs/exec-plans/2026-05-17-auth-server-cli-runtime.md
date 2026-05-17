# Auth Server CLI Runtime

Status: runtime wiring is pushed and hosted-clean for enforced branch gates;
package executable follow-up is implemented locally with full verification
passed and is ready for commit/push.

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
- Follow up by proving the documented package executable target
  `dart run connectanum_auth_server:auth_server` instead of only direct script
  execution, and expose explicit executable metadata for global/package runner
  discovery.

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
- Commit/push: `58609e1` pushed to `codex/post-rc-production-readiness`.
- Hosted CI: push CI #25991321778 and PR CI #25991322544 passed for `58609e1`.
- Hosted package dry-run: push #25991321771 and PR #25991322493 passed for
  `58609e1`.
- Strict deployment-chain audit with latest CI/logs, package dry-run, workflow
  visibility, GHCR visibility, WAMP benchmark relevance, native artifact
  relevance, router image relevance, and RC-readiness reporting: passed for the
  enforced gates on 2026-05-17.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --require-rc-ready`:
  failed as expected because PR #79 still requires review/merge and the final
  RC still needs a fresh approved tag/prerelease plus tag-matched Native
  Artifacts and Router Image evidence.
- Follow-up pre-edit `bin/test-fast`: passed on 2026-05-17.
- Follow-up focused `dart test packages/connectanum_auth_server/test/auth_server_cli_test.dart`:
  passed on 2026-05-17 after switching the smoke to
  `dart run connectanum_auth_server:auth_server`.
- Follow-up manual `dart run connectanum_auth_server:auth_server --help`:
  passed on 2026-05-17.
- Follow-up post-edit `bin/test-fast`: passed on 2026-05-17.
- Follow-up full local `bin/verify`: passed on 2026-05-17.

## Remaining

- Commit and push the follow-up package executable readiness slice, then collect
  hosted CI/package dry-run evidence and rerun the strict audit.
- Complete PR #79 review/merge into the release branch.
- After release approval, choose a fresh RC tag for `58609e1` or its promoted
  release-branch successor, then refresh tag-matched Native Artifacts and
  Router Image evidence.
