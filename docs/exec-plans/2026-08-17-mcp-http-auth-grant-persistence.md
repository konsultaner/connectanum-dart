# Exec Plan: MCP HTTP-Auth Grant Persistence

Status: completed
Owner: Codex
Created: 2026-08-17
Last updated: 2026-08-17

## Goal

Make router-issued HTTP-auth grants safe to persist and restore across consumer
application restarts without losing issuer provenance, authorization lineage,
or expiry semantics.

## Scope

- Add an explicit, versioned JSON state contract for
  `ConnectanumHttpAuthGrant` that keeps the exact issuing auth endpoint,
  identity/role/method/provider lineage, details, issue time, and absolute
  access/refresh expiry times.
- Require restored state to match an expected auth endpoint and, when supplied,
  the target MCP HTTP origin before any credential is accepted.
- Reject malformed, unsupported, future-dated, internally inconsistent, or
  non-JSON state through a typed exception whose messages do not reveal token
  values.
- Keep the existing auth-response parser and raw bearer/raw refresh APIs
  compatible. State serialization deliberately contains credentials; durable
  storage and encryption remain the consumer application's responsibility.
- Prevent grant-aware MCP client construction/replacement from accepting a
  known-expired access token and prevent grant-aware refresh from sending a
  known-expired refresh token. Grants without expiry metadata keep their
  existing compatibility behavior.
- Exercise the public state round trip from an isolated consumer package and
  the maintained router-hosted MCP live smoke.

## Preconditions

- The expected launchd wrapper, its current `codex exec` child, and live
  runlock are the scheduled run, not an overlap. No unrelated Codex process is
  editing this repository and no startup conflict is present.
- Serena instructions, project activation, and onboarding checks pass.
- `docs/project_state.md`, this branch's completed execution plans,
  `ROADMAP_NEXT.md`, and the MCP readiness context in `ROADMAP.md` have been
  reviewed.
- `bin/test-fast` passes before source changes, including 366 core tests, 117
  MCP tests, 314 client/MCP tests, 97 benchmark tests with 37 live WAMP
  workloads, and every maintained generated-consumer/router CLI smoke.

## Plan

1. Add fail-first client tests for JSON round trips, endpoint/origin pins,
   absolute expiry preservation, tamper rejection, token-redacted errors, and
   expired grant-aware use.
2. Implement the versioned state helpers and grant lifetime checks while
   preserving the current response and raw-token surfaces.
3. Extend public exports/package-boundary checks and the generated consumer
   smoke so a package-only application persists, restores, uses, refreshes,
   and revokes a router-issued grant.
4. Update public package guidance and durable project state only where the
   implementation materially changes the supported surface.
5. Run focused formatting, analysis, tests, package-boundary checks, affected
   live smokes, and canonical `bin/verify`.
6. Commit code and bookkeeping together, run the strict clean-tree package
   audit, publish to both maintained remotes, then require exact-head hosted CI
   and package evidence plus the deployment-chain audits.

## Progress

- 2026-08-17: Preflight and the required pre-change `bin/test-fast` baseline
  pass. Symbol-aware review confirms that issued grants retain relative expiry
  durations but have no issue time, absolute expiry, state schema, or restore
  pins; a restart therefore cannot recover the issuer-bound grant safely.
- 2026-08-17: Fail-first client regressions now cover JSON round trips, exact
  issuer and MCP-origin pins, absolute expiry preservation, strict schema and
  consistency checks, token-redacted failures, and pre-I/O rejection of
  known-expired access and refresh grants. The public MCP IO entrypoint and
  generated router CLI consumer both persist and restore a real router-issued
  grant before direct JSON, Streamable HTTP, pub/sub, refresh, and revocation.
- 2026-08-17: Focused analysis and tests pass, including the combined 208-case
  HTTP-auth/Streamable client suite, all 15 public IO-entrypoint tests, all 23
  consumer-boundary checks, and the isolated router CLI consumer smoke.
  Canonical `bin/verify` passes with zero formatting changes, 117 Rust
  core/serializer checks, all 52 FFI tests plus metrics mode, 366 Dart core
  tests, 117 MCP package tests, the complete 318-case client/MCP suite, all 97
  benchmark tests with 37 live WAMP workloads, all 454 router tests, six
  remote-auth tests, 13 native follow-ups, every maintained generated and
  globally activated consumer smoke, Chrome, and Dart2Wasm. The 20-case
  release-package and 22-case deployment-audit regressions plus all 34 router-
  image smoke contracts also pass inside verification.
- 2026-08-17: Clean-tree strict release readiness passes all seven publishable
  packages with zero warnings. Commit `a577ed17` (`Persist router HTTP auth
  grants safely`) is published to both maintained feature-branch remotes.
  Exact-head GitHub `CI` run `31996897743` passes Fast Checks job `95290054438`,
  Full Verify job `95291420053`, and Dart VM Coverage job `95291420264`;
  retained coverage artifact `9277433897` has digest
  `sha256:fb61f0e2ac8d602e88bafe7b171d43df0d2152bf1368e1bbbbf80ba4e2bb6cf4`.
  Dart Package Publish Dry Run `31996897741` passes job `95290054489` and
  covers the exact head.
- 2026-08-17: The feature-branch deployment-chain audit passes exact-head
  CI/job/log cleanliness, current package-run relevance, checked-in workflow
  visibility, and public router-package visibility. The comprehensive strict
  protected-release baseline also passes from an isolated `master` worktree at
  `ec53a327`; its missing newly authorized RC tag remains intentionally non-
  gating.

## Handoff

- Completed. Implementation, local verification, clean-tree package readiness,
  publication, exact-head hosted workflows, retained coverage evidence, the
  feature-branch deployment audit, and the strict protected-release baseline
  pass.
