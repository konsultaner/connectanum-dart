# MCP Origin Header Multiplicity Validation

Status: complete; local and exact-head hosted verification green

## Goal

Make router-hosted MCP reject repeated case-insensitive `Origin` headers before
route rate limiting, bearer authentication, or MCP principal/session handling,
even when the first collapsed value is allowed.

## Context

The native HTTP boundary now retains normalized duplicate-header-name
evidence, but MCP Origin validation still selects one scalar value. A request
can therefore carry both an allowed and rejected Origin and reach quota,
authentication, or session state according to header iteration order. MCP's
existing invalid-Origin boundary is HTTP 403 and intentionally precedes those
mutations.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run the
   required workflow, Serena, overlap, completed-plan, both-roadmap, and green
   pre-change fast-matrix checks.
2. Add a fail-first router regression with allowed-first, rejected-second
   case-variant Origin fields and require a sessionless HTTP 403 without CORS,
   rate-limit, or bearer-challenge state.
3. Make the shared MCP Origin predicate fail closed on repeated normalized
   Origin names so the pre-rate-limit ingress gate and CORS response builder
   cannot disagree.
4. Extend real native HTTP integration and the neutral installed-router
   consumer smoke, including valid direct JSON and Streamable recovery after
   rejection.
5. Run focused and full verification, capture the durable convention, publish
   the implementation checkpoint, and audit the exact-head GitHub deployment
   chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes; the scheduled runlock belongs
  to the current live run and no unrelated same-repository Codex process
  exists.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: A fail-first router regression sent an allowed Origin before a
  case-variant rejected Origin and observed HTTP 401 instead of HTTP 403,
  proving scalar selection let the request reach bearer authentication.
- 2026-08-12: The shared MCP Origin predicate now rejects normalized repeated
  Origin names before scalar parsing. Focused synthetic and real native HTTP
  regressions, router analysis, shell syntax, diff hygiene, the complete router
  runtime suite, and the isolated installed-router consumer pass. The consumer
  reports `originHeaderMultiplicityValidation: true`, proves the rejection
  exposes no CORS, rate-limit, bearer-challenge, or session state, and continues
  through direct JSON, pub/sub, Streamable HTTP, refresh/revoke, and session
  deletion.
- 2026-08-12: Post-change `bin/verify` passes with zero formatting changes,
  114 Rust core tests, 52 Rust FFI tests, 360 core tests, 101 MCP tests, the
  complete 280-case client/MCP suite, all 96 benchmark cases and 36 live WAMP
  workloads, all 436 router tests, six remote-auth integrations, 13 native
  follow-ups, every generated and installed consumer smoke, and
  Chrome/Dart2Wasm.
- 2026-08-12: Implementation commit `75cf249f7066` reached both maintained
  `master` branches. The clean-commit strict package gate passes all seven
  synchronized `3.0.0-beta` archives with zero warnings. Exact-head CI
  `31604704535`, package dry run `31604704478`, WAMP Profile Benchmarks
  `31604704494`, and Router Image dry run `31606491257` all pass. CI uploaded
  coverage artifact `9145272598`, WAMP uploaded artifact `9144850018`, and
  Router Image uploaded preview artifact `9145326473` plus Docker build
  records `9145493288` and `9145492382`. The comprehensive strict
  deployment-chain audit exits zero with clean exact-head CI logs and every
  required branch, workflow, public package, unchanged native-release
  relevance, loaded-image MCP, multi-architecture image, package-publish, and
  benchmark gate clean. The non-gating RC summary remains intentionally not
  ready because no approved numeric RC tag points at this implementation head.
