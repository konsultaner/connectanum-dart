## Goal

Expand the checked-in HTTP auth bridge bench beyond the current ticket-only
flow so it also exercises `wampcra` and `scram` challenge/response login over
HTTP, then reuses the issued bearer tokens on protected and refresh flows.

## Scope

- extend the shipped bench router config so the HTTP auth bridge can negotiate
  `ticket`, `wampcra`, and `scram` for the secure bench realm
- teach the Rust bench orchestrator to complete HTTP auth challenges for
  `wampcra` and `scram` instead of hard-failing non-ticket auth methods
- add or extend focused tests and the shipped HTTP auth scenario so the new
  methods are covered across the supported HTTP transports
- refresh checked-in project state and roadmap/design docs when the milestone
  lands

## Non-goals

- redesigning the HTTP auth bridge protocol
- changing the existing bearer-provider (`jwt` / `oauth`) protected-route path
- implementing remote auth provider latency work in the same slice unless it
  becomes trivial after the challenge-method expansion

## Verification

- `bin/test-fast`
- focused bench/router auth tests
- focused scenario/config parsing checks as needed
- `bin/verify`

## Status

- completed

## Handoff

- Completed. The shipped bench router config now exposes `ticket`,
  `wampcra`, and `scram` on the secure bench realm's HTTP auth bridge path,
  the Rust HTTP bench orchestrator completes both challenge-response methods,
  `native/bench/scenarios/http_auth_smoke.toml` now covers login, refresh,
  and protected-route flows for all three methods across HTTP/1.1, HTTP/2,
  and HTTP/3, and focused router/native bench tests plus `bin/verify` all
  passed on Darwin arm64.
