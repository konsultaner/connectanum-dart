# MCP Content-Type Header Multiplicity Validation

Status: completed

## Goal

Make router-hosted MCP reject repeated case-insensitive `Content-Type` field
names on POST before one native scalar value can select JSON body handling or
allow request dispatch.

## Context

The native HTTP boundary preserves normalized duplicate-header-name evidence
while exposing scalar header values to router handlers. Router-hosted MCP now
rejects repeated authorization, Origin, protocol-version, session-ID, and
resume-cursor names at their corresponding trust boundaries, but POST media
type validation still selects one `Content-Type` scalar. A request can carry a
valid JSON content type before a conflicting case-variant field and let map
iteration decide whether the body is accepted. The fix must preserve protected
route authentication, Accept negotiation, unknown compatibility-session
handling, stateless 2026 behavior, and continued use of a valid session after
rejection.

## Plan

1. Preserve the completed resume-header checkpoint's hosted-evidence notes and
   run the workflow, Serena, overlap, both-roadmap, and green pre-change fast
   verification checks.
2. Add a fail-first protected-session regression proving a repeated
   case-insensitive `Content-Type` request currently reaches scalar media-type
   validation or dispatch.
3. Reject repeated normalized `Content-Type` names on POST after authentication
   and the existing compatibility-session precedence boundaries but before
   scalar media-type validation, body decoding, or dispatch.
4. Extend real native HTTP integration and the neutral installed-router
   consumer smoke, then prove the original session remains usable.
5. Run focused and full verification, write the durable Serena convention,
   bundle implementation plus state evidence, publish both maintained remotes,
   and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, active-plan, both-roadmap,
  and exact-head deployment preflights passed. The only startup changes are the
  completed resume-header checkpoint's expected hosted-evidence notes; the
  scheduled wrapper, child Codex process, and live runlock belong to this run,
  and no unrelated same-repository editor exists.
- 2026-08-12: Pre-change `bin/test-fast` passed. The protected-session
  fail-first regression returned HTTP 202 for an authenticated notification
  carrying `Content-Type: application/json` plus case-variant
  `content-type: text/plain`, proving scalar selection allowed dispatch; its
  bearer-free counterpart remained HTTP 401.
- 2026-08-12: Router-hosted POST handling now rejects normalized repeated
  `Content-Type` names with the canonical HTTP 400 JSON-RPC
  `Invalid Content-Type header` response. Sessionless initialize, active
  session, bearer-free protected, and unknown claimed-session regressions pin
  the intended precedence and session reflection behavior.
- 2026-08-12: The focused synthetic runtime test, real native-router test,
  router analyzer, shell syntax, diff hygiene, all 19 consumer-boundary
  contracts, and the neutral installed-router consumer smoke pass. Native and
  generated consumer requests use raw HTTP so the evidence contains two
  distinct case-variant wire fields; both continue through valid session use
  after rejection.
- 2026-08-12: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests, 52 FFI tests, 360 Dart core tests, all 101 MCP tests, the complete
  280-case client/MCP matrix, all 97 benchmark cases and 37 live WAMP
  workloads, all 436 router tests, six isolated remote-auth integrations, 13
  native follow-ups, every neutral consumer and installed-command smoke, and
  Chrome/Dart2Wasm coverage. The implementation is ready to publish; exact-head
  hosted workflows and the strict deployment-chain audit remain follow-up
  evidence.
- 2026-08-12: Strict release-ready validation passed all seven synchronized
  `3.0.0-beta` package archives with zero warnings. Implementation commit
  `9a61449621ea` is published on both maintained `master` remotes. Exact-head
  Dart Package Publish Dry Run `31637826023` and WAMP Profile Benchmarks
  `31637826063` pass; CI `31637826022` also passes Fast Checks, Full Verify,
  and coverage.
- 2026-08-12: Router Image dry run `31637835420` failed before image creation
  because current `dart:stable` (3.13.0) now rejects `dart compile exe` when
  the package graph declares build hooks. Official Dart CLI documentation says
  hook-bearing applications must use `dart build`; `dart build cli` runs build
  hooks and emits an application bundle under `<output>/bundle/`. A fail-first
  Dockerfile contract reproduced the stale command. The image builder now uses
  `dart build cli --target=packages/connectanum_router/bin/connectanum_router.dart
  --output=/out` and copies `/out/bundle/bin/connectanum_router`; all 29 focused
  Router Image MCP contracts pass. Local Docker Desktop stalled while resolving
  the Dockerfile frontend and while sending the legacy build context, before a
  build instruction ran, so the repaired exact-head hosted dry run remains the
  decisive image proof.
- 2026-08-12: Exact-head CI `31637826022` completed successfully, including
  Fast Checks, Full Verify, and Dart VM coverage. Post-repair `bin/test-fast`
  also passes the complete local fast matrix, including all neutral consumer
  and installed-command MCP smokes. Final post-repair `bin/verify` passes the
  complete repository matrix: formatting, Rust/FFI, 360 core, 101 MCP, 280
  client/MCP, 97 benchmark plus 37 live WAMP, 436 router, isolated remote-auth,
  native follow-up, consumer-package, installed-command, and Chrome/Dart2Wasm
  coverage. Publication, the repaired Router Image dry run, and the strict
  audit remain.
- 2026-08-12: Toolchain-repair commit `fc62e6c5ef81` is published on both
  maintained `master` remotes. Strict release-ready package validation again
  passed all seven synchronized archives with zero warnings. Exact-head CI
  `31642069646`, Dart Package Publish Dry Run `31642123332`, WAMP Profile
  Benchmarks `31642125463`, and Router Image dry run `31642076746` all pass.
  CI uploaded coverage artifact `9159878300`, WAMP uploaded artifact
  `9159478975`, and Router Image uploaded preview artifact `9159248769` plus
  Docker build records `9159390243` and `9159389744`. The repaired image job
  passed the hook-aware local build, loaded router-hosted MCP smoke, and
  multi-architecture dry-run build. The comprehensive strict deployment-chain
  audit passes exact-head CI and log cleanliness, package, relevant native
  release, Router Image, WAMP, workflow visibility, public router package,
  branch protection, and release-readiness gates. Creating a follow-up numeric
  RC tag remains an explicit release-approval decision and is not part of this
  checkpoint.
