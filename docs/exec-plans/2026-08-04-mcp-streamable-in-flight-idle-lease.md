# Exec Plan: MCP Streamable In-Flight Idle Lease

## Status

Completed.

## Goal

Keep a compatibility-era Streamable HTTP endpoint alive while a valid request
is still executing, then begin its configured idle deadline only after the last
in-flight request completes. A slow router-provided tool must not complete into
an already-expired session.

## Scope

- Track active compatibility-session requests on the router-hosted MCP
  endpoint.
- Cancel the idle deadline while at least one valid request is in flight and
  rearm it after the final request completes.
- Apply the lease to valid GET/SSE polling and POST JSON-RPC work, including
  slow WAMP-backed tool calls.
- Keep endpoint creation, explicit DELETE, router shutdown, and proactive idle
  disposal idempotent and race-safe.
- Ensure malformed session traffic does not acquire a lease or extend the idle
  deadline.
- Prove the behavior through focused runtime and native public-client
  regressions.

## Non-Goals

- Change the default or configured idle timeout values.
- Add sessions to modern `2026-07-28` or direct JSON requests.
- Add cancellation of an application-owned WAMP invocation when the HTTP
  caller disconnects.
- Change bearer, OAuth, or router-issued grant behavior.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first slow-tool regression showing the endpoint expires during a valid
  in-flight request.
- Focused valid-request lease, malformed-traffic, post-completion expiry, and
  lifecycle cleanup tests.
- Dart formatting and targeted analysis.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after proactive quiet-session cleanup landed. Endpoint
  lookup currently rearms the deadline before request validation, and the
  deadline remains armed while valid WAMP-backed work executes. The next
  checkpoint makes active work non-idle without allowing malformed requests to
  act as keepalives.
- 2026-08-04: Pre-change `bin/test-fast` passed. The focused native public-client
  regression now fails after a delayed authorized tool result because the very
  next request receives `404 Unknown MCP HTTP session`, reproducing endpoint
  removal while valid work is still in flight.
- 2026-08-04: Compatibility endpoints now count validated GET/POST requests,
  cancel the deadline while any are active, and rearm only after the final
  request completes. Endpoint lookup no longer acts as activity, malformed
  Last-Event-ID traffic cannot prolong a session, and fallback sweeping remains
  active for genuinely idle endpoints. The overlapping slow-tool regression,
  existing autonomous cleanup regression, complete synthetic runtime suite,
  formatting, and targeted router analysis pass.
- 2026-08-04: Full `bin/verify` passes twice against the exact implementation
  tree. The implementation is ready to push; exact-head hosted workflows,
  Router Image dry-run evidence, and the strict deployment-chain audit remain.
- 2026-08-04: Implementation commit `bbb0dea` is on both maintained `master`
  branches. Exact-head CI `30891197308`, Dart Package Publish Dry Run
  `30891197512`, WAMP Profile Benchmarks `30891195436`, and Router Image dry
  run `30891203830` all pass with zero check annotations. Coverage artifact
  `8885593882`, WAMP artifact `8885261362`, Router Image preview artifact
  `8885106190`, Docker build records `8885216150` and `8885215685`, and the
  comprehensive strict deployment-chain audit all pass.
