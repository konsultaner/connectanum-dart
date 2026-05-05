# Exec Plan: MCP External Authorization Context

Status: completed
Owner: Codex
Created: 2026-05-05
Last updated: 2026-05-05

## Goal

Ensure router-hosted MCP and authenticated HTTP bridge calls execute with the
effective external caller authorization context instead of privileged router
service semantics.

## Scope

In scope:

- Carry an explicit internal-versus-external authorization flag through router
  internal sessions.
- Use external authorization for router-hosted MCP anonymous route sessions and
  HTTP-auth bridge bearer sessions.
- Re-check MCP WAMP call, publish, and subscribe authorization at dispatch time.
- Preserve existing configured HTTP RPC bridge behavior for service routes that
  intentionally expose router-owned procedures.
- Strengthen the no-session-profile MCP regression test so a privileged realm
  service session cannot be reused by anonymous MCP requests.

Out of scope:

- Standalone MCP server deployment changes.
- Public documentation refresh beyond durable project state.
- New MCP protocol features unrelated to caller authorization.

## Plan

1. Reproduce the flaw with focused MCP route coverage.
2. Thread `authorizationIsInternal` through router internal session bootstrap and
   worker-isolate authorization requests.
3. Make MCP anonymous route sessions and bearer-authenticated bridge sessions
   external authorization contexts.
4. Re-check MCP call, publish, and subscribe rights immediately before dispatch.
5. Run focused MCP isolation, OpenMetrics compatibility, `bin/test-fast`, and
   full `bin/verify`.

## Progress

- 2026-05-05: Added the explicit authorization-context flag to router internal
  sessions and the internal-session isolate authorization request.
- 2026-05-05: Updated router-hosted MCP and HTTP-auth bridge session creation so
  MCP/public and bearer-authenticated bridge calls authorize as external
  principals. Anonymous MCP route sessions remain route-scoped and no longer
  fall back to realm-global privileged service sessions.
- 2026-05-05: Added dispatch-time MCP call, publish, and subscribe authorization
  checks.
- 2026-05-05: Kept generic configured HTTP RPC bridge routes compatible with
  existing service-route behavior after the OpenMetrics focused regression
  caught an over-broad externalization.
- 2026-05-05: Completed local verification.

## Verification

- `dart test test/router_integration_native_test.dart -n "serves OpenMetrics payload over HTTP metrics route" -r expanded --chain-stack-traces`
- `dart test test/router_integration_native_test.dart -n "does not run anonymous MCP calls as a privileged realm session" -r expanded --chain-stack-traces`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-05-05: MCP and authenticated HTTP bridge calls need external caller
  authorization semantics. Generic configured HTTP RPC routes may still act as
  router service bridges unless protected or scoped by route/session-profile
  configuration, because existing service routes such as OpenMetrics depend on
  that behavior.

## Handoff

Complete locally. Push and hosted GitHub evidence are pending.
