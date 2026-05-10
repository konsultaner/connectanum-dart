# Exec Plan: MCP Router Native Auth Grant Smoke

Status: full local verification complete; push and hosted evidence pending
Owner: Codex
Created: 2026-05-10
Last updated: 2026-05-10

## Goal

Make router-native MCP integration coverage use full HTTP auth bridge grants for
successful secure Streamable HTTP clients, matching the public consumer API path
while preserving raw bearer headers only for direct HTTP and rejected-principal
assertions.

## Scope

- In scope: `packages/connectanum_router/test/router_integration_native_test.dart`
  secure MCP Streamable client setup and the public MCP README guidance for
  protected routes.
- Out of scope: router runtime behavior changes, HTTP auth protocol changes,
  and generated consumer package smoke changes already covered by the prior
  exec plan.

## Files Expected To Change

- `packages/connectanum_router/test/router_integration_native_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-10-mcp-router-native-auth-grant-smoke.md`

## Preconditions

- Serena project onboarding is complete for this repository.
- Pre-change `bin/test-fast` must pass before editing the integration test.

## Plan

1. Confirm the current branch and pre-change fast gate are clean.
2. Convert successful secure router-native MCP clients from raw access-token
   strings to `ConnectanumHttpAuthGrant` plus
   `McpStreamableHttpClient.withAuthGrant`.
3. Keep explicit bearer headers for direct HTTP assertions and
   rejected-principal session isolation probes.
4. Run focused router-native MCP integration coverage, `bin/test-fast`, and
   `bin/verify`; then push and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-10.
- Focused `dart test packages/connectanum_router/test/router_integration_native_test.dart -p vm`
  passed on 2026-05-10.
- Post-change `bin/test-fast` passed on 2026-05-10.
- Full local `bin/verify` passed on 2026-05-10.

## Decision Log

- 2026-05-10: Continue the MCP auth-grant migration at the router-native
  integration layer because it is the remaining successful secure MCP coverage
  still constructing Streamable clients from copied access-token strings.

## Handoff

Implementation and full local verification are complete. Push and hosted
deployment-chain evidence remain pending.
