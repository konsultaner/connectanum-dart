# HTTP Route Deterministic Namespace Shorthand

Status: complete

## Goal

Close the HTTP bridge shorthand gap for router-managed reserved-realm and
namespace routes by making Dart runtime dispatch derive the same deterministic
WAMP realm/procedure target as native routing.

## Scope

- Keep native `reserved_realm` / `namespace` route encoding aligned with the
  existing native materialization model.
- Parse route action aliases that consumers commonly use in Dart-style config
  (`reservedRealm`, `appendMethodSuffix`, etc.).
- Derive reserved-realm and namespace dispatch targets in Dart runtime matching
  when native handshakes do not already provide a target.
- Add focused config-loader, native JSON, and runtime regressions.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_config_loader_test.dart --name "deterministic HTTP route shorthand aliases" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_json_test.dart --name "deterministic HTTP shorthand routes" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "deterministic HTTP shorthand targets" --chain-stack-traces`: passed on 2026-05-14.
- `bin/verify`: passed on 2026-05-14.
- Commit `f3079e8` pushed to GitHub PR #79 on 2026-05-14.
- PR-triggered GitHub CI #25849798467 passed with `Fast Checks` and
  `Full Verify` green on 2026-05-14.
- PR-triggered Dart Package Publish Dry Run #25849798445 passed on
  2026-05-14.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`: passed on 2026-05-14.
