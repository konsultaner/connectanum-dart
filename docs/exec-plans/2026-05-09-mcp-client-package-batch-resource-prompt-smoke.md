# Exec Plan: MCP Client Package Batch Resource/Prompt Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the generated client-only consumer package smoke prove that a downstream
application can use public `McpStreamableHttpClient.postBatch(...)` calls for
MCP resource and prompt detail operations without relying on router-private code
or losing Streamable HTTP session state.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Generated router-hosted consumer and runnable example smokes already cover
  batched resource/prompt behavior against real router-hosted MCP endpoints.
- The generated client-only package smoke covered typed resource/prompt helpers,
  generic tool/meta batches, batch error isolation, and batched pub/sub, but did
  not yet prove public `postBatch(...)` resource/prompt detail sequencing and
  resource/prompt error recovery from a normal package boundary.

## Scope

- Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
- Add direct JSON `postBatch(...)` coverage for `resources/read`,
  `resources/templates/list`, `prompts/list`, and `prompts/get` while omitting
  Streamable session headers.
- Add direct JSON batch error/recovery coverage for missing resources and
  prompts.
- Add Streamable HTTP `postBatch(...)` coverage for the same resource/prompt
  detail and error/recovery paths while preserving the initialized MCP session
  id and SSE cursor.
- Keep the fake endpoint neutral and package-local; do not add private
  downstream application references.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused generated client-only consumer package smoke passed on 2026-05-09
  with isolated `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
- Commit `e04d911` (`test: cover mcp client batch resources`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25602314946` for `e04d911` completed successfully
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

- 2026-05-09: Chose this slice because real router-hosted consumer smokes
  already cover batched resource/prompt detail operations, while the
  client-only generated package smoke did not yet prove the same public
  `postBatch(...)` usage from a package boundary.
- 2026-05-09: Include missing-resource and missing-prompt batch errors in both
  direct JSON and Streamable paths so agents can rely on JSON-RPC error
  isolation without losing the active Streamable session.

## Handoff

Implementation, local verification, push, and hosted CI/deployment-chain
evidence are complete. Remaining strict audit findings are operator-side
release gaps, not regressions from this smoke-test change.
