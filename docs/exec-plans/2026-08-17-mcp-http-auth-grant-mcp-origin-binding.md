# Exec Plan: MCP HTTP-Auth Grant Origin Binding

Status: completed
Owner: Codex
Created: 2026-08-17
Last updated: 2026-08-17

## Goal

Prevent a downstream application from disclosing a router-issued bearer grant
to an MCP endpoint on a different HTTP origin.

## Scope

- In scope:
  - bind grant-aware MCP client construction and replacement to the HTTP origin
    of the grant's issuing auth endpoint;
  - reject grants with unknown or different origin before creating or replacing
    an authorization header;
  - cover both maintained Streamable HTTP and modern stateless constructors;
  - retain raw bearer-token constructors and replacement for compatibility and
    explicit caller-managed authority;
  - preserve same-origin direct JSON, Streamable HTTP, WAMP meta, pub/sub, and
    package-boundary smoke behavior.
- Out of scope:
  - changing router-side grant scope or route policy;
  - constraining raw bearer-token APIs;
  - cross-origin token delegation or exchange.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/http_auth_client.dart`
- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_client/CHANGELOG.md`
- `bin/common.sh`
- `packages/connectanum_mcp/README.md`
- `packages/connectanum_mcp/test/io_client_export_test.dart`
- `packages/connectanum_mcp/CHANGELOG.md`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `tool/test_mcp_consumer_package_boundary.py`
- `docs/project_state.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- Commit `dc659d69` is published to both maintained feature-branch remotes.
- The preceding slice's hosted-evidence documentation is the only inherited
  working-tree change and will be bundled with this implementation.
- Exact-head GitHub CI and package dry-run workflows are green.

## Plan

1. Add fail-first public-client regressions proving that an endpoint-bound
   grant cannot create or replace authorization for a cross-origin MCP client.
2. Add a public grant-origin predicate and enforce it in grant-aware
   Streamable/stateless construction and replacement before bearer material is
   copied into client state.
3. Extend the public MCP export and generated consumer boundary checks while
   retaining same-origin live lifecycles.
4. Run focused client/package tests and maintained consumer smokes.
5. Run `bin/verify`, review, publish, and collect exact-head hosted evidence.

## Verification

- focused Streamable HTTP client tests
- public MCP IO package tests
- generated consumer structural boundary checks
- affected source/globally activated/generated consumer smokes
- `bin/test-fast`
- `bin/verify`
- strict release-ready package dry run
- exact-head hosted workflows after publication

## Decision Log

- 2026-08-17: Selected this slice because exact auth-endpoint provenance now
  protects refresh and revocation, but grant-aware MCP constructors can still
  copy the bearer into a client targeting another origin. Discovery already
  requires the auth route to share the protected MCP origin, so the public
  grant-aware client boundary should preserve that authority before I/O.
- 2026-08-17: Keep raw bearer-token APIs explicitly caller-managed for
  compatibility; only grant-aware APIs require known same-origin provenance.

## Progress

- 2026-08-17: Serena preflight, onboarding, overlap checks, project-state and
  both-roadmap review pass. Only the preceding slice's intentional hosted-
  evidence documentation is modified at startup.
- 2026-08-17: Pre-change `bin/test-fast` passes, including the complete
  312-case client/MCP suite and all 97 benchmark tests with 37 live WAMP
  workloads.
- 2026-08-17: Fail-first Streamable HTTP regressions reproduce cross-origin
  grant construction and replacement before implementation. Grant-aware
  Streamable/stateless construction and in-place replacement now require known
  same-origin issuer provenance, and failed replacement preserves the active
  session, cursor, and credential.
- 2026-08-17: The complete 180-case Streamable HTTP client file, combined
  230-case focused public client/package suite, Dart analysis, 23-case generated
  consumer structural suite, and shell syntax validation pass.
- 2026-08-17: The first canonical verification attempt exposed maintained
  client-consumer and router raw-JSON fixtures that omitted grant issuer
  provenance. The guard failed them before I/O as designed. All generated fake
  endpoints now use a matching auth origin, raw-JSON grant helpers attach the
  exact issuing endpoint, the isolated and globally activated client consumer
  smoke passes, and the full 454-case router VM suite passes with `ffi-test`.
- 2026-08-17: Final canonical `bin/verify` passes with zero formatting changes,
  the complete 314-case client/MCP suite, all 97 benchmark tests with 37 live
  WAMP workloads, all 454 router tests, six remote-auth integrations, 13
  zero-copy follow-ups, every maintained isolated/generated/globally activated
  consumer smoke, Chrome, and Dart2Wasm. The strict release-ready package dry
  run reaches the changed client package with clean package content and stops
  only on its intentional dirty-tree warning; rerun from the implementation
  commit remains before publication.
- 2026-08-17: Clean-tree strict release readiness passes all seven publishable
  packages with zero warnings. Commit `3bdecef8` (`Bind router HTTP auth grants
  to MCP origins`) is published to both maintained feature-branch remotes.
  Exact-head GitHub `CI` run `31991484405` passes Fast Checks job `95275734383`,
  Full Verify job `95276929712`, and Dart VM Coverage job `95276929731`;
  retained coverage artifact `9275787067` has digest
  `sha256:f111f22f38671d7dce56fa138f12afee5a42482a6afba2e46f532fee9d19cfc1`.
  Dart Package Publish Dry Run `31991484403` passes job `95275734357` and
  covers the exact head.
- 2026-08-17: The feature-branch deployment-chain audit passes exact-head
  CI/job/log cleanliness, current package-run relevance, checked-in workflow
  visibility, and public router-package visibility. The strict protected-
  release baseline also passes from an isolated `master` worktree at
  `ec53a327` with required Fast Checks and Full Verify branch protection.

## Handoff

- Completed. Implementation, local verification, clean-tree package readiness,
  publication, exact-head hosted workflows, retained coverage evidence, the
  feature-branch deployment audit, and the strict protected-release baseline
  pass.
