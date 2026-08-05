# MCP Client Terminal Close

Status: complete

## Goal

Make `McpStreamableHttpClient.close()` a terminal lifecycle boundary that
rejects new network work on that client while preserving a caller-owned
`HttpClient` for use by a newly constructed replacement MCP client.

## Context

Close currently cancels client-owned requests, response-body readers, modern
listeners, and session state, but the same client instance can start new MCP
requests and listeners afterward when its transport is caller-owned. That can
recreate session or authorization activity after an application has completed
shutdown. The ordinary MCP request path, modern listener path, and instance
OAuth network helpers need the same terminal lifecycle contract. Pure local
authorization-request construction and explicit local state mutation remain
outside this network boundary.

## Plan

1. Run the pre-change fast suite and add fail-first regressions for ordinary
   requests, modern listeners, and OAuth discovery after close.
2. Add one deterministic closed-state guard across all new client network work
   while retaining the existing close-race cancellation paths.
3. Prove repeated close remains safe and a replacement MCP client can reuse the
   same caller-owned HTTP transport.
4. Extend the neutral client-only consumer-package smoke, then run focused
   analysis/tests and `bin/verify`.
5. Update project state, commit and push the implementation with its evidence,
   then audit the exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast`: passed on 2026-08-05.
- Fail-first regressions reproduced a closed client sending a direct request,
  allocating and establishing a new listener, and performing OAuth protected
  resource discovery.
- Focused client analysis, all 161 Streamable HTTP client tests, and the
  complete 241-case MCP/client suite pass.
- The neutral client-only consumer-package smoke passes from source and
  through the globally activated public package command. It requires direct
  requests, listeners, and OAuth discovery to remain local after close, then
  proves a replacement client can reuse the caller-owned HTTP transport.
- `bash -n bin/common.sh`, the public-artifact reference guard, and
  `git diff --check` pass.
- Full `bin/verify`: passed on 2026-08-05. Verification covered 113 Rust core
  tests, 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the complete
  241-case MCP/client suite, all 96 benchmark tests including 36 live WAMP
  workloads, all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and
  every isolated and globally activated consumer/CLI smoke.
- Hosted exact-head deployment audit: passed. Commit `d0cd1c0c` is on both
  maintained `master` branches. GitHub CI `31051953413`, Dart Package Publish
  Dry Run `31051954139`, WAMP Profile Benchmarks `31051953192`, and Router
  Image dry run `31053156773` passed. Coverage artifact `8949174172`, WAMP
  artifact `8948847968`, Router Image preview artifact `8949213785`, and Docker
  build records `8949295252` and `8949294843` were uploaded. The comprehensive
  strict deployment-chain audit passes with clean exact-head CI logs,
  loaded-image MCP runtime smoke, multi-architecture image build, and all
  required branch, workflow, package, native-release, publish-dry-run,
  benchmark, and registry gates clean. Release-candidate readiness remains
  intentionally non-gating until an approved numeric RC tag points at the
  release commit.

## Outcome

Client close now permanently rejects new ordinary requests, MCP 2026
listeners, and OAuth network helpers on that instance. Repeated close is safe,
listener rejection occurs before a dedicated transport is allocated, and a
caller-owned HTTP transport remains open for a replacement MCP client. Local
authorization-request construction and explicit local state mutation retain
their non-network semantics. Local implementation and package verification is
complete, and exact-head hosted workflow and deployment-audit evidence is clean
at implementation commit `d0cd1c0c`.
