# Exec Plan: Official SDK Named WAMP Meta Smoke

Status: complete; implementation and exact-head deployment evidence clean
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Prove that a neutral external agent using the pinned official MCP SDK can
discover and invoke router-provided WAMP Meta tools through their canonical
named JSON parameters, across public and bearer-protected legacy and modern
Router Image endpoints.

## Scope

- In scope:
  - Validate the advertised `wamp.registration.lookup` named-input schema,
    including `procedure`, optional `match`, and the lossless WAMP result
    envelope.
  - Invoke that tool through the official SDK with canonical
    `procedure`/`match` arguments and require a resolved registration id.
  - Run the proof on public/protected and compatibility/modern endpoints.
  - Add bounded, secret-safe Router Image evidence and source-contract tests.
- Out of scope:
  - Changing WAMP Meta behavior, authorization, or visibility.
  - Replacing the existing Dart package and direct JSON coverage for all 15
    standard Meta procedures.
  - Adding a new MCP SDK dependency to a published Dart package.

## Files Expected To Change

- `tool/smoke_official_mcp_client.mjs`
- `bin/router-image-mcp-smoke`
- `tool/test_router_image_mcp_smoke.py`
- `docs/project_state.md` and this plan.

## Preconditions

- The named WAMP Meta implementation and exact-head deployment chain are green
  at implementation base `0b126848`.
- The Router Image smoke already pins `@modelcontextprotocol/client@2.0.0` and
  exposes the standard Meta API on every route under test.

## Plan

1. Add a fail-first source contract for schema validation, canonical named
   inputs, structured result validation, and bounded shell evidence.
2. Extend the official SDK smoke with one registration lookup per endpoint and
   validate the advertised schema before dispatch.
3. Run focused Python/JavaScript/shell checks, then the canonical fast and full
   verification gates.
4. Commit and push the implementation, then collect exact-head CI, package,
   Router Image, WAMP, and strict-audit evidence.

## Verification

- `python3 -m unittest tool.test_router_image_mcp_smoke`
- `node --check tool/smoke_official_mcp_client.mjs`
- `bash -n bin/router-image-mcp-smoke`
- `python3 tool/check_public_artifact_references.py`
- `git diff --check`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-14: The official SDK smoke already proves tools, resources, prompts,
  pub/sub, auth retry, and both protocol eras, but its only WAMP Meta call is
  the no-argument `wamp.session.count`. The smallest material agent-readiness
  gap is therefore a named lookup whose schema and result are validated by the
  external SDK itself.
- 2026-08-14: `wamp.registration.lookup` is the representative boundary because
  it exercises both a required canonical string and an optional constrained
  match policy, and resolves a real router-provided registration without
  requiring private application procedures.
- 2026-08-14: Exact-head Router Image evidence is mandatory for this slice
  because the implementation changes the packaged smoke boundary and the local
  Docker attempt did not progress past registry metadata resolution. Hosted run
  `31796333675` built and loaded the image, emitted `named_wamp_meta=true`, and
  completed its multi-architecture dry run.

## Handoff

- Pre-change `bin/test-fast` passes at base `0b126848` after the preceding
  strict deployment-chain audit completed successfully.
- The official SDK now validates the named lookup input and output schemas,
  calls `wamp.registration.lookup` with `procedure: wamp.session.count` and
  `match: exact`, and requires one positive registration id across all four
  Router Image endpoint modes. The shell emits only bounded boolean evidence.
- The source-contract test failed first on the absent named-Meta markers, then
  the focused 33-case Python suite, JavaScript syntax, shell syntax, public
  artifact reference check, and diff hygiene passed after implementation.
- Post-change `bin/test-fast` passes across package, benchmark, router, and all
  isolated and globally activated consumer smokes. A local Docker build was
  cancelled after registry metadata resolution produced no first build step;
  exact packaged runtime proof will come from the hosted Router Image dry run.
- Full `bin/verify` passes on the first attempt with formatting unchanged, 114
  Rust core tests, all 52 FFI tests, 364 Dart core tests, 111 MCP tests, the
  281-case client suite, 97 benchmark tests including the 37-workload live WAMP
  matrix, the 441-case router suite, 6 remote-auth tests, 13 native follow-ups,
  all consumer smokes, Chrome, and Dart2Wasm green.
- Commit `a50e9bc3` is published to both maintained `master` branches.
  Exact-head CI `31796325817` passes Fast Checks, Dart VM Coverage, and Full
  Verify and retains coverage artifact `9217890744`. Exact-head Router Image
  dry run `31796333675` passes the build, loaded-image official SDK smoke, and
  multi-architecture dry run; it retains preview artifact `9217509258` and
  Docker build records `9217522969` and `9217522593`.
- The comprehensive strict deployment-chain audit exits zero. It confirms the
  latest package dry run `31790478885`, native release dry run `31221315902`,
  and WAMP profile run `31790478963` remain clean and relevant because no
  sensitive inputs for those workflows changed. No RC tag was selected without
  release approval.
