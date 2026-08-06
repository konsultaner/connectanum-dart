# MCP HTTP Redirect Isolation

Status: complete

## Goal

Keep credentials, MCP session identifiers, resume cursors, and router-issued
authentication grants bound to the endpoint selected by the consumer instead
of silently following an HTTP redirect to another request target.

## Context

The Dart `HttpClientRequest` default enables automatic redirects. Protected
Streamable HTTP POST, GET, DELETE, and request-scoped listen requests currently
inherit that behavior, as does the router HTTP-auth client. That can relocate a
credential- or session-bearing operation, accept a redirected authentication
grant, or mutate client session state from a response that did not come from
the configured endpoint.

OAuth metadata discovery remains credential-free and independently validates
discovered endpoints, so this milestone is scoped to requests that carry or
establish authority. Redirect responses should surface through the existing
typed HTTP exceptions, leave the redirect target untouched, and preserve MCP
session and resume state.

## Plan

1. Preserve the green fast-suite baseline and add fail-first local-server
   regressions for Streamable HTTP POST, GET, DELETE, request-scoped listen,
   and router HTTP authentication redirects.
2. Disable automatic redirect following before protected request headers or
   bodies are written.
3. Verify that 3xx responses remain typed, redirect targets receive no
   requests, and MCP session/resume state is not cleared or replaced.
4. Run focused package analysis and tests, `bin/test-fast`, and `bin/verify`.
5. Update the public security contract and project state, bundle the carried
   discovery-deadline hosted evidence with the implementation commit, push
   both maintained branches, and audit the exact-head deployment chain.

## Verification

- Pre-change `bin/test-fast` passed on 2026-08-06, including all MCP/client
  suites, live-router workloads, neutral consumer/package smokes, the complete
  router CLI MCP lifecycle matrix, and focused native/router regressions.
- Four fail-first cases reproduced the gap: a Streamable POST followed a `303`
  and succeeded, GET polling and request-scoped listen reached their redirect
  targets, and router HTTP auth accepted a relocated refresh grant. DELETE did
  not follow under the current Dart runtime and supplies explicit state-
  preservation coverage. All five cases pass after the fix.
- `dart analyze packages/connectanum_client` passes. The complete Streamable
  HTTP and router HTTP-auth regression files pass all 178 cases, including
  shared-transport shutdown wrappers forwarding the redirect policy.
- The first post-change fast run exposed the same missing redirect-property
  forwarding in the generated public consumer transport double. Its isolated
  package smoke passes after the fixture fix, and a fresh uninterrupted
  `bin/test-fast` passes with 360 core tests, all 94 MCP tests, the complete
  257-case MCP/client suite, all 96 benchmark tests with live-router workloads,
  every neutral source/global package smoke, the router CLI MCP lifecycle
  matrix, and focused native/router regressions.
- Final exact-code `bin/verify` passes with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core,
  94 MCP, 257 MCP/client, 96 benchmark/live-router, and 387 router tests; all 13
  focused native-forwarding regressions; every neutral consumer package and
  CLI smoke; and Chrome Dart2Wasm WebSocket coverage.
- Implementation commit `936915a3` is on both maintained `master` branches.
  Exact-head GitHub CI `31083579324`, Dart Package Publish Dry Run
  `31083579469`, WAMP Profile Benchmarks `31083578385`, and Router Image dry
  run `31083615763` passed on their first attempts.
- CI uploaded coverage artifact `8960944934`; WAMP uploaded benchmark artifact
  `8960619628`; Router Image uploaded preview artifact `8960488619` and Docker
  build records `8960582083` and `8960582654`.
- The comprehensive strict deployment-chain audit passes with clean exact-head
  CI logs, loaded-image MCP runtime smoke, multi-architecture image build, and
  all required branch, workflow, package, native-release, package-dry-run, and
  benchmark gates ready. A new RC tag remains an explicit release-approval
  action outside this checkpoint.

## Outcome

Protected MCP and router HTTP-auth requests now remain bound to their configured
endpoint, with typed redirect failures and unchanged MCP state. Local
implementation and verification, exact-head hosted workflows, and the
comprehensive strict deployment-chain audit are clean.
