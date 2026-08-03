# Exec Plan: Router Image Modern Resource Listener Package Smoke

## Status

Active.

## Goal

Make the globally activated public `connectanum_mcp` executable prove a
request-scoped MCP `2026-07-28` dynamic-resource update lifecycle against the
fresh Router Image without creating compatibility-era session or resume state.

## Scope

- Let stateless `router_hosted_client` runs accept a resource update topic.
- Open a filtered `subscriptions/listen` stream for the selected resource,
  validate the exact acknowledgment, publish an acknowledged update through
  direct JSON, validate the correlated resource notification, reread the
  resource, and close the listener locally.
- Assert that the complete lifecycle leaves both MCP session ID and resume
  cursor absent for public and bearer-protected clients.
- Add a neutral procedure-backed dynamic resource to both Router Image smoke
  endpoints and require the lifecycle in the two modern package-client runs.
- Keep compatibility-era Streamable HTTP and all existing direct JSON, WAMP
  Meta API, pub/sub, authentication, and package-boundary evidence intact.

## Non-Goals

- Add a new MCP protocol extension or change router listener semantics.
- Replace the compatibility-era resource subscription lifecycle.
- Publish or retag a Router Image.

## Verification

- Pre-change `bin/test-fast`.
- A focused source contract that fails against the previous stateless option
  rejection and missing Router Image dynamic-resource invocation.
- Package analysis/tests, focused package-boundary and Router Image contracts,
  and a real local native-router or exact-image lifecycle.
- Full `bin/verify` before handoff.
- Exact-head CI, package dry run, Router Image dry run, WAMP benchmarks, hosted
  log inspection, and the comprehensive strict deployment-chain audit after
  the implementation push.

## Progress

- 2026-08-03: Selected after the isolated global package-client Router Image
  checkpoint completed with clean local and hosted evidence. The public client
  already exposes request-scoped listeners, but its shipped executable rejects
  resource update options in modern stateless mode and the fresh-image package
  runs therefore do not exercise that current-protocol lifecycle.
- 2026-08-03: Pre-change `bin/test-fast` passed. The focused package and Router
  Image contracts then failed on the old stateless option rejection, absent
  listener helper and lifecycle markers, and missing dynamic-resource image
  configuration.
- 2026-08-03: The executable now maps resource update options to a filtered
  request-scoped listener in modern mode while retaining the compatibility-era
  Streamable subscription. It validates the acknowledgment, publishes the
  update through direct JSON, receives the filtered notification, rereads,
  closes locally, and proves no session or resume state was created.
- 2026-08-03: The 17 Router Image and 19 package-boundary contracts pass,
  `connectanum_mcp` is analyzer-clean, all 113 focused client MCP tests
  pass, and the complete image runner passes against a local packaged router.
  Its public and protected modern lines both record `request_listener=true`;
  compatibility Streamable and protected auth-lifecycle evidence remain green.
- 2026-08-03: Full `bin/verify` passes, including the isolated globally
  activated MCP client, consumer-package and router CLI smokes, all 36 live
  WAMP integration scenarios, 380 router tests, and Chrome/Wasm coverage.
