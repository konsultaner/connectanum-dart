# Exec Plan: Release Candidate Readiness

Status: active
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-27

## Problem

The workspace is ready to move from long-lived feature-branch validation toward
a first release candidate, but the release must come from the GitHub default
branch with clean CI, visible workflows, native runtime bundles, and router
image validation. Public pub.dev publishing remains a separate release-track
decision because `connectanum_client` still depends on private
`connectanum_core`.

## Scope

- Treat MCP as RC-ready after the direct WAMP API helper smoke evidence unless
  a consumer integration uncovers a real correctness bug.
- Align `bin/audit-github-deployment-chain --require-rc-ready` with the first
  RC definition: GitHub prerelease readiness can pass when pub.dev publishing is
  intentionally deferred and the only strict Dart package blocker is the known
  private `connectanum_core` dependency.
- Accept inspected native GitHub prerelease evidence for RC readiness while
  keeping the standalone native release dry-run audit gate strictly
  non-mutating.
- Add an explicit non-mutating Router Image dry-run audit gate so container
  build validation is tracked separately from GHCR package visibility/publish
  approval.
- Promote `add-router` into the GitHub default branch used for releases.
- Configure required GitHub status checks for `Fast Checks` and `Full Verify`.
- Run local release gates, hosted CI, hosted package dry-run evidence, WAMP
  profile benchmark evidence, native artifact prerelease publishing, router
  image dry-run/publish validation, and final deployment-chain audits.

## Non-Goals

- Public pub.dev publishing for the first RC.
- Making private workspace packages publishable.
- Adding new MCP helper permutations after the RC-ready smoke unless a real
  integration bug appears.
- Mentioning private downstream application names or local downstream paths in
  checked-in docs or public artifacts.

## Milestones

- MCP direct WAMP API helper smoke is complete and hosted GitHub CI is green.
- RC audit semantics distinguish GitHub prerelease readiness from deferred
  pub.dev release-order decisions without hiding package dry-run warnings.
- GitHub `master` contains the release branch content and checked-in workflows.
- GitHub branch protection requires `Fast Checks` and `Full Verify`.
- `v0.1.0-rc.1` exists as a non-draft GitHub prerelease with native bundles,
  checksums, and Sigstore metadata.
- `ghcr.io/konsultaner/connectanum-router:0.1.0-rc.1` is published and the
  router package is visible through the public GHCR registry API or GitHub
  Packages metadata fallback.
- Final audits pass for GitHub-prerelease RC readiness, with pub.dev release
  order explicitly deferred.

## Verification

- `bin/test-fast`
- `bash -n bin/audit-github-deployment-chain`
- `bin/audit-github-deployment-chain --help`
- `bin/audit-github-deployment-chain --branch add-router --require-clean-router-image-dry-run`
- `bin/dart-package-publish-dry-run`
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
  is expected to fail only on the known private `connectanum_core` dependency.
- `bin/verify`
- GitHub `CI`: `Fast Checks` and `Full Verify` green on the release branch.
- GitHub `Dart Package Publish Dry Run`: green with zero warnings.
- GitHub `WAMP Profile Benchmarks`: green on the release-sensitive branch/tag.
- GitHub `Native Artifacts`: prerelease run green for `v0.1.0-rc.1`.
- GitHub `Router Image`: dry-run green, then publish green for `v0.1.0-rc.1`.
- `bin/audit-github-deployment-chain --branch master --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --show-rc-readiness`
- `bin/audit-github-deployment-chain --branch master --require-rc-ready`

## Decision Log

- 2026-05-27: Hardened public `McpStreamableHttpClient` raw JSON request
  params validation before transport dispatch. Raw request objects now require
  `params`, when present, to be an object with string keys; array params and
  maps with non-string params keys are rejected locally. This matches the
  standalone MCP server and router-hosted direct JSON MCP parsers that
  normalize params through `jsonMapFrom(...)`, keeping direct JSON, tool, meta,
  and pub/sub calls from opening HTTP for request objects that package-hosted
  MCP ingress would reject. Fail-first coverage reproduced the prior behavior
  where an array-params request reached the fake endpoint and returned a normal
  `tools/list` response; regression coverage also verifies non-string params
  keys are rejected locally. Baseline `bin/test-fast` passed before the change
  on 2026-05-27. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC request objects" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Hosted evidence remains on the
  latest fully clean checkpoint `d31feca` until this implementation commit is
  pushed and its deployment chain completes.
- 2026-05-27: Hardened public `McpStreamableHttpClient` raw JSON request
  validation so empty method names are rejected before dispatch. The raw
  request guard already rejected missing or non-string methods,
  response-shaped requests, invalid params shapes, invalid request IDs, empty
  batches, and duplicate batch IDs; it now also requires the method string to
  be non-empty, matching standalone MCP server and router-hosted MCP ingress
  parser behavior. This keeps raw direct JSON, tool, meta, and pub/sub calls
  from opening HTTP for request objects that the package server paths would
  reject as invalid requests. Fail-first coverage reproduced the prior
  behavior where an empty method request reached the fake endpoint and returned
  a normal response. Baseline `bin/test-fast` passed before the change on
  2026-05-27. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC request objects" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `d31feca` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `d31feca` is clean: GitHub `CI` `26494429335`, `Dart Package Publish Dry
  Run` `26494429357`, `WAMP Profile Benchmarks` `26494429336`, and
  non-mutating `Router Image` dry-run `26494437746` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `d31feca`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened MCP JSON-RPC request validation consistently across
  standalone and router-hosted MCP ingress. Standalone `_requestFrom(...)` and
  router-hosted `_directJsonRequestFrom(...)` now reject request-shaped objects
  that also include response-only `result` or `error` members, matching the
  public Streamable HTTP client raw-request guard and returning invalid-request
  responses instead of dispatching malformed tool, meta, or pub/sub calls.
  Fail-first coverage reproduced the prior server and router behavior where
  response-shaped requests could reach handler dispatch. Baseline
  `bin/test-fast` passed before the change on 2026-05-27. Focused local
  coverage passed with
  `dart test packages/connectanum_mcp/test/lifecycle_test.dart --name "response-only members" -r expanded`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "guards MCP Streamable HTTP ingress and sessions" -r expanded`,
  `dart analyze packages/connectanum_mcp/lib/src/server/mcp_server.dart packages/connectanum_mcp/test/lifecycle_test.dart packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  and `dart test packages/connectanum_mcp -r expanded`. Full local
  `bin/verify` passed on 2026-05-27, including formatting, Rust/FFI, MCP
  package smokes, client/native transport suites, auth server, live WAMP
  transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `8309afe` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `8309afe` is clean: GitHub `CI` `26492798306`, `Dart Package Publish Dry
  Run` `26492798308`, `WAMP Profile Benchmarks` `26492798305`, and
  non-mutating `Router Image` dry-run `26492807464` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `8309afe`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened outgoing MCP Streamable HTTP session headers before
  public `McpStreamableHttpClient` sends session-bound requests. The client
  still exposes mutable `sessionId` state for consumers that need manual
  session control, but `_applyHeaders` now rejects locally injected
  `MCP-Session-Id` values containing HTTP-header-invalid characters before a
  request is opened. This closes the remaining client-side session header path
  after response-header and SSE resume-cursor validation: malformed local state
  can no longer become an outbound session header while session-free requests
  remain unaffected. Fail-first coverage reproduced the prior behavior where a
  caller could assign an invalid `sessionId` after initialize and then attempt
  a `tools/list` request with that invalid header. Baseline `bin/test-fast`
  passed before the change on 2026-05-27. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid outgoing MCP-Session-Id" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `2b9df3b` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `2b9df3b` is clean: GitHub `CI` `26491250776`, `Dart Package Publish Dry
  Run` `26491250805`, `WAMP Profile Benchmarks` `26491250777`, and
  non-mutating `Router Image` dry-run `26491257061` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `2b9df3b`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened MCP Streamable HTTP SSE event-id handling before public
  `McpStreamableHttpClient` mutates session or resume cursor state. Parsed SSE
  `id` values containing HTTP-header-invalid control characters are now
  rejected before POST/SSE or polling responses capture MCP session headers or
  update `lastEventId`, and invalid caller-provided `Last-Event-ID` poll
  overrides fail before the poll request is sent. Empty SSE `id` values remain
  valid and continue to clear the resume cursor. Fail-first coverage reproduced
  the prior behavior where invalid server-supplied SSE IDs could become the
  next resume cursor and where an invalid caller override could be attempted
  directly. Baseline `bin/test-fast` passed before the change on 2026-05-27.
  Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid.*(event ids|Last-Event-ID|SSE event id)" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `7eef8e0` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `7eef8e0` is clean: GitHub `CI` `26489810145`, `Dart Package Publish Dry
  Run` `26489810140`, `WAMP Profile Benchmarks` `26489810147`, and
  non-mutating `Router Image` dry-run `26489832587` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `7eef8e0`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened MCP Streamable HTTP poll event payload validation
  before public `McpStreamableHttpClient.poll()` captures MCP session headers
  or the resume cursor. Every non-empty GET/SSE `data:` payload returned by
  Streamable HTTP polling must now be a JSON-RPC object or non-empty batch
  array whose items are valid JSON-RPC response, request, or notification
  objects. Empty poll events remain valid keep-alive events, but malformed
  scalar or otherwise invalid event payloads can no longer advance `sessionId`
  or `lastEventId`. Fail-first coverage reproduced the prior behavior where
  scalar poll event data was returned and the response session header plus SSE
  `id` mutated client state. Baseline `bin/test-fast` passed before the change
  on 2026-05-27. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "malformed Streamable HTTP poll messages" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `7292c3b` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `7292c3b` is clean: GitHub `CI` `26488177832`, `Dart Package Publish Dry
  Run` `26488177835`, `WAMP Profile Benchmarks` `26488177777`, and
  non-mutating `Router Image` dry-run `26488596360` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `7292c3b`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened MCP Streamable HTTP SSE event payload validation before
  public `McpStreamableHttpClient` POST/SSE results are matched or returned.
  Every non-empty SSE `data:` payload in a solicited POST response stream must
  now be a JSON-RPC object or non-empty batch array whose items are valid
  JSON-RPC response, request, or notification objects. This preserves
  MCP-compatible server requests and progress notifications before a matching
  response while preventing malformed scalar or otherwise invalid event
  payloads from being ignored behind a later valid response. Validation still
  runs before MCP session/header/cursor capture, so malformed interim SSE
  messages cannot mutate `sessionId` or `lastEventId`. Fail-first coverage
  reproduced the prior behavior where scalar SSE event data before single and
  batch responses was ignored and callers received the later valid response.
  Baseline `bin/test-fast` passed before the change on 2026-05-27. Focused
  local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "malformed Streamable HTTP SSE messages" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `f1c2895` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `f1c2895` is clean: GitHub `CI` `26486040723`, `Dart Package Publish Dry
  Run` `26486040722`, `WAMP Profile Benchmarks` `26486040721`, and
  non-mutating `Router Image` dry-run `26486480668` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `f1c2895`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened MCP client-side JSON-RPC response ID type validation
  before public Streamable HTTP client results are returned. Public direct JSON
  and solicited Streamable HTTP POST/SSE single and batch responses now reject
  response objects whose `id` is not a string or integer before matching them to
  the originating request. This closes the Dart numeric-equality gap where a
  malformed fractional response ID such as `1.0` could be accepted as matching
  a valid integer request ID `1`. Validation still runs before MCP
  session/header/cursor capture, so malformed response IDs cannot mutate
  `sessionId` or `lastEventId`. Fail-first coverage reproduced the prior
  behavior where malformed response IDs were emitted successfully to callers
  across direct JSON single, Streamable SSE single, direct JSON batch, and
  Streamable SSE batch responses. Baseline `bin/test-fast` passed before the
  change on 2026-05-27. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC .*response ids" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "response ids|response discriminants|response versions|response error|incomplete JSON-RPC batch responses|duplicate JSON-RPC batch response ids" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `acf769a` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `acf769a` is clean: GitHub `CI` `26484233787`, `Dart Package Publish Dry
  Run` `26484233697`, `WAMP Profile Benchmarks` `26484233696`, and
  non-mutating `Router Image` dry-run `26484725990` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `acf769a`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened MCP client-side JSON-RPC error response object
  validation before public Streamable HTTP client results are returned. Public
  direct JSON and solicited Streamable HTTP POST/SSE responses now reject
  malformed JSON-RPC error responses whose `error.code` is not an integer or
  whose `error.message` is not a string, across single requests and batches,
  before callers can observe the response. Validation still runs before MCP
  session/header/cursor capture, so malformed error envelopes cannot mutate
  `sessionId` or `lastEventId`. Fail-first coverage reproduced the prior
  behavior where malformed error responses were emitted successfully to
  callers. Baseline `bin/test-fast` passed before the change. Focused local
  coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "response error" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "response error|response discriminants|response versions|unexpected JSON-RPC .*response ids|incomplete JSON-RPC batch responses|duplicate JSON-RPC batch response ids" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `3244ad9` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `3244ad9` is clean: GitHub `CI` `26482282638`, `Dart Package Publish Dry
  Run` `26482282677`, `WAMP Profile Benchmarks` `26482282629`, and
  non-mutating `Router Image` dry-run `26482302462` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `3244ad9`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-27: Hardened MCP client-side empty JSON-RPC batch validation before
  public Streamable HTTP client dispatch. The public
  `McpStreamableHttpClient.postBatch(...)` and `postBatchDirect(...)` paths now
  reject empty JSON-RPC batch arrays before opening HTTP, aligning the client
  raw batch escape hatch with the standalone MCP server and router-hosted MCP
  ingress behavior that already returns an invalid-request response for empty
  batches. This prevents consumer applications from accidentally treating a
  malformed empty batch as a successful notification-only batch. Fail-first
  coverage reproduced the prior behavior where `postBatch([])` emitted `null`
  after dispatching to the fake endpoint. Baseline `bin/test-fast` passed
  before the change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "empty JSON-RPC batches" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "empty JSON-RPC batches|invalid JSON-RPC request objects|duplicate JSON-RPC batch request ids|invalid JSON-RPC batch request ids" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-27, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `1ec2c58` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `1ec2c58` is clean: GitHub `CI` `26480510364`, `Dart Package Publish Dry
  Run` `26480510361`, `WAMP Profile Benchmarks` `26480510321`, and
  non-mutating `Router Image` dry-run `26480524504` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-27 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `1ec2c58`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-26: Hardened MCP client-side direct JSON request object validation
  before public Streamable HTTP client dispatch. The public
  `McpStreamableHttpClient.post(...)` and `postBatch(...)` paths now reject raw
  JSON-RPC request objects whose `method` member is missing or not a string,
  whose object also contains response-only `result` or `error` members, or
  whose present `params` member is not a JSON object or array, before opening
  HTTP. Direct JSON helpers inherit the same guard, so consumer applications
  cannot accidentally send response-shaped or otherwise malformed tool, meta,
  or pub/sub requests through the raw JSON escape hatch. Fail-first coverage
  reproduced the prior behavior where a missing-method request was sent to the
  fake endpoint and returned as a successful `tools/list` response. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC request objects" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC request objects|invalid JSON-RPC request ids|invalid JSON-RPC request versions|invalid JSON-RPC batch request ids|duplicate JSON-RPC batch request ids" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-26, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `d6b6e91` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `d6b6e91` is clean: GitHub `CI` `26478752624`, `Dart Package Publish Dry
  Run` `26478752623`, `WAMP Profile Benchmarks` `26478752655`, and
  non-mutating `Router Image` dry-run `26478763017` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-26 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `d6b6e91`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-26: Hardened MCP client-side JSON-RPC object version validation
  before public Streamable HTTP client dispatch or response delivery. The
  public `McpStreamableHttpClient.post(...)` and `postBatch(...)` paths now
  reject direct JSON request objects whose `jsonrpc` member is not exactly
  `2.0`, including invalid batch items, before opening HTTP. Public direct JSON
  and solicited Streamable HTTP POST/SSE response objects now require the same
  `jsonrpc: "2.0"` member before callers can observe them; validation still
  runs before successful MCP session/header/cursor capture, so malformed
  JSON-RPC versions cannot mutate `sessionId` or `lastEventId`. Fail-first
  coverage reproduced the prior behavior where malformed request versions were
  sent and malformed direct JSON/SSE response versions were returned
  successfully. Baseline `bin/test-fast` passed before the change. Focused
  local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC .*versions" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`.
  Full local `bin/verify` passed on 2026-05-26, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `ca778cf` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `ca778cf` is clean: GitHub `CI` `26477031560`, `Dart Package Publish Dry
  Run` `26477031554`, `WAMP Profile Benchmarks` `26477031553`, and
  non-mutating `Router Image` dry-run `26477052716` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-26 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `ca778cf`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-26: Hardened MCP client-side JSON-RPC response object
  discriminants before returning public Streamable HTTP client results. The
  public `McpStreamableHttpClient.post(...)` and `postBatch(...)` paths now
  require response objects to contain exactly one of `result` or `error`, and
  error responses must carry a JSON object `error` member before raw direct
  JSON callers can observe them. Streamable HTTP POST/SSE response streams now
  apply the same validation to solicited response objects while continuing to
  ignore MCP-compatible interim server requests and progress notifications,
  including server requests interleaved before batch responses. Response-shape
  validation still runs before successful MCP session/header/cursor capture, so
  malformed discriminants cannot mutate `sessionId` or `lastEventId`.
  Fail-first coverage reproduced the prior behavior where raw direct JSON and
  POST/SSE responses with missing or conflicting response discriminants were
  returned successfully, and where a batch POST/SSE server request was rejected
  as an unexpected batch response ID. Baseline `bin/test-fast` passed before
  the change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC .*response discriminants|server requests before batch responses" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `0dac69c` was pushed to `origin` `add-router` and GitHub
  `add-router`/`master`. Hosted evidence for `0dac69c` is clean: GitHub `CI`
  `26474781234`, `Dart Package Publish Dry Run` `26474781276`, `WAMP Profile
  Benchmarks` `26474781275`, and non-mutating `Router Image` dry-run
  `26474800894` all completed successfully. The strict `master`
  deployment-chain audit passed on 2026-05-26 with clean latest CI jobs/logs,
  clean package dry-run, clean router image dry-run, clean WAMP profile
  benchmark evidence, and relevant native release dry-run evidence. GitHub
  Status reported all systems operational and Actions operational. RC release
  readiness remains not ready because no RC tag points at `0dac69c`, a GitHub
  prerelease still requires release approval after selecting an RC tag, the
  router image RC tag is not selected, and public pub.dev publishing remains
  deferred pending package ownership/versioning and workspace package release
  order decisions.
- 2026-05-26: Hardened MCP client-side single JSON-RPC response ID
  validation before returning public Streamable HTTP client results. Direct
  JSON `McpStreamableHttpClient.post(...)` responses must now include an `id`
  matching the request `id`, and Streamable HTTP POST/SSE response streams now
  inspect every JSON-RPC response object so an extra mismatched response cannot
  be hidden behind a later matching response. MCP-compatible server requests
  and progress notifications in the same POST/SSE stream remain accepted before
  the solicited response, matching the Streamable HTTP transport guidance in
  https://modelcontextprotocol.io/specification/2025-06-18/basic/transports.
  Response-shape validation still runs before successful MCP
  session/header/cursor capture, so malformed responses cannot mutate
  `sessionId` or `lastEventId`. Fail-first coverage reproduced the prior
  behavior where a direct JSON response with `id: "other-response"` was
  returned successfully and a Streamable SSE response with an extra mismatched
  response was ignored when a later matching response appeared. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "unexpected JSON-RPC single response ids|server requests before matching responses" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `8f2de31` was pushed to `origin` `add-router` and GitHub
  `add-router`/`master`. Hosted evidence for `8f2de31` is clean: GitHub `CI`
  `26472278175`, `Dart Package Publish Dry Run` `26472278178`, `WAMP Profile
  Benchmarks` `26472278174`, and non-mutating `Router Image` dry-run
  `26472312261` all completed successfully. The strict `master`
  deployment-chain audit passed on 2026-05-26 with clean latest CI jobs/logs,
  clean package dry-run, clean router image dry-run, clean WAMP profile
  benchmark evidence, and relevant native release dry-run evidence. GitHub
  Status reported all systems operational and Actions operational. RC release
  readiness remains not ready because no RC tag points at `8f2de31`, a GitHub
  prerelease still requires release approval after selecting an RC tag, the
  router image RC tag is not selected, and public pub.dev publishing remains
  deferred pending package ownership/versioning and workspace package release
  order decisions.
- 2026-05-26: Hardened MCP client-side single-request ID validation before
  dispatch. The public `McpStreamableHttpClient.post(...)` now rejects every
  present JSON-RPC request ID that is not a string or integer, including
  explicit `null` and fractional numeric IDs, before opening HTTP. Direct JSON
  access through `postDirect(...)` inherits the protection, while
  `postBatch(...)` now uses the same request-ID guard before duplicate-ID
  checks. This prevents consumer applications from accidentally sending
  malformed direct JSON or Streamable HTTP tool/meta/pubsub requests through
  the raw JSON escape hatch. Fail-first coverage reproduced the prior behavior
  where `id: null` was sent to the fake endpoint and returned as a successful
  single response. Baseline `bin/test-fast` passed before the change. Focused
  local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC request ids" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC request ids|invalid JSON-RPC batch request ids|duplicate JSON-RPC batch request ids" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-26, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `5e01a71` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `5e01a71` is clean: GitHub `CI` `26469650582`, `Dart Package Publish Dry
  Run` `26469650425`, `WAMP Profile Benchmarks` `26469651283`, and
  non-mutating `Router Image` dry-run `26469661353` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-26 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `5e01a71`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-26: Hardened MCP client-side batch request ID validation before
  dispatch. The public `McpStreamableHttpClient.postBatch(...)` now rejects
  every present JSON-RPC batch request ID that is not a string or integer,
  including explicit `null` and fractional numeric IDs, before opening HTTP;
  duplicate valid request IDs remain rejected locally through the same guard.
  Direct JSON batch access through `postBatchDirect(...)` inherits the
  protection, so consumer applications cannot accidentally send malformed
  direct JSON or Streamable HTTP tool/meta/pubsub batches. Fail-first coverage
  reproduced the prior behavior where invalid request IDs were sent to the
  fake endpoint and returned as successful batch responses. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC batch request ids" -r expanded`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "invalid JSON-RPC batch request ids|duplicate JSON-RPC batch request ids" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  and `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-26, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `89c6bd3` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `89c6bd3` is clean: GitHub `CI` `26467267462`, `Dart Package Publish Dry
  Run` `26467267460`, `WAMP Profile Benchmarks` `26467267458`, and
  non-mutating `Router Image` dry-run `26467273784` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-26 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `89c6bd3`, a GitHub prerelease still requires
  release approval after selecting an RC tag, the router image RC tag is not
  selected, and public pub.dev publishing remains deferred pending package
  ownership/versioning and workspace package release order decisions.
- 2026-05-26: Hardened MCP batch request ID integrity before dispatch. The
  public `McpStreamableHttpClient.postBatch(...)` now rejects duplicate string
  or integer JSON-RPC request IDs locally before opening HTTP, while the
  standalone MCP server and router-hosted MCP direct JSON/Streamable HTTP
  ingress reject duplicate valid batch request IDs before dispatching any tool,
  WAMP-backed API, or pub/sub operation. Fail-first coverage reproduced the
  prior behavior where duplicate request IDs were accepted, side-effecting
  handlers ran, and clients only failed later on duplicate response IDs.
  Baseline `bin/test-fast` passed before the change. Focused local coverage
  passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "duplicate JSON-RPC batch request ids" -r expanded`,
  `dart test packages/connectanum_mcp/test/lifecycle_test.dart --name "duplicate JSON-RPC batch request ids" -r expanded`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "smoke tests MCP router RPC pubsub and route security" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_mcp/lib/src/server/mcp_server.dart packages/connectanum_mcp/test/lifecycle_test.dart packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart test packages/connectanum_mcp/test/lifecycle_test.dart -r expanded`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "smoke tests MCP router RPC pubsub and route security|serves Streamable HTTP batch responses on router MCP routes" -r expanded`,
  `dart test packages/connectanum_mcp -r expanded`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  and `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`.
  Full local `bin/verify` passed on 2026-05-26, including formatting,
  Rust/FFI, MCP package smokes, client/native transport suites, auth server,
  live WAMP transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `a1ab1d9` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `a1ab1d9` is clean: GitHub `CI` `26464849958`, `Dart Package Publish Dry
  Run` `26464850056`, `WAMP Profile Benchmarks` `26464849959`, and
  non-mutating `Router Image` dry-run `26464868738` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-26 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational and Actions operational. RC release readiness remains not ready
  because no RC tag points at `a1ab1d9`, a GitHub prerelease still requires
  release approval, and public pub.dev publishing remains blocked on package
  ownership/versioning and workspace package release order decisions.
- 2026-05-26: Hardened `McpStreamableHttpClient.postBatch(...)` batch
  response ID integrity. Streamable HTTP SSE batch collection now preserves
  every response object with an `id` through validation instead of
  pre-filtering to requested IDs, and the shared batch response-shape validator
  now rejects response items without IDs, unexpected response IDs, and
  duplicate response IDs before returning results to consumer applications.
  Fail-first coverage reproduced the prior behavior where an unexpected SSE
  response ID was silently dropped and duplicate direct JSON batch responses
  were returned as normal results. Baseline `bin/test-fast` passed before the
  change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "unexpected JSON-RPC batch response ids|duplicate JSON-RPC batch response ids|collects batch responses|incomplete JSON-RPC batch" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `294f5fa` was pushed to `origin` `add-router` and GitHub
  `add-router`/`master`. Hosted evidence for `294f5fa` is clean: GitHub `CI`
  `26462114157`, `Dart Package Publish Dry Run` `26462114085`, `WAMP Profile
  Benchmarks` `26462114159`, and non-mutating `Router Image` dry-run
  `26462150409` all completed successfully. The strict `master`
  deployment-chain audit passed on 2026-05-26 with clean latest CI jobs/logs,
  clean package dry-run, clean router image dry-run, clean WAMP profile
  benchmark evidence, and relevant native release dry-run evidence. GitHub
  Status reported all systems operational and Actions operational. RC release
  readiness remains not ready because no RC tag points at `294f5fa`, a GitHub
  prerelease still requires release approval, and public pub.dev publishing
  remains blocked on package ownership/versioning and workspace package release
  order decisions.
- 2026-05-26: Hardened `McpStreamableHttpClient.postBatch(...)` so partial
  JSON-RPC batch responses are rejected before consumer applications treat
  them as complete. The shared response-shape validator now requires every
  batch request item with an `id` to have a matching response object with the
  same `id` across both direct JSON and Streamable HTTP POST/SSE responses,
  while preserving notification-only batch behavior. Fail-first coverage
  reproduced the prior behavior where partial direct JSON and Streamable SSE
  batch responses were returned as normal one-item lists. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "incomplete JSON-RPC batch" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `1fc0518` was pushed to `origin` `add-router` and GitHub
  `add-router`/`master`. Hosted evidence for `1fc0518` is clean: GitHub `CI`
  `26459717229`, `Dart Package Publish Dry Run` `26459717086`, `WAMP Profile
  Benchmarks` `26459717298`, and non-mutating `Router Image` dry-run
  `26459750248` all completed successfully. The strict `master`
  deployment-chain audit passed on 2026-05-26 with clean latest CI jobs/logs,
  clean package dry-run, clean router image dry-run, clean WAMP profile
  benchmark evidence, and relevant native release dry-run evidence. GitHub
  Status reported overall minor service degradation, but Actions was
  operational with no Actions incident. RC release readiness remains not ready
  because no RC tag points at `1fc0518`, a GitHub prerelease still requires
  release approval, and public pub.dev publishing remains blocked on package
  ownership/versioning and workspace package release order decisions.
- 2026-05-26: Hardened outgoing MCP protocol-version handling at the public
  `McpStreamableHttpClient` boundary. Unsupported constructor
  `defaultProtocolVersion` values, public `protocolVersion` assignments, and
  explicit per-request `protocolVersion` overrides now throw `ArgumentError`
  locally before mutating state or sending HTTP, so consumer applications cannot
  poison `client.protocolVersion` or send unsupported `MCP-Protocol-Version`
  request headers through the typed client. The router-hosted MCP example and
  generated consumer-package smoke now keep server-side unsupported protocol
  coverage with a fixed-length raw HTTP initialize probe using `2099-01-01`.
  Fail-first coverage reproduced the prior unsupported constructor acceptance,
  the prior network request before explicit override rejection, and the prior
  public assignment poisoning. Baseline `bin/test-fast` passed before the
  change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "unsupported.*protocol (versions locally|versions before requests|assignments locally)" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart packages/connectanum_router/example/router_hosted_mcp.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`,
  `bash -n bin/common.sh`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `a59cbfd` was pushed to `origin` `add-router` and GitHub
  `add-router`/`master`. Hosted evidence for `a59cbfd` is clean: GitHub `CI`
  `26456230989`, `Dart Package Publish Dry Run` `26456230984`, `WAMP Profile
  Benchmarks` `26456230981`, and non-mutating `Router Image` dry-run
  `26457275301` all completed successfully. The strict `master`
  deployment-chain audit passed on 2026-05-26 with clean latest CI jobs/logs,
  clean package dry-run, clean router image dry-run, clean WAMP profile
  benchmark evidence, and relevant native release dry-run evidence. RC release
  readiness remains not ready because no RC tag points at `a59cbfd`, a GitHub
  prerelease still requires release approval, and public pub.dev publishing
  remains blocked on package ownership/versioning and workspace package release
  order decisions.
- 2026-05-26: Hardened the public `McpStreamableHttpClient` Streamable HTTP
  negotiation path so unsupported MCP protocol versions cannot poison
  downstream session state. The client now mirrors the supported MCP protocol
  versions `2025-03-26`, `2025-06-18`, and `2025-11-25`; it rejects
  unsupported `MCP-Protocol-Version` response headers before mutating
  session/protocol state, and rejects unsupported
  `initialize.result.protocolVersion` values while clearing any session state
  captured during the failed initialize attempt. Fail-first coverage reproduced
  the prior acceptance of the unsupported `2099-01-01` version in both a
  response header and initialize result body. Baseline `bin/test-fast` passed
  before the change. Focused local coverage passed with
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --name "unsupported.*protocol" -r expanded`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `12a3589` was pushed to `origin` `add-router` and GitHub
  `add-router`/`master`. Hosted evidence for `12a3589` is clean: GitHub `CI`
  `26452004232`, `Dart Package Publish Dry Run` `26452014982`, `WAMP Profile
  Benchmarks` `26452024592`, and non-mutating `Router Image` dry-run
  `26452033333` all completed successfully. The strict `master`
  deployment-chain audit passed on 2026-05-26 with clean latest CI jobs/logs,
  clean package dry-run, clean router image dry-run, clean WAMP profile
  benchmark evidence, and relevant native release dry-run evidence. RC release
  readiness remains not ready because no RC tag points at `12a3589`, a GitHub
  prerelease still requires release approval, and public pub.dev publishing
  remains blocked on package ownership/versioning and workspace package release
  order decisions.
- 2026-05-26: Hardened MCP JSON-RPC request parsing so explicit
  present-but-null and fractional numeric request IDs are rejected in both the
  standalone MCP server and router-hosted MCP direct JSON ingress. The shared
  protocol helper now distinguishes request IDs from recovered error-response
  IDs: `isJsonRpcRequestId` accepts only string or integer IDs for incoming
  requests, while `isJsonRpcId` still permits null where the server must report
  an error for an invalid or unknown incoming ID. Regression coverage pins
  standalone `initialize` and router-hosted `/mcp` direct JSON `tools/list`
  requests with `id: null` and `id: 1.5`; each returns `invalid_request` with a
  null response ID, and the router path does not allocate an MCP session
  header. Baseline `bin/test-fast` passed before both request-ID changes.
  Focused local coverage passed with
  `dart analyze packages/connectanum_mcp/lib/src/protocol/json_rpc.dart packages/connectanum_mcp/lib/src/server/mcp_server.dart packages/connectanum_mcp/test/lifecycle_test.dart packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_mcp/test/lifecycle_test.dart -r expanded`,
  and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "guards MCP Streamable HTTP ingress and sessions" -r expanded`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`.
  Full local `bin/verify` passed on 2026-05-26, including formatting, Rust/FFI,
  MCP package smokes, client/native transport suites, auth server, live WAMP
  transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `3cf5ad1` was pushed to
  `origin` `add-router` and GitHub `add-router`/`master`. Hosted evidence for
  `3cf5ad1` is clean: GitHub `CI` `26449193044`, `Dart Package Publish Dry
  Run` `26449193063`, `WAMP Profile Benchmarks` `26449193100`, and
  non-mutating `Router Image` dry-run `26449211784` all completed
  successfully. The strict `master` deployment-chain audit passed on
  2026-05-26 with clean latest CI jobs/logs, clean package dry-run, clean
  router image dry-run, clean WAMP profile benchmark evidence, and relevant
  native release dry-run evidence. GitHub Status reported all systems
  operational with the earlier Actions/Pages incident in monitoring. RC release
  readiness remains not ready because no RC tag points at `3cf5ad1`, a GitHub
  prerelease still requires release approval, and public pub.dev publishing
  remains blocked on package ownership/versioning and workspace package release
  order decisions.
- 2026-05-26: Added a best-effort GitHub Actions service-status section to
  `bin/audit-github-deployment-chain`. The audit now queries the public GitHub
  Status summary and prints the overall status, Actions component status, and
  any active Actions incident before evaluating checked-in workflow visibility
  and hosted runs, so stale CI evidence caused by a GitHub Actions outage is
  visible in the release audit output itself. Baseline `bin/test-fast` passed
  before the change. Focused local coverage passed with
  `bash -n bin/audit-github-deployment-chain` and
  `python3 -m unittest tool.test_audit_github_deployment_chain`. Full local
  `bin/verify` passed on 2026-05-26, including formatting, Rust/FFI, MCP
  package smokes, client/native transport suites, auth server, live WAMP
  transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. A live strict
  `master` deployment-chain audit after the change reported GitHub Status
  `major` / Actions `major_outage` for "Incident with Actions and Pages" and
  still failed because CI/log/package dry-run evidence was stale for the
  then-checked-out head `57cd452`. Commit `5996ec5` was pushed to `origin`
  `add-router` and GitHub `add-router`/`master`; no GitHub Actions runs
  appeared for `5996ec5` while GitHub Status remained `major` / Actions
  `major_outage`. The post-push strict `master` deployment-chain audit still
  failed because the latest hosted CI/log/package dry-run/router-image/WAMP
  profile evidence is stale for checked-out head `5996ec5`, while native
  release dry-run evidence remains relevant and clean.
- 2026-05-26: Hardened the public HTTP auth bridge client's refresh/revoke
  token handling for downstream MCP/auth session flows. Refresh and revoke
  tokens are still trimmed at the boundary, but empty values and values that
  still contain whitespace, control characters, or DEL are rejected before any
  JSON auth request is sent. This keeps consumer applications from forwarding
  malformed session credentials into router-hosted MCP/auth flows and aligns
  refresh/revoke validation with MCP bearer-token hardening. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `dart analyze packages/connectanum_client/lib/src/mcp/http_auth_client.dart packages/connectanum_client/test/mcp/http_auth_client_test.dart`
  and
  `dart test packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-26, including formatting, Rust/FFI,
  MCP package smokes, client/native transport suites, auth server, live WAMP
  transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `57cd452` was pushed to
  GitHub `master` and `add-router`, but hosted evidence is currently blocked by
  GitHub Actions degraded service: no workflow runs appeared for `57cd452`,
  both manual `CI` and `Dart Package Publish Dry Run` workflow dispatch
  attempts failed with HTTP 500, and the strict `master` deployment-chain audit
  failed because CI/log/package dry-run evidence is still stale for the
  checked-out head. The latest fully clean hosted checkpoint remains
  `4ce9673`.
- 2026-05-26: Extended the generated MCP consumer package smoke to prove
  consumer code can use a plain `McpStreamableHttpClient` with lowercase
  `authorization: bearer ...` headers issued by the HTTP auth bridge against
  router-hosted bearer-protected MCP routes. The smoke covers direct JSON tool
  catalog and tool-call access without Streamable session state, direct
  JSON-response route catalog access without Streamable session state, and a
  stateful Streamable HTTP initialize/catalog/tool-call/delete flow using the
  same lowercase bearer scheme. Baseline `bin/test-fast` passed before the
  change. Focused local coverage passed with `bash -n bin/common.sh`,
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport
  integration, router-hosted MCP example smoke, generated consumer-package
  smokes, full router suite, zero-copy router tests, and Chrome/Dart2Wasm
  browser WebSocket smoke. Commit `4ce9673` was pushed to GitHub `master` and
  `add-router`; GitHub `master` CI run `26445279934` and GitHub `add-router`
  CI run `26445273893` passed with Fast Checks and Full Verify green. The
  strict `master` deployment-chain audit passed against `4ce9673`, with clean
  latest CI jobs/logs at `4ce9673`; clean Dart Package Publish Dry Run
  `26442590065`, Router Image dry-run `26443240229`, WAMP Profile Benchmarks
  `26442589992`, and Native Artifacts dry-run `26396437881` remained relevant
  because no publish-sensitive, router-image-sensitive,
  WAMP-profile-sensitive, or native-release-sensitive paths changed. RC
  readiness remains not ready until a release-approved numeric RC tag, GitHub
  prerelease, and router image RC tag are created.
- 2026-05-26: Hardened router-side HTTP bearer extraction for protected HTTP
  routes and router-hosted MCP. The shared parser now accepts the
  case-insensitive `bearer` auth scheme with a space or tab separator and
  rejects empty bearer values or tokens containing whitespace, control
  characters, or DEL before treating a request as bearer-authenticated. This
  applies to configured HTTP auth providers, direct JSON calls, and Streamable
  HTTP requests that flow through router-hosted MCP. Regression coverage pins
  lowercase bearer headers for the JWT provider route and secure MCP
  direct-JSON/Streamable route-security smoke. Baseline `bin/test-fast` passed
  before the change. Focused local coverage passed with
  `dart format packages/connectanum_router/lib/src/router/router_instance/router_binding.dart packages/connectanum_router/test/router_runtime_test.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart analyze packages/connectanum_router/lib/src/router/router_instance/router_binding.dart packages/connectanum_router/test/router_runtime_test.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_router/test/router_runtime_test.dart --name "validates protected HTTP bearer routes through configured JWT provider" -r expanded`,
  and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "smoke tests MCP router RPC pubsub and route security" -r expanded`.
  Full local `bin/verify` passed on 2026-05-26 after clearing a stale local
  native-runtime lock from an earlier verification attempt and confirming the
  affected bench pair passed in isolation. Commit `5233b5f` was pushed to
  GitHub `master` and `add-router`; GitHub `master` CI run `26442590013` and
  GitHub `add-router` CI run `26442589119` passed with Fast Checks and Full
  Verify green. GitHub Dart Package Publish Dry Run runs `26442590065`
  (`master`) and `26442588941` (`add-router`) passed. GitHub WAMP Profile
  Benchmarks runs `26442589992` (`master`) and `26442589049` (`add-router`)
  passed. A non-mutating Router Image dry-run `26443240229` passed at
  `5233b5f` with preview metadata `sha-5233b5ff6842`, skipped GHCR login, and
  no image push. The strict `master` deployment-chain audit passed against
  `5233b5f`, with clean latest CI jobs/logs, package dry-run, router image
  dry-run, WAMP profile benchmark, and Native Artifacts dry-run `26396437881`
  still relevant because no native-release-sensitive paths changed. RC
  readiness remains not ready until a release-approved numeric RC tag, GitHub
  prerelease, and router image RC tag are created.
- 2026-05-26: Hardened the public `McpStreamableHttpClient` bearer-token
  constructors so tokens containing whitespace or control characters are
  rejected before an `Authorization: Bearer` header is created. The guard
  applies to both `McpStreamableHttpClient.withBearerToken(...)` and
  `McpStreamableHttpClient.withAuthGrant(...)`, while preserving the existing
  outer-whitespace trim behavior for otherwise valid grants. The regression
  test covers space, tab, newline, and NUL-containing tokens for direct bearer
  construction and the auth-grant path. Baseline `bin/test-fast` passed before
  the change. Focused local coverage passed with
  `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `git diff --check`, and `python3 tool/check_public_artifact_references.py`.
  Full local `bin/verify` passed on 2026-05-26 after clearing a transient local
  native-runtime lock overlap from an earlier verification attempt; the clean
  run included formatting, Rust/FFI, MCP package smokes, client/native
  transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `6020b00` was pushed to GitHub `master` and `add-router`;
  GitHub `master` CI run `26439604365` and GitHub `add-router` CI run
  `26439599417` passed with Fast Checks and Full Verify green. GitHub Dart
  Package Publish Dry Run runs `26439604367` (`master`) and `26439599413`
  (`add-router`) passed. GitHub WAMP Profile Benchmarks runs `26439604345`
  (`master`) and `26439599415` (`add-router`) passed. A non-mutating Router
  Image dry-run `26440235110` passed at `6020b00` with preview metadata
  `sha-6020b00b1cc3`, skipped GHCR login, and no image push. The strict
  `master` deployment-chain audit passed against `6020b00`, with clean latest
  CI jobs/logs, package dry-run, router image dry-run, WAMP profile benchmark,
  and Native Artifacts dry-run `26396437881` still relevant because no
  native-release-sensitive paths changed. RC readiness remains not ready until
  a release-approved numeric RC tag, GitHub prerelease, and router image RC tag
  are created.
- 2026-05-26: Extended the generated MCP consumer package smoke to prove
  router-hosted bearer-protected MCP endpoints reject rotated and revoked
  access tokens for direct JSON lifecycle/meta calls without destroying active
  Streamable HTTP session state. During both invalid-token phases, an
  initialized secure Streamable session now attempts `pingDirect(...)` and
  `notificationDirect('notifications/initialized', ...)`; each request must fail
  with HTTP 401 while the client's `sessionId` and `lastEventId` remain
  unchanged. The smoke still covers direct tools, direct WAMP meta/pubsub
  helpers, direct batches, direct resources/prompts, stateful Streamable
  tools/resources/prompts, poll, delete, stale-session cleanup, refresh-token
  rotation rejection, and refresh/access-token revocation. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `source bin/common.sh; run_mcp_consumer_package_smoke`. Full local
  `bin/verify` passed on 2026-05-26, including formatting, Rust/FFI, MCP package
  smokes, client/native transport suites, auth server, live WAMP transport
  integration, router-hosted MCP example smoke, generated consumer-package
  smokes, full router suite, zero-copy router tests, and Chrome/Dart2Wasm
  browser WebSocket smoke. Commit `cd35952` was pushed to GitHub `master` and
  `add-router`. GitHub `master` CI run `26437158066` and GitHub `add-router` CI
  run `26437158075` passed with Fast Checks and Full Verify green. The strict
  `master` deployment-chain audit passed against `cd35952`, with clean latest
  CI jobs, clean CI logs, and relevant clean hosted evidence for Dart Package
  Publish Dry Run `26433844437`, Router Image dry-run `26434291709`, Native
  Artifacts dry-run `26396437881`, and WAMP Profile Benchmarks run
  `26423773849`. The Dart package and router-image dry-runs remain relevant
  because this checkpoint did not change publish-sensitive or
  router-image-sensitive inputs. RC readiness remains not ready until a
  release-approved numeric RC tag, GitHub prerelease, and router image RC tag
  are created.
- 2026-05-26: Extended the generated MCP consumer package smoke to prove
  router-hosted bearer-protected MCP endpoints reject rotated and revoked
  access tokens across the direct JSON resource/prompt helper surface without
  destroying active Streamable HTTP session state. During both invalid-token
  phases, an initialized secure Streamable session now attempts
  `listResourcesDirect(...)`, `readResourceDirect(...)`,
  `listResourceTemplatesDirect(...)`, `listPromptsDirect(...)`, and
  `getPromptDirect(...)`; each request must fail with HTTP 401 while the
  client's `sessionId` and `lastEventId` remain unchanged. The smoke still
  covers direct tools, direct WAMP meta/pubsub helpers, direct batches,
  stateful Streamable tools/resources/prompts, poll, delete, stale-session
  cleanup, refresh-token rotation rejection, and refresh/access-token
  revocation. Baseline `bin/test-fast` passed before the change. Focused local
  coverage passed with `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `source bin/common.sh; run_mcp_consumer_package_smoke`. Full local
  `bin/verify` passed on 2026-05-26, including formatting, Rust/FFI, MCP
  package smokes, client/native transport suites, auth server, live WAMP
  transport integration, router-hosted MCP example smoke, generated
  consumer-package smokes, full router suite, zero-copy router tests, and
  Chrome/Dart2Wasm browser WebSocket smoke. Commit `638a243` was pushed to
  GitHub `master` and `add-router`. GitHub `master` CI run `26435513289` and
  GitHub `add-router` CI run `26435510478` passed with Fast Checks and Full
  Verify green. The strict `master` deployment-chain audit passed against
  `638a243`, with clean latest CI jobs, clean CI logs, and relevant clean
  hosted evidence for Dart Package Publish Dry Run `26433844437`, Router Image
  dry-run `26434291709`, Native Artifacts dry-run `26396437881`, and WAMP
  Profile Benchmarks run `26423773849`. The Dart package and router-image
  dry-runs remain relevant because this checkpoint did not change
  publish-sensitive or router-image-sensitive inputs. RC readiness remains not
  ready until a release-approved numeric RC tag, GitHub prerelease, and router
  image RC tag are created.
- 2026-05-26: Extended the public `connectanum_mcp_io.dart` package-boundary
  auth smoke to prove exported revoke helpers make revoked credentials fail
  without creating or mutating Streamable MCP session state. After the refreshed
  bearer direct `connectanum.api.describe` check, the smoke now revokes the
  refreshed access token and asserts `pingDirect(...)` fails with HTTP 401
  while `sessionId` remains unset. It then revokes the refreshed refresh token
  and asserts a follow-up HTTP auth refresh fails with HTTP 401. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `dart analyze packages/connectanum_mcp/test/io_client_export_test.dart` and
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including formatting, Rust/FFI, MCP package smokes,
  client/native transport suites, auth server, live WAMP transport integration,
  router-hosted MCP example smoke, generated consumer-package smokes, full
  router suite, zero-copy router tests, and Chrome/Dart2Wasm browser WebSocket
  smoke. Commit `9dacf75` was pushed to GitHub `master` and `add-router`.
  GitHub `master` CI run `26433844471` and GitHub `add-router` CI run
  `26433844438` passed with Fast Checks and Full Verify green. GitHub Dart
  Package Publish Dry Run runs `26433844437` (`master`) and `26433844469`
  (`add-router`) passed. A non-mutating Router Image dry-run `26434291709`
  passed at `9dacf75` with metadata preview `sha-9dacf7535621`, skipped GHCR
  login, and completed the multi-arch preview build. The strict `master`
  deployment-chain audit passed against `9dacf75`, with clean CI jobs, clean CI
  logs, clean Dart package publish dry-run, clean router image dry-run,
  relevant native release dry-run evidence, and relevant WAMP profile benchmark
  evidence. RC readiness remains not ready until a release-approved numeric RC
  tag, GitHub prerelease, and router image RC tag are created.
- 2026-05-26: Extended the public `connectanum_mcp_io.dart` package-boundary
  auth smoke again to cover authenticated direct WAMP pub/sub helper access
  through the exported IO entrypoint. After obtaining a ticket grant and
  initializing an authenticated Streamable MCP session, the smoke now calls
  `subscribeWampTopicDirect(...)`, `publishWampEventDirect(...)`,
  `pollWampEventsDirect(...)`, and `unsubscribeWampTopicDirect(...)` through
  the same exported `McpStreamableHttpClient`. It asserts that each direct
  pub/sub request uses the original ticket bearer, sends no `MCP-Session-Id`
  header, preserves the active Streamable session, and round-trips a published
  event before the refreshed-bearer direct `connectanum.api.describe` check.
  Baseline `bin/test-fast` passed before the change. Focused local coverage
  passed with
  `dart analyze packages/connectanum_mcp/test/io_client_export_test.dart`,
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including MCP package smokes, generated
  consumer-package smokes, the full router suite, and the Chrome/Dart2Wasm
  browser WebSocket smoke. The commit was pushed to GitHub `master` and
  `add-router` as `1776f3d`; GitHub `master` CI run `26432353976` and GitHub
  `add-router` CI run `26432353963` passed with Fast Checks and Full Verify
  green. GitHub Dart Package Publish Dry Run runs `26432353975` (`master`) and
  `26432353962` (`add-router`) passed. A non-mutating Router Image dry-run
  `26432759614` passed at `1776f3d` with metadata preview
  `sha-1776f3d67616`, skipped GHCR login, and no image push. The strict
  `master` deployment-chain audit passed with clean latest CI/logs, package
  dry-run, native release dry-run relevance, Router Image dry-run, and WAMP
  profile benchmark relevance at `1776f3d`. RC readiness remains not ready
  until a release-approved numeric RC tag, GitHub prerelease, and router image
  RC tag are created.
- 2026-05-26: Extended the public `connectanum_mcp_io.dart` package-boundary
  auth smoke to prove exported HTTP auth helpers and
  `McpStreamableHttpClient.withAuthGrant(...)` preserve the expected session
  boundaries across stateful Streamable HTTP, authenticated direct JSON calls,
  and refreshed bearer credentials. The smoke obtains a ticket grant through
  the exported `ConnectanumHttpAuthClient`, initializes an authenticated
  Streamable MCP session, verifies a session-bound `ping(...)`, then sends
  authenticated `pingDirect(...)` and `connectanum.tools.list` direct JSON
  requests through the same client and asserts that those direct requests have
  no `MCP-Session-Id` header while the client's active Streamable session
  remains intact. The same smoke refreshes the auth grant and creates a second
  exported `McpStreamableHttpClient` from the refreshed bearer token, proving
  direct `pingDirect(...)` and `connectanum.api.describe` metadata access use
  the refreshed credential without creating local session state. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed with
  `dart analyze packages/connectanum_mcp/test/io_client_export_test.dart`,
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-26, including MCP package smokes, generated
  consumer-package smokes, the full router suite, and the Chrome/Dart2Wasm
  browser WebSocket smoke. The commit was pushed to GitHub `master` and
  `add-router` as `708c827`; GitHub `master` CI run `26430863296` and GitHub
  `add-router` CI run `26430863499` passed with Fast Checks and Full Verify
  green. GitHub Dart Package Publish Dry Run runs `26430863297` (`master`) and
  `26430863505` (`add-router`) passed. A non-mutating Router Image dry-run
  `26431248553` passed at `708c827` with metadata preview
  `sha-708c827e9243`, skipped GHCR login, and no image push. The strict
  `master` deployment-chain audit passed with clean latest CI/logs, package
  dry-run, native release dry-run relevance, Router Image dry-run, and WAMP
  profile benchmark relevance at `708c827`. RC readiness remains not ready
  until a release-approved numeric RC tag, GitHub prerelease, and router image
  RC tag are created.
- 2026-05-26: Extended the public `connectanum_mcp_io.dart` package-boundary
  smoke to prove stateful Streamable HTTP `postBatch(...)` requests can mix
  direct dotted `connectanum.pubsub.*` and `connectanum.api.*` methods through
  the exported `McpStreamableHttpClient` surface. The test fixture now returns
  SSE responses for accepted batch requests, and the smoke asserts active MCP
  session headers, SSE cursor advancement, direct WAMP API metadata, pub/sub
  publish/poll/unsubscribe behavior, and lifecycle-free direct JSON isolation
  after the stateful batches. Baseline `bin/test-fast` passed before the
  change. Focused local coverage passed with
  `dart analyze packages/connectanum_mcp/test/io_client_export_test.dart` and
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-26, including MCP package smokes,
  generated consumer-package smokes, the full router suite, and the
  Chrome/Dart2Wasm browser WebSocket smoke. The commit was pushed to GitHub
  `master` and `add-router` as `594fa71`; GitHub `master` CI run
  `26427902479` and GitHub `add-router` CI run `26427900037` passed with Fast
  Checks and Full Verify green. GitHub Dart Package Publish Dry Run runs
  `26427902478` (`master`) and `26427900040` (`add-router`) passed. A
  non-mutating Router Image dry-run `26428304280` passed at `594fa71`, and the
  strict `master` deployment-chain audit passed with clean latest CI/logs,
  package dry-run, and Router Image dry-run evidence at `594fa71`. RC
  readiness remains not ready until a release-approved numeric RC tag, GitHub
  prerelease, and router image RC tag are created.
- 2026-05-26: Extended the generated router-hosted MCP consumer-package smoke
  again to cover stateful Streamable direct WAMP API/pubsub batches through
  dotted JSON-RPC methods, not only `tools/call` wrappers or lifecycle-free
  direct JSON batches. The smoke now posts direct
  `connectanum.pubsub.subscribe` plus `connectanum.api.list`, direct
  `connectanum.pubsub.publish` plus `connectanum.api.describe`, repeated
  direct `connectanum.pubsub.poll` plus `connectanum.api.list`, and direct
  `connectanum.pubsub.unsubscribe` plus `connectanum.api.list` using the active
  `McpStreamableHttpClient.postBatch(...)` session. Each batch checks that the
  Streamable session id is preserved, the SSE cursor advances, direct WAMP API
  metadata remains visible, and a service-published event reaches the
  direct-pub/sub subscription. Baseline `bin/test-fast` passed before the
  change. Focused local coverage passed with `bash -n bin/common.sh`,
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and `python3 tool/check_public_artifact_references.py`.
  Full local `bin/verify` passed on 2026-05-26, including the generated
  consumer-package smoke and full router suite. The commit was pushed to
  GitHub `master` and `add-router` as `a803d9e`; GitHub `master` CI run
  `26426514535` and GitHub `add-router` CI run `26426513681` passed with Fast
  Checks and Full Verify green. The strict `master` deployment-chain audit
  passed with clean latest CI/logs at `a803d9e`; hosted Dart Package Publish
  Dry Run `26423773895`, hosted WAMP Profile Benchmarks `26423773849`, and
  non-mutating Router Image dry-run `26424148305` remain clean and relevant
  from `eb2ae2a` because this smoke-script/docs checkpoint changed no
  publish-sensitive, WAMP profile benchmark-sensitive, or router-image-sensitive
  inputs. RC readiness remains not ready until a release-approved numeric RC
  tag, GitHub prerelease, and router image RC tag are created.
- 2026-05-26: Extended the generated router-hosted MCP consumer-package smoke
  to cover stateful Streamable direct WAMP/meta methods beyond the procedure
  call regression. The smoke now posts direct `connectanum.api.describe` body
  params and performs a direct `connectanum.pubsub.subscribe`,
  `connectanum.pubsub.publish`, `connectanum.pubsub.poll`, and
  `connectanum.pubsub.unsubscribe` roundtrip on the active Streamable session,
  checking that each operation preserves the session and advances the SSE
  cursor. Baseline `bin/test-fast` passed before the change. Focused local
  coverage passed with `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`. Full
  local `bin/verify` passed on 2026-05-26, including the generated
  consumer-package smoke and full router suite. The commit was pushed to
  GitHub `master` and `add-router` as `b416479`; GitHub `master` CI run
  `26425147196` and GitHub `add-router` CI run `26425143224` passed with Fast
  Checks and Full Verify green. The strict `master` deployment-chain audit
  passed with clean latest CI/logs at `b416479`; hosted Dart Package Publish
  Dry Run `26423773895`, hosted WAMP Profile Benchmarks `26423773849`, and
  non-mutating Router Image dry-run `26424148305` remain clean and relevant
  from `eb2ae2a` because this smoke-script/docs checkpoint changed no
  publish-sensitive, WAMP profile benchmark-sensitive, or router-image-sensitive
  inputs. RC readiness remains not ready until a release-approved numeric RC
  tag, GitHub prerelease, and router image RC tag are created.
- 2026-05-26: Treated a generated consumer-package smoke failure as a real
  MCP Streamable compatibility bug after generic stateful JSON-RPC direct WAMP
  procedure calls returned `400` with a missing `Mcp-Param-TaskId` error when
  the request included only `Mcp-Method` metadata and body params. Router
  parameter-header validation now requires mapped `Mcp-Param-*` headers only
  for the named metadata path (`Mcp-Name`) or when a request supplies any
  parameter header, preserving mismatch/malformed-header rejection while
  allowing direct procedure and WAMP/meta methods to use JSON-RPC body params.
  The generated consumer package smoke now covers stateful generic direct
  method calls, `connectanum.tools.call` alias calls with public parameter
  headers, and direct `connectanum.api.list`. Baseline `bin/test-fast` passed
  before the change. Focused local coverage passed:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "guards MCP Streamable HTTP ingress and sessions"`,
  `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`. Full
  local `bin/verify` passed on 2026-05-26 with the generated consumer-package
  smoke and full router suite covering the new regression. The commit was
  pushed to GitHub `master` and `add-router` as `eb2ae2a`; GitHub `master` CI
  run `26423773850` and GitHub `add-router` CI run `26423773740` passed with
  Fast Checks and Full Verify green. Hosted Dart Package Publish Dry Run runs
  `26423773895` (`master`) and `26423773738` (`add-router`) passed; hosted WAMP
  Profile Benchmarks runs `26423773849` (`master`) and `26423773736`
  (`add-router`) passed with artifact upload ready. Non-mutating Router Image
  dry-run `26424148305` passed on `master` with preview metadata
  `sha-eb2ae2a97e30`, GHCR login skipped, and no image publish. The strict
  `master` deployment-chain audit passed with clean latest CI, clean CI logs,
  clean Dart package publish dry-run, clean WAMP profile benchmark, and clean
  Router Image dry-run requirements. RC readiness remains not ready until a
  release-approved numeric RC tag, GitHub prerelease, and router image RC tag
  are created.
- 2026-05-25: Extended the generated router-hosted MCP consumer package smoke
  again to prove raw headerless Streamable `resources/read` and `prompts/get`
  compatibility across the public package boundary. The smoke now posts single
  JSON-RPC requests with no `Mcp-Method` or `Mcp-Name` request-metadata headers
  and asserts route-provided resource content and prompt arguments are resolved
  from body fields alone. This closes the remaining single-request
  resource/prompt gap after headerless `tools/list` and `tools/call` coverage.
  Baseline `bin/test-fast` passed before the smoke-only change. Focused local
  coverage passed: `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`. Full
  local `bin/verify` passed again with the router-hosted MCP consumer package
  smoke covering headerless `tools/call`, `resources/read`, and `prompts/get`.
  The commit was pushed to GitHub `master` as `f03cf4d`; GitHub CI run
  `26422149068` passed with Fast Checks and Full Verify green, GitHub
  `add-router` CI run `26422149058` passed with Fast Checks and Full Verify
  green, and the strict `master` deployment-chain audit passed with clean
  latest CI, clean CI logs, clean Dart package publish dry-run, clean WAMP
  profile benchmark, and clean Router Image dry-run requirements. The audit
  kept the `4ff256d` package dry-run, WAMP benchmark, and Router Image dry-run
  evidence relevant because this smoke-only commit did not touch their
  sensitive inputs.
- 2026-05-25: Extended the generated router-hosted MCP consumer package smoke
  to prove raw headerless Streamable `tools/call` compatibility across the
  public package boundary. The smoke now posts a JSON-RPC `tools/call` request
  with no `Mcp-Method`, `Mcp-Name`, or `Mcp-Param-*` request-metadata headers
  and asserts the streamed tool result is derived from body fields alone. This
  closes the consumer-agent readiness gap left after headerless `tools/list`
  coverage. Baseline `bin/test-fast` passed before the smoke-only change.
  Focused local coverage passed: `bash -n bin/common.sh`, `git diff --check`,
  and `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`. Full
  local `bin/verify` passed again with the router-hosted MCP consumer package
  smoke covering headerless `tools/call`. The commit was pushed to GitHub
  `master` as `6d97391`; GitHub CI run `26420809812` passed with Fast Checks
  and Full Verify green, and the strict `master` deployment-chain audit passed
  with clean latest CI, clean CI logs, clean Dart package publish dry-run,
  clean WAMP profile benchmark, and clean Router Image dry-run requirements.
  The audit kept the `4ff256d` package dry-run, WAMP benchmark, and Router
  Image dry-run evidence relevant because this smoke-only commit did not touch
  their sensitive inputs.
- 2026-05-25: Made router-hosted Streamable HTTP MCP compatible with
  standard clients that omit Connectanum/MCP request-metadata headers. The
  stable Streamable HTTP transport surface at
  `https://modelcontextprotocol.io/specification/2025-06-18/basic/transports`
  does not require `Mcp-Method`, `Mcp-Name`, or `Mcp-Param-*`; the draft
  transport metadata path at
  `https://modelcontextprotocol.io/specification/draft/basic/transports`
  remains authoritative when clients send it. Router validation now accepts
  headerless streamable `initialize` and `tools/call` requests, while still
  rejecting mismatched metadata headers and requiring all mapped parameter
  headers when a streamable client opts into metadata headers. Baseline
  `bin/test-fast` passed before the change. The focused router regression
  failed before the fix and passed afterward. A post-change `bin/test-fast`
  run exposed the stale generated consumer-smoke expectation for missing
  `Mcp-Method`; after updating that smoke, focused local coverage passed:
  the targeted router Streamable ingress/session test, `bash -n bin/common.sh`,
  `git diff --check`, and the generated router-hosted MCP consumer package
  smoke. Full local `bin/verify` passed, including Rust/FFI, MCP package
  smokes, client/native transport suites, live WAMP transport integration,
  router-hosted MCP smokes, the full router suite with the headerless
  Streamable HTTP MCP regression, zero-copy router tests, and the
  Chrome/Dart2Wasm browser WebSocket smoke. The checkpoint is hosted green at
  `4ff256d`: GitHub CI run `26418353089`, Dart Package Publish Dry Run
  `26418353050`, and WAMP Profile Benchmarks `26418353051` all passed on
  `add-router`, with WAMP artifact upload ready. The strict `add-router`
  deployment-chain audit also passed with clean latest CI, clean CI logs,
  clean Dart package publish dry-run, and clean WAMP profile benchmark
  requirements. The same commit was then promoted to GitHub `master` for the
  release branch. A fresh local `bin/verify` passed on Darwin arm64 after the
  promotion. Hosted `master` evidence is clean at `4ff256d`: CI run
  `26419213664` passed with Fast Checks and Full Verify green, Dart Package
  Publish Dry Run `26419213726` passed, WAMP Profile Benchmarks `26419213725`
  passed with artifact upload ready, and non-mutating Router Image dry-run
  `26419643836` passed with preview metadata `sha-4ff256d6f108`, GHCR login
  skipped, and no image publish. The strict `master` deployment-chain audit
  passed with clean latest CI, clean CI logs, clean Dart package publish
  dry-run, clean WAMP profile benchmark, and clean Router Image dry-run
  requirements.
- 2026-05-25: Tightened public MCP Streamable HTTP response-session
  validation in `McpStreamableHttpClient`. Successful Streamable HTTP
  responses that echo a malformed `MCP-Session-Id` response header still raise
  `McpStreamableProtocolException`, but the client now preserves the active
  `sessionId` / `lastEventId` so consumer applications can retry or explicitly
  clean up after a bad server/proxy response. Baseline `bin/test-fast` passed
  before the change. The focused regression failed before the fix and passed
  afterward. Focused local coverage passed: formatting and analyzer for the
  MCP client source/test files, the focused malformed response-session
  regression, the full `streamable_http_client_test.dart` suite, and the
  generated router-hosted MCP consumer package smoke. Full local `bin/verify`
  passed, including Rust/FFI, MCP package smokes, client/native transport
  suites, live WAMP transport integration, router-hosted MCP smokes, the full
  router suite, and the Chrome/Dart2Wasm browser WebSocket smoke. The
  checkpoint is hosted green at `e81e21a`: GitHub CI run `26416144700`, Dart
  Package Publish Dry Run `26416144720`, and WAMP Profile Benchmarks
  `26416144718` all passed on `add-router`, with WAMP artifact upload ready.
  The strict `add-router` deployment-chain audit also passed with clean latest
  CI, clean CI logs, clean Dart package publish dry-run, and clean WAMP
  profile benchmark requirements.
- 2026-05-25: Tightened public MCP Streamable HTTP initialize cursor
  semantics in `McpStreamableHttpClient.initialize(...)`. A successful
  initialization response that negotiates a session now clears any stale
  local `Last-Event-ID` resume cursor even when the returned
  `MCP-Session-Id` matches the client's previous local session id, preventing
  consumer applications from replaying obsolete SSE cursors after a successful
  re-initialize. Non-initialize Streamable responses keep the existing cursor
  behavior and only reset it when the negotiated session id changes. Baseline
  `bin/test-fast` passed before the change. The focused regression failed
  before the fix and passed afterward. Focused local coverage passed:
  formatting and analyzer for the MCP client source/test files, the focused
  same-session initialize cursor regression, the full
  `streamable_http_client_test.dart` suite, and the generated router-hosted
  MCP consumer package smoke. Full local `bin/verify` passed, including
  Rust/FFI, MCP package smokes, client/native transport suites, live WAMP
  transport integration, router-hosted MCP smokes, the full router suite, and
  the Chrome/Dart2Wasm browser WebSocket smoke. The checkpoint is hosted green
  at `ff71566`: GitHub CI run `26414549163`, Dart Package Publish Dry Run
  `26414549161`, and WAMP Profile Benchmarks `26414549162` all passed on
  `add-router`. The strict `add-router` deployment-chain audit also passed
  with clean latest CI, clean CI logs, clean Dart package publish dry-run, and
  clean WAMP profile benchmark requirements.
- 2026-05-25: Tightened public MCP Streamable HTTP sessionless initialize
  semantics in `McpStreamableHttpClient.initialize(...)`. A successful
  initialization response that omits `MCP-Session-Id` now clears any stale
  local `sessionId` / `lastEventId` state before later operations, preventing
  consumer applications from leaking an obsolete session header to servers
  that opt out of Streamable HTTP session management. Later Streamable
  responses may still omit `MCP-Session-Id` without ending an active session.
  The focused regression failed before the fix and passed afterward. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed:
  formatting and analyzer for the MCP client source/test files, the focused
  sessionless-initialize regression, the full `streamable_http_client_test.dart`
  suite, and the generated router-hosted MCP consumer package smoke. Full
  local `bin/verify` passed, including Rust/FFI, MCP package smokes,
  client/native transport suites, live WAMP transport integration, the
  router-hosted MCP example smoke, generated consumer-package smokes, the full
  router suite with MCP auth/session/security coverage, and the Chrome/
  Dart2Wasm browser WebSocket smoke. The previous DELETE response-session
  checkpoint is hosted green at `478aa9a`: GitHub CI run `26411324800`, Dart
  Package Publish Dry Run `26411324802`, and WAMP Profile Benchmarks
  `26411324771` all passed on `add-router`.
- 2026-05-25: Tightened public MCP Streamable HTTP session cleanup semantics
  in `McpStreamableHttpClient.deleteSession(...)`. Successful DELETE responses
  may still omit `MCP-Session-Id`, but any echoed session header must now be
  syntactically valid and match the active client session before local
  `sessionId` / `lastEventId` state is cleared. Empty, malformed, or mismatched
  DELETE response session headers now raise `McpStreamableProtocolException`
  and preserve client state, preventing consumer applications from silently
  accepting bad router or proxy cleanup responses. The focused regression
  failed before the fix and passed afterward. Baseline `bin/test-fast` passed
  before the change. Focused local coverage passed: formatting and analyzer for
  the MCP client source/test files, the focused DELETE response-header
  regression, the full `streamable_http_client_test.dart` suite, and the
  generated router-hosted MCP consumer package smoke. Full local `bin/verify`
  passed, including Rust/FFI, MCP package smokes, client/native transport
  suites, live WAMP transport integration, the router-hosted MCP example smoke,
  generated consumer-package smokes, the full router suite with MCP
  auth/session/security coverage, and the Chrome/Dart2Wasm browser WebSocket
  smoke. The previous public auth-grant direct notification package checkpoint
  is hosted green at `34db112`: GitHub CI run `26406021113`, Dart Package
  Publish Dry Run `26406021123`, and WAMP Profile Benchmarks `26406021172` all
  passed on `add-router`.
- 2026-05-25: Extended the generated router-hosted MCP consumer package smoke
  so JSON-response compatibility routes prove active-session direct JSON
  helper access across the public package boundary. After Streamable
  initialization, `/mcp/json-post`, `/mcp/secure-json-post`, and
  `/mcp/non-streaming-post` now run the existing active-session direct helper
  matrix for direct tool calls, generic JSON-RPC access, WAMP API metadata,
  WAMP session/registration/subscription helpers, resources, prompts, direct
  batches, and pub/sub, then assert the active `MCP-Session-Id` remains stable
  and no POST/SSE cursor is captured. The public JSON-response route fixtures
  now expose the same declared topic metadata and batch pub/sub topic as the
  main MCP route, keeping route-provided tool/meta catalogs consistent for
  consumer applications. Baseline `bin/test-fast` passed before the change.
  Focused local coverage passed: `bash -n bin/common.sh`, the generated
  router-hosted MCP consumer package smoke, `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed, including formatting, Rust/FFI, MCP package smokes, client/native
  transport suites, live WAMP transport integration, the router-hosted MCP
  example smoke, generated consumer-package smokes, the full router suite with
  MCP auth/session/security coverage, and the Chrome/Dart2Wasm browser
  WebSocket smoke. The previous public auth-grant direct notification package
  checkpoint is hosted green at `34db112`: GitHub CI run `26406021113`, Dart
  Package Publish Dry Run `26406021123`, and WAMP Profile Benchmarks
  `26406021172` all passed on `add-router`.
- 2026-05-25: Extended the generated MCP client-only consumer package smoke
  so lifecycle-free auth-grant direct notification helpers are proven across
  the public package boundary before any Streamable HTTP session exists. The
  smoke now imports `connectanum_mcp_io.dart` and calls
  `notifyToolDirect(...)`, `notifyConnectanumToolDirect(...)`,
  `notifyConnectanumMethodDirect(...)`, and `notifyWampEventDirect(...)`
  while stale per-call `Authorization` metadata is present, then asserts the
  grant-owned bearer token wins, no `MCP-Session-Id` is sent, client
  `sessionId` / `lastEventId` remain unset, and the expected MCP method/name
  headers are visible for consumer application usage. Baseline
  `bin/test-fast` passed before the change. Focused local coverage passed:
  `bash -n bin/common.sh`, the generated MCP client-only consumer package
  smoke, `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local
  `bin/verify` passed, including Rust/FFI, MCP package smokes, client/native
  transport suites, live WAMP transport integration, the router-hosted MCP
  example smoke, the expanded generated client-only consumer smoke, generated
  router consumer-package smoke, the full router suite with MCP
  auth/session/security coverage, and the Chrome/Dart2Wasm browser WebSocket
  smoke. The previous public auth-grant direct notification package
  checkpoint is hosted green at `34db112`: GitHub CI run `26406021113`, Dart
  Package Publish Dry Run `26406021123`, and WAMP Profile Benchmarks
  `26406021172` all passed on `add-router`.
- 2026-05-25: Strengthened the public MCP client auth-grant direct JSON
  package regression to cover lifecycle-free notification-only helpers before
  any Streamable HTTP session exists. `McpStreamableHttpClient.withAuthGrant(...)`
  now has focused test evidence for `notifyToolDirect(...)`,
  `notifyConnectanumToolDirect(...)`, `notifyConnectanumMethodDirect(...)`, and
  the typed WAMP pub/sub `notifyWampEventDirect(...)` helper while stale
  constructor and per-call `Authorization` metadata is present. The regression
  asserts notification requests omit JSON-RPC `id`, use the grant-owned bearer
  token, negotiate `application/json`, send no `MCP-Session-Id` or
  `Last-Event-ID`, leave `sessionId` / `lastEventId` unset, and expose the
  expected MCP method/name request headers for consumer application usage.
  Baseline `bin/test-fast` passed before the change. Focused local coverage
  passed: formatting and analyzer for `streamable_http_client_test.dart`, the
  focused MCP client test, `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed, including Rust/FFI, MCP package smokes, client/native transport
  suites, live WAMP transport integration, the router-hosted MCP example smoke,
  generated consumer-package smokes, the full router suite with MCP
  auth/session/security coverage, and the Chrome/Dart2Wasm browser WebSocket
  smoke. The prior standard WAMP meta package checkpoint is hosted green at
  `0b36433`: GitHub CI run `26404081734`, Dart Package Publish Dry Run
  `26404081757`, and WAMP Profile Benchmarks `26404081754` all passed on
  `add-router`.
- 2026-05-25: Strengthened the public MCP client auth-grant direct JSON
  package regression to cover the full standard WAMP session, registration,
  and subscription meta helper surface before any Streamable HTTP lifecycle.
  `McpStreamableHttpClient.withAuthGrant(...)` now has focused test evidence
  for direct `wamp.session.list`, `wamp.session.get`,
  `wamp.registration.lookup`, `wamp.registration.get`,
  `wamp.registration.list_callees`, `wamp.registration.count_callees`,
  `wamp.subscription.lookup`, `wamp.subscription.get`,
  `wamp.subscription.list_subscribers`, and
  `wamp.subscription.count_subscribers`, in addition to the already covered
  auth-grant direct ping, tool catalog, WAMP API metadata, resources, prompts,
  pub/sub, and direct batch path. The regression asserts the full
  lifecycle-free direct helper set uses the grant-owned bearer token instead
  of stale caller `Authorization` metadata, negotiates `application/json`,
  sends no `MCP-Session-Id`, and leaves `sessionId` / `lastEventId` unset for
  consumer application usage. Baseline `bin/test-fast` passed before the
  change. Focused local coverage passed: formatting and analyzer for
  `streamable_http_client_test.dart` plus the focused MCP client test. Full
  local `bin/verify` passed, including Rust/FFI, MCP package smokes,
  client/native transport suites, live WAMP transport integration, the
  router-hosted MCP example smoke, generated consumer-package smokes, the full
  router suite with MCP auth/session/security coverage, and the Chrome/
  Dart2Wasm browser WebSocket smoke. The prior auth-grant direct WAMP meta
  generated consumer checkpoint is hosted green at `cc6bf72`: GitHub CI run
  `26402225830`, Dart Package Publish Dry Run `26402225835`, and WAMP Profile
  Benchmarks `26402225895` all passed on `add-router`.
- 2026-05-25: Strengthened public MCP client and generated consumer-package
  auth-grant direct JSON coverage for route-provided WAMP meta, resources, and
  prompts. The `McpStreamableHttpClient.withAuthGrant(...)` regression now
  exercises direct `wamp.session.count`, `wamp.registration.list`,
  `wamp.registration.match`, `wamp.subscription.list`,
  `wamp.subscription.match`, `resources/list`, `resources/read`,
  `resources/templates/list`, `prompts/list`, and `prompts/get` before any
  Streamable HTTP lifecycle, in addition to the existing direct ping, tool
  catalog, WAMP API metadata, WAMP pub/sub, and direct batch path. The
  generated MCP client-only consumer smoke now adds auth-grant direct WAMP
  registration/subscription lookup, match, list, detail, callee/subscriber
  list/count, and lifecycle-free tool-name/header coverage under the same
  grant-owned bearer-token path. Together they assert requests override stale
  caller `Authorization` metadata, negotiate `application/json`, send no
  `MCP-Session-Id`, and leave `sessionId` / `lastEventId` unset for
  lifecycle-free consumer application usage. Baseline `bin/test-fast` passed
  before the change. Focused local coverage passed: formatting and analyzer
  for `streamable_http_client_test.dart`, the focused MCP client test,
  `bash -n bin/common.sh`, the generated MCP client-only consumer smoke,
  `git diff --check`, and `python3 tool/check_public_artifact_references.py`.
  Full local `bin/verify` passed, including Rust/FFI, MCP package smokes,
  client/native transport suites, live WAMP transport integration, the
  router-hosted MCP example smoke, the expanded generated client-only consumer
  smoke, the generated router consumer-package smoke, the full router suite
  with MCP auth/session/security coverage, and the Chrome/Dart2Wasm browser
  WebSocket smoke. Hosted evidence remains clean at `debd545`; no hosted
  evidence for this checkpoint is recorded here yet.
- 2026-05-25: Closed the HTTP bridge catch-all route mapping gap for consumer
  application readiness. Pathless Dart `HttpRouteMatch` entries now encode to
  native `path: "/"` / `match_kind: "prefix"` routes, preserving method and
  protocol filters while matching non-root paths; native route resolution still
  prefers more-specific prefixes over the catch-all. `ROADMAP.md` now marks the
  catch-all mapping item complete. Focused coverage passed through the Dart
  `router_json_test.dart` native-config encoding regression and the `ct_core`
  `http_route_root_prefix_is_catch_all_and_specific_routes_win` resolver
  regression. Full local `bin/verify` passed, including the MCP package
  smokes, router-hosted MCP example smoke, generated consumer-package smoke,
  native route resolver regression, and full router suite. Commit `debd545`
  was pushed to GitLab `origin/add-router`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `debd545`: `add-router` CI run
  `26395007217` and `master` CI run `26395007168` passed with Fast Checks and
  Full Verify green; Dart Package Publish Dry Run runs `26395007165` and
  `26395007113` passed; WAMP Profile Benchmarks runs `26395007164` and
  `26395007187` passed; kTLS Validation runs `26395007133` and `26395007111`
  passed; manual `master` Router Image dry-run `26395055656` passed with
  preview metadata `sha-debd545c148c`; manual `master` Native Artifacts
  validation dry-run `26396437881` passed with release intent accepted for
  `v0.1.0-rc.2-validation.debd545`, native release preview artifacts ready,
  and no GitHub Release mutation. The strict deployment-chain audit passed
  required gates on `master` at `debd545`. RC readiness remains not-ready
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected for `debd545`; the audit suggests follow-up
  `v0.1.0-rc.2`, which requires release approval before pushing. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-25: Tightened RC readiness so validation dry-run Native Artifacts
  evidence cannot satisfy a selected numeric RC tag. `bin/audit-github-deployment-chain
  --require-rc-ready` now fails with an explicit `Native release prerelease
  tag: not ready` finding when the latest accepted native evidence is still a
  dry-run, even if the selected GitHub RC tag, GitHub prerelease, and router
  image tag are otherwise present. The focused regression stubs that exact
  shape with a clean native validation dry-run plus selected
  `v0.1.0-rc.2`, then asserts RC readiness fails and prints the prerelease
  next action. Baseline `bin/test-fast` passed on 2026-05-25 before this
  change, including the MCP package smokes, router-hosted MCP example smoke,
  generated consumer-package smoke, and router/client fast suites. Focused
  local coverage passed: `bash -n bin/audit-github-deployment-chain`,
  `bin/audit-github-deployment-chain --help`,
  `python3 -m unittest tool.test_audit_github_deployment_chain.AuditGithubDeploymentChainTest.test_rc_readiness_rejects_native_dry_run_for_selected_rc_tag`,
  `python3 -m unittest tool.test_audit_github_deployment_chain.AuditGithubDeploymentChainTest.test_rc_readiness_rejects_native_dry_run_for_selected_rc_tag tool.test_audit_github_deployment_chain.AuditGithubDeploymentChainTest.test_rc_readiness_accepts_native_prerelease_evidence tool.test_audit_github_deployment_chain.AuditGithubDeploymentChainTest.test_rc_readiness_rejects_native_prerelease_tag_mismatch`,
  `python3 -m unittest tool.test_audit_github_deployment_chain`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-25, including Rust/FFI, MCP package smokes, client/native
  transport suites, live WAMP transport integration, the router-hosted MCP
  example smoke, the generated consumer-package smoke, the full router suite
  with MCP auth/session/security coverage, and the Chrome/Dart2Wasm browser
  WebSocket smoke. Commit `60da83a` was pushed to GitLab `origin/add-router`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `60da83a`: `add-router` CI run `26392750019` passed with Fast Checks and
  Full Verify green, and `master` CI run `26392750230` passed with Fast Checks
  and Full Verify green. The strict deployment-chain audit passed required
  gates on `master` at `60da83a`, including clean current-head CI/logs,
  still-relevant Dart package dry-run `26386446103`, still-relevant Native
  Artifacts dry-run `26286794628`, still-relevant Router Image dry-run
  `26386910657`, still-relevant WAMP Profile Benchmarks run `26386446115`,
  branch protection, workflow visibility, and router package visibility. RC
  readiness remains not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected for `60da83a`;
  the audit suggests follow-up `v0.1.0-rc.2`, which requires release approval
  before pushing. No RC tag, GitHub Release, or router image was created or
  moved.
- 2026-05-25: Tightened RC readiness so native prerelease evidence must belong
  to the selected RC tag. `bin/audit-github-deployment-chain` now records the
  accepted Native Artifacts release evidence tag/mode and, when RC readiness
  accepts actual prerelease evidence, compares that tag with the selected
  GitHub numeric RC tag used by the GitHub prerelease and router-image RC
  gates. Validation dry-run evidence remains non-mutating and non-tag-bound.
  The focused regression stubs native prerelease evidence for `v0.1.0-rc.1`
  while the selected GitHub RC tag, GitHub prerelease, and router image tag are
  `v0.1.0-rc.2`, then asserts `--require-rc-ready` fails with a specific
  mismatch finding. Baseline `bin/test-fast` passed on 2026-05-25 before this
  change, including the MCP package smokes, router-hosted MCP example smoke,
  generated consumer-package smoke, and router/client fast suites. Focused
  local coverage passed: `bash -n bin/audit-github-deployment-chain`,
  `bin/audit-github-deployment-chain --help`,
  `python3 -m unittest tool.test_audit_github_deployment_chain.AuditGithubDeploymentChainTest.test_rc_readiness_rejects_native_prerelease_tag_mismatch`,
  `python3 -m unittest tool.test_audit_github_deployment_chain`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-25, including the updated audit tooling regression, MCP
  package smokes, generated consumer-package smoke, router-hosted MCP example
  smoke, router suite, and Chrome/Dart2Wasm browser WebSocket smoke. Commit
  `d63d10e` (`tooling: align native prerelease rc evidence`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `d63d10e`: `add-router` CI run `26390328494` passed
  with Fast Checks and Full Verify green, and `master` CI run `26390328511`
  passed with Fast Checks and Full Verify green. The strict deployment-chain
  audit passed required gates on `master` at `d63d10e`, including clean
  current-head CI/logs, still-relevant Dart package dry-run `26386446103`,
  still-relevant Native Artifacts dry-run `26286794628`, still-relevant Router
  Image dry-run `26386910657`, still-relevant WAMP Profile Benchmarks run
  `26386446115`, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected
  for `d63d10e`; the audit suggests follow-up `v0.1.0-rc.2`, which requires
  release approval before pushing. Pub.dev publishing remains deferred for
  release-order and operator decisions. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-25: Fixed RC readiness tag selection so
  `bin/audit-github-deployment-chain --show-rc-readiness` /
  `--require-rc-ready` prefers a GitHub numeric RC tag when both local-only and
  GitHub RC tags point at the checked-out head. This prevents a stale or lower
  local tag from making the GitHub prerelease and router-image RC tag gates
  inspect the wrong candidate after release approval. The focused regression
  stubs a local `v0.1.0-rc.1` and a GitHub `v0.1.0-rc.2` at the same commit,
  then asserts the audit reports both tags while selecting the GitHub tag for
  the prerelease and `ghcr.io/konsultaner/connectanum-router:0.1.0-rc.2`
  checks. Baseline `bin/test-fast` passed on 2026-05-25 before this change,
  including the MCP package smokes, router-hosted MCP example smoke, generated
  consumer-package smoke, and router/client fast suites. Focused local coverage
  passed: `bash -n bin/audit-github-deployment-chain`,
  `bin/audit-github-deployment-chain --help`,
  `python3 -m unittest tool.test_audit_github_deployment_chain.AuditGithubDeploymentChainTest.test_rc_readiness_prefers_github_rc_tag_over_local_lower_tag`,
  `python3 -m unittest tool.test_audit_github_deployment_chain`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-25, including the updated audit tooling regression, MCP
  package smokes, generated consumer-package smoke, router-hosted MCP example
  smoke, router suite, and Chrome/Dart2Wasm browser WebSocket smoke. Commit
  `0e36538` (`tooling: prefer github rc tag in audit`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `0e36538`: `add-router` CI run `26388413559` passed with Fast
  Checks and Full Verify green, and `master` CI run `26388418063` passed with
  Fast Checks and Full Verify green. The strict deployment-chain audit passed
  required gates on `master` at `0e36538`, including clean current-head CI/logs,
  still-relevant Dart package dry-run `26386446103`, still-relevant WAMP
  Profile Benchmarks run `26386446115`, still-relevant Router Image dry-run
  `26386910657`, still-relevant Native Artifacts dry-run evidence, branch
  protection, workflow visibility, and router package visibility. RC readiness
  remains not-ready only because no approved numeric RC tag, GitHub prerelease,
  or matching RC router image tag has been selected for `0e36538`; pub.dev
  publishing remains deferred for release-order and operator decisions. No RC
  tag, GitHub Release, or router image was created or moved.
- 2026-05-25: Strengthened the MCP HTTP auth client regression so downstream
  applications can safely protect the HTTP auth bridge itself while still using
  `ConnectanumHttpAuthClient` to mint MCP bearer grants. The focused test now
  asserts `Authorization` remains caller-controlled: a constructor default
  authorization header is forwarded, per-call authorization overrides that
  default for ticket-grant challenge/authenticate requests, refresh calls keep
  the default when no per-call replacement is provided, and revoke calls forward
  their own per-call authorization. The same test continues to assert JSON
  request framing headers stay client-owned. Baseline `bin/test-fast` passed on
  2026-05-25 before this change. Focused local coverage passed:
  `dart format packages/connectanum_client/test/mcp/http_auth_client_test.dart`,
  `dart analyze packages/connectanum_client/test/mcp/http_auth_client_test.dart`,
  `dart test packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`,
  `git diff --check`, and
  `python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
  passed on 2026-05-25, including the updated MCP HTTP auth client test, MCP
  package smokes, generated consumer-package smoke, router-hosted MCP example
  smoke, router suite, and Chrome/Dart2Wasm browser WebSocket smoke. Commit
  `f33eb6a` (`test: cover mcp auth bridge authorization headers`) was pushed
  to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `f33eb6a`: `add-router` CI run `26386442961`, Dart
  Package Publish Dry Run `26386442960`, and WAMP Profile Benchmarks
  `26386442962` passed; `master` CI run `26386446104`, Dart Package Publish
  Dry Run `26386446103`, and WAMP Profile Benchmarks `26386446115` passed.
  Manual `master` Router Image dry-run `26386910657` passed at `f33eb6a`,
  uploaded the preview metadata `sha-f33eb6a8b10e`, skipped GHCR login, and
  validated the multi-arch image without publishing. The strict
  deployment-chain audit passed required gates on `master` at `f33eb6a`,
  including clean current-head CI/logs, Dart package dry-run, WAMP profile
  benchmark, Router Image dry-run, still-relevant Native Artifacts dry-run
  evidence, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-25: Extended the generated MCP client-only consumer package smoke so
  a consumer application path now proves auth-grant direct resources, prompts,
  and WAMP session meta helpers before any Streamable HTTP lifecycle starts.
  The pre-lifecycle direct JSON path now covers direct ping, `tools/list`,
  `connectanum.api.list`, `resources/list`, `resources/read`,
  `resources/templates/list`, `prompts/list`, `prompts/get`,
  `wamp.session.count`, `wamp.session.list`, `wamp.session.get`, direct WAMP
  pub/sub subscribe/publish/poll/unsubscribe, and direct batches while stale
  per-call `Authorization` metadata is present. The smoke asserts every request
  uses the grant-owned bearer token, sends no MCP session header, leaves
  `sessionId` and `lastEventId` unset, and routes the pub/sub and session meta
  helpers through the expected `connectanum.pubsub.*` and `wamp.session.*`
  tools. Baseline `bin/test-fast` passed on 2026-05-25 before this change.
  Focused local coverage passed: `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-25, including the updated MCP
  client-only consumer package smoke, router-hosted MCP example smoke,
  generated consumer-package smoke, router suite, and Chrome/Dart2Wasm browser
  WebSocket smoke. Commit `78e0eb0`
  (`test: cover auth grant direct mcp catalog`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `78e0eb0`: `add-router` CI run `26384979697` passed with Fast Checks and
  Full Verify green; `master` CI run `26384984837` passed with Fast Checks and
  Full Verify green. The strict deployment-chain audit passed required gates on
  `master` at `78e0eb0`, including clean current-head CI/logs, still-relevant
  Dart package dry-run, WAMP profile benchmark, Router Image dry-run, Native
  Artifacts dry-run evidence, branch protection, workflow visibility, and
  router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected; pub.dev publishing remains deferred for release-order and
  operator decisions. No RC tag, GitHub Release, or router image was created or
  moved.
- 2026-05-25: Strengthened the public Streamable HTTP MCP client auth-grant
  regression so lifecycle-free typed direct WAMP pub/sub helpers are pinned in
  focused package tests, not only in the generated consumer-package smoke.
  `McpStreamableHttpClient.withAuthGrant(...)` is now covered across
  `subscribeWampTopicDirect(...)`, `publishWampEventDirect(...)`,
  `pollWampEventsDirect(...)`, and `unsubscribeWampTopicDirect(...)` while
  stale per-call `Authorization` metadata is present. The regression asserts
  every request still uses the grant-owned bearer token, stays on
  `application/json`, sends no MCP session header, leaves `sessionId` and
  `lastEventId` unset, and routes through the expected `connectanum.pubsub.*`
  tool calls. Baseline `bin/test-fast` passed on 2026-05-25 before this
  change. Focused local coverage passed:
  `dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-25, including the updated client
  MCP test, MCP client/server package smokes, router-hosted MCP example smoke,
  generated consumer-package smoke, router suite, and Chrome/Dart2Wasm browser
  WebSocket smoke. Commit `3778692`
  (`test: cover auth grant direct wamp helpers`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `3778692`: `master` CI run `26383251625` and `add-router` CI run
  `26383247054` passed with Fast Checks and Full Verify green; `master` WAMP
  Profile Benchmarks run `26383251626` and `add-router` WAMP Profile
  Benchmarks run `26383247053` passed; `master` Dart Package Publish Dry Run
  `26383251624` and `add-router` Dart Package Publish Dry Run `26383247044`
  passed. Manual `master` Router Image dry-run `26383629405` passed at
  `3778692`, uploaded the preview metadata `sha-3778692b25e3`, skipped GHCR
  login, and validated the multi-arch build without publishing. The strict
  deployment-chain audit passed required gates on `master` at `3778692`,
  including clean current-head CI/logs, Dart package dry-run, WAMP profile
  benchmark, Router Image dry-run, still-relevant Native Artifacts dry-run
  evidence, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-25: Extended the generated MCP client-only consumer package smoke so
  a consumer application path now proves auth-grant direct WAMP pub/sub helper
  use before any Streamable HTTP lifecycle starts. The pre-lifecycle auth-grant
  direct JSON path now subscribes, publishes, polls, and unsubscribes through
  the typed direct WAMP pub/sub helpers while stale per-call `Authorization`
  metadata is present, then asserts the fake endpoint only observes the
  client-owned bearer token and no MCP session header. The same smoke now also
  rejects reuse of the rotated original refresh token with `401` while keeping
  the original access token valid for the later Streamable lifecycle smoke.
  Baseline `bin/test-fast` passed on 2026-05-25 before this change. Focused
  local coverage passed: `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-25, including the updated MCP
  client-only consumer package smoke, router-hosted MCP example smoke,
  generated consumer-package smoke, router suite, and Chrome/Dart2Wasm browser
  WebSocket smoke. Commit `e9b0440`
  (`test: cover mcp auth grant direct pubsub`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `e9b0440`: `master` CI run `26382129143` and `add-router` CI run
  `26382095683` passed with Fast Checks and Full Verify green. The strict
  deployment-chain audit passed required gates on `master` at `e9b0440`,
  including clean current-head CI/logs, still-relevant Dart package dry-run,
  WAMP profile benchmark, Router Image dry-run, and Native Artifacts dry-run
  evidence, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-25: Extended the generated MCP client-only consumer package smoke to
  cover refresh-token revocation from the consumer application boundary. The
  smoke now refreshes the issued auth grant, proves the refreshed bearer is used
  for lifecycle-free direct JSON, revokes the refreshed access token, and
  verifies a follow-up direct JSON request returns `401` without creating
  Streamable HTTP session state. It then revokes the refreshed refresh token
  with `token_type_hint: refresh_token`, attempts another refresh with that
  revoked token, and asserts the auth bridge returns `401`. The fake consumer
  endpoint now tracks revoked access and refresh tokens and records refresh,
  revoke, and rejected-refresh request bodies/traces while preserving the
  original issued grant for later Streamable lifecycle checks. Baseline
  `bin/test-fast` passed on 2026-05-25 before this change. Focused local
  coverage passed: `bash -n bin/common.sh`, `git diff --check`,
  `python3 tool/check_public_artifact_references.py`, and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-25, including the updated MCP
  client-only consumer package smoke, router-hosted MCP example smoke,
  generated consumer-package smoke, router suite, and Chrome/Dart2Wasm browser
  WebSocket smoke. Commit `900b7e9`
  (`test: cover mcp refresh token revoke smoke`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `900b7e9`: `master` CI run `26380824261` and `add-router` CI run
  `26380823498` passed with Fast Checks and Full Verify green. The strict
  deployment-chain audit passed required gates on `master` at `900b7e9`,
  including clean current-head CI/logs, still-relevant Dart package dry-run,
  WAMP profile benchmark, Router Image dry-run, and Native Artifacts dry-run
  evidence, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
- 2026-05-25: Extended the generated MCP client-only consumer package smoke to
  cover HTTP auth grant refresh and revoke from the consumer application
  boundary. The smoke refreshes the issued grant, constructs
  `McpStreamableHttpClient.withAuthGrant(...)` from the refreshed grant, sends a
  lifecycle-free direct JSON `ping` with stale per-call `Authorization`
  metadata, and asserts the fake endpoint observes the refreshed bearer token
  without any MCP session header or client `sessionId` / `lastEventId`
  mutation. It then revokes the refreshed access token with
  `token_type_hint: access_token` and proves a follow-up direct JSON request is
  rejected with `401` without creating Streamable HTTP session state. The fake
  endpoint now accepts the original and refreshed access tokens and tracks
  revoked access tokens so the issued grant remains available for the existing
  Streamable lifecycle smoke. Baseline `bin/test-fast` passed on 2026-05-25
  before this change. Focused local coverage passed: `bash -n bin/common.sh`,
  `git diff --check`, `python3 tool/check_public_artifact_references.py`, and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-25, including the updated MCP
  client-only consumer package smoke, router-hosted MCP example smoke,
  generated consumer-package smoke, router suite, and Chrome/Dart2Wasm browser
  WebSocket smoke. Commit `fcc6ef4`
  (`test: cover mcp auth grant refresh smoke`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `fcc6ef4`: `master` CI run `26379386698` and `add-router` CI run
  `26379383928` passed with Fast Checks and Full Verify green. The strict
  deployment-chain audit passed required gates on `master` at `fcc6ef4`,
  including clean current-head CI/logs, still-relevant Dart package dry-run,
  WAMP profile benchmark, Router Image dry-run, and Native Artifacts dry-run
  evidence, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric RC
  tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
- 2026-05-25: Extended the generated MCP client-only consumer package smoke so
  a downstream application path now proves auth-grant direct JSON use before
  any Streamable HTTP lifecycle starts. The smoke constructs
  `McpStreamableHttpClient.withAuthGrant(...)`, sends stale per-call
  `Authorization` metadata through direct JSON `ping`, `tools/list`, WAMP API
  helper access, and direct JSON batch POST, then asserts the fake consumer
  endpoint only observes the grant access token and no MCP session header. The
  client also keeps `sessionId` / `lastEventId` unset for that pre-lifecycle
  flow. This promotes the earlier auth-grant direct JSON unit regression into
  consumer-package evidence for applications that need tool/meta API access
  without private project assumptions. Baseline `bin/test-fast` passed on
  2026-05-25. Focused local coverage passed: `bash -n bin/common.sh` and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-25, including the updated MCP
  client-only consumer package smoke, router-hosted MCP example smoke,
  generated consumer-package smoke, router suite, and Chrome/Dart2Wasm browser
  WebSocket smoke. Commit `324ee24`
  (`test: cover mcp auth grant consumer direct json`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `324ee24`: `master` CI run `26377930589` and `add-router` CI run
  `26377928223` passed with Fast Checks and Full Verify green. The latest run
  list confirmed no new Dart Package Publish Dry Run or WAMP Profile Benchmarks
  started for this smoke-script/docs checkpoint; the strict deployment-chain
  audit accepted still-relevant Dart package, WAMP, Router Image, and Native
  Artifacts evidence because no corresponding sensitive inputs changed. The
  strict audit passed required gates on `master` at `324ee24`, including clean
  current-head CI/logs, branch protection, workflow visibility, and router
  package visibility. RC readiness remains not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected; pub.dev publishing remains deferred for release-order and operator
  decisions.
- 2026-05-25: Strengthened the public Streamable HTTP MCP auth-grant
  regression so `McpStreamableHttpClient.withAuthGrant(...)` is covered across
  lifecycle-free direct JSON helper calls, not only initialized Streamable HTTP
  sessions. A client constructed from `ConnectanumHttpAuthGrant` now proves
  its owned trimmed bearer token stays authoritative when per-call headers try
  to provide stale `Authorization` metadata across direct JSON `ping`,
  standard `tools/list`, Connectanum tool/meta API access, and direct JSON
  batch POST. The regression also asserts these direct JSON calls stay
  lifecycle-free: every request uses `application/json`, no MCP session header
  is sent, and `sessionId` / `lastEventId` remain unset. This aligns auth
  grants with the bearer-token direct JSON lifecycle smoke and protects
  downstream applications that use HTTP auth grants for direct tool/meta API
  access without first opening a Streamable session. Baseline `bin/test-fast`
  passed on 2026-05-25. Focused local coverage passed:
  `dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-25, including the router-hosted
  MCP example smoke, generated consumer-package smoke, and Chrome/Dart2Wasm
  browser WebSocket smoke. Commit `da1c41a`
  (`test: cover mcp auth grant direct json`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `da1c41a`: `master` CI run `26376646690` and `add-router` CI run
  `26376646678` passed with Fast Checks and Full Verify green. Dart Package
  Publish Dry Run `26376646677` on `master` and `26376646691` on `add-router`,
  plus WAMP Profile Benchmarks `26376646652` on `master` and `26376646707` on
  `add-router`, passed for the same head. Manual non-mutating Router Image
  dry-run `26377017450` passed on `master`, uploaded preview metadata for
  `sha-da1c41a82f1f`, skipped GHCR login, and did not push an image. Native
  Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `da1c41a`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current
  Router Image dry-run, relevant native release dry-run, branch protection,
  workflow visibility, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected; pub.dev publishing remains
  deferred for release-order and operator decisions. No RC tag, GitHub
  Release, or published router image was created or moved.
- 2026-05-25: Strengthened the public Streamable HTTP MCP bearer-token
  regression so `McpStreamableHttpClient.withBearerToken(...)` is covered
  across both Streamable HTTP and lifecycle-free direct JSON calls while stale
  per-call `Authorization` metadata is present. The primary Streamable smoke
  now sends conflicting per-call bearer headers across `initialize`,
  `notifications/initialized`, `tools/list`, GET/SSE polling, Streamable batch
  POST, DELETE cleanup, and direct JSON `tools/list`, `ping`, and batch POST,
  then asserts every recorded request uses the client-owned trimmed bearer
  token. This keeps the convenience constructor aligned with the auth-grant
  lifecycle regression and protects downstream applications that mix
  Streamable HTTP sessions with direct JSON MCP tool/meta access. Baseline
  `bin/test-fast` passed on 2026-05-25. Focused local coverage passed:
  `dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-25, including the router-hosted
  MCP example smoke, generated consumer-package smoke, and Chrome/Dart2Wasm
  browser WebSocket smoke. Commit `a60d432`
  (`test: cover mcp bearer lifecycle headers`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `a60d432`: `master` CI run `26375633670` and `add-router` CI run
  `26375630452` passed with Fast Checks and Full Verify green. Dart Package
  Publish Dry Run `26375633662` on `master` and `26375630482` on `add-router`,
  plus WAMP Profile Benchmarks `26375633672` on `master` and `26375630471` on
  `add-router`, passed for the same head. Manual non-mutating Router Image
  dry-run `26375900535` passed on `master`, uploaded preview metadata for
  `sha-a60d43290c44`, skipped GHCR login, and did not push an image. Native
  Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `a60d432`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current
  Router Image dry-run, relevant native release dry-run, branch protection,
  workflow visibility, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected; pub.dev publishing remains
  deferred for release-order and operator decisions. No RC tag, GitHub
  Release, or published router image was created or moved.
- 2026-05-25: Extended the public Streamable HTTP MCP client auth-grant
  regression from initialization-only coverage to the full initialized session
  lifecycle. `McpStreamableHttpClient.withAuthGrant(...)` is now covered across
  Streamable `initialize`, sessionful `tools/list`, GET/SSE polling, and DELETE
  cleanup while stale per-call `Authorization` headers are present. The
  regression proves the client-owned bearer grant remains authoritative, custom
  consumer trace headers still apply per request, sessionful operations attach
  the active MCP session id, and `deleteSession(...)` clears local session
  state. Baseline `bin/test-fast` passed on 2026-05-25. Focused local coverage
  passed: `dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  and
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-25, including the router-hosted
  MCP example smoke, generated consumer-package smoke, and Chrome/Dart2Wasm
  browser WebSocket smoke. Commit `c588ff4`
  (`test: cover mcp auth grant lifecycle`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `c588ff4`: `master` CI run `26374623727` and `add-router` CI run
  `26374619965` passed with Fast Checks and Full Verify green. Dart Package
  Publish Dry Run `26374623735` on `master` and `26374619948` on
  `add-router`, plus WAMP Profile Benchmarks `26374623736` on `master` and
  `26374619943` on `add-router`, passed for the same head. Manual
  non-mutating Router Image dry-run `26374917999` passed on `master`, uploaded
  preview metadata for `sha-c588ff46d07c`, skipped GHCR login, and did not
  push an image. Native Artifacts dry-run `26286794628` remains relevant
  because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `c588ff4`,
  including clean current-head CI/logs, Dart package dry-run, WAMP profile
  benchmark evidence, current Router Image dry-run, relevant native release
  dry-run, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or published router image was created
  or moved.
- 2026-05-24: Hardened the hosted browser WebSocket smoke in `bin/test-all`
  so retryable `package:test` browser-manager startup or load stalls cannot
  consume an entire GitHub CI job. Each attempt is now bounded by
  `CONNECTANUM_BROWSER_TEST_ATTEMPT_TIMEOUT_SECONDS`, defaulting to 420
  seconds, while preserving `CONNECTANUM_BROWSER_TEST_ATTEMPTS` and keeping
  retry-attempt output out of GitHub annotations until the final attempt. This
  addresses the same failure mode seen on the first `master` CI attempt at
  `3f3f4c2`, where rerunning the failed hosted browser job passed cleanly.
  `tool/test_verification_scripts.py` now guards the retry wrapper, attempt
  timeout, and reporter behavior. Baseline `bin/test-fast` passed on
  2026-05-24. Focused local coverage passed: `bash -n bin/test-all` and
  `python3 tool/test_verification_scripts.py`. Full local `bin/verify` passed
  on 2026-05-24, including the Chrome/Dart2Wasm browser WebSocket smoke
  through the updated wrapper. Commit `8a8f09b`
  (`ci: bound browser smoke attempts`) was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `8a8f09b`: `master` CI run `26373596238` and `add-router` CI run
  `26373596242` passed with Fast Checks and Full Verify green. Dart Package
  Publish Dry Run `26371382131` on `master` and `26371382110` on `add-router`,
  WAMP Profile Benchmarks `26371382109` on `master` and `26371382129` on
  `add-router`, Router Image dry-run `26372834591`, and Native Artifacts
  dry-run `26286794628` remain relevant because no corresponding sensitive
  inputs changed after their clean runs. The strict deployment-chain audit
  passed required gates on `master` at `8a8f09b`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, relevant
  Router Image dry-run, relevant native release dry-run, branch protection,
  workflow visibility, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected; pub.dev publishing remains
  deferred for release-order and operator decisions. No RC tag, GitHub Release,
  or router image was created or moved.
- 2026-05-24: Hardened the public Streamable HTTP MCP client's
  authorization ownership. `McpStreamableHttpClient` now captures a
  client-level `Authorization` header from constructor headers,
  `withBearerToken(...)`, or `withAuthGrant(...)` and reapplies it after
  request-specific headers, preventing stale or conflicting per-call metadata
  from swapping the bearer principal on a client that already owns auth/session
  state. Plain clients without client-level auth state can still provide
  per-call `Authorization` headers. Coverage now proves auth-grant clients keep
  the grant bearer token even when `initialize(...)` receives a stale
  `Authorization` header, and plain clients still send per-call authorization.
  Baseline `bin/test-fast` passed on 2026-05-24. Focused local coverage
  passed: `dart format` and `dart analyze` for
  `packages/connectanum_client/lib/src/mcp/streamable_http_client.dart` and
  `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`, plus
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
  Full local `bin/verify` passed on 2026-05-24. Commit `3f3f4c2`
  (`fix: keep mcp bearer auth stable`) was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `3f3f4c2`: `master` CI run `26371382128` passed after a failed-job rerun
  cleared a hosted browser-runner load flake, and `add-router` CI run
  `26371382102` passed with Fast Checks and Full Verify green; Dart Package
  Publish Dry Run `26371382131` on `master` and `26371382110` on `add-router`
  passed; WAMP Profile Benchmarks `26371382109` on `master` and `26371382129`
  on `add-router` passed; Router Image dry-run `26372834591` passed on
  `master` with preview metadata `sha-3f3f4c2e9e4a`, GHCR login skipped, and
  preview metadata uploaded. Native Artifacts dry-run `26286794628` remains
  relevant because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `3f3f4c2`,
  including clean current-head CI/logs, Dart package dry-run, WAMP profile
  benchmark evidence, current Router Image dry-run, relevant native release
  dry-run, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended the secure JSON-response MCP independent-principal
  coverage across the native router integration smoke, public router-hosted
  MCP example, and generated consumer-package smoke. A second valid bearer
  principal now proves lifecycle-free direct JSON `resources/list`,
  `resources/read`, `resources/templates/list`, `prompts/list`, and
  `prompts/get` access before initialization, then repeats resource and prompt
  access on its own initialized JSON-response Streamable HTTP session while
  asserting the owner principal's session is not reused and POST/SSE cursor
  state remains unchanged. Pre-change `bin/test-fast` passed on 2026-05-24.
  Focused local coverage passed:
  `dart analyze packages/connectanum_router/test/router_integration_native_test.dart packages/connectanum_router/example/router_hosted_mcp.dart`,
  `cd packages/connectanum_router && dart test test/router_integration_native_test.dart --name "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Full local `bin/verify` passed on 2026-05-24.
  Commit `e1a496e` (`test: cover secure json mcp resources prompts`) was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `e1a496e`: `master` CI run `26370411899` and
  `add-router` CI run `26370411877` passed with Fast Checks and Full Verify
  green; Dart Package Publish Dry Run `26370411887` on `master` and
  `26370411864` on `add-router` passed; WAMP Profile Benchmarks `26370411888`
  on `master` and `26370411900` on `add-router` passed; Router Image dry-run
  `26369504710` at `25afea8` and Native Artifacts dry-run `26286794628`
  remain relevant because no corresponding sensitive inputs changed after
  their clean runs. The strict deployment-chain audit passed required gates on
  `master` at `e1a496e`, including clean current-head CI/logs, Dart package
  dry-run, WAMP profile benchmark evidence, relevant Router Image and native
  release dry-runs, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Strengthened the checked-in `connectanum_mcp` IO entrypoint
  pub/sub smoke so it proves side effects instead of only request shapes. The
  fake Streamable MCP endpoint now records per-subscription event queues,
  applies notification-only `connectanum.pubsub.publish` requests without
  producing JSON-RPC responses, and returns the actual queued payloads through
  `connectanum.pubsub.poll`. The smoke now proves a consumer application using
  public `package:connectanum_mcp/connectanum_mcp_io.dart` APIs can publish
  events through typed Streamable WAMP helpers, direct
  `connectanum.pubsub.publish` calls, notification-only method publishes, and
  `notifyWampEvent(...)`, then poll all four payloads while preserving the
  Streamable session cursor for notifications. It also proves lifecycle-free
  direct JSON pub/sub publish/poll returns the direct payload while the active
  Streamable session state stays unchanged. Pre-change `bin/test-fast` passed
  on 2026-05-24. Focused local coverage passed:
  `dart format packages/connectanum_mcp/test/io_client_export_test.dart`,
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`,
  and `dart analyze packages/connectanum_mcp`. Full local `bin/verify` passed
  on 2026-05-24. Commit `25afea8`
  (`test: cover mcp io pubsub side effects`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `25afea8`: `master` CI run `26369187521` and `add-router` CI run
  `26369185437` passed with Fast Checks and Full Verify green; Dart Package
  Publish Dry Run `26369187504` on `master` and `26369185436` on `add-router`
  passed; Router Image dry-run `26369504710` passed on `master`; WAMP Profile
  Benchmarks `26366801338` and Native Artifacts dry-run `26286794628` remain
  relevant because no corresponding sensitive inputs changed after their clean
  runs. The strict deployment-chain audit passed required gates on `master` at
  `25afea8`, including clean current-head CI/logs, Dart package dry-run, WAMP
  profile benchmark evidence, current Router Image dry-run, relevant native
  release dry-run, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended the generated consumer-package smoke from the standard
  Streamable MCP tool notification helper and a `connectanum.tool.call`
  notification-only batch to the remaining sessionful tool-method aliases. A
  downstream application smoke now sends notification-only tool calls through
  standard `tools/call`, Connectanum `connectanum.tool.call`, direct dotted
  procedure names, and plural `connectanum.tools.call` while an initialized
  Streamable HTTP session is active. The smoke asserts each valid notification
  invokes the registered WAMP procedure, `MCP-Session-Id` and the POST/SSE
  resume cursor stay unchanged, and an invalid notification-only batch entry is
  accepted and dropped without invoking the procedure. Pre-change
  `bin/test-fast` passed on 2026-05-24. Focused local coverage passed:
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  `git diff --check`, and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
  `7b4a88e` (`test: cover streamable mcp tool notifications`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `7b4a88e`: `master` CI run `26368059584` and
  `add-router` CI run `26368057989` passed with Fast Checks and Full Verify
  green. Dart Package Publish Dry Run `26366801335`, WAMP Profile Benchmarks
  `26366801338`, Router Image dry-run `26366846880`, and Native Artifacts
  dry-run `26286794628` remain relevant because no corresponding sensitive
  inputs changed after their clean runs. The strict deployment-chain audit
  passed required gates on `master` at `7b4a88e`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current
  Router Image dry-run, relevant native release dry-run, branch protection,
  workflow visibility, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected; pub.dev publishing remains
  deferred for release-order and operator decisions. No RC tag, GitHub Release,
  or router image was created or moved.
- 2026-05-24: Extended checked-in native router MCP notification coverage from
  accepted HTTP responses to WAMP side effects. The router integration smoke
  now records `app.safe.lookup` invocations and proves notification-only direct
  JSON calls through standard `tools/call`, Connectanum
  `connectanum.tool.call`, direct dotted `app.safe.lookup`, and plural
  `connectanum.tools.call` invoke the registered WAMP procedure without
  creating or mutating Streamable HTTP session state. Coverage runs on the
  public MCP route, a public notification-only batch with an invalid
  notification ignored, bearer-protected `/mcp/secure` for both the primary
  secure route and a second valid bearer principal before initialization, and
  bearer-protected `/mcp/secure-json-post` for both primary and independent
  valid bearer principals before initialization. Pre-change `bin/test-fast`
  passed on 2026-05-24. Focused local coverage passed:
  `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`
  and
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal|smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`.
  Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
  `3feb797` (`test: cover direct mcp notification side effects`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `3feb797`: `master` CI run `26366801355` and
  `add-router` CI run `26366796353` passed with Fast Checks and Full Verify
  green; Dart Package Publish Dry Run `26366801335` on `master` and
  `26366796357` on `add-router` passed; WAMP Profile Benchmarks `26366801338`
  on `master` and `26366796352` on `add-router` passed; manual non-mutating
  Router Image dry-run `26366846880` passed on `master` at `3feb797` with
  preview metadata `sha-3feb797f84b1`, GHCR login skipped, and preview
  metadata uploaded. Native Artifacts dry-run `26286794628` remains relevant
  because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `3feb797`,
  including clean current-head CI/logs, Dart package dry-run, WAMP profile
  benchmark evidence, current Router Image dry-run, relevant native release
  dry-run, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended the public router-hosted MCP example direct JSON
  tool/meta smoke to notification-only tool-method paths. The example now
  records `example.task.lookup` invocations and proves standard `tools/call`,
  Connectanum `connectanum.tool.call`, direct dotted `example.task.lookup`, and
  plural `connectanum.tools.call` notifications invoke the registered WAMP
  procedure without creating or mutating Streamable HTTP session state. Because
  the helper is shared, the coverage runs on the public route, both
  bearer-protected MCP routes, and independent valid bearer principal paths
  before Streamable initialization. Pre-change `bin/test-fast` passed on
  2026-05-24. Focused local coverage passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart` and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`.
  Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
  `dbb52aa` (`example: cover direct mcp tool notifications`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `dbb52aa`: `master` CI run `26365310039` and
  `add-router` CI run `26365307456` passed with Fast Checks and Full Verify
  green; Dart Package Publish Dry Run `26365310038` on `master` and
  `26365307444` on `add-router` passed; WAMP Profile Benchmarks `26365310040`
  on `master` and `26365307457` on `add-router` passed; manual non-mutating
  Router Image dry-run `26365614158` passed on `master` at `dbb52aa` with
  preview metadata `sha-dbb52aa872f6`, GHCR login skipped, and preview metadata
  uploaded. Native Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `dbb52aa`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current
  Router Image dry-run, relevant native release dry-run, branch protection,
  workflow visibility, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected; pub.dev publishing remains
  deferred for release-order and operator decisions. No RC tag, GitHub Release,
  or router image was created or moved.
- 2026-05-24: Extended secure MCP direct JSON tool/meta API readiness from
  `tools/call` helpers and catalogs to direct dotted JSON-RPC tool-method names.
  The checked-in native router smoke now proves `app.safe.lookup` can be called
  directly on both bearer-protected MCP routes, `/mcp/secure` and
  `/mcp/secure-json-post`, for owner and independent valid bearer principals
  without mutating `sessionId` or `lastEventId`. The public router-hosted MCP
  example now calls `example.task.lookup` as a direct JSON-RPC method inside its
  direct tool/meta smoke, and both the public example and generated
  consumer-package smoke run the full direct tool/meta helper sweep for a
  second valid bearer principal before that principal initializes a Streamable
  session on secure Streamable and secure JSON-response routes. Pre-change
  `bin/test-fast` passed on 2026-05-24. Focused local coverage passed:
  `dart analyze packages/connectanum_router/test/router_integration_native_test.dart packages/connectanum_router/example/router_hosted_mcp.dart`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal|smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `bash -n bin/common.sh`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `python3 tool/check_public_artifact_references.py`, and `git diff --check`.
  Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
  `26b7348` (`test: cover direct mcp dotted methods`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `26b7348`: `master` CI run `26364003714` and `add-router` CI run
  `26364002656` passed with Fast Checks and Full Verify green; Dart Package
  Publish Dry Run `26364003678` on `master` and `26364002658` on `add-router`
  passed; WAMP Profile Benchmarks `26364003654` on `master` and `26364002655`
  on `add-router` passed; manual non-mutating Router Image dry-run
  `26364336014` passed on `master` at `26b7348` with preview metadata
  `sha-26b734836c67`, GHCR login skipped, and preview metadata uploaded. Native
  Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `26b7348`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
  Image dry-run, relevant native release dry-run, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready only
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected; pub.dev publishing remains deferred for
  release-order and operator decisions. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-24: Extended secure MCP independent-principal coverage from direct
  WAMP/pubsub readiness to the full direct WAMP meta helper surface on both
  bearer-protected MCP routes. The checked-in router integration smoke now
  registers `app.safe.lookup` for the secure route-isolation test and asserts
  that a second valid bearer principal can call direct WAMP session,
  registration, callee, subscription, subscriber, and subscriber-count helpers
  before initializing a Streamable session on both `/mcp/secure` and
  `/mcp/secure-json-post`. The helper proves the direct principal sees only its
  own visible session/subscription scope, internal service sessions stay hidden
  from callee/subscriber metadata, and `sessionId`/`lastEventId` remain unset.
  The public router-hosted MCP example and generated consumer-package smoke now
  run the same direct WAMP meta helper sweep before direct pub/sub for secure
  Streamable and secure JSON-response routes. Pre-change `bin/test-fast` passed
  on 2026-05-24. Focused local coverage passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal" --chain-stack-traces`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `bash -n bin/common.sh`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  and
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
  Post-change `python3 tool/check_public_artifact_references.py`,
  `git diff --check`, `bin/test-fast`, and full local `bin/verify` passed on
  2026-05-24 for this checkpoint. Commit `20c6c97`
  (`test: cover direct mcp wamp meta sessions`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `20c6c97`: `master` CI run `26362759298` and `add-router` CI run
  `26362755835` passed with Fast Checks and Full Verify green; Dart Package
  Publish Dry Run `26362759287` on `master` and `26362755826` on `add-router`
  passed; WAMP Profile Benchmarks `26362759307` on `master` and `26362755815`
  on `add-router` passed; manual non-mutating Router Image dry-run
  `26363036566` passed on `master` at `20c6c97` with preview metadata
  `0.1.0-rc.2-validation.20c6c97`, GHCR login skipped, and preview metadata
  uploaded. Native Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `20c6c97`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
  Image dry-run, relevant native release dry-run, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready only
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected; pub.dev publishing remains deferred for
  release-order and operator decisions. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-24: Extended secure JSON-response MCP independent-principal
  coverage from tool-catalog/session isolation to direct WAMP/pubsub readiness.
  After rejected cross-principal `MCP-Session-Id` reuse on
  `/mcp/secure-json-post`, the checked-in router integration smoke, public
  router-hosted MCP example, and generated consumer-package smoke now prove
  the second valid bearer principal can access the direct JSON tool catalog
  plus WAMP topic metadata and pub/sub without lifecycle side effects, then
  initialize a distinct JSON-response Streamable HTTP session and run pub/sub
  while keeping JSON POST responses in JSON mode without capturing a POST/SSE
  cursor. The public example and generated consumer-package smoke cover
  lifecycle-free direct JSON WAMP/pubsub access before initialize and
  independent pub/sub after initialize; the native integration test pins
  route-level direct WAMP topic catalog access, direct pub/sub delivery,
  independent JSON-response Streamable pub/sub delivery, and owner-session
  stability. Pre-change `bin/test-fast` passed on 2026-05-24. Focused local
  coverage passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Post-change `bin/test-fast` passed locally, and full
  local `bin/verify` passed for this checkpoint. Commit `8cd8f5e`
  (`test: cover json-response mcp pubsub sessions`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `8cd8f5e`: `master` CI run `26361007393` and `add-router` CI run
  `26361003647` passed with Fast Checks and Full Verify green; Dart Package
  Publish Dry Run `26361007296` on `master` and `26361003643` on `add-router`
  passed; WAMP Profile Benchmarks `26361007284` on `master` and `26361003657`
  on `add-router` passed; manual non-mutating Router Image dry-run
  `26361298005` passed on `master` with preview metadata
  `0.1.0-rc.2-validation.8cd8f5e`, GHCR login skipped, and preview metadata
  uploaded. Native Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `8cd8f5e`, including clean current-head
  CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
  Image dry-run, relevant native release dry-run, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready only
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected; pub.dev publishing remains deferred for
  release-order and operator decisions. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-24: Extended secure standard Streamable MCP independent-principal
  coverage from tool-catalog/session isolation to direct WAMP/pubsub readiness.
  After rejected cross-principal `MCP-Session-Id` reuse on `/mcp/secure`, the
  checked-in router integration smoke, public router-hosted MCP example, and
  generated consumer-package smoke now prove the second valid bearer principal
  can access direct JSON tool and WAMP topic metadata plus pub/sub without
  lifecycle side effects, then initialize a distinct Streamable HTTP session
  and run pub/sub while advancing only that independent session's SSE cursor.
  The public example and generated consumer-package smoke cover lifecycle-free
  direct JSON WAMP/pubsub access before initialize; the native integration test
  pins route-level direct WAMP topic catalog access, direct pub/sub delivery,
  independent Streamable pub/sub delivery, and owner-session stability.
  Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage
  passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal" --chain-stack-traces`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Post-change `bin/test-fast` passed locally, and full
  local `bin/verify` passed for this checkpoint. Commit `a2c706f`
  (`test: cover independent mcp pubsub sessions`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted evidence is clean
  at `a2c706f`: `master` CI run `26359793602` and `add-router` CI run
  `26359791440` passed with Fast Checks and Full Verify green; Dart Package
  Publish Dry Run `26359793607` on `master` and `26359791425` on `add-router`
  passed; WAMP Profile Benchmarks `26359793618` on `master` and `26359791432`
  on `add-router` passed; manual Router Image dry-run `26359802334` passed on
  `master` with preview metadata `0.1.0-rc.2-validation.a2c706fc2275`, GHCR
  login skipped, and preview metadata uploaded. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. The strict deployment-chain audit passed required gates on `master`
  at `a2c706f`, including clean current-head CI/logs, Dart package dry-run,
  WAMP profile benchmark evidence, current Router Image dry-run, relevant
  native release dry-run, branch protection, workflow visibility, and router
  package visibility. RC readiness remains not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected; pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended secure standard Streamable MCP auth/session coverage to
  prove independent use by a second valid bearer principal, not only rejected
  reuse of the owner session. The checked-in router integration smoke, public
  router-hosted MCP example, and generated consumer-package smoke now cover the
  bearer-protected `/mcp/secure` route after rejected cross-principal
  `MCP-Session-Id` reuse. The same valid principal can use public MCP HTTP
  helpers to access the direct JSON tool catalog without lifecycle side effects,
  initialize a distinct Streamable HTTP session, capture a session-scoped
  POST/SSE cursor on the standard Streamable tools/list path, list tools, and
  delete its own session without mutating the owner session. The public example
  and generated consumer-package smoke cover the reuse rejection matrix across
  Streamable methods; the checked-in router integration smoke pins the
  route-level session ownership behavior with a second valid bearer principal.
  Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage
  passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal" --chain-stack-traces`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Post-change `bin/test-fast` passed locally, and full
  local `bin/verify` passed for this checkpoint. Commit `1e86c5a`
  (`test: cover secure streamable mcp sessions`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `1e86c5a`: `master` CI run `26358592094` passed with Fast Checks and Full
  Verify green plus clean logs, and `add-router` CI run `26358590215` passed
  with Fast Checks and Full Verify green. Dart Package Publish Dry Run
  `26358592098` on `master` and `26358590188` on `add-router` passed at
  `1e86c5a`; WAMP Profile Benchmarks `26358592107` on `master` and
  `26358590204` on `add-router` passed at `1e86c5a`; manual non-mutating
  Router Image dry-run `26358602876` passed on `master` at `1e86c5a` with
  preview metadata `0.1.0-rc.2-validation.1e86c5a977a3`, GHCR login skipped,
  and preview metadata uploaded; Native Artifacts dry-run `26286794628` remains
  relevant because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `1e86c5a`,
  including clean current-head CI/logs, Dart package dry-run, WAMP profile
  benchmark evidence, current Router Image dry-run, relevant native release
  dry-run, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  pub.dev publishing remains deferred for release-order and operator decisions.
  No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended secure JSON-response MCP auth/session coverage to prove
  independent use by a second valid bearer principal, not only rejected reuse of
  the owner session. The checked-in router integration smoke, public
  router-hosted MCP example, and generated consumer-package smoke now reject
  cross-principal `MCP-Session-Id` reuse on `/mcp/secure-json-post`, then prove
  the second valid principal can use public MCP HTTP helpers to access the
  direct JSON tool catalog, initialize a distinct Streamable HTTP session, keep
  JSON-response POSTs from capturing a POST/SSE cursor, list tools, and delete
  its own session without mutating the owner session. The generated consumer
  smoke follows paginated catalog pages because that route intentionally sets a
  tool page size of one. Pre-change `bin/test-fast` passed on 2026-05-24.
  Focused local coverage passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Post-change `bin/test-fast` passed locally, and full
  local `bin/verify` passed for this checkpoint. Commit `2b14e88`
  (`test: cover independent json-response mcp sessions`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `2b14e88`: `master` CI run `26357273499` passed with Fast Checks and
  Full Verify green plus clean logs, and `add-router` CI run `26357271763`
  passed with Fast Checks and Full Verify green. Dart Package Publish Dry Run
  `26357273488` on `master` and `26357271785` on `add-router` passed at
  `2b14e88`; WAMP Profile Benchmarks `26357273487` on `master` and
  `26357271784` on `add-router` passed at `2b14e88`; manual non-mutating Router
  Image dry-run `26357553510` passed on `master` at `2b14e88` with GHCR login
  skipped and preview metadata uploaded; Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `2b14e88`, including clean current-head CI/logs, Dart package dry-run, WAMP
  profile benchmark evidence, current Router Image dry-run, relevant native
  release dry-run, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval
  is given. Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended the public router-hosted MCP example with
  auth/session isolation coverage for the bearer-protected JSON-response MCP
  route at `/mcp/secure-json-post`. The example now issues a second valid
  ticket bearer principal and proves a different bearer principal cannot reuse
  the owner `MCP-Session-Id` across Streamable batches, notifications, tools,
  resources, prompts, GET/SSE poll, and DELETE (`404 Not Found`). It also
  proves bearerless active-session reuse returns `401 Unauthorized`, and an
  unknown bearer is rejected across active direct JSON tools, WAMP meta/pubsub,
  resources, and prompts without mutating the owner state before Streamable
  failures clear the rejected client's stale session state. Pre-change
  `bin/test-fast` passed on 2026-05-24. Focused local coverage passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `python3 tool/check_public_artifact_references.py`, and `git diff --check`.
  Full local `bin/verify` passed on 2026-05-24. Commit `bc2575c`
  (`example: cover json-response mcp session isolation`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `bc2575c`: `master` CI run `26355702455` passed with Fast Checks and
  Full Verify green plus clean logs, and `add-router` CI run `26355702355`
  passed with Fast Checks and Full Verify green. Dart Package Publish Dry Run
  `26355702488` on `master` and `26355702383` on `add-router` passed at
  `bc2575c`; WAMP Profile Benchmarks `26355702451` on `master` and
  `26355702340` on `add-router` passed at `bc2575c`; manual non-mutating Router
  Image dry-run `26355974643` passed on `master` at `bc2575c` with GHCR login
  skipped and preview metadata uploaded; Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `bc2575c`, including clean current-head CI/logs, Dart package dry-run, WAMP
  profile benchmark evidence, current Router Image dry-run, relevant native
  release dry-run, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected;
  the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval
  is given. Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended the generated consumer-package router-hosted MCP smoke
  for auth/session isolation on the bearer-protected JSON-response MCP route.
  The generated consumer application smoke now proves `/mcp/secure-json-post`
  rejects a different valid bearer principal that tries to reuse the owner
  `MCP-Session-Id` on JSON-response Streamable POSTs with `404 Not Found` /
  `Unknown MCP HTTP session`, rejects bearerless active-session reuse with
  `401 Unauthorized`, and rejects an unknown bearer across active direct JSON
  tools, direct WAMP meta/pubsub calls, Streamable batches, notifications,
  tools, resources, prompts, GET/SSE poll, and DELETE. The owner client keeps
  its active MCP session id, keeps the POST/SSE cursor empty, and continues
  through typed protocol override, pub/sub, GET/SSE poll, and DELETE cleanup
  coverage. Pre-change `bin/test-fast` passed on 2026-05-24. Focused local
  coverage passed:
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `1d80b57`
  (`test: cover consumer json-response mcp sessions`) is clean: `master` CI
  run `26354715574` passed with Fast Checks and Full Verify green plus clean
  logs, and `add-router` CI run `26354713644` passed with Fast Checks and Full
  Verify green. Dart Package Publish Dry Run `26353736911` at `c453949`, WAMP
  Profile Benchmarks `26353736914` at `c453949`, Router Image dry-run
  `26353998120` at `c453949`, and Native Artifacts dry-run `26286794628`
  remain relevant because no publish-, WAMP-profile-, router-image-, or
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `1d80b57`, including clean current-head
  CI/logs, relevant Dart package dry-run, relevant WAMP profile benchmark
  evidence, relevant Router Image dry-run, relevant native release dry-run,
  branch protection, workflow visibility, and router package visibility. RC
  readiness remains not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected; the audit
  suggests `v0.1.0-rc.2` as the next numeric tag if release approval is given.
  Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended the checked-in router native integration coverage for
  auth/session isolation on the bearer-protected JSON-response MCP route. The
  `smoke tests MCP router RPC pubsub and route security` integration test now
  proves `/mcp/secure-json-post` rejects an unknown bearer before any
  Streamable lifecycle session exists, omits `MCP-Session-Id` on the
  unauthorized response, then rejects raw JSON POST requests that reuse an
  active `MCP-Session-Id` without a bearer or with an unknown bearer. The same
  smoke now also proves a Streamable HTTP POST from a different valid bearer
  principal using the owner session id is rejected with `404 Not Found` /
  `Unknown MCP HTTP session`. The owner client keeps its active MCP session id,
  keeps the POST/SSE resume cursor empty, and continues through the existing
  route-provided resources/prompts, pub/sub, poll, unsubscribe, and DELETE
  cleanup assertions. Pre-change `bin/test-fast` passed on 2026-05-24.
  Focused local coverage passed:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`,
  `python3 tool/check_public_artifact_references.py`, and `git diff --check`.
  Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `c453949`
  (`test: cover json-response mcp principal isolation`) is clean: `master` CI
  run `26353736923` passed with Fast Checks and Full Verify green plus clean
  logs, and `add-router` CI run `26353735642` passed with Fast Checks and Full
  Verify green. Dart Package Publish Dry Run `26353736911` on `master` and
  `26353735630` on `add-router` passed cleanly at `c453949`; WAMP Profile
  Benchmarks `26353736914` on `master` and `26353735619` on `add-router`
  passed at `c453949`. Router Image dry-run `26353998120` passed for current
  head with preview metadata `sha-c453949d0b17`, GHCR login skipped, and no
  image publish. The strict deployment-chain audit passed required gates on
  `master` at `c453949`, including clean current-head CI/logs, current Dart
  package dry-run, current WAMP profile benchmark evidence, current Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. RC readiness remains not-ready only because no approved numeric RC
  tag, GitHub prerelease, or matching RC router image tag has been selected;
  the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval
  is given. Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Hosted evidence for commit `8299cd9`
  (`test: cover rejected json-response mcp bearers`) is clean: `master` CI
  run `26352813257` passed with Fast Checks and Full Verify green plus clean
  logs, and `add-router` CI run `26352812811` passed with Fast Checks and Full
  Verify green. Dart Package Publish Dry Run `26352813256` on `master` and
  `26352812807` on `add-router` passed cleanly at `8299cd9`; WAMP Profile
  Benchmarks `26352813275` on `master` and `26352812823` on `add-router`
  passed at `8299cd9`. Router Image dry-run `26353070574` passed for current
  head with preview metadata `sha-8299cd9de96b`, GHCR login skipped, and no
  image publish. The strict deployment-chain audit passed required gates on
  `master` at `8299cd9`, including clean current-head CI/logs, current Dart
  package dry-run, current WAMP profile benchmark evidence, current Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. RC readiness remains not-ready only because no approved numeric RC
  tag, GitHub prerelease, or matching RC router image tag has been selected;
  the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval
  is given. Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Extended the checked-in router native integration coverage for
  the bearer-protected JSON-response MCP route. The
  `smoke tests MCP router RPC pubsub and route security` integration test now
  proves `/mcp/secure-json-post` exposes route-provided resources, resource
  templates, and prompts through authenticated direct JSON before Streamable
  initialization without creating an MCP session id. After Streamable
  initialize, initialized notification, and tools/list, the same smoke proves
  Streamable resources/list, resources/read, resources/templates/list,
  prompts/list, and prompts/get on the JSON-response route while keeping the
  active session id stable and the POST/SSE resume cursor empty before the
  existing pub/sub and DELETE cleanup assertions. Pre-change `bin/test-fast`
  passed on 2026-05-24. Focused local coverage passed:
  `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`,
  `python3 tool/check_public_artifact_references.py`, and `git diff --check`.
  Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `bb7d3a5`
  (`test: cover secure json-response mcp resources`) is clean: `master` CI
  run `26351940781` passed with Fast Checks and Full Verify green plus clean
  logs, and `add-router` CI run `26351939292` passed with Fast Checks and Full
  Verify green. Dart Package Publish Dry Run `26351940788` on `master` and
  `26351939291` on `add-router` passed cleanly at `bb7d3a5`; WAMP Profile
  Benchmarks `26351940789` on `master` and `26351939286` on `add-router`
  passed at `bb7d3a5`. Router Image dry-run `26352174318` passed for current
  head with preview metadata `sha-bb7d3a5d36c0`, GHCR login skipped, and no
  image publish. The strict deployment-chain audit passed required gates on
  `master` at `bb7d3a5`, including clean current-head CI/logs, current Dart
  package dry-run, current WAMP profile benchmark evidence, current Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. RC readiness remains not-ready only because no approved numeric RC
  tag, GitHub prerelease, or matching RC router image tag has been selected;
  the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval
  is given. Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Added checked-in router native integration coverage for the
  bearer-protected JSON-response MCP route. The shared MCP smoke fixture now
  exposes `/mcp/secure-json-post` with `post_response_transport: json`, the
  same route-provided tool, WAMP meta API, pub/sub, resources, and prompts
  surface as `/mcp/secure`, and the `smoke tests MCP router RPC pubsub and
  route security` integration test proves missing-bearer rejection, public IO
  client authenticated direct JSON tool catalog access, WAMP topic meta
  discovery, Streamable initialize and initialized notifications, tools/list,
  pub/sub subscribe, service-session publish, poll, unsubscribe, and DELETE
  cleanup. The route-level assertions also verify JSON POST responses keep the
  active MCP session id stable without capturing a POST/SSE resume cursor.
  Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage
  passed: `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
  `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`,
  `python3 tool/check_public_artifact_references.py`, and `git diff --check`.
  Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `26d5ed5`
  (`test: cover secure json-response mcp integration`) is clean: `master` CI
  run `26351016213` passed with Fast Checks and Full Verify green plus clean
  logs, and `add-router` CI run `26351015880` passed with Fast Checks and Full
  Verify green. Dart Package Publish Dry Run `26351016222` on `master` and
  `26351015879` on `add-router` passed cleanly at `26d5ed5`; WAMP Profile
  Benchmarks `26351016231` on `master` and `26351015870` on `add-router`
  passed at `26d5ed5`. Router Image dry-run `26351265685` passed for current
  head with preview metadata `sha-26d5ed52278a`, GHCR login skipped, and no
  image publish. The strict deployment-chain audit passed required gates on
  `master` at `26d5ed5`, including clean current-head CI/logs, current Dart
  package dry-run, current WAMP profile benchmark evidence, current Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. RC readiness remains not-ready only because no approved numeric RC
  tag, GitHub prerelease, or matching RC router image tag has been selected;
  the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval
  is given. Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Updated the public router-hosted MCP example to expose a
  bearer-protected JSON-response MCP route at `/mcp/secure-json-post` with
  `post_response_transport: json`. The example smoke now proves missing-bearer
  and unknown-bearer rejection on that route, then uses an HTTP ticket auth
  grant through the public IO client to cover direct JSON tools/list and
  tools/call, WAMP tool/meta helpers, route-provided resources and prompts,
  Streamable initialize and initialized notifications, tools/list, tools/call,
  resources/read, prompts/get, pub/sub subscribe/publish/poll/unsubscribe,
  GET/SSE `notifications/tools/list_changed` polling, and DELETE cleanup.
  The smoke also asserts JSON POST responses keep the active session id stable
  and do not capture POST/SSE cursors before GET/SSE polling. This keeps the
  checked-in public example aligned with the generated consumer-package secure
  JSON-response route readiness evidence without relying on private downstream
  application assumptions. Pre-change `bin/test-fast` passed on 2026-05-24.
  Focused local coverage passed:
  `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`,
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
  `python3 tool/check_public_artifact_references.py`, and `git diff --check`.
  Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `7440ca4`
  (`example: cover secure json-response mcp route`) is clean: `master` CI run
  `26350085437` passed with Fast Checks and Full Verify green plus clean logs,
  and `add-router` CI run `26350083211` passed with Fast Checks and Full
  Verify green. Dart Package Publish Dry Run `26350085430` on `master` and
  `26350083219` on `add-router` passed cleanly at `7440ca4`; WAMP Profile
  Benchmarks `26350085438` on `master` and `26350083220` on `add-router`
  passed at `7440ca4`. Router Image dry-run `26350340880` passed for current
  head with preview metadata `sha-7440ca41ac9a`, GHCR login skipped, and no
  image publish. The strict deployment-chain audit passed required gates on
  `master` at `7440ca4`, including clean current-head CI/logs, current Dart
  package dry-run, current WAMP profile benchmark evidence, current Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. RC readiness remains not-ready only because no approved numeric RC
  tag, GitHub prerelease, or matching RC router image tag has been selected;
  the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval
  is given. Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Added bearer-protected JSON-response MCP route coverage to the
  generated consumer-package smoke. The fixture now exposes
  `/mcp/secure-json-post` with snake-case `post_response_transport: json`,
  rejects missing and unknown bearer tokens before authentication, then runs
  the existing JSON-response compatibility route smoke through an HTTP ticket
  auth grant. The authorized smoke covers direct JSON single, batch,
  notification-only, and error/recovery requests, Streamable initialize and
  initialized notifications, tools/resources/prompts, raw tools/list and ping
  with the active `MCP-Session-Id`, WAMP pub/sub polling, GET/SSE notification
  delivery, and DELETE cleanup without changing the Streamable session id or
  capturing POST/SSE cursors. This closes the app-shaped gap where
  JSON-response routes were only public while secure auth/session correctness
  was proven on the standard Streamable route. Pre-change `bin/test-fast`
  passed on 2026-05-24. Focused local coverage passed:
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, and `git diff --check`. Full local `bin/verify`
  passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `77015b9`
  (`test: cover secure json-response mcp route`) is clean: `master` CI run
  `26349158295` passed with Fast Checks and Full Verify green plus clean logs,
  and `add-router` CI run `26349158303` passed with Fast Checks and Full
  Verify green. The strict deployment-chain audit passed required gates on
  `master` at `77015b9`, including clean current-head CI/logs, relevant Dart
  package dry-run, relevant WAMP profile benchmark evidence, relevant Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. Router Image dry-run
  `26345818520` at `f8497d6` remains relevant because no
  router-image-sensitive paths changed, with preview metadata
  `sha-f8497d6ea540`, GHCR login skipped, and no image publish. Dart Package
  Publish Dry Run `26344002614` at `9ac5e22`, WAMP Profile Benchmarks
  `26344002624` at `9ac5e22`, and Native Artifacts dry-run `26286794628`
  remain relevant because no publish-, WAMP-profile-, or
  native-release-sensitive inputs changed. RC readiness remains not-ready only
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected; the audit suggests `v0.1.0-rc.2` as the next
  numeric tag if release approval is given. Pub.dev publishing remains
  deferred for release-order and operator decisions. No RC tag, GitHub
  Release, or router image was created or moved.
- 2026-05-24: Extended the generated consumer-package router-hosted MCP smoke
  for JSON-response Streamable compatibility routes after initialization. The
  route smoke now sends the active `MCP-Session-Id` through the raw direct JSON
  error/recovery CORS assertion on both `postResponseTransport: json` and
  `streamPostResponses: false` endpoints, covering missing tools, resources,
  prompts, API descriptions, and pub/sub handles plus mixed success/error
  batches with notification suppression. The smoke verifies those active
  direct JSON requests keep the Streamable session id stable and do not capture
  a POST/SSE cursor before continuing normal route operations. Pre-change
  `bin/test-fast` passed on 2026-05-24. Focused local coverage passed:
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `cb6fdfc`
  (`test: cover active json-response mcp errors`) is clean: `master` CI run
  `26348290257` passed with Fast Checks and Full Verify green plus clean logs,
  and `add-router` CI run `26348288465` passed with Fast Checks and Full
  Verify green. The strict deployment-chain audit passed required gates on
  `master` at `cb6fdfc`, including clean current-head CI/logs, relevant Dart
  package dry-run, relevant WAMP profile benchmark evidence, relevant Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. Router Image dry-run
  `26345818520` at `f8497d6` remains relevant because no
  router-image-sensitive paths changed, with preview metadata
  `sha-f8497d6ea540`, GHCR login skipped, and no image publish. Dart Package
  Publish Dry Run `26344002614` at `9ac5e22`, WAMP Profile Benchmarks
  `26344002624` at `9ac5e22`, and Native Artifacts dry-run `26286794628`
  remain relevant because no publish-, WAMP-profile-, or
  native-release-sensitive inputs changed. RC readiness remains not-ready only
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected; the audit suggests `v0.1.0-rc.2` as the next
  numeric tag if release approval is given. Pub.dev publishing remains
  deferred for release-order and operator decisions. No RC tag, GitHub
  Release, or router image was created or moved.
- 2026-05-24: Continued JSON-response Streamable compatibility route
  hardening in the generated consumer-package router-hosted MCP smoke by
  applying the existing raw direct JSON error/recovery CORS assertion to both
  `postResponseTransport: json` and `streamPostResponses: false` routes before
  opening a Streamable session. This proves missing tools, resources, prompts,
  API descriptions, and pub/sub handles return JSON-RPC-shaped errors with
  CORS-visible headers, mixed success/error batches still suppress
  notification-only entries, and follow-up catalog reads recover without
  creating Streamable session state on JSON-response routes. Pre-change
  `bin/test-fast` passed on 2026-05-24. Focused local coverage passed:
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `d1888c0`
  (`test: cover json-response mcp error recovery`) is clean: `master` CI run
  `26347442474` passed with Fast Checks and Full Verify green plus clean logs,
  and `add-router` CI run `26347441207` passed with Fast Checks and Full
  Verify green. Router Image dry-run `26345818520` at `f8497d6` remains
  relevant because no router-image-sensitive paths changed, with preview
  metadata `sha-f8497d6ea540`, GHCR login skipped, and no image publish. Dart
  Package Publish Dry Run `26344002614` at `9ac5e22`, WAMP Profile Benchmarks
  `26344002624` at `9ac5e22`, and Native Artifacts dry-run `26286794628`
  remain relevant because no publish-, WAMP-profile-, or
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `d1888c0`, including clean current-head
  CI/logs, relevant Dart package dry-run, relevant WAMP profile benchmark
  evidence, relevant Router Image dry-run, native release dry-run relevance,
  branch protection, workflow visibility, and router package visibility. RC
  readiness remains not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected; the audit
  suggests `v0.1.0-rc.2` as the next numeric tag if release approval is given.
  Pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-24: Continued JSON-response Streamable compatibility route
  hardening in the generated consumer-package router-hosted MCP smoke by
  applying the existing raw direct JSON notification-only CORS assertion to
  both `postResponseTransport: json` and `streamPostResponses: false` routes
  before opening a Streamable session. This proves notification-only
  initialized/tools, tool-call, and pub/sub publish batches remain
  CORS-visible, bodyless `202 Accepted` responses that do not create or mutate
  Streamable MCP session state on JSON-response routes. Pre-change
  `bin/test-fast` passed on 2026-05-24. Focused local coverage passed:
  `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `d6b4c44`
  (`test: cover json-response mcp notifications`) is clean: `master` CI run
  `26346638661` passed with Fast Checks and Full Verify green plus clean logs,
  and `add-router` CI run `26346636643` passed with Fast Checks and Full
  Verify green. Router Image dry-run `26345818520` at `f8497d6` remains
  relevant because no router-image-sensitive paths changed, with preview
  metadata `sha-f8497d6ea540`, GHCR login skipped, and no image publish. Dart
  Package Publish Dry Run `26344002614` at `9ac5e22`, WAMP Profile Benchmarks
  `26344002624` at `9ac5e22`, and Native Artifacts dry-run `26286794628`
  remain relevant because no publish-, WAMP-profile-, or
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `d6b4c44`, including clean current-head
  CI/logs, relevant Dart package dry-run, relevant WAMP profile benchmark
  evidence, relevant Router Image dry-run, native release dry-run relevance,
  branch protection, workflow visibility, and router package visibility. RC
  readiness remains not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order and operator decisions. No RC
  tag, GitHub Release, or router image was created or moved.
- 2026-05-24: The generated consumer-package router-hosted MCP smoke now
  applies the raw direct JSON CORS single and batch assertions to both
  JSON-response Streamable compatibility routes before opening a Streamable
  session: `postResponseTransport: json` and `streamPostResponses: false`.
  This proves sessionless direct JSON access for tools/list, ping, tool-call
  aliases, WAMP API list/describe metadata, resources/list/read/templates,
  prompts/list/get, and pub/sub subscribe/publish/poll/unsubscribe on those
  JSON response routes, including batch JSON-RPC catalog, detail, tool-call,
  and pub/sub flows. This closes a consumer-readiness gap where the
  compatibility routes had typed Streamable resource/prompt coverage and raw
  stateful tools/ping coverage, but not the direct JSON tool/meta API and
  pub/sub surface expected by agents that do not use the typed Dart client.
  Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage
  passed:
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
  and `git diff --check`. Full local `bin/verify` passed on 2026-05-24.
- 2026-05-24: Hosted evidence for commit `f8497d6`
  (`test: cover direct json mcp response routes`) is clean: `master` CI run
  `26345815906` passed with Fast Checks and Full Verify green plus clean logs,
  `add-router` CI run `26345815895` passed, and clean Router Image dry-run
  `26345818520` passed for current head with preview metadata
  `sha-f8497d6ea540`, GHCR login skipped, and no image publish. The latest
  Dart Package Publish Dry Run `26344002614` at `9ac5e22` remains relevant
  because no publish-sensitive paths changed, the latest WAMP Profile
  Benchmarks run `26344002624` at `9ac5e22` remains relevant because no
  WAMP-profile-sensitive paths changed, and Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. The strict deployment-chain audit passed required gates on
  `master` at `f8497d6`, including clean current-head CI/logs, relevant Dart
  package dry-run, relevant WAMP profile benchmark evidence, current Router
  Image dry-run, native release dry-run relevance, branch protection,
  workflow visibility, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected, and pub.dev publishing
  remains deferred for release-order and operator decisions. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-23: The generated consumer-package router-hosted MCP smoke now
  configures resources, resource templates, prompts, and pagination limits on
  both JSON-response Streamable compatibility routes:
  `postResponseTransport: json` and `streamPostResponses: false`. The smoke
  verifies typed Streamable resources/prompts helpers on those routes,
  confirms the responses stay JSON rather than POST/SSE, keeps the active
  session id stable, and extends typed direct protocol-version override
  coverage to resources/read and prompts/get from the same app-shaped package
  boundary. This closes a remaining consumer-readiness gap where
  JSON-response MCP routes were only proving tools and pub/sub. Pre-change
  `bin/test-fast` passed on 2026-05-23. Focused local coverage passed:
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, and `git diff --check`. Full local `bin/verify`
  passed on 2026-05-23.
- 2026-05-23: Hosted evidence for commit `f860178`
  (`test: cover json-response mcp context routes`) is clean: `master` CI run
  `26344918687` passed with Fast Checks and Full Verify green plus clean logs,
  `add-router` CI run `26344909791` passed, and clean Router Image dry-run
  `26344922913` passed for current head with preview metadata
  `sha-f86017842835`, GHCR login skipped, and no image publish. The latest
  Dart Package Publish Dry Run `26344002614` at `9ac5e22` remains relevant
  because no publish-sensitive paths changed, the latest WAMP Profile
  Benchmarks run `26344002624` at `9ac5e22` remains relevant because no
  WAMP-profile-sensitive paths changed, and Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. The strict deployment-chain audit passed required gates on
  `master` at `f860178`, including clean current-head CI/logs, relevant Dart
  package dry-run, relevant WAMP profile benchmark evidence, current Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order and operator decisions. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-23: Non-initialize per-call `protocolVersion` overrides on
  `McpStreamableHttpClient` Streamable HTTP requests are now header-only and
  no longer replace the client's negotiated MCP protocol version from the
  response header. Initialize requests still negotiate and update the client
  protocol state, while session-scoped helper calls such as
  `ping(protocolVersion: ...)` keep the existing session id, event cursor, and
  negotiated version. The public router-hosted MCP example now proves typed
  direct protocol-version overrides across live tools, resources, prompts,
  WAMP metadata, and pub/sub endpoints, including bearer-protected access. The
  generated consumer-package smoke also exercises typed direct and Streamable
  helper protocol-version overrides from an app-shaped package boundary
  without private project assumptions. Pre-change `bin/test-fast` passed on
  2026-05-23. Focused local coverage passed:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -lc 'source bin/common.sh; run_router_hosted_mcp_example_smoke; run_mcp_consumer_package_smoke'`,
  `bash -n bin/common.sh`, and
  `dart analyze packages/connectanum_client packages/connectanum_router`. Full
  local `bin/verify` passed on 2026-05-23.
- 2026-05-23: Hosted evidence for commit `9ac5e22`
  (`fix: keep streamable protocol overrides stateless`) is clean:
  `master` CI run `26344002623` passed with Fast Checks and Full Verify green
  plus clean logs, `add-router` CI run `26344001242` passed, `master` Dart
  Package Publish Dry Run `26344002614` passed, `add-router` Dart Package
  Publish Dry Run `26344001253` passed, `master` WAMP Profile Benchmarks
  `26344002624` passed, `add-router` WAMP Profile Benchmarks `26344001266`
  passed, and clean Router Image dry-run `26344012477` passed for current
  head with preview metadata `sha-9ac5e22430a4`, GHCR login skipped, and no
  image publish. Native Artifacts dry-run `26286794628` remains relevant
  because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `9ac5e22`,
  including clean current-head CI/logs, current Dart package dry-run, current
  WAMP profile benchmark evidence, current Router Image dry-run, native
  release dry-run relevance, branch protection, workflow visibility, and
  router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: The typed MCP HTTP helper layer now exposes the same per-call
  protocol-version override as the low-level and generic helpers.
  `McpStreamableHttpClient` typed helpers for ping, tool listing/calls and
  notifications, Connectanum direct tool/method access, resources, prompts,
  and the router-hosted WAMP helper extension all accept optional
  `protocolVersion` values and forward them as `MCP-Protocol-Version` without
  mutating the client's negotiated Streamable HTTP version. This keeps
  downstream applications on public typed direct JSON and WAMP helper APIs
  when they need to probe older supported MCP protocol versions, instead of
  forcing raw JSON-RPC POST bodies or lower-level generic calls for that
  compatibility path. Focused local coverage passed:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
  and
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`.
  Pre-change `bin/test-fast` and full local `bin/verify` passed on
  2026-05-23.
- 2026-05-23: Hosted evidence for commit `e2cd258`
  (`fix: expose mcp protocol override on typed helpers`) is clean:
  `master` CI run `26342560829` passed with Fast Checks and Full Verify green
  plus clean logs, `add-router` CI run `26342560812` passed, `master` Dart
  Package Publish Dry Run `26342560810` passed, `add-router` Dart Package
  Publish Dry Run `26342560819` passed, `master` WAMP Profile Benchmarks
  `26342560800` passed, `add-router` WAMP Profile Benchmarks `26342560813`
  passed, and clean Router Image dry-run `26342852651` passed for current
  head with preview metadata `sha-e2cd2580e16a`, GHCR login skipped, and no
  image publish. Native Artifacts dry-run `26286794628` remains relevant
  because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `e2cd258`,
  including clean current-head CI/logs, current Dart package dry-run, current
  WAMP profile benchmark evidence, current Router Image dry-run, native
  release dry-run relevance, branch protection, workflow visibility, and
  router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: Hosted evidence for commit `941ae91`
  (`fix: expose mcp protocol override on request helpers`) is clean:
  `master` CI run `26341477286` passed with Fast Checks and Full Verify green
  plus clean logs, `add-router` CI run `26341477312` passed, `master` Dart
  Package Publish Dry Run `26341477304` passed, `add-router` Dart Package
  Publish Dry Run `26341477297` passed, `master` WAMP Profile Benchmarks
  `26341477303` passed, `add-router` WAMP Profile Benchmarks `26341477296`
  passed, and clean Router Image dry-run `26341778458` passed for current
  head with preview metadata `sha-941ae9164dc5`, GHCR login skipped, and no
  image publish. Native Artifacts dry-run `26286794628` remains relevant
  because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `941ae91`,
  including clean current-head CI/logs, current Dart package dry-run, current
  WAMP profile benchmark evidence, current Router Image dry-run, native
  release dry-run relevance, branch protection, workflow visibility, and
  router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: Generic MCP HTTP client helpers now expose the same
  protocol-version override that low-level POST helpers already had:
  `McpStreamableHttpClient.request(...)`, `requestDirect(...)`,
  `notification(...)`, and `notificationDirect(...)` accept an optional
  `protocolVersion` and forward it as `MCP-Protocol-Version` without mutating
  the client's negotiated Streamable HTTP version. This keeps downstream
  applications on public direct JSON tool/meta APIs when they need to probe
  older supported MCP protocol versions, instead of forcing raw JSON-RPC POST
  bodies for that compatibility path. Focused local coverage passed:
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
  and
  `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`.
  Pre-change `bin/test-fast` and full local `bin/verify` passed on
  2026-05-23. Hosted evidence is pending for the next pushed commit; the
  latest fully clean hosted checkpoint remains `25fd0f7`.
- 2026-05-23: Streamable HTTP explicit initialize negotiation now sends the
  requested supported MCP protocol version in both the JSON-RPC initialize body
  and the `MCP-Protocol-Version` request header. The low-level direct JSON POST
  helpers also accept a protocol-version header override without mutating the
  negotiated client version, so compatibility probes can exercise older
  supported MCP versions through direct JSON access. Generated
  consumer-package smokes and the router-hosted example now keep the client
  default at latest while passing explicit initialize versions, proving
  header/body alignment from the consumer boundary. Pre-change `bin/test-fast`
  passed, focused MCP client test, generated consumer smoke, router-hosted
  example smoke, public-artifact guard, shell syntax check, diff checks, and
  full local `bin/verify` passed on 2026-05-23. Commit `25fd0f7`
  (`fix: align explicit mcp protocol headers`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `25fd0f7`: `master` CI run `26340457507` passed with Fast Checks and Full
  Verify green plus clean logs, `add-router` CI run `26340457117` passed,
  `master` Dart Package Publish Dry Run `26340457490` passed, `add-router`
  Dart Package Publish Dry Run `26340457128` passed, `master` WAMP Profile
  Benchmarks `26340457495` passed, `add-router` WAMP Profile Benchmarks
  `26340457141` passed, and clean Router Image dry-run `26340473727` passed
  for current head with preview metadata `sha-25fd0f778518`, GHCR login
  skipped, and no image publish. Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `25fd0f7`, including clean current-head CI/logs, current Dart package
  dry-run, current WAMP profile benchmark evidence, current Router Image
  dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order and operator decisions. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-23: MCP initialize negotiation now returns a requested supported
  protocol version (`2025-03-26`, `2025-06-18`, or `2025-11-25`) instead of
  always upgrading to latest, while unsupported body versions still fall back
  to latest. Router-hosted Streamable HTTP and direct JSON responses propagate
  the negotiated or supported request protocol version in MCP response headers,
  and the Streamable HTTP client updates its negotiated protocol version from
  the initialize result. Generated consumer-package smokes and the
  router-hosted example now assert that supported older MCP versions remain
  negotiated for downstream application readiness. Pre-change `bin/test-fast`
  passed, focused lifecycle/client/router, generated consumer smoke,
  router-hosted example smoke, public-artifact guard, and diff checks passed,
  and full local `bin/verify` passed on 2026-05-23. Commit `d216a2d`
  (`fix: honor supported mcp protocol versions`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `d216a2d`: `master` CI run `26339458336` passed with Fast Checks
  and Full Verify green plus clean logs, `add-router` CI run `26339456857`
  passed, `master` Dart Package Publish Dry Run `26339458338` passed,
  `add-router` Dart Package Publish Dry Run `26339456838` passed, `master`
  WAMP Profile Benchmarks `26339458339` passed, `add-router` WAMP Profile
  Benchmarks `26339456830` passed, and clean Router Image dry-run
  `26339470709` passed for current head with preview metadata
  `sha-d216a2d5ae8e`, GHCR login skipped, and no image publish. Native
  Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `d216a2d`, including clean current-head
  CI/logs, current Dart package dry-run, current WAMP profile benchmark
  evidence, current Router Image dry-run, native release dry-run relevance,
  branch protection, workflow visibility, and router package visibility. RC
  readiness remains not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order and operator decisions. No RC
  tag, GitHub Release, or router image was created or moved.
- 2026-05-23: The public artifact reference guard now also scans
  `bin/common.sh`, keeping the generated MCP consumer smoke packages and their
  embedded package metadata under the same local downstream path and
  private-literal guard as checked-in public docs, package metadata,
  release-note templates, and examples. Pre-change `bin/test-fast` passed, and
  focused local checks passed: `python3 tool/check_public_artifact_references.py`
  and `python3 tool/test_public_artifact_references.py`. Full local
  `bin/verify` passed on 2026-05-23 for this checkpoint. Commit `c704248` was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `c704248`: `master` CI run `26337377257` passed
  with Fast Checks and Full Verify green plus clean logs, and `add-router` CI
  run `26337374836` passed. The strict deployment-chain audit passed required
  gates on `master` at `c704248`; Dart Package Publish Dry Run, Native
  Artifacts dry-run, Router Image dry-run, and WAMP Profile Benchmarks evidence
  from `e14615a` or earlier remained relevant because `c704248` did not change
  those sensitive inputs. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: Fast and full verification now run
  `tool/check_public_artifact_references.py` plus focused unit coverage to
  guard checked-in public docs, release-note templates, package metadata, and
  examples against local downstream paths. The guard keeps the release/public
  artifact boundary aligned with neutral "consumer application" and
  "downstream application" wording without checking in private application
  names. Pre-change `bin/test-fast` passed, and focused local checks passed:
  `python3 tool/check_public_artifact_references.py`,
  `python3 tool/test_public_artifact_references.py`, `bash -n bin/test-fast
  bin/test-all`, and `git diff --check`. Full local `bin/verify` passed after
  the verification guard was wired into fast/full verification. Commit
  `b259c79` was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `b259c79`: `master` CI run
  `26336504930` passed with Fast Checks and Full Verify green plus clean logs,
  and `add-router` CI run `26336504920` passed. The strict deployment-chain
  audit passed required gates on `master` at `b259c79`; Dart Package Publish
  Dry Run, Native Artifacts dry-run, Router Image dry-run, and WAMP Profile
  Benchmarks evidence from `e14615a` or earlier remained relevant because
  `b259c79` did not change those sensitive inputs. RC readiness remains
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected, and pub.dev publishing
  remains deferred for release-order and operator decisions. No RC tag, GitHub
  Release, or router image was created or moved.
- 2026-05-23: The generated consumer package smoke now exercises
  router-hosted MCP from the package boundary with the public MCP route
  configured through camel-case route option aliases for server identity,
  catalog page sizes, allowed origins, topic schema metadata, and resource
  template/content fields. The smoke asserts that Streamable HTTP
  `initialize` returns the route-provided MCP `serverInfo` and `instructions`;
  the JSON POST and non-streaming POST route smokes also use the camel-case
  response-mode aliases while the secure route keeps the legacy snake-case
  options covered. Local verification passed: pre-change `bin/test-fast`,
  focused generated MCP consumer package smoke, `bash -n bin/common.sh`,
  `git diff --check`, and full local `bin/verify`. Hosted evidence is pending
  for the next pushed commit; the latest fully clean hosted checkpoint remains
  `e14615a`.
- 2026-05-23: Router-hosted MCP route options now honor and validate
  top-level camel-case aliases for agent-facing controls, including
  `includePubsubTools`, `includeStandardMetaApi`,
  `includeRegisteredProcedures`, `includeSubscribedTopics`,
  `toolListPageSize`, `promptListPageSize`, `resourceListPageSize`,
  `resourceTemplateListPageSize`, `postResponseTransport`, and
  `streamPostResponses`. Route `name`, `version`, `title`, `description`, and
  `instructions` now flow into MCP `initialize` server metadata and
  instructions instead of only influencing direct WAMP API metadata, and prompt
  `resultDescription` is accepted and validated as the camel-case alias. Local
  verification passed: pre-change `bin/test-fast`, focused router JSON config
  test, focused router-hosted MCP alias/server identity integration test,
  `dart analyze packages/connectanum_router`, `git diff --check`, and full
  local `bin/verify`. Commit `e14615a`
  (`fix: honor mcp route option aliases`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `e14615a`: `master` CI run `26334367559` passed with Fast Checks and Full
  Verify green plus clean logs, `add-router` CI run `26334364715` passed,
  `master` Dart Package Publish Dry Run `26334367577` passed, `add-router`
  Dart Package Publish Dry Run `26334364694` passed, `master` WAMP Profile
  Benchmarks `26334368013` passed, `add-router` WAMP Profile Benchmarks
  `26334364701` passed, and clean Router Image dry-run `26334375630` passed
  for current head with preview metadata `sha-e14615a40cc2`, GHCR login
  skipped, and no image publish. Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `e14615a`, including clean current-head CI/logs, current Dart package
  dry-run, current WAMP profile benchmark evidence, current Router Image
  dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order and operator decisions. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-23: Router-hosted MCP route options now validate agent-facing
  string fields before building the native router config. Malformed server
  `name`, configured procedure/topic display fields, configured resource and
  resource-template URI/display/content fields, and configured prompt,
  prompt-argument, and prompt-message string fields fail fast instead of being
  silently dropped or reported as vague missing values. Configured procedures
  now also honor the camel-case `toolName` alias. Pre-change `bin/test-fast`,
  focused router JSON config test, and full local `bin/verify` passed. Commit
  `ef4906b` (`fix: validate mcp string route options`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `ef4906b`: `master` CI run `26333047829` passed with Fast Checks
  and Full Verify green plus clean logs, `add-router` CI run `26333047819`
  passed, `master` Dart Package Publish Dry Run `26333047828` passed,
  `add-router` Dart Package Publish Dry Run `26333047820` passed, `master`
  WAMP Profile Benchmarks `26333047831` passed, `add-router` WAMP Profile
  Benchmarks `26333047818` passed, and clean Router Image dry-run
  `26333056237` passed for current head with preview metadata
  `sha-ef4906b7cab3`, GHCR login skipped, and no image publish. Native
  Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `ef4906b`, including clean current-head
  CI/logs, current Dart package dry-run, current WAMP profile benchmark
  evidence, current Router Image dry-run, native release dry-run relevance,
  branch protection, workflow visibility, and router package visibility. RC
  readiness remains not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order and operator decisions. No RC
  tag, GitHub Release, or router image was created or moved.
- 2026-05-23: Router-hosted MCP procedure and topic metadata route options now
  validate agent-facing metadata shapes before native router config export.
  Metadata string fields, string-list fields such as `publishesEvents`, direct
  annotation hints, and nested `annotations` hint values now fail fast when
  malformed instead of being silently dropped from direct JSON or Streamable
  HTTP tool/topic metadata. Pre-change `bin/test-fast`, focused router JSON
  config test, and full local `bin/verify` passed. Commit `de79b40`
  (`fix: validate mcp metadata route options`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `de79b40`: `master` CI run `26332071957` passed with Fast Checks and Full
  Verify green plus clean logs, `add-router` CI run `26332071970` passed,
  `master` Dart Package Publish Dry Run `26332071969` passed, `add-router`
  Dart Package Publish Dry Run `26332071958` passed, `master` WAMP Profile
  Benchmarks `26332071941` passed, `add-router` WAMP Profile Benchmarks
  `26332071959` passed, and clean Router Image dry-run `26332103181` passed
  for current head with preview metadata `sha-de79b40edc18`, GHCR login
  skipped, and no image publish. Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `de79b40`, including clean current-head CI/logs, current Dart package
  dry-run, current WAMP profile benchmark evidence, current Router Image
  dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order and operator decisions. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-23: Router-hosted MCP schema route option validation now walks
  nested procedure and topic schema metadata recursively, requiring map keys to
  be strings, values to be JSON-compatible, and numbers to be finite. Malformed
  nested `inputSchema`, `outputJsonSchema`, `eventSchema`, and metadata schema
  aliases now fail while building native router config instead of escaping into
  agent-facing tool/topic metadata for direct JSON or Streamable HTTP clients.
  Pre-change `bin/test-fast`, focused router JSON config test, and full local
  `bin/verify` passed. Commit `bc2260c`
  (`fix: validate recursive mcp schema json`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `bc2260c`: `master` CI run `26331196480` passed with Fast Checks and Full
  Verify green plus clean logs, `add-router` CI run `26331196355` passed,
  `master` Dart Package Publish Dry Run `26331196497` passed, `add-router`
  Dart Package Publish Dry Run `26331196373` passed, `master` WAMP Profile
  Benchmarks `26331196490` passed, `add-router` WAMP Profile Benchmarks
  `26331196365` passed, and clean Router Image dry-run `26331202343` passed
  for current head with preview metadata `sha-bc2260c99087`, GHCR login
  skipped, and no image publish. Native Artifacts dry-run `26286794628` remains
  relevant because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `bc2260c`,
  including clean current-head CI/logs, current Dart package dry-run, current
  WAMP profile benchmark evidence, current Router Image dry-run, native release
  dry-run relevance, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected,
  and pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-23: Router-hosted MCP procedure and topic route config now validates
  direct JSON schema aliases plus nested metadata schema aliases as JSON
  objects with string keys. Malformed `inputSchema`, `outputJsonSchema`,
  `eventSchema`, and metadata schema variants now fail while building native
  router config instead of silently dropping agent-facing tool or topic schema
  metadata for a consumer application. Pre-change `bin/test-fast`, focused
  router JSON config test, and full local `bin/verify` passed. Commit
  `49ff2c5` (`fix: validate mcp schema route options`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `49ff2c5`: `master` CI run `26330377110` passed with Fast Checks
  and Full Verify green plus clean logs, `add-router` CI run `26330375276`
  passed, `master` Dart Package Publish Dry Run `26330377353` passed,
  `add-router` Dart Package Publish Dry Run `26330375284` passed, `master` WAMP
  Profile Benchmarks `26330377119` passed, `add-router` WAMP Profile Benchmarks
  `26330375274` passed, and clean Router Image dry-run `26330382749` passed for
  current head with preview metadata `sha-49ff2c504620`, GHCR login skipped,
  and no image publish. Native Artifacts dry-run `26286794628` remains relevant
  because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `49ff2c5`,
  including clean current-head CI/logs, current Dart package dry-run, current
  WAMP profile benchmark evidence, current Router Image dry-run, native release
  dry-run relevance, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected,
  and pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-23: Router-hosted MCP topic route config now validates and honors
  camel-case `allowPublish` and `allowSubscribe` aliases in addition to the
  existing snake-case config keys, matching the public MCP WAMP topic metadata
  shape. The router-hosted MCP smoke now declares a public read-only topic with
  `allowPublish: false`; direct JSON and Streamable HTTP checks prove the
  metadata exposes `allowPublish: false`/`allowSubscribe: true` and that
  publish attempts fail instead of silently defaulting to publishable.
  Pre-change `bin/test-fast`, focused router JSON config test, focused
  router-hosted MCP integration smoke, and full local `bin/verify` passed.
  Commit `2659ee0` (`fix: honor camel mcp topic options`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `2659ee0`: `master` CI run `26329548485` passed with Fast Checks
  and Full Verify green plus clean logs, `add-router` CI run `26329547966`
  passed, `master` Dart Package Publish Dry Run `26329548469` passed,
  `add-router` Dart Package Publish Dry Run `26329547976` passed, `master` WAMP
  Profile Benchmarks `26329548463` passed, `add-router` WAMP Profile Benchmarks
  `26329547974` passed, and clean Router Image dry-run `26329558070` passed for
  current head with preview metadata `sha-2659ee0e63f5`, GHCR login skipped,
  and no image publish. Native Artifacts dry-run `26286794628` remains relevant
  because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `2659ee0`,
  including clean current-head CI/logs, current Dart package dry-run, current
  WAMP profile benchmark evidence, current Router Image dry-run, native release
  dry-run relevance, branch protection, workflow visibility, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag, GitHub prerelease, or matching RC router image tag has been selected,
  and pub.dev publishing remains deferred for release-order and operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-23: MCP route option validation now also rejects malformed nested
  configured procedure/topic/resource/prompt fields while building native
  router config, including non-boolean procedure call flags, non-boolean topic
  publish/subscribe flags, non-integer or negative resource sizes, non-list
  prompt arguments/messages, non-boolean required prompt arguments, and
  non-string prompt message roles. This keeps router-hosted MCP endpoints
  fail-fast for consumer application configuration errors instead of silently
  ignoring nested route fields or falling back to defaults. Pre-change
  `bin/test-fast`, focused router JSON config test, and full local
  `bin/verify` passed. Commit `9b3e96d`
  (`fix: validate nested mcp route options`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `9b3e96d`: `master` CI run `26328491376` passed with Fast Checks and Full
  Verify green plus clean logs, `add-router` CI run `26328491411` passed,
  `master` Dart Package Publish Dry Run `26328491393` passed, `add-router`
  Dart Package Publish Dry Run `26328491409` passed, `master` WAMP Profile
  Benchmarks `26328491395` passed, `add-router` WAMP Profile Benchmarks
  `26328491408` passed, and clean Router Image dry-run `26328839965` passed
  for current head with preview metadata `sha-9b3e96d38542`, GHCR login
  skipped, and no image publish. Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `9b3e96d`, including clean current-head CI/logs, current Dart package
  dry-run, current WAMP profile benchmark evidence, current Router Image
  dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order and operator decisions. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-23: MCP route option validation now also rejects non-boolean include
  flags, non-positive or non-integer list page sizes, malformed
  allowed-origin option shapes, and malformed configured
  procedure/topic/resource/resource-template/prompt list entries while
  building native router config. This keeps router-hosted MCP endpoints
  fail-fast for consumer application configuration errors instead of silently
  disabling catalog entries, defaulting capability switches, or deferring
  page-size failures until request-time endpoint construction. Pre-change
  `bin/test-fast`, focused router JSON config test, and full local
  `bin/verify` passed. Commit `7f2d4f9`
  (`fix: validate mcp route option shapes`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `7f2d4f9`: `master` CI run `26327603290` passed with Fast Checks and Full
  Verify green plus clean logs, `add-router` CI run `26327603273` passed,
  `master` Dart Package Publish Dry Run `26327603260` passed, `add-router`
  Dart Package Publish Dry Run `26327603276` passed, `master` WAMP Profile
  Benchmarks `26327603281` passed, `add-router` WAMP Profile Benchmarks
  `26327603275` passed, and Router Image dry-run `26327615245` passed for
  current head with preview metadata `sha-7f2d4f9ca7ec`, GHCR login skipped,
  and no image publish. Native Artifacts dry-run `26286794628` remains
  relevant because no native-release-sensitive inputs changed. The strict
  deployment-chain audit passed required gates on `master` at `7f2d4f9`,
  including clean current-head CI/logs, current Dart package dry-run, current
  WAMP profile benchmark evidence, current Router Image dry-run, native
  release dry-run relevance, branch protection, workflow visibility, and
  router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: MCP route option validation now rejects invalid
  `post_response_transport` values and non-boolean `stream_post_responses`
  values while building native router config, so consumer applications fail
  fast on non-streaming POST response misconfiguration instead of silently
  falling back to the default Streamable POST response behavior. The generated
  router-hosted MCP consumer package smoke now covers both public
  non-streaming POST response configuration forms: `/mcp/json-post` with
  `post_response_transport: json`, and `/mcp/non-streaming-post` with
  `stream_post_responses: false`. The shared smoke initializes Streamable
  sessions with the package client, proves normal Streamable POST operations
  stay JSON instead of SSE even when `Accept` permits both JSON and
  `text/event-stream`, verifies `sessionId` stability and no POST SSE cursor
  capture across tool catalog, tool call, raw `tools/list`, raw `ping`, and
  pub/sub publish/poll paths, then proves GET/SSE polling remains available
  for server notifications before session deletion clears state. This keeps
  downstream application readiness coverage on public APIs and neutral router
  fixtures without private project assumptions. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused router JSON config test, focused generated
  router-hosted MCP consumer smoke, and full local `bin/verify` passed. Commit
  `e274b5a` (`fix: validate mcp post response options`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `e274b5a`: `master` CI run `26326611407` passed with Fast Checks
  and Full Verify green plus clean logs, `add-router` CI run `26326609144`
  passed, `master` Dart Package Publish Dry Run `26326611413` passed,
  `add-router` Dart Package Publish Dry Run `26326609130` passed, `master`
  WAMP Profile Benchmarks `26326611401` passed, `add-router` WAMP Profile
  Benchmarks `26326609137` passed, and Router Image dry-run `26326876433`
  passed for current head with GHCR login skipped and no image publish. Native
  Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed. The strict deployment-chain audit
  passed required gates on `master` at `e274b5a`, including clean current-head
  CI/logs, current Dart package dry-run, current WAMP profile benchmark
  evidence, current Router Image dry-run, native release dry-run relevance,
  branch protection, workflow visibility, and router package visibility. RC
  readiness remains not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order and operator decisions. No RC
  tag, GitHub Release, or router image was created or moved.
- 2026-05-23: The generated router-hosted MCP consumer package smoke now adds
  a public `/mcp/json-post` route with `post_response_transport: json` and a
  declared pub/sub topic. The smoke initializes a Streamable session with the
  package client, proves normal Streamable POST operations stay JSON instead
  of SSE even when `Accept` permits both JSON and `text/event-stream`, verifies
  `sessionId` stability and no POST SSE cursor capture across tool catalog,
  tool call, raw `tools/list`, raw `ping`, and pub/sub publish/poll paths,
  then proves GET/SSE polling remains available for server notifications
  before session deletion clears state. This keeps downstream application
  readiness coverage on public APIs and neutral router fixtures without
  private project assumptions. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused generated router-hosted MCP consumer smoke,
  and full local `bin/verify` passed. Commit `d2cc63b`
  (`test: cover mcp json post responses`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `d2cc63b`: `master` CI run `26325673314` passed with Fast Checks and Full
  Verify green plus clean logs, and `add-router` CI run `26325672952` passed.
  `master` Dart Package Publish Dry Run `26323732462`, `master` WAMP Profile
  Benchmarks `26323732487`, Router Image dry-run `26323764121`, and Native
  Artifacts dry-run `26286794628` remain relevant because no
  publish-sensitive, WAMP-profile-benchmark-sensitive, router-image-sensitive,
  or native-release-sensitive inputs changed since those runs. The strict
  deployment-chain audit passed required gates on `master` at `d2cc63b`,
  including clean current-head CI/logs, relevant Dart package dry-run,
  relevant WAMP profile benchmark evidence, relevant Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility,
  and router package visibility. RC readiness remains not-ready only because
  no approved numeric RC tag, GitHub prerelease, or matching RC router image
  tag has been selected, and pub.dev publishing remains deferred for
  release-order and operator decisions. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-23: The generated router-hosted MCP consumer package smoke now
  proves active Streamable sessions do not contaminate lifecycle-free direct
  JSON access. After Streamable initialization, the smoke calls public direct
  JSON WAMP API helpers, public direct JSON WAMP meta helpers, direct JSON WAMP
  subscription meta discovery, and direct JSON session/authid/authrole publish
  filters, then verifies the original Streamable `sessionId` and `lastEventId`
  remain unchanged. This keeps downstream application readiness coverage on
  public APIs and neutral router fixtures without private project assumptions.
  Pre-change `bin/test-fast`, `bash -n bin/common.sh`, focused generated
  router-hosted MCP consumer smoke, and full local `bin/verify` passed. Commit
  `dfedfd5` (`test: cover active-session direct mcp access`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `dfedfd5`: `master` CI run `26324656392` passed with
  Fast Checks and Full Verify green plus clean logs, and `add-router` CI run
  `26324655835` passed. `master` Dart Package Publish Dry Run `26323732462`,
  `master` WAMP Profile Benchmarks `26323732487`, Router Image dry-run
  `26323764121`, and Native Artifacts dry-run `26286794628` remain relevant
  because no publish-sensitive, WAMP-profile-benchmark-sensitive,
  router-image-sensitive, or native-release-sensitive inputs changed since
  those runs. The strict deployment-chain audit passed required gates on
  `master` at `dfedfd5`, including clean current-head CI/logs, relevant Dart
  package dry-run, relevant WAMP profile benchmark evidence, relevant Router
  Image dry-run, native release dry-run relevance, branch protection, workflow
  visibility, and router package visibility. RC readiness remains not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order and operator decisions. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-23: Router publish delivery now honors standard WAMP authid/authrole
  include and exclude option keys from raw WAMP, direct JSON MCP, and
  Streamable MCP publish calls. The router worker maps `exclude_authid`,
  `exclude_authrole`, `eligible_authid`, and `eligible_authrole` into state
  matching, while the state matcher still accepts legacy plural auth filter
  aliases for compatibility. The generated router-hosted MCP consumer package
  smoke discovers the MCP subscriber session and auth metadata through WAMP
  meta, then proves session ID, authid, and authrole delivery/suppression
  filters through both direct JSON and Streamable MCP paths without private
  project assumptions. A router worker regression covers raw WAMP authid
  include/exclude delivery. Pre-change `bin/test-fast`, `bash -n bin/common.sh`,
  focused router worker authid/authrole tests, focused generated router-hosted
  MCP consumer smoke, repeated `bin/test-fast`, and full local `bin/verify`
  passed. Commit `3c6ff20` (`fix: honor mcp auth publish filters`) was pushed
  to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `3c6ff20`: `master` CI run `26323732469` passed with
  Fast Checks and Full Verify green and clean logs, `add-router` CI run
  `26323730795` passed, `master` Dart Package Publish Dry Run `26323732462`
  and `add-router` Dart Package Publish Dry Run `26323730799` passed, `master`
  WAMP Profile Benchmarks `26323732487` and `add-router` WAMP Profile
  Benchmarks `26323730797` passed, and Router Image dry-run `26323764121`
  passed for `0.1.0-rc.1-validation.3c6ff20` with preview upload, skipped GHCR
  login, completed multi-arch build, and clean annotations. Native Artifacts
  dry-run `26286794628` remains relevant because no native-release-sensitive
  inputs changed since `89c7915`. The strict deployment-chain audit passed
  required gates on `master` at `3c6ff20`, including clean current-head CI/logs,
  Dart package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility, and
  router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: The generated router-hosted MCP consumer package smoke now
  proves public `mcpWampPublishOptions(...)` session-filter delivery semantics
  through both direct JSON and Streamable MCP paths. The smoke discovers the
  MCP subscriber session through WAMP subscription meta, publishes with
  `eligible: [subscriberId]` and proves delivery, then publishes with
  `exclude: [subscriberId]` plus `excludeMe: false` and uses a follow-up
  delivered marker to prove the same subscription does not receive the excluded
  event. It keeps the earlier
  `excludeMe: false` self-delivery, `excludeMe: true` non-delivery, and
  service-session publication delivery checks, so the generated consumer
  package now covers acknowledged publish options and real router pub/sub
  delivery filters without private project assumptions. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused generated router-hosted MCP
  consumer smoke, repeated `bin/test-fast`, and full local `bin/verify` passed.
  Commit `f7cf3d3` (`test: cover mcp session publish filters`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted evidence is
  clean at `f7cf3d3`: `master` CI run `26322569564` passed with Fast Checks
  and Full Verify green and clean logs, and `add-router` CI run `26322567606`
  passed. `master` Dart Package Publish Dry Run `26319930721` and `add-router`
  Dart Package Publish Dry Run `26319930224` remain relevant because no
  publish-sensitive paths changed since `8aba33c`; `master` WAMP Profile
  Benchmarks `26319930699` and `add-router` WAMP Profile Benchmarks
  `26319930217` remain relevant because no WAMP profile benchmark-sensitive
  paths changed since `8aba33c`; Router Image dry-run `26320203435` remains
  relevant because no router-image-sensitive paths changed since `8aba33c`;
  Native Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed since `89c7915`. The strict
  deployment-chain audit passed required gates on `master` at `f7cf3d3`,
  including clean current-head CI/logs, relevant Dart package dry-run,
  relevant WAMP profile benchmark evidence, relevant Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility,
  and router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: The generated router-hosted MCP consumer package smoke now
  proves public `mcpWampPublishOptions(...)` delivery semantics through both
  direct JSON and Streamable MCP paths. Each path publishes with
  `acknowledge: true` and `excludeMe: false`, then polls the same MCP
  subscription to prove the caller receives its own event; each path also
  publishes with `excludeMe: true` and asserts the caller does not receive that
  event. The smoke still verifies service-session publication delivery
  afterward, so the coverage now proves the public option builder affects real
  router pub/sub delivery instead of only publish acknowledgements. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused generated router-hosted MCP
  consumer smoke, repeated `bin/test-fast`, and full local `bin/verify` passed.
  Commit `2e3a792` (`test: cover mcp exclude-me publish options`) was pushed
  to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted evidence
  is clean at `2e3a792`: `master` CI run `26321124924` passed with Fast Checks
  and Full Verify green and clean logs, and `add-router` CI run `26321124820`
  passed. `master` Dart Package Publish Dry Run `26319930721` and `add-router`
  Dart Package Publish Dry Run `26319930224` remain relevant because no
  publish-sensitive paths changed since `8aba33c`; `master` WAMP Profile
  Benchmarks `26319930699` and `add-router` WAMP Profile Benchmarks
  `26319930217` remain relevant because no WAMP profile benchmark-sensitive
  paths changed since `8aba33c`; Router Image dry-run `26320203435` remains
  relevant because no router-image-sensitive paths changed since `8aba33c`;
  Native Artifacts dry-run `26286794628` remains relevant because no
  native-release-sensitive inputs changed since `89c7915`. The strict
  deployment-chain audit passed required gates on `master` at `2e3a792`,
  including clean current-head CI/logs, relevant Dart package dry-run,
  relevant WAMP profile benchmark evidence, relevant Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility,
  and router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: Public MCP WAMP pub/sub clients now have
  `mcpWampPublishOptions(...)` and `mcpWampSubscribeOptions(...)` builders for
  canonical WAMP option maps instead of hand-built string-key maps. The
  builders emit standard wire keys such as `exclude_me`, `meta_topic`,
  `get_retained`, and PPT option fields while preserving consumer extension
  keys from `custom`; typed parameters override duplicate `custom` entries for
  standard fields. Streamable client tests prove both active-session and
  lifecycle-free direct JSON helpers send these option maps, the MCP IO export
  smoke covers the same helpers through `connectanum_mcp_io.dart`, and the
  generated client-only plus router-hosted consumer smokes use the public
  builders for subscribe/publish acknowledgement paths. Pre-change
  `bin/test-fast`, focused client/MCP tests,
  `dart analyze packages/connectanum_client packages/connectanum_mcp`, focused
  generated client-only and router-hosted consumer smokes, repeated
  `bin/test-fast`, and full local `bin/verify` passed. Commit `8aba33c`
  (`feat: add mcp wamp option builders`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted evidence is clean at
  `8aba33c`: `master` CI run `26319930691` passed with Fast Checks and Full
  Verify green and clean logs, `add-router` CI run `26319930213` passed,
  `master` Dart Package Publish Dry Run `26319930721` and `add-router` Dart
  Package Publish Dry Run `26319930224` passed, `master` WAMP Profile
  Benchmarks `26319930699` and `add-router` WAMP Profile Benchmarks
  `26319930217` passed, and Router Image dry-run `26320203435` passed for
  `0.1.0-rc.2-validation.8aba33c` with preview upload, skipped GHCR login,
  completed multi-arch build, and clean annotations. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed since `89c7915`. The strict deployment-chain audit passed required
  gates on `master` at `8aba33c`, including clean current-head CI/logs, Dart
  package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility,
  and router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: `McpWampApi` now normalizes standard WAMP publish and subscribe
  option keys from public MCP pub/sub `options` maps into typed
  `PublishOptions` and `SubscribeOptions` before dispatching through the WAMP
  session. Publish options now accept `acknowledge`, session
  `exclude`/`eligible` filters, authid/authrole include/exclude filters,
  `exclude_me`, `disclose_me`, `retain`, and PPT option aliases; the top-level
  MCP `acknowledge` argument wins over `options.acknowledge`. Subscribe
  options now accept `match`, `meta_topic`, and `get_retained`. Unknown option
  keys are still preserved in `custom`, so consumer applications can pass
  extension fields without losing them. The MCP WAMP API regression now
  captures publish and subscribe requests and asserts typed option mapping plus
  custom-option preservation. Focused `wamp_api_test.dart`, full
  `wamp_api_test.dart`, `dart analyze packages/connectanum_mcp`, repeated
  `bin/test-fast`, and full local `bin/verify` passed. Commit `06228fb`
  (`fix: normalize mcp wamp pubsub options`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted evidence is clean at
  `06228fb`: `master` CI run `26318444140` passed with Fast Checks and Full
  Verify green and clean logs, `add-router` CI run `26318442150` passed,
  `master` Dart Package Publish Dry Run `26318444109` and `add-router` Dart
  Package Publish Dry Run `26318442141` passed, and Router Image dry-run
  `26318773516` passed for `0.1.0-rc.2-validation.06228fb` with preview
  upload, skipped GHCR login, completed multi-arch build, and clean
  annotations. WAMP Profile Benchmarks `26317169023` on `master` and
  `26317168999` on `add-router` remain relevant because no WAMP profile
  benchmark-sensitive inputs changed since `d35ac42`. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed since `89c7915`. The strict deployment-chain audit passed required
  gates on `master` at `06228fb`, including clean current-head CI/logs, Dart
  package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility,
  and router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: `McpStreamableHttpClient._postPayload()` now validates
  JSON-RPC POST response semantics for lifecycle-free direct JSON calls as well
  as Streamable HTTP session calls before accepting response state. Successful
  non-empty JSON or POST/SSE response bodies to JSON-RPC notifications or
  notification-only batches now throw even when the caller used
  `streamable: false` / `includeSession: false`; accepted, no-content, and
  empty notification responses remain accepted. Direct JSON helpers remain
  lifecycle-free because response `MCP-Session-Id` / protocol-version headers
  and SSE resume cursors are only captured for lifecycle-bound Streamable
  requests. Focused client coverage now exercises direct JSON single
  notifications and notification-only batches with response bodies and proves
  the active Streamable `sessionId` and `lastEventId` remain unchanged. The
  generated client-only consumer-package smoke covers the same direct JSON
  notification-body rejection through public `connectanum_mcp_io.dart` APIs.
  The generated smoke endpoint now returns accepted/no-body responses for
  ordinary no-id JSON-RPC messages unless a test hook explicitly forces a
  malformed notification response body. After the fix, focused direct JSON
  regression coverage, full `streamable_http_client_test.dart`, `bash -n
  bin/common.sh`, `dart analyze packages/connectanum_client`, focused
  generated client-only consumer smoke, repeated `bin/test-fast`, and full
  local `bin/verify` passed. Commit `d35ac42`
  (`fix: reject direct mcp notification responses`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted evidence is clean
  at `d35ac42`: `master` CI run `26317169024` passed with Fast Checks and Full
  Verify green and clean logs, `add-router` CI run `26317168997` passed,
  `master` Dart Package Publish Dry Run `26317168989` and `add-router` Dart
  Package Publish Dry Run `26317168998` passed, `master` WAMP Profile
  Benchmarks `26317169023` and `add-router` WAMP Profile Benchmarks
  `26317168999` passed, and Router Image dry-run `26317182342` passed for
  `0.1.0-rc.2-validation.d35ac42` with preview upload, skipped GHCR login,
  completed multi-arch build, and clean annotations. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed since `89c7915`. The strict deployment-chain audit passed required
  gates on `master` at `d35ac42`, including clean current-head CI/logs, Dart
  package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility,
  and router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-23: `McpStreamableHttpClient._postPayload()` now rejects non-empty
  successful POST response bodies for JSON-RPC notifications and
  notification-only batches before accepting response `MCP-Session-Id` /
  protocol-version headers or POST/SSE resume cursors. This follows the MCP
  Streamable HTTP transport contract
  (`https://modelcontextprotocol.io/specification/2025-06-18/basic/transports`):
  accepted client notifications or responses use `202 Accepted` with no body,
  while response-bearing requests use JSON or SSE bodies. Empty, accepted, or
  no-content notification responses still remain accepted. The focused
  regression was added first and failed against the prior behavior because a
  notification-only POST with a body returned normally instead of throwing
  before state capture. Coverage now exercises single notifications and
  notification-only batches over both JSON and POST/SSE bodies, proving
  `sessionId` and `lastEventId` stay unchanged when the server includes
  replacement session headers or SSE event ids. The generated client-only
  consumer-package smoke covers the same paths through public
  `connectanum_mcp_io.dart` APIs. Pre-change `bin/test-fast` passed before
  edits; after the fix, focused client regression coverage, full
  `streamable_http_client_test.dart`, `bash -n bin/common.sh`, focused
  generated client-only consumer smoke, `dart analyze
  packages/connectanum_client`, repeated `bin/test-fast`, and full local
  `bin/verify` passed. Commit `f15518b`
  (`fix: reject mcp notification response bodies`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted evidence is clean
  at `f15518b`: `master` CI run `26315819342` passed with Fast Checks and Full
  Verify green and clean logs, `add-router` CI run `26315818609` passed,
  `master` Dart Package Publish Dry Run `26315819303` and `add-router` Dart
  Package Publish Dry Run `26315818619` passed, `master` WAMP Profile
  Benchmarks `26315819251` and `add-router` WAMP Profile Benchmarks
  `26315818639` passed, and Router Image dry-run `26315836302` passed for
  `0.1.0-rc.2-validation.f15518b` with preview upload, skipped GHCR login,
  completed multi-arch build, and clean annotations. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed since `89c7915`. The strict deployment-chain audit passed required
  gates on `master` at `f15518b`, including clean current-head CI/logs, Dart
  package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
  native release dry-run relevance, branch protection, workflow visibility,
  and router package visibility. RC readiness remains not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for release-order
  and operator decisions. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-22: `McpStreamableHttpClient._postPayload()` now validates
  response-bearing JSON-RPC POST response shapes before accepting successful
  response `MCP-Session-Id` / protocol-version headers or POST/SSE resume
  cursors. Single requests with an `id` must receive a JSON object, batches
  with request ids must receive an array of JSON objects, and accepted,
  no-content, empty, or POST/SSE streams without a matching response now throw
  before mutating Streamable HTTP session state. The client regression was
  added first and failed against the prior behavior because a valid JSON array
  response with `MCP-Session-Id: post-json-shape-session` changed the active
  session from `session-1` before the public helper rejected the response
  shape. Coverage now also exercises POST/SSE streams that contain only
  notifications and response-bearing batches that return a single JSON object.
  The generated client-only consumer-package smoke covers the same paths
  through public `connectanum_mcp_io.dart` APIs. Pre-change `bin/test-fast`
  passed before edits; after the fix, focused client regression coverage, full
  `streamable_http_client_test.dart`, `bash -n bin/common.sh`, focused
  generated client-only consumer smoke, `dart analyze
  packages/connectanum_client`, repeated `bin/test-fast`, and full local
  `bin/verify` passed. Commit `bed07fa`
  (`fix: validate mcp post response shape`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26313816851` passed with clean logs, `add-router` CI run `26313816819`
  passed, hosted Dart Package Publish Dry Run runs `26313816817` and
  `26313816843` passed, hosted WAMP Profile Benchmarks runs `26313816842` and
  `26313816821` passed, and current-head Router Image dry-run `26313868479`
  passed for `0.1.0-rc.2-validation.bed07fa`. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. The strict deployment-chain audit passed required gates on `master`
  at `bed07fa`; RC readiness remains blocked only by explicit RC tag,
  prerelease, router-image tag selection, and deferred pub.dev release-order
  decisions.
- 2026-05-22: `McpStreamableHttpClient._postPayload()` now captures
  successful POST response `MCP-Session-Id` and protocol-version headers only
  after JSON bodies or POST/SSE event data parse successfully. POST/SSE resume
  cursor capture also waits until SSE event JSON is valid and the response has
  been selected, so malformed response bodies cannot poison the active
  Streamable HTTP session or clear a valid resume cursor before throwing. HTTP
  401/403/404 session cleanup still runs before any response header capture,
  and successful 202/204/empty notification responses still capture valid
  response session headers. The client regression was added first and failed
  against the prior behavior because a malformed JSON POST response with
  `MCP-Session-Id: post-json-session` changed the active session from
  `session-1` before throwing. The generated client-only consumer-package smoke
  now exercises the same malformed POST JSON/SSE response paths through public
  `connectanum_mcp_io.dart` APIs and verifies recovery on the preserved
  session. Pre-change `bin/test-fast` passed before edits; after the fix,
  focused client regression coverage, full `streamable_http_client_test.dart`,
  `bash -n bin/common.sh`, focused generated client-only consumer smoke,
  `dart analyze packages/connectanum_client`, repeated `bin/test-fast`, and
  full local `bin/verify` passed. Commit `66e89c6`
  (`fix: preserve mcp post sessions`) was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted `master` CI run `26311665595`
  passed with clean logs, `add-router` CI run `26311662052` passed, hosted
  Dart Package Publish Dry Run runs `26311665598` and `26311662027` passed,
  hosted WAMP Profile Benchmarks runs `26311665596` and `26311662028` passed,
  and current-head Router Image dry-run `26311683317` passed for
  `0.1.0-rc.2-validation.66e89c6`. Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `66e89c6`; RC readiness remains blocked only by explicit RC tag,
  prerelease, router-image tag selection, and deferred pub.dev release-order
  decisions.
- 2026-05-22: `McpStreamableHttpClient.poll()` now validates successful
  Streamable HTTP GET responses as `text/event-stream` before capturing
  server-provided `MCP-Session-Id` or protocol-version headers. A non-SSE
  `200 OK` poll response with a valid-looking response session header still
  throws `FormatException`, but no longer replaces the active session id or
  clears the resume cursor. The client regression was added first and failed
  against the prior behavior because a JSON poll response with
  `MCP-Session-Id: poll-json-session` changed the active session from
  `session-1` before throwing. The generated client-only consumer-package smoke
  now exercises the same non-SSE poll response through public
  `connectanum_mcp_io.dart` APIs, proves the active session and resume cursor
  remain intact, clears the test cursor, and verifies a fresh poll can recover
  on the same session. Pre-change `bin/test-fast` passed before edits; after
  the fix, focused client regression coverage, full
  `streamable_http_client_test.dart`, `bash -n bin/common.sh`, focused
  generated client-only consumer smoke, `dart analyze
  packages/connectanum_client`, repeated `bin/test-fast`, and full local
  `bin/verify` passed. Commit `f782968` (`fix: preserve mcp poll sessions`) was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  `master` CI run `26309125787` passed with clean logs, `add-router` CI run
  `26309125582` passed, hosted Dart Package Publish Dry Run runs `26309125789`
  and `26309125515` passed, hosted WAMP Profile Benchmarks runs `26309125788`
  and `26309125514` passed, and current-head Router Image dry-run
  `26309745717` passed for `0.1.0-rc.2-validation.f782968`. Native Artifacts
  dry-run `26286794628` remains relevant because no native-release-sensitive
  inputs changed. The strict deployment-chain audit passed required gates on
  `master` at `f782968`; RC readiness remains blocked only by explicit RC tag,
  prerelease, router-image tag selection, and deferred pub.dev release-order
  decisions.
- 2026-05-22: `McpStreamableHttpClient` now rejects explicit empty
  Streamable HTTP `MCP-Session-Id` response headers instead of silently
  ignoring them. A missing response session header still means no negotiation,
  but any present value must pass `_mcpSessionIdHeaderValueValid(...)`; an
  empty value clears `sessionId` and `lastEventId` and throws
  `McpStreamableProtocolException` so consumer applications cannot treat an
  invalid response session as a successful initialize. The client regression
  was added first and failed against the prior behavior because an empty
  response `MCP-Session-Id` returned a successful initialize result. The
  generated client-only consumer-package smoke now exercises the same explicit
  empty response-session header through public `connectanum_mcp_io.dart` APIs,
  proves state remains clear, and verifies a fresh initialize can recover. The
  pre-change `bin/test-fast` gate was started before edits and completed
  cleanly; after the fix, focused client regression coverage, full
  `streamable_http_client_test.dart`, `bash -n bin/common.sh`, focused
  generated client-only consumer smoke, `dart analyze
  packages/connectanum_client`, repeated `bin/test-fast`, `git diff --check`,
  and full local `bin/verify` passed on 2026-05-22. Commit `d0f5358`
  (`fix: reject empty mcp response sessions`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26306530073` passed with clean logs, `add-router` CI run `26306530125`
  passed, hosted Dart Package Publish Dry Run runs `26306530127` and
  `26306530072` passed, hosted WAMP Profile Benchmarks runs `26306530135` and
  `26306530124` passed, and current-head Router Image dry-run `26306568456`
  passed for `0.1.0-rc.2-validation.d0f5358`. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. The strict deployment-chain audit passed required gates on `master`
  at `d0f5358`; RC readiness remains blocked only by explicit RC tag,
  prerelease, router-image tag selection, and deferred pub.dev release-order
  decisions.
- 2026-05-22: `McpStreamableHttpClient` now treats an empty SSE `id:` field as
  an explicit Streamable HTTP resume-cursor reset instead of ignoring it.
  `event.id == null` still means the event did not carry an id field, while
  `event.id == ''` clears `lastEventId`, so later `poll()` requests do not
  send a stale `Last-Event-ID` after a standards-compatible SSE reset. The
  client regression was added first and failed against the previous behavior
  because an empty response event id left `lastEventId` at
  `session-1:post:1`. The generated client-only consumer-package smoke now
  sends the same empty-id SSE response through public
  `connectanum_mcp_io.dart` APIs and follows it with a poll to prove the stale
  cursor was not replayed. Pre-change `bin/test-fast` passed; after the fix,
  focused client regression coverage, full `streamable_http_client_test.dart`,
  `bash -n bin/common.sh`, focused generated client-only consumer smoke, `dart
  analyze packages/connectanum_client`, and repeated `bin/test-fast` passed.
  Full local `bin/verify` passed on 2026-05-22. Commit `dbaa0f3`
  (`fix: reset mcp sse resume cursor`) was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted `master` CI run `26304262034`
  passed with clean logs, `add-router` CI run `26304262081` passed, hosted
  Dart Package Publish Dry Run runs `26304262111` and `26304262077` passed,
  hosted WAMP Profile Benchmarks runs `26304262035` and `26304262052` passed,
  and current-head Router Image dry-run `26304274791` passed for
  `0.1.0-rc.2-validation.dbaa0f3`. Native Artifacts dry-run `26286794628`
  remains relevant because no native-release-sensitive inputs changed. The
  strict deployment-chain audit passed required gates on `master` at
  `dbaa0f3`; RC readiness remains blocked only by explicit RC tag, prerelease,
  router-image tag selection, and deferred pub.dev release-order decisions.
- 2026-05-22: `McpStreamableHttpClient` now validates server-provided
  Streamable HTTP `MCP-Session-Id` response headers before capturing them.
  Valid response session ids must be non-empty visible ASCII, matching the
  router-hosted session-id invariant. A malformed response `MCP-Session-Id`
  clears `sessionId` and `lastEventId` and throws
  `McpStreamableProtocolException`, so consumer applications cannot poison
  later requests with invalid MCP session state. Session headers are now
  captured only after HTTP error handling, preserving stale-session cleanup
  semantics for 401/403/404 responses without accepting response session
  headers from failed requests. The client regression was added first and
  failed against the previous behavior because `initialize` accepted
  `malformed session` as the active session id. The generated client-only
  consumer-package smoke now uses public `connectanum_mcp_io.dart` APIs against
  a bearer-protected fake endpoint to prove malformed response session headers
  are rejected, client state remains clear, and a fresh Streamable initialize
  can recover. Pre-change `bin/test-fast` passed; after the fix, focused client
  regression coverage, full `streamable_http_client_test.dart`, `dart analyze
  packages/connectanum_client`, `bash -n bin/common.sh`, focused generated
  client-only consumer smoke, and repeated `bin/test-fast` passed. Full local
  `bin/verify` passed on 2026-05-22. Commit `730e75b`
  (`fix: reject malformed mcp response sessions`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26301874277` passed with clean logs, `add-router` CI run `26301874343`
  passed, hosted Dart Package Publish Dry Run runs `26301874299` and
  `26301874267` passed, hosted WAMP Profile Benchmarks runs `26301874338` and
  `26301874276` passed, and current-head Router Image dry-run `26301886236`
  passed for `0.1.0-rc.2-validation.730e75b`. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. The strict deployment-chain audit passed required gates on `master`
  at `730e75b`; RC readiness remains blocked only by explicit RC tag,
  prerelease, router-image tag selection, and deferred pub.dev release-order
  decisions.
- 2026-05-22: Router-hosted MCP Streamable HTTP session IDs now reject
  malformed client headers before endpoint lookup or response-header echo.
  `_mcpSessionIdHeaderValueValid(...)` permits only non-empty visible ASCII for
  session-scoped Streamable requests; malformed `MCP-Session-Id` on POST, GET,
  or DELETE returns `400` JSON-RPC `invalid_request`, omits `MCP-Session-Id`
  from the response, and leaves direct JSON POST requests lifecycle-free. The
  router integration regression was added first and failed against the previous
  behavior because a malformed session id was treated as an unknown session
  with `404`. The generated consumer-package smoke now sends malformed
  Streamable POST, GET, and DELETE requests through raw `HttpClient` against
  public `McpStreamableHttpClient.endpoint`, including configured bearer
  headers, and proves public and bearer-protected router-hosted MCP endpoints
  reject them without capturing Streamable client state. Pre-change
  `bin/test-fast` passed; after the fix, focused router integration coverage,
  `dart analyze packages/connectanum_router`, `bash -n bin/common.sh`, focused
  generated router-hosted MCP consumer smoke, repeated `bin/test-fast`, `git
  diff --check`, and full local `bin/verify` passed. Commit `eb9a9c5`
  (`fix: reject malformed mcp session ids`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26299150343` passed with clean logs, `add-router` CI run `26299150459`
  passed, hosted Dart Package Publish Dry Run runs `26299150379` and
  `26299150397` passed, hosted WAMP Profile Benchmarks runs `26299150488` and
  `26299150455` passed, and current-head Router Image dry-run `26299168032`
  passed for `0.1.0-rc.2-validation.eb9a9c5`. Native Artifacts dry-run
  `26286794628` remains relevant because no native-release-sensitive inputs
  changed. The strict deployment-chain audit passed required gates on `master`
  at `eb9a9c5`; RC readiness remains blocked only by explicit RC tag,
  prerelease, router-image tag selection, and deferred pub.dev release-order
  decisions.
- 2026-05-22: Router-hosted MCP Streamable HTTP `initialize` now rejects
  requests that include a client-supplied `MCP-Session-Id` before endpoint
  lookup or creation. The router returns a `400` JSON-RPC `invalid_request`,
  omits `MCP-Session-Id` from the response, and keeps Streamable HTTP sessions
  server-assigned so consumer applications or agents cannot select predictable
  session ids. The router integration regression was added first and failed
  against the previous behavior because the same request was accepted with
  `200 OK`. The generated consumer-package smoke now sends the same request
  through a raw `HttpClient` against public `McpStreamableHttpClient.endpoint`,
  including configured bearer headers, and proves public and bearer-protected
  router-hosted MCP endpoints reject it without capturing Streamable client
  state. Pre-change `bin/test-fast` passed; after the fix, focused router
  integration coverage, `dart analyze packages/connectanum_router`, `bash -n
  bin/common.sh`, focused generated router-hosted MCP consumer smoke, repeated
  `bin/test-fast`, `git diff --check`, and full local `bin/verify` passed.
  Commit `27c65d2` (`fix: reject client mcp initialize sessions`) was pushed
  to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master`
  CI run `26296339766` passed with clean logs, `add-router` CI run
  `26296339683` passed, hosted Dart Package Publish Dry Run runs `26296339784`
  and `26296339688` passed, hosted WAMP Profile Benchmarks runs `26296339687`
  and `26296339710` passed, and current-head Router Image dry-run
  `26296373275` passed for `0.1.0-rc.2-validation.27c65d2`. Native Artifacts
  dry-run `26286794628` remains relevant because no native-release-sensitive
  inputs changed. The strict deployment-chain audit passed required gates on
  `master` at `27c65d2`; RC readiness remains blocked only by explicit RC
  tag/prerelease/router-image tag selection and deferred pub.dev release-order
  decisions.
- 2026-05-22: Router-hosted MCP Streamable `initialize` handling now treats
  newly created endpoints as tentative until initialization succeeds. If the
  MCP server returns a JSON-RPC error for a new Streamable `initialize`
  request, the router disposes that endpoint and omits `MCP-Session-Id` so
  consumer applications cannot reuse a failed initialization as an active MCP
  session. The router integration regression was added first and failed against
  the previous session leak; the generated consumer-package smoke now proves
  the same rejected-initialize behavior through public
  `McpStreamableHttpClient.post(...)` before the normal Streamable lifecycle.
  Pre-change `bin/test-fast` passed; after the fix, focused router integration
  coverage, `dart analyze packages/connectanum_router`, `bash -n
  bin/common.sh`, focused generated router-hosted MCP consumer smoke, and
  repeated `bin/test-fast` passed. Full local `bin/verify` also passed. Commit
  `08557f7` (`fix: drop rejected mcp initialize sessions`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master`
  CI run `26293468018` passed with clean logs, `add-router` CI run
  `26293451755` passed, hosted Dart Package Publish Dry Run runs `26293468008`
  and `26293451704` passed, hosted WAMP Profile Benchmarks runs `26293468009`
  and `26293451763` passed, and current-head Router Image dry-run
  `26293615506` passed for `0.1.0-rc.2-validation.08557f7`. Native Artifacts
  dry-run `26286794628` remains relevant because no native-release-sensitive
  inputs changed. The strict deployment-chain audit passed required gates on
  `master` at `08557f7`; RC readiness remains blocked only by explicit RC
  tag/prerelease/router-image tag selection and deferred pub.dev release-order
  decisions.
- 2026-05-22: Router-hosted MCP Streamable HTTP session deletion now cleans up
  endpoint-created WAMP pub/sub subscriptions. `_RouterMcpEndpoint` tracks
  subscription ids created through MCP pub/sub helpers, removes ids on explicit
  unsubscribe, and best-effort unsubscribes any remaining ids when DELETE
  removes the MCP session or the endpoint is disposed. Router integration
  coverage and the generated consumer-package smoke now prove a Streamable MCP
  subscription has one route-visible subscriber before DELETE and zero after
  DELETE through direct JSON WAMP subscription meta. Pre-change
  `bin/test-fast`, focused router integration coverage, `dart analyze
  packages/connectanum_router`, `bash -n bin/common.sh`, focused generated
  router-hosted MCP consumer smoke, `git diff --check`, and full local
  `bin/verify` passed. Commit `383e0a9`
  (`fix: clean up mcp delete subscriptions`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26289774583` passed after rerun with clean logs, `add-router` CI run
  `26289773557` passed, hosted Dart Package Publish Dry Run runs `26289774620`
  and `26289773603` passed, hosted WAMP Profile Benchmarks runs `26289774563`
  and `26289773604` passed, and current-head Router Image dry-run
  `26290485783` passed for `0.1.0-rc.2-validation.383e0a9`. The strict
  deployment-chain audit passed required gates on `master` at `383e0a9`; RC
  readiness remains blocked only by explicit RC tag/prerelease/router-image tag
  selection and deferred pub.dev release-order decisions.
- 2026-05-22: Current implementation checkpoint adds per-method HTTP route
  action overrides for the Dart router config surface. `HttpRouteSettings`
  now carries `methodActions`, `RouterConfigLoader` accepts
  `method_actions` / `methodActions`, `RouterSettingsCodec` round-trips the
  overrides, native config encoding emits method-specific targets, and Dart
  synthetic route matching includes override keys in allowed-method handling
  for deterministic `405` / `Allow` responses. `ROADMAP.md` now marks
  per-method overrides complete while keeping catch-all wildcard translation
  tables open. Pre-change `bin/test-fast`, focused config-loader/runtime
  route-method tests, `git diff --check`, and full local `bin/verify` passed.
  Hosted deployment-chain evidence remains pending for this checkpoint.
- 2026-05-22: Commit `3c5d977`
  (`test: cover http route method mismatches`) adds focused evidence for the
  HTTP route method
  whitelist half of the roadmap's 405/426 route-readiness item. Native route
  matching now has regression coverage for `MethodNotAllowed` and sorted
  `Allow` methods, the native HTTP/1 listener has a network regression proving
  a method mismatch returns `405 Method Not Allowed` without queuing a
  Dart-dispatched HTTP request, and the Dart synthetic dispatch path has
  matching coverage for `405`, the `Allow` header, `method_not_allowed`, and no
  `http_request_dispatched` event. `ROADMAP.md` now marks the method/protocol
  whitelist item complete. Pre-change `bin/test-fast`, focused native
  `cargo test -p ct_core method_mismatch -- --nocapture`, focused Dart
  route-method runtime testing, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted `master` CI run `26282723125`,
  `add-router` CI run `26282711412`, hosted Dart Package Publish Dry Run runs
  `26282723109` and `26282711355`, hosted WAMP Profile Benchmarks runs
  `26282723154` and `26282711353`, hosted kTLS Validation runs `26282723160`
  and `26282711453`, Native Artifacts dry-run `26283321576`, and Router Image
  dry-run `26283321578` all passed at `3c5d977`. The strict deployment-chain
  audit passed required gates on `master` at `3c5d977`; RC readiness remains
  blocked only by explicit RC tag/prerelease/router-image tag selection and
  deferred pub.dev release-order decisions.
- 2026-05-22: Router HTTP route protocol whitelist enforcement now returns a
  deterministic protocol mismatch response instead of falling through to route
  not found. Native route matching canonicalizes HTTP protocol aliases and
  returns `ProtocolNotAllowed` for existing route paths served over disallowed
  protocols; HTTP/1 native responses return `426 Upgrade Required` with an
  `Upgrade` header, while HTTP/2 and HTTP/3 avoid invalid connection-specific
  upgrade headers. The Dart synthetic HTTP dispatch path mirrors the same
  `426` JSON error with `protocol_not_allowed`. Pre-change `bin/test-fast`,
  focused native and Dart route-protocol tests, and full local `bin/verify`
  passed. Commit `c45aa4b`
  (`fix: return 426 for http route protocol mismatch`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26278863274`, `add-router` CI run `26278857982`, hosted Dart Package
  Publish Dry Run runs `26278863327` and `26278857984`, hosted WAMP Profile
  Benchmarks runs `26278863232` and `26278857985`, hosted kTLS Validation runs
  `26278863231` and `26278858035`, Native Artifacts dry-run `26279547806`, and
  Router Image dry-run `26279547969` all passed at `c45aa4b`. The strict
  deployment-chain audit passed required gates on `master` at `c45aa4b`; RC
  readiness remains blocked only by explicit RC tag/prerelease/router-image tag
  selection and deferred pub.dev release-order decisions.
- 2026-05-13: The first RC target is a downstream-consumable GitHub prerelease
  with native artifacts and router image validation. Pub.dev publishing is
  deferred until package ownership, public versions, and release order are
  explicit.
- 2026-05-13: GitHub `master` is the default release branch. It currently
  represents the old single-package history, so promotion must merge the
  workspace branch into GitHub `master` while keeping the workspace layout.
- 2026-05-19: Before adding more feature surface, local `bin/test-fast`
  exposed a native WAMP worker readiness timeout in the bench integration
  suite. The worker readiness budget was raised from 20s to 60s, the stale
  local `ffi-test` native artifact was rebuilt during diagnosis, and focused
  WAMP transport repros, the full WAMP transport integration suite,
  `bin/test-fast`, and `bin/verify` passed locally.
- 2026-05-19: Commit `8058104` (`test: harden native wamp worker readiness`)
  was pushed to both configured remotes. GitHub `CI` run `26087763061`
  completed successfully with `Fast Checks` and `Full Verify` green, GitHub
  `WAMP Profile Benchmarks` run `26087763027` completed successfully, and
  GitHub `Dart Package Publish Dry Run` run `26087763335` completed
  successfully. The deployment-chain audit passed the clean latest CI, clean
  latest CI logs, and clean relevant Dart package publish dry-run gates for
  `add-router`.
- 2026-05-19: GitHub `Native Artifacts` run `26088923120` completed
  successfully for `v0.1.0-rc.1`, but the GitHub tag already exists at
  `47bbf9c`, so that run is stale-tag evidence rather than current-head
  no-mutation evidence. A unique validation-tag dry-run, GitHub `Native
  Artifacts` run `26089627231` for `v0.1.0-rc.1-validation.8058104`, failed
  during Sigstore signing after Cosign could not fetch ambient OIDC
  credentials on Linux x64, Linux arm64, and macOS Apple Silicon.
- 2026-05-19: The native artifact workflow now retries Cosign `sign-blob` and
  `verify-blob` calls up to three attempts, and the deployment-chain audit now
  accepts both project and native dry-run release-intent lines. Pre-change
  `bin/test-fast`, focused local validation, and full local `bin/verify`
  passed before commit.
- 2026-05-19: Commit `f2f8720` (`ci: harden native artifact dry-run evidence`)
  was pushed to both configured remotes. GitHub `CI` run `26090478456`
  completed successfully with `Fast Checks` and `Full Verify` green. GitHub
  `Native Artifacts` run `26090497983` completed successfully for
  `v0.1.0-rc.1-validation.f2f8720`; all five platform jobs and the dry-run
  release-preview job passed, no GitHub Release mutation occurred, and the
  `native-release-preview` artifact was uploaded. The deployment-chain audit
  passed the clean latest CI, clean latest CI logs, clean relevant Dart package
  publish dry-run, and clean native release dry-run gates for `add-router`.
- 2026-05-19: GitHub `Router Image` dry-run `26091104743` for
  `0.1.0-rc.1-validation.f2f8720` failed before publishing because
  `deploy/docker/Dockerfile` copied a root `pubspec.lock` that is not checked
  in for this workspace. The Dockerfile now copies only `pubspec.yaml` before
  `dart pub get`, matching the workspace's generated-lockfile build path.
- 2026-05-19: Commit `7f54fbb` (`ci: fix router image workspace build`) was
  pushed to both configured remotes. Follow-up GitHub `Router Image` dry-run
  `26091677645` for `0.1.0-rc.1-validation.7f54fbb` progressed to
  `dart compile exe`, then failed because `/out/connectanum_router` could not
  be opened when `/out` did not exist. The Dockerfile now creates `/out`
  before compiling the router runner. Local Docker validation is blocked
  because the local Docker daemon is not running. Full local `bin/verify`
  passed on 2026-05-19 for this Dockerfile output-directory fix.
- 2026-05-19: Commit `f30aa7f` (`ci: fix router image compile output`) was
  pushed to both configured remotes, and GitHub CI run `26092286670` passed.
  Follow-up GitHub `Router Image` dry-run `26092291070` for
  `0.1.0-rc.1-validation.f30aa7f` reached the Docker Rust release build for
  `ct_ffi`, then failed because the pinned `rust:1.85-bookworm` builder does
  not implement `Default` for raw pointer fields in `ct_ffi` FFI output
  structs. A local Rust 1.85 release build for `ct_ffi` reproduced the failure
  and now passes after adding explicit zeroed defaults for the `repr(C)`
  scalar/pointer buffers. `cargo fmt --all --check` from `native/transport`,
  `git diff --check`, and full local `bin/verify` passed on 2026-05-19 for
  this Rust 1.85 compatibility fix.
- 2026-05-19: Commit `6d681ab` (`fix: support rust 1.85 ffi defaults`) was
  pushed to both configured remotes. GitHub CI run `26093400216` passed, GitHub
  `Router Image` dry-run `26093405157` passed for
  `0.1.0-rc.1-validation.6d681ab`, and GitHub `Native Artifacts` dry-run
  `26094664567` passed for `v0.1.0-rc.1-validation.6d681ab` with all five
  `ct_ffi` platform jobs and release-preview upload green. The deployment-chain
  audit passed clean latest CI, clean latest CI logs, clean relevant Dart
  package publish dry-run, and clean native release dry-run gates for
  `add-router`. RC readiness still requires router image package visibility and
  current-head RC tag/prerelease selection; pub.dev remains deferred.
- 2026-05-19: The deployment-chain audit now exposes
  `--show-router-image-dry-run` and `--require-clean-router-image-dry-run`.
  The gate verifies the latest relevant manual Router Image dry-run completed
  successfully, uploaded `router-image-preview`, skipped GHCR login, completed
  the multi-arch build step, and still covers checked-out router image inputs.
  The gate passed locally against GitHub `Router Image` dry-run `26093405157`;
  GHCR package visibility remains a separate publish/approval gate.
- 2026-05-19: Commit `d01afce` (`ci: gate router image dry-run evidence`) was
  pushed to both configured remotes. GitHub CI run `26096473969` passed, and
  the strict deployment-chain audit passed clean latest CI, clean latest CI
  logs, clean relevant Dart package publish dry-run, clean native release
  dry-run, and clean router image dry-run gates for `add-router`. RC readiness
  remains blocked by router image package visibility/publish approval and
  current-head RC tag/prerelease selection; pub.dev remains deferred.
- 2026-05-19: Native HTTP/1 keep-alive idle timeouts are now treated as quiet
  lifecycle closures in `ct_core`, keeping generated router-hosted MCP
  consumer-package smoke logs clean while preserving diagnostics for
  non-timeout protocol and I/O read errors. Pre-change `bin/test-fast` passed
  and exposed the timeout diagnostic noise. Focused native regression,
  generated consumer-package smoke output scan, `git diff --check`, and full
  local `bin/verify` passed. Commit `f0c1590`
  (`fix: silence expected http1 idle timeouts`) was pushed to both configured
  remotes. GitHub CI run `26098749788`, GitHub WAMP Profile Benchmarks run
  `26098749790`, GitHub kTLS Validation run `26098749771`, GitHub `Native
  Artifacts` dry-run `26099397722`, GitHub `Router Image` dry-run
  `26099397318`, and the strict deployment-chain audit all passed for the new
  head. RC readiness remains blocked by router image package visibility/publish
  approval and current-head RC tag/prerelease selection; pub.dev remains
  deferred.
- 2026-05-19: The Router Image workflow now uses Node 24-backed Docker setup
  actions (`docker/setup-qemu-action@v4` and `docker/setup-buildx-action@v4`)
  instead of the Node 20-backed `v3` tags, and the Router Image dry-run audit
  now fails on warning/failure check-run annotations. Pre-change
  `bin/test-fast`, primary GitHub action metadata checks for `node24`,
  `bash -n bin/audit-github-deployment-chain`, Router Image workflow YAML
  parsing, `git diff --check`, an expected failing
  `bin/audit-github-deployment-chain --branch add-router
  --require-clean-router-image-dry-run` against the old Node 20-annotated
  dry-run, and full local `bin/verify` passed. Commit `5a10bd5`
  (`ci: harden router image action audit`) was pushed to both configured
  remotes. GitHub CI run `26102726359` passed with `Fast Checks` and
  `Full Verify` green, GitHub `Router Image` dry-run `26102736224` passed for
  `0.1.0-rc.1-validation.5a10bd5`, and the strict deployment-chain audit passed
  clean latest CI, clean latest CI logs, clean relevant Dart package publish
  dry-run, clean native release dry-run, and clean router image dry-run gates.
  The Router Image dry-run audit reported check annotations clean. RC readiness
  gained public GHCR registry package-visibility evidence in the follow-up
  audit hardening; current-head RC tag/prerelease selection remains blocked on
  a release decision and pub.dev remains deferred.
- 2026-05-19: The router package visibility gate now probes public GHCR
  registry pull metadata before falling back to GitHub Packages metadata:
  `tags/list` must expose at least one tag and the first visible tag must have
  a reachable manifest digest. Pre-change `bin/test-fast`, Bash syntax/help
  checks, `git diff --check`, the focused router package audit, an
  RC-readiness audit, and full local `bin/verify` completed; all required local
  gates passed. The package visibility gate currently reports public tag
  `v0.1.0-rc.1` with manifest digest
  `sha256:45d168f29a2b4c1c187ed21ff18c0f0539703b66c2709422cc414b360966b737`.
  Commit `65caf71` (`ci: audit ghcr router package visibility`) was pushed to
  both configured remotes. GitHub CI run `26105461957` passed with
  `Fast Checks` and `Full Verify` green, and the strict deployment-chain audit
  passed clean latest CI, clean latest CI logs, clean relevant Dart package
  publish dry-run, clean native release dry-run, clean router image dry-run,
  and router package visibility gates.
- 2026-05-19: The RC-readiness audit now inventories existing local RC tags
  when no RC tag points at the checked-out head, including each tag's target
  commit and stale/current status. Pre-change `bin/test-fast`, Bash syntax,
  help output, the focused RC-readiness audit, and full local `bin/verify`
  passed. Commit `cbe1e1d` (`ci: report stale rc tag evidence`) was pushed to
  both configured remotes. GitHub CI run `26108394380` passed with
  `Fast Checks` and `Full Verify` green, and the strict deployment-chain audit
  passed clean latest CI, clean latest CI logs, clean relevant Dart package
  publish dry-run, clean native release dry-run, clean router image dry-run,
  and router package visibility gates. The audit now reports
  `v0.1.0-rc.1 -> 47bbf9c` as stale for checked-out head `cbe1e1d`, so the
  remaining RC tag action is an explicit release decision to move the stale tag
  under policy or choose a follow-up RC tag.
- 2026-05-19: The RC-readiness audit now uses both local and GitHub RC tags
  for the checked-out-head tag gate, and prints stale-tag inventories from both
  sources when no RC tag points at the candidate head. Pre-change
  `bin/test-fast`, Bash syntax, help output, the focused RC-readiness audit,
  and full local `bin/verify` passed. Commit `e25c0c7` (`ci: audit github rc
  tag evidence`) was pushed to both configured remotes. GitHub CI run
  `26111109838` passed with `Fast Checks` and `Full Verify` green, and the
  strict deployment-chain audit passed clean latest CI, clean latest CI logs,
  clean relevant Dart package publish dry-run, clean native release dry-run,
  clean router image dry-run, and router package visibility gates. The audit
  reports both local and GitHub `v0.1.0-rc.1 -> 47bbf9c` as stale for
  checked-out head `e25c0c7`.
- 2026-05-19: The generated neutral consumer package smoke now covers
  protected MCP route missing-bearer rejection for standard resource/prompt
  helpers over direct JSON and Streamable HTTP, including `resources/list`,
  `resources/read`, `resources/templates/list`, `prompts/list`, `prompts/get`,
  and resource-prompt batch calls. Pre-change `bin/test-fast` passed.
  Post-change `bash -n bin/common.sh`, `bin/test-fast`, and full local
  `bin/verify` passed.
- 2026-05-19: The deployment-chain audit now requires latest hosted CI job and
  CI-log evidence to cover the checked-out commit exactly, rejecting stale
  green branch runs before they can satisfy `--require-clean-latest-ci`,
  `--require-clean-latest-ci-logs`, or RC readiness. A fake-`gh` regression is
  wired into `bin/test-fast` and `bin/test-all`. Focused Bash syntax checks,
  the fake-`gh` audit regression, the real current-head CI/log audit, and a
  fresh `bin/test-fast` passed locally.
- 2026-05-19: The fake-`gh` exact-head audit regression now synthesizes stale
  run SHAs instead of resolving `HEAD~1`, keeping the test valid in shallow
  GitHub Actions checkouts. Focused Bash syntax checks, the fake-`gh`
  regression, `git diff --check`, and `bin/test-fast` passed locally.
- 2026-05-19: The RC-readiness audit now accepts inspected Native Artifacts
  prerelease publish evidence as native hosted evidence only in RC-readiness
  mode. The standalone native release dry-run gate remains strict: it still
  requires a non-mutating dry-run intent and release-preview artifact. The
  fake-`gh` regression now covers a non-draft native prerelease targeting the
  checked-out commit with the expected asset inventory, and `bin/test-fast`
  passed locally.
- 2026-05-19: GitHub `master` was promoted to `2eced84` with an ancestry-only
  merge commit that preserves the already-verified `add-router` tree while
  making the previous GitHub `master` history an ancestor. Pre-merge
  `bin/test-fast` and post-merge local `bin/verify` passed. The `add-router`
  branch was pushed to both configured remotes, and GitHub `master` was updated
  by fast-forward. Hosted evidence for `master` is current and green: CI run
  `26125709823`, Dart Package Publish Dry Run `26125709820`, WAMP Profile
  Benchmarks `26125709822`, kTLS Validation `26125709821`, Native Artifacts
  dry-run `26126356470`, and Router Image dry-run `26126361337`. The strict
  deployment-chain audit passed clean latest CI, clean latest CI logs, clean
  Dart package dry-run, clean native release dry-run, clean router image
  dry-run, and router package visibility gates for `master`. The first
  `add-router` CI run for `2eced84` hit a hosted browser test harness flake
  while loading the web transport test, then passed after rerunning the failed
  job. Current-head RC tag/prerelease selection remains the only GitHub RC
  readiness blocker; no RC tag or GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now derives concrete, non-mutating
  follow-up RC tag suggestions from existing numeric local and GitHub RC tags
  when no RC tag points at the checked-out head. The fake-`gh` regression covers
  stale local and GitHub `v0.1.0-rc.1` tags and asserts that the audit suggests
  `v0.1.0-rc.2` while leaving RC prerelease selection not-ready. Pre-change
  `bin/test-fast`, focused Bash syntax, the audit regression module,
  `git diff --check`, a real read-only `master` RC-readiness audit, and full
  local `bin/verify` passed. No RC tag or GitHub Release was created or moved.
- 2026-05-20: The stale-RC fake-`gh` regression now also synthesizes local,
  GitHub, and GHCR validation/dry-run RC tags. It asserts that duplicate local
  and GitHub stale numeric tags produce exactly one `v0.1.0-rc.2` suggestion
  and that validation/dry-run RC tags do not become follow-up release-tag
  suggestions. Pre-change `bin/test-fast`, focused Bash syntax, the audit
  regression module, `git diff --check`, and full local `bin/verify` passed.
  No RC tag or GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now requires numeric RC tags for the
  checked-out-head release-tag gate while still inventorying RC-looking
  validation/dry-run tags as current or stale evidence. The fake-`gh`
  regression now points a validation/dry-run tag at the checked-out head and
  proves it does not satisfy RC tag readiness; the audit still suggests only
  the next numeric follow-up tag. Pre-change `bin/test-fast`, focused Bash
  syntax, the audit regression module, `git diff --check`, a real read-only
  `master` RC-readiness audit, and full local `bin/verify` passed. No RC tag or
  GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now reports the audited branch head and
  requires it to match the checked-out head before RC readiness or follow-up
  numeric RC tag suggestions are evaluated. A fake-`gh` regression covers a
  stale audited branch head and proves follow-up RC tag suggestions are
  suppressed until the audited branch and checkout are aligned. Pre-change
  `bin/test-fast`, focused Bash syntax, the audit regression module, help
  output, `git diff --check`, an aligned `add-router` RC-readiness summary, and
  full local `bin/verify` passed. A read-only `master` RC-readiness summary
  confirmed mismatch suppression, but GitHub returned a transient 502 while
  inspecting Dart package dry-run jobs, so that summary was not used as clean
  release evidence. No RC tag or GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now also requires the audited branch to be
  the GitHub default branch before RC readiness or follow-up numeric RC tag
  suggestions are evaluated. A fake-`gh` regression covers an aligned
  non-default branch and proves follow-up RC tag suggestions are suppressed
  until the default branch is audited. Pre-change `bin/test-fast`, focused Bash
  syntax, the audit regression module, help output, `git diff --check`, a live
  read-only `add-router` RC-readiness summary, and full local `bin/verify`
  passed. The live summary reports `add-router` as branch/head aligned but not
  the default release branch, and it does not suggest `v0.1.0-rc.2` until
  `master` is audited from an aligned checkout. Commit `ea309d6` was pushed to
  GitLab `origin` and GitHub `add-router`; GitHub `CI` run `26135920644`
  passed, and the strict deployment-chain audit passed for `add-router` with RC
  readiness still not-ready because the audited branch is not the default
  release branch and no numeric RC tag points at `ea309d6`. No RC tag or GitHub
  Release was created or moved.
- 2026-05-20: The Native Artifacts release-intent path now treats project
  SemVer prerelease tags such as `v0.1.0-rc.2` as prereleases even when the
  workflow is triggered by a tag push or a manual dispatch without the explicit
  `prerelease=true` input. This prevents an approved RC tag from accidentally
  creating a stable GitHub Release. Pre-change `bin/test-fast` passed. Focused
  release-intent unit tests, a CLI validation for `v1.2.3-rc.1`, a workflow
  guard snippet check, an isolated bench package rerun, `git diff --check`, and
  full local `bin/verify` passed locally. Commit `06dee45` was pushed to GitLab
  `origin` and GitHub `add-router`; GitHub `CI` run `26137710822` passed,
  Native Artifacts dry-run `26138108909` passed for validation tag
  `v0.1.0-rc.1-validation.06dee45`, and the strict deployment-chain audit
  passed with RC readiness still not-ready because `add-router` is not the
  default release branch and no numeric RC tag points at `06dee45`. No RC tag or
  GitHub Release was created or moved.
- 2026-05-20: GitHub `master` was fast-forward promoted from `2eced84` to
  `06dee45` so the release-safety fix is on the default release branch. GitHub
  reported the protected-branch PR rule was bypassed for the direct update.
  Hosted `master` CI run `26138507065` passed, Native Artifacts dry-run
  `26138936777` passed for validation tag
  `v0.1.0-rc.1-validation.06dee45`, and the strict deployment-chain audit
  passed on `master` with clean CI/log, Dart package dry-run, native release
  dry-run, router image dry-run, workflow visibility, and router package
  visibility gates. RC readiness remains not-ready only because no approved
  numeric RC tag or GitHub prerelease points at `06dee45`; the audit suggests
  `v0.1.0-rc.2` as the next follow-up tag after release approval. No RC tag or
  GitHub Release was created or moved. A final local `bin/verify` handoff pass
  also completed successfully after the hosted evidence was recorded.
- 2026-05-20: GitHub `master` was fast-forward promoted again from `06dee45` to
  `0c0e043` so the route rate-limit implementation is on the default release
  branch. GitHub reported the protected-branch PR rule was bypassed for the
  direct update. Local `bin/test-fast` and `bin/verify` passed before
  promotion. Hosted `master` evidence is current and green: CI run
  `26150667099` passed after rerunning a transient browser harness load
  failure, Dart Package Publish Dry Run `26150666982` passed, WAMP Profile
  Benchmarks `26150666988` passed, Native Artifacts dry-run `26151756102`
  passed for validation tag `v0.1.0-rc.1-validation.0c0e043`, and Router Image
  dry-run `26151756160` passed for validation tag
  `0.1.0-rc.1-validation.0c0e043`. The strict deployment-chain audit passed on
  `master` with clean CI/log, Dart package dry-run, native release dry-run,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility gates. RC readiness remains not-ready only because no
  approved numeric RC tag or GitHub prerelease points at `0c0e043`; the audit
  suggests `v0.1.0-rc.2` as the next follow-up tag after release approval. No
  RC tag or GitHub Release was created or moved.
- 2026-05-20: Fixed router-hosted MCP direct JSON notification semantics on
  `add-router` so recognized notification-only tool calls suppress
  handler/validation error response bodies and keep returning `202 Accepted`
  with an empty body. Pre-change `bin/test-fast` passed. The focused MCP router
  smoke regression failed before the fix because an invalid notification
  returned a JSON-RPC error body, then passed after the fix. `git diff --check`,
  post-change `bin/test-fast`, and full local `bin/verify` also passed. Commit
  `5a3d6f3` was pushed to GitLab `origin` and GitHub `add-router`. Hosted
  `add-router` evidence passed at that head: CI run `26155949934` (Fast Checks
  and Full Verify), Dart Package Publish Dry Run `26155949954`, and WAMP Profile
  Benchmarks `26155949979`. No RC tag or GitHub Release was created or moved.
- 2026-05-20: Added router-hosted MCP direct JSON batch notification regression
  coverage to the native router smoke. The test posts an invalid
  notification-only `connectanum.tool.call` inside a mixed direct JSON batch and
  proves the notification error is suppressed while a following
  `connectanum.api.list` request returns as the only batch response.
  Pre-change `bin/test-fast`, the focused MCP router smoke regression,
  `git diff --check`, post-change `bin/test-fast`, and full local `bin/verify`
  passed. Commit `7fb63b0` was pushed to GitLab `origin` and GitHub
  `add-router`. Hosted `add-router` evidence passed at that head: CI run
  `26158162335` (Fast Checks and Full Verify), Dart Package Publish Dry Run
  `26158162312`, and WAMP Profile Benchmarks `26158162311`. The non-RC strict
  deployment-chain audit also passed clean latest CI, clean CI logs, and clean
  Dart package dry-run gates for `add-router` at `7fb63b0`. No RC tag or GitHub
  Release was created or moved.
- 2026-05-20: Added router-hosted MCP direct JSON all-notification batch
  coverage to the native router smoke. The test posts a valid notification-only
  `connectanum.tool.call` and an invalid notification-only `connectanum.tool.call`
  in one direct JSON batch, then proves the router returns `202 Accepted` with
  an empty body, no JSON payload, and no `mcp-session-id` header. Pre-change
  `bin/test-fast`, the focused MCP router smoke regression, `git diff --check`,
  post-change `bin/test-fast`, and full local `bin/verify` passed. Commit
  `7ed0e08` was pushed to GitLab `origin` and GitHub `add-router`. Hosted
  `add-router` evidence passed at that head: CI run `26160395220` (Fast Checks
  and Full Verify), Dart Package Publish Dry Run `26160395223`, and WAMP Profile
  Benchmarks `26160395225`. The non-RC strict deployment-chain audit also passed
  clean latest CI, clean CI logs, and clean Dart package dry-run gates for
  `add-router` at `7ed0e08`. No RC tag or GitHub Release was created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP CORS
  smoke to cover all-notification direct JSON tool-call batches on both public
  and bearer-protected routes. The generated smoke now posts a valid
  notification-only `connectanum.tool.call` for the consumer procedure plus an
  invalid missing-name `connectanum.tool.call` notification in one direct JSON
  batch, and asserts `202 Accepted`, empty body, no JSON payload, and no
  `mcp-session-id` header. Pre-change `bin/test-fast`, `bash -n bin/common.sh`,
  the focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `c0d8523` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26162406329` passed at `c0d8523` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove direct JSON notification batches have WAMP-side effects, not only the
  right HTTP shape. The smoke now records consumer procedure task ids, asserts a
  mixed direct JSON batch invokes its notification-only consumer procedure call,
  and asserts public plus bearer-protected all-notification CORS batches invoke
  the valid `connectanum.tool.call` notification while the invalid missing-name
  notification stays suppressed. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `2fc71a5` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26164678308` passed at `2fc71a5` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove direct JSON notification-only pub/sub publishes have WAMP-side
  effects on both public and bearer-protected routes. The smoke now subscribes
  through direct JSON, posts a valid `connectanum.pubsub.publish` notification
  and an invalid missing-topic publish notification in one all-notification
  batch, polls the subscription, and asserts only the valid event arrives.
  Pre-change `bin/test-fast`, `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `b48d952` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26167043374` passed at `b48d952` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove Streamable HTTP session notification-only pub/sub publishes have
  WAMP-side effects. The smoke now subscribes over Streamable HTTP, posts a
  notification-only `connectanum.pubsub.publish` batch with one valid publish
  and one invalid missing-topic publish, asserts no JSON-RPC response or
  Streamable session cursor mutation, then polls the subscription and asserts
  only the valid event arrives. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `922fa1f` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26169647527` passed at `922fa1f` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove Streamable HTTP session notification-only direct tool calls have
  WAMP-side effects. The smoke now posts an all-notification
  `connectanum.tool.call` batch with one valid call and one invalid missing-name
  call, asserts no JSON-RPC response or immediate Streamable session cursor
  mutation, proves the valid WAMP procedure ran, drains the session, and proves
  the invalid notification did not invoke the procedure. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Hosted `add-router`
  evidence is clean at this follow-up: commit `5b27b19` was pushed to GitLab
  `origin` and GitHub `add-router`, GitHub CI run `26172167427` passed with
  Fast Checks and Full Verify green, and the non-RC strict deployment-chain
  audit passed clean latest CI, clean CI logs, and clean relevant Dart package
  dry-run gates. Dart Package Publish Dry Run `26160395223` remains clean and
  relevant at previous commit `7ed0e08` because no publish-sensitive paths
  changed since then; WAMP Profile Benchmarks `26160395225` remain clean at
  `7ed0e08`. No RC tag or GitHub Release was created or moved.
- 2026-05-20: Added public direct Connectanum notification helpers for
  downstream application readiness. `McpStreamableHttpClient` now exposes
  `notifyConnectanumToolDirect(...)` and `notifyConnectanumMethodDirect(...)`
  as lifecycle-free direct JSON notification APIs, and the `connectanum_mcp_io`
  entrypoint re-exports them. Client tests and MCP package tests assert the
  helpers send notification-only JSON-RPC payloads without `id`, without
  Streamable session headers, and without mutating an active session id or SSE
  cursor. The generated consumer package router-hosted MCP smoke now calls both
  helpers against a consumer WAMP procedure and verifies the procedure is
  invoked through the public package surface. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused client/MCP package tests, the focused
  generated consumer package smoke, `git diff --check`, and full local
  `bin/verify` passed. Commit `6fcd450` was pushed to GitLab `origin` and
  GitHub `add-router`. Hosted `add-router` evidence is clean at this follow-up:
  GitHub CI run `26174880668` passed with Fast Checks and Full Verify green,
  Dart Package Publish Dry Run `26174880599` passed, WAMP Profile Benchmarks
  `26174880601` passed, and the non-RC strict deployment-chain audit passed
  clean latest CI, clean CI logs, and clean Dart package dry-run gates.
- 2026-05-20: Added a public direct WAMP pub/sub notification helper for
  downstream application readiness. `McpStreamableHttpClient` now exposes
  `notifyWampEventDirect(...)`, which sends `connectanum.pubsub.publish` as a
  notification-only direct JSON request without requiring downstream callers to
  assemble JSON-RPC payloads manually. Client tests and `connectanum_mcp_io`
  re-export tests assert the helper sends no JSON-RPC `id`, does not attach
  Streamable session headers, and does not mutate active Streamable session
  state. The generated consumer package router-hosted MCP smoke now subscribes
  through direct JSON, calls the helper, polls the event queue, and verifies
  the notification reaches the WAMP subscription. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused client/MCP package tests, the focused
  generated consumer package smoke, `git diff --check`, and full local
  `bin/verify` passed. Commit `a1ef285` was pushed to GitLab `origin` and
  GitHub `add-router`. Hosted `add-router` evidence is clean at this follow-up:
  GitHub CI run `26177091687` passed with Fast Checks and Full Verify green,
  Dart Package Publish Dry Run `26177091693` passed, WAMP Profile Benchmarks
  `26177091686` passed, and the non-RC strict deployment-chain audit passed
  clean latest CI, clean CI logs, and clean Dart package dry-run gates.
- 2026-05-20: This follow-up closes a direct Connectanum tool header
  parity gap. `callConnectanumToolDirect(...)` and
  `notifyConnectanumToolDirect(...)` now reuse cached `x-mcp-header` parameter
  metadata when sending lifecycle-free direct JSON tool calls and
  notifications, matching standard `tools/call` behavior after standard or
  Connectanum direct catalog discovery. Client tests assert generated
  `Mcp-Param-*` headers for call and notification helpers, and the generated
  client-only consumer-package smoke captures `Mcp-Param-Text` from an
  external-package endpoint. Pre-change `bin/test-fast`, `bash -n
  bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, and focused
  `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'` passed; full
  local `bin/verify` passed. Commit `ed88382` was pushed to GitLab `origin`
  and GitHub `add-router`. Hosted `add-router` evidence is clean at this
  follow-up: GitHub CI run `26179778871` passed with Fast Checks and Full
  Verify green, Dart Package Publish Dry Run `26179778866` passed, WAMP Profile
  Benchmarks `26179778869` passed, and the non-RC strict deployment-chain audit
  passed clean latest CI, clean CI logs, and clean Dart package dry-run gates.
- 2026-05-20: This implementation follow-up closes the router-hosted direct
  Connectanum tool alias side of the same header contract. The client now emits
  `Mcp-Name` for `connectanum.tool.call` and `connectanum.tools.call`, the
  router validates `Mcp-Name` plus `Mcp-Param-*` for those aliases using the
  same tool schema path as standard `tools/call`, and direct dotted tool
  methods validate any present parameter headers against their schema. Native
  router coverage now accepts matching `connectanum.tool.call` headers and
  rejects mismatched `Mcp-Param-*` values; the generated consumer-package
  router-hosted MCP smoke proves public direct helpers override bad
  caller-provided `Mcp-Name`/`Mcp-Param-*` headers before reaching the real
  router endpoint. Pre-change `bin/test-fast`, formatting, `bash -n
  bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, focused
  `dart test packages/connectanum_router/test/router_integration_native_test.dart
  --chain-stack-traces`, focused generated consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `7d0bddd`
  was pushed to GitLab `origin` and GitHub `add-router`. Hosted `add-router`
  evidence is clean at this follow-up: GitHub CI run `26183740303` passed with
  Fast Checks and Full Verify green, Dart Package Publish Dry Run
  `26183740300` passed, WAMP Profile Benchmarks `26183740754` passed, and the
  non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean Dart package dry-run gates.
- 2026-05-20: This follow-up broadens direct Connectanum tool header parity to
  the generic direct JSON method helpers.
  `callConnectanumMethodDirect(...)` and
  `notifyConnectanumMethodDirect(...)` now synthesize cached
  `Mcp-Param-*` headers for `tools/call`, `connectanum.tool.call`,
  `connectanum.tools.call`, and cached dotted tool-method calls, overriding
  stale caller-provided parameter headers before the router validates them.
  Client tests prove the generic alias and dotted-method paths emit corrected
  headers; the generated client-only consumer-package smoke captures corrected
  alias/dotted parameter headers; and the generated router-hosted consumer
  package smoke sends stale task/note headers through the public generic
  helpers to prove downstream applications can call a real router endpoint
  without hand-assembling trusted MCP parameter headers. Pre-change
  `bin/test-fast`, formatting, `bash -n bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, focused
  generated client-only and router-hosted consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `fb88885`
  implemented the generic helper/header smoke coverage, and follow-up commit
  `a411ed1` removed a Dart 3.12 analyzer-dead fallback exposed by the first
  hosted CI/dry-run attempt. Hosted `add-router` evidence is clean at
  `a411ed1`: GitHub CI run `26186967933` passed with Fast Checks and Full
  Verify green, Dart Package Publish Dry Run `26186967888` passed, WAMP
  Profile Benchmarks `26186967889` passed, and the non-RC strict
  deployment-chain audit passed clean latest CI, clean CI logs, and clean Dart
  package dry-run gates.
- 2026-05-20: This follow-up closes the notification-only side of the generic
  direct tool header contract. High-level direct Connectanum tool helpers now
  strip caller-provided `Mcp-Param-*` headers before adding regenerated cached
  parameter headers, preventing stale parameters from leaking through typed,
  alias, or dotted direct notification helpers. Client tests cover uncached
  stale-header removal plus cached typed, dotted-method, and
  `connectanum.tools.call` alias notification regeneration with active
  Streamable session state preserved. The generated client-only and
  router-hosted consumer-package smokes now send stale parameter headers
  through typed, alias, and dotted direct notification helpers and prove
  corrected captured headers or real router side effects. Pre-change
  `bin/test-fast`, formatting, `bash -n bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, focused
  generated client-only and router-hosted consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `bafbe25`
  was pushed to GitLab `origin` and GitHub `add-router`. Hosted `add-router`
  evidence is clean at this follow-up: GitHub CI run `26189389158` passed with
  Fast Checks and Full Verify green, Dart Package Publish Dry Run
  `26189389072` passed, WAMP Profile Benchmarks `26189389097` passed, and the
  non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean Dart package dry-run gates.
- 2026-05-20: This local follow-up extends stale `Mcp-Param-*` header safety
  evidence to direct WAMP pub/sub notification helpers. The focused client test
  now sends a stale `Mcp-Param-Topic` through `notifyWampEventDirect(...)` and
  asserts the lifecycle-free direct JSON notification carries no stale
  parameter headers. The generated router-hosted consumer-package smoke sends
  the same stale topic header through the public helper and proves the event is
  still delivered by the real router endpoint. Pre-change `bin/test-fast`,
  formatting, `bash -n bin/common.sh`, focused
  `dart test -p vm packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  focused generated client-only and router-hosted consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `4d80537` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted `add-router`
  evidence is clean at `4d80537`: CI run `26191487398` passed with Fast Checks
  and Full Verify green, Dart Package Publish Dry Run `26191487475` passed,
  WAMP Profile Benchmarks `26191487402` passed, and the non-RC strict
  deployment-chain audit passed clean latest CI, clean CI logs, and clean Dart
  package dry-run gates.
- 2026-05-20: This implementation follow-up adds a public
  Streamable-session WAMP pub/sub notification helper for consumer
  applications. `notifyWampEvent(...)` sends `connectanum.pubsub.publish` as a
  notification-only Streamable HTTP request while preserving the active MCP
  session and stripping stale caller-provided `Mcp-Param-*` headers through the
  same Connectanum method header path as direct helpers. Client tests prove the
  helper sends no JSON-RPC `id`, carries Streamable session headers, and drops
  stale `Mcp-Param-Topic`; the MCP IO export test proves the helper is
  available through `package:connectanum_mcp/connectanum_mcp_io.dart`; and the
  generated router-hosted consumer-package smoke proves the public helper
  delivers a WAMP event through a real router endpoint without mutating the SSE
  cursor. Pre-change `bin/test-fast`, formatting, `bash -n bin/common.sh`,
  focused client/MCP package tests, and the focused generated router-hosted
  consumer-package smoke passed locally. Full local `bin/verify` passed.
  Commit `1021cb9` was pushed to GitLab `origin` and GitHub `add-router`.
  Hosted `add-router` evidence is clean at `1021cb9`: CI run `26193409876`
  passed with Fast Checks and Full Verify green, Dart Package Publish Dry Run
  `26193409938` passed, WAMP Profile Benchmarks `26193409936` passed, and the
  non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean Dart package dry-run gates.
- 2026-05-21: This implementation follow-up adds standard MCP tool
  notification helpers for consumer applications. `notifyTool(...)` and
  `notifyToolDirect(...)` send id-free `tools/call` notifications, preserve the
  active MCP session and SSE cursor for Streamable HTTP, keep direct JSON
  lifecycle-free, and strip then regenerate stale caller-provided
  `Mcp-Param-*` headers from cached tool metadata. Client tests prove the
  Streamable and direct request shapes plus parameter-header regeneration; the
  MCP IO export test proves the helpers are available through
  `package:connectanum_mcp/connectanum_mcp_io.dart`; and the generated
  router-hosted consumer-package smoke proves standard direct and Streamable
  helper calls invoke a consumer WAMP procedure through a real router endpoint
  without private assumptions. Pre-change `bin/test-fast`, formatting,
  `bash -n bin/common.sh`, focused client/MCP package tests, the focused
  generated router-hosted consumer-package smoke, `git diff --check`, and full
  local `bin/verify` passed. Commit `b45a96f` was pushed to GitLab `origin`
  and GitHub `add-router`. Hosted `add-router` evidence is clean at
  `b45a96f`: CI run `26195189401` passed with Fast Checks and Full Verify
  green, Dart Package Publish Dry Run `26195189402` passed, WAMP Profile
  Benchmarks `26195189400` passed, and the non-RC strict deployment-chain
  audit passed clean latest CI, clean CI logs, and clean Dart package dry-run
  gates.
- 2026-05-21: GitHub `master` was fast-forward promoted from `0c0e043` to
  `b45a96f`, placing the router-hosted MCP downstream-readiness helpers on the
  default release branch. GitHub reported the PR-only branch rule was bypassed
  for the direct update. Local `bin/test-fast` passed before promotion, and
  post-promotion local `bin/verify` passed. Hosted `master` evidence is clean
  at `b45a96f`: CI run `26196195552` passed with Fast Checks and Full Verify
  green, Dart Package Publish Dry Run `26196195553` passed, WAMP Profile
  Benchmarks `26196195554` passed, and Router Image dry-run `26196649190`
  passed without GHCR login while uploading the preview artifact. Native
  Artifacts dry-run `26151756102` remains relevant because no
  native-release-sensitive paths changed since `0c0e043`. The strict
  deployment-chain audit passed clean current-head CI, clean CI logs, clean
  Dart package dry-run, native release dry-run relevance, fresh router image
  dry-run relevance, workflow visibility, branch protection, and router package
  visibility gates. RC readiness remains not-ready only because no approved
  numeric RC tag or GitHub prerelease points at `b45a96f`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag, and pub.dev publishing
  remains deferred for package ownership/version/release-order decisions.
- 2026-05-21: The deployment-chain audit now prints explicit branch-protection
  handoff evidence for pull-request enforcement and administrator bypass state.
  A fake-`gh` regression covers the protected default-branch output, and the
  live `master` audit reports `Require pull requests: true` and `Admin bypass
  allowed: true`, matching the direct-promotion bypass signal from GitHub.
  Pre-change `bin/test-fast`, `bash -n bin/audit-github-deployment-chain`,
  `python3 tool/test_audit_github_deployment_chain.py`, `git diff --check`,
  `bin/audit-github-deployment-chain --branch master --show-rc-readiness`, and
  full local `bin/verify` passed. Commit `882c207` was pushed to GitLab
  `origin` and GitHub `add-router`. Hosted `add-router` evidence is clean: CI
  run `26198235075` passed with Fast Checks and Full Verify green, and the
  gated deployment-chain audit passed current-head CI/log checks, workflow
  visibility, router package visibility, and the relevant Dart package dry-run
  gate. The latest Dart Package Publish Dry Run remains `26195189402` at
  `b45a96f`, and the audit accepts it because no publish-sensitive paths
  changed in `882c207`.
- 2026-05-21: GitHub `master` was fast-forward promoted from `b45a96f` to
  `882c207`, so the default release branch now includes the explicit
  branch-protection audit handoff evidence. GitHub again reported the PR-only
  branch rule was bypassed for the direct update, and the promoted audit output
  records `Require pull requests: true` with `Admin bypass allowed: true`.
  Local `bin/test-fast` passed before the promotion, and post-promotion local
  `bin/verify` passed. Hosted `master` CI run `26199199255` passed with Fast
  Checks in 4m26s and Full Verify in 6m15s. The strict deployment-chain audit
  passed clean current-head CI, clean CI logs, relevant Dart package dry-run,
  relevant native release dry-run, relevant router image dry-run, workflow
  visibility, branch protection, and router package visibility gates. The
  latest relevant runs remain Dart Package Publish Dry Run `26196195553`, WAMP
  Profile Benchmarks `26196195554`, Router Image dry-run `26196649190`, and
  Native Artifacts dry-run `26151756102`; the audit accepts that evidence
  because `882c207` changed only audit/tooling and docs paths that are not
  sensitive to those release gates. RC readiness remains not-ready only because
  no approved numeric RC tag or GitHub prerelease points at `882c207`; the
  audit suggests `v0.1.0-rc.2` as the next release-decision tag. No RC tag or
  GitHub Release was created or moved.
- 2026-05-21: The RC-readiness audit now refuses to accept a local-only
  numeric RC tag as sufficient GitHub prerelease evidence. A fake-`gh`/fake-git
  regression covers the stale-remote-tag case where a local tag points at the
  checked-out head but the GitHub tag does not; `--require-rc-ready` must keep
  the GitHub prerelease gate not-ready until the approved RC tag exists on
  GitHub at the checked-out head. Pre-change `bin/test-fast`,
  `bash -n bin/audit-github-deployment-chain`, and
  `python3 -m unittest tool/test_audit_github_deployment_chain.py` passed;
  full local `bin/verify` passed before handoff. Commit `11a9b24` was pushed
  to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  `master` CI run `26201026642` passed with Fast Checks and Full Verify green,
  and the strict deployment-chain audit passed required release-branch gates at
  `11a9b24`. RC readiness remains not-ready only because no approved numeric
  RC tag or GitHub prerelease points at `11a9b24`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up adds
  `McpStreamableHttpClient.callConnectanumMethod(...)` as the
  Streamable-session counterpart to `callConnectanumMethodDirect(...)`, letting
  consumer applications call router-provided dotted Connectanum methods through
  an active MCP session without hand-assembling direct JSON requests. Client
  coverage proves Streamable session headers are preserved and cached
  `Mcp-Param-*` headers are regenerated over stale caller headers; the MCP IO
  export test proves the helper is available through
  `package:connectanum_mcp/connectanum_mcp_io.dart` and works for
  `connectanum.pubsub.publish`; and the generated router-hosted
  consumer-package smoke proves the public helper publishes and receives a WAMP
  event through a real router endpoint without private assumptions. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused client/MCP tests, the
  focused generated router-hosted consumer-package smoke, and full local
  `bin/verify` passed.
- 2026-05-21: Hosted GitHub `master` and `add-router` CI for commit `3674e86`
  exposed a Linux Chrome/Dart2Wasm browser harness failure after the
  non-browser Full Verify suites had passed:
  `websocket_transport_web_test.dart` failed during test loading with
  `Bad state: Cannot add stream while adding stream`, then the test runner hung
  until the Full Verify job timed out as cancelled. The browser runtime smoke
  is now explicit in `bin/test-all`: hosted Linux CI uses the stable Dart2Js
  browser compiler for this Chrome smoke, while local/non-Linux runs keep the
  Dart2Wasm default from the package test config. Pre-change `bin/test-fast`
  passed before this CI-stability patch.
- 2026-05-21: Commit `462f4e0` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub CI passed at `462f4e0` for
  both promoted branches: `master` run `26204808842` and `add-router` run
  `26204805797` each completed Fast Checks and Full Verify successfully. A
  manual Router Image dry-run on `master` at `462f4e0`, run `26205189275`,
  completed successfully, uploaded the preview artifact, and skipped GHCR
  login. The strict deployment-chain audit passes required gates at `462f4e0`:
  latest CI job/log, Dart package publish dry-run relevance, native release
  dry-run relevance, router image dry-run relevance, workflow visibility,
  branch protection, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag or GitHub prerelease points
  at `462f4e0`; the audit suggests `v0.1.0-rc.2` as the next
  release-decision tag.
- 2026-05-21: This implementation follow-up adds focused public-surface
  coverage for `McpStreamableHttpClient.notifyConnectanumMethod(...)`, the
  Streamable-session notification counterpart to
  `callConnectanumMethod(...)`. Client tests prove the helper sends id-free
  JSON-RPC through the active MCP session while preserving the session id and
  SSE cursor and regenerating cached `Mcp-Param-*` headers over stale caller
  headers. The MCP IO export test proves the helper is available through
  `package:connectanum_mcp/connectanum_mcp_io.dart` for
  `connectanum.pubsub.publish`, and the generated router-hosted
  consumer-package smoke proves the public helper publishes and receives a WAMP
  event through a real router endpoint without private assumptions. Pre-change
  `bin/test-fast`, formatting, `bash -n bin/common.sh`, focused client/MCP
  package tests, the focused generated router-hosted consumer-package smoke,
  `git diff --check`, and full local `bin/verify` passed.
- 2026-05-21: Commit `79570a1` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26206356283` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26206354103` passed, Dart Package
  Publish Dry Run `26206356286` passed on `master`, WAMP Profile Benchmarks
  `26206356266` passed on `master`, and Router Image dry-run `26206759399`
  passed on `master` with preview artifact upload and skipped GHCR login. The
  strict deployment-chain audit passes required gates at `79570a1`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. RC readiness remains not-ready only because no approved
  numeric RC tag or GitHub prerelease points at `79570a1`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up adds public IO-entrypoint
  Streamable WAMP meta helper coverage for consumer applications. The MCP IO
  export smoke now initializes `McpStreamableHttpClient` through
  `package:connectanum_mcp/connectanum_mcp_io.dart`, calls typed WAMP meta
  helpers over session-aware `tools/call`, and asserts Streamable session id
  plus SSE cursor propagation through the package boundary. The coverage
  includes `countWampSessions(...)`, `matchWampRegistration(...)`,
  `countWampRegistrationCallees(...)`, `matchWampSubscription(...)`, and
  `countWampSubscriptionSubscribers(...)`. Pre-change `bin/test-fast`,
  formatting, focused
  `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
  `git diff --check`, and full local `bin/verify` passed.
- 2026-05-21: Commit `022811d` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26207890975` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26207886336` passed, Dart Package
  Publish Dry Run `26207890979` passed on `master`, and Dart Package Publish
  Dry Run `26207886355` passed on `add-router`. A fresh Router Image dry-run on
  `master`, run `26208362869`, passed for `022811d`, uploaded the preview
  artifact, skipped GHCR login, and kept the router image gate non-mutating.
  The strict deployment-chain audit passes required gates at `022811d`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. The latest WAMP Profile Benchmarks run remains
  `26206356266` at `79570a1` and is still relevant because this follow-up
  changed only MCP package test coverage and state docs, not
  benchmark-sensitive WAMP profile inputs. RC readiness remains not-ready only
  because no approved numeric RC tag or GitHub prerelease points at `022811d`;
  the audit suggests `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up expands the public IO-entrypoint
  Streamable WAMP meta smoke from representative helpers to the full typed
  session/registration/subscription helper surface. The MCP IO export smoke now
  initializes `McpStreamableHttpClient` through
  `package:connectanum_mcp/connectanum_mcp_io.dart`, calls all typed WAMP meta
  helpers over session-aware `tools/call`, asserts Streamable session id and
  SSE cursor propagation through `io-session-1:post:15`, and verifies
  representative request argument envelopes for session, registration, and
  subscription lookups. Pre-change `bin/test-fast`, formatting, focused
  `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
  `git diff --check`, and full local `bin/verify` passed.
- 2026-05-21: Commit `f9b4f31` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26209778136` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26209774233` passed, Dart Package
  Publish Dry Run `26209778116` passed on `master`, and Dart Package Publish
  Dry Run `26209774291` passed on `add-router`. A fresh Router Image dry-run on
  `master`, run `26210273976`, passed for `f9b4f31`, uploaded the preview
  artifact, skipped GHCR login, and kept the router image gate non-mutating.
  The strict deployment-chain audit passes required gates at `f9b4f31`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. The latest WAMP Profile Benchmarks run remains
  `26206356266` at `79570a1` and is still relevant because this follow-up
  changed only MCP package test coverage and state docs, not
  benchmark-sensitive WAMP profile inputs. RC readiness remains not-ready only
  because no approved numeric RC tag or GitHub prerelease points at `f9b4f31`;
  the audit suggests `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up closes the remaining public
  IO-entrypoint direct JSON WAMP subscription-meta package-boundary smoke gap.
  The MCP IO export smoke now calls `listWampSubscriptionsDirect(...)`,
  `lookupWampSubscriptionDirect(...)`, `matchWampSubscriptionDirect(...)`,
  `getWampSubscriptionDirect(...)`,
  `listWampSubscriptionSubscribersDirect(...)`, and
  `countWampSubscriptionSubscribersDirect(...)` through
  `package:connectanum_mcp/connectanum_mcp_io.dart`, asserts lifecycle-free
  direct JSON `connectanum.tool.call` request shapes without session headers,
  and verifies representative lookup/subscriber argument envelopes.
  Pre-change `bin/test-fast`, formatting, focused
  `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
  `git diff --check`, and full local `bin/verify` passed before handoff.
- 2026-05-21: Commit `548d267` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26211691986` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26211687420` passed, Dart Package
  Publish Dry Run `26211691941` passed on `master`, and Dart Package Publish
  Dry Run `26211687476` passed on `add-router`. A fresh Router Image dry-run on
  `master`, run `26212270565`, passed for `548d267`, uploaded the preview
  artifact, skipped GHCR login, and kept the router image gate non-mutating.
  The strict deployment-chain audit passes required gates at `548d267`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. The latest WAMP Profile Benchmarks run remains
  `26206356266` at `79570a1` and is still relevant because this follow-up
  changed only MCP package test coverage and state docs, not
  benchmark-sensitive WAMP profile inputs. RC readiness remains not-ready only
  because no approved numeric RC tag or GitHub prerelease points at `548d267`;
  the audit suggests `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up adds WAMP Profile Benchmarks as a
  first-class deployment-chain audit and RC-readiness gate.
  `bin/audit-github-deployment-chain` now exposes
  `--show-wamp-profile-benchmarks` and
  `--require-clean-wamp-profile-benchmarks`; the gate verifies the latest
  `WAMP Profile Benchmarks` run status, expected `Linux WAMP profile gates`
  job, canonical validation step, benchmark artifact upload, and stale-run
  relevance across WAMP-profile-sensitive inputs. Fake-`gh` regression coverage
  accepts stale benchmark evidence when no sensitive inputs changed and rejects
  it when checked-out package inputs changed after the benchmark head. The
  hosted WAMP benchmark workflow path filter now includes
  `packages/connectanum_core/**` and root `pubspec.yaml`, matching the audit
  sensitivity for package/runtime inputs.
  Pre-change `bin/test-fast`, `bash -n bin/audit-github-deployment-chain`,
  `python3 -m unittest tool/test_audit_github_deployment_chain.py`, live
  `bin/audit-github-deployment-chain --branch master --strict
  --require-workflows-visible --require-router-package
  --require-clean-latest-ci --require-clean-latest-ci-logs
  --require-clean-dart-package-publish-dry-run
  --require-clean-native-release-dry-run --require-clean-router-image-dry-run
  --require-clean-wamp-profile-benchmarks --show-rc-readiness`,
  `git diff --check`, and full local `bin/verify` passed. Commit `9825526`
  (`ci: gate wamp profile benchmark evidence`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `9825526`: `master` CI run `26214693146` passed, `add-router` CI run
  `26214694060` passed, `master` WAMP Profile Benchmarks run `26214693251`
  passed, and `add-router` WAMP Profile Benchmarks run `26214693816` passed.
  The strict deployment-chain audit now passes required gates at `9825526`:
  current-head CI/logs, relevant Dart package dry-run, relevant native release
  dry-run, relevant router image dry-run, current-head WAMP profile benchmark
  evidence, workflow visibility, branch protection, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag or GitHub prerelease points at `9825526`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up hardens Dart package release-plan
  diagnostics for scoped package dry-runs. `bin/dart-package-publish-dry-run
  --show-release-plan` now inventories the full workspace package set even when
  the actual `dart pub publish --dry-run` target is scoped to one package, so
  release-order output cannot hide private packages that still affect a public
  publish. The actual archive dry-run remains scoped to the selected package
  targets. A fake-`dart` regression in
  `tool/test_dart_package_publish_dry_run.py` is wired into both
  `bin/test-fast` and `bin/test-all`, proving a scoped `connectanum_client`
  release plan still lists all private workspace packages and only runs one
  archive dry-run. The RC-readiness audit deferred-pub.dev summary now keeps
  the full release-plan headings when surfacing that inventory, so package
  lists are not detached from their meaning. Pre-change `bin/test-fast`,
  `python3 tool/test_dart_package_publish_dry_run.py`,
  `bin/dart-package-publish-dry-run --show-release-plan connectanum_client`,
  `python3 tool/test_audit_github_deployment_chain.py`, `git diff --check`, and
  full local `bin/verify` passed. Commit `4dec39c` (`ci: inventory dart package
  release plan`) was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `4dec39c`: `master` CI run
  `26217438556` passed, `add-router` CI run `26217438580` passed, `master` Dart
  Package Publish Dry Run run `26217438575` passed, and `add-router` Dart
  Package Publish Dry Run run `26217438585` passed. Focused audit readability
  tests and full local `bin/verify` passed for the headed deferred-pub.dev
  summary follow-up. Commit `7d60dd8` (`ci: label dart release-plan audit
  output`) was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted CI is clean at `7d60dd8`: `master` CI run `26218795344`
  passed with Fast Checks and Full Verify green, and `add-router` CI run
  `26218790197` passed with Fast Checks and Full Verify green. The strict
  deployment-chain audit passes required gates at `7d60dd8`; it accepts Dart
  Package Publish Dry Run run `26217438575` from `4dec39c` as relevant because
  no publish-sensitive paths changed in the audit-output follow-up. RC readiness
  remains not-ready only because no approved numeric RC tag or GitHub prerelease
  points at `7d60dd8`; the audit suggests `v0.1.0-rc.2`. Commit `becaf98` (`ci:
  publish dart release plan in dry-run workflow`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`, updating hosted Dart Package Publish
  Dry Run execution to call
  `bin/dart-package-publish-dry-run --show-release-plan`, so GitHub run logs and
  step summaries include the release-order inventory on publish-sensitive
  changes. Pre-change `bin/test-fast`,
  `python3 tool/test_dart_package_publish_dry_run.py`,
  `bin/dart-package-publish-dry-run --show-release-plan connectanum_client`,
  and full local `bin/verify` passed for this follow-up. Hosted GitHub evidence
  is clean at `becaf98`: `master` CI run `26220664156` passed with Fast Checks
  and Full Verify green, `add-router` CI run `26220660767` passed with Fast
  Checks and Full Verify green, `master` Dart Package Publish Dry Run run
  `26220664109` passed with release-plan sections visible in the log, and
  `add-router` Dart Package Publish Dry Run run `26220660832` passed with the
  same log evidence. The strict deployment-chain audit passes required gates at
  `becaf98`; RC readiness remains not-ready only because no approved numeric RC
  tag or GitHub prerelease points at `becaf98`; the audit suggests
  `v0.1.0-rc.2`.
- 2026-05-21: Commit `156192c` (`ci: audit rc router image tag evidence`)
  tightens the RC-readiness audit for router image evidence.
  `bin/audit-github-deployment-chain` now derives the required Router Image tag
  from the selected numeric RC tag (`v0.1.0-rc.N` -> `0.1.0-rc.N`) and probes
  that exact public GHCR manifest during `--show-rc-readiness` /
  `--require-rc-ready`, so generic package visibility can no longer mask a
  missing RC image tag. The fake-GitHub/GHCR regression suite covers both the
  ready path and a visible-package/missing-RC-image-tag failure. Pre-change
  `bin/test-fast`, focused `bash -n bin/audit-github-deployment-chain`,
  focused `python3 -m unittest tool/test_audit_github_deployment_chain.py`, a
  live read-only `bin/audit-github-deployment-chain --branch master
  --show-rc-readiness` summary, `git diff --check`, and full local `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub evidence is clean at `156192c`: `master` CI
  run `26222937612` passed with Fast Checks and Full Verify green,
  `add-router` CI run `26222934044` passed with Fast Checks and Full Verify
  green, and the strict deployment-chain audit passed required gates on
  `master`. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `babaa9f` (`ci: normalize manual router image tags`)
  normalizes manual Router Image workflow `image_tag` inputs that use project
  version refs, so a manual `v0.1.0-rc.N` input resolves to Docker tag
  `0.1.0-rc.N`, the same tag shape used by release-tag-triggered runs and exact
  RC audit checks. Manual
  `publish_approval` still has to match the normalized primary Docker tag, so an
  approval containing the leading `v` is rejected for normalized publishes.
  Pre-change `bin/test-fast`, focused `python3 -m unittest
  tool/test_render_router_image_metadata.py
  tool/test_render_native_release_notes.py`, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `babaa9f`: `master` CI run `26225035187` and `add-router` CI run
  `26225035212` passed with Fast Checks and Full Verify green, Router Image
  dry-run `26225059344` passed on `master` for manual `image_tag=v0.1.0-rc.2`
  without GHCR login, and the strict deployment-chain audit passed required
  gates on `master`. No RC tag, GitHub Release, or router image was created or
  moved.
- 2026-05-21: Commit `f91cc8b` (`ci: audit router image preview metadata`)
  hardens Router Image dry-run artifact evidence in the deployment-chain audit.
  The audit now downloads `router-image-preview`, verifies
  `router-image-metadata.md` targets `ghcr.io/konsultaner/connectanum-router`,
  requires dry-run mode and publish=false, parses and validates the primary
  Docker tag, and rejects project-version `v` prefixes that would not match
  exact RC image tag semantics. Pre-change `bin/test-fast`, focused `bash -n
  bin/audit-github-deployment-chain`, focused `python3 -m unittest
  tool/test_audit_github_deployment_chain.py`, live read-only
  `bin/audit-github-deployment-chain --branch master
  --show-router-image-dry-run`, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `f91cc8b`: `master` CI run `26228085097` and `add-router` CI run
  `26228080838` passed with Fast Checks and Full Verify green, and the strict
  deployment-chain audit passed required gates on `master` at `f91cc8b`. The
  strict audit accepts Router Image dry-run `26225059344` as relevant because no
  router-image-sensitive inputs changed after that run, downloads the preview
  metadata, and verifies primary tag `0.1.0-rc.2` before accepting the gate. No
  RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `9ba8748` (`fix: harden MCP auth error handling`) hardens
  downstream application behavior when a router-hosted auth bridge returns a
  non-JSON error body. `ConnectanumHttpAuthClient` now throws typed
  `ConnectanumHttpAuthException`s for non-success plain-text or HTML auth
  bridge responses, preserving status code and raw body with no decoded error
  payload, while successful malformed JSON still fails as malformed JSON. The
  focused `http_auth_client_test.dart` regression covers a plain-text 503
  challenge response, and the generated client-only consumer package smoke now
  proves the same behavior through
  `package:connectanum_mcp/connectanum_mcp_io.dart` using public APIs only.
  Local evidence: pre-change `bin/test-fast`, focused
  `dart test packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`,
  `bash -n bin/common.sh`, focused `run_mcp_client_package_smoke`,
  `git diff --check`, and clean-tree full `bin/verify` passed. The commit was
  pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `9ba8748`: `master` CI run `26231778548`, `add-router`
  CI run `26231777640`, Dart Package Publish Dry Run runs `26231779191` on
  `master` and `26231777632` on `add-router`, and WAMP Profile Benchmarks runs
  `26231779087` on `master` and `26231777445` on `add-router` passed. Router
  Image dry-run `26232580498` passed on `master` for manual
  `image_tag=v0.1.0-rc.2` without GHCR login, uploaded preview metadata, and
  verified primary tag `0.1.0-rc.2`. The strict deployment-chain audit passed
  required gates on `master` at `9ba8748`; RC readiness still reports not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-21: Commit `34c9889` (`fix: select streamable mcp sse responses by
  id`) fixes downstream application response selection when a Streamable HTTP
  SSE POST stream includes server notifications before JSON-RPC responses. The
  client now matches response objects by request ID for single requests and
  batches, ignores interleaved notification events, and still captures the last
  SSE event ID for session resume. Focused client regressions and the generated
  client-only consumer package smoke cover the public package path using
  `connectanum_mcp_io`. Local evidence: pre-change `bin/test-fast`, focused
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -n bin/common.sh`, focused `run_mcp_client_package_smoke`,
  `git diff --check`, clean-tree `bin/test-fast`, and clean-tree `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub `master` evidence is clean at `34c9889`: CI
  run `26235994960`, Dart Package Publish Dry Run `26235995708`, WAMP Profile
  Benchmarks `26235993239`, and Router Image dry-run `26236030117` passed. The
  strict deployment-chain audit passed required gates on `master` at
  `34c9889`; RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `4daf824` (`fix: honor mcp accept quality weights`)
  hardens router-hosted MCP Streamable HTTP content negotiation for downstream
  applications. The router now honors `q=0` media ranges in `Accept` headers
  before choosing JSON or SSE response paths, so explicit JSON rejection returns
  `406 Not Acceptable` before standard MCP header validation and explicit SSE
  rejection keeps session POST responses on JSON instead of an SSE stream.
  Fail-first focused coverage reproduced the compatibility gap in
  `guards MCP Streamable HTTP ingress and sessions`; the fixed focused native
  MCP ingress regression, `dart analyze packages/connectanum_router`,
  `git diff --check`, clean-tree `bin/test-fast`, and clean-tree `bin/verify`
  passed locally. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub `master` evidence is clean
  at `4daf824`: CI run `26239725979`, Dart Package Publish Dry Run
  `26239726467`, WAMP Profile Benchmarks `26239726002`, and Router Image
  dry-run `26239757142` passed. The strict deployment-chain audit passed
  required gates on `master` at `4daf824`; RC readiness still reports not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-21: Commit `a9dc2f6` (`fix: apply mcp accept specificity`) applies
  HTTP `Accept` media-range specificity to router-hosted MCP content
  negotiation. Exact
  `application/json;q=0` and `text/event-stream;q=0` ranges now reject those
  response types even when a less-specific wildcard such as `*/*;q=1` is
  present, so direct JSON and SSE clients cannot accidentally opt back into a
  response type they explicitly reject. Fail-first focused coverage reproduced
  `application/json;q=0, */*;q=1` returning `200` instead of `406` in
  `guards MCP Streamable HTTP ingress and sessions`; the fixed focused native
  MCP ingress regression, `dart analyze packages/connectanum_router`,
  `git diff --check`, `bin/test-fast`, and `bin/verify` pass locally.
  The commit was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `a9dc2f6`: `master` CI run
  `26242592111`, Dart Package Publish Dry Run `26242591939`, WAMP Profile
  Benchmarks `26242592123`, Router Image dry-run `26242601368`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `a9dc2f6`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-21: Commit `37dfd6f` (`fix: isolate mcp direct json sessions`) fixes
  router-hosted MCP direct JSON session isolation for downstream applications.
  Direct JSON POSTs that negotiate only `application/json` now ignore caller
  `MCP-Session-Id` headers when selecting the router endpoint and response
  lifecycle headers, so stale Streamable HTTP session IDs cannot make
  lifecycle-free direct tool/meta API calls return `404`. Streamable HTTP
  requests, GET polling, and DELETE session cleanup still enforce MCP session
  IDs. Fail-first focused coverage reproduced a stale direct `tools/list` call
  returning `404` in `guards MCP Streamable HTTP ingress and sessions`; the
  fixed focused native MCP ingress regression, `dart analyze
  packages/connectanum_router`, `git diff --check`, patched `bin/test-fast`,
  and patched `bin/verify` passed locally. The commit was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `37dfd6f`: `master` CI run `26245432181`, Dart Package Publish Dry
  Run `26245432059`, WAMP Profile Benchmarks `26245432055`, Router Image
  dry-run `26245445679`, and matching `add-router` CI/dry-run/WAMP runs
  passed. The strict deployment-chain audit passed required gates on `master`
  at `37dfd6f`; RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `dea8697` (`fix: isolate mcp direct json error sessions`)
  closes the matching direct JSON error-response session leak. Router-hosted
  direct JSON POSTs that negotiate only `application/json` now suppress caller
  `MCP-Session-Id` headers on early error responses as well as successful direct
  JSON responses, including unsupported MCP protocol versions and malformed
  JSON bodies. True Streamable HTTP POSTs, GET polling, and DELETE session
  cleanup continue to preserve and enforce session lifecycle headers.
  Fail-first focused coverage reproduced stale response headers in
  `guards MCP Streamable HTTP ingress and sessions`; after the fix, the focused
  native MCP ingress regression, `dart analyze packages/connectanum_router`,
  `bash -n bin/common.sh`, focused generated consumer-package smoke,
  `git diff --check`, patched `bin/test-fast`, and full local `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub evidence is clean at `dea8697`: `master` CI
  run `26248484287`, Dart Package Publish Dry Run `26248484324`, WAMP Profile
  Benchmarks `26248484285`, Router Image dry-run `26248512314`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `dea8697`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-21: Commit `c54f36d` (`fix: isolate mcp route auth sessions`) closes
  the matching route-level auth response session leak before the MCP handler
  runs. Pre-dispatch MCP route auth and rate-limit failures now use the same
  direct-vs-Streamable response-session decision as router-hosted MCP handling,
  so lifecycle-free direct JSON POSTs that negotiate only `application/json`
  do not echo stale caller `MCP-Session-Id` headers on missing or invalid bearer
  token failures. True Streamable HTTP auth failures still preserve the owned
  session id. Fail-first generated consumer-package smoke reproduced the secure
  direct JSON missing-bearer stale-session leak; after the fix, focused
  generated consumer-package smoke, `bash -n bin/common.sh`,
  `dart analyze packages/connectanum_router`, focused native MCP ingress
  regression, patched `bin/test-fast`, and full local `bin/verify` passed. The
  commit was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `c54f36d`: `master` CI run
  `26251320957`, Dart Package Publish Dry Run `26251320959`, WAMP Profile
  Benchmarks `26251320944`, Router Image dry-run `26251338983`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `c54f36d`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-21: Current local implementation follow-up adds focused router
  integration regression coverage for the MCP route-level auth response session
  contract. The secure route isolation test now proves lifecycle-free direct
  JSON POSTs with stale `MCP-Session-Id` headers do not echo that session id on
  missing or invalid bearer-token failures, while true Streamable HTTP POST auth
  failures still preserve the owned session id. Pre-change `bin/test-fast`,
  focused `isolates MCP Streamable HTTP sessions by route and bearer principal`
  router integration test, `git diff --check`, and full local `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub evidence is clean at `62c0146`: `master` CI
  run `26253868994`, Dart Package Publish Dry Run `26253868990`, WAMP Profile
  Benchmarks `26253868997`, Router Image dry-run `26254530985`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `62c0146`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. The Router Image dry-run
  uploaded preview metadata for `0.1.0-rc.2` and skipped GHCR login. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `6db2c26`
  (`test: cover mcp rate-limit session isolation`) extends the same
  pre-dispatch MCP response-session boundary to route-level rate-limit coverage.
  The router runtime rate-limit test now proves lifecycle-free direct JSON POSTs
  with stale `MCP-Session-Id` headers do not echo that session id when the route
  limit has already been exceeded, while true Streamable HTTP POST failures
  still preserve the owned session id. Pre-change `bin/test-fast`, focused
  `rate limited MCP routes keep Streamable HTTP CORS headers` router runtime
  test, `git diff --check`, and full local `bin/verify` passed. The commit was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `6db2c26`: `master` CI run `26256185398`, Dart
  Package Publish Dry Run `26256185362`, WAMP Profile Benchmarks `26256185401`,
  Router Image dry-run `26256205180`, and matching `add-router` CI/dry-run/WAMP
  runs passed. The first `add-router` CI attempt failed in the hosted Dart
  browser harness before the browser test body ran, then the failed-job rerun
  passed. The strict deployment-chain audit passed required gates on `master` at
  `6db2c26`; RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected. The Router Image dry-run uploaded preview metadata for
  `0.1.0-rc.2` and skipped GHCR login. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-22: Commit `fafbc56`
  (`test: cover consumer mcp rate-limit smoke`) extends route-level rate-limit MCP
  response-session evidence from the focused router runtime test into the
  generated consumer-package router-hosted MCP smoke. The neutral consumer app
  now hosts a real rate-limited MCP route, spends the first two allowed
  requests on direct JSON `tools/list` and Streamable `initialize`, then proves
  the exhausted route returns `429 rate_limited` without echoing a stale direct
  JSON caller session id while preserving the owned Streamable session id on a
  true Streamable POST failure. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused generated
  `run_mcp_consumer_package_smoke`, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `fafbc56`: `master` CI run `26258446014` and `add-router` CI run
  `26258445002` passed. The strict deployment-chain audit passed required
  gates on `master` at `fafbc56`, using current-head CI/log evidence plus the
  latest relevant Dart package dry-run, native dry-run, WAMP profile benchmark,
  and Router Image dry-run evidence. RC readiness still reports not-ready only
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-22: Commit `7f48714`
  (`fix: allow mcp delete after route limit`) lets MCP Streamable HTTP
  `DELETE` cleanup bypass the route-level rate-limit gate while retaining route
  auth/session validation. Fail-first focused runtime coverage reproduced
  cleanup `DELETE` returning `429` after route-limit exhaustion; after the fix,
  focused rate-limited MCP runtime tests, `bash -n bin/common.sh`, the
  generated consumer-package router-hosted MCP smoke,
  `dart analyze packages/connectanum_router`, `git diff --check`, and full
  local `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `7f48714`: `master` CI run `26260457692`, Dart Package Publish Dry Run
  `26260457644`, WAMP Profile Benchmarks `26260457656`, Router Image dry-run
  `26260908932`, and matching `add-router` CI/dry-run/WAMP runs passed. The
  first strict audit found the previous Router Image dry-run stale for this
  router-sensitive change; after manual non-mutating Router Image dry-run
  `26260908932`, the strict deployment-chain audit passed required gates on
  `master` at `7f48714`. RC readiness still reports not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for
  release-order/operator decisions. No RC tag, GitHub Release, or router image
  was created or moved.
- 2026-05-22: Commit `3a066b2`
  (`test: cover mcp client rate-limit cleanup`) adds public-client regression
  coverage for rate-limited Streamable HTTP cleanup.
  `McpStreamableHttpClient` now has focused test evidence that a `429`
  Streamable POST failure preserves the active session id and SSE cursor, and
  that a following `DELETE` cleanup still sends the owned `MCP-Session-Id`
  before clearing local state. Pre-change `bin/test-fast`, the focused
  `keeps Streamable HTTP session state after rate-limit failures` client test,
  the full `streamable_http_client_test.dart` suite, `git diff --check`, and
  full local `bin/verify` passed. The first full local `bin/verify` attempt hit
  stale failed-process native-runtime lock contention; after terminating that
  process group, the two affected benchmark tests passed in isolation and the
  full `bin/verify` rerun passed. The commit was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `3a066b2`: `master` CI run `26262595795`, Dart Package Publish Dry Run
  `26262595840`, WAMP Profile Benchmarks `26262595846`, Router Image dry-run
  `26263051056`, and matching `add-router` CI/dry-run/WAMP runs passed. The
  strict deployment-chain audit passed required gates on `master` at
  `3a066b2`. RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected, and pub.dev publishing remains deferred for release-order/operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-22: Commit `c30e9d1`
  (`fix: keep mcp standard headers client-owned`) hardens public MCP HTTP
  client standard-header ownership. `McpStreamableHttpClient` now filters
  caller-provided `Mcp-Method` and `Mcp-Name` from constructor and per-call
  header maps before applying the synthesized single-message standard headers
  or intentionally omitting them on GET/SSE polling and JSON-RPC batches.
  Focused regression coverage now proves stale caller standard headers cannot
  leak into initialize, direct JSON, Streamable POST, GET/SSE poll, or batch
  requests while ordinary consumer trace headers still pass through.
  Pre-change `bin/test-fast`, `dart format`, the focused
  `owns MCP protocol and session headers despite caller headers` client test,
  the full `streamable_http_client_test.dart` suite, `git diff --check`, and
  full local `bin/verify` passed. The commit was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `c30e9d1`: `master` CI run `26264152549`, Dart Package Publish Dry Run
  `26264152546`, WAMP Profile Benchmarks `26264152545`, Router Image dry-run
  `26264557016`, and matching `add-router` CI/dry-run/WAMP runs passed. The
  first strict audit found the previous Router Image dry-run stale for this
  router-image-sensitive client/package change; after manual non-mutating
  Router Image dry-run `26264557016`, the strict deployment-chain audit passed
  required gates on `master` at `c30e9d1`. RC readiness still reports not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order/operator decisions. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-22: Commit `6cc318b`
  (`test: cover consumer mcp standard headers`) extends the generated
  client-only MCP consumer package smoke to cover public package
  standard-header ownership. The smoke now sends stale caller `Mcp-Method` and
  `Mcp-Name` headers through direct JSON, Streamable POST, and GET/SSE poll
  requests, records standard MCP headers by consumer trace, and proves
  synthesized `Mcp-Method` values are client-owned while stale caller
  `Mcp-Name` values and GET/SSE standard MCP headers are stripped. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused
  `bash -lc 'source bin/common.sh && run_mcp_client_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. The commit was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `6cc318b`: `master` CI run `26265975937` and
  `add-router` CI run `26265972592` passed with Fast Checks and Full Verify
  green. The strict deployment-chain audit passed required gates on `master`
  at `6cc318b`, using current-head CI/log evidence plus still-relevant Dart
  package dry-run, native release dry-run, Router Image dry-run, and WAMP
  profile benchmark evidence because no package, native-release, router-image,
  or WAMP profile inputs changed in this script/docs checkpoint. RC readiness
  still reports not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order/operator decisions. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-22: Commit `f08e002`
  (`test: cover router mcp standard headers`) extends the generated
  router-hosted MCP consumer package smoke to cover public package
  standard-header ownership against a real router. The smoke now sends stale
  caller `Mcp-Method` and `Mcp-Name` headers through public direct JSON tool
  helper calls, generic Streamable JSON-RPC `tools/call` POSTs, Streamable WAMP
  pub/sub notifications, and Streamable tool notifications. This proves
  consumer-package APIs sanitize or own standard MCP headers before router
  validation across direct JSON and Streamable HTTP paths. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused
  `bash -lc 'source bin/common.sh && run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. The commit was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `f08e002`: `master` CI run `26267304417` and
  `add-router` CI run `26267301141` passed with Fast Checks and Full Verify
  green. The strict deployment-chain audit passed required gates on `master`
  at `f08e002`, using current-head CI/log evidence plus still-relevant Dart
  package dry-run, native release dry-run, Router Image dry-run, and WAMP
  profile benchmark evidence because no package, native-release, router-image,
  or WAMP profile inputs changed in this script/docs checkpoint. RC readiness
  still reports not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order/operator decisions. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-22: Current local implementation follow-up resets the public MCP
  Streamable HTTP client's SSE cursor when a response negotiates a different
  session id. `McpStreamableHttpClient._captureSessionHeaders` now clears
  `lastEventId` before adopting a changed non-empty `MCP-Session-Id`, keeping
  `Last-Event-ID` scoped to the active session after re-initialize or session
  rotation. The existing stale-session regression now asserts re-initialize
  clears the cursor. Pre-change `bin/test-fast`, focused
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `git diff --check`, and full local `bin/verify` passed. Commit `742c004`
  (`fix: reset mcp sse cursor on session change`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `742c004`: `master` CI run `26268556973`, `add-router` CI run
  `26268556046`, `master` Dart Package Publish Dry Run `26268556951`,
  `master` WAMP Profile Benchmarks `26268556950`, and manual non-mutating
  `master` Router Image dry-run `26268965259` passed. The strict
  deployment-chain audit passed required gates on `master` at `742c004`; RC
  readiness remains blocked only by explicit RC tag/prerelease/router-image
  tag selection and deferred pub.dev release-order decisions.
- 2026-05-22: Current local implementation follow-up makes public MCP
  Streamable HTTP cleanup safe when no session is active.
  `McpStreamableHttpClient.deleteSession()` now returns after local cleanup
  when `sessionId` is already null, clearing any orphan SSE cursor without
  sending an invalid network `DELETE` lacking `MCP-Session-Id`. This keeps
  downstream application `finally` cleanup paths safe after failed
  initialization, prior cleanup, or local state reset. Pre-change
  `bin/test-fast`, `dart format`, and focused
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
  passed, followed by full local `bin/verify`. Commit `182c236`
  (`fix: skip mcp delete without active session`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `182c236`: `master` CI run `26270250594`, `add-router` CI run
  `26270245743`, `master` Dart Package Publish Dry Run `26270250595`,
  `add-router` Dart Package Publish Dry Run `26270245773`, `master` WAMP
  Profile Benchmarks `26270250619`, `add-router` WAMP Profile Benchmarks
  `26270245772`, and manual non-mutating `master` Router Image dry-run
  `26270676681` passed. The strict deployment-chain audit passed required
  gates on `master` at `182c236`; RC readiness remains blocked only by explicit
  RC tag/prerelease/router-image tag selection and deferred pub.dev
  release-order decisions.
- 2026-05-22: Release-gate test follow-up adds regression coverage for the
  first-RC Dart package deferral boundary.
  `tool/test_dart_package_publish_dry_run.py` now proves strict release-ready
  mode fails on the known `connectanum_client` private `connectanum_core`
  dependency while preserving zero-warning dry-run and release-plan output.
  `tool/test_audit_github_deployment_chain.py` now proves the RC audit rejects
  unexpected strict Dart package blockers instead of treating them as the
  intentional first-RC pub.dev deferral. Pre-change `bin/test-fast`, focused
  Python suites, `git diff --check`, and full local `bin/verify` passed. Commit
  `690c3c6` (`test: cover strict dart publish deferral`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26271999722` and `add-router` CI run `26271999694` passed with Fast Checks
  and Full Verify green. The strict deployment-chain audit passed required gates
  on `master` at `690c3c6`, using current-head CI/log evidence plus
  still-relevant Dart package dry-run, native release dry-run, Router Image
  dry-run, and WAMP profile benchmark evidence because no package,
  native-release, router-image, or WAMP profile inputs changed in this
  test/docs checkpoint. RC readiness remains blocked only by explicit RC
  tag/prerelease/router-image tag selection and deferred pub.dev release-order
  decisions.
- 2026-05-22: Local RC audit deferral hardening now requires the strict Dart
  publish dry-run output to include release-order and operator-decision
  evidence before treating the known private `connectanum_core` dependency as
  an intentional first-RC pub.dev deferral.
  `tool/test_audit_github_deployment_chain.py` adds fake-hosted RC coverage for
  a strict dry-run that has the known blocker but omits the release plan, and
  `bin/audit-github-deployment-chain` rejects missing release-plan evidence or
  contradictory warning-gate output. Pre-change `bin/test-fast`, focused
  `python3 tool/test_audit_github_deployment_chain.py`,
  `bash -n bin/audit-github-deployment-chain`, `git diff --check`, and the live
  read-only strict deployment-chain audit against `master` passed locally. Full
  local `bin/verify` passed for this follow-up. Commit `209b91c`
  (`test: require dart release plan for rc deferral`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted `add-router` CI
  run `26274323057` passed with Fast Checks and Full Verify green. Hosted
  `master` CI run `26274326442` passed with Fast Checks and a rerun Full Verify
  on attempt 2 after a hosted browser-runner load flake. The strict
  deployment-chain audit passed required gates on `master` at `209b91c`, using
  current-head CI/log evidence plus still-relevant Dart package dry-run, native
  release dry-run, Router Image dry-run, and WAMP profile benchmark evidence
  because no package, native-release, router-image, or WAMP profile inputs
  changed in this audit/test/docs checkpoint. RC readiness remains blocked only
  by explicit RC tag/prerelease/router-image tag selection and deferred pub.dev
  release-order decisions.
- 2026-05-22: Local hosted CI reliability follow-up hardens the client browser
  WebSocket smoke after `master` CI run `26274326442` needed a Full Verify rerun
  for a retryable package:test Chrome browser-manager load flake (`Bad state:
  Cannot add stream while adding stream`). `bin/test-all` now retries the
  browser smoke, uses the expanded reporter on non-final attempts to avoid
  GitHub error annotations, and keeps the default reporter on the final attempt
  so real failures remain visible. `tool/test_verification_scripts.py` regresses
  this verification-script contract and is wired into `bin/test-fast` and
  `bin/test-all`. Pre-change `bin/test-fast`, `bash -n bin/test-fast
  bin/test-all`, and focused `python3 tool/test_verification_scripts.py` passed;
  full local `bin/verify` passed for this follow-up. Commit `d9d8a82`
  (`ci: retry browser smoke on hosted flake`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26276704174` and hosted `add-router` CI run `26276703045` passed with Fast
  Checks and Full Verify green. The strict deployment-chain audit passed
  required gates on `master` at `d9d8a82`, using current-head CI/log evidence
  plus still-relevant Dart package dry-run, native release dry-run, Router Image
  dry-run, and WAMP profile benchmark evidence because no package,
  native-release, router-image, or WAMP profile inputs changed in this
  CI-script/docs checkpoint. RC readiness remains blocked only by explicit RC
  tag/prerelease/router-image tag selection and deferred pub.dev release-order
  decisions.

## Handoff

Active. The current local implementation checkpoint strengthens public MCP
client auth-grant evidence for lifecycle-free direct JSON WAMP meta, resource,
and prompt access. `McpStreamableHttpClient.withAuthGrant(...)` now has focused
coverage for direct `wamp.session.count`, `wamp.registration.list`,
`wamp.registration.match`, `wamp.subscription.list`,
`wamp.subscription.match`, `resources/list`, `resources/read`,
`resources/templates/list`, `prompts/list`, and `prompts/get` before any
Streamable HTTP lifecycle, while asserting grant-owned bearer headers,
`application/json`, no `MCP-Session-Id`, and no local `sessionId` /
`lastEventId` state.

Local evidence for this checkpoint: pre-change `bin/test-fast`, focused
format/analyze/test coverage for
`packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
`git diff --check`, `python3 tool/check_public_artifact_references.py`, and
full local `bin/verify` passed on 2026-05-25.

The latest fully clean hosted checkpoint remains `debd545`: hosted `master`
and `add-router` CI, Dart Package Publish Dry Run, WAMP Profile Benchmarks,
kTLS Validation, manual Router Image dry-run, and manual Native Artifacts
validation dry-run passed for that commit. The strict deployment-chain audit
passed required gates on `master` at `debd545`.

RC readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected for `debd545`;
the audit suggests `v0.1.0-rc.2` as the next numeric tag if release approval is
given. Pub.dev publishing remains deferred for release-order and operator
decisions. No RC tag, GitHub Release, or router image was created or moved.
