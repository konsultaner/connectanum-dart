# Exec Plan: Router-Hosted MCP Auth and Meta API

Status: active
Owner: Codex
Created: 2026-05-03
Last updated: 2026-05-03

## Goal

Make MCP a router-hosted endpoint and protocol view over the same authenticated
WAMP/meta API surface that application clients can call directly. MCP tool,
publish, subscribe, and meta calls must execute as the authenticated route
principal or session, never as an accidentally privileged internal service
session.

## Scope

In scope:

- Correct the current MCP routing model so endpoint configuration on the router
  enables MCP; a separate MCP-only server process is not the intended product
  path.
- Add fail-first router integration coverage proving MCP calls run under the
  route-authenticated authid/authrole/session rights and are denied when that
  principal cannot call, publish, or subscribe.
- Add or align a JSON-callable meta/tool API surface for frontend clients, using
  the same catalog and authorization checks that MCP exposes to agents.
- Treat WAMP registration/subscription/session meta API data plus `_ai_meta_data`
  as the source of truth for tool discovery and descriptions.
- Keep package-local MCP protocol primitives only where they help implement or
  test the router endpoint.

Out of scope:

- Do not create or promote a standalone MCP server as the product deployment
  shape.
- Do not copy Java annotation mechanics; Dart should use explicit route,
  registration details, and config metadata instead.
- Do not treat `allowCall`, `safe`, or `danger` metadata as authorization. They
  are catalog/presentation hints; the router authorizer remains authoritative.
- Do not add downstream application names or private project references to
  public docs.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_internal_session.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `packages/connectanum_mcp/lib/src/tools/wamp_api.dart`
- `packages/connectanum_mcp/test/`
- `docs/project_state.md`
- Public MCP/router docs only after behavior is corrected

## Preconditions

- Preserve the clean hosted checkpoint at `8df2224` unless a newer verified
  checkpoint replaces it.
- Before behavior changes, run `bin/test-fast`.
- Keep CI clean. If local `bin/verify` or hosted GitHub Actions turns red, fix
  that before adding more MCP features.
- Existing route auth, session profile, and WAMP authorizer semantics are the
  compatibility boundary; MCP must adapt to them rather than bypass them.

## Plan

1. Record the design correction and reproduce the flaw.
   Add a focused router integration test where an MCP route has public and
   authenticated access, a registered procedure/topic requires a specific
   authrole, the public/anonymous MCP caller is denied, and the authenticated
   caller succeeds with the expected authid/authrole visible to authorization or
   callee metadata.

2. Define the router MCP request context.
   Introduce an explicit context for MCP/JSON bridge calls containing realm,
   authid, authrole, authmethod/authprovider, route binding, security mode, and
   optional backing session. Endpoint caches must be keyed by the effective
   principal and route, not by a privileged reusable internal session.

3. Implement call-as-principal dispatch.
   Route MCP tool calls, WAMP meta calls, publish, subscribe, poll, and
   unsubscribe operations through router-side helpers that perform the same
   authorization checks as normal WAMP traffic. Use a real authenticated session
   when one exists; otherwise use a deliberately scoped virtual route session
   with the authenticated principal, not an elevated service identity.

4. Expose one shared catalog to MCP and JSON clients.
   Build the callable/publish/subscribe catalog from the router's WAMP
   registration, subscription, and session meta data, including `_ai_meta_data`.
   MCP `tools/list`, `tools/call`, and the JSON frontend API should use this
   same filtered catalog so an agent and a frontend see the same permitted
   surface after login.

5. Align metadata and safety fields.
   Preserve existing icon, prompt, resource, and tool-result protocol support,
   but extend API metadata only where it improves the shared catalog:
   JSON-schema input/output, `danger`, `safe`, domain/entity/tags/verbs, event
   publication metadata, and hidden/default input argument hints. Keep this
   metadata declarative and registration/config based.

6. Add integration and smoke coverage.
   Cover router-hosted MCP RPC, meta API discovery, pub/sub, safe/unsafe
   visibility, denied calls, authenticated calls, and JSON-callable frontend
   access. Add a smoke path that can be exercised by an MCP client after route
   login, without requiring a standalone MCP-only server.

7. Update docs and handoff state.
   Reframe public docs so router endpoint configuration is the primary MCP
   story. Any package-local stdio/example server should be documented only as a
   development/protocol example or removed from public product-facing docs.

## Progress

- 2026-05-03: Completed the first MCP auth/session isolation slice. Added a
  fail-first router integration test proving an anonymous MCP route must not
  reuse a privileged realm internal session, then fixed unauthenticated MCP
  routes to use route-scoped anonymous session cache keys.
- 2026-05-03: Keyed internal sessions created through `_ensureInternalSession`
  no longer replace the realm-global internal session index. This prevents HTTP
  bearer/profile/route sessions from becoming the implicit realm service
  session for later anonymous route calls.
- 2026-05-03: Full local `bin/verify` passed after the MCP route session
  isolation fix and docs updates.
- 2026-05-03: Added the shared router-hosted direct JSON-RPC facade on the
  existing `type: mcp` route. Frontend clients can call
  `connectanum.tools.list`, `connectanum.tool.call`, and dotted MCP tool names
  such as `connectanum.api.list`, `connectanum.pubsub.publish`, or an
  application procedure directly without creating a separate MCP server or
  running the MCP lifecycle first. These direct calls use the same refreshed
  tool registry and route-authenticated session as MCP `tools/list` and
  `tools/call`.
- 2026-05-03: Extended the router MCP smoke test to cover anonymous direct API
  metadata, anonymous safe direct calls, anonymous unsafe denial, and
  bearer-authenticated unsafe direct calls. Focused
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security"`
  and `dart analyze packages/connectanum_router` passed.
- 2026-05-03: Full local `bin/verify` passed after the MCP direct-JSON route
  endpoint, smoke coverage, and docs updates.
- 2026-05-03: Remaining work in this plan is stronger catalog filtering by
  effective principal and final public docs cleanup once behavior is complete.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded`
- `dart analyze packages/connectanum_router packages/connectanum_mcp`
- `dart test packages/connectanum_mcp -r expanded`
- `git diff --check`
- `bin/verify`
- Hosted GitHub Actions and deployment-chain audit before considering the slice
  complete

## Decision Log

- 2026-05-03: User identified that the current MCP implementation can expose
  tools without a correct right/session system. The next work must prioritize
  call-as-principal semantics and a router-hosted endpoint over further MCP
  protocol polish.
- 2026-05-03: Prior router implementation research showed the desired shape:
  AI/tool metadata belongs on the WAMP registration/subscription meta API, and
  HTTP-to-WAMP bridge calls must authorize first and dispatch as the caller's
  session/principal.
- 2026-05-03: Product direction is router-owned MCP. A standalone MCP server is
  not the desired deployment architecture.
- 2026-05-03: Default/no-profile MCP routes were the first concrete flaw:
  because realm-global internal sessions were reused, a previously created
  privileged service session could become the MCP caller. The fix is to make
  unauthenticated MCP sessions route-scoped and non-global.

## Handoff

Next automation run should continue with stronger principal-filtered catalog
behavior. Keep the MCP anonymous isolation test and the MCP direct-JSON smoke
path in the focused verification set.
