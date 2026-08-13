# MCP Official SDK Agent Context Smoke

Status: active

## Goal

Prove that a neutral agent host can consume the router-provided instructions and
render a configured prompt through the pinned official TypeScript SDK on public
and bearer-protected endpoints across legacy and modern protocol eras.

## Context

The packaged Router Image already proves official SDK negotiation,
authentication, catalogs, static resource reads, a WAMP-backed tool call, and a
complete router-provided pub/sub lifecycle. It only enumerates the configured
prompt, however. A consumer application still lacks independent evidence that
the advertised prompt can be rendered with arguments and supplied to a model,
or that the router instructions survive negotiation.

The official client exposes `getInstructions()` after connection and
`getPrompt()` for rendering an advertised prompt. The smoke will validate the
configured neutral text without printing prompt contents, credentials, or
protocol/session identifiers beyond the existing bounded summary.

References:

- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/client.md>
- <https://modelcontextprotocol.io/specification/2026-07-28/server/prompts>

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run workflow,
   Serena, overlap, both-roadmap, exact-head CI, and pre-change verification.
2. Add a fail-first Router Image contract for official-client instructions and
   argument-bearing prompt rendering.
3. Extend the tracked official-client smoke through those operations for public
   and protected legacy and modern endpoints while retaining all existing
   catalog, resource, tool, pub/sub, auth, and session assertions.
4. Add bounded Router Image evidence markers without exposing instructions,
   prompt messages, bearer credentials, pub/sub handles, or event payloads.
5. Run focused live and full verification, strict package and privacy checks,
   record durable Serena guidance, publish both maintained remotes, and audit
   exact-head GitHub CI and Router Image deployment evidence.

## Progress

- 2026-08-13: Repository workflow, required skill, Serena, overlap,
  completed-plan, both-roadmap, and worktree preflights pass. The only startup
  edits are the preceding completed checkpoint's expected hosted-evidence
  notes; no unrelated same-repository editor exists.
- 2026-08-13: Official TypeScript client guidance confirms that agent hosts use
  `getInstructions()` after connection and `getPrompt()` with arguments to
  render reusable prompt messages.
- 2026-08-13: Pre-change `bin/test-fast` passes the complete fast regression,
  live WAMP integration, generated-consumer, and package smoke matrix.
- 2026-08-13: The fail-first Router Image contract reports the five missing
  source and evidence assertions. Node and shell syntax checks plus all 30
  focused Router Image contracts pass after implementation.
- 2026-08-13: An independent live native-router probe with the pinned official
  SDK 2.0.0 passes public and protected legacy and modern lifecycles. Every run
  receives the configured instructions, renders `inspect-router-image` with a
  client-selected argument, and retains the catalog, static resource, WAMP
  tool, structured pub/sub, auth-retry, and session-era assertions. The smoke
  output keeps instructions and rendered prompt contents private.
- 2026-08-13: Final `bin/verify` passes formatting, Rust core and FFI, all Dart
  package tests, native and browser coverage, generated and globally activated
  consumer smokes, the 97-case benchmark suite, and all 439 router tests. The
  post-verification 30-case Router Image contract, Node/shell syntax, privacy,
  and diff checks pass. Strict release-ready dry-runs validate all seven
  synchronized `3.0.0-beta` archives with zero warnings and no private
  workspace dependency blockers. Publication and exact-head hosted evidence
  remain.
