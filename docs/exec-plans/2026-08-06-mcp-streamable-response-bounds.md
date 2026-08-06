# MCP Streamable HTTP Response Bounds

Status: complete; local and hosted deployment-chain evidence clean

## Goal

Prevent ordinary MCP Streamable HTTP responses from consuming unbounded memory
before JSON or SSE validation while preserving compatibility for normal tool,
resource, prompt, pub/sub, and session lifecycles.

## Context

OAuth token, registration, and metadata helpers already apply explicit response
limits. The main Streamable HTTP client instead buffers POST, GET, and DELETE
response bodies without a byte cap. A hostile or misconfigured router can
therefore grow a downstream application's memory use before the client rejects
the response content.

This checkpoint adds a configurable raw-byte limit to buffered ordinary
responses. The limit must apply consistently across public constructors and
must cancel an oversized response without mutating established MCP session or
resume state. Long-lived request-scoped listener streams are intentionally
outside this buffering limit because they are consumed incrementally.

## Plan

1. Preserve the green fast-suite baseline and add fail-first local-server
   regressions for oversized, exact-boundary, and invalid-limit behavior.
2. Add a compatibility-friendly default raw-byte limit and forward it through
   every public Streamable HTTP client constructor.
3. Count raw response bytes before UTF-8 decoding, cancel oversized response
   streams, return a typed protocol failure, and preserve client state.
4. Run focused package analysis and tests, `bin/test-fast`, and `bin/verify`.
5. Bundle the implementation with milestone records, push both maintained
   branches, and audit the exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast` passed on 2026-08-06 with 360 core tests, all 94
  MCP tests, the complete 257-case MCP/client suite, all 96 benchmark and live-
  router tests, every neutral package/consumer smoke, the router CLI MCP
  lifecycle matrix, and focused native/router regressions.
- Three fail-first regressions failed to compile because no response-bound API
  existed. They now prove oversized POST, GET, and DELETE bodies return the
  typed limit failure without clearing active session or resume state, an exact
  multibyte UTF-8 boundary succeeds, invalid limits are rejected, and all seven
  public constructors forward the configured value.
- `dart analyze packages/connectanum_client packages/connectanum_mcp` and all
  168 focused Streamable HTTP cases pass.
- Post-change `bin/test-fast` passes with 360 core tests, all 94 MCP tests, the
  complete 260-case MCP/client suite, all 96 benchmark/live-router tests, every
  neutral generated and globally activated package/consumer smoke, the router
  CLI MCP lifecycle matrix, and focused native/router regressions.
- Final exact-code `bin/verify` passes with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core,
  94 MCP, 260 MCP/client, 96 benchmark/live-router, and 387 router tests; all 13
  focused native-forwarding regressions; every neutral consumer package and
  CLI smoke; and Chrome Dart2Wasm WebSocket coverage.
- Implementation commit `d8071919` is on both maintained `master` branches.
  Exact-head GitHub CI `31090133222`, Dart Package Publish Dry Run
  `31090133381`, WAMP Profile Benchmarks `31090133069`, and Router Image dry
  run `31091444072` passed on their first attempts. CI uploaded coverage
  artifact `8963555998`, WAMP uploaded benchmark artifact `8963271885`, and
  Router Image uploaded preview artifact `8963617527` plus Docker build records
  `8963722690` and `8963723322`.
- The comprehensive strict deployment-chain audit exited zero with clean
  exact-head CI logs, package and native-release dry-run evidence, the loaded-
  image MCP runtime smoke, the multi-architecture image build, the WAMP profile
  gate, workflow visibility, branch protection, and the public router package
  all ready. A numeric release-candidate tag remains an explicit release-
  approval action outside this checkpoint.

## Outcome

Ordinary buffered MCP Streamable HTTP POST, GET, and DELETE responses now have
a configurable raw-byte bound across every public client constructor. An
oversized body is cancelled with a typed protocol failure without disturbing
active session or resume state, exact UTF-8 byte boundaries remain valid, and
the same client and transport recover for later requests. Local verification,
both maintained branches, and the exact-head hosted deployment chain are clean.
