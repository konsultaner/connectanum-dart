# Exec Plan: Router Image Stateless Public Client Smoke

## Status

Completed.

## Goal

Make the shipped `connectanum_mcp:router_hosted_client` executable prove the
current stateless `2026-07-28` router-hosted MCP path against the loaded Router
Image, instead of leaving modern direct tool, WAMP Meta API, and pub/sub
evidence exclusively to the raw protocol probe.

## Scope

- Let the public executable select its existing stateless client constructors
  for `2026-07-28` while retaining session-era constructors for `2025-*`.
- Run discovery plus typed direct JSON tool, WAMP Meta API, and pub/sub helpers
  without initialize, batches, protocol sessions, resume cursors, or DELETE.
- Keep the existing compatibility-era public/protected executable runs as the
  Streamable HTTP, session deletion, and ticket refresh/revoke gate.
- Add public and bearer-protected stateless executable runs to the canonical
  loaded-image smoke and require explicit modern lifecycle-free evidence.
- Preserve the raw Python compatibility guard and the final non-publishing
  multi-architecture image build.

## Non-Goals

- Change router MCP dispatch, auth, WAMP Meta API, or pub/sub semantics.
- Add experimental MCP tasks or another protocol extension.
- Remove the `2025-*` Streamable HTTP compatibility path.
- Add application-specific data, credentials, or filesystem assumptions.
- Publish or retag a Router Image.

## Verification

- Public executable source-contract and dry-run regressions.
- Focused Router Image smoke contract regressions.
- Public and protected stateless executable runs against a real local native
  router and, when available, the locally loaded Router Image.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head CI, package dry run, WAMP benchmarks, Router Image dry run, and
  strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-03: Selected after reviewing project state, both roadmaps, the
  official current and draft Streamable HTTP direction, the public client and
  router symbols, and the completed loaded-image evidence. The package client
  already supports the stateless protocol and standard routing headers, but
  the shipped executable rejects `2026-07-28`, so modern image evidence still
  depends on the raw Python probe.
- 2026-08-03: Pre-change `bin/test-fast` passed at exact local, GitLab, and
  GitHub head `80c9555`, including all native/router integration, MCP/client,
  live WAMP benchmark, generated consumer, globally activated executable, and
  router CLI consumer gates.
- 2026-08-03: Focused source-contract regressions first failed because the
  executable rejected `2026-07-28` and the loaded-image runner invoked only
  the compatibility-era lifecycle. The public executable now selects its
  stateless constructors for the modern version, discovers server support,
  runs typed direct tools, WAMP metadata, and pub/sub, and proves it retained
  no session id or resume cursor. Session-only auth lifecycle and resource
  subscription options fail before network access in stateless mode.
- 2026-08-03: The loaded-image runner now keeps the public and protected
  compatibility-era executable runs and adds public and ticket-authenticated
  stateless runs with explicit protocol, sessionless, direct-tool, WAMP Meta
  API, and pub/sub evidence. The package README and changelog describe the
  consumer-facing executable mode with neutral examples.
- 2026-08-03: All 33 focused Python contracts, shell syntax, package analysis,
  all 94 MCP tests, the focused 114-case client suite, and real executable
  dry-run validation pass. Public and protected stateless executions against
  the current local native router completed discovery, direct tools, complete
  standard WAMP metadata, and pub/sub with `sessionless: true`.
- 2026-08-03: An older cached Router Image failed the pre-existing raw probe
  because its protected unauthorized-session response leaked a session header.
  The current native router passed that same complete raw probe. A fresh local
  image build again remained blocked resolving the upstream Dockerfile
  frontend, so exact fresh-image evidence remains assigned to the hosted
  Router Image dry run.
- 2026-08-03: Post-change `bin/test-fast` passed, including the focused
  contracts, 20 native integration tests, 22 consumer integration tests, 360
  core tests, all 94 MCP tests, the complete 193-case MCP/client suite, all 96
  benchmark tests with 36 live WAMP workloads, generated and globally
  activated package smokes, the complete router CLI consumer smoke, and
  focused native/auth/session follow-ups.
- 2026-08-03: Final local `bin/verify` passed formatting with 393 files and no
  rewrites, analysis, 113 Rust core tests, 52 Rust FFI tests, 360 Dart core
  tests, all 94 MCP tests, the complete 193-case MCP/client suite, all 96
  benchmark tests, the complete 380-case router suite, the 13-case native
  follow-up, every generated and globally activated package smoke, and
  Chrome/Dart2Wasm.
- 2026-08-03: Commit `519a8e0` was pushed to GitLab and GitHub. Exact-head CI
  `30778403924`, Dart Package Publish Dry Run `30778403858`, Router Image dry
  run `30778430327`, and WAMP Profile Benchmarks `30778435730` all passed. CI
  uploaded coverage artifact `8843009435`, Router Image uploaded preview
  artifact `8842836960`, and WAMP uploaded benchmark artifact `8842923179`.
- 2026-08-03: The hosted fresh-image smoke retained the raw public/protected
  protocol probe and then ran the shipped executable in stateless mode against
  both endpoints. Both executions reported protocol `2026-07-28`,
  `sessionless: true`, discovery support, direct tools, configured WAMP Meta
  API, and pub/sub before the compatibility-era executable runs and final
  non-publishing multi-architecture build also passed.
- 2026-08-03: The comprehensive strict deployment-chain audit exited clean
  with exact-head CI and log cleanliness, package dry run, relevant native
  release evidence, Router Image dry run, WAMP artifacts, workflow visibility,
  branch protection, and public router-package visibility ready. Selecting the
  suggested follow-up RC tag remains an approval-gated release action outside
  this plan.
