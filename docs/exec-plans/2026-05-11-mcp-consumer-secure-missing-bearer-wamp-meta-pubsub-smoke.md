# Exec Plan: MCP Consumer Secure Missing-Bearer WAMP Meta Pub/Sub Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that
bearer-protected MCP endpoints reject missing credentials for WAMP meta API and
pub/sub calls, not only tool catalog calls.

## Scope

- In scope: unauthenticated direct JSON `connectanum.api.list` rejection against
  the secure router MCP endpoint.
- In scope: unauthenticated direct JSON `connectanum.pubsub.subscribe` rejection
  against the secure router MCP endpoint.
- In scope: unauthenticated direct JSON batches that mix WAMP meta and pub/sub
  method-name calls.
- In scope: unauthenticated Streamable HTTP batches that mix WAMP meta and
  pub/sub tool calls through `tools/call`.
- In scope: checks that each rejected no-credential request leaves the generated
  consumer client's Streamable session state unset.
- Out of scope: auth policy changes, token grant behavior changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-missing-bearer-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous MCP
  session-method slice will remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `d2c8e19` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Expand the secure no-credential smoke helper with direct JSON WAMP meta and
   pub/sub method-name calls.
2. Add direct JSON and Streamable HTTP batch variants that mix WAMP meta and
   pub/sub calls, proving the secure route rejects the whole request before MCP
   dispatch.
3. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Commit `3ca481c` (`test: cover secure mcp meta pubsub auth`) is pushed to
  both remotes.
- GitHub `CI` run `25676940340` completed successfully for `3ca481c` with
  `Fast Checks` and `Full Verify` green.
- The hosted CI log scan was clean.
- GitHub `Dart Package Publish Dry Run` run `25635686773` remains clean and
  relevant because no publish-sensitive package inputs changed after
  `90a27ca`.
- The deployment-chain audit passed with clean latest CI, clean hosted CI logs,
  and a clean relevant Dart package publish dry-run.
- The strict audit still reports only known operator-side release-hardening
  gaps: branch protection/required checks are absent,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
  is not visible in GitHub Packages.

## Decision Log

- 2026-05-11: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Secure missing-bearer coverage already
  proves tool catalog and Streamable session-method paths; WAMP meta and pub/sub
  are the remaining direct application APIs that should be pinned on the
  no-credential secure route.

## Handoff

Implementation plus focused, fast, full local, and hosted verification are
complete. Remaining gaps are operator-side deployment-chain hardening:
branch protection/required checks, default-branch visibility for
`.github/workflows/router-image.yml`, and public visibility for
`ghcr.io/konsultaner/connectanum-router`.
