# Exec Plan: MCP Consumer Secure Unknown-Bearer WAMP Meta Pub/Sub Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-11
Last updated: 2026-05-11

## Goal

Make the generated router-hosted MCP consumer package smoke prove that secure
MCP endpoints reject an unknown raw bearer token on fresh clients across the
same direct JSON and Streamable WAMP meta/pub/sub route matrix used for
missing-bearer and stale/revoked-bearer checks.

## Scope

- In scope: an access token string that was never issued by the HTTP auth
  bridge, used by a fresh MCP client without an active Streamable session.
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
- `docs/exec-plans/2026-05-11-mcp-consumer-secure-unknown-bearer-wamp-meta-pubsub-smoke.md`
- Existing docs-only hosted-evidence updates from the previous rejected-bearer
  WAMP meta/pub-sub slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `66225d8` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-11.

## Plan

1. Add a deterministic unknown bearer token value to the generated consumer
   smoke.
2. Reuse the existing fresh-client rejected-bearer helper before issuing any
   valid grant so unknown bearer credentials cover the direct JSON, WAMP
   meta/pub/sub, and Streamable HTTP route shapes.
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
- Commit `caf987a` (`test: cover unknown mcp bearer auth`) was pushed to both
  configured remotes on 2026-05-11.
- GitHub Actions `CI` run `25684774263` passed on `caf987a`: `Fast Checks`
  completed successfully at 2026-05-11T17:05:08Z and `Full Verify` completed
  successfully at 2026-05-11T17:11:26Z.
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
  generated consumer package smoke. Previous slices covered missing credentials
  and stale/revoked issued credentials; an unknown raw bearer token exercises
  the auth-present but invalid credential path before any consumer application
  needs private assumptions.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted log
scan, and the non-strict deployment-chain audit are clean for `caf987a`. The
only remaining strict-audit gaps are operator-side release-hardening items.
