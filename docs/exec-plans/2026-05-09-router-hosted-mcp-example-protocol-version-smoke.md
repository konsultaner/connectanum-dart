# Exec Plan: Router-Hosted MCP Example Protocol Version Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove Streamable HTTP protocol
version compatibility on both public and bearer-protected MCP routes.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Generated consumer package smoke already covered Streamable HTTP protocol
  version compatibility. The public runnable example still needed matching
  proof for consumer applications and agents using the package without private
  project assumptions.
- Older supported protocol versions must initialize cleanly and negotiate to
  the current version. Unsupported protocol versions must be rejected without
  leaving Streamable HTTP session or cursor state behind.

## Scope

- Add public example checks for supported older protocol versions
  `2025-03-26` and `2025-06-18`.
- Add public example checks that unsupported protocol version `2099-01-01`
  returns HTTP 400 without establishing session state.
- Run the same checks against the bearer-protected MCP route using the public
  bearer-token client constructor.
- Keep the checks isolated from the main example MCP sessions.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke passed on 2026-05-09 with isolated
  `TMPDIR`:
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- Use fresh short-lived `McpStreamableHttpClient` instances for protocol
  compatibility checks so older-version negotiation and unsupported-version
  rejection cannot alter the main public or secure example sessions.

## Handoff

Local verification is clean. Commit, push, and hosted deployment-chain evidence
are pending.
