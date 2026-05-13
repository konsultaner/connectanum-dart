# Exec Plan: Router-Hosted MCP Example Resources And Prompts

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the runnable router-hosted MCP example demonstrate the full configured
endpoint surface that consumer applications need: WAMP-backed tools, direct
JSON calls, configured resources, resource templates, and prompts.

## Scope

In scope:

- Configure a static resource, resource template, and prompt on the example
  `type: mcp` route.
- Extend `--smoke-and-exit` to prove lifecycle-free direct JSON resource and
  prompt access.
- Extend the same smoke to prove normal Streamable MCP resource-template and
  prompt access after initialization.

Out of scope:

- Adding a second standalone MCP server process.
- Introducing dynamic application-data projection.
- Changing router-hosted MCP runtime behavior beyond example coverage.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-router-hosted-mcp-example-resources-prompts.md`

## Plan

1. Add resource, resource-template, and prompt route options to the example.
2. Smoke direct JSON `resources/list`, `resources/read`, and `prompts/get`
   through the typed client helpers.
3. Smoke Streamable MCP `resources/templates/list` and `prompts/get` after
   `initialize` / `notifications/initialized`.
4. Run focused analysis and the example smoke, then full local verification.
5. Commit, push, and inspect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change full local `bin/verify` passed on 2026-05-04 before this example
  follow-up.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_router` and
  `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`.
- Full local `bin/verify` passed on 2026-05-04 after the example follow-up.
- Commit `42a600d` was pushed to both remotes. Hosted GitHub evidence for
  `42a600d` is clean: `CI` run `25312011623` completed successfully with
  `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
  `25312011638` completed successfully, and `WAMP Profile Benchmarks` run
  `25312011620` completed successfully. The hosted log scan found no
  actionable warnings, deprecations, skipped-test lines, panics, failures,
  connection reset/refused noise, or broken pipes; matches were limited to Git
  checkout's default-branch hint, package dry-run `0 warnings` summaries,
  normal Rust `0 ignored` / filtered-test summaries, and passing test names.

## Decision Log

- 2026-05-04: Keep this as a runnable example hardening slice rather than a
  docs-only explanation. Consumer applications get stronger evidence when the
  example fails fast if configured resource or prompt access regresses.

## Handoff

Implementation, local verification, and hosted GitHub deployment-chain evidence
are complete.
