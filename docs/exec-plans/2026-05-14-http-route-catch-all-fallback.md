# HTTP Route Catch-All Fallback

Status: complete

## Goal

Close the HTTP bridge translation-table gap for catch-all fallback routes and
keep Dart synthetic routing aligned with native route priority.

## Scope

- Add explicit catch-all HTTP route match support to router settings/config.
- Encode catch-all routes to native routing as a prefix `/` fallback instead of
  an exact root-only route.
- Make Dart runtime matching select the most specific matching route, so
  catch-all fallbacks do not shadow exact or longer-prefix routes.
- Add focused config, native JSON, and runtime regressions.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_config_loader_test.dart --name "catch-all HTTP wildcard routes" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_json_test.dart --name "catch-all HTTP routes" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "catch-all HTTP routes" --chain-stack-traces`: passed on 2026-05-14.
- `git diff --check`: passed on 2026-05-14.
- `bin/verify`: passed on 2026-05-14.
- Commit `649d925` pushed to GitHub PR #79 on 2026-05-14.
- PR-triggered GitHub CI #25847918490 passed with `Fast Checks` and
  `Full Verify` green on 2026-05-14.
- PR-triggered Dart Package Publish Dry Run #25847918488 passed on
  2026-05-14.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`: passed on 2026-05-14.
