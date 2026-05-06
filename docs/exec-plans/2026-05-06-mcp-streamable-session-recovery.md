# Exec Plan: MCP Streamable Session Recovery

## Goal

Make the public Streamable HTTP MCP client recover cleanly when a router-hosted
MCP session is terminated or otherwise unknown, so downstream applications do
not keep resending a stale `MCP-Session-Id`.

## Scope

- Clear the client-side MCP session id and SSE cursor after HTTP `404 Not
  Found` responses that indicate the server no longer recognizes the session.
- Ensure `initialize` starts a fresh Streamable HTTP lifecycle without sending
  any previously stored `MCP-Session-Id`.
- Cover the behavior with the fake MCP endpoint tests in
  `packages/connectanum_client`.
- Add real router-hosted MCP coverage proving stale sessions fail once, clear
  client state, and allow a clean re-initialize through public APIs.

Out of scope:

- OAuth discovery or scope-step-up support.
- Changing the existing JSON-RPC batch compatibility behavior.
- Adding new MCP server feature families such as tasks or elicitation.

## Plan

1. Record the active plan and preserve the existing docs-only hosted-CI notes.
2. Patch `McpStreamableHttpClient` session handling for initialize and `404`
   responses.
3. Add focused client tests for POST/GET/DELETE stale-session paths.
4. Extend router-hosted MCP integration coverage for real stale-session
   recovery.
5. Run focused client/router tests, then `bin/verify` before handoff.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- Passed on 2026-05-06 after implementation:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
- Passed on 2026-05-06 after implementation:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "isolates MCP Streamable HTTP sessions by route and bearer principal"`.
- Passed on 2026-05-06 after implementation:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Full local `bin/verify` passed on 2026-05-06, including formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  smoke, generated consumer package smoke, full router package tests,
  zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
- Hosted GitHub evidence for `eff3b10` is clean: `CI` run `25431647686`
  completed successfully with `Fast Checks` and `Full Verify`, `Dart Package
  Publish Dry Run` run `25431647641` completed successfully, and `WAMP Profile
  Benchmarks` run `25431647607` completed successfully.
- Public check-run annotation audit found zero GitHub annotations for the
  `Fast Checks`, `Full Verify`, `Publish Dry Run`, and `Linux WAMP profile
  gates` check runs. Raw hosted log download remained blocked in this
  environment because GitHub returned `Must have admin rights to Repository`
  and no GitHub token was present.

## Handoff

Complete. Local verification and hosted GitHub evidence are clean.
