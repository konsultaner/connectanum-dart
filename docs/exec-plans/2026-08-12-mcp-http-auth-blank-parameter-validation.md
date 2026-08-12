# MCP HTTP-Auth Blank Parameter Validation

Status: implementation and local verification green; publication pending

## Goal

Make the router-provided HTTP authentication endpoint reject explicitly
present blank string parameters from JSON bodies, query parameters, and
Connectanum headers before it allocates or consumes challenge state or mutates
a refresh/revocation lineage, while preserving omission and operation-specific
validation behavior.

## Context

The bridge now rejects non-string JSON values and conflicting non-empty
sources, but its selector helper trims and ignores blank strings. A blank
explicit value could therefore be treated as absent while another source
drove initial authentication, challenge completion, refresh rotation, or
revocation. In particular, a blank signature without an alternate credential
could consume and abort a pending challenge rather than fail before state
mutation.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the Serena
   and overlap preflight, inspect both roadmaps, and establish a green
   pre-change fast matrix.
2. Add a fail-first router lifecycle regression covering blank body, query,
   and header sources across initial authentication, challenge completion,
   refresh, and revoke operations with legitimate retry and lineage
   preservation.
3. Add presence-aware, operation-specific blank string validation with the
   existing generic, state/token-free HTTP 400 `invalid_auth_parameter`
   response before mutation.
4. Extend the neutral installed-router consumer with blank state rejection,
   pending-capacity retention, legitimate completion, and an explicit summary
   marker.
5. Run focused analysis/tests and full `bin/verify`, write durable Serena and
   project state, publish the implementation checkpoint, and audit the
   exact-head GitHub deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: The fail-first regression supplied a blank initial realm
  alongside a valid realm header. The router proceeded to an HTTP 401
  challenge instead of returning the required fail-closed HTTP 400 before
  authenticator state allocation.
- 2026-08-12: Operation-scoped validation now rejects explicitly blank body,
  query, and header sources for operation selectors, initial
  realm/method/identity, challenge signatures, refresh aliases, revocation
  aliases, and revocation hints. Omitted and irrelevant fields retain their
  existing behavior.
- 2026-08-12: Router analysis and the focused malformed-value, selector-source,
  refresh, and revoke regressions pass. Shell syntax and the isolated neutral
  installed-router consumer smoke pass; the smoke reports
  `authParameterBlankValidation: true`, proves blank state rejection preserves
  pending capacity, and completes the legitimate challenge before continuing
  through protected MCP, direct JSON, pub/sub, refresh/revoke, and Streamable
  HTTP paths.
- 2026-08-12: Full `bin/verify` passes with zero formatting changes, clean
  analysis, 114 Rust core tests, 52 Rust FFI tests, the 360-case Dart core
  suite, 101 MCP package tests, the complete 280-case client/MCP matrix, all 96
  benchmark cases and 36 live WAMP workloads, all 434 router tests, six
  isolated remote-auth integrations, 13 native follow-ups, every neutral
  consumer and installed-command smoke, and Chrome/Dart2Wasm coverage.
