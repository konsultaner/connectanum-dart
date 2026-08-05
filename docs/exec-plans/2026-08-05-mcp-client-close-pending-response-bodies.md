# MCP Client Close Pending Response Bodies

Status: complete

## Goal

Make `McpStreamableHttpClient.close()` terminate ordinary MCP HTTP response
body reads started by that client even when response headers have already
arrived and the underlying `HttpClient` is caller-owned, without closing or
otherwise invalidating the shared transport.

## Context

Ordinary standard/direct JSON `POST`, compatibility `GET`, and session
`DELETE` requests now remain client-owned until response headers are
established. Their bodies are still consumed through an untracked stream after
that boundary. A server that flushes valid response headers and then stalls the
body can therefore leave the public API call pending after local client close.
Modern `subscriptions/listen` traffic already uses dedicated request-scoped
clients and remains an independent ownership boundary.

## Plan

1. Run the pre-change fast suite and add fail-first regressions for stalled
   response bodies across direct JSON `POST`, compatibility `GET`, and session
   `DELETE` on a caller-owned transport.
2. Track ordinary response-body readers through completion and make close
   cancel their stream subscriptions with a deterministic client-close error.
3. Preserve caller-owned transport reuse, compatibility state invalidation,
   and modern listener ownership behavior.
4. Extend the neutral client-only consumer-package smoke to require prompt
   rejection after response headers have arrived, then run focused
   analysis/tests and `bin/verify`.
5. Update project state, commit and push the implementation with its evidence,
   then audit the exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast`: passed on 2026-08-05.
- Fail-first regressions reproduced stalled direct JSON `POST`, compatibility
  `GET`, and session `DELETE` response bodies surviving client close after
  response headers arrived. A separate close-boundary regression reproduced a
  response delivered after close completing successfully.
- Focused client analysis, all 158 Streamable HTTP client tests, and the
  complete 238-case MCP/client suite pass.
- The neutral client-only consumer-package smoke passes from source and
  through the globally activated public package command. It requires the MCP
  client to reject a stalled response body promptly and proves a replacement
  MCP client can reuse the caller-owned transport.
- `bash -n bin/common.sh`, the public-artifact reference guard, and
  `git diff --check` pass.
- Full `bin/verify`: passed on 2026-08-05. Verification covered 113 Rust core
  tests, 52 Rust FFI tests, 360 Dart core tests, all 94 MCP tests, the complete
  238-case MCP/client suite, all 96 benchmark tests including 36 live WAMP
  workloads, all 384 router tests, 13 native follow-ups, Chrome/Dart2Wasm, and
  every isolated and globally activated consumer/CLI smoke.
- Hosted exact-head deployment audit: passed. Commit `0589faa5` is on both
  maintained `master` branches. GitHub CI `31045416577`, Dart Package Publish
  Dry Run `31045416678`, WAMP Profile Benchmarks `31045416853`, and Router
  Image dry run `31045483684` passed. Coverage artifact `8946769962`, WAMP
  artifact `8946451040`, Router Image preview artifact `8946265081`, and Docker
  build records `8946373432` and `8946372789` were uploaded. The comprehensive
  strict deployment-chain audit passes with clean exact-head CI logs,
  loaded-image MCP runtime smoke, multi-architecture image build, and all
  required branch, workflow, package, native-release, publish-dry-run,
  benchmark, and registry gates clean. Release-candidate readiness remains
  intentionally non-gating until an approved numeric RC tag points at the
  release commit.

## Outcome

Ordinary MCP endpoint requests now retain explicit client ownership through
response-body completion. Client close rejects registered readers with a
deterministic state error and cancels their stream subscriptions, including a
response delivered across the close boundary. The caller-owned transport
remains open and reusable, and modern request-scoped listener ownership remains
independent. Exact-head hosted workflow and deployment-audit evidence is
complete at implementation commit `0589faa5`.
