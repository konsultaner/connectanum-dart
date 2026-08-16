# Exec Plan: MCP Auth-Route Discovery

Status: completed
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Make every router-hosted MCP Bearer challenge advertise an HTTP-auth route that
can actually issue a grant for the protected route's resolved realm and session
profile.

## Problem

The router currently advertises the first exact-path route whose base action is
`auth`. With multiple session profiles, a protected MCP endpoint can therefore
direct a consumer to an auth route that issues an intentionally incompatible
grant. Auth actions configured as the effective `POST` method action are not
discoverable at all, even though the router serves them normally.

## Plan

1. Extend the existing public HTTP-auth profile-isolation regression so a
   missing-bearer MCP request must discover its compatible alternate auth route
   and complete that advertised grant path successfully.
2. Make auth-route discovery mirror native effective-`POST` routing, including
   method-action overrides and base-action method constraints.
3. Select only candidates compatible with the challenged session profile and
   resolved realm, while preserving `/auth` as the conventional fallback.
4. Run focused, fast, and full verification, then publish and collect exact-head
   deployment-chain evidence.

## Progress

- 2026-08-16: Serena and repository preflight completed with no unrelated
  editor or stale lock. The inherited working-tree changes are the preceding
  route-match isolation milestone's exact-head hosted-evidence notes.
- 2026-08-16: Pre-change `bin/test-fast` passed, including all 97 benchmark
  tests with 37 live WAMP workloads and every maintained MCP consumer/CLI
  smoke.
- 2026-08-16: The public HTTP regression first failed because a missing-bearer
  request for the alternate-profile MCP route received
  `auth_path="/auth"`. That first route issues a grant for the wrong profile
  and the existing credential binding correctly rejects it.
- 2026-08-16: Auth-route discovery now mirrors the native method-target map for
  `POST`, skips a compatible-profile route whose only effective method is a
  non-auth `GET`, and selects an auth action configured through the compatible
  route's `POST` method action. The resulting grant completes a modern
  sessionless MCP tool request without a session header.
- 2026-08-16: The focused regression passes five consecutive runs, the complete
  100-test router runtime suite passes, and router analysis is clean.
- 2026-08-16: Post-change `bin/test-fast` passes, including all 97 benchmark
  tests with 37 live WAMP workloads, every maintained MCP consumer/CLI smoke,
  and the isolated globally activated package paths.
- 2026-08-16: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer tests, 52 native FFI tests, the feature-gated native
  metrics snapshot, 366 Dart core tests, 116 MCP tests, the complete 293-case
  MCP/client suite, all 97 benchmark tests including 37 live WAMP workloads,
  all 454 router cases, six remote-auth tests, 13 native follow-ups, every
  maintained consumer/global-activation smoke, Chrome, and Dart2Wasm.
- 2026-08-16: Commit `6882c00b` was published to both maintained `master`
  branches. Exact-head CI `31942878631`, Dart Package Publish Dry Run
  `31942878623`, WAMP Profile Benchmarks `31942878630`, and Router Image dry
  run `31942892443` all passed. Coverage artifact `9262712175`, WAMP artifact
  `9262568104`, Router Image preview artifact `9262497040`, and Docker build
  records `9262550427` and `9262550136` are available.
- 2026-08-16: The comprehensive strict deployment-chain audit passed with
  clean exact-head CI jobs and logs, package and retained native-release
  evidence, loaded-image router-hosted MCP smoke, multi-architecture image
  build, WAMP artifact, workflow visibility, branch protection, and public
  Router Image package visibility. Its non-gating RC summary remains
  intentionally not ready because no approved numeric RC tag points at this
  implementation commit.

## Handoff

- Complete. The implementation, local verification, publication, exact-head
  hosted workflows, retained artifacts, and comprehensive strict audit all
  pass.
