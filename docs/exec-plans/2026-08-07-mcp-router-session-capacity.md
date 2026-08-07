# MCP Router Session Capacity

Status: active; implementation and local verification clean, commit and hosted verification pending

## Goal

Bound compatibility-era router-hosted MCP session admission so a client bug or
hostile caller cannot retain arbitrarily many server/session objects during the
configured idle window while modern stateless requests remain sessionless.

## Scope

- In scope: positive snake/camel route options, a safe default capacity,
  route-scoped atomic admission, authorization precedence, HTTP/JSON-RPC
  overload behavior without session-header leakage, active-session reuse,
  modern direct JSON independence, DELETE and idle-expiry capacity recovery,
  and normal local and hosted verification.
- Out of scope: limiting WAMP realm sessions, request-scoped MCP 2026 listener
  concurrency, per-principal quotas, distributed limits across router
  processes, and changing the existing session idle timeout.

## Preconditions

- Both maintained `master` branches and the local branch start at `5e3c2391`.
- The preceding router response-body checkpoint passed local verification,
  exact-head hosted workflows, and the comprehensive strict deployment audit.
- The preceding checkpoint's hosted-evidence bookkeeping is intentionally
  uncommitted and will accompany this implementation.

## Plan

1. Run the pre-change fast gate and add fail-first route-validation and native-
   router regressions showing that a configured session capacity is ignored.
2. Add positive `max_session_count` and `maxSessionCount` route options with a
   bounded default and enforce admission atomically before a compatibility MCP
   endpoint is retained.
3. Prove public and protected capacity rejection, missing-bearer precedence,
   no rejected-session state/header, continued use of the admitted session,
   modern stateless direct JSON independence, DELETE and idle-expiry recovery.
4. Run focused, fast, and full verification; update durable state; commit and
   push both maintained branches; then audit exact-head hosted evidence.

## Verification

- `dart analyze packages/connectanum_router`
- `dart test packages/connectanum_router/test/router_json_test.dart`
- focused `router_integration_native_test.dart` regression
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-07: Source audit found that compatibility MCP sessions receive
  per-route idle expiry but have no admission bound. Each admitted ID retains
  an MCP server endpoint and may retain WAMP subscription state until DELETE,
  idle expiry, or router shutdown. The limit will count only compatibility
  endpoints for the route; the shared modern/stateless endpoint and request-
  scoped listeners remain outside this session-capacity slice.
- 2026-08-07: The pre-change `bin/test-fast` gate passed. Fail-first route
  validation then accepted `max_session_count: 0`, and the native router
  admitted a second compatibility session on a route configured for one.
- 2026-08-07: MCP routes now accept positive `max_session_count` and
  `maxSessionCount` values with a default of 1024. Admission sweeps expired
  sessions first, counts only compatibility endpoints on the same listener and
  route, and atomically rejects excess initialize requests with HTTP `503` and
  a JSON-RPC internal error without an MCP session header.
- 2026-08-07: Native integration coverage proves public and protected route
  limits, missing-bearer precedence while the protected route is full,
  rejected-client state isolation, active-session reuse, sessionless direct
  JSON operation at capacity, and recovery after both DELETE and idle expiry.
- 2026-08-07: Focused router analysis, route-validation tests, and native
  session/idle-expiry tests passed. Post-change `bin/test-fast` and
  `bin/verify` both exited zero; full verification included Rust core/FFI,
  all Dart packages, router native integrations, neutral consumer and CLI
  smokes, router-hosted MCP live variants, and Chrome Dart2Wasm coverage.

## Handoff

- Commit and push bounded session admission together with the deferred exact-
  head evidence from the preceding checkpoint, then audit the new exact-head
  hosted deployment chain.
