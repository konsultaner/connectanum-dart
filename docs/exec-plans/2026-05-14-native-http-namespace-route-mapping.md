# Native HTTP Namespace Route Mapping

Status: complete

## Goal

Close the remaining HTTP bridge namespace auto-mapping readiness item by adding
native runtime evidence that namespace routes enqueue the deterministic WAMP
realm/procedure target before Dart dispatch.

## Scope

- Add a native HTTP/1.1 route regression for `type: namespace`.
- Assert the queued request summary includes the expected realm, procedure,
  path, query, method, and protocol.
- Mark the roadmap namespace auto-mapping item complete once focused and full
  verification pass.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-14.
- `cargo test -p ct_core http_namespace_route_maps_path_to_wamp_procedure_before_dispatch`: passed on 2026-05-14.
- `bin/verify`: passed on 2026-05-14.
- Commit `4337eee` pushed to GitHub PR #79 on 2026-05-14.
- PR-triggered GitHub CI #25852022424 passed with `Fast Checks` and
  `Full Verify` green on 2026-05-14.
- PR-triggered Dart Package Publish Dry Run #25852022270 passed on
  2026-05-14.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run`: passed on 2026-05-14.
