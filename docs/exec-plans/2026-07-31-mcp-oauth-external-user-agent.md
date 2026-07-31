# Exec Plan: MCP OAuth External User-Agent Orchestration

## Status

Complete.

## Goal

Let native and Flutter MCP consumers launch an OAuth authorization request in
their platform's external user-agent and await the existing RFC 8252 loopback
callback without hand-assembling concurrent listener, launcher, timeout, and
failure-cleanup logic.

## Scope

- Add a public external-user-agent launcher callback contract to the IO-only
  OAuth loopback API.
- Begin consuming the loopback listener before invoking the launcher so an
  immediate redirect cannot race or deadlock the application.
- Pass only the prepared authorization URI to the launcher and return the
  existing validated `McpAuthorizationCode` after a successful callback.
- Share one total timeout across launcher invocation and callback receipt.
- Close the listener and drain its pending wait when the launcher fails or
  stalls, then expose only a typed redacted failure.
- Keep invalid listener/request configuration from invoking the external
  user-agent.
- Prove the helper through focused listener tests, the public MCP IO entrypoint,
  and the isolated consumer-package lifecycle smoke.

## Standards Direction

- RFC 8252 requires native applications to use an external user-agent rather
  than an embedded web view. The public helper coordinates that launch with the
  existing loopback listener but does not prescribe a UI or process package.
- The launcher is caller-supplied because the package supports pure Dart,
  desktop, and Flutter targets whose platform-safe browser integrations differ.
  The package owns OAuth ordering, deadlines, callback validation, and cleanup;
  the consumer owns only the platform action that opens the supplied URI.
- The listener must already be consuming before the launcher is invoked. This
  permits launchers that return after the browser interaction and prevents an
  immediate callback from waiting on application-private ordering.
- Launcher exceptions are untrusted application/platform details. They are not
  retained in the public exception or rendered by `toString()`, because they
  can contain the authorization URI, state, local paths, or process output.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://www.rfc-editor.org/rfc/rfc8252.html>
- <https://www.rfc-editor.org/rfc/rfc9700.html>

## Non-Goals

- Add a Flutter dependency or select an OS-specific browser executable.
- Use an embedded web view, expose authorization URI query data in exceptions,
  or relax the existing loopback redirect and state checks.
- Persist client registrations, PKCE verifiers, authorization transactions, or
  bearer grants across application launches.
- Change router authorization-server behavior or OAuth endpoint discovery.

## Verification

- Focused external-user-agent success, invalid-input, launcher-failure,
  launcher-timeout, cleanup, and redaction regressions
- Public MCP IO-entrypoint lifecycle regression
- Isolated client consumer-package smoke
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Pre-change `bin/test-fast` passed, including all MCP OAuth and
  client suites, isolated and globally activated consumers, benchmark
  integrations, router-hosted MCP variants, and router CLI coverage.
- 2026-07-31: Added the public launcher callback and
  `authorizeWithExternalUserAgent`, which starts the validated listener first,
  returns callback success or OAuth errors without waiting for a launcher that
  stays open, bounds a stalled launcher through the callback deadline, and
  redacts launch failures after closing and draining the listener.
- 2026-07-31: Added focused success, callback-error, invalid-input,
  launcher-failure, timeout, cleanup, and redaction coverage. The public MCP IO
  lifecycle and isolated consumer smoke now use the orchestration helper and
  verify the exact authorization URI supplied across the package boundary.
- 2026-07-31: Focused package analysis, 14 loopback regressions, the public MCP
  IO lifecycle, the full client MCP and MCP package suites, all 18 public
  package-boundary guards, and the isolated and globally activated client
  consumer smoke passed.
- 2026-07-31: Post-change `bin/test-fast` passed, including 166 client MCP
  tests, all router-hosted MCP modes, the generated package consumers, the
  benchmark integration suite, and router CLI consumer coverage.
- 2026-07-31: Complete local `bin/verify` passed, including formatting, 113
  Rust core tests, 52 FFI tests, 360 core Dart tests, 85 MCP tests, 166 client
  MCP tests, all 96 benchmark tests, the complete 377-test router suite,
  isolated and globally activated package consumers, router-hosted MCP and
  router CLI consumer smokes, 13 focused native-router tests, and the
  Chrome/Dart2Wasm WebSocket test.
