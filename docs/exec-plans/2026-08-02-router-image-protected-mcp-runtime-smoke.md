# Exec Plan: Router Image Protected MCP Runtime Smoke

## Status

In progress.

## Goal

Make router-image release evidence prove that the packaged router can issue a
neutral ticket-authenticated HTTP grant and serve a protected router-hosted MCP
endpoint without exposing authenticated Streamable HTTP session state to an
unauthenticated request.

## Scope

- Extend the neutral Router Image smoke configuration with a ticket-backed
  `/auth` route and bearer-protected `/mcp/secure` route.
- Extend the black-box image client through challenge completion, modern direct
  JSON discovery/meta access, a compatibility-era Streamable pub/sub lifecycle,
  access-token revocation, and rejected-bearer behavior.
- Assert that missing bearer credentials neither receive nor destroy an active
  MCP session, and fix the router if the packaged lifecycle exposes a gap.
- Keep the existing public MCP image lifecycle intact.

## Non-Goals

- Add a new authentication method, external identity provider, or OAuth flow.
- Publish or retag a router image.
- Duplicate the complete native-router and generated-consumer matrices in the
  image workflow.
- Depend on private application names, paths, services, or credentials.

## Verification

- Focused smoke-client/config contract tests.
- Focused native-router auth/session regression.
- Local packaged public and protected MCP lifecycle when Docker registry bases
  are available.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, package dry run, WAMP benchmarks, Router Image dry run,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected after reviewing `ROADMAP_NEXT.md` and `ROADMAP.md`.
  The public Router Image MCP lifecycle is green, while protected grant,
  session, direct JSON, pub/sub, and revocation behavior remained outside the
  packaged runtime boundary.
- 2026-08-02: Pre-change `bin/test-fast` passed across analysis, deployment and
  package contracts, Rust and Dart suites, live WAMP benchmarks, generated and
  globally activated consumers, and router auth/session coverage.
- 2026-08-02: Added neutral ticket auth plus protected MCP routes and extended
  the black-box client through unauthenticated rejection, challenge completion,
  modern direct meta access, Streamable pub/sub and DELETE, grant revocation,
  and revoked-bearer rejection.
- 2026-08-02: The first live packaged run reproduced an auth/session defect:
  a missing-bearer Streamable request reflected its client-supplied
  `MCP-Session-Id` on the 401 response. A focused native regression reproduced
  the leak. The generated consumer then exposed the same stale behavior for
  handler-level invalid-bearer rejection. Both rejection paths now omit MCP
  session headers, and the native plus generated-consumer regressions prove
  the authenticated session remains usable across missing and invalid bearer
  attempts.
- 2026-08-02: Six focused Python smoke/config tests, Python compilation, shell
  syntax validation, and YAML parsing pass. Local Docker registry metadata
  resolution stalled before the uncached canonical base images could resolve;
  the hosted Router Image dry run remains the required clean-build and
  black-box container evidence.
- 2026-08-02: Post-change `bin/test-fast` passed. The first full verification
  exposed two additional HTTP/3 and principal-isolation expectations that
  still required a session header on protected 401 responses; those contracts
  now require no session header while retaining authenticated-session recovery.
  Final `bin/verify` passed with no formatting changes, 113 Rust core tests, 52
  Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the complete 193-case
  MCP/client suite, all 96 benchmark tests with live WAMP workloads, isolated
  and globally activated consumers, the complete 380-case router suite, 13
  focused native follow-ups, and Chrome/Dart2Wasm WebSocket coverage.
