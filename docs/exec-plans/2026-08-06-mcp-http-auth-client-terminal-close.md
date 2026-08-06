# MCP HTTP Auth Client Terminal Close

Status: complete

## Goal

Make `ConnectanumHttpAuthClient.close()` a terminal lifecycle boundary for
router HTTP-auth challenge, token, refresh, and revocation work, including
requests already in flight through a caller-owned shared `HttpClient`.

## Context

The public Streamable HTTP client now rejects new network work after close and
cancels ordinary MCP plus OAuth requests waiting for headers or response-body
completion. The adjacent router HTTP-auth helper still only closes an owned
transport. With a caller-owned transport, close currently does nothing: new
requests can start, an in-flight request can survive shutdown, and a two-step
authentication operation can resume with its token request after close.

The owning HTTP transport must remain usable by a replacement auth client.
Close should cancel the auth-client operation, not broaden ownership to the
caller-provided transport or leak credentials in lifecycle errors.

## Plan

1. Preserve the green fast-suite baseline and add fail-first regressions for
   new work after close, requests blocked on response headers or response-body
   completion, and two-step authentication paused between challenge and token
   requests.
2. Add terminal operation/request ownership to `ConnectanumHttpAuthClient`,
   keeping repeated close safe and caller-owned transport reuse intact.
3. Extend the neutral client-only package smoke so an installed consumer proves
   pending router-auth cancellation and replacement-client reuse without
   private project assumptions.
4. Run focused auth-client tests, package-boundary checks, `bin/test-fast`, and
   `bin/verify`.
5. Update project state, bundle the prior hosted-evidence notes with the
   implementation commit, push both maintained branches, and audit the
   exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast` passed on 2026-08-06.
- The fail-first lifecycle suite reproduced all four missing boundaries: close
  accepted new auth work, left challenge/refresh/revoke requests waiting for
  response headers, left a refresh response-body read pending, and did not
  cancel authentication paused between challenge and token requests.
- Focused analysis passed with no issues. The existing HTTP-auth suite plus the
  lifecycle suite passed all 16 cases.
- All 19 generated-consumer source contracts passed. The source neutral
  client-only package smoke passed pending revoke cancellation and replacement
  auth-client reuse of a caller-owned shared HTTP transport.
- Post-change `bin/test-fast` passed on 2026-08-06.
- `bin/verify` passed on 2026-08-06 with no formatting changes: 113 Rust core
  tests plus serializer integration cases, 52 Rust FFI tests, 360 Dart core
  tests, all 94 MCP tests, the complete 247-case MCP/client suite, all 96
  benchmark tests including live router workloads, all 384 router tests, the
  13-case native-forwarding follow-up, every isolated and globally activated
  package smoke, and Chrome/Dart2Wasm WebSocket coverage.
- Implementation commit `8c1318d0` is on both maintained `master` branches.
  Exact-head GitHub CI `31063345534`, Dart Package Publish Dry Run
  `31063345537`, WAMP Profile Benchmarks `31063345560`, and Router Image dry
  run `31064380140` passed. The WAMP run's first attempt narrowly missed two
  unchanged 1.2 Mbps pub/sub floors; its failed-job rerun passed the canonical
  gate without code or threshold changes.
- CI uploaded coverage artifact `8953222227`. The successful WAMP attempt
  uploaded benchmark artifact `8953259558`. Router Image uploaded preview
  artifact `8953302828` and Docker build records `8953357658` and
  `8953357382`.
- The comprehensive strict deployment-chain audit passed with clean exact-head
  CI logs, package and native-release dry-run evidence, the loaded-image MCP
  runtime smoke, the multi-architecture image build, the WAMP profile gate,
  workflow visibility, branch protection, and the public router package all
  ready. RC tagging remains an explicit release-approval action outside this
  checkpoint.

## Outcome

`ConnectanumHttpAuthClient` now tracks complete challenge/token, refresh, and
revocation operations as well as each request through response-body
consumption. Close rejects new work, promptly completes pending callers with a
redacted terminal `StateError`, aborts only this helper's active requests, and
prevents a paused authentication callback from opening its token request after
shutdown. Repeated close is safe, and caller-owned shared transports remain
usable by replacement auth clients. The implementation is locally verified
and shipped on both maintained branches. Exact-head CI, package, WAMP, and
Router Image workflows plus the comprehensive strict deployment-chain audit
are clean.
