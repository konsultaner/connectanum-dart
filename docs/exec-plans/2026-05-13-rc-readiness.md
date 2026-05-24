# Exec Plan: Release Candidate Readiness

Status: active
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-24

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
  local `bin/verify` passed for this checkpoint.
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

Active. The current local implementation checkpoint strengthens
router-hosted MCP auth/session evidence for the bearer-protected
JSON-response route at `/mcp/secure-json-post`. The checked-in router
integration smoke, public example, and generated consumer-package smoke now
prove that a second valid bearer principal cannot reuse the owner
`MCP-Session-Id`, and can then use public MCP HTTP helpers to access the
direct JSON catalog, initialize a distinct Streamable HTTP session, keep
JSON-response POSTs cursor-free, list tools, and delete its own session
without mutating the owner session.

Local evidence for this checkpoint: pre-change `bin/test-fast`, focused
analyzer coverage for the example and router integration smoke, the focused
native router MCP route-security test, the public router-hosted MCP example
smoke, the generated consumer-package smoke, `bash -n bin/common.sh`,
`python3 tool/check_public_artifact_references.py`, `git diff --check`,
post-change `bin/test-fast`, and full local `bin/verify` passed on
2026-05-24.

The latest fully clean hosted checkpoint remains `bc2575c`: hosted `master` CI
run `26355702455` and hosted `add-router` CI run `26355702355` passed with
Fast Checks and Full Verify green. Dart Package Publish Dry Run
`26355702488` on `master` and `26355702383` on `add-router` passed at
`bc2575c`; WAMP Profile Benchmarks `26355702451` on `master` and
`26355702340` on `add-router` passed at `bc2575c`; manual non-mutating Router
Image dry-run `26355974643` passed on `master` at `bc2575c`; Native Artifacts
dry-run `26286794628` remains relevant. The strict deployment-chain audit
passed required gates on `master` at `bc2575c`.

RC readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; the audit
suggests `v0.1.0-rc.2` as the next numeric tag if release approval is given.
Pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
