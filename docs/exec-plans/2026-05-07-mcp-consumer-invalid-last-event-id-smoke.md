# Exec Plan: MCP Consumer Invalid Last-Event-ID Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that router-hosted
Streamable HTTP rejects an unknown `Last-Event-ID` resume cursor without
destroying the active MCP session or forcing the consumer to reinitialize.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use only public consumer-facing `McpStreamableHttpClient` APIs.
  - Assert the invalid resume request returns HTTP 400, mentions
    `Last-Event-ID`, preserves active session/cursor state, and leaves the
    session usable.
- Out of scope:
  - Changing router resume semantics.
  - Changing public client APIs.
  - Adding private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-invalid-last-event-id-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Existing docs-only hosted-evidence updates for the protocol-version smoke
  remain uncommitted and should be bundled with this implementation commit.

## Plan

1. Add the generated consumer-app Streamable invalid-resume assertion.
2. Run focused smoke and formatting checks.
3. Run `bin/verify`, commit implementation plus state updates, push both
   remotes, and inspect hosted CI evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`,
  `git diff --check`, and
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted GitHub evidence is pending for the implementation commit.

## Decision Log

- 2026-05-07: Chose this slice because router integration tests already cover
  unknown `Last-Event-ID` rejection, but the neutral consumer smoke did not
  prove the public Streamable client keeps the active session usable after
  that protocol edge.
- 2026-05-07: The first focused smoke used the pre-resume event id as the
  cursor preservation baseline. The public client correctly advanced
  `lastEventId` when the valid resume poll returned a keepalive SSE event, so
  the final assertion snapshots the cursor after that successful resume before
  checking the invalid resume path.

## Handoff

Complete locally. Push the implementation commit and inspect hosted CI before
recording hosted evidence.
