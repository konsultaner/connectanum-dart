# MCP HTTP-Auth Nested Object Duplicate Validation

Status: implementation complete; local verification green; publication pending

## Goal

Make the router-provided HTTP authentication endpoint reject repeated JSON
object members anywhere inside operation-relevant initial `authextra` or
challenge `extra` values before invoking authenticators or consuming challenge
state, while preserving valid objects, null-as-omitted compatibility, and
operation-specific handling of irrelevant fields.

## Context

The HTTP auth bridge now retains duplicate top-level request members and
validates the outer shape of map-valued authentication parameters. Duplicate
members inside an `authextra` or `extra` object are still collapsed by
`jsonDecode` before authenticator callbacks receive the metadata. Authenticators
may use both direct and nested metadata members for security-sensitive
decisions, so parser last-value behavior must not decide their input.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the required
   workflow/Serena/overlap/roadmap preflight, and establish a green pre-change
   fast matrix.
2. Add fail-first router lifecycle coverage for duplicate direct and nested
   members inside initial `authextra` and challenge `extra`, including pending
   capacity and legitimate-retry assertions.
3. Retain duplicate-member evidence within the selected auth object and reject
   it with the generic state/token-free HTTP 400 before authenticator creation
   or pending-challenge removal, without changing valid/null or irrelevant
   cross-operation behavior.
4. Extend the neutral installed-router consumer smoke with duplicate nested
   auth-object rejection, retained pending state, valid completion, and an
   explicit evidence marker.
5. Run focused and full verification, write durable Serena/project state,
   publish the implementation checkpoint, and audit the exact-head GitHub
   deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes are the preceding
  checkpoint's expected hosted-evidence notes; the runlock belongs to the live
  scheduled wrapper and no unrelated same-repository Codex process exists.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: Fail-first router lifecycle coverage reproduced an escaped-
  equivalent duplicate member inside initial `authextra` reaching the ticket
  authenticator and returning HTTP 401 instead of the generic HTTP 400. The
  final dedicated lifecycle regression covers direct, nested, and array-held
  duplicate objects for initial `authextra`, direct and nested challenge
  `extra`, explicit-null compatibility, retained max-one pending capacity,
  legitimate completion, and refresh-operation scoping.
- 2026-08-12: The raw JSON evidence scan now canonicalizes object member names
  and recursively retains duplicate evidence for each top-level value. Initial
  and challenge handlers reject evidence only for the selected object
  parameter before authenticator creation or pending-state removal. Router
  analysis, the focused regression, the complete 88-case router runtime suite,
  shell syntax, diff hygiene, and the neutral installed-router consumer smoke
  pass. The consumer reports `authNestedObjectMultiplicityValidation: true`
  and completes the retained legitimate challenge before continuing through
  protected MCP, direct JSON, pub/sub, refresh/revoke, and Streamable HTTP.
- 2026-08-12: Full `bin/verify` passes with unchanged formatting and clean
  analysis, 114 Rust core tests, 52 FFI tests, all 360 Dart core tests, all 101
  MCP tests, the 280-case client/MCP matrix, all 96 benchmark cases and 36 live
  WAMP workloads, all 435 router tests, six isolated remote-auth integrations,
  13 native follow-ups, every neutral consumer and installed-command smoke,
  and Chrome/Dart2Wasm coverage.
- 2026-08-12: Implementation commit `9d038536a356` reached both maintained
  `master` branches. Exact-head GitHub CI `31580742905` then exposed five new
  Dart 3.13 analyzer diagnostics absent from the local SDK, and package dry run
  `31580742681` failed on the same router warnings. The repair awaits a WAMP
  fake-call result before its `finally` cleanup, removes three unused catch
  stack bindings, and forwards the native library path with a super parameter.
  Workspace analysis plus the 51-case benchmark-runner, 70-case router worker,
  and 12-case native transport suites pass. A second full `bin/verify` passes
  the complete matrix unchanged at 435 router tests.
