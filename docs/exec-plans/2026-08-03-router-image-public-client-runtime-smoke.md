# Exec Plan: Router Image Public Client Runtime Smoke

## Status

Active.

## Goal

Make Router Image release evidence prove that the shipped
`connectanum_mcp:router_hosted_client` executable can use the locally loaded
container through public and bearer-protected endpoints without private
consumer assumptions.

## Scope

- Install Dart in the Router Image workflow and resolve the checked-out public
  workspace before the loaded-image smoke.
- Keep the existing raw protocol smoke as the low-level compatibility guard.
- Run the public package executable against the loaded public endpoint with the
  neutral configured procedure and topic.
- Run the same executable against the protected endpoint by obtaining a
  router-issued ticket grant from the packaged auth endpoint.
- Require direct JSON, standard tool, configured WAMP Meta API, Streamable HTTP,
  pub/sub, session deletion, and protected refresh/revocation evidence.
- Preserve the final multi-architecture build and non-mutating dry-run behavior.

## Non-Goals

- Change router MCP, WAMP Meta API, authentication, or Streamable HTTP runtime
  semantics.
- Add application-specific resources, prompts, credentials, or filesystem
  assumptions.
- Publish or retag a router image.

## Verification

- Runner and workflow source-contract regressions before implementation.
- Public and protected executable runs against a real local native router and,
  when available, the locally loaded Router Image.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head CI, package dry run, WAMP benchmarks, Router Image dry run, and
  strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-03: Selected after reviewing project state, both roadmaps, the
  completed Router Image plan chain, relevant Serena memories, and the shipped
  client executable. The loaded image has comprehensive raw-protocol evidence,
  and the executable has comprehensive source-started-router evidence, but no
  release workflow currently joins those two public surfaces.
- 2026-08-03: Pre-change `bin/test-fast` passed at exact local, GitLab, and
  GitHub head `459a16b`, including native/router integration, MCP/client,
  benchmark, packaging, generated consumer, globally activated client/router,
  and focused Router Image suites.
- 2026-08-03: Added a source-contract regression that first failed because the
  Router Image runner did not invoke the public package executable and the
  workflow did not install Dart or resolve workspace dependencies. The focused
  14-case Router Image suite now passes with those requirements enforced.
- 2026-08-03: The loaded-image runner keeps the raw Python compatibility smoke,
  then invokes `connectanum_mcp:router_hosted_client` against both `/mcp` and
  `/mcp/secure`. It requires direct JSON, standard tools, configured
  registration/subscription metadata, active Streamable HTTP, pub/sub, and
  initialized-session evidence; the protected run additionally requires the
  complete refresh/revoke lifecycle summary.
- 2026-08-03: Both package-client invocations passed against a real local
  native router using the image smoke configuration and compatibility protocol
  version `2025-11-25`. The public run completed direct/Streamable Meta API and
  pub/sub checks; the protected run also reported issued, refreshed, refreshed
  direct-ping, refreshed Streamable-session, revoked-access rejection, and
  revoked-refresh rejection evidence. A local Docker build could not start
  because Docker Desktop remained blocked resolving the upstream Dockerfile
  frontend, so exact loaded-image evidence remains assigned to the hosted
  Router Image dry run.
- 2026-08-03: Post-change `bin/test-fast` passed, including the focused 14-case
  Router Image suite, 20 native integration tests, 22 consumer integration
  tests, 360 core tests, all 94 MCP tests, the complete 193-case MCP/client
  suite, all 96 benchmark tests with 36 live WAMP workloads and all 15 standard
  Meta APIs, generated and globally activated package smokes, the complete
  router CLI consumer smoke, and focused native/auth/session follow-ups.
- 2026-08-03: Final local `bin/verify` passed formatting with 393 files and no
  rewrites, analysis, 113 Rust core tests, 52 Rust FFI tests, 360 Dart core
  tests, all 94 MCP tests, the complete 193-case MCP/client suite, all 96
  benchmark tests, the complete 380-case router suite, the 13-case native
  follow-up, every generated and globally activated package smoke, and
  Chrome/Dart2Wasm.
