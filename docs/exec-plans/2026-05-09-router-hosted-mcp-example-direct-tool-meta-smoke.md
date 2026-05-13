# Exec Plan: Router-Hosted MCP Example Direct Tool/Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can use direct JSON tool aliases and metadata APIs without starting or mutating
an MCP Streamable HTTP session.

## Scope

- In scope:
  - Extend `packages/connectanum_router/example/router_hosted_mcp.dart`.
  - Add direct JSON coverage for `callConnectanumToolDirect`.
  - Add direct JSON coverage for `connectanum.tools.call` and
    `connectanum.tool.call` aliases.
  - Add generic direct JSON coverage for `connectanum.tools.list`,
    `connectanum.api.list`, and `connectanum.api.describe`.
  - Assert these direct JSON calls do not create or mutate Streamable
    session/SSE state.
  - Bundle the previous docs-only hosted-evidence state updates from the
    router-hosted MCP example batch pub/sub checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Consumer-specific application references.

## Files Expected To Change

- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-pubsub-smoke.md`
- `docs/exec-plans/2026-05-09-router-hosted-mcp-example-direct-tool-meta-smoke.md`

## Preconditions

- Latest pushed implementation commit `7162b1c` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.

## Plan

1. Extend the public router-hosted MCP example with lifecycle-free direct JSON
   tool alias checks.
2. Extend the same helper with direct JSON tool and API metadata discovery
   checks.
3. Run focused example smoke, post-change `bin/test-fast`, and full
   `bin/verify` with isolated `TMPDIR`.
4. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke
  (`source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke`)
  passed on 2026-05-09 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- `git diff --check` passed on 2026-05-09.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `7c936c9` (`test: cover mcp example direct tool meta`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25586788256` for `7c936c9` completed successfully on
  2026-05-09 with `Fast Checks` (6m04s) and `Full Verify` (8m36s) green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
  hosted CI logs, and a clean Dart package publish dry-run covering checked-out
  head (`25586788266`).
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-09: Chose this slice because the generated router-hosted consumer
  smoke already proves direct JSON tool alias and metadata API access, while
  the runnable public example only showed the dotted procedure method and
  batched metadata calls mixed into other checks.

## Handoff

Implementation, local verification, hosted CI, and standard deployment-chain
audit evidence are clean for `7c936c9`. Remaining strict audit failures are
operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.
