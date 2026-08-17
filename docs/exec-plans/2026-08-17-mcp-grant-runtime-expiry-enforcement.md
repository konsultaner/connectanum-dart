# Exec Plan: MCP Grant Runtime Expiry Enforcement

Status: completed
Owner: Codex
Created: 2026-08-17
Last updated: 2026-08-17

## Goal

Prevent grant-aware MCP clients from transmitting a bearer credential after
its locally known access-token expiry while preserving active Streamable HTTP
state for a caller-managed refresh and in-place grant replacement.

## Scope

- Retain the absolute access-token expiry alongside the client-owned
  authorization header for router HTTP-auth and OAuth token grants.
- Carry that expiry in the same immutable authorization snapshot used by each
  POST, GET, DELETE, and request-scoped listener setup.
- Reject an expired snapshot through a public, token-redacted typed exception
  immediately before opening a new HTTP request.
- Keep the active MCP session ID, resume cursor, protocol, request sequence,
  HTTP-client ownership, and established request-scoped listeners unchanged so
  a consumer application can refresh and replace the grant in place.
- Make replacement update header and expiry atomically. Raw bearer-token APIs
  and grants without advertised expiry remain caller-managed compatibility
  surfaces.
- Do not terminate an already-established listener merely because its
  establishment grant later expires; server-side stream authorization and
  caller-owned refresh/reconnect policy remain authoritative for open streams.
- Prove the boundary in focused client regressions and through the public MCP
  IO package entrypoint.

## Preconditions

- The expected launchd wrapper, its current `codex exec` child, and live
  runlock are the scheduled run, not an overlap. No unrelated Codex process is
  editing this repository and no startup conflict is present.
- The only inherited changes are the completed grant-persistence plan and
  project-state hosted-evidence bookkeeping from commit `a577ed17`.
- Serena instructions, exact-path project activation, and onboarding checks
  pass.
- `docs/project_state.md`, the completed grant-persistence plan,
  `ROADMAP_NEXT.md`, and the MCP readiness context in `ROADMAP.md` have been
  reviewed.

## Plan

1. Run the required pre-change `bin/test-fast` baseline.
2. Add fail-first regressions proving a grant accepted before expiry cannot be
   used for any new MCP HTTP request after expiry and that rejection preserves
   session/resume/auth state.
3. Retain expiry in authorization snapshots, add the redacted public exception,
   and enforce it at the common pre-open request boundary.
4. Prove fresh in-place grant replacement restores same-session operation and
   that raw bearer clients retain their existing behavior.
5. Extend the public MCP IO package proof and package guidance/changelogs.
6. Run focused formatting, analysis, tests, public boundary checks, affected
   smoke tests, and canonical `bin/verify`.
7. Commit implementation and bookkeeping together, run the strict clean-tree
   package audit, publish to both maintained remotes, and require exact-head
   hosted CI/package evidence plus deployment-chain audits.

## Progress

- 2026-08-17: Preflight and symbol-aware review confirm that grant-aware
  construction/replacement validates current expiry but authorization state
  retains only the bearer header. A client accepted before expiry can therefore
  continue opening new HTTP requests with the known-expired credential.
- 2026-08-17: The required pre-change `bin/test-fast` baseline passes through
  the complete package, benchmark, generated-consumer, globally activated, and
  router CLI smoke matrix. The fail-first regression could not compile before
  the new public exception existed.
- 2026-08-17: Grant-aware router HTTP-auth and OAuth clients now retain access-
  token expiry in their immutable authorization snapshot and reject it at the
  common request-open boundary. POST, GET, DELETE, direct JSON, and request-
  scoped listener setup all fail without network I/O after expiry; session and
  resume state stay intact, raw bearer clients remain caller-managed, and fresh
  in-place replacement restores requests on the same client.
- 2026-08-17: Focused formatting and analysis pass. The complete VM
  Streamable HTTP client regression file and all 16 public MCP IO-entrypoint
  tests pass, including live public-package proof of redacted expiry rejection
  and successful replacement.
- 2026-08-17: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer checks, all 52 FFI tests plus metrics mode, 366 Dart core
  tests, 118 MCP package tests, the complete 319-case client/MCP suite, all 97
  benchmark tests with 37 live WAMP workloads, all 454 router tests, six remote-
  auth tests, 13 native follow-ups, every maintained isolated/generated/globally
  activated consumer smoke, Chrome, and Dart2Wasm. Its 20-case release-package,
  22-case deployment-audit, and 34-case router-image contract blocks also pass.
- 2026-08-17: Serena memory `mcp/grant_runtime_expiry_enforcement` records the
  durable snapshot, replacement, session-preservation, established-listener,
  and raw-bearer compatibility contract.
- 2026-08-17: Clean-tree strict release readiness passes all seven publishable
  packages at synchronized version `3.0.0-beta` with zero warnings, validated
  executable entrypoints, and no private workspace dependency blockers.
- 2026-08-17: Clean commit `5ecd0f1d` (`Reject expired MCP grants before
  requests`) is published to both maintained feature-branch remotes. Exact-head
  GitHub `CI` run `32002152088` passes Fast Checks job `95304397082`, Full
  Verify job `95305916439`, and Dart VM Coverage job `95305916459`, including
  successful Codecov upload. Retained coverage artifact `9279199917` has digest
  `sha256:c43685affc05e6aaa3af863bdd68dd638bdc3717b4a1f909ea11c473c31cb7f7`.
  Dart Package Publish Dry Run `32002152101` passes job `95304397053` and
  covers the exact head.
- 2026-08-17: The feature-branch deployment-chain audit passes exact-head
  CI/job/log cleanliness, current package-run relevance, checked-in workflow
  visibility, and public router-package visibility. The comprehensive strict
  protected-release baseline also passes from an isolated `master` worktree at
  `ec53a327`, including required status checks, exact-head CI/log cleanliness,
  relevant package/native/router-image/WAMP evidence, workflow visibility, and
  public router-package visibility. Its non-gating RC summary correctly remains
  not ready because no newly approved numeric RC tag targets that commit.
- 2026-08-17: Post-completion consumer-application validation exposed a router
  bridge gap when a router-hosted MCP internal caller selected an external WAMP
  callee: final results, progressive results, and invocation errors attempted
  to resolve a network connection for the internal session instead of using its
  response port. The worker now returns all three response forms through the
  existing internal-session message contract while preserving lazy payloads,
  PPT metadata, and custom details. A focused worker regression and a live
  consumer-application smoke prove MCP initialization, tool discovery, a read
  procedure, and a guarded state-changing procedure against an external
  WebSocket callee.
- 2026-08-17: Canonical `bin/verify` passes after the bridge fix with zero
  formatting changes, all native tests, 366 Dart core tests, 118 MCP package
  tests, the complete 319-case client/MCP suite, all 97 benchmark tests with 37
  live WAMP workloads, all 455 router tests, six remote-auth tests, 13 native
  follow-ups, every maintained consumer smoke, Chrome, and Dart2Wasm.

## Handoff

- Completed. Implementation, focused checks, canonical verification, clean-
  tree package readiness, publication, exact-head hosted workflows, retained
  coverage evidence, the feature-branch deployment audit, the strict protected-
  release baseline, and post-completion external-callee integration hardening
  pass.
