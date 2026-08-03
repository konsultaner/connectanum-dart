# Exec Plan: Isolated Router Image Package Client Smoke

## Status

Active.

## Goal

Make the canonical Router Image dry run prove that a globally activated public
`connectanum_mcp` executable can use the freshly built router image without
running the client from the repository workspace.

## Scope

- Stage the public `connectanum_core`, `connectanum_client`, and
  `connectanum_mcp` package graph in a temporary workspace.
- Activate `router_hosted_client` into an isolated pub cache and verify that
  the resolved executable comes from that cache.
- Use that executable for all public/protected and modern/compatibility Router
  Image MCP runs.
- Preserve the existing capability markers and add explicit globally activated
  client provenance to the four bounded success-evidence lines.
- Remove the temporary workspace and pub cache on success, failure, or signal.

## Non-Goals

- Change MCP protocol, authorization, session, resource, prompt, WAMP Meta
  API, or pub/sub behavior.
- Depend on a published prerelease from pub.dev instead of the exact source
  revision under test.
- Publish or retag a Router Image.

## Verification

- A focused Router Image source contract, first failing because the runner
  invoked `dart run` from the repository workspace.
- Shell syntax validation and the full Router Image MCP contract suite.
- A real locally loaded Router Image run when Docker can build the exact
  source revision.
- `bin/test-fast` before the change and `bin/verify` before handoff.
- Exact-head CI, package dry run, Router Image dry run, WAMP benchmarks, hosted
  log inspection, and strict deployment-chain audit after the implementation
  push.

## Progress

- 2026-08-03: Selected after the readable Router Image evidence plan completed
  with clean local and hosted verification. Existing local verification proves
  isolated global activation against the source example, while the canonical
  fresh-image workflow still runs the package executable from the repository
  workspace.
- 2026-08-03: Pre-change `bin/test-fast` passed. A focused source contract then
  failed on the missing isolated workspace, pub cache, global activation,
  resolved-command check, and executable provenance.
- 2026-08-03: The runner now stages only the public MCP dependency graph,
  activates `router_hosted_client` into an isolated pub cache, and uses that
  command for all four image runs. Shell syntax and all 16 focused Router Image
  MCP contracts pass.
- 2026-08-03: An exact local Router Image build completed, and the full runner
  passed against it. The fresh image accepted the raw protocol probe and all
  four globally activated package-client runs; the bounded lines prove public
  and router-issued auth, modern sessionlessness, compatibility Streamable
  deletion/auth lifecycle, resources/templates/prompts, WAMP Meta API, and
  pub/sub.
- 2026-08-03: Full `bin/verify` passed after the change, including formatting,
  Rust core/FFI, MCP/client/package-boundary and global-activation smokes, live
  WAMP benchmarks, all router tests, native follow-ups, and Chrome/Dart2Wasm.
  Exact-head hosted workflows and the strict deployment-chain audit remain.
