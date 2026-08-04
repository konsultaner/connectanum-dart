# Exec Plan: MCP Streamable Catalog-Refresh Lease

## Status

Active.

## Goal

Keep a compatibility-era Streamable HTTP endpoint alive while a valid POST
request refreshes its router-provided tool catalog, without allowing rejected
parameter metadata to reset the session idle deadline.

## Scope

- Protect asynchronous realm-snapshot and authorization work performed by
  `_refreshTools()` before request dispatch.
- Preserve the original idle deadline when catalog-dependent parameter-header
  validation rejects the request.
- Begin a fresh idle interval only after an accepted request completes.
- Keep modern stateless, direct JSON, disabled-timeout, explicit DELETE, and
  disposal behavior unchanged.
- Prove the behavior through focused synthetic and native public-client
  regressions.

## Non-Goals

- Change route-configured idle timeout values.
- Cache or weaken authorization-sensitive tool catalog refreshes.
- Add new MCP protocol extensions.
- Cancel application-owned WAMP invocations when an HTTP caller disconnects.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first near-deadline request regression that delays catalog refresh.
- Focused accepted-request and rejected-parameter-metadata deadline tests.
- Dart formatting and targeted router analysis.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after the counted in-flight request lease landed.
  Compatibility POST handling currently awaits `_refreshTools()` before it
  acquires that lease. Realm snapshot and authorization work can therefore
  expire and dispose an endpoint while a valid near-deadline request is already
  refreshing its router-provided catalog.
- 2026-08-04: Pre-change `bin/test-fast` passed. A native public-client
  regression now blocks catalog authorization beyond the configured idle
  timeout. The initialize response returns without a session identifier after
  the endpoint expires during refresh, reproducing disposal of valid work
  before request dispatch.
- 2026-08-04: Compatibility POST handling now acquires a counted request hold
  before catalog refresh. Accepted activity resets the deadline only after all
  overlapping holds complete; catalog-dependent rejection rearms the remaining
  original interval and expires immediately when that interval has elapsed.
  The fail-first native regression, the existing overlapping slow-tool
  regression, the rejected parameter-metadata deadline regression, all 76
  synthetic runtime cases, formatting, and targeted router analysis pass.
- 2026-08-04: Full `bin/verify` passed formatting, Rust and Dart analysis and
  tests, native FFI coverage, all 384 core tests, all 94 MCP tests, all 96
  benchmark tests, browser coverage, router/native follow-ups, and the
  isolated and globally activated consumer-package smokes. Exact-head hosted
  workflows and the strict deployment-chain audit remain before completion.
