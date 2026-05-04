# Exec Plan: MCP Example Verification Gate

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Make the public router-hosted MCP example smoke part of the standard
verification path so consumer-style usage of the package is continuously
proved, not only checked manually during MCP feature work.

## Scope

In scope:

- Add a canonical verification helper that runs
  `packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`
  when a native runtime is available or can be built.
- Wire the helper into `bin/test-fast` and `bin/test-all` so `bin/verify`
  covers the public router-hosted MCP example.
- Preserve existing skip behavior for unsupported hosts or environments that
  have neither Cargo nor `CONNECTANUM_NATIVE_LIB`.

Out of scope:

- New MCP protocol behavior.
- New public examples or public docs.
- Consumer-specific application references.

## Plan

1. Reuse the root native-runtime detection/build helpers.
2. Add one shared shell helper for the router-hosted MCP example smoke.
3. Call the helper from fast and full verification after the native library
   path is normally available.
4. Run the example smoke directly, then `bin/test-fast` and `bin/verify`.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused smoke helper check passed on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_router_hosted_mcp_example_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-04 and included the
  router-hosted MCP example smoke gate.
- Full local `bin/verify` passed on 2026-05-04 and included the same gate
  through `bin/test-all`.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
evidence are pending.
