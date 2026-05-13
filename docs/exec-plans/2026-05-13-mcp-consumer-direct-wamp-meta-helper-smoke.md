# Exec Plan: MCP Consumer Direct WAMP Meta Helper Smoke

Status: active; full local verification passing
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Problem

The generated consumer-package router-hosted MCP smoke proves raw direct
JSON-RPC access to WAMP session, registration, and subscription metadata, but
it does not yet prove that a neutral consumer application can use the public
dedicated direct WAMP meta helper APIs against the router-provided MCP
endpoint. That leaves downstream application readiness dependent on example
coverage instead of package-boundary smoke evidence.

## Scope

- Add generated consumer-package smoke coverage for direct WAMP session,
  registration, and subscription meta helper APIs.
- Assert those direct helper calls remain lifecycle-free and do not mutate an
  active Streamable HTTP session id or SSE cursor.
- Keep the existing raw direct JSON-RPC and batch metadata coverage in place.

## Non-Goals

- Changing MCP wire protocol behavior.
- Removing raw JSON-RPC access coverage.
- Changing public package metadata or release automation.

## Milestones

- Baseline `bin/test-fast` passed on 2026-05-13 before implementation.
- Generated consumer-package router-hosted MCP smoke now calls the dedicated
  direct WAMP session, registration, and subscription meta helper APIs while
  keeping raw generic direct JSON-RPC and batch coverage.

## Verification

- `bin/test-fast` passed before edits on 2026-05-13.
- `bash -n bin/common.sh` passed on 2026-05-13.
- `run_mcp_consumer_package_smoke` passed on 2026-05-13, including generated
  package `dart analyze` and router-hosted MCP runtime smoke.
- `git diff --check` passed on 2026-05-13.
- Full local `bin/verify` passed on 2026-05-13.

## Decision Log

- Generated consumer-package smokes should prove public helper APIs from a
  package-boundary app, while raw direct JSON-RPC coverage remains responsible
  for envelope, batch, and generic JSON-RPC behavior.

## Handoff

Implementation is complete and full local verification is passing. Commit,
push, and hosted evidence are pending.
