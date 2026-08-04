# Exec Plan: Router Image Protected JSON-Response Package Smoke

## Status

Completed.

## Goal

Prove that the canonical packaged Router Image exposes a neutral protected MCP
endpoint configured for JSON POST responses, and that both a raw Streamable
HTTP consumer and the globally activated public package client can complete the
route's authenticated lifecycle without source-tree assumptions.

## Scope

- Add a protected Router Image smoke route with
  `post_response_transport: json` and the existing neutral tool, resource,
  prompt, metadata, and pub/sub declarations.
- Require missing bearer credentials to fail before session creation.
- Initialize a compatibility Streamable HTTP session with a router-issued
  bearer and prove that POST responses are `application/json`, retain the
  session ID, require no SSE framing or cursor handling, and support DELETE.
- Run the globally activated `connectanum_mcp` client through its complete
  protected direct JSON and compatibility lifecycle against the new route.
- Emit one additional bounded package-client evidence line and one bounded raw
  response-mode marker for hosted log inspection.

## Non-Goals

- Change router MCP response-transport semantics or public package APIs.
- Add another MCP protocol version, authentication method, or public JSON-only
  route.
- Duplicate the complete native/source JSON-response test matrix in the image
  runner.
- Change existing public or protected default-response routes.

## Verification

- Pre-change `bin/test-fast`.
- A focused failing Router Image JSON-response packaging contract before runner
  implementation.
- Python compilation, shell syntax validation, and the complete Router Image
  contract suite.
- The canonical runner against a freshly built current-source local image,
  followed by the canonical Linux/amd64 image in the hosted Router Image dry
  run.
- Full `bin/verify` before handoff.
- Exact-head CI and Router Image dry run, hosted evidence inspection, and the
  comprehensive strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-04: Selected after the packaged image proved complete public and
  protected modern/compatibility lifecycles but still exposed only the default
  Streamable POST response behavior. Source, native integration, public
  examples, and generated consumer coverage already prove the router's JSON
  response option; the canonical loaded-image package smoke did not.
- 2026-08-04: Pre-change `bin/test-fast` passed the complete fast regression
  set, including package consumer smokes, Router Image contracts, native
  authorization coverage, and live WAMP benchmark workloads.
- 2026-08-04: The focused packaging contract failed first because the
  canonical config, raw runner argument, protected package-client invocation,
  and bounded JSON-response evidence were absent. The image config now exposes
  `/mcp/secure-json` with `post_response_transport: json`. The raw runner
  requires an authenticated unframed `application/json` initialize and tool
  response with one stable session ID and successful DELETE. The globally
  activated package client completes the full protected compatibility and auth
  lifecycle against the same route and emits a fifth bounded evidence line.
  Python compilation, shell syntax validation, and all 27 Router Image
  contracts pass.
- 2026-08-04: The complete runner passed with the mounted current smoke config
  and clients against the immediately preceding verified Router Image, whose
  router binary inputs are unchanged by this config/runner-only checkpoint.
  The raw marker proves JSON content type, compatibility protocol and stable
  session headers, no SSE cursor dependency, and session DELETE. The log
  contains exactly five bounded package-client evidence lines, including the
  protected JSON-response auth lifecycle. The normal canonical Dockerfile
  build stalled at Docker Hub's Dockerfile-frontend metadata lookup and was
  canceled cleanly, so the exact-head hosted Linux/amd64 build remains required
  before closure.
- 2026-08-04: Full `bin/verify` passed formatting, all Rust and FFI suites, 360
  core tests, 94 MCP tests, the complete 193-case MCP/client authorization
  suite, all 96 benchmark tests with 36 live real-router WAMP workloads, every
  isolated and globally activated consumer smoke, the complete 380-case router
  suite, 13 native-forwarding follow-ups, and Chrome/Dart2Wasm coverage.
- 2026-08-04: Implementation commit `982b113` was pushed to GitLab and GitHub.
  Exact-head CI `30871127631` passed Fast Checks, Full Verify, Dart VM Coverage,
  Codecov upload, the clean hosted-log scan, and coverage artifact
  `8878173146`. Router Image dry run `30871145474` passed its canonical
  Linux/amd64 current-source build, loaded-image runtime smoke, non-publishing
  multi-architecture build, skipped GHCR login, and clean annotations, and
  uploaded preview artifact `8877920088`. Its hosted log contains the raw
  `json_response_ready=true protected=true compatibility_json=true
  protocol_header=true session_header=true session_delete=true
  post_sse_cursor=false` marker and exactly five package-client evidence lines,
  including the protected JSON-response package lifecycle. The package
  publish, native release, and WAMP profile evidence remains relevant because
  no corresponding sensitive inputs changed. The comprehensive strict
  deployment-chain audit exited zero with every required gate ready; RC tagging
  and prerelease creation remain separate approval-gated release actions.
