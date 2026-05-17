# Router Caller Disclosure Policy

Status: implementation complete locally; commit, push, and hosted evidence
refresh are pending.

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

## Remaining

- Commit and push the implementation with this state update.
- Refresh hosted CI/package-dry-run evidence for the pushed checkpoint.
