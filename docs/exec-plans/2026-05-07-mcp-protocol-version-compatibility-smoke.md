# Exec Plan: MCP Protocol Version Compatibility Smoke

Status: complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove the generated router-hosted MCP consumer package can use public
Streamable HTTP client APIs with older supported MCP protocol-version headers,
and that unsupported protocol-version headers fail cleanly without creating
Streamable session state.

## Scope

In scope:

- Extend the generated router-hosted consumer package smoke in `bin/common.sh`.
- Cover public MCP route initialization with older supported
  `MCP-Protocol-Version` values.
- Assert the server negotiates the public client back to
  `McpStreamableHttpClient.latestProtocolVersion`.
- Assert an unsupported protocol-version header returns HTTP 400 and leaves no
  session or SSE cursor state on the public client.

Out of scope:

- Changing supported MCP protocol versions.
- Changing auth semantics or route policy.
- Adding docs-only public narrative without implementation evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`,
  `git diff --check`, and
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.

## Decision Log

- 2026-05-07: Keep the smoke at the consumer-package level so the evidence
  proves downstream applications can rely on public package APIs rather than
  private router test harness assumptions.

## Handoff

Complete with local verification. Hosted CI evidence is pending for the next
pushed implementation commit.
