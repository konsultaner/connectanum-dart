# Exec Plan: MCP Client Package Direct WAMP Helper Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated client-only consumer package that downstream
applications can use direct JSON WAMP API, WAMP meta, and pub/sub helper
surfaces after a Streamable HTTP session is active, without leaking
Streamable session headers or relying on router/private project assumptions.

## Scope

- In scope:
  - Extend `run_mcp_client_package_smoke` in `bin/common.sh`.
  - Exercise direct JSON `McpStreamableHttpClient.describeWampApi` and
    `McpStreamableHttpClient.countWampSessions` in the generated package.
  - Track direct `connectanum.tool.call` helper names received without
    `MCP-Session-Id`.
  - Assert direct WAMP API, WAMP meta, and pub/sub helper tool names all omit
    Streamable session state after initialization.
  - Bundle existing hosted-evidence docs updates from the previous MCP client
    package direct resource/prompt smoke checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Package publishing policy changes.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-client-package-direct-wamp-helper-smoke.md`
- Existing docs-only hosted-evidence updates for the previous MCP client
  package direct resource/prompt smoke plan.

## Preconditions

- Latest pushed implementation commit `15f754a` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Add direct JSON WAMP API describe and WAMP session meta count calls to the
   generated client-only consumer package.
2. Record direct WAMP helper tool names that arrived without
   `MCP-Session-Id`.
3. Assert direct `connectanum.api.list`, `connectanum.api.describe`,
   `wamp.session.count`, and pub/sub helper calls all remain lifecycle-free
   after Streamable initialization.
4. Run focused syntax/smoke checks, post-change `bin/test-fast`, and
   `bin/verify` with isolated `TMPDIR`.
5. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh bin/test-fast bin/test-all` passed on
  2026-05-08.
- Focused `git diff --check` passed on 2026-05-08.
- Focused generated client-only consumer smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Pushed implementation commit `be335d8`
  (`test: cover mcp direct wamp helper client smoke`) to `origin/add-router`
  and `github/add-router` on 2026-05-08.
- GitHub CI run `25550173165` passed on 2026-05-08: `Fast Checks` passed in
  5m57s and `Full Verify` passed in 8m45s.
- Deployment-chain audit passed with latest clean CI and relevant Dart package
  publish dry-run evidence on 2026-05-08.
- Strict deployment-chain audit still fails only the known operator-owned gaps:
  no branch protection, `.github/workflows/router-image.yml` not discoverable
  from the default branch, and `ghcr.io/konsultaner/connectanum-router` not
  visible.

## Decision Log

- 2026-05-08: Chose this slice because the generated client-only consumer
  package already exercised direct JSON WAMP API list and pub/sub helpers after
  Streamable initialization, but only asserted method-level
  `connectanum.tool.call` header behavior. Tracking helper tool names makes the
  smoke prove each direct WAMP API/meta/pubsub helper remains lifecycle-free.

## Handoff

Complete. Implementation passed focused syntax/generated client-only smoke
checks, post-change `bin/test-fast`, full local `bin/verify`, hosted GitHub
CI, and the normal deployment-chain audit. Strict audit remains blocked only
on the known operator-owned GitHub deployment gaps.
