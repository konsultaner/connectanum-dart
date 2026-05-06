# Exec Plan: MCP Direct WAMP Helpers After Streamable Init

## Goal

Prove that consumer applications can use lifecycle-free direct JSON WAMP
meta/pub-sub helpers on the same client that already owns a Streamable MCP
session, without leaking Streamable session headers or mutating session event
state.

## Scope

- Add client regression coverage for direct JSON WAMP API and pub/sub helpers
  after Streamable initialization, asserting requests omit `Mcp-Session-Id`
  and `Last-Event-ID` while preserving the existing client session state.
- Extend `run_mcp_consumer_package_smoke` so the generated consumer package
  performs direct JSON WAMP meta discovery and pub/sub after Streamable
  initialization, before continuing normal Streamable tool calls.
- Bundle the pending hosted-evidence bookkeeping from the previous checkpoint
  with this implementation commit.

## Non-Goals

- Changing router-hosted MCP protocol semantics.
- Adding application-specific downstream references.
- Reworking public docs beyond project-state evidence for this implementation
  checkpoint.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- `bash -n bin/common.sh` passed on 2026-05-06.
- Focused client regression passed on 2026-05-06:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "keeps direct WAMP helpers lifecycle-free with an active Streamable session"`.
- Full MCP client test file passed on 2026-05-06:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
- Focused analyze passed on 2026-05-06:
  `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`.
- Focused generated consumer-package smoke passed on 2026-05-06:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-06, including the new client
  regression and the updated generated consumer package smoke.
- Full `bin/verify` passed on 2026-05-06, including formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  and generated consumer package smoke, full router package tests, zero-copy
  router checks, and Chrome Dart2Wasm WebSocket transport tests.
- Hosted evidence pending.

## Status

- 2026-05-06: Started after the consumer direct-catalog smoke reached clean
  hosted evidence. The next downstream-readiness gap is proving direct WAMP
  meta/pub-sub helper calls remain lifecycle-free when mixed with an active
  Streamable session.
- 2026-05-06: Complete locally. The client regression now asserts direct JSON
  WAMP helpers omit Streamable session and event headers while preserving
  client session state, and the generated consumer package smoke now exercises
  direct WAMP meta discovery plus pub/sub after Streamable initialization
  before continuing normal Streamable tool calls. Hosted evidence is pending.
