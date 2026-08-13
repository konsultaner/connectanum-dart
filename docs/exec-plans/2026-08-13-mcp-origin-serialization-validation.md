# MCP Origin Serialization Validation

Status: completed

## Goal

Reject malformed single `Origin` values on router-hosted MCP routes before
rate limiting, bearer authentication, or MCP session state, while preserving
valid same-authority and explicitly configured origin behavior.

## Context

The router already rejects repeated `Origin` fields, but its default
same-authority check parses one value and compares only the parsed host and
port. A raw HTTP client can therefore append user info, a path, query, or
fragment to an otherwise matching HTTP(S) URL and pass the MCP origin guard.
An HTTP `Origin` value is a serialized origin, not a general request URL, so
the router must validate that shape before allow-list or authority decisions.
[RFC 6454 section 7.1](https://www.rfc-editor.org/rfc/rfc6454.html#section-7.1)
defines the wire shape as `scheme://host[:port]`; this checkpoint therefore
preserves valid non-HTTP schemes while rejecting URL-only components.

## Plan

1. Preserve the completed Host-multiplicity checkpoint's hosted-evidence
   notes and run repository workflow, Serena, overlap, both-roadmap, worktree,
   and pre-change fast-verification checks.
2. Add fail-first synthetic and raw native HTTP regressions showing that a
   same-host Origin carrying URL path data reaches authentication and consumes
   route state.
3. Validate single router-hosted MCP Origin values as serialized
   origins before allow-list and same-authority checks, retaining absent Origin
   compatibility and valid non-HTTP scheme/host/port triples.
4. Extend the neutral installed-router consumer smoke with malformed-Origin
   rejection and immediate valid endpoint reuse.
5. Run focused and full verification, record the durable Serena convention,
   bundle implementation with pending hosted bookkeeping, publish both
   maintained remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, completed-plan,
  both-roadmap, and worktree preflights passed. The only startup changes are
  the completed Host-multiplicity checkpoint's expected hosted-evidence notes;
  the scheduled wrapper, child Codex process, and live runlock belong to this
  run, and no unrelated same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed against exact local, GitLab,
  and GitHub head `aa3a3c42`, including all 97 benchmark cases and 37 live
  WAMP workloads plus the complete consumer/package and focused router/native
  smoke matrix.
- 2026-08-13: Fail-first synthetic and raw native HTTP regressions each
  received HTTP 401 for a same-host Origin carrying a path, proving that the
  previous host-only comparison reached bearer authentication.
- 2026-08-13: Router-hosted MCP now parses a present Origin as an RFC 6454
  scheme/host/optional-port tuple before allow-list or same-authority checks.
  User info, path, query, fragment, invalid/missing authority, and origin-list
  shapes fail closed while a valid non-HTTP consumer scheme remains usable.
- 2026-08-13: Synthetic coverage rejects seven malformed shapes before CORS,
  rate limiting, authentication, or session state and immediately reaches the
  expected bearer challenge with a valid custom-scheme Origin. The raw native
  regression passes the same path case without response state.
- 2026-08-13: The neutral generated consumer proves an explicitly configured
  malformed value cannot bypass syntax validation, and the globally activated
  router plus isolated Dart consumer reports
  `originSerializationValidation: true` before completing its direct JSON,
  pub/sub, Streamable HTTP, authentication, and endpoint-reuse matrix. Focused
  router analysis/tests, shell syntax, all 20 generator contracts, and both
  consumer smokes pass.
- 2026-08-13: Full `bin/verify` passes with no formatting changes, 114 Rust
  core tests, 52 Rust FFI tests, 360 Dart core tests, all 101 MCP tests, the
  complete 280-case client/MCP suite, all 97 benchmark tests with 37 live WAMP
  workloads, every generated and globally activated consumer smoke, the
  complete 438-case router suite, 6 remote-auth cases, 13 native follow-ups,
  and Chrome/Dart2Wasm coverage. Strict release-ready package validation
  reaches all seven synchronized `3.0.0-beta` archives: six report zero
  warnings, and the changed router archive reports only the expected
  pre-commit dirty-worktree warning with no content, archive-shape, version,
  or dependency blocker. Clean exact-commit package validation, publication,
  and hosted deployment-chain evidence remain.
- 2026-08-13: Commit `5145bf98` is published to GitLab and GitHub. Clean
  exact-commit strict validation passes all seven synchronized `3.0.0-beta`
  package archives with zero warnings and no private workspace dependency
  blockers.
- 2026-08-13: Exact-head CI `31673242800`, Dart Package Publish Dry Run
  `31673242754`, WAMP Profile Benchmarks `31673242797`, and Router Image dry
  run `31673271387` all pass on their first attempts. Retained artifacts are
  Dart VM coverage `9170929139`, WAMP profile evidence `9170661094`, Router
  Image preview `9170514362`, and Docker build records `9170637547` and
  `9170636884`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs and every required package, Router Image,
  WAMP, relevant Native Artifacts, protected-branch, workflow-visibility, and
  public-router-package gate ready. Native Artifacts run `31221315902` remains
  relevant because no native-release-sensitive input changed. A numeric RC tag
  remains release-approval work and was not created.
