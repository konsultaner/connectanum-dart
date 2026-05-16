# Exec Plan: HTTP Handler Native Integration

## Status

Complete locally on 2026-05-16.

## Goal

Close the remaining production-readiness gap for HTTP `handler` route actions:
prove a real native HTTP request crosses the native route table and dispatches
to a router-registered Dart handler, and prove missing handler registrations
fail explicitly without falling through to WAMP.

## Scope

- Extend the native router integration harness so tests can pass
  `httpRouteHandlers` into `Router.start`.
- Add native runtime coverage for a configured `handler` route that receives a
  JSON request body and returns a structured JSON response.
- Add native runtime coverage for an unregistered configured `handler` route
  returning structured `501 handler_not_registered`.
- Bundle existing hosted-evidence docs from the previous handler implementation
  with this code/test change.

## Out Of Scope

- New handler API shapes or callback helper permutations.
- More MCP helper work unless a consumer integration exposes a correctness bug.
- Release branch promotion or RC tagging, which still require operator/reviewer
  action.

## Verification

- Pre-edit `bin/test-fast` passed.
- Focused native integration tests passed:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "configured HTTP handler routes through native runtime" -r expanded`.
- Full local `bin/verify` passed before handoff.
- Hosted CI/package/audit evidence is pending until this implementation bundle
  is pushed.
