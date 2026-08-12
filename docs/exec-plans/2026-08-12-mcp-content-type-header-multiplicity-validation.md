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
