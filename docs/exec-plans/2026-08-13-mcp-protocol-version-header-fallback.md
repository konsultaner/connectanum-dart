# MCP Protocol-Version Header Fallback

Status: completed

## Goal

Make router-hosted MCP treat a missing `MCP-Protocol-Version` header as
protocol revision `2025-03-26`, while preserving initialize-body negotiation,
explicit supported-version echoing, authentication, claimed-session lookup,
and the strict `2026-07-28` request-metadata boundary.

## Context

The router supports `2025-03-26`, `2025-06-18`, `2025-11-25`, and the modern
`2026-07-28` revision. Unsupported explicit headers fail closed, and initialize
responses already align their header with the version negotiated from the JSON
body. For non-initialize requests without a version header, however, the router
currently labels responses with the latest session revision, `2025-11-25`.
Official Streamable HTTP compatibility guidance says servers supporting clients
from before the header was defined may treat an omitted header as
`2025-03-26`. This checkpoint makes that fallback explicit and reusable without
weakening the required header and mirrored metadata validation for modern
requests.

References:

- <https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>
- <https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http>

## Plan

1. Preserve the completed content-type checkpoint's hosted-evidence notes and
   run the workflow, Serena, overlap, both-roadmap, exact-head CI, and
   pre-change fast-verification checks.
2. Add fail-first native-router regressions for missing-header public,
   protected, and claimed-session traffic, while retaining initialize-body and
   explicit-header behavior.
3. Add one shared protocol fallback constant and use it for router response and
   error envelopes when the request header is absent.
4. Extend the neutral generated consumer package smoke with a raw missing-header
   probe that proves the fallback and continued direct JSON/Streamable use.
5. Run focused and full verification, strict package validation, privacy and
   diff review, record the durable Serena convention, publish both maintained
   remotes, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, completed-plan,
  both-roadmap, exact-head CI, and worktree preflights passed. The only startup
  changes are the completed content-type checkpoint's expected hosted-evidence
  notes; the scheduled wrapper, child Codex process, and live runlock belong to
  this run, and no unrelated same-repository editor exists.
- 2026-08-13: Official stable and draft Streamable HTTP guidance identifies
  `2025-03-26` as the compatibility interpretation for a missing
  `MCP-Protocol-Version` header. Pre-change `bin/test-fast` passed the complete
  fast matrix, including all 20 generated-consumer contracts, 37 live WAMP
  workloads, and every neutral consumer and installed-command smoke.
- 2026-08-13: The fail-first native regression received
  `MCP-Protocol-Version: 2025-11-25` for a successful headerless direct request
  instead of the required `2025-03-26` fallback. The public MCP package now
  exports one fallback constant, the router derives response/error versions
  from an explicit supported request header or that fallback, and pre-route
  rate-limit/transport-auth rejections use the same derivation without
  trusting a claimed session.
- 2026-08-13: Focused MCP lifecycle and native-router regressions pass. They
  cover headerless public direct JSON, active and unknown claimed sessions,
  missing and unknown bearer credentials, initialize-body negotiation, and
  continued explicit-version behavior. Router and MCP analysis, shell syntax,
  all 20 generated-consumer boundary contracts, and the freshly sourced
  neutral installed-router consumer smoke pass. The raw consumer proves HTTP
  401 before session lookup without a bearer, HTTP 200 plus active-session
  reflection with a bearer, the `2025-03-26` response header in both cases,
  unchanged public-client session/resume state, and continued session use.
- 2026-08-13: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests, 52 FFI tests, 360 Dart core tests, all 101 MCP tests, the complete
  280-case client/MCP matrix, all 97 benchmark tests and 37 live WAMP
  workloads, all 439 router tests, 6 isolated remote-auth cases, 13 native
  follow-ups, every neutral consumer and installed-command smoke, and
  Chrome/Dart2Wasm coverage. Privacy and diff checks are clean. Publish
  dry-runs reach all seven synchronized `3.0.0-beta` archives: the first five
  packages report zero warnings, and the changed MCP and router archives each
  report only the expected pre-commit dirty-worktree warning for their three
  and four modified package files. Clean exact-commit validation, publication,
  and hosted deployment-chain evidence remain.
- 2026-08-13: Commit `85b65cf4` is published to GitLab and GitHub. Clean
  exact-commit strict validation passes all seven synchronized `3.0.0-beta`
  archives with zero warnings and no private workspace dependency blockers.
- 2026-08-13: Exact-head CI `31697806204`, Dart Package Publish Dry Run
  `31697806184`, WAMP Profile Benchmarks `31697806183`, and Router Image dry
  run `31699279379` pass on their first attempts. Retained artifacts are Dart
  VM coverage `9180546119`, WAMP profile evidence `9180224919`, Router Image
  preview `9180571495`, and Docker build records `9180725208` and
  `9180724181`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head jobs/logs and every required package, Router Image, WAMP,
  relevant Native Artifacts, protected-branch, workflow-visibility, and
  public-router-package gate ready. Native Artifacts run `31221315902` remains
  relevant because no native-release-sensitive input changed. A numeric RC tag
  remains release-approval work and was not created.
