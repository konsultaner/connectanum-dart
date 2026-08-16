# Exec Plan: MCP Public Client Auth-Endpoint Discovery

Status: active
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Let the published router-hosted MCP client obtain a ticket grant from the
router-advertised compatible HTTP-auth route when a consumer supplies realm,
auth ID, and ticket credentials without separately hard-coding `--auth-url`.

## Scope

- In scope:
  - make `--auth-url` an optional override for ticket credentials;
  - probe the protected MCP endpoint without credentials or Streamable session
    state and require a compatible Bearer challenge with `auth_path`;
  - construct the public auth client through
    `ConnectanumHttpAuthClient.fromMcpBearerChallenge`;
  - preserve explicit endpoint, raw bearer, refresh/revoke, direct JSON,
    Streamable HTTP, WAMP meta, and pub/sub behavior;
  - prove discovery in dry-run validation and the maintained live public-client
    smoke without exposing credentials.
- Out of scope:
  - selecting or persisting consumer credentials;
  - OAuth authorization-server discovery changes;
  - accepting cross-origin or non-path auth references.

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/cli/router_hosted_client.dart`
- `bin/common.sh`
- `tool/test_mcp_consumer_package_boundary.py`
- `docs/project_state.md`
- `ROADMAP.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- The inherited documentation-only hosted evidence for commit `2de11049`
  remains intentional and will be bundled with this implementation.
- Pre-change `bin/test-fast` passes on 2026-08-16.

## Plan

1. Add fail-first dry-run and live-smoke expectations for complete ticket
   credentials without `--auth-url`.
2. Implement a credential-free, sessionless challenge probe and compatible
   challenge selection for the published client, retaining explicit URL as an
   override.
3. Run focused CLI/boundary checks, the fast gate, and canonical verification.
4. Record the material milestone, publish it, and collect exact-head hosted
   workflow and strict deployment-chain evidence.

## Verification

- `python3 -m unittest tool.test_mcp_consumer_package_boundary`
- focused public router-hosted MCP dry-run and live smoke helpers
- `bin/test-fast`
- `bin/verify`
- exact-head hosted CI and deployment-chain strict audit after publication

## Decision Log

- 2026-08-16: Selected this as the next shipped-path readiness gap because the
  public auth factory can now consume `auth_path`, but the published client
  still requires consumers to provide the same endpoint separately.
- 2026-08-16: Keep an explicit `--auth-url` override for non-router endpoints
  and deterministic deployment configuration. Discovery is used only when the
  complete ticket credential tuple is present and no override was supplied.

## Progress

- 2026-08-16: Serena preflight and overlap checks passed. Both maintained
  `master` refs start at `2de11049`; only the preceding checkpoint's two
  documentation-evidence files were modified at startup.
- 2026-08-16: Pre-change `bin/test-fast` passes the complete fast regression,
  package, benchmark, router, generated-consumer, and globally activated
  executable matrix, including all 97 benchmark tests and 37 live WAMP
  workloads.
- 2026-08-16: Fail-first dry-run coverage rejected complete ticket credentials
  without `--auth-url`. The maintained live smoke also reproduced the missing
  discovery path before implementation.
- 2026-08-16: The published client now treats `--auth-url` as an optional
  override. Without it, the client sends a credential-free sessionless ping to
  the protected MCP endpoint, requires a realm-matched Bearer challenge with
  `auth_path`, and constructs `ConnectanumHttpAuthClient` through the public
  challenge factory before sending ticket credentials.
- 2026-08-16: Focused package analysis and all 22 consumer-boundary tests pass.
  The live public-client smoke proves source and globally activated execution,
  discovered ticket authentication, refresh/revoke lifecycle, direct JSON,
  Streamable HTTP, WAMP meta, and pub/sub behavior. Mismatched-realm and
  unprotected endpoints fail closed without printing the ticket.
- 2026-08-16: Post-change `bin/test-fast` passes the complete regression,
  package, benchmark, router, generated-consumer, and globally activated
  executable matrix, including all 97 benchmark tests and 37 live WAMP
  workloads.
- 2026-08-16: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer tests, 52 native FFI tests, the feature-gated native
  metrics snapshot, 366 Dart core tests, 116 MCP tests, the complete 296-case
  MCP/client suite, all 97 benchmark tests including 37 live WAMP workloads,
  all 454 router cases, six remote-auth tests, 13 native follow-ups, every
  maintained consumer/global-activation smoke, Chrome, and Dart2Wasm.

## Handoff

- Active. Implementation and all local verification pass. Publication,
  exact-head hosted workflows, and the comprehensive strict deployment-chain
  audit remain.
