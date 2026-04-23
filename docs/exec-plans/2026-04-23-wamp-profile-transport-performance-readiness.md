# Exec Plan: WAMP Profile Transport Performance Readiness

## Status

Queued behind `docs/exec-plans/2026-04-23-mcp-support-groli-app.md`.

## Goal

After the first usable MCP server/bridge path is complete, make the
WAMP-profile transport benchmark surface production-ready enough to support
release decisions for real RawSocket/WebSocket WAMP users.

## Priority

- Keep the CI chain green first.
- Finish the active MCP milestone before starting this plan unless CI or a
  shipped-path blocker requires WAMP benchmark work sooner.
- Treat this as production-readiness work, not speculative performance
  exploration.
- Defer unrelated HTTP/3, kTLS, E2EE, and broad benchmark exploration until the
  WAMP-profile transport gates are credible.

## Scope

- Define the canonical WAMP transport scenarios that count for release
  readiness: RawSocket, WebSocket, cleartext, TLS, native client, Dart client,
  JSON, MessagePack, CBOR, RPC, pub/sub, auth/session setup, mixed serializer,
  PPT payload mode, and representative fan-out/control paths.
- Decide which existing scenarios should be smoke gates versus throughput
  gates, and remove or rename ambiguous artifacts that look meaningful but are
  not release-decision inputs.
- Add explicit scenario-specific throughput and latency budgets through the
  bench artifact gate rather than relying on raw summaries.
- Record local Darwin and hosted Linux baselines for the canonical scenarios.
- Make regressions actionable: every failed budget should point to a transport,
  serializer, workload family, and likely owner path.
- Keep docs human-readable so users can understand what "production-ready WAMP
  transport performance" means without reading raw JSON artifacts.

## Non-Goals

- Reopening speculative HTTP/3 queue-depth experiments.
- Treating every benchmark scenario as a CI gate.
- Optimizing rare WAMP profile edge cases before the canonical RawSocket and
  WebSocket release paths have credible budgets.
- Replacing WAMP conformance work; this plan is performance and benchmark
  readiness, not protocol-correctness coverage.

## Candidate Inputs

- `native/bench/scenarios/wamp_transport_throughput.toml`
- `native/bench/scenarios/wamp_client_impl_throughput.toml`
- `native/bench/scenarios/wamp_secure_throughput.toml`
- `native/bench/scenarios/wamp_payload_mode_throughput.toml`
- `native/bench/scenarios/wamp_mixed_serializer_throughput.toml`
- `native/bench/scenarios/wamp_publish_fanout_throughput.toml`
- `native/bench/scenarios/wamp_control_smoke.toml`
- `native/bench/artifact_gate/`

## Verification Plan

- Run `bin/test-fast` before code or benchmark-gate changes.
- Validate artifact policy parsing with focused `native/bench` tests.
- Run canonical WAMP bench scenarios locally when budgets change.
- Dispatch hosted Linux validation for the canonical scenario set before
  declaring the plan complete.
- Run `bin/verify` before handoff and watch hosted CI after pushes.

## First Slice

- Inventory existing WAMP scenarios and mark each as smoke, throughput,
  diagnostic, or obsolete.
- Pick the smallest release-decision gate set.
- Add or adjust artifact policies for that gate set, starting with budgets that
  reflect current known local and hosted baselines rather than aspirational
  targets.
