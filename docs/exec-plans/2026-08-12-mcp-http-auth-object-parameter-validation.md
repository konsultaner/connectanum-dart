# MCP HTTP-Auth Object Parameter Validation

Status: complete

## Goal

Make the router-provided HTTP authentication endpoint reject malformed non-null
or repeated map-valued authentication parameters before invoking
authenticators, allocating challenge state, or consuming an existing challenge,
while keeping valid objects and compatibility-era null-as-omitted
`authextra`/`extra` payloads compatible.

## Context

The HTTP auth bridge validates operation selectors and scalar credentials
across JSON, query, and header sources. Its JSON `authextra` and challenge
`extra` inputs are different: non-null non-object values are currently
discarded, repeated top-level members are collapsed, and challenge state is
removed before the decoded `extra` value is interpreted. That leaves malformed
authentication metadata able to change authenticator input or consume a
retryable challenge. Existing public clients may serialize absent optional
objects as null, so null retains its established omitted-value semantics.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the required
   workflow/Serena/overlap/roadmap preflight, and establish a green pre-change
   fast matrix.
2. Add fail-first router lifecycle coverage for non-object and repeated initial
   `authextra` plus challenge `extra` inputs, including pending-capacity and
   legitimate-retry assertions.
3. Validate the map-valued parameters only for their selected operation and
   reject them with the generic state/token-free HTTP 400 before authenticator
   or grant state mutation.
4. Extend the neutral installed-router consumer smoke with the same rejection,
   retained pending state, valid completion, and an explicit evidence marker.
5. Run focused and full verification, write durable Serena/project state,
   publish the implementation checkpoint, and audit the exact-head GitHub
   deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes are the preceding
  checkpoint's expected hosted-evidence notes; no unrelated same-repository
  Codex process or stale runlock exists.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: The fail-first router lifecycle regression reproduced a
  non-object initial `authextra` reaching the ticket authenticator and returning
  an HTTP 401 challenge instead of the generic HTTP 400.
- 2026-08-12: Initial `authextra` and challenge `extra` now reject non-null
  non-object or repeated top-level JSON values only for their selected
  operation. Null remains compatible as an omitted optional object. Rejection
  uses the generic state/token-free HTTP 400 before authenticator creation or
  pending-challenge removal, while valid objects and irrelevant cross-operation
  fields remain compatible.
- 2026-08-12: Router analysis, the focused fail-first regression, and the
  complete 88-case router runtime lifecycle pass. Shell syntax and the neutral
  installed-router consumer smoke pass; the consumer reports
  `authObjectParameterValidation: true`, proves both malformed and repeated
  challenge-object rejection preserve max-one pending capacity, and completes
  the legitimate challenge before continuing through protected MCP, direct
  JSON, pub/sub, refresh/revoke, and Streamable HTTP paths.
- 2026-08-12: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests, 52 FFI tests, all 360 Dart core tests, all 101 MCP tests, the 280-case
  client/MCP matrix, all 96 benchmark cases and 36 live WAMP workloads, all 434
  router tests, six isolated remote-auth integrations, 13 native follow-ups,
  every neutral consumer and installed-command smoke, and Chrome/Dart2Wasm
  coverage.
- 2026-08-12: Implementation commit `c39ca2385131` is on both maintained
  `master` branches. Exact-head CI `31574536358`, Dart Package Publish Dry Run
  `31574536413`, WAMP Profile Benchmarks `31574536381`, and Router Image dry
  run `31574578812` all passed on their first attempts. CI uploaded coverage
  artifact `9133131431`, WAMP uploaded benchmark artifact `9132819435`, and
  Router Image uploaded preview artifact `9132643342` plus Docker build records
  `9132753196` and `9132752751`.
- 2026-08-12: Comprehensive
  `bin/audit-github-deployment-chain --branch master --run-limit 8 --strict
  --require-workflows-visible --require-router-package
  --require-clean-latest-ci --require-clean-latest-ci-logs
  --require-clean-dart-package-publish-dry-run
  --require-clean-native-release-dry-run --require-clean-router-image-dry-run
  --require-clean-wamp-profile-benchmarks --show-rc-readiness` passes with
  clean exact-head CI logs and all required branch, workflow, package,
  native-release, package-publish, loaded-image MCP, multi-architecture image,
  and benchmark gates clean. Its non-gating release-candidate summary remains
  intentionally not ready because no approved numeric RC tag points at this
  implementation commit.
