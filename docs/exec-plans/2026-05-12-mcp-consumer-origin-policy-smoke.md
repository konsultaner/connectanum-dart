# Exec Plan: MCP Consumer Origin Policy Smoke

Status: complete locally; hosted evidence pending
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
- Hosted CI and deployment-chain evidence are pending until the implementation
  commit is pushed.

## Decision Log

- 2026-05-12: Continue MCP downstream-readiness hardening on the neutral
  generated consumer package smoke. Existing router integration coverage pins
  invalid Origin handling; the generated consumer package smoke should also
  prove that a configured allowed Origin works on real router-provided public
  and secure MCP routes through public package APIs.

## Handoff

Implementation is complete locally. Focused smoke, `bin/test-fast`, and
`bin/verify` are clean. Commit, push, hosted CI, and deployment-chain evidence
remain pending.
