# Exec Plan: MCP Streamable Session Idle Expiry

## Status

Active.

## Goal

Bound abandoned router-hosted compatibility-session state so a consumer that
does not send Streamable HTTP `DELETE` cannot retain MCP endpoint resources and
subscriptions indefinitely. Expired session identifiers must receive the
spec-required `404`, while a fresh initialization must create a distinct usable
session.

## Scope

- Add a validated MCP route option for Streamable HTTP session idle timeout,
  with a production-safe default and an explicit disabled value.
- Track activity only for protocol-session-backed MCP endpoints; modern
  stateless and direct JSON requests remain sessionless.
- Remove and dispose idle endpoint state before serving later MCP traffic.
- Return `404` for an expired session identifier and permit immediate creation
  of a replacement session.
- Cover snake_case and camelCase configuration, stale-session behavior,
  replacement-session behavior, and the maintained public client recovery
  contract.

## Non-Goals

- Reintroduce protocol sessions into the modern `2026-07-28` transport.
- Add durable cross-process session storage or resume state.
- Change bearer-token, OAuth discovery, or router-issued grant semantics.
- Add another Router Image endpoint or duplicate existing package-client
  protocol matrices.

## Verification

- Pre-change `bin/test-fast`.
- Focused fail-first router option and Streamable HTTP lifecycle regressions.
- Dart formatting/analyzer checks and the focused router/client tests.
- Full `bin/verify` before handoff.
- Exact-head CI and relevant hosted workflow evidence plus the comprehensive
  strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-04: Selected after the canonical Router Image and globally activated
  package client completed public/protected, compatibility/stateless, JSON/SSE,
  direct JSON/meta/pub-sub, resource-update, and auth lifecycle coverage. The
  remaining concrete session-correctness gap is server-side cleanup when a
  compatibility client disappears without sending `DELETE`; the maintained
  Streamable HTTP contract permits server termination and requires stale
  session identifiers to return `404` so the client can initialize again.
- 2026-08-04: Pre-change `bin/test-fast` passed the consumer smokes, 360 core
  tests, 94 MCP tests, 193 MCP/client cases, native/client/auth suites, all 96
  benchmark tests with 36 live real-router WAMP workloads, CLI/package smokes,
  Router Image contracts, and browser/Wasm coverage.
- 2026-08-04: Fail-first option validation rejected neither negative timeout
  alias, and the focused runtime regression received `200` from an idle
  session where `404` was required. The implementation now validates both
  aliases, defaults compatibility sessions to 600000 milliseconds, treats `0`
  as disabled, lazily removes expired endpoints before later MCP traffic, and
  disposes their subscriptions without adding state to modern or direct JSON
  requests.
- 2026-08-04: Formatting and targeted analysis pass. Focused configuration,
  synthetic runtime, and native public-client regressions pass, including
  client state clearing on `404`, replacement initialization, and WAMP
  subscriber-count cleanup after expiry.
- 2026-08-04: Full `bin/verify` passes all native and Rust suites, 360 core
  tests, 94 MCP tests, 193 MCP/client cases, all 96 benchmark tests with 36
  live real-router WAMP workloads, every isolated and globally activated
  consumer and CLI smoke, the complete 382-case router suite, 13
  native-forwarding follow-ups, and Chrome/Dart2Wasm coverage. Exact-head
  hosted evidence and the strict deployment-chain audit remain pending.
