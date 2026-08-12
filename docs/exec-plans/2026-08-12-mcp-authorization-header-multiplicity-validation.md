# MCP Authorization Header Multiplicity Validation

Status: complete; local and exact-head hosted verification green

## Goal

Make router-hosted MCP reject repeated case-insensitive `Authorization`
headers before selecting a bearer value for rate limiting, transport
authentication, or MCP principal/session creation, while preserving
invalid-Origin precedence and bearer-free OPTIONS and Protected Resource
Metadata access.

## Context

The native HTTP boundary now retains normalized duplicate-header-name
evidence, but router-hosted MCP still reads a scalar `Authorization` value.
The selected value can therefore depend on header collapse or map iteration
order, and a rejected request can mutate a bearer-keyed rate-limit bucket
before authentication or session handling establishes a trusted principal.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the required
   workflow, Serena, overlap, completed-plan, both-roadmap, and green
   pre-change fast-matrix checks.
2. Add fail-first router coverage for case-variant repeated Authorization,
   invalid-Origin precedence, credential-free OPTIONS, rate-limit isolation,
   and sessionless generic rejection.
3. Reject repeated Authorization before rate-limit and transport-auth
   evaluation, without requiring a bearer for ordinary Protected Resource
   Metadata or preflight handling.
4. Extend native and neutral generated-consumer evidence across real repeated
   headers, protected direct JSON recovery, and bearer-bucket isolation.
5. Run focused and full verification, capture the durable convention, publish
   the implementation checkpoint, and audit the exact-head GitHub deployment
   chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes are the preceding
  checkpoint's expected hosted-evidence notes; the scheduled runlock belongs
  to a live process and no unrelated same-repository Codex process exists.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: A fail-first router regression expected generic HTTP 400 for a
  case-variant repeated Authorization request but observed HTTP 401, proving
  that MCP ingress selected one scalar bearer after rate-limit evaluation.
  The ingress boundary now rejects repeated Authorization after Origin policy
  and before rate limiting, transport authentication, or principal/session
  resolution for POST, GET, DELETE, and OPTIONS. Errors retain allowed-origin
  CORS and preflight headers while omitting challenges, rate-limit headers,
  and caller-supplied session state.
- 2026-08-12: Focused synthetic and real native HTTP regressions, router
  analysis, shell syntax, diff hygiene, the full router runtime suite, and the
  isolated generated consumer pass. The consumer proves a rejected request
  cannot consume the sole bearer-keyed rate-limit bucket, rejects two valid
  principals without creating session or challenge state, and immediately
  recovers with one valid grant. Ordinary bearer-free Protected Resource
  Metadata remains available.
- 2026-08-12: Post-change `bin/verify` passes with zero formatting changes,
  114 Rust core tests, 52 Rust FFI tests, 360 core tests, 101 MCP tests, the
  complete 280-case client/MCP suite, all 96 benchmark cases and 36 live WAMP
  workloads, all 436 router tests, six remote-auth integrations, 13 native
  follow-ups, every generated and installed consumer smoke, and
  Chrome/Dart2Wasm.
- 2026-08-12: Implementation commit `bdf3a9e0d24a` reached both maintained
  `master` branches. The clean-commit strict package gate passes all seven
  synchronized `3.0.0-beta` archives with zero warnings. Exact-head CI
  `31598216464`, package dry run `31598216444`, WAMP Profile Benchmarks
  `31598216558`, and Router Image dry run `31598417943` all pass. CI uploaded
  coverage artifact `9142561534`, WAMP uploaded artifact `9142214114`, and
  Router Image uploaded preview artifact `9142044409` plus Docker build
  records `9142179382` and `9142178624`. The comprehensive strict
  deployment-chain audit exits zero with clean exact-head CI logs and every
  required branch, workflow, public package, unchanged native-release
  relevance, loaded-image MCP, multi-architecture image, package-publish, and
  benchmark gate clean. The non-gating RC summary remains intentionally not
  ready because no approved numeric RC tag points at this implementation head.
