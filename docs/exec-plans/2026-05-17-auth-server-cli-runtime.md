# Auth Server CLI Runtime

Status: runtime wiring, package executable follow-up, health/metrics endpoint
follow-up, and YAML package-executable config smoke are pushed and hosted-clean
for enforced branch gates. The missing-service-realm fail-closed smoke is
implemented locally with full verification passing; push/hosted evidence and RC
release-control blockers remain.

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
- Reuse the router OpenMetrics HTTP exporter from the auth-server executable
  when config enables `metrics.open_metrics`, and smoke-test `/healthz` plus
  the configured metrics path through the package executable.
- Prove the documented `auth_service.yaml` config path through the package
  executable so the shared router JSON/YAML config loader is covered from the
  auth-server CLI surface.
- Prove `--check` rejects configs that omit the configured auth service realm
  before native runtime startup.
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
- Follow-up commit/push: `8d2ee00` pushed to
  `codex/post-rc-production-readiness`.
- Follow-up hosted CI: push CI #25992722694 and PR CI #25992723633 passed for
  `8d2ee00`.
- Follow-up hosted package dry-run: push #25992722667 and PR #25992723637
  passed for `8d2ee00`.
- Follow-up hosted release-sensitive evidence refresh: Router Image dry-run
  #25993038176 and WAMP Profile Benchmarks #25993038113 passed for `8d2ee00`.
- Follow-up strict deployment-chain audit with latest CI/logs, package dry-run,
  router image dry-run, WAMP benchmark relevance, workflow visibility, GHCR
  visibility, and RC-readiness reporting: passed for the enforced gates on
  2026-05-17.
- Health/metrics follow-up pre-edit `bin/test-fast`: passed on 2026-05-17.
- Health/metrics focused `dart test packages/connectanum_auth_server/test/auth_server_cli_test.dart -r expanded`:
  passed on 2026-05-17.
- Health/metrics focused `dart test packages/connectanum_auth_server/test -r expanded`:
  passed on 2026-05-17.
- Health/metrics focused `dart analyze packages/connectanum_auth_server`:
  passed on 2026-05-17.
- Health/metrics post-edit `bin/test-fast`: passed on 2026-05-17.
- Health/metrics full local `bin/verify`: passed on 2026-05-17.
- Health/metrics commit/push: `1a849f5` pushed to
  `codex/post-rc-production-readiness`.
- Health/metrics hosted CI: push CI #25994206592 and PR CI #25994207170 passed
  for `1a849f5`.
- Health/metrics hosted package dry-run: push #25994206615 and PR #25994207176
  passed for `1a849f5`.
- Health/metrics strict deployment-chain audit with latest CI/logs, package
  dry-run, router image dry-run relevance, WAMP benchmark relevance, workflow
  visibility, GHCR visibility, native release relevance, and RC-readiness
  reporting: passed for the enforced gates on 2026-05-17.
- YAML config follow-up pre-edit `bin/test-fast`: passed on 2026-05-17.
- YAML config focused `dart test packages/connectanum_auth_server/test/auth_server_cli_test.dart -r expanded`:
  passed on 2026-05-17.
- YAML config full local `bin/verify`: passed on 2026-05-17.
- YAML config commit/push: `1f6b590` pushed to
  `codex/post-rc-production-readiness`.
- YAML config hosted CI: push CI #25995471254 and PR CI #25995472200 passed
  for `1f6b590`.
- YAML config hosted package dry-run: push #25995471249 and PR #25995472192
  passed for `1f6b590`.
- YAML config strict deployment-chain audit with latest CI/logs, package
  dry-run, router image dry-run relevance, WAMP benchmark relevance, native
  release relevance, workflow visibility, GHCR visibility, and RC-readiness
  reporting: passed for the enforced gates on 2026-05-17.
- Missing-service-realm follow-up pre-edit `bin/test-fast`: passed on
  2026-05-17.
- Missing-service-realm focused `dart test packages/connectanum_auth_server/test/auth_server_cli_test.dart -r expanded`:
  passed on 2026-05-17.
- Missing-service-realm focused `dart analyze packages/connectanum_auth_server`:
  passed on 2026-05-17.
- Missing-service-realm focused `dart test packages/connectanum_auth_server/test -r expanded`:
  passed on 2026-05-17.
- Missing-service-realm post-edit `bin/test-fast`: passed on 2026-05-17.
- Missing-service-realm full local `bin/verify`: passed on 2026-05-17.

## Remaining

- Commit/push the bundled missing-service-realm smoke code and state updates,
  then collect hosted CI/package dry-run evidence and rerun the strict audit if
  required for handoff.
- Complete PR #79 review/merge into the release branch.
- After release approval, choose a fresh RC tag for the current branch head or
  its promoted release-branch successor, then refresh tag-matched Native
  Artifacts and Router Image evidence.
