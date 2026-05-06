# Exec Plan: MCP Consumer Direct Catalog Smoke

## Goal

Prove from the generated consumer package smoke that a downstream application
can discover a router-hosted MCP tool catalog through lifecycle-free direct JSON
and then call the discovered tool through Streamable MCP with custom
`Mcp-Param-*` headers.

## Scope

- Extend `run_mcp_consumer_package_smoke` so the generated package performs a
  direct JSON `connectanum.tools.list` discovery after Streamable session
  initialization but before its first Streamable `tools/call`.
- Assert the direct catalog still sees the expected tool without changing
  Streamable session state.
- Keep the existing direct JSON, Streamable, pub/sub, resources, prompts, auth,
  and session lifecycle smoke coverage intact.
- Bundle the pending hosted-evidence bookkeeping from the previous checkpoint
  with this implementation commit.

## Non-Goals

- Changing router-hosted MCP protocol semantics.
- Adding private downstream application references.
- Adding public docs before the smoke and verification evidence are clean.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-06.
- `bash -n bin/common.sh` passed on 2026-05-06.
- Focused generated consumer-package smoke passed on 2026-05-06:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-06, including the updated
  generated consumer package smoke.
- Full `bin/verify` passed on 2026-05-06, including formatting, Rust
  native/FFI tests, Python package-artifact checks, MCP package tests, client
  tests, auth-server tests, bench integration tests, router-hosted MCP example
  and generated consumer package smoke, full router package tests, zero-copy
  router checks, and Chrome Dart2Wasm WebSocket transport tests.
- Hosted evidence pending for this implementation checkpoint.

## Status

- 2026-05-06: Started after the direct catalog header-cache client slice reached
  clean hosted evidence. The next downstream-readiness gap is proving the same
  mixed direct-catalog-to-Streamable-call flow in the generated consumer
  package smoke.
- 2026-05-06: Completed locally. The generated consumer package now discovers
  router-hosted tools through direct JSON after Streamable initialization,
  asserts that discovery does not mutate Streamable session state, and then
  performs the first Streamable tool call using the direct catalog cache before
  running the existing Streamable catalog, batch, resources, prompts, pub/sub,
  auth, and session lifecycle coverage. Hosted evidence is pending.
