# Exec Plan: MCP Consumer Origin Policy Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Make the generated router-hosted MCP consumer package smoke prove that
configured MCP Origin policy works for both public and bearer-protected routes
when a downstream application uses only public package APIs.

## Scope

- In scope: configuring public and secure router-hosted MCP routes with a
  neutral allowed origin.
- In scope: proving direct JSON and Streamable HTTP requests with the allowed
  `Origin` header work on public and bearer-protected MCP routes.
- In scope: proving direct JSON requests with a disallowed `Origin` header fail
  with HTTP 403 without creating local Streamable HTTP session state.
- Out of scope: browser-specific CORS preflight handling, changing default
  Origin policy semantics, or adding application-specific hostnames.

## Files Expected To Change

- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-12-mcp-consumer-origin-policy-smoke.md`
- Existing docs-only hosted-evidence updates from the secure protocol-version
  slice remain bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `8ceac39` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-12.

## Plan

1. Add a neutral allowed-origin constant to the generated consumer package
   smoke and configure both public and secure MCP route options with it.
2. Add a focused smoke helper that creates public and auth-grant MCP clients
   with allowed/disallowed `Origin` headers through public client constructors.
3. Assert allowed-origin direct JSON and Streamable HTTP calls succeed, and
   disallowed-origin direct JSON calls fail with HTTP 403 without local session
   state.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- Focused `bash -n bin/common.sh` passed on 2026-05-12.
- Focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
  2026-05-12.
- Post-change `bin/test-fast` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `6dfcb87`
  (`test: cover mcp origin policy smoke`) was pushed to both configured remotes
  on 2026-05-12.
- GitHub Actions `CI` run `25731613387` passed on `6dfcb87`: `Fast Checks`
  completed successfully at 2026-05-12T11:35:53Z and `Full Verify` completed
  successfully at 2026-05-12T11:42:17Z.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, latest CI log scan
  clean, and Dart Package Publish Dry Run `25635686773` still relevant because
  no publish-sensitive paths changed since that dry-run head.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Decision Log

- 2026-05-12: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Existing router integration coverage pins
  invalid Origin handling; the generated consumer package smoke should also
  prove that a configured allowed Origin works on real router-provided public
  and secure MCP routes through public package APIs.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `6dfcb87`.
The only remaining strict-audit gaps are operator-side release-hardening items.
