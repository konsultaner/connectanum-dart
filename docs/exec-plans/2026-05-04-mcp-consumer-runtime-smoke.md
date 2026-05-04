# Exec Plan: MCP Consumer Runtime Smoke

Status: complete; local verification clean; hosted evidence pending for latest WAMP meta-helper commit
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
- Exercise typed WAMP API/meta discovery helpers from the consumer package,
  including procedure/topic catalog lookup, registration lookup/details,
  session counting, and subscription lookup/details.
- Exercise direct JSON-RPC WAMP pub/sub subscribe/publish/poll/unsubscribe from
  the consumer package.
- Exercise initialized Streamable MCP tool listing/calling, WAMP pub/sub helper
  polling, and Streamable HTTP session lifecycle from the consumer package.
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
- Hosted evidence is pending for the latest WAMP meta-helper implementation
  commit.
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

Latest implementation and local verification are complete. Hosted GitHub CI
evidence is pending for the WAMP meta-helper commit.
