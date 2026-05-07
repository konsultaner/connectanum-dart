# Exec Plan: MCP Consumer Participant Meta Smoke

Status: complete; hosted CI evidence clean
Owner: Codex
Created: 2026-05-07
Last updated: 2026-05-07

## Goal

Prove from the generated neutral consumer package that router-hosted MCP WAMP
participant meta helpers expose only consumer-visible participant IDs and do
not leak the router service session behind public or bearer-protected routes.

## Scope

- In scope:
  - Extend `run_mcp_consumer_package_smoke` in `bin/common.sh`.
  - Use public consumer-facing `McpStreamableHttpClient` WAMP meta helper APIs.
  - Assert `wamp.registration.list_callees` and
    `wamp.registration.count_callees` hide the internal service callee for the
    router-exposed procedure.
  - Assert `wamp.subscription.list_subscribers` and
    `wamp.subscription.count_subscribers` report only visible consumer
    subscriber IDs and match each other.
  - Exercise the assertions through lifecycle-free direct JSON, initialized
    Streamable HTTP, and direct JSON after Streamable initialization.
- Out of scope:
  - Changing router WAMP meta semantics.
  - Changing public client APIs.
  - Adding private downstream application references.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-single-error-smoke.md`
- `docs/exec-plans/2026-05-07-mcp-consumer-participant-meta-smoke.md`

## Preconditions

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Existing docs-only hosted-evidence updates for the single-error smoke remain
  uncommitted and should be bundled with this implementation commit.

## Plan

1. Pass the router service session into the generated consumer WAMP meta smoke
   helpers.
2. Add registration callee list/count assertions for direct JSON and
   Streamable HTTP paths.
3. Add subscription subscriber list/count assertions for direct JSON and
   Streamable HTTP paths.
4. Run focused smoke and formatting checks.
5. Run `bin/verify`, commit implementation plus state updates, push both
   remotes, and inspect hosted CI evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-07.
- Focused checks passed on 2026-05-07:
  `bash -n bin/common.sh bin/test-fast bin/test-all`,
  `git diff --check`, and
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-07.
- Full local `bin/verify` passed on 2026-05-07.
- Hosted GitHub `CI` run `25482719085` for `6114ed0` completed
  successfully with `Fast Checks` and `Full Verify`, both with zero
  annotations.
- The Dart Package Publish Dry Run workflow did not trigger for `6114ed0`
  because no publish-sensitive paths changed. The latest relevant package
  dry-run remains `25463696541` for `3a0bbf0`, which completed successfully
  and still covers checked-out package inputs.
- The deployment-chain audit
  `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed against `6114ed0`; the strict variant correctly failed only on the
  known operator-owned deployment-chain gaps: `add-router` branch protection,
  router image workflow visibility from the default branch, and GHCR router
  package visibility.

## Decision Log

- 2026-05-07: Chose this slice because previous router-native tests pinned
  participant meta scoping, but the generated consumer package smoke did not
  yet prove public WAMP meta helper calls preserve that contract through the
  package surface a consumer application or agent uses.

## Handoff

Complete with hosted CI evidence. Remaining strict audit findings are
operator-owned deployment-chain gaps.
