# MCP Resource Template Subscriptions

Status: completed

## Goal

Let consumer applications subscribe to a concrete URI produced by a readable
router-hosted MCP resource template. Legacy `resources/subscribe` and modern
`subscriptions/listen` must retain route-principal authorization, emit
`notifications/resources/updated` for the concrete URI only, and release or
revoke the underlying WAMP subscription consistently.

## Context

Readable resource templates now resolve concrete URIs through standard MCP and
direct JSON APIs. Resource-update subscription paths still resolve only exact
configured resources, however, so the same concrete template URI is silently
omitted from a modern listen acknowledgment and rejected by legacy subscribe.
Catalog refresh would also revoke such a subscription because it compares only
the exact resource catalog.

MCP resource subscriptions name a concrete resource URI rather than a catalog
entry type. The official TypeScript SDK documents URI-based subscription
bookkeeping for 2025-era connections and URI filters in
`subscriptions/listen` for 2026-era connections. The server must deliver
`notifications/resources/updated` only to the connection or stream that asked
for that URI.

References:

- <https://modelcontextprotocol.io/specification/2025-11-25/server/resources>
- <https://modelcontextprotocol.io/specification/2025-11-25/schema>
- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/servers/resources.md>
- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/migration/support-2026-07-28.md>

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run repository
   workflow, Serena, overlap, both-roadmap, exact-head, and pre-change checks.
2. Add fail-first core and router regressions proving a concrete readable
   template URI is not currently accepted by legacy or modern resource
   subscription paths.
3. Expose bounded core template-match resolution without duplicating URI
   parsing in the router, preserving exact-resource precedence and decoded
   variables.
4. Resolve subscription configuration from exact resources or visible readable
   templates, authorize the configured WAMP update topic, and retain concrete
   URI ownership through refresh, revocation, unsubscribe, and cleanup.
5. Extend neutral consumer and pinned official SDK Router Image evidence across
   public/protected legacy/modern endpoints without exposing resource contents,
   credentials, protocol/session identifiers, or event payloads.
6. Run focused and full verification, strict package/privacy checks, record
   durable Serena guidance, publish both maintained remotes, and audit exact-
   head GitHub CI and Router Image evidence.

## Progress

- 2026-08-13: Repository workflow, required skill, Serena, overlap,
  completed-plan, both-roadmap, exact-head, and worktree preflights pass. The
  only startup edits are the preceding completed checkpoint's expected hosted-
  evidence notes; no unrelated same-repository editor exists.
- 2026-08-13: Official protocol and TypeScript SDK guidance confirms that both
  protocol eras subscribe by concrete resource URI and require filtered
  `notifications/resources/updated` delivery. Current router resolution is
  exact-resource-only in legacy subscribe/unsubscribe, modern listen
  preparation, and catalog-refresh authorization reconciliation.
- 2026-08-13: Pre-change `bin/test-fast` passes, including 20 live router
  tests, 22 generated-consumer tests, all package/native suites, 37 live WAMP
  workloads, and the installed CLI/consumer smoke matrix.
- 2026-08-13: Fail-first core, router integration, and configuration
  regressions reproduced the exact-resource-only boundary. The core registry
  now exposes its deterministic readable-template match, and every router
  subscription and refresh-reconciliation path resolves an exact visible
  resource first or a readable visible template second. Template update topics
  require a read procedure, retain the consumer-selected concrete URI, and use
  the existing route-principal WAMP subscription authorization and cleanup.
- 2026-08-13: The neutral official SDK smoke now subscribes, receives one
  concrete-URI update, and unsubscribes on every public/protected legacy/modern
  client. The focused core and router suites, 30-case Router Image contract,
  analyzers, format, Node/shell syntax, privacy, and diff checks pass.
- 2026-08-13: A local Router Image build cannot reach Docker Hub metadata in
  this shell, including the pinned Dockerfile frontend; no application build
  step starts. `.dockerignore` now excludes Serena and native benchmark build
  caches from the packaged context. The exact-head hosted Router Image dry run
  remains the authoritative built-container and pinned-client check after
  publication.
- 2026-08-13: Full `bin/verify` passes with zero formatting changes. The final
  matrix includes 114 Rust core, 52 Rust FFI, 360 Dart core, 107 MCP, 280
  client/MCP, 97 benchmark, 37 live WAMP workload, 441 router, six remote-auth,
  and 13 native follow-up tests plus every maintained isolated consumer and the
  Chrome Dart2Wasm smoke. A pre-commit strict publish dry-run reports only the
  expected dirty-package warning for the modified MCP package; it will be
  repeated from the implementation commit before publication.
- 2026-08-13: The clean implementation commit passes
  `bin/dart-package-publish-dry-run --strict-release-ready`: all seven
  synchronized `3.0.0-beta` archives validate with zero warnings, no private
  workspace dependency blockers, and every declared executable present.
- 2026-08-13: Implementation commit `3ab636ed` is published to both maintained
  `master` branches. Exact-head CI `31745550079` passes every expected job with
  clean logs and retains coverage artifact `9199364031`; Dart Package Publish
  Dry Run `31745550076` passes; and WAMP Profile Benchmarks `31745550075`
  passes with artifact `9199037390`.
- 2026-08-13: Router Image dry run `31745588742` passes the loaded-image smoke
  with official SDK 2.0.0 evidence for concrete-template subscribe, update,
  and unsubscribe across public/protected legacy/modern clients. It skips GHCR
  login and retains preview artifact `9198847546` plus Docker build records
  `9199010201` and `9199009250`. The comprehensive strict deployment-chain
  audit exits zero with every required gate ready; RC publication remains
  intentionally ungated because no release was requested.
