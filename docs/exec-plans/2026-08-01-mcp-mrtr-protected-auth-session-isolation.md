# Exec Plan: MCP MRTR Protected Auth and Session Isolation

## Status

Completed.

## Goal

Prove that a consumer application can complete MCP `2026-07-28` form
elicitation through a bearer-protected router endpoint without exposing input
requests to rejected callers or mutating an existing `2025-*` Streamable HTTP
session.

## Scope

- Add focused public-client regressions showing that ordinary and direct JSON
  MRTR retries read the current bearer grant on every round, so caller-managed
  grant replacement during an elicitation callback applies to the retry.
- Prove that modern MRTR calls made by a client with an active compatibility-
  era Streamable session omit that session from every request and preserve the
  existing session ID and resume cursor.
- Extend protected router smoke coverage so missing or unknown credentials are
  rejected before any elicitation callback or WAMP procedure invocation.
- Extend the isolated generated consumer package to complete standard and
  direct JSON MRTR rounds with a real router-issued bearer grant and no MCP
  session state.
- Keep the supported MRTR surface limited to non-sensitive form-mode
  `elicitation/create`; this milestone does not add another MCP extension.

## Non-Goals

- Add URL-mode elicitation, Roots, Sampling, Tasks, or Apps.
- Automatically refresh credentials or choose an authorization policy inside
  the MRTR helper.
- Interpret or persist opaque server `requestState` in the router.
- Prescribe UI, secure-storage, or user-agent choices for consumer
  applications.

## Verification

- Focused `McpStreamableHttpClient` auth/session regressions.
- Consumer-package boundary tests.
- Real isolated generated consumer package against the native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package publish dry run, WAMP benchmark workflow,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-01: Selected after both roadmaps confirmed that the concrete MCP
  2026 stateless, listener, and form-MRTR layers are complete and further
  protocol extensions remain demand-driven. The next concrete readiness gap is
  protected MRTR behavior across credential rejection, grant rotation, and
  compatibility-session isolation.
- 2026-08-01: Added a focused client regression covering standard and direct
  JSON MRTR with a grant replacement inside each elicitation callback. Every
  initial request uses the original bearer, every retry uses the replacement,
  modern requests omit the active compatibility session header, and the
  existing session ID and resume cursor remain unchanged.
- 2026-08-01: Extended the isolated generated consumer package so missing and
  unknown credentials are rejected before the callback or WAMP invocation,
  while a real router-issued bearer grant completes standard and direct JSON
  form rounds without creating MCP session state.
- 2026-08-01: The focused client file passed all 110 tests, the consumer
  boundary suite passed all 19 tests, and the isolated generated consumer
  completed against the native router. Pre-change and post-change
  `bin/test-fast` passed.
- 2026-08-01: Complete `bin/verify` passed, including formatting, Rust core and
  FFI, Dart VM, live WAMP, generated package, native router, Chrome, and
  Dart2Wasm coverage.
- 2026-08-01: Commit `76dae03` was pushed to GitLab and GitHub. Exact-head
  GitHub CI `30714923011`, Dart Package Publish Dry Run `30714923069`, and
  WAMP Profile Benchmarks `30714922995` passed on their first attempts.
  Coverage artifact `8823219004` and WAMP artifact `8823111335` were uploaded,
  and the strict deployment-chain audit passed with a clean exact-head CI log
  scan and every required branch, package, and benchmark gate clean.
