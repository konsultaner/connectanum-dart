# MCP CORS Request-Header Field-Value Preservation

Status: completed

## Goal

Make router-hosted MCP combine every case-insensitive
`Access-Control-Request-Headers` field value when answering CORS preflights,
so browser-facing direct JSON and Streamable HTTP endpoints return the same
allow-list for split and comma-joined request fields.

## Context

Native HTTP ingress preserves immutable case-insensitive value lists for legal
HTTP list fields, and router-hosted MCP already consumes that representation
for `Accept`. The CORS response path still selects one scalar
`Access-Control-Request-Headers` value. A consumer or intermediary that emits
the same requested header list across multiple field lines can therefore
receive an incomplete `Access-Control-Allow-Headers` response even though the
equivalent comma-joined preflight succeeds. The fix must retain origin policy,
route-method handling, unauthenticated preflight behavior, `Vary` semantics,
and the absence of MCP session state.

## Plan

1. Preserve the completed request-metadata checkpoint's hosted-evidence notes
   and run the workflow, Serena, overlap, both-roadmap, and green pre-change
   fast verification checks.
2. Add fail-first synthetic and raw native HTTP regressions for split
   case-insensitive `Access-Control-Request-Headers` fields.
3. Combine the preserved field values when reflecting the preflight allow-list
   without weakening origin, auth, route-method, or session isolation.
4. Extend the neutral installed-router consumer smoke with a real split-field
   preflight through the public package boundary.
5. Run focused and full verification, write the durable Serena convention,
   bundle implementation and state evidence, publish both maintained remotes,
   and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-13: Repository workflow, Serena, overlap, active-plan, both-roadmap,
  and worktree preflights passed. The only startup changes are the completed
  request-metadata checkpoint's expected hosted-evidence notes; the scheduled
  wrapper, child Codex process, and live runlock belong to this run, and no
  unrelated same-repository editor exists.
- 2026-08-13: Pre-change `bin/test-fast` passed the complete fast matrix,
  including 360 core tests, 101 MCP tests, the 280-case client/MCP matrix, 97
  benchmark tests and 37 live WAMP workloads, plus every neutral consumer and
  installed-command smoke.
- 2026-08-13: Fail-first synthetic and raw native HTTP/1.1 preflights each
  reflected only `Authorization, Content-Type` and discarded a second
  case-insensitive field containing `MCP-Protocol-Version`.
- 2026-08-13: Router-hosted MCP now joins every preserved non-empty
  `Access-Control-Request-Headers` field value before reflecting
  `Access-Control-Allow-Headers`. Synthetic and raw native regressions pass
  while retaining origin, method, `Vary`, and session-header isolation.
- 2026-08-13: The neutral installed-router consumer smoke configures an
  explicit protected CORS origin, sends a split-field unauthenticated
  preflight, receives the complete four-header allow-list, and proves no MCP
  session is created. Focused router analysis/tests, shell syntax, and all 19
  package-boundary contracts pass.
- 2026-08-13: Full `bin/verify` passes 114 Rust core tests, 52 FFI tests, 360
  Dart core tests, all 101 MCP tests, the 280-case client/MCP matrix, 97
  benchmark cases plus 37 live WAMP workloads, all 437 router tests, six
  isolated remote-auth integrations, 13 native follow-ups, every consumer and
  installed-command smoke, and Chrome/Dart2Wasm. Strict package validation,
  publication, and exact-head hosted evidence remain.
- 2026-08-13: Strict release-ready package validation reaches the changed
  router archive with zero content warnings and only the expected dirty-
  worktree warning before the implementation commit. Clean exact-commit
  validation then passes all seven synchronized `3.0.0-beta` package archives
  with zero warnings and no private workspace dependency blockers.
- 2026-08-13: Commit `11a4f321` is published to GitLab and GitHub. Exact-head
  CI `31658474930`, Dart Package Publish Dry Run `31658474924`, WAMP Profile
  Benchmarks `31658474954`, and Router Image dry run `31658496081` all pass on
  their first attempts. Retained artifacts are Dart VM coverage `9165584530`,
  WAMP profile evidence `9165430379`, Router Image preview `9165297412`, and
  Docker build records `9165402035` and `9165401451`.
- 2026-08-13: The comprehensive strict deployment-chain audit exits zero with
  clean exact-head CI jobs and logs, clean and relevant package, Router Image,
  WAMP, and Native Artifacts evidence, protected default-branch requirements,
  visible workflows, and public router-package metadata. Native Artifacts dry
  run `31221315902` remains relevant because no native-release-sensitive input
  changed. A new numeric RC tag remains release-approval work and was not
  created.
