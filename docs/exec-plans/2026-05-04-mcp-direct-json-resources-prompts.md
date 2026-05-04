# Exec Plan: MCP Direct JSON Resources And Prompts

Status: implementation complete; local verification clean; hosted evidence pending
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make router-hosted MCP resources and prompts usable from lifecycle-free direct
JSON clients, including typed Dart helpers, without weakening the router-owned
MCP endpoint model.

## Scope

In scope:

- Let router-hosted MCP direct JSON dispatch handle the standard
  `resources/list`, `resources/read`, `resources/templates/list`,
  `prompts/list`, and `prompts/get` methods before MCP initialization.
- Add `directJson` options to the typed resource and prompt helpers on
  `McpStreamableHttpClient`.
- Ensure direct JSON helper calls do not attach an `MCP-Session-Id`, even when
  the client already has a Streamable HTTP session.
- Add focused client and router integration regressions.
- Update public MCP docs for the new direct JSON resource/prompt path.

Out of scope:

- Automatic application data or prompt projection.
- A standalone MCP-only router process.
- Changing standard MCP lifecycle requirements for normal MCP clients.

## Files Expected To Change

- `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart`
- `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `packages/connectanum_router/test/router_integration_native_test.dart`
- `packages/connectanum_mcp/README.md`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-04-mcp-direct-json-resources-prompts.md`

## Plan

1. Add direct JSON resource/prompt client coverage that proves no session header
   is sent.
2. Add router-hosted integration coverage that reads configured resources and
   prompts before MCP initialization.
3. Implement direct JSON dispatch for resource and prompt methods on the
   router-hosted endpoint.
4. Extend typed `McpStreamableHttpClient` resource/prompt helpers with a
   `directJson` mode and session-header suppression.
5. Run focused analysis/tests, then full local verification before handoff.
6. Push and inspect hosted GitHub deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused checks passed on 2026-05-04:
  `dart analyze packages/connectanum_client packages/connectanum_router`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`.
- Full local `bin/verify` passed on 2026-05-04 after the direct JSON
  resource/prompt implementation.

## Decision Log

- 2026-05-04: Keep direct resource/prompt access on the existing router-hosted
  MCP endpoint. This preserves the product direction that the router provides
  MCP when configured, while giving frontend clients direct JSON access to the
  same configured context/prompt surface.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
GitHub deployment-chain evidence are pending.
