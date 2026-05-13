# Exec Plan: Router-Hosted MCP Example Auth Refresh/Revoke Smoke

Status: complete; hosted CI evidence clean
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
- Commit `1e40a1a` (`test: cover mcp example auth refresh`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-09.
- Hosted GitHub `CI` run `25592499292` for `1e40a1a` completed successfully
  on 2026-05-09 with `Fast Checks` (4m19s) and `Full Verify` (6m02s) green.
- Hosted `WAMP Profile Benchmarks` run `25592499289` completed successfully on
  2026-05-09 with `Linux WAMP profile gates` green (8m01s).
- Hosted `Dart Package Publish Dry Run` run `25592499290` completed
  successfully on 2026-05-09 with `Publish Dry Run` green and covering the
  checked-out head.
- Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
  relevant Dart package publish dry-run evidence.
- Strict deployment audit still reports operator-side release gaps: branch
  protection and required status checks are absent,
  `.github/workflows/router-image.yml` is not discoverable from the default
  branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- Keep the public example smoke narrower than the generated consumer package
  smoke: the example checks representative direct JSON and Streamable MCP
  paths for refreshed credentials, while the generated consumer package smoke
  remains the broader rejected-request-shape matrix.

## Handoff

Implementation, local verification, hosted CI, WAMP profile, and standard
deployment-chain audit evidence are clean for `1e40a1a`. Remaining strict audit
failures are operator-side release controls: branch protection/required checks,
default-branch router workflow visibility, and GHCR router package visibility.
