# MCP Official SDK Cache Contract

Status: completed

## Goal

Make router-hosted MCP's modern `2026-07-28` responses satisfy the official
cacheable-result contract and prove that a neutral consumer can negotiate and
use the packaged router with the official MCP TypeScript client SDK.

## Context

The router already negotiates the modern, sessionless protocol era and adds
`resultType` plus server metadata to successful responses. The official
`@modelcontextprotocol/client` 2.0.0 SDK can connect and discover the router,
but rejects the first `tools/list` response because its modern result lacks the
required `ttlMs` and `cacheScope` fields. The 2026-07-28 MCP caching contract
requires those hints for complete results from `server/discover`, all four
catalog list methods, and `resources/read`. Router catalogs and resource data
can vary by authorization context, so their cache hints must not permit sharing
across credentials.

References:

- <https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching>
- <https://modelcontextprotocol.io/specification/2026-07-28/server/tools>
- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/clients/connect.md>

## Plan

1. Preserve the completed protocol-version checkpoint's hosted-evidence notes
   and run the workflow, Serena, overlap, both-roadmap, exact-head CI, and
   pre-change fast-verification checks.
2. Add fail-first native-router coverage for every modern cacheable result and
   demonstrate the current official SDK validation failure independently.
3. Add conservative, authorization-safe cache hints only to successful complete
   modern results whose methods are cacheable under the protocol.
4. Add a pinned, isolated official MCP TypeScript SDK smoke to the packaged
   Router Image runtime evidence, covering legacy and modern negotiation plus a
   real tool call without relying on repository-private client assumptions.
5. Run focused and full verification, strict package validation, privacy and
   diff review, record the durable Serena convention, publish both maintained
   remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, completed-plan,
  both-roadmap, exact-head CI, and worktree preflights passed. The only startup
  changes are the completed protocol-version checkpoint's expected hosted
  evidence notes; the scheduled wrapper and its child Codex process belong to
  this run, and no unrelated same-repository editor exists.
- 2026-08-13: An isolated official `@modelcontextprotocol/client` 2.0.0 probe
  proves legacy Streamable HTTP negotiation, catalog access, and session
  establishment. Automatic modern negotiation reaches the router's
  `server/discover` successfully, then fails `tools/list` result validation
  because `ttlMs` and `cacheScope` are absent. Official 2026-07-28 guidance
  requires those hints on six cacheable complete-result methods and defines
  `private` as the safe scope for authorization-dependent results.
- 2026-08-13: Native fail-first coverage reproduces the missing hints, then
  passes across all six cacheable result methods with conservative `ttlMs: 0`
  and `cacheScope: private` defaults that preserve upstream values. The
  tracked, pinned official SDK smoke passes both legacy sessionful and modern
  sessionless negotiation, every catalog, a resource read, and a WAMP-backed
  tool call against a locally launched router.
- 2026-08-13: Focused shell, Node syntax, generated smoke-contract, analyzer,
  native-router, and diff checks pass. `bin/verify` passes the complete Rust,
  Dart, generated-consumer, FFI, router, browser, and benchmark matrix. The
  strict package audit reaches the changed router archive with only its
  expected pre-commit dirty-worktree warning; clean exact-commit validation,
  publication, and hosted Router Image evidence remain.
- 2026-08-13: Commit `d2ae33dd` is published to GitLab and GitHub. Clean
  exact-commit strict validation passes all seven synchronized `3.0.0-beta`
  archives with zero warnings and no private workspace dependency blockers.
- 2026-08-13: Exact-head CI `31705829438`, Dart Package Publish Dry Run
  `31705829385`, WAMP Profile Benchmarks `31705829401`, and Router Image dry
  run `31705855519` pass on their first attempts. The Router Image log
  explicitly proves the official 2.0.0 SDK's legacy sessionful and modern
  sessionless flows plus catalogs, resource read, and WAMP-backed tool call.
  Retained artifacts are Dart VM coverage `9183769722`, WAMP profile evidence
  `9183380866`, Router Image preview `9183142629`, and Docker build records
  `9183296408` and `9183295793`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head jobs/logs and every required package, Router Image, WAMP,
  relevant Native Artifacts, protected-branch, workflow-visibility, and
  public-router-package gate ready. Native Artifacts run `31221315902` remains
  relevant because no native-release-sensitive input changed. A numeric RC tag
  remains release-approval work and was not created.
