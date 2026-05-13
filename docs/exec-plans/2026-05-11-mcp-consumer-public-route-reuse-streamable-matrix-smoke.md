# Exec Plan: MCP Consumer Public Route Reuse Streamable Matrix Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that a public
MCP route cannot reuse another client's active secure Streamable HTTP session ID
across the broad Streamable HTTP method matrix that a downstream application
would exercise.

## Scope

- In scope: a public-route `McpStreamableHttpClient` seeded with the primary
  secure client's active `Mcp-Session-Id` and last event id.
- In scope: Streamable HTTP batches for tool/resource catalog methods and WAMP
  meta/pub/sub `tools/call` methods, notification requests, typed tools, typed
  resources, typed prompts, GET/SSE poll, and session delete.
- In scope: proving each rejected public-route reuse attempt returns HTTP 404
  and clears only the rejected client's local Streamable session state.
- In scope: proving the primary owner Streamable MCP session remains usable
  after the rejected public-route reuse attempts.
- Out of scope: auth grant semantics, bearer validation policy changes, and
  consumer application assumptions.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-public-route-reuse-streamable-matrix-smoke.md`
- Existing docs-only hosted-evidence updates from the previous missing-bearer
  slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `0c21cd5` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Replace the public-route active-session poll/delete checks in the generated
   consumer package smoke with the reusable stale-session Streamable method
   matrix.
2. Re-seed the copied session id and last event id before each rejected request
   because the client clears stale Streamable session state after session
   failures.
3. Cover Streamable batches, WAMP meta/pub/sub `tools/call` batches,
   notifications, tools, resources, prompts, poll, and delete.
4. Re-check the primary owner session after the rejected public-route attempts.
5. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Commit `ffa38c4` (`test: cover public mcp route reuse matrix`) was pushed to
  both configured remotes on 2026-05-11.
- GitHub Actions `CI` run `25695269935` passed on `ffa38c4`: `Fast Checks`
  completed successfully at 2026-05-11T20:30:26Z and `Full Verify` completed
  successfully at 2026-05-11T20:36:59Z.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-11. The audit found latest CI clean, latest CI log scan
  clean, and Dart Package Publish Dry Run `25635686773` still relevant because
  no publish-sensitive paths changed since that dry-run head.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Earlier slices covered other-principal
  secure-route reuse and missing-bearer secure-route reuse across the broad
  Streamable method matrix; the remaining public-route reuse check still only
  covered poll/delete and should exercise the same downstream-facing route
  surface.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted log
scan, and the non-strict deployment-chain audit are clean for `ffa38c4`. The
only remaining strict-audit gaps are operator-side release-hardening items.
