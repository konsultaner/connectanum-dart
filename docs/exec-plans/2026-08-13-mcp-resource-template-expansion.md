# Exec Plan: MCP Resource-Template Expansion

Status: active
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Let a downstream Dart application turn an advertised MCP resource template
into a correctly escaped concrete URI without implementing URI-template
parsing itself, then prove that concrete URI can be read through the shipped
router-hosted client package.

## Scope

- In scope:
  - A shared public, bounded RFC 6570 Level 1 URI-template parser with strict
    variable-name validation, matching, and UTF-8 percent-encoded expansion.
  - Reuse of the shared parser by the MCP server resource registry so server
    matching and consumer expansion cannot drift.
  - Public router-hosted client options that select an advertised template,
    expand caller-supplied variables, and read the resulting URI through
    direct JSON and compatibility Streamable HTTP.
  - Focused core/server/CLI contracts and isolated Router Image package-client
    evidence for public and protected endpoints.
- Out of scope:
  - RFC 6570 operators or modifiers beyond Level 1 simple expressions.
  - Inferring template variables from application data.
  - Changing the router's already-complete template read/subscription
    authorization or ownership semantics.

## Files Expected To Change

- `packages/connectanum_core/lib/src/mcp/`
- `packages/connectanum_core/lib/connectanum_core.dart`
- `packages/connectanum_core/test/`
- `packages/connectanum_client/lib/mcp.dart`
- `packages/connectanum_mcp/lib/src/resources/resource.dart`
- `packages/connectanum_mcp/lib/src/cli/router_hosted_client.dart`
- `packages/connectanum_mcp/lib/connectanum_mcp.dart`
- `packages/connectanum_mcp/README.md`
- `packages/connectanum_mcp/test/resources_test.dart`
- `packages/connectanum_{core,client,mcp}/CHANGELOG.md`
- `bin/common.sh`
- `bin/router-image-mcp-smoke`
- `deploy/docker/router_mcp_smoke.yaml`
- `tool/test_router_image_mcp_smoke.py`
- `tool/test_mcp_consumer_package_boundary.py`
- `docs/project_state.md`

## Preconditions

- The readable-template and concrete-template subscription milestones remain
  green at implementation commit `3ab636ed`.
- Prior hosted-evidence edits in this plan's predecessor and project state are
  preserved and bundled with this implementation commit.
- No secrets or private downstream application assumptions are required.

## Plan

1. Run the pre-change fast gate and add fail-first parser/expansion and public
   package-client contracts.
2. Implement one shared template representation, replace the server-private
   parser with it, and wire advertised-template expansion into the public CLI.
3. Exercise direct JSON and compatibility Streamable reads from the isolated
   globally activated package client against public and protected Router Image
   endpoints.
4. Run focused checks, `bin/test-fast`, `bin/verify`, privacy/package checks,
   then publish and validate required exact-head hosted evidence.

## Verification

- `bin/test-fast`
- `dart test packages/connectanum_core/test/mcp_resource_uri_template_test.dart`
- `dart test packages/connectanum_mcp/test/resources_test.dart`
- `python3 -m unittest tool.test_router_image_mcp_smoke`
- `python3 -m unittest tool.test_mcp_consumer_package_boundary`
- `dart analyze packages/connectanum_core packages/connectanum_mcp`
- `bash -n bin/router-image-mcp-smoke`
- `bin/verify`

## Decision Log

- 2026-08-14: Chose consumer-side template expansion because router reads and
  subscriptions are complete, but public Dart consumers still receive raw
  template strings and otherwise must duplicate validation and escaping.
- 2026-08-14: Put the syntax utility in `connectanum_core` and reuse it from
  the MCP server and IO client surface to keep one matching/expansion contract
  without introducing a package cycle.
- 2026-08-14: Require the package client to paginate the advertised template
  catalog and expand the server-returned template value. The protected JSON-
  response fixture places the readable target on page two behind a metadata-
  only sentinel so hosted evidence cannot pass with a first-page assumption.

## Progress

- 2026-08-14: Pre-change and post-change `bin/test-fast` pass. Fail-first core,
  MCP, public CLI, and Router Image source contracts reproduced the missing
  consumer expansion path before implementation. Focused analysis, 27 Dart
  parser/server tests, 50 Python contracts, shell syntax, the public dry-run
  smoke, privacy, and diff checks pass.
- 2026-08-14: Full `bin/verify` passes with zero formatting changes. The matrix
  includes 114 Rust core, 52 Rust FFI, 364 Dart core, 108 MCP, 280 client/MCP,
  97 benchmark, 37 live WAMP workload, 441 router, six remote-auth, and 13
  native follow-up tests plus every maintained isolated consumer and Chrome
  Dart2Wasm smoke.
- 2026-08-14: The public-artifact privacy guard and diff check pass. A pre-
  commit strict package dry-run validates the first three unchanged packages
  with zero warnings, then stops on the expected dirty-worktree warning for
  the modified client changelog and export. From the clean implementation
  commit, `bin/dart-package-publish-dry-run --strict-release-ready` validates
  all seven synchronized `3.0.0-beta` archives with zero warnings, no private
  workspace dependency blockers, and every declared executable present.

## Handoff

- Implementation, local verification, and clean strict package validation are
  complete. Publication and exact-head hosted evidence remain.
