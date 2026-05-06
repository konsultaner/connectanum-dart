# Exec Plan: MCP Consumer Custom Header Smoke

## Goal

Upgrade the generated consumer-package smoke so router-hosted MCP custom
parameter headers are proven from a temporary downstream package using only
public package APIs. The smoke should register a header-annotated tool, discover
it through `McpStreamableHttpClient.listTools()`, and call it through
Streamable MCP so the package client must emit matching `Mcp-Param-*` headers.

## Scope

- Add `x-mcp-header` annotations to the neutral WAMP-backed procedure exposed by
  the generated consumer package smoke.
- Pass a wrapper-shaped string argument through the public Streamable client so
  the smoke proves the base64 wrapper ambiguity path as well as ordinary
  primitive custom headers.
- Keep direct JSON compatibility covered by the existing direct-call path.
- Bundle this plan with the implementation and the already pending hosted
  evidence bookkeeping from the previous MCP custom-header slice.

## Non-Goals

- Adding a public example or package README material.
- Changing router-hosted MCP semantics beyond the generated smoke coverage.
- Adding private downstream application references.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- Focused verification passed on 2026-05-06:
  - `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`
- Post-change `bin/test-fast` passed on 2026-05-06.
- Full `bin/verify` passed on 2026-05-06, including formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  and generated consumer package smoke, full router package tests, zero-copy
  router checks, and Chrome Dart2Wasm WebSocket transport tests.

## Status

- 2026-05-06: Started after hosted evidence for `255c990` was clean. The next
  slice is generated consumer-package smoke coverage for custom MCP parameter
  headers.
- 2026-05-06: Implementation and full local verification are complete. Hosted
  evidence is pending after push.
