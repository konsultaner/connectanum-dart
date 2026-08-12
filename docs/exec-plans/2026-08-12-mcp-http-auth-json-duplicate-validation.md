# MCP HTTP-Auth JSON Duplicate Validation

Status: complete

## Goal

Make the router-provided HTTP authentication endpoint retain top-level JSON
member multiplicity and reject repeated operation-relevant scalar parameters
before allocating or consuming challenge state or mutating refresh/revocation
lineage, while preserving operation-specific validation for unrelated fields.

## Context

The HTTP auth bridge previously decoded request JSON directly into a Dart map.
Repeated object members were therefore collapsed before selector and
credential validation, leaving security-sensitive interpretation dependent on
parser last-value behavior even though equivalent repeated query keys already
failed closed.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the required
   workflow/Serena/overlap/roadmap preflight, and establish a green pre-change
   fast matrix.
2. Add fail-first router lifecycle coverage using raw JSON bodies with repeated
   selector, initial-auth, challenge, refresh, and revoke members.
3. Retain decoded top-level member multiplicity without weakening standard JSON
   syntax validation, and apply duplicate validation only to fields relevant to
   the selected auth operation.
4. Extend the neutral installed-router consumer smoke with repeated-state JSON
   rejection, pending-capacity retention, legitimate challenge completion, and
   an explicit summary marker.
5. Run focused and full verification, write durable Serena/project state,
   publish the implementation checkpoint, and audit the exact-head GitHub
   deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes; no unrelated same-repository
  Codex process or stale runlock exists.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: The fail-first regression showed that repeated initial `realm`
  JSON members were collapsed and dispatched to a realm-dependent HTTP 404
  instead of the generic HTTP 400.
- 2026-08-12: HTTP auth body decoding now retains duplicate top-level member
  evidence, including escaped-equivalent key spellings, and applies it to
  selectors, initial credentials, challenge signatures, refresh aliases, and
  revocation credentials/hints only when relevant to the selected operation.
  Rejection is the generic state/token-free HTTP 400 before mutation;
  unrelated repeated members remain ignored across other operations.
- 2026-08-12: Router analysis and the focused malformed-parameter lifecycle
  regression pass. Shell syntax and the isolated neutral installed-router
  consumer smoke pass; the smoke reports
  `authBodyMultiplicityValidation: true`, proves repeated-state JSON rejection
  preserves pending capacity, and completes the legitimate challenge before
  continuing through protected MCP, direct JSON, pub/sub, refresh/revoke, and
  Streamable HTTP paths.
- 2026-08-12: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests, 52 FFI tests, all 360 Dart core tests, all 101 MCP tests, the 280-case
  client/MCP matrix, all 96 benchmark cases and 36 live WAMP workloads, all
  434 router tests, six isolated remote-auth integrations, 13 native
  follow-ups, every neutral consumer and installed-command smoke, and
  Chrome/Dart2Wasm coverage.
- 2026-08-12: Commit `56c2a64d` is published to both maintained `master`
  branches. Exact-head GitHub CI `31569465395`, Dart Package Publish Dry Run
  `31569465430`, WAMP Profile Benchmarks `31569465330`, and dispatched Router
  Image dry run `31569484002` all pass. Retained artifacts are Dart VM coverage
  `9131106661`, WAMP evidence `9130886257`, Router Image preview `9130745460`,
  and Docker build records `9130823079` / `9130822665`. The comprehensive
  strict deployment-chain audit exits zero with clean exact-head CI logs,
  loaded-image MCP runtime smoke, relevant native-release evidence, and every
  required deployment gate ready. RC creation remains an explicit
  release-approval action outside this checkpoint.
