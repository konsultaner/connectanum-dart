# Exec Plan: MCP Public Client Auth-Method Parity

Status: active
Owner: Codex
Created: 2026-08-16
Last updated: 2026-08-16

## Goal

Let the published router-hosted MCP client authenticate through every
challenge method already supported by the public router HTTP-auth client:
ticket, WAMP-CRA, and SCRAM. Preserve challenge-discovered auth endpoints,
explicit endpoint overrides, bearer grants, and both modern sessionless and
compatibility-era Streamable HTTP behavior.

## Scope

- In scope:
  - retain the existing `--ticket` contract;
  - add mutually exclusive WAMP-CRA and SCRAM secret options;
  - issue the selected grant through public `ConnectanumHttpAuthClient`
    helpers after the same credential-free challenge discovery;
  - make dry-run and lifecycle evidence identify the selected method without
    exposing secret material;
  - prove source and globally activated package execution against a real
    router-hosted protected MCP endpoint.
- Out of scope:
  - OAuth browser authorization changes;
  - encrypted secret storage or refresh scheduling;
  - adding router authentication methods not already supported by the public
    HTTP-auth client.

## Files Expected To Change

- `packages/connectanum_mcp/lib/src/cli/router_hosted_client.dart`
- `packages/connectanum_router/example/router_hosted_mcp.dart`
- `bin/common.sh`
- `tool/test_mcp_consumer_package_boundary.py`
- `ROADMAP.md`
- `docs/project_state.md`

## Preconditions

- The scheduled launchd wrapper and its current Codex child are the expected
  run; no unrelated process is editing this repository.
- The inherited documentation-only hosted evidence for commit `7fbc82f`
  remains intentional and will be bundled with this implementation.
- Pre-change `bin/test-fast` passes on 2026-08-16.

## Plan

1. Add fail-first dry-run and package-boundary expectations for WAMP-CRA and
   SCRAM credentials, mutual exclusion, and secret redaction.
2. Generalize challenge-discovered grant issuance and auth lifecycle handling
   while retaining ticket and bearer compatibility.
3. Run focused package/static checks plus real-router source and globally
   activated client smokes for both added methods.
4. Run canonical verification, record the milestone, publish it, and collect
   exact-head hosted workflow and strict deployment-chain evidence.

## Verification

- `python3 -m unittest tool.test_mcp_consumer_package_boundary`
- focused public router-hosted MCP dry-run and live smoke helpers
- `bin/test-fast`
- `bin/verify`
- exact-head hosted CI and deployment-chain strict audit after publication

## Decision Log

- 2026-08-16: Selected this as the next downstream-readiness gap because the
  router and public HTTP-auth client already support ticket, WAMP-CRA, and
  SCRAM, while the published router-hosted MCP executable proves only ticket
  grants.
- 2026-08-16: Use mutually exclusive `--ticket`, `--wampcra-secret`, and
  `--scram-secret` options. This keeps existing ticket invocations compatible
  and prevents a separate method selector from disagreeing with the supplied
  secret kind.

## Progress

- 2026-08-16: Serena preflight and overlap checks passed. Local, GitLab, and
  GitHub `master` start at `7fbc82f`; only the preceding checkpoint's two
  documentation-evidence files were modified at startup.
- 2026-08-16: Pre-change `bin/test-fast` passes the complete fast regression,
  package, benchmark, router, generated-consumer, and globally activated
  executable matrix, including all 97 benchmark tests and 37 live WAMP
  workloads.
- 2026-08-16: Fail-first execution rejected `--wampcra-secret` as unknown and
  both focused package-boundary contracts failed before implementation.
- 2026-08-16: The published client now selects ticket, WAMP-CRA, or SCRAM
  through one method-neutral challenge-discovered HTTP-auth path. Dry-run,
  discovery, and lifecycle evidence identify the method while retaining secret
  redaction and mutual-exclusion validation.
- 2026-08-16: Router example coverage exposes all three authenticators on the
  protected MCP session profile. The source WAMP-CRA compatibility run and
  globally activated modern SCRAM run both pass authentication, refresh and
  revocation, direct JSON tools, WAMP meta operations, and pub/sub against the
  real router.
- 2026-08-16: Focused analysis, shell syntax, all 22 package-boundary tests,
  the complete dry-run helper, and the complete live helper pass. Canonical
  post-change verification remains.
- 2026-08-16: Post-change `bin/test-fast` passes the complete fast regression,
  package, benchmark, router, generated-consumer, and globally activated
  executable matrix, including the new WAMP-CRA and SCRAM live runs.
- 2026-08-16: Canonical `bin/verify` passes with zero formatting changes, 117
  Rust core/serializer tests, 52 native FFI tests, the feature-gated metrics
  snapshot, 366 Dart core tests, 116 MCP tests, the complete 296-case
  MCP/client suite, all 97 benchmark tests including 37 live WAMP workloads,
  all 454 router cases, six remote-auth tests, 13 native follow-ups, every
  maintained consumer/global-activation smoke, Chrome, and Dart2Wasm.

## Handoff

- Active. Implementation, focused real-router evidence, and canonical local
  verification pass; publication and hosted deployment-chain evidence remain.
