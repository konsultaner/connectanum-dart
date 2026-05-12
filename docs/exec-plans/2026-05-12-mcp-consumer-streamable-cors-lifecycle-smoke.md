# Exec Plan: MCP Consumer Streamable CORS Lifecycle Smoke

Status: implementation complete locally; hosted CI and deployment-chain evidence pending
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

Implementation and local verification are complete. Hosted CI and
deployment-chain evidence are pending until the implementation commit is pushed.
