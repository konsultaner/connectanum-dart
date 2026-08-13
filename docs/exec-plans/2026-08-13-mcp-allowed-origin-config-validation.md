# MCP Allowed-Origin Configuration Validation

Status: completed

## Goal

Reject malformed router-hosted MCP `allowed_origins` entries while building
the native router configuration, so consumer applications receive an
actionable startup failure instead of silently running a route whose malformed
entry can never authorize a request.

## Context

Runtime MCP ingress now validates each request `Origin` as a serialized origin
before allow-list, same-authority, rate-limit, authentication, or session
decisions. Route configuration still validates only that `allowed_origins` is
a string or list of strings. It therefore accepts empty entries and general
URLs carrying user info, path, query, or fragment data even though runtime
origin validation must reject those values. Configuration should enforce the
same serialized-origin boundary while preserving the wildcard and valid
custom-scheme origins.

## Plan

1. Preserve the completed origin-serialization checkpoint's hosted evidence
   and run repository workflow, Serena, overlap, both-roadmap, worktree, and
   pre-change fast-verification checks.
2. Add a fail-first router configuration regression for malformed scalar and
   list entries, with valid wildcard and serialized-origin controls.
3. Validate every configured allowed-origin entry during native config
   construction without exposing the rejected value in the error message.
4. Extend the neutral generated consumer package smoke to prove startup-time
   configuration rejection and retain runtime malformed-request rejection.
5. Run focused and full verification, record the durable Serena convention,
   bundle implementation with pending hosted bookkeeping, publish both
   maintained remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, completed-plan,
  both-roadmap, and worktree preflights passed. The only startup changes are
  the completed origin-serialization checkpoint's expected hosted-evidence
  notes; the scheduled wrapper, child Codex process, and live runlock belong
  to this run, and no unrelated same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed against exact local, GitLab,
  and GitHub head `5145bf98`, including all 20 generator contracts, all 97
  benchmark cases and 37 live WAMP workloads, every generated and globally
  activated consumer smoke, and the focused router/native regression matrix.
- 2026-08-13: The fail-first router regression showed
  `buildNativeConfigJson()` returning normally for the configured value
  `https://agent.example/untrusted-path` instead of rejecting the route.
- 2026-08-13: Native config construction now validates every scalar or list
  allowed-origin alias after trimming. Wildcard and valid serialized custom-
  scheme/host/optional-port values remain supported; empty, user-info, path,
  query, fragment, missing-authority, and origin-list shapes fail with a
  key/index-specific error that does not echo the rejected value.
- 2026-08-13: The focused 25-case router config suite, router analysis, shell
  syntax, all 20 generator contracts, and the isolated neutral consumer smoke
  pass. The consumer proves malformed configuration rejection before native
  runtime discovery, then starts a valid router and proves malformed request-
  Origin rejection before CORS, rate limiting, authentication, or session
  state.
- 2026-08-13: Full `bin/verify` passes with no formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, all 101 MCP tests, the
  complete 280-case client/MCP suite, all 97 benchmark tests with 37 live WAMP
  workloads, every generated and globally activated consumer smoke, the
  complete 439-case router suite, 6 remote-auth cases, 13 native follow-ups,
  and Chrome/Dart2Wasm coverage.
- 2026-08-13: Strict release-ready package validation reaches all seven
  synchronized `3.0.0-beta` archives. Six report zero warnings, and the
  changed router archive reports only the expected pre-commit dirty-worktree
  warning for its two modified package files, with no content, archive-shape,
  version, or dependency blocker. Clean exact-commit package validation,
  publication, and hosted deployment-chain evidence remain.
- 2026-08-13: Commit `05fd1f21` is published to GitLab and GitHub. Clean
  exact-commit strict validation passes all seven synchronized `3.0.0-beta`
  package archives with zero warnings and no private workspace dependency
  blockers.
- 2026-08-13: Exact-head CI `31678516989`, Dart Package Publish Dry Run
  `31678516966`, WAMP Profile Benchmarks `31678517003`, and Router Image dry
  run `31678534781` all pass on their first attempts. Retained artifacts are
  Dart VM coverage `9173011647`, WAMP profile evidence `9172653678`, Router
  Image preview `9172511624`, and Docker build records `9172657803` and
  `9172656933`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs and every required package, Router Image,
  WAMP, relevant Native Artifacts, protected-branch, workflow-visibility, and
  public-router-package gate ready. Native Artifacts run `31221315902` remains
  relevant because no native-release-sensitive input changed. A numeric RC tag
  remains release-approval work and was not created.
