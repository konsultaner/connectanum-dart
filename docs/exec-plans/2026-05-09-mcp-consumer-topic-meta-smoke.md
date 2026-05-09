# Exec Plan: MCP Consumer Topic Meta Smoke

Status: complete; local verification clean
Owner: Codex
Created: 2026-05-09
Last updated: 2026-05-09

## Goal

Make the generated consumer package smoke prove that a consumer application can
discover configured WAMP topic metadata, including describe-time event schema
and publish/subscribe capabilities, through both lifecycle-free direct JSON and
initialized Streamable HTTP MCP requests.

## Context

- Current priority is router-hosted MCP and downstream application development
  readiness.
- The public router-hosted MCP example now covers topic metadata discovery.
- The generated consumer package smoke already proves topic catalog visibility,
  but it does not yet describe the configured topic or assert the schema and
  capability fields a consumer application would use for pub/sub planning.

## Scope

- Add schema and metadata to the generated consumer package route topic.
- Extend generated consumer smoke WAMP API metadata checks to call
  `connectanum.api.describe` for the configured topic through direct JSON and
  Streamable HTTP helpers.
- Preserve existing session-state guarantees for lifecycle-free direct JSON
  calls made while Streamable HTTP is active.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Focused generated consumer package smoke passed on 2026-05-09 with isolated
  `TMPDIR` via
  `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
- Full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.

## Decision Log

- Keep this as generated consumer package smoke coverage so package consumers
  prove the metadata path without relying on private project configuration.

## Handoff

Implementation and local verification are complete. Commit, push, and hosted
deployment-chain evidence are pending.
