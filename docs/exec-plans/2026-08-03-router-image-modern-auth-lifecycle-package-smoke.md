# Exec Plan: Router Image Modern Auth Lifecycle Package Smoke

## Status

Completed.

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
  `auth_lifecycle=true refreshed_grant_listener=true`.
- 2026-08-03: Commit `93ed142` was pushed to GitLab and GitHub. Exact-head CI
  `30823927110`, Dart Package Publish Dry Run `30823926183`, Router Image dry
  run `30825339516`, and WAMP Profile Benchmarks `30825346436` all passed. CI
  uploaded coverage artifact `8860503359`, Router Image uploaded preview
  artifact `8860601699`, and WAMP uploaded benchmark artifact `8860818718`.
- 2026-08-03: Fresh-image logs contain exactly four bounded package evidence
  lines. The protected modern line proves the globally activated client used a
  router-issued grant, remained sessionless, completed its original request
  listener, and completed `auth_lifecycle=true refreshed_grant_listener=true`.
  Both compatibility lines retain Streamable HTTP and session deletion. The
  comprehensive strict deployment-chain audit exited clean with every required
  gate ready. RC tagging remains approval-gated.
