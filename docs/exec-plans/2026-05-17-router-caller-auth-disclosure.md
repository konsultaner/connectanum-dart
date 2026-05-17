# Router Caller Auth Disclosure

Status: complete; code is pushed and hosted deployment-chain evidence is clean
for enforced gates.

## Goal

Complete WAMP caller disclosure details for router-dispatched RPC invocations.
When caller disclosure is allowed by caller `disclose_me` or callee
`disclose_caller`, callees should receive the caller session plus
`caller_authid` and `caller_authrole` when those values are known. When
disclosure is not allowed, router-owned caller disclosure fields must not be
forwarded or spoofed through custom call options.

## Plan

- Carry caller auth identity through `InvocationDispatchResult`.
- Apply disclosed caller auth details on Dart fallback, internal-session, and
  native zero-copy invocation forwarding.
- Filter router-owned invocation detail keys from custom call options.
- Add focused worker/runtime/native coverage for the disclosed and undisclosed
  paths.

## Verification

- `bin/test-fast`: passed before edits on 2026-05-17.
- `dart analyze packages/connectanum_router`: passed.
- `dart test packages/connectanum_router/test/router_worker_session_test.dart --chain-stack-traces`: passed.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --chain-stack-traces`: passed.
- `cargo test -p ct_ffi cbor_event_and_invocation_segments_preserve_payload_slices --release`: passed.
- `git diff --check`: passed.
- Private-name scan on touched docs: passed.
- `bin/verify`: passed on 2026-05-17.
- Commit `314a962`: pushed to GitHub PR #79.
- GitHub CI #25983330491 and #25983331352: passed with `Fast Checks` and
  `Full Verify` green.
- Dart Package Publish Dry Run #25983330497 and #25983331308: passed.
- Native Artifacts dry-run #25983559481: passed for preview tag `v0.1.0-rc.2`.
- Router Image dry-run #25983562548: passed for preview tag `v0.1.0-rc.2`.
- WAMP Profile Benchmarks #25983565524: passed.
- Strict deployment-chain audit with latest CI/logs, package dry-run, native
  dry-run, router-image dry-run, WAMP benchmarks, workflow visibility, GHCR
  package visibility, and RC-readiness reporting: passed for enforced gates.

## Remaining

- PR #79 still requires review/merge into `master` before release-branch
  promotion.
- A fresh operator-approved RC tag is still required for the promoted candidate;
  the published `v0.1.0-rc.1` tag remains tied to `47bbf9c`.
- Pub.dev publishing remains deferred until package ownership, public versions,
  and private workspace release order are explicitly decided.
