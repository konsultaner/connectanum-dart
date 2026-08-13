# MCP Allowed-Origin Tuple Matching

Status: active

## Goal

Match explicit router-hosted MCP `allowed_origins` entries by their normalized
scheme, host, and effective port, so valid equivalent configuration and
request serializations authorize the same origin instead of failing because
their raw strings differ.

## Context

The preceding checkpoint validates every configured allow-list entry as an
origin-shaped URI, but runtime authorization still uses exact string
membership. A valid configured value such as
`HTTPS://AGENT.EXAMPLE:443` therefore rejects the ordinary browser
serialization `https://agent.example`.

[RFC 6454 sections 4 through 6](https://www.rfc-editor.org/rfc/rfc6454.html#section-4)
define an origin as a scheme/host/port triple, lowercase the scheme and host,
substitute the protocol's default port, and compare those normalized triples.
The router should apply that identity rule only after its existing strict
serialized-origin shape validation. CORS responses must continue reflecting
the request's valid Origin value unless the configured wildcard applies.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence edits and run
   repository workflow, Serena, overlap, both-roadmap, worktree, and
   pre-change fast-verification checks.
2. Add a fail-first router regression for a normalized request Origin that is
   equivalent to a configured origin with uppercase scheme/host and an
   explicit default port.
3. Compare validated configured and request origins by normalized
   scheme/host/effective-port tuples while preserving wildcard, malformed-
   origin rejection, default same-authority behavior, and CORS reflection.
4. Extend neutral consumer evidence if needed to prove the public route
   behavior without private project assumptions.
5. Run focused and full verification, record the durable Serena convention,
   bundle implementation with pending hosted bookkeeping, publish both
   maintained remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, required skill, Serena, overlap,
  completed-plan, both-roadmap, and worktree preflights passed. The only
  startup changes are the preceding checkpoint's expected hosted-evidence
  notes; the scheduled wrapper, child Codex process, and live runlock belong
  to this run, and no unrelated same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed against exact local, GitLab,
  and GitHub head `05fd1f21`, including all 20 generator contracts, 360 core
  tests, 101 MCP tests, the complete client/MCP matrix, all 97 benchmark cases
  and 37 live WAMP workloads, every generated and globally activated consumer
  smoke, and the focused router/native regression matrix.
- 2026-08-13: The fail-first synthetic router regression received HTTP 403
  for request Origin `https://agent.example` when the configured origin was
  the equivalent `HTTPS://AGENT.EXAMPLE:443`, proving the raw-string mismatch.
- 2026-08-13: Explicit allow-list matching now compares already-validated URI
  scheme, normalized host, and effective port values. Wildcard handling and
  default same-authority matching are unchanged. The focused regression
  proves the equivalent origin reaches bearer authentication with request-
  Origin CORS reflection, while the same host on port 444 remains forbidden
  before CORS, authentication, rate limiting, or session state.
- 2026-08-13: Router analysis, shell syntax, the focused runtime regression,
  and the neutral installed-router consumer package smoke pass. The smoke
  starts a route configured with the uppercase/default-port origin and proves
  a lowercase MCP 2026 sessionless direct JSON tool-list response, exact
  request-Origin CORS reflection, and no MCP session header.
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
