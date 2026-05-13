# Exec Plan: MCP Consumer Secure Rejected-Bearer WAMP Meta Pub/Sub Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that secure
MCP endpoints reject stale or revoked bearer tokens on fresh clients across the
same direct JSON and Streamable WAMP meta/pub/sub route matrix used for
missing-bearer checks.

## Scope

- In scope: rotated or revoked bearer tokens used by a fresh MCP client without
  an active Streamable session.
- In scope: direct JSON `connectanum.tools.list`, `connectanum.api.list`, and
  `connectanum.pubsub.subscribe` rejection coverage.
- In scope: direct JSON batches covering tool catalog and WAMP meta/pub/sub
  requests.
- In scope: Streamable HTTP `initialize`, batch `tools/list`, and batch
  WAMP meta/pub/sub `tools/call` rejection coverage.
- Out of scope: auth policy changes, token grant behavior changes, and
  documentation-only cleanup.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-rejected-bearer-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous active-bearer
  WAMP meta/pub-sub slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `9895c92` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Factor the secure MCP no-credentials route matrix into a reusable helper.
2. Reuse that helper for stale/revoked bearer token checks so fresh rejected
   bearer clients cover direct JSON, WAMP meta/pub/sub, and Streamable HTTP
   route shapes.
3. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-11.
- Focused `bash -n bin/common.sh` passed on 2026-05-11.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-11.
- Post-change `bin/test-fast` passed on 2026-05-11.
- Full local `bin/verify` passed on 2026-05-11.
- Commit `66225d8` (`test: cover rejected mcp meta pubsub auth`) was pushed
  to both configured remotes on 2026-05-11.
- GitHub Actions `CI` run `25682352222` passed on `66225d8`: `Fast Checks`
  completed successfully at 2026-05-11T16:20:01Z and `Full Verify` completed
  successfully at 2026-05-11T16:26:29Z.
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
  generated consumer package smoke. The previous slice covered stale/revoked
  bearer tokens on already-active Streamable sessions; fresh rejected-bearer
  clients should hit the same app-facing WAMP meta/pub-sub route matrix before
  any private application assumptions are needed.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted log
scan, and the non-strict deployment-chain audit are clean for `66225d8`. The
only remaining strict-audit gaps are operator-side release-hardening items.
