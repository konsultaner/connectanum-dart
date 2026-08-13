# MCP Official SDK Pub/Sub Smoke

Status: completed

## Goal

Prove that a neutral consumer can complete router-provided WAMP pub/sub through
standard MCP `tools/call` operations with the pinned official TypeScript SDK on
public and bearer-protected endpoints across legacy and modern protocol eras.

## Context

The packaged Router Image already proves official SDK authentication, legacy
session termination, modern sessionlessness, catalogs, resource reads, and a
read-only WAMP-backed tool. Its independent official-client evidence does not
yet prove the stateful pub/sub helpers that a downstream application uses to
subscribe, publish, poll, and release router-backed topic ownership.

The MCP 2026 tools contract recommends that stateful tools return an explicit
handle which the client supplies to later calls because modern MCP has no
protocol session. The official TypeScript client exposes `structuredContent`
from `callTool()` as the machine-readable result. The smoke will therefore
carry the returned opaque handle across separate calls instead of depending on
private state or parsing display text.

References:

- <https://modelcontextprotocol.io/specification/2026-07-28/server/tools>
- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/client.md>

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run workflow,
   Serena, overlap, both-roadmap, exact-head CI, and pre-change verification.
2. Add a fail-first Router Image contract for official-client subscribe,
   acknowledged self-delivered publish, explicit-handle poll, and unsubscribe.
3. Extend the tracked official-client smoke through that lifecycle for public
   and protected legacy and modern endpoints, validating structured results and
   cleaning up subscriptions before legacy session termination.
4. Add bounded Router Image evidence markers without exposing handles,
   publication IDs, bearer credentials, or event payloads.
5. Run focused live and full verification, strict package and privacy checks,
   record the durable Serena convention, publish both maintained remotes, and
   audit exact-head GitHub CI and Router Image deployment evidence.

## Progress

- 2026-08-13: Repository workflow, required skill, Serena, overlap,
  completed-plan, both-roadmap, exact-head CI, and worktree preflights pass.
  The only startup edits are the preceding completed checkpoint's expected
  hosted-evidence notes; no unrelated same-repository editor exists.
- 2026-08-13: Official MCP tools guidance confirms that stateful tools should
  return an explicit handle for subsequent calls in modern sessionless MCP,
  and the official client exposes structured tool results for machine use.
- 2026-08-13: Pre-change `bin/test-fast` passes the complete fast regression,
  live WAMP integration, generated-consumer, and package smoke matrix.
- 2026-08-13: The fail-first official-client Router Image contract fails on
  all missing pub/sub source and evidence markers, then all 30 contracts pass
  after implementation. Shell and Node syntax checks pass.
- 2026-08-13: An independent live native-router probe with the pinned official
  SDK 2.0.0 passes public and protected legacy and modern lifecycles. Every run
  discovers all four tools, carries the structured subscribe handle, receives
  its acknowledged self-delivered event without drops, and unsubscribes.
  Protected runs still recover from exactly one HTTP 401; legacy sessions are
  terminated and modern runs remain sessionless.
- 2026-08-13: Final `bin/verify` passes formatting, Rust core and FFI, all Dart
  package tests, native and browser coverage, generated and globally activated
  consumer smokes, the 97-case benchmark suite, and all 439 router tests.
  Strict release-ready dry-runs validate all seven synchronized `3.0.0-beta`
  archives with zero warnings. Public-artifact, credential-output, and diff
  checks pass. Publication and exact-head hosted evidence remain.
