# Exec Plan: MCP External Bearer Scope-Key Isolation

Status: complete
Owner: Codex
Created: 2026-08-15
Last updated: 2026-08-15

## Goal

Prevent distinct router-hosted MCP external-auth scopes from sharing an
internal WAMP session when configurable provider, realm, and session-profile
names form the same delimiter-joined cache key.

## Scope

- In scope:
  - prove isolation between two protected MCP routes whose provider, realm,
    and profile tuples collide under the current colon-joined key;
  - replace the ambiguous tuple serialization with an opaque,
    collision-resistant scope digest;
  - preserve per-credential authorization-context ordering and terminal
    rejection cleanup without retaining raw bearer credentials;
  - verify each route exposes only the tools registered in its configured
    realm.
- Out of scope:
  - restricting currently valid provider, realm, or profile names;
  - changing external-provider validation policy;
  - changing MCP tool naming or authorization semantics.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/router_runtime_test.dart`
- `ROADMAP.md`
- `docs/project_state.md`
- this execution plan

## Preconditions

- No unrelated Codex process is editing this repository.
- Both maintained `master` branches point at commit `c0e5854f`; its exact-head
  deployment chain and comprehensive strict audit are green.
- The existing hosted-evidence notes are docs-only and will be bundled with
  this implementation.
- Pre-change `bin/test-fast` exits zero across the maintained repository,
  live-WAMP, executable, and consumer-smoke matrix.

## Plan

1. Add a public protected MCP runtime regression with two deliberately
   delimiter-colliding provider/realm/profile tuples and realm-specific tools.
2. Encode the external-auth scope as an unambiguous opaque digest while
   keeping the bearer itself out of binding-owned cache and turn keys.
3. Run focused checks and `bin/verify`, update durable readiness state, publish
   the implementation to both maintained remotes, and inspect the exact-head
   GitHub deployment chain.

## Verification

- `bin/test-fast`
- Focused router runtime regression before and after implementation
- HTTP-auth provider and router runtime matrix
- `dart analyze packages/connectanum_router`
- `bin/verify`
- Exact-head GitHub CI, package dry run, WAMP benchmark, Router Image dry run,
  and strict deployment-chain audit after publication

## Decision Log

- 2026-08-15: Provider names, realm URIs, and session-profile names are
  configurable strings. Joining them with `:` is not injective, so a cache key
  must encode field boundaries independently of their contents.
- 2026-08-15: The fail-first public regression initialized both colliding
  protected routes, but initialization of the second scope closed the first
  route's retained context. Its next valid tool call returned HTTP 404 instead
  of HTTP 200.
- 2026-08-15: The cache and turn key now hashes the JSON-encoded provider,
  realm, profile, and credential-digest tuple into a fixed opaque scope key.
  Both routes retain independent sessions, list only their own realm tools,
  and return realm-specific direct JSON tool-call results.
- 2026-08-15: Router analysis, the focused scope/context regressions, and the
  complete HTTP-auth provider plus router runtime matrix pass all 104 cases.
  Focused local review found no confirmed correctness or security issue; its
  syntax concern was disproved by the clean analyzer and executing test, and
  the extra digest allocation is negligible beside per-request external
  provider validation.
- 2026-08-15: Full `bin/verify` exits zero with formatting unchanged; Rust core
  and FFI green; 366 core tests; 116 MCP tests; the complete 293-case
  MCP/client suite; 97 benchmark tests including all 37 live WAMP workloads;
  the 444-case router suite; six remote-auth tests; 13 native follow-ups; every
  maintained consumer smoke; Chrome; and Dart2Wasm green.
- 2026-08-15: Commit `e444c989` is published to both maintained `master`
  branches. Exact-head CI `31888094426`, Dart Package Publish Dry Run
  `31888094454`, WAMP Profile Benchmarks `31888094447`, and Router Image dry
  run `31888120409` all pass with zero check annotations. Coverage artifact
  `9247965577`, WAMP artifact `9247884067`, Router Image preview artifact
  `9247812363`, and Docker build records `9247856745` and `9247856528` are
  available.
- 2026-08-15: The comprehensive strict deployment-chain audit exits zero with
  exact-head CI and logs, package publishing, reusable native-release evidence,
  loaded-image MCP smoke, multi-architecture image builds, WAMP artifacts,
  branch protection, workflows, and package visibility clean. The non-gating
  RC summary remains intentionally not ready because no approved numeric RC tag
  points at this implementation commit.

## Handoff

- Implementation, local verification, publication, exact-head hosted evidence,
  and the strict deployment-chain audit are complete.
