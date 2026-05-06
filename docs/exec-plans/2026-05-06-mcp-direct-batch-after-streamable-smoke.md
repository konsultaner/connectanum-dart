# Exec Plan: MCP Direct Batch After Streamable Smoke

Status: complete locally; hosted evidence pending
Owner: Codex
Created: 2026-05-06
Last updated: 2026-05-06

## Goal

Prove that consumer applications can mix lifecycle-free direct JSON-RPC batch
calls with an already initialized router-hosted Streamable HTTP MCP session
without leaking or mutating session state.

## Scope

- In scope:
  - Client regression coverage for direct JSON batch requests after
    Streamable initialization.
  - Generated consumer package smoke coverage for direct batch calls after
    Streamable initialization and before normal Streamable calls continue.
  - Local verification evidence.
- Out of scope:
  - Router protocol changes.
  - Public documentation expansion beyond project-state bookkeeping.

## Files Expected To Change

- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-06-mcp-direct-batch-after-streamable-smoke.md`

## Preconditions

- `bin/test-fast` is green before implementation.
- No secrets or deployment credentials are required.
- The existing hosted-evidence project-state edits remain docs-only until
  bundled with this implementation commit.

## Plan

1. Add focused client coverage proving `postBatch(..., streamable: false,
   includeSession: false)` sends JSON-only requests without MCP session or SSE
   resume headers after initialization.
2. Extend the generated consumer package smoke so the same direct batch path is
   exercised after Streamable initialization and proves session/cursor state is
   unchanged.
3. Run focused MCP client tests, generated consumer package smoke,
   `bin/test-fast`, and `bin/verify`; then push and collect hosted evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- `bash -n bin/common.sh` passed on 2026-05-06.
- `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "keeps direct JSON batches lifecycle-free with an active Streamable session"` passed on 2026-05-06.
- `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded` passed on 2026-05-06.
- `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart` passed on 2026-05-06.
- `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'` passed on 2026-05-06.
- Post-change `bin/test-fast` passed on 2026-05-06.
- Full local `bin/verify` passed on 2026-05-06.
- Pending: hosted GitHub evidence after push.

## Decision Log

- 2026-05-06: Chose direct JSON batch-after-Streamable coverage as the next
  MCP readiness slice because direct tool/meta, resources/prompts, WAMP
  helpers, pub/sub, and direct catalog paths already had mixed direct/Streamable
  session coverage, while batch mode still only had a lifecycle-free
  no-session smoke.

## Handoff

- Direct JSON batch-after-Streamable coverage is complete locally. Push the
  implementation commit and collect hosted GitHub evidence.
