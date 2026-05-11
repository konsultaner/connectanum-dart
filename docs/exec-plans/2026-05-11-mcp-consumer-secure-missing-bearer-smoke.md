# Exec Plan: MCP Consumer Secure Missing-Bearer Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that
bearer-protected MCP endpoints reject missing credentials across direct JSON and
Streamable HTTP ingress before a downstream application receives or reuses MCP
session state.

## Scope

- In scope: unauthenticated direct JSON `connectanum.tools.list` and direct JSON
  batch `connectanum.tools.list` rejection assertions against the secure router
  MCP endpoint.
- In scope: unauthenticated Streamable HTTP `initialize` and batch `tools/list`
  rejection assertions against the secure router MCP endpoint.
- In scope: checks that each rejected no-credential request leaves the
  generated consumer client's Streamable session state unset.
- Out of scope: auth policy changes, token grant behavior changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-missing-bearer-smoke.md`
- Existing docs-only hosted-evidence updates from the previous MCP catalog
  slice will remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `4d9c786` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Expand the secure no-credential smoke helper to cover direct JSON single,
   direct JSON batch, Streamable `initialize`, and Streamable batch POST paths.
2. Assert each rejected request returns HTTP 401 and does not populate the
   consumer client's Streamable session identifiers.
3. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push and
   collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`
  passed on 2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Commit `e31f063` (`test: cover secure mcp missing bearer batches`) is pushed
  to both remotes.
- GitHub `CI` run `25671922553` completed successfully for `e31f063` with
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
  router-hosted consumer package smoke. Secure direct JSON single-request
  rejection is already covered; missing-bearer batch and Streamable initialization
  ingress need the same generated consumer proof.

## Handoff

Implementation plus focused, fast, full local, and hosted verification are
complete. Remaining gaps are operator-side deployment-chain hardening:
branch protection/required checks, default-branch visibility for
`.github/workflows/router-image.yml`, and public visibility for
`ghcr.io/konsultaner/connectanum-router`.
