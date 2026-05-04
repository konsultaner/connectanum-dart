# Exec Plan: Router-Hosted MCP Secure Example

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the runnable router-hosted MCP example prove the secure consumer path, not
only the public anonymous path.

## Scope

In scope:

- Keep MCP hosted by router `type: mcp` routes.
- Add a bearer-protected MCP route to the existing runnable example.
- Add a local HTTP ticket-auth route used only by the example smoke path.
- Make `--smoke-and-exit` prove unauthenticated denial on the secure route.
- Make `--smoke-and-exit` then issue a bearer token and prove authenticated
  direct JSON plus Streamable MCP access on the secure route.

Out of scope:

- New MCP runtime semantics.
- A standalone MCP server process.
- Private downstream application references.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-router-hosted-mcp-secure-example.md`

## Plan

1. Extend the example router settings with `/auth` and `/mcp/secure`.
2. Add an example ticket authenticator and member role with the same WAMP
   permissions needed by the MCP smoke.
3. Update the example smoke to run against both public and secure endpoints.
4. Run focused analyzer/example checks, then full verification.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_router` and
  `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`.
- Full local `bin/verify` passed on 2026-05-04.
- Commit `af56f1c` was pushed to both remotes. Hosted GitHub evidence for
  `af56f1c` is clean: `CI` run `25315729357` completed successfully with
  `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
  `25315729371` completed successfully, and `WAMP Profile Benchmarks` run
  `25315729373` completed successfully. The hosted log scan found no
  actionable warnings, deprecations, skipped-test lines, panics, failures,
  connection reset/refused noise, or broken pipes; matches were limited to Git
  checkout's default-branch hint, package dry-run `0 warnings` summaries,
  normal Rust `0 ignored` / filtered-test summaries, and passing test names.

## Decision Log

- 2026-05-04: Use the existing router HTTP auth route and ticket
  authenticator instead of hard-coding an authorization header. This keeps the
  example aligned with the real router-hosted MCP route-auth contract.

## Handoff

Implementation, local verification, and hosted GitHub deployment-chain evidence
are complete.
