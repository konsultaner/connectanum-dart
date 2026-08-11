# MCP HTTP-Auth Selector Source Isolation

Status: complete locally; publication and hosted verification pending

## Goal

Make the router-provided HTTP authentication endpoint reject distinct `state`
or `grant_type` values supplied through different request sources before it
consumes challenge state or performs token work, while accepting identical
duplicates.

## Context

The auth bridge previously chose the first non-empty selector from the JSON
body, query, and Connectanum header. A request could therefore present a valid
pending state in the body and a different state in the header; the router
silently ignored the header, consumed the challenge, and issued tokens. The
same precedence ambiguity could select refresh versus revocation when
`grant_type` sources disagreed.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the Serena
   and overlap preflight, and establish a green pre-change fast matrix.
2. Add a fail-first router regression for conflicting state and grant-type
   sources, state preservation, and identical duplicate acceptance.
3. Resolve distinct non-empty selector values before dispatch and return a
   state/token-free HTTP 400 with stable `conflicting_auth_selector` reason.
4. Extend the neutral installed-router consumer through conflicting-source
   rejection, pending-capacity retention, legitimate completion, and protected
   MCP paths.
5. Run focused analysis/tests and full `bin/verify`, write durable Serena and
   project state, publish the implementation checkpoint, and audit the
   exact-head GitHub deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes; local and both maintained
  `master` heads matched exact commit `8cbddf5f` with a clean hosted deployment
  chain.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: The fail-first regression sent a valid pending ticket state in
  the body and a different header state. The router ignored the header and
  returned HTTP 200 plus fresh access and refresh tokens instead of rejecting
  the ambiguous request without consuming state.
- 2026-08-12: The auth bridge now collects distinct non-empty `state` and
  `grant_type` values across body, query, and headers before dispatch. More
  than one value fails closed with `conflicting_auth_selector`; identical
  duplicate state values remain valid and the preserved challenge completes.
- 2026-08-12: Router analysis and all 16 auth-bridge runtime tests pass. Shell
  syntax and the isolated neutral installed-router consumer smoke pass; the
  smoke reports `authSelectorSourceIsolation: true`, proves the rejection is
  state/token-free and preserves pending capacity, then continues through
  protected MCP, direct JSON, pub/sub, refresh/revoke, and Streamable HTTP
  paths.
- 2026-08-12: Full `bin/verify` passes, including 433 router tests, all 6
  isolated remote-auth integrations, all 13 native follow-ups, and the
  Chrome/Dart2Wasm WebSocket check.
