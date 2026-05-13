## Goal

Expand the checked-in HTTP bearer-provider bench so it measures both existing
local JWT validation and a real OAuth introspection-backed protected-route
path, instead of covering only the static JWT smoke case.

## Scope

- add bench harness support for an OAuth introspection provider used by the
  shipped bench router config
- add a dedicated introspection-backed protected HTTP route to the bench config
- add or extend bench scenarios/tests so JWT and OAuth protected-route paths
  are both exercised across the supported HTTP transports
- refresh checked-in project state and roadmap/status docs when the milestone
  lands

## Non-goals

- redesigning the router's HTTP auth provider model
- changing the existing ticket-based auth bridge flow
- adding OIDC discovery or new token formats beyond the current provider types
- turning this slice into a full throughput matrix unless the existing bench
  harness already makes that trivial

## Verification

- `bin/test-fast`
- focused bench/auth provider tests
- focused scenario/config parsing checks as needed
- `bin/verify`

## Status

- completed

## Handoff

- `http_bearer_provider_smoke.toml` is now the dedicated provider-backed HTTP
  auth baseline for the bench. It covers both local JWT validation and local
  OAuth introspection-backed protected routes across HTTP/1.1, HTTP/2, and
  HTTP/3.
- `packages/connectanum_bench/tool/bench_main.dart` now starts a local OAuth
  introspection harness when the configured bench router settings reference
  `oauth` HTTP auth providers, so the shipped bench config stays self-contained
  in local and CI runs.
- There is no active exec plan now. The next session should choose the next
  unfinished milestone from `ROADMAP_NEXT.md`.
