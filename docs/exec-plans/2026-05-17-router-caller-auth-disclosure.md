# Router Caller Auth Disclosure

Status: implementation complete locally; commit, push, and hosted evidence
refresh are pending.

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

## Remaining

- Commit and push the implementation with this state update.
- Refresh hosted CI/package-dry-run evidence for the pushed checkpoint.
