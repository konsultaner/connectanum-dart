# Exec Plan: Router-Hosted MCP Example Auth Refresh/Revoke Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the runnable router-hosted MCP example prove that consumer applications
can safely use the HTTP auth bridge refresh and revocation lifecycle with a
bearer-protected MCP route.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- Generated consumer package smoke already covered refresh-token rotation and
  revocation. The public runnable example still only proved initial ticket
  token issuance plus bearer-protected MCP access.
- The example should prove that rotated and revoked tokens are rejected by both
  fresh secure MCP requests and already-initialized Streamable HTTP sessions.

## Scope

- Enable refresh-token rotation on the example HTTP auth route.
- Preserve the issued auth grant so the example can use both the access token
  and refresh token.
- Add a focused secure MCP smoke that refreshes the grant, rejects the old
  access and refresh tokens, proves the refreshed access token works for direct
  JSON and initialized Streamable HTTP requests, revokes the refreshed grant,
  and rejects the revoked access and refresh tokens.
- Assert rejected active Streamable HTTP sessions clear client-side session and
  cursor state.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused router-hosted MCP example smoke passed on 2026-05-09 with isolated
  `TMPDIR`:
  `bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- Keep the public example smoke narrower than the generated consumer package
  smoke: the example checks representative direct JSON and Streamable MCP
  paths for refreshed credentials, while the generated consumer package smoke
  remains the broader rejected-request-shape matrix.

## Handoff

Local verification is clean. Commit, push, and hosted deployment-chain evidence
are pending.
