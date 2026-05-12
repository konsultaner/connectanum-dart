# Exec Plan: MCP Consumer Streamable CORS Lifecycle Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Prove browser-like downstream applications can use router-hosted MCP
Streamable HTTP sessions through configured CORS policy, including readable
session/protocol headers on stateful initialize, notification, POST/SSE,
GET/SSE, DELETE, and stale-session responses.

## Scope

- In scope: generated consumer package smoke coverage for public and
  bearer-protected router-hosted MCP routes using raw `HttpClient` requests with
  a neutral allowed `Origin`.
- In scope: asserting `Access-Control-Allow-Origin`,
  `Access-Control-Expose-Headers`, `MCP-Session-Id`, and
  `MCP-Protocol-Version` across stateful Streamable HTTP responses.
- In scope: proving raw Streamable POST/SSE tool listing, GET/SSE notification
  polling, `Last-Event-ID` resume behavior, session deletion, and deleted
  session rejection through the same CORS path.
- Out of scope: changing public CORS defaults, adding application-specific
  hosts, or altering non-MCP HTTP route behavior unless the smoke exposes a
  correctness bug.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-12-mcp-consumer-streamable-cors-lifecycle-smoke.md`
- Existing docs-only hosted-evidence updates from the CORS preflight slice
  remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- Latest pushed branch checkpoint `e35cab0` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-12.
- `bash -n bin/common.sh` passed on 2026-05-12.
- Focused generated consumer smoke (`bash -lc 'source bin/common.sh;
  run_mcp_consumer_package_smoke'`) passed on 2026-05-12.
- Post-change `bin/test-fast` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `786904a` (`test: cover mcp streamable cors lifecycle`) was pushed
  to both configured remotes on 2026-05-12.
- GitHub Actions `CI` run `25739082402` passed on `786904a`: `Fast Checks`
  completed successfully at 2026-05-12T13:59:06Z and `Full Verify` completed
  successfully at 2026-05-12T14:05:25Z.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, latest CI log scan
  clean, and a clean relevant Dart package publish dry-run; the dry-run remains
  relevant from `e35cab0` because no publish-sensitive paths changed.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Plan

1. Extend the generated consumer package smoke so public and secure MCP routes
   are initialized via raw Streamable HTTP requests that carry the allowed
   `Origin` header.
2. Assert browser-readable CORS metadata and MCP session/protocol headers on
   initialize, initialized notification, POST/SSE tool listing, GET/SSE poll,
   Last-Event-ID resume, DELETE, and deleted-session rejection.
3. Run `bash -n bin/common.sh`, focused generated consumer smoke,
   `bin/test-fast`, and `bin/verify`; then push and collect hosted
   deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.

## Decision Log

- 2026-05-12: Continue MCP downstream-readiness hardening after CORS preflight.
  The previous slice proved preflight and direct JSON CORS metadata; this slice
  covers the stateful Streamable HTTP lifecycle that browser-like consumer
  applications need to read and reuse MCP session headers.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `786904a`.
The only remaining strict-audit gaps are operator-side release-hardening items.
