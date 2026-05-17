# Router Caller Disclosure Policy

Status: complete. Implementation is committed and pushed as `7de6f7c`; local
verification and hosted CI/deployment evidence are clean.

## Goal

Make router invocation caller disclosure consistent across external workers,
internal sessions, and native-forwarded invocations before the next release
candidate. A callee that registered with `disclose_caller` must receive the
caller session ID even when the caller did not set `disclose_me`, and internal
callees must not receive caller session IDs unless disclosure was requested by
the caller or callee policy.

## Implementation

- `RouterStateStore._dispatchInvocation` computes the disclosure decision once
  from `CALL.options.disclose_me` and the selected callee registration details.
- `InvocationDispatchResult` carries that decision to all invocation forwarding
  paths.
- Worker external forwarding, worker internal forwarding, and
  router-internal-session forwarding use the shared dispatch decision instead
  of recomputing or always disclosing the caller.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-17.
- `dart test packages/connectanum_router/test/router_worker_session_test.dart --name "honors callee-requested caller disclosure during CALL dispatch"`: passed.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "applies caller disclosure policy across internal sessions"`: passed.
- `dart test packages/connectanum_router/test/router_worker_session_test.dart packages/connectanum_router/test/router_runtime_test.dart`: passed.
- `dart analyze packages/connectanum_router`: passed.
- `git diff --check`: passed.
- Private-name scan on touched docs: passed.
- `bin/verify`: passed on 2026-05-17.
- Push-triggered GitHub CI #25982020999: passed.
- PR-triggered GitHub CI #25982021874: passed.
- Push-triggered Dart Package Publish Dry Run #25982020997: passed.
- PR-triggered Dart Package Publish Dry Run #25982021872: passed.
- Router Image dry-run #25982272601: passed for preview tag `v0.1.0-rc.2`.
- WAMP Profile Benchmarks #25982272605: passed.
- Strict deployment-chain audit with latest CI/logs, package dry-run,
  router-image dry-run, WAMP benchmark, and RC-readiness reporting: passed for
  the refreshable branch gates.

## Remaining

- PR #79 still needs review/merge before release-branch promotion.
- Final RC tagging still needs operator approval for a fresh tag at the
  promoted commit plus matching native/router evidence for that tag.
