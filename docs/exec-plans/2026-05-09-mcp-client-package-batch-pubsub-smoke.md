# Exec Plan: MCP Client Package Batch Pub/Sub Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the generated client-only consumer package smoke prove that a downstream
application can use public `McpStreamableHttpClient.postBatch(...)` calls for
WAMP-backed MCP pub/sub helper tools without relying on router-private code or
losing Streamable HTTP session state.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Generated router-hosted consumer and runnable example smokes already cover
  batched pub/sub behavior against real router-hosted MCP endpoints.
- The generated client-only package smoke covered public one-request pub/sub
  helpers, generic batch calls, and batch error isolation, but did not yet prove
  public `postBatch(...)` pub/sub sequencing from a normal package boundary.

## Scope

- Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
- Add direct JSON `postBatch(...)` pub/sub coverage that subscribes, publishes,
  polls, and unsubscribes using the returned subscription handle while omitting
  Streamable session headers.
- Add Streamable HTTP `postBatch(...)` pub/sub coverage for the same operation
  sequence while preserving the initialized MCP session id and SSE cursor.
- Keep the fake endpoint neutral and package-local; do not add private
  downstream application references.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused generated client-only consumer package smoke passed on 2026-05-09
  with isolated `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Hosted GitHub `CI` run `25601414311` for `75d1b3f` completed successfully
  on 2026-05-09 with `Fast Checks` and `Full Verify` green.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence. The latest relevant
  `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
  it is still relevant because no publish-sensitive paths changed since that
  run.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-09: Chose this slice because direct JSON and Streamable HTTP
  `postBatch(...)` pub/sub sequencing remained unproven at the public
  client-only package boundary after generic batch and batch error isolation
  coverage landed.
- 2026-05-09: Sequence subscribe first, then use the returned handle in
  follow-up publish/poll/unsubscribe batches. This mirrors a normal consumer
  application instead of assuming a deterministic endpoint-specific handle.

## Handoff

Implementation, local verification, push, and hosted CI/deployment-chain
evidence are complete. Remaining strict audit findings are operator-side
release gaps, not regressions from this smoke-test change.
