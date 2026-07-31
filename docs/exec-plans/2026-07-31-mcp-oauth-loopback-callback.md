# Exec Plan: MCP OAuth Native Loopback Callback

## Status

Complete.

## Goal

Let native Dart MCP consumers receive an OAuth authorization response on a
standards-conformant loopback redirect and safely hand the result to the
existing state and PKCE flow without application-private listener code.

## Scope

- Bind an IO-only HTTP listener to a caller-selected loopback IP address and
  an ephemeral port by default.
- Expose the exact redirect URI for authorization requests and dynamic client
  registration.
- Wait once for a matching authorization response with a total timeout and a
  bounded number of unrelated requests.
- Require GET, the configured path, and exactly one matching `state` value
  before accepting a callback; safely ignore bounded stray loopback traffic.
- Reconstruct the callback from the listener's known redirect target and the
  received query instead of trusting the request `Host` header.
- Return static, non-reflective browser responses with no-store and restrictive
  security headers, then close the listener on every terminal path.
- Export the listener through public IO MCP entrypoints and prove it from an
  isolated consumer package without private project assumptions.

## Standards Direction

- RFC 8252 requires native applications to use an external user-agent and
  defines loopback redirects using IP literals such as `127.0.0.1` or `[::1]`
  with a dynamically selected port. It recommends IP literals instead of the
  `localhost` hostname and requires authorization servers to allow arbitrary
  ports for loopback redirect URIs.
- The MCP authorization specification requires exact redirect registration,
  PKCE, and `state` validation. The listener therefore exposes its final bound
  URI before the authorization request is created and only accepts a request
  created for that exact URI.
- A local callback endpoint is reachable by unrelated local software. Wrong
  methods, paths, and states are rejected without completing the flow, but
  every request consumes a bounded attempt and the entire wait shares one
  deadline.
- The incoming `Host` header is attacker-controlled HTTP input. The accepted
  callback URI is derived from the already-known listener URI plus only the
  received query, so host spoofing cannot change redirect validation.
- Browser response bodies are static and never include authorization codes,
  states, error descriptions, or raw query data.

Primary references:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- <https://www.rfc-editor.org/rfc/rfc8252.html>
- <https://www.rfc-editor.org/rfc/rfc7636.html>
- <https://www.rfc-editor.org/rfc/rfc9700.html>

## Non-Goals

- Launch or control the system browser.
- Persist client registrations, tokens, PKCE verifiers, or authorization
  transactions across application launches.
- Bind wildcard or non-loopback interfaces, reserve a fixed port by default,
  or use the `localhost` hostname.
- Implement custom URI schemes, claimed HTTPS redirects, mobile deep links,
  or an embedded web view.
- Change router authorization-server behavior.

## Verification

- Focused binding, valid callback, stray-request, host-spoofing, OAuth-error,
  timeout, lifecycle, redaction, and validation regressions
- Public IO-entrypoint and isolated consumer-package smoke coverage
- `dart analyze packages/connectanum_client packages/connectanum_mcp`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-07-31: Pre-change `bin/test-fast` passed, including package suites,
  native and Dart WAMP workloads, isolated and global consumers, every
  router-hosted MCP mode, and router CLI consumer coverage.
- 2026-07-31: Confirmed the loopback IP-literal, ephemeral-port, exact redirect,
  PKCE, and state requirements against the MCP specification and RFC 8252, and
  recorded the listener's bounded local-request and untrusted-Host contract.
- 2026-07-31: Added the public one-shot loopback callback listener with IPv4-
  first/IPv6-fallback binding, configurable loopback IP and safe path, total
  timeout, request bound, exact redirect/state/path/method checks, and closure
  on every terminal outcome.
- 2026-07-31: Added static hardened browser responses, rebuilt accepted
  callbacks from the known listener URI instead of `Host`, and sanitized typed
  parser errors so codes, states, descriptions, and raw callback queries do not
  enter response bodies or exception strings.
- 2026-07-31: Added nine focused listener regressions, updated the public IO
  authorization lifecycle to use a real ephemeral callback, and updated the
  isolated consumer smoke to register, receive, and exchange against the exact
  bound redirect while preserving its active Streamable HTTP session.
- 2026-07-31: Focused client/MCP analysis and tests, the isolated client
  package smoke, and post-change `bin/test-fast` passed. The expanded client MCP
  suite now contains 161 tests, including the nine listener regressions.
- 2026-07-31: A clean complete `bin/verify` passed formatting, 113 Rust core
  tests, 52 FFI tests, 360 core Dart tests, 85 MCP tests, 161 client MCP tests,
  all 96 benchmark tests, the complete 377-test router suite, isolated and
  globally activated consumers, every router-hosted MCP variant, focused native
  forwarding checks, and Chrome/Dart2Wasm.
- 2026-07-31: Commit `624d262` was pushed to GitLab and GitHub. Exact-head
  GitHub CI `30633977048`, Dart Package Publish Dry Run `30633977054`, and WAMP
  Profile Benchmarks `30633977046` passed on their first attempts; the strict
  deployment-chain audit then passed with clean CI logs and all required
  branch, workflow, package, benchmark-artifact, and registry gates clean.
