# Exec Plan: MCP Route-Security Resources And Prompts

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Prove that router-hosted MCP resources, resource templates, and prompts follow
the same route/session/auth behavior as WAMP-backed tools and direct JSON
metadata calls.

## Scope

In scope:

- Extend the existing public/secure router-hosted MCP integration smoke with
  configured resources, resource templates, and prompts.
- Cover lifecycle-free direct JSON resource/prompt calls on the public route.
- Cover initialized Streamable MCP resource/prompt calls on the public route.
- Cover direct JSON batch calls that mix WAMP metadata, tool calls, resources,
  prompts, and notifications.
- Cover protected-route denial for unauthenticated direct JSON resources and
  authenticated direct JSON access with a bearer token.

Out of scope:

- Changing runtime MCP semantics without a failing regression.
- Adding a standalone MCP server process.
- Adding dynamic application-data projection.

## Files Expected To Change

- `packages/connectanum_router/test/router_integration_native_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-route-security-resources-prompts.md`

## Plan

1. Add configured MCP resources, resource templates, and prompts to the existing
   public/secure route-security smoke settings.
2. Assert public direct JSON and Streamable MCP resource/prompt access.
3. Assert direct JSON batch handles resource and prompt methods alongside WAMP
   metadata/tool methods.
4. Assert protected direct JSON resource calls require route authentication and
   succeed with bearer-authenticated route identity.
5. Run focused router analysis/test, then full verification.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`
  and `dart analyze packages/connectanum_router`.
- Full local `bin/verify` passed on 2026-05-04.
- Commit `227fbf3` was pushed to both remotes. Hosted GitHub evidence for
  `227fbf3` is clean: `CI` run `25313970259` completed successfully with
  `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
  `25313970231` completed successfully, and `WAMP Profile Benchmarks` run
  `25313970226` completed successfully. The hosted log scan found no
  actionable warnings, deprecations, skipped-test lines, panics, failures,
  connection reset/refused noise, or broken pipes; matches were limited to Git
  checkout's default-branch hint, package dry-run `0 warnings` summaries,
  normal Rust `0 ignored` / filtered-test summaries, and passing test names.

## Decision Log

- 2026-05-04: Keep this as regression coverage because the implementation
  already routes direct JSON and Streamable MCP requests through the route
  session. The missing proof was that configured resources/prompts obey the
  same public/secure route contract.

## Handoff

Implementation, local verification, and hosted GitHub deployment-chain evidence
are complete.
