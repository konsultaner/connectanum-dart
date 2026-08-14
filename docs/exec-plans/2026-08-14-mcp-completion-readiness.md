# Exec Plan: MCP Completion Readiness

Status: active; implementation and local verification complete; hosted evidence pending
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Make prompt and resource-template argument completion usable through the public
Dart packages and router-hosted MCP endpoints, including lifecycle-free direct
JSON access and neutral installed-package evidence.

## Scope

- In scope:
  - Typed prompt/resource-template completion references, arguments, context,
    and bounded results shared by the public MCP server and IO client surfaces.
  - `completion/complete` server dispatch and truthful `completions`
    capability advertisement.
  - Streamable HTTP and direct JSON client helpers with strict result
    validation and MCP 2026 request metadata/header handling.
  - Router-configured completion candidates for prompts and resource
    templates, filtered without exposing unauthorized catalogs.
  - Focused package/router regressions plus neutral consumer and Router Image
    smoke evidence.
- Out of scope:
  - Deprecated MCP logging, roots, or sampling APIs.
  - Opt-in Tasks or application-specific completion ranking services.
  - Automatic projection of arbitrary WAMP application data into suggestions.

## Files Expected To Change

- Shared MCP protocol types in `packages/connectanum_core`.
- Server, capability, prompt/resource, and tests in `packages/connectanum_mcp`.
- Streamable/direct HTTP helpers and tests in `packages/connectanum_client`.
- Router MCP config, dispatch, validation, and focused integration tests.
- Neutral consumer/Router Image smoke tooling and public MCP compatibility
  notes where the supported protocol surface materially changes.

## Preconditions

- Commit `f27eceb6` is published to both maintained `master` branches and its
  exact-head deployment-chain evidence is green.
- The pre-change `bin/test-fast` gate exits zero.
- The stable MCP `2026-07-28` schema includes `completion/complete` as the one
  client-to-server core request not yet implemented here. Logging, roots, and
  sampling are deprecated; Tasks remain an opt-in extension.

## Plan

1. Add fail-first shared-model, server, client, and router tests for completion
   validation, capability advertisement, and standard/direct request paths.
2. Implement the shared typed contract plus server dispatch and bounded result
   semantics.
3. Add typed Streamable HTTP/direct JSON helpers and strict response checks.
4. Add router-configured prompt/resource-template candidates with standard,
   direct JSON, stateless, and authorization-filtered behavior.
5. Extend neutral package and Router Image smoke evidence, update public notes,
   and run focused checks plus full repository verification.
6. Commit and push the implementation, then collect exact-head hosted and
   strict deployment-chain evidence required by the affected package paths.

## Verification

- Focused core, MCP server, Streamable HTTP client, and router MCP tests.
- Neutral installed-package server/client and router consumer smokes.
- Router Image MCP smoke contracts.
- Affected package analysis and shell/Python validation.
- `bin/verify`.

## Decision Log

- 2026-08-14: Official stable schema comparison shows discovery, tools,
  resources, prompts, and subscriptions are implemented; completion is the
  remaining non-deprecated core client request. It improves interactive
  consumer use of the already-shipped prompt/resource-template catalogs and
  therefore outranks opt-in extensions and speculative transport work.
- 2026-08-14: Router configuration will provide explicit bounded candidate
  sets. Dynamic ranking/application-data projection stays outside this slice,
  avoiding implicit disclosure while still giving downstream applications a
  useful standard endpoint.
- 2026-08-14: Router-configured candidate lists are capped at 1000 values per
  argument, and each response remains capped at the MCP limit of 100 values.
  This keeps static route configuration useful without making request cost or
  memory use unbounded.

## Handoff

- Pre-change `bin/test-fast` exits zero, including 364 core tests, 113 MCP
  tests, the 282-case MCP/client suite, 97 benchmark tests with all 37 live
  WAMP workloads, and maintained installed-package/router smokes.
- Typed package regressions, focused router standard/direct/modern and
  authorization-filtering tests, affected-package analysis, shell/JavaScript/
  Python checks, the server-only package smoke, the router-hosted consumer
  smoke, and Router Image smoke contracts pass.
- Full `bin/verify` exits zero with formatting unchanged, 114 Rust core tests,
  all 52 FFI tests, 366 Dart core tests, 115 MCP tests, the 283-case MCP/client
  suite, 97 benchmark tests including all 37 live WAMP workloads, the 442-case
  router suite, 6 remote-auth tests, 13 native follow-ups, all generated and
  globally activated consumer smokes, Chrome, and Dart2Wasm green.
- Commit/push, exact-head hosted workflows, and the strict deployment-chain
  audit remain.
