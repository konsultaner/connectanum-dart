# Exec Plan: MCP WAMP Meta JSON Parameters

Status: active
Owner: Codex
Created: 2026-08-14
Last updated: 2026-08-14

## Goal

Make router-hosted standard WAMP Meta API tools directly usable by agents and
consumer applications through procedure-specific named JSON parameters and
accurate advertised schemas, without breaking callers that already send raw
WAMP `arguments` and `argumentsKeywords`.

## Scope

- In scope:
  - Procedure-specific input schemas for all 15 standard WAMP Meta API tools.
  - Named JSON parameters for session, registration, and subscription
    identifiers, procedure/topic URIs, and optional lookup match policies.
  - An explicit compatibility path for existing raw positional and keyword
    WAMP argument payloads.
  - A reusable output schema for the lossless WAMP result envelope.
  - Core, package-boundary, and Router Image smoke evidence across direct JSON
    and standard `tools/call` access.
- Out of scope:
  - Changing WAMP Meta API result semantics, authorization, or visibility.
  - Paginating standard WAMP Meta API procedure results.
  - Adding non-standard WAMP Meta procedures or changing the public typed Dart
    helper signatures.

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/tools/wamp_api.dart`
- `packages/connectanum_mcp/lib/src/cli/router_hosted_client.dart`
- `packages/connectanum_mcp/test/wamp_api_test.dart`
- `bin/common.sh`
- `tool/smoke_router_image_mcp.py`
- `tool/test_router_image_mcp_smoke.py`
- `tool/test_mcp_consumer_package_boundary.py`
- Package/readme/changelog files only where the public contract requires it.
- `docs/project_state.md` and this plan.

## Preconditions

- The maintained branch and exact-head hosted deployment chain are green at
  implementation base `2b21b0d2`.
- No new credentials or product decision is required; named parameters map to
  the already-shipped standard Meta API procedure signatures.

## Plan

1. Run the pre-change fast gate and add fail-first core and smoke contracts for
   procedure-specific schemas and named JSON parameters.
2. Implement a procedure-aware compatibility mapper and accurate shared result
   schema while retaining raw WAMP payload support.
3. Convert the neutral Router Image Meta calls to named inputs and run focused
   package, Python, router, privacy, and full verification.
4. Commit and push the implementation with pending hosted-evidence bookkeeping,
   then collect exact-head CI, package, Router Image, and strict-audit evidence.

## Verification

- `dart test packages/connectanum_mcp/test/wamp_api_test.dart -r expanded`
- `dart test packages/connectanum_mcp -r expanded`
- `dart test packages/connectanum_router/test/router_json_test.dart -r expanded`
- `python3 -m unittest tool.test_router_image_mcp_smoke`
- `python3 -m unittest tool.test_mcp_consumer_package_boundary`
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `bash -n bin/router-image-mcp-smoke bin/common.sh`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-08-14: The typed Dart client already exposes meaningful Meta API
  concepts, but router-hosted tools advertise only generic raw WAMP payloads.
  Procedure-specific named parameters are the highest-priority remaining direct
  JSON readiness gap and can be added without changing router authorization or
  standard WAMP behavior.
- 2026-08-14: Existing raw `arguments` and `argumentsKeywords` remain a
  compatibility form. Mixing raw and named forms will be rejected so callers
  do not silently send ambiguous WAMP calls.
- 2026-08-14: Canonical direct JSON fields are `sessionId`, `registrationId`,
  `subscriptionId`, `procedure`, and `topic`; lookup tools also accept the
  standard `exact`, `prefix`, and `wildcard` match policies. Documented legacy
  aliases remain accepted, but conflicting aliases, unknown fields,
  non-positive ids, and ambiguous named/raw requests fail before WAMP dispatch.
- 2026-08-14: The shared result schema advertises the lossless
  `arguments`/`argumentsKeywords`/`details` envelope returned by the bridge.
  The packaged router-hosted client, generated consumer templates, and Router
  Image smoke now use canonical named inputs while dedicated tests retain the
  raw and legacy compatibility evidence.
- 2026-08-14: Exact-head Router Image dry run `31782248716` exposed a catalog
  merge defect after the local gates passed: the smoke fixture explicitly
  configures `wamp.session.count`, so its generic descriptor was retained before
  the canonical standard Meta descriptor and erased `inputSchema.properties`.
  The router now makes canonical standard procedure descriptors authoritative
  whenever `includeStandardMetaApi` is enabled. A fail-first native regression
  mirrors the configured-URI collision and verifies the canonical no-argument,
  named-argument, and output schemas.

## Handoff

- Implementation is complete locally. Pre-change and post-change
  `bin/test-fast` pass. Focused MCP package, router JSON, Router Image smoke,
  package-boundary, Python compile, Bash syntax, Dart analysis, and diff-hygiene
  checks pass.
- Full `bin/verify` exits zero across formatting, Rust core/FFI, Dart
  package/native/browser suites, generated and globally activated consumer
  smokes, live WAMP and benchmark coverage, the complete router suite, Chrome,
  and Dart2Wasm. The first `ct_ffi` attempt hit the known retryable HTTP/3
  handshake assertion; the canonical verifier retried automatically and all
  52 FFI tests passed on the second attempt.
- Implementation commit `d77fc83b` is published to both maintained `master`
  branches. Exact-head CI `31781038469`, Dart Package Publish Dry Run
  `31781038421`, and WAMP Profile Benchmarks `31781038434` pass on their first
  attempts. Router Image `31782248716` failed only its new schema assertion and
  supplied the configured-URI collision reproduced by the native regression.
- Post-fix focused tests, package/router analysis, shell/Python hygiene, and
  `bin/test-fast` pass. A second full `bin/verify` passes with all 52 FFI tests
  green on the first attempt and the expanded 441-case router suite green.
  The corrective commit/push, replacement exact-head hosted workflows, passing
  Router Image evidence, and strict deployment-chain audit remain.
