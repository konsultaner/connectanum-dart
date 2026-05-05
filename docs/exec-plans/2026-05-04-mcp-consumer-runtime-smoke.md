# Exec Plan: MCP Consumer Runtime Smoke

Status: complete; hosted evidence clean
Owner: Codex
Created: 2026-05-04
Last updated: 2026-05-04

## Goal

Prove that a neutral downstream Dart package can use only public
`connectanum_client`, `connectanum_mcp`, and `connectanum_router` entrypoints to
host and call a router-backed MCP endpoint, not just resolve imports or
construct API objects. The current smoke also proves a bearer-protected
router-hosted MCP route from the same neutral consumer package.

## Scope

In scope:

- Upgrade the temporary consumer package smoke to start a native router when a
  native runtime library is available.
- Register a WAMP procedure through a public internal router session and expose
  it through public and bearer-protected router-hosted MCP HTTP routes.
- Exercise the HTTP ticket-auth bridge from the consumer package, including
  unauthenticated rejection on the protected MCP route and bearer-token use for
  direct JSON and Streamable HTTP requests.
- Exercise direct JSON-RPC tool listing/calling from the consumer package.
- Exercise mixed direct JSON-RPC batches from the consumer package, including
  API catalog lookup, direct procedure calls, configured resources/prompts, and
  notification response omission without capturing Streamable session state.
- Exercise configured MCP resources, resource templates, and prompts from the
  consumer package through direct JSON and initialized Streamable MCP on public
  and bearer-protected routes.
- Exercise typed WAMP API/meta discovery helpers from the consumer package,
  including procedure/topic catalog lookup, registration lookup/details,
  session counting, and subscription lookup/details.
- Exercise direct JSON-RPC WAMP pub/sub subscribe/publish/poll/unsubscribe from
  the consumer package.
- Exercise initialized Streamable MCP tool listing/calling, WAMP pub/sub helper
  polling, and Streamable HTTP session lifecycle from the consumer package.
- Exercise mixed initialized Streamable HTTP batches from the consumer package,
  including tool listing/calling, configured resources/prompts, notification
  response omission, and session-prefixed SSE event-state updates.
- Prove Streamable HTTP `GET`/SSE polling, `Last-Event-ID` resume behavior, and
  `DELETE` session cleanup through public consumer APIs.
- Preserve the existing public API construction fallback when no native runtime
  is available.

Out of scope:

- Adding private downstream application references.
- Replacing the canonical router-hosted MCP package example.
- Changing native artifact publishing or package release order.

## Plan

1. Run the pre-change fast baseline.
2. Extend `run_mcp_consumer_package_smoke` so the generated consumer app can
   host public and bearer-protected router-backed MCP endpoints with public
   package APIs.
3. Run the focused consumer smoke.
4. Run `bin/test-fast` and `bin/verify`.
5. Push and collect hosted CI/deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-04.
- Focused consumer package smoke passed on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
- Post-change `bin/test-fast` passed on 2026-05-04 and included the upgraded
  protected runtime consumer package smoke.
- The latest Streamable HTTP lifecycle extension passed the focused consumer
  package smoke on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
  It proves that a neutral consumer package can capture the router-provided
  MCP session id, receive `tools/list_changed` over Streamable HTTP `GET`/SSE
  after registering a dynamic WAMP procedure, resume with `Last-Event-ID`
  without replaying the old event, and delete the MCP session.
- Latest local `bin/test-fast` passed on 2026-05-04 after the Streamable HTTP
  lifecycle extension.
- Latest local `bin/verify` passed on 2026-05-04 after the Streamable HTTP
  lifecycle extension. It included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client tests, auth-server tests,
  bench integration tests, the router-hosted MCP example smoke, the upgraded
  protected consumer runtime smoke with Streamable HTTP session lifecycle,
  full router package tests including router-hosted MCP auth/session coverage,
  zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
- The latest WAMP meta-helper extension passed the focused consumer package
  smoke on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
  It proves that the neutral consumer package can use typed WAMP API and
  standard meta helpers through both direct JSON and initialized Streamable MCP
  to discover procedures/topics, resolve registration and subscription details,
  and count route-visible sessions.
- Latest local `bin/test-fast` passed on 2026-05-04 after the WAMP meta-helper
  extension.
- Latest local `bin/verify` passed on 2026-05-04 after the WAMP meta-helper
  extension. It included formatting, Rust native/FFI tests, Python
  package-artifact checks, MCP package tests, client tests, auth-server tests,
  bench integration tests, the router-hosted MCP example smoke, the upgraded
  protected consumer runtime smoke with WAMP meta helpers and Streamable HTTP
  session lifecycle, full router package tests including router-hosted MCP
  auth/session coverage, zero-copy router checks, and Chrome Dart2Wasm
  WebSocket transport tests.
- The latest resource/prompt consumer-smoke extension passed the focused
  consumer package smoke on 2026-05-04:
  `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
  It proves that the neutral consumer package can configure MCP resources,
  resource templates, and prompts on public and bearer-protected router-hosted
  MCP routes, advertise those capabilities during Streamable initialization,
  exercise `resources/list`, `resources/read`, `resources/templates/list`,
  `prompts/list`, and `prompts/get` through both direct JSON and initialized
  Streamable MCP, and keep direct JSON helper use session-free.
- Latest local `bin/test-fast` passed on 2026-05-04 after the resource/prompt
  consumer-smoke extension.
- Latest local `bin/verify` passed on 2026-05-04 after the resource/prompt
  consumer-smoke extension. It included formatting, Rust native/FFI tests,
  Python package-artifact checks, MCP package tests, client tests,
  auth-server tests, bench integration tests, the router-hosted MCP example
  smoke, the upgraded protected consumer runtime smoke with configured
  resources/prompts, WAMP meta helpers, and Streamable HTTP session lifecycle,
  full router package tests including router-hosted MCP auth/session coverage,
  zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
- Commit `cb63df1` was pushed to both remotes. Hosted GitHub `CI` run
  `25340546748` completed successfully with `Fast Checks` and `Full Verify`.
  The deployment-chain audit with required clean latest CI, clean hosted CI
  logs, and clean Dart package publish dry-run passed for branch head
  `cb63df1`. `Dart Package Publish Dry Run` and `WAMP Profile Benchmarks` did
  not trigger for this script/docs change; the latest package dry-run remains
  clean and relevant on `207be91` because no publish-sensitive paths changed.
  The remaining audit findings are the existing operator/deployment items
  around branch protection, default-branch router workflow visibility, and
  GHCR router package visibility.
- The latest batch-smoke extension passed local `bin/test-fast` and full local
  `bin/verify` on 2026-05-05.
  The generated consumer package now proves mixed direct JSON-RPC batches and
  initialized Streamable HTTP batches against both public and bearer-protected
  router-hosted MCP routes. The direct JSON batch path proves API catalog
  lookup, direct procedure calls, configured resources/prompts, notification
  response omission, and no Streamable session state capture. The Streamable
  batch path proves tool listing/calling, configured resources/prompts,
  notification response omission, and a session-prefixed SSE event id update
  through the public consumer client API. Full verify included formatting,
  Rust native/FFI tests, Python package-artifact checks, MCP package tests,
  client tests, auth-server tests, bench integration tests, the router-hosted
  MCP example smoke, the upgraded protected consumer runtime smoke with
  batch/resources/prompts/WAMP meta/session-lifecycle coverage, full router
  package tests including router-hosted MCP auth/session/batch coverage,
  zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
- Commit `4847124` was pushed to both remotes. Hosted GitHub `CI` run
  `25363296633` completed successfully with `Fast Checks` and `Full Verify`.
  The hosted log audit found no actionable warnings, skipped tests,
  deprecations, panics, broken pipes, connection errors, or GitHub annotation
  errors/warnings. Broad failed/error word matches were benign passing test
  names and expected error-path coverage. `Dart Package Publish Dry Run` and
  `WAMP Profile Benchmarks` did not trigger for this script/docs change; the
  latest package dry-run and WAMP benchmark workflows remain clean and relevant
  on `207be91` because no publish-sensitive or benchmark-sensitive package
  paths changed.
- Commit `e826f7e` was pushed to both remotes. Hosted GitHub `CI` run
  `25338108663` completed successfully with `Fast Checks` and `Full Verify`.
  The deployment-chain audit with required clean latest CI, clean hosted CI
  logs, and clean Dart package publish dry-run passed for branch head
  `e826f7e`. `Dart Package Publish Dry Run` and `WAMP Profile Benchmarks` did
  not trigger for this script/docs change; the latest package dry-run remains
  clean and relevant on `207be91` because no publish-sensitive paths changed.
  The remaining audit findings are the existing operator/deployment items
  around branch protection, default-branch router workflow visibility, and
  GHCR router package visibility.
- Commit `95956f3` was pushed to both remotes. Hosted GitHub `CI` run
  `25336128328` completed successfully with `Fast Checks` and `Full Verify`.
  The deployment-chain audit with required clean latest CI, clean hosted CI
  logs, and clean Dart package publish dry-run passed for branch head
  `95956f3`. `Dart Package Publish Dry Run` and `WAMP Profile Benchmarks` did
  not trigger for this script/docs change; the latest package dry-run remains
  clean and relevant on `207be91` because no publish-sensitive paths changed.
  The remaining audit findings are the existing operator/deployment items
  around branch protection, default-branch router workflow visibility, and
  GHCR router package visibility.
- Commit `d8310ac` was pushed to both remotes. Hosted GitHub `CI` run
  `25334205849` completed successfully with `Fast Checks` and `Full Verify`.
  The deployment-chain audit with required clean latest CI, clean hosted CI
  logs, and clean Dart package publish dry-run passed for branch head
  `d8310ac`. `Dart Package Publish Dry Run` and `WAMP Profile Benchmarks` did
  not trigger for this script/docs change; the latest package dry-run remains
  clean and relevant on `207be91` because no publish-sensitive paths changed.
  The remaining audit findings are the existing operator/deployment items
  around branch protection, default-branch router workflow visibility, and
  GHCR router package visibility.
- Previous commit `693f930` was pushed to both remotes. Hosted GitHub `CI` run
  `25332159136` completed successfully with `Fast Checks` and `Full Verify`.
  The deployment-chain audit with required clean latest CI and clean hosted CI
  logs passed for branch head `693f930`. `Dart Package Publish Dry Run` and
  `WAMP Profile Benchmarks` did not trigger for this script/docs change; the
  latest package dry-run remains clean and relevant on `207be91` because no
  publish-sensitive paths changed. The remaining audit findings are the
  existing operator/deployment items around branch protection, default-branch
  router workflow visibility, and GHCR router package visibility.

## Handoff

Implementation, local verification, and hosted GitHub CI evidence are complete.
