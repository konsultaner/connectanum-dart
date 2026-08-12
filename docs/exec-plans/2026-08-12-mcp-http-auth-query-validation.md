# MCP HTTP-Auth Query Validation

Status: complete

## Goal

Make the router-provided HTTP authentication endpoint reject malformed query
encoding and repeated operation-relevant scalar query parameters before it
allocates or consumes challenge state or mutates a refresh/revocation lineage,
while preserving operation-specific validation for unrelated query fields.

## Context

The bridge previously parsed its query string directly into a scalar map.
Repeated keys were silently collapsed before source-conflict checks, and an
invalid percent escape raised out of the auth handler without an HTTP response.
That made the security-sensitive request interpretation depend on parser
collapse behavior rather than the bridge's generic fail-closed contract.

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes, run the Serena
   and overlap preflight, inspect both roadmaps, and establish a green
   pre-change fast matrix.
2. Add fail-first router lifecycle coverage for repeated auth query keys and
   malformed percent encoding, with legitimate challenge and grant retries.
3. Parse auth query fields without losing multiplicity, reject decoding errors
   and repeated operation-relevant keys with the existing generic HTTP 400
   `invalid_auth_parameter` response, and keep irrelevant duplicates scoped
   out of other operations.
4. Extend the neutral installed-router consumer with repeated-state rejection,
   pending-capacity retention, legitimate completion, and an explicit summary
   marker.
5. Run focused analysis/tests and full `bin/verify`, write durable Serena and
   project state, publish the implementation checkpoint, and audit the
   exact-head GitHub deployment chain.

## Progress

- 2026-08-12: Repository workflow, Serena, overlap, completed-plan, and both
  roadmap preflights passed. The only startup changes were the preceding
  checkpoint's expected hosted-evidence notes.
- 2026-08-12: Pre-change `bin/test-fast` passed the complete core, MCP,
  client/auth, benchmark, router-hosted consumer, packaging, installed-command,
  and native follow-up matrix, including all 96 benchmark cases and 36 live
  WAMP workloads.
- 2026-08-12: The fail-first regression showed that repeated initial `realm`
  query keys were collapsed and dispatched to a realm-dependent HTTP 404
  instead of the generic HTTP 400, while a malformed percent escape produced
  no response and timed out the request.
- 2026-08-12: Strict query parsing now retains duplicate-key evidence and
  converts malformed decoding into the generic, state/token-free HTTP 400.
  Repeated selector, initial, refresh, and revoke keys are rejected only when
  relevant to the selected operation; unrelated repeated keys remain ignored.
- 2026-08-12: Router analysis and focused selector-source, malformed-value,
  refresh, and revoke regressions pass. Shell syntax and the isolated neutral
  installed-router consumer smoke pass; the smoke reports
  `authQueryValidation: true`, proves repeated state rejection preserves
  pending capacity, and completes the legitimate challenge before continuing
  through protected MCP, direct JSON, pub/sub, refresh/revoke, and Streamable
  HTTP paths.
- 2026-08-12: Full `bin/verify` passes formatting and analysis, 114 Rust core
  tests, 52 FFI tests, all 360 Dart core tests, all 101 MCP tests, the 280-case
  client/MCP matrix, all 96 benchmark cases and 36 live WAMP workloads, all
  434 router tests, six isolated remote-auth integrations, 13 native
  follow-ups, every neutral consumer and installed-command smoke, and
  Chrome/Dart2Wasm coverage.
- 2026-08-12: Commit `9dd71183` is published to both maintained `master`
  branches. Exact-head GitHub CI `31565229346`, Dart Package Publish Dry Run
  `31565229330`, WAMP Profile Benchmarks `31565229358`, and dispatched Router
  Image dry run `31565240994` all pass. Retained artifacts are Dart VM coverage
  `9129496766`, WAMP evidence `9129335988`, Router Image preview `9129208998`,
  and Docker build records `9129283396` / `9129283105`. The comprehensive
  strict deployment-chain audit exits zero with clean exact-head CI logs,
  loaded-image MCP runtime smoke, relevant native-release evidence, and every
  required deployment gate ready. RC creation remains an explicit
  release-approval action outside this checkpoint.
