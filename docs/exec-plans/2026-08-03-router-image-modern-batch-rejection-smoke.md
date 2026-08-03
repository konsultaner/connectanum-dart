# Exec Plan: Router Image Modern Batch Rejection Smoke

## Status

Completed.

## Goal

Prove that router-hosted MCP `2026-07-28` endpoints reject removed JSON-RPC
batch requests at the HTTP boundary without creating compatibility-era session
state, while the maintained `2025-11-25` Streamable HTTP path keeps its
supported batch behavior.

## Scope

- Add a focused native-router regression for a well-formed modern batch sent
  with the required protocol and transport headers.
- Require HTTP 400, JSON-RPC `invalidRequest`, the negotiated modern protocol
  response header, and no `MCP-Session-Id` header.
- Extend the canonical loaded Router Image smoke to prove the same rejection on
  public and bearer-protected endpoints.
- Keep the existing globally activated public-client compatibility batch smoke
  as positive evidence that only the modern protocol removed batching.
- Expose one bounded hosted-log marker for modern batch rejection.
- Reuse the tested shared command-timeout helper for the browser smoke so a
  successful verification run cannot leave its watchdog sleeper holding the
  output pipe open until the full timeout expires.

## Non-Goals

- Reintroduce JSON-RPC batching to MCP 2026.
- Change compatibility-era batch semantics or public client parsing.
- Add another MCP protocol extension.

## Verification

- Pre-change `bin/test-fast`.
- Focused native-router and Router Image smoke-contract tests.
- The complete real Router Image runner against a locally built image.
- Full `bin/verify` before handoff.
- Exact-head CI, package dry run, Router Image dry run, WAMP benchmarks, hosted
  log inspection, and the comprehensive strict deployment-chain audit after
  the implementation push.

## Progress

- 2026-08-03: Selected after confirming the public client intentionally rejects
  MCP 2026 batches and the router already has the matching runtime gate, but no
  native-router or loaded-image regression pins the response status, error
  envelope, protocol header, and session isolation.
- 2026-08-03: Pre-change `bin/test-fast` passed. The package executable now
  exercises the public client's local no-batch guard without changing session
  state. The focused native-router regression pins the raw HTTP rejection, and
  the canonical image runner checks public and router-issued-bearer endpoints.
  Dart analysis, all 37 package/Router Image contracts, the focused native
  test, and the complete local loaded-image smoke pass. The first full
  `bin/verify` completed every test successfully but exposed an orphaned
  browser-watchdog sleeper; the runner now delegates to the shared timeout
  helper and has a focused prompt-return regression. The final full
  `bin/verify` rerun passed and returned immediately after the Dart2Wasm
  browser smoke.
- 2026-08-03: Commit `437df23` was pushed to GitLab and GitHub. Exact-head CI
  `30832856716`, Dart Package Publish Dry Run `30832856688`, Router Image dry
  run `30834158108`, and WAMP Profile Benchmarks `30832856637` all passed. CI
  uploaded coverage artifact `8864028186`, Router Image uploaded preview
  artifact `8864138423`, and WAMP uploaded benchmark artifact `8863836803`.
- 2026-08-03: Fresh-image logs contain the raw
  `modern_batch_rejected=true status=400 error=-32600 sessionless=true`
  evidence plus exactly four bounded package lines. Both modern lines report
  `modern_batch_unsupported=true`; both compatibility lines retain Streamable
  HTTP and session deletion. The comprehensive strict deployment-chain audit
  exited zero with every required gate ready. RC tagging remains
  approval-gated.
