# MCP HTTP-Auth Header Multiplicity Validation

Status: implementation complete; local verification green; publication pending

## Goal

Make the router-provided HTTP authentication endpoint retain case-insensitive
request-header multiplicity and reject repeated operation-relevant selector or
credential headers before allocating or consuming challenge state or mutating
token lineage, while preserving operation-specific handling of unrelated
headers.

## Context

The native HTTP parsers retain every request-header entry and the FFI exposes
each entry to Dart. The Dart native-handshake decoder currently stores those
entries in a scalar map, so repeated same-name headers are overwritten and
case-variant names can leave `_headerValue` choosing the first entry. That
makes security-sensitive HTTP-auth interpretation depend on transport and map
collapse behavior even though repeated relevant JSON and query fields already
fail closed.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the required
   workflow, Serena, overlap, completed-plan, and both-roadmap preflights, and
   establish a green pre-change fast matrix.
2. Add fail-first native-boundary and router lifecycle coverage for repeated
   operation-relevant HTTP-auth headers, including case variants, pending
   capacity, legitimate retry, token-lineage isolation, and irrelevant-header
   operation scoping.
3. Retain normalized duplicate-header-name evidence through native handshakes
   and router requests, then apply it to the existing operation-specific
   generic HTTP 400 validation before authenticator or token mutation.
4. Extend the neutral installed-router consumer smoke with repeated auth-header
   rejection, retained pending state, valid completion, and an explicit
   evidence marker.
5. Run focused and full verification, write durable Serena/project state,
   publish the implementation checkpoint, and audit the exact-head GitHub
   deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes are the preceding
  checkpoint's expected hosted-evidence notes; the scheduled runlock belongs
  to a live process and no unrelated same-repository Codex process exists.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: A fail-first router lifecycle regression expected generic HTTP
  400 for case-variant repeated realm headers but observed HTTP 401, proving
  that scalar header lookup still selected one value. `NativeHttpHandshake`
  now retains an immutable lowercase duplicate-name set across both HTTP
  handshake paths, `_RouterBoss` carries it into `RouterHttpRequest`, and the
  existing operation-specific HTTP-auth string-source validation rejects only
  relevant repeated headers before state or token mutation.
- 2026-08-12: Focused router lifecycle, full router runtime, native HTTP
  boundary, native request-body, router analysis, shell syntax, and diff checks
  pass. The installed neutral router consumer smoke sends a genuinely repeated
  auth-state header, observes generic token-free HTTP 400, proves the pending
  challenge remains allocated, completes authentication normally, and reports
  `authHeaderMultiplicityValidation: true`.
- 2026-08-12: Post-change `bin/verify` passes the complete matrix at 436 router
  tests, 360 core tests, 101 MCP tests, 280 client/MCP tests, all 96 benchmark
  cases and 36 live WAMP workloads, six remote-auth integrations, all neutral
  and installed consumers, native follow-ups, and Chrome/Dart2Wasm. Publication
  and exact-head hosted evidence remain.
