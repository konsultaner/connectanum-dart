# Exec Plan: MCP Consumer Direct WAMP API Helper Smoke

Status: complete; local and hosted evidence clean
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

The generated consumer-package router-hosted MCP smoke proves raw direct
JSON-RPC access to `connectanum.api.list` and `connectanum.api.describe`, and it
also exercises mixed WAMP API helper calls with `directJson: true`. It does not
yet prove that a neutral consumer application can use the public named direct
WAMP API helper APIs against the router-provided MCP endpoint.

## Scope

- Add generated consumer-package smoke coverage for `listWampApiDirect` and
  `describeWampApiDirect` against procedure and topic metadata.
- Assert those direct helper calls remain lifecycle-free and do not mutate an
  active Streamable HTTP session id or SSE cursor.
- Keep the existing raw direct JSON-RPC and mixed `directJson: true` helper
  coverage in place.

## Non-Goals

- Changing MCP wire protocol behavior.
- Removing raw JSON-RPC access coverage.
- Changing public package metadata or release automation.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Generated consumer-package router-hosted MCP smoke calls the named direct WAMP
  API helper APIs and validates procedure and topic metadata from the public
  package boundary.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `run_mcp_consumer_package_smoke` passed on 2026-05-13, including generated
  package `dart analyze` and router-hosted MCP runtime smoke.
- `git diff --check` passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.
- Commit `be89a91` (`mcp: smoke consumer direct wamp api helpers`) was pushed
  to both configured remotes on 2026-05-13.
- GitHub `CI` run `25796015262` completed successfully on 2026-05-13 with
  `Fast Checks` and `Full Verify` green.

## Decision Log

- 2026-05-13: Keep this as consumer-package smoke coverage because the public
  helper APIs already exist; the readiness gap is proving package-boundary use
  against router-hosted MCP.
- 2026-05-13: With this package-boundary direct WAMP API helper smoke green,
  MCP is RC-ready for the first GitHub prerelease. Treat additional helper
  permutations as post-RC polish unless they uncover a consumer integration
  correctness bug.

## Handoff

Implementation is pushed and hosted CI is green. This closes the active MCP
slice for first-RC readiness; continue with release-branch promotion and hosted
deployment-chain validation.
