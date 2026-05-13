# Exec Plan: MCP Consumer Generic Streamable Subscription Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-08
Last updated: 2026-05-08

## Goal

Prove from the generated router-hosted consumer package smoke that downstream
applications can use generic Streamable JSON-RPC `tools/call` requests for
router-provided WAMP subscription meta procedures while a public pub/sub
subscription is active.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Add generic Streamable JSON-RPC coverage for `wamp.subscription.lookup`,
    `wamp.subscription.match`, `wamp.subscription.list`,
    `wamp.subscription.get`, `wamp.subscription.list_subscribers`, and
    `wamp.subscription.count_subscribers`.
  - Assert subscription meta calls preserve the initialized MCP session id and
    advance the Streamable SSE cursor.
  - Assert visible subscriber metadata is scoped to the consumer-facing MCP
    session and does not expose the service session.
  - Bundle the previous docs-only hosted-evidence state updates from the
    generic Streamable WAMP meta/resource-template checkpoint.
- Out of scope:
  - Router runtime behavior changes.
  - New public API methods.
  - Private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-meta-template-smoke.md`
- `docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-subscription-meta-smoke.md`

## Preconditions

- Latest pushed implementation commit `53e616e` has clean hosted CI evidence.
- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Local validation that starts a native runtime uses an isolated `TMPDIR`.

## Plan

1. Extend the active generic Streamable pub/sub smoke section with raw WAMP
   subscription meta tool calls while the generic subscription handle is live.
2. Run focused syntax/generated consumer smoke checks, post-change
   `bin/test-fast`, and full `bin/verify` with isolated `TMPDIR`.
3. Commit implementation plus bundled state updates, push both remotes, and
   inspect hosted GitHub evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Focused `bash -n bin/common.sh bin/test-fast bin/test-all` and
  `git diff --check` passed on 2026-05-08.
- Focused generated router-hosted consumer package smoke
  (`source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke`) passed
  on 2026-05-08 with isolated `TMPDIR`.
- Post-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
- Commit `89a97ec`
  (`test: cover mcp generic streamable subscription meta`) was pushed to
  `origin/add-router` and `github/add-router` on 2026-05-08.
- Hosted GitHub `CI` run `25567752876` for `89a97ec` completed successfully
  on 2026-05-08 with `Fast Checks` (6m01s) and `Full Verify` (8m33s) green.
- Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
  relevant clean Dart package publish dry-run (`25485027779`, no
  publish-sensitive changes since that run).
- Strict deployment audit still reports operator-side gaps: branch protection
  and required status checks are absent, `.github/workflows/router-image.yml`
  is not discoverable from the default branch, and
  `ghcr.io/konsultaner/connectanum-router` is not visible.

## Decision Log

- 2026-05-08: Chose this slice because generic Streamable JSON-RPC consumer
  smoke already covers router API describe, session/registration meta,
  resource templates, and pub/sub delivery, while subscription meta is the next
  WAMP introspection surface a downstream application or agent needs to inspect
  live pub/sub state through the generic MCP endpoint.

## Handoff

Implementation, hosted GitHub CI, and the standard deployment-chain audit are
clean. Remaining strict deployment audit findings are release-operations gaps
outside this implementation slice.
