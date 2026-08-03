# Exec Plan: Router Image Modern Auth Lifecycle Package Smoke

## Status

Active.

## Goal

Make the globally activated public `connectanum_mcp` executable prove ticket
grant refresh and revocation through the protected Router Image MCP
`2026-07-28` endpoint without creating compatibility-era session or resume
state.

## Scope

- Let `--auth-lifecycle-smoke` run in modern stateless mode.
- Keep the lifecycle protocol-aware: a refreshed modern grant must complete a
  direct request and the configured request-scoped resource-listener lifecycle
  without creating session state, while compatibility mode retains
  initialize/notify/delete coverage.
- Revoke the refreshed access token and require a subsequent modern direct
  request to be rejected without changing client state.
- Revoke the rotated refresh token and require refresh rejection.
- Require the complete lifecycle in the protected modern Router Image package
  run and expose bounded hosted-log evidence.
- Preserve public execution, compatibility Streamable HTTP, and the existing
  protected compatibility authentication lifecycle.

## Non-Goals

- Automatically refresh or reconnect an already-open listener.
- Change router token lifetime, revocation, or authorization semantics.
- Add another MCP protocol extension or prescribe consumer credential storage.

## Verification

- Pre-change `bin/test-fast`.
- Focused source contracts that first fail on the stateless lifecycle
  prohibition and missing protected modern image invocation/evidence.
- Package analysis/tests and the complete real Router Image runner.
- Full `bin/verify` before handoff.
- Exact-head CI, package dry run, Router Image dry run, WAMP benchmarks, hosted
  log inspection, and the comprehensive strict deployment-chain audit after
  the implementation push.

## Progress

- 2026-08-03: Selected after the modern dynamic-resource listener package
  checkpoint completed with clean local and hosted evidence. The shipped
  executable still rejects auth lifecycle in stateless mode, leaving refresh
  and revocation proven only by the compatibility package run.
- 2026-08-03: Pre-change `bin/test-fast` passed. Focused package-boundary and
  Router Image contracts then failed on the stateless lifecycle rejection,
  missing protected modern invocation, and absent refreshed-grant evidence.
- 2026-08-03: The executable now selects the stateless authenticated client for
  modern lifecycle checks, proves direct JSON and the configured
  request-scoped resource listener with the rotated grant, preserves absent
  session/resume state, and rejects both revoked access and refresh tokens.
  Compatibility mode retains initialize/notify/delete coverage.
- 2026-08-03: Package analysis, all 19 package-boundary contracts, all 17
  Router Image contracts, the complete isolated real-image runner, and full
  `bin/verify` pass. The protected modern bounded evidence records
  `auth_lifecycle=true refreshed_grant_listener=true`; hosted exact-head
  evidence remains.
