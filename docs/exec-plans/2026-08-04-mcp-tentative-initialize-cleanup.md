# Exec Plan: MCP Tentative Initialize Cleanup

## Status

Completed.

## Goal

Ensure a compatibility-era Streamable HTTP endpoint becomes observable and
reusable only after its `initialize` request succeeds and its response is sent.

## Scope

- Treat a newly allocated Streamable initialize endpoint as tentative across
  asynchronous catalog refresh, parameter-header validation, protocol
  dispatch, and response delivery.
- Omit the server-generated `MCP-Session-Id` from every rejected tentative
  initialize response.
- Dispose tentative endpoint state after pre-dispatch rejection, dispatch
  errors, or response-delivery failure.
- Preserve successful initialize, existing-session, modern stateless, direct
  JSON, GET/SSE, DELETE, and idle-lease behavior.
- Prove the failure and cleanup through the real native HTTP boundary using
  only public protocol behavior.

## Non-Goals

- Change accepted MCP parameter-header syntax.
- Add new protocol methods or MCP 2026 extensions.
- Change established-session error or idle-timeout semantics.
- Expose router-internal endpoint counts as public API.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first native HTTP regression for a parameter-header rejection after
  tentative endpoint allocation.
- Focused native and synthetic router tests plus targeted analysis.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows, Router Image dry run, and strict
  deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after the catalog-refresh lease checkpoint. Existing
  rejected-initialize cleanup covers JSON-RPC errors returned by the MCP
  server, but catalog-dependent parameter-header rejection occurs after a
  tentative endpoint is allocated and before that cleanup branch. The error
  response can therefore expose the generated session identifier and retain
  endpoint state despite failed initialization.
- 2026-08-04: Pre-change `bin/test-fast` passed. The fail-first native HTTP
  regression sends a valid initialize with a non-ASCII `Mcp-Param-*` value so
  rejection happens after catalog refresh and endpoint allocation, then checks
  that no generated session identifier escapes and no rejected endpoint can be
  deleted as an accepted session.
- 2026-08-04: The raw native HTTP regression fails before implementation:
  rejection returns a generated `MCP-Session-Id`, and deleting that identifier
  returns `202` rather than `404`. Dart `HttpClient` rejects the non-ASCII
  header before transmission, so the regression deliberately uses a raw socket
  against the real native listener to exercise router-side validation.
- 2026-08-04: Newly issued initialize endpoints now remain tentative until a
  non-error initialize response is delivered. Pre-dispatch rejection omits the
  generated session ID; exceptions, rejected server responses, and response
  delivery failures release the counted request hold and remove the tentative
  endpoint. The fail-first native contract, prior in-flight and catalog-refresh
  lease regressions, targeted router analysis, and all 76 synthetic runtime
  tests pass. Advisory local review prompted cleanup-before-removal ordering and
  a nullable tentative-session identifier instead of a non-null assertion.
- 2026-08-04: Full `bin/verify` passed formatting, analysis, 113 Rust core and
  52 Rust FFI tests, all 360 Dart core tests, all 94 MCP tests, the complete
  193-case MCP/client authorization suite, all 96 benchmark tests, all 384
  router tests, native follow-ups, Chrome/Dart2Wasm coverage, and every
  isolated and globally activated consumer/CLI smoke.
- 2026-08-04: Implementation commit `1d0ac41` is on both maintained `master`
  branches. Exact-head CI `30903324385`, Dart Package Publish Dry Run
  `30903324602`, WAMP Profile Benchmarks `30903324320`, and Router Image dry
  run `30903336234` passed on their first attempts with zero check annotations.
  Coverage artifact `8890450507`, WAMP artifact `8890188059`, Router Image
  preview artifact `8889992368`, and both Docker build records were uploaded.
  The comprehensive strict deployment-chain audit passed with all required
  branch, workflow, package, publish-dry-run, and benchmark-artifact gates
  clean.
