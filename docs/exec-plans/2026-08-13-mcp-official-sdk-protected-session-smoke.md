# MCP Official SDK Protected Session Smoke

Status: completed

## Goal

Prove that a neutral protected router-hosted MCP endpoint works through the
official TypeScript SDK's bearer-provider retry contract across legacy
sessionful and modern sessionless protocol negotiation.

## Context

The packaged Router Image now proves public endpoint interoperability with
`@modelcontextprotocol/client` 2.0.0, while protected route behavior is covered
only by the Dart package client and raw probes. The official SDK's minimal
`AuthProvider` obtains a bearer token before every request, calls
`onUnauthorized` after HTTP 401, and retries once. Its Streamable HTTP guidance
also requires clients to terminate a legacy server-side session explicitly;
modern negotiation must remain sessionless.

References:

- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/client.md#authentication>
- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/clients/connect.md#disconnect-cleanly>
- <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization>

## Plan

1. Preserve the completed cache-contract checkpoint's hosted-evidence notes and
   run workflow, Serena, overlap, both-roadmap, exact-head CI, and pre-change
   fast-verification checks.
2. Extend the tracked official-client smoke to obtain a router-issued bearer
   grant without logging credentials, begin each protected connection with a
   rejected token, and prove the SDK's single 401 refresh/retry path.
3. Cover both legacy sessionful and modern sessionless protected negotiation,
   all catalogs, resource read, WAMP-backed tool use, and explicit legacy
   session termination through the official transport.
4. Strengthen the generated Router Image smoke-contract tests and bounded
   evidence markers for the new protected behavior.
5. Run focused and full verification, strict package validation, privacy and
   diff review, record the durable Serena convention, publish both maintained
   remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, required skill, Serena, overlap,
  completed-plan, both-roadmap, exact-head CI, and worktree preflights pass.
  The only startup edits are the completed cache-contract checkpoint's expected
  hosted-evidence notes; the scheduled wrapper and child Codex process belong
  to this run, and no unrelated same-repository editor exists.
- 2026-08-13: Official SDK documentation confirms that a minimal
  `AuthProvider` supplies the bearer token per request, receives HTTP 401
  through `onUnauthorized`, and is retried once. The maintained disconnect
  guidance separately requires explicit termination of legacy Streamable HTTP
  sessions, while a modern negotiated connection has no protocol session.
- 2026-08-13: The tracked official-client smoke now obtains a neutral
  router-issued ticket grant without printing it, starts each protected
  connection with a rejected bearer, proves exactly one `onUnauthorized`
  callback replaces that credential, and exercises all catalogs, a resource
  read, and a WAMP-backed tool call through both maintained protocol eras.
  Legacy runs explicitly call `terminateSession()` and prove the SDK clears
  its session ID; modern runs prove no session ID is established.
- 2026-08-13: Shell and Node syntax checks, the 30-case generated Router Image
  smoke-contract suite, credential-output guards, and an independent live
  native-router probe all pass. The live probe proves public and protected
  legacy session creation/termination plus public and protected modern
  sessionlessness; both protected runs recover from exactly one HTTP 401.
- 2026-08-13: Pre-change `bin/test-fast` and final `bin/verify` pass the full
  Rust, Dart, generated-consumer, FFI, router, browser, packaging, and benchmark
  matrix. Strict release-ready dry-runs validate all seven synchronized
  `3.0.0-beta` archives with zero warnings, and the public-artifact reference
  and diff checks pass. Publication and exact-head hosted evidence remain.
- 2026-08-13: Commit `2f7b4b13` is published to GitLab and GitHub. Exact-head
  CI `31712403688` passes Fast Checks, Full Verify, Dart VM Coverage, Codecov,
  and coverage artifact `9186471498`. Router Image dry run `31712410969`
  passes on its first attempt with preview artifact `9185824668` and Docker
  build records `9185845897` and `9185845065`; its loaded-image log explicitly
  proves SDK 2.0.0 public/protected use, bearer retry, legacy session creation
  and termination, modern sessionlessness, all catalogs, resource read, and
  WAMP-backed tool use.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI logs and every required package, Router Image, WAMP,
  relevant Native Artifacts, protected-branch, workflow-visibility, and public
  router-package gate ready. The last Dart Package Publish Dry Run
  `31705829385` and WAMP Profile Benchmarks `31705829401` remain relevant
  because this checkpoint changed no package or benchmark-sensitive inputs.
