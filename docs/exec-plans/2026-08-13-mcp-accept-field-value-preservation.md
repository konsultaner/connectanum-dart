# MCP Accept Field-Value Preservation

Status: completed

## Goal

Make router-hosted MCP preserve every case-insensitive `Accept` field value
from native HTTP ingress and negotiate the combined list, so repeated legal
list fields cannot silently discard JSON or SSE response support.

## Context

The native HTTP boundary retains normalized duplicate-header-name evidence but
currently exposes one scalar value per exact header spelling. That behavior is
correctly used to reject repeated security-sensitive singleton MCP headers,
but `Accept` is a list field: multiple field lines are semantically equivalent
to one comma-separated value and must be evaluated together. Router-hosted MCP
currently selects one scalar `Accept` value, so field spelling and arrival
order can incorrectly change JSON versus SSE negotiation or Streamable HTTP
session opt-in. The fix must preserve the existing quality, specificity,
authentication, protocol, session, and singleton-header precedence rules.

## Plan

1. Preserve the completed content-type checkpoint's hosted-evidence notes and
   run the workflow, Serena, overlap, both-roadmap, and green pre-change fast
   verification checks.
2. Add fail-first synthetic and raw native HTTP regressions proving separate
   `Accept` field values are not currently negotiated as one list.
3. Carry immutable case-insensitive header value lists through native ingress
   into router requests while retaining normalized duplicate-name evidence for
   singleton validation.
4. Negotiate all `Accept` field values together and extend the neutral
   installed-router consumer smoke with real split-field Streamable HTTP proof.
5. Run focused and full verification, write the durable Serena convention,
   bundle implementation plus state evidence, publish both maintained remotes,
   and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, active-plan, both-roadmap,
  and worktree preflights passed. The only startup changes are the completed
  content-type checkpoint's expected hosted-evidence notes; the scheduled
  wrapper, child Codex process, and live runlock belong to this run, and no
  unrelated same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed the complete fast matrix,
  including native ingress tests, router-hosted MCP regressions, live WAMP
  workloads, and every neutral consumer and installed-command smoke.
- 2026-08-13: Fail-first synthetic coverage returned HTTP 200 without an MCP
  session when JSON and SSE appeared in case-variant `Accept` fields. The raw
  native HTTP request returned 406 when the same two values appeared as
  separate wire fields, proving both the router scalar-selection bug and the
  native exact-name overwrite boundary.
- 2026-08-13: Native HTTP ingress now preserves a deeply immutable,
  case-insensitive list of every field value alongside the existing scalar map
  and normalized duplicate-name evidence. Router requests and WAMP HTTP
  snapshots retain that value list, including invocation-payload round trips,
  while singleton MCP header validation remains unchanged.
- 2026-08-13: Router-hosted MCP now parses every `Accept` field value before
  JSON/SSE negotiation. Synthetic, raw native, and neutral installed-router
  consumer proofs create and delete a protected compatibility session from
  split JSON and SSE fields; split-field `q=0` regressions retain the existing
  exact-media-range precedence over wildcards.
- 2026-08-13: Focused router analysis, runtime/request-snapshot tests, native
  MCP integration tests, shell syntax, all 19 consumer-boundary contracts, the
  neutral installed-router consumer smoke, and full `bin/verify` pass. Full
  verification covers 114 Rust core tests, 52 FFI tests, 360 Dart core tests,
  all 101 MCP tests, the 280-case client/MCP matrix, 97 benchmark cases and 37
  live WAMP workloads, all 436 router tests, six isolated remote-auth
  integrations, 13 native follow-ups, every generated and globally activated
  consumer smoke, and Chrome/Dart2Wasm.
- 2026-08-13: Clean strict release-ready validation passes all seven
  synchronized `3.0.0-beta` package archives with zero warnings and no private
  workspace dependency blockers. The implementation is ready to publish;
  exact-head hosted workflows and the strict deployment-chain audit remain.
