# Exec Plan: Router-Hosted MCP Example Topic Meta Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can discover router-provided WAMP topic metadata through both lifecycle-free
direct JSON and initialized Streamable HTTP MCP requests.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The public example already configures the `example.events.task` topic and
  proves pub/sub helper calls. Its generic WAMP API metadata smoke currently
  focuses on procedures.
- Agents and consumer applications need topic catalog/describe coverage to
  discover available pub/sub surfaces without private assumptions.

## Scope

- Add topic metadata assertions to the public router-hosted MCP example.
- Cover `connectanum.api.list` and `connectanum.api.describe` for
  `example.events.task` through lifecycle-free direct JSON.
- Cover the same topic catalog and describe checks through initialized
  Streamable HTTP `tools/call`.
- Preserve existing assertions that direct JSON metadata calls do not mutate
  Streamable session id or SSE cursor state.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke passed on 2026-05-09 with isolated
  `TMPDIR`:
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- Keep this as public example smoke coverage rather than a new API surface:
  the lower-level router and client tests already cover authorization filtering,
  so the example should prove the consumer-facing happy path for topic metadata.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
deployment-chain evidence are pending.
