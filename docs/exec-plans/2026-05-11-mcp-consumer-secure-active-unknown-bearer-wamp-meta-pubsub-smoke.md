# Exec Plan: MCP Consumer Secure Active Unknown-Bearer WAMP Meta Pub/Sub Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that secure
MCP endpoints reject an unknown raw bearer token when that client attempts to
reuse another client's active Streamable HTTP session ID, across the same direct
JSON, WAMP meta/pub/sub, and Streamable HTTP matrix used for active rejected
bearer checks.

## Scope

- In scope: an access token string that was never issued by the HTTP auth
  bridge.
- In scope: a secure `McpStreamableHttpClient` seeded with another client's
  active `Mcp-Session-Id` and last event id.
- In scope: the existing active rejected-bearer helper matrix: direct JSON
  `connectanum.api.list`, direct JSON `connectanum.pubsub.subscribe`, direct
  JSON batches with WAMP meta/pub/sub methods, Streamable batch tool/resource
  and WAMP meta/pub/sub calls, notifications, resource/template/prompt helpers,
  poll, and session delete.
- In scope: proving the primary owner Streamable MCP session remains usable
  after the rejected unknown-bearer reuse attempt.
- Out of scope: auth policy changes, token grant behavior changes, and
  consumer application assumptions.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-active-unknown-bearer-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous unknown-bearer
  fresh-client slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `caf987a` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Add a secure unknown-bearer client to the Streamable session reuse isolation
   smoke.
2. Seed it with the primary client's active session id and last event id, then
   reuse the active rejected-bearer helper so unknown credentials cover direct
   JSON, WAMP meta/pub/sub, Streamable HTTP, poll, and delete paths.
3. Re-check the primary owner session after the rejected reuse attempt.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Commit `251e5e2` (`test: cover active unknown mcp bearer auth`) was pushed
  to both configured remotes on 2026-05-11.
- GitHub Actions `CI` run `25687247656` passed on `251e5e2`: `Fast Checks`
  completed successfully at 2026-05-11T17:53:13Z and `Full Verify` completed
  successfully at 2026-05-11T17:59:50Z.
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
  generated consumer package smoke. Previous slices covered unknown bearer
  credentials on fresh clients and stale/revoked issued credentials on active
  sessions; unknown bearer credentials on an active session ID complete the
  auth-present but invalid-session-reuse path without consumer application
  assumptions.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted log
scan, and the non-strict deployment-chain audit are clean for `251e5e2`. The
only remaining strict-audit gaps are operator-side release-hardening items.
