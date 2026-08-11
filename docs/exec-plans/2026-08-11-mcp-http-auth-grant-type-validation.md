# MCP HTTP-Auth Grant-Type Validation

Status: complete locally; publication and hosted verification pending

## Goal

Make the router-provided HTTP authentication endpoint reject unsupported token
operation grant types before it allocates authenticator, challenge, session, or
grant state, so malformed consumer requests cannot enter a different auth flow.

## Context

The auth bridge reserves `grant_type=refresh_token` for refresh and
`grant_type=revoke` for revocation while requests without `grant_type` start or
continue the configured challenge flow. The dispatch switch previously had no
default branch, so any other non-empty value fell through to fresh
authentication. A payload carrying an unsupported grant plus valid realm,
method, and identity fields therefore returned a challenge instead of failing
closed.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run the
   pre-change fast regression matrix from a dedicated feature branch.
2. Add a fail-first router regression that combines an unsupported grant type
   with otherwise valid ticket-authentication fields.
3. Reject unsupported non-empty grant types with a state-free HTTP 400 and the
   stable `unsupported_grant_type` reason before authenticator dispatch.
4. Run focused auth-bridge regression coverage, formatting and analysis,
   followed by full `bin/verify`.
5. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes; local and both maintained
  `master` heads matched exact commit `6a1afc94` with a clean hosted deployment
  chain.
- 2026-08-11: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-11: Symbol-aware inspection found that the auth bridge dispatches the
  supported refresh and revoke aliases but has no default rejection. The
  fail-first router regression supplied `grant_type=password` with a valid
  ticket identity and received HTTP 401 challenge instead of the expected
  state-free HTTP 400.
- 2026-08-11: The grant dispatch now rejects unsupported non-empty values with
  `unsupported_grant_type`; the focused fail-first regression passes.
- 2026-08-11: Router analysis and all 14 auth-bridge runtime tests pass,
  preserving ticket, CRA, SCRAM, capacity, lockout, refresh concurrency,
  rotation, and revocation behavior. Shell syntax and the isolated neutral
  installed-router consumer smoke pass; the smoke reports
  `authGrantTypeValidation: true`, proves the rejection is state/token-free,
  and then continues through protected MCP, direct JSON, pub/sub,
  refresh/revoke, and Streamable HTTP paths.
- 2026-08-11: Full `bin/verify` passes, including 431 router tests, all 6
  isolated remote-auth integrations, all 13 native follow-ups, and the
  Chrome/Dart2Wasm WebSocket check.
