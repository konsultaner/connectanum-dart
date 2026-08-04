# Exec Plan: MCP Client Rejected Initialize Cleanup

## Status

Completed.

## Goal

Ensure a Streamable HTTP client never treats a JSON-RPC error returned from
`initialize` as an established or reusable MCP session, even when a server or
proxy includes a valid-looking session header on the rejected response.

## Scope

- Recognize a validated JSON-RPC error response to `initialize` before
  capturing response session, protocol-version, or SSE resume state.
- Clear stale Streamable session and resume state after a rejected initialize.
- Apply the invariant to both the typed `initialize` helper and generic public
  JSON-RPC POST usage.
- Preserve successful initialization, ordinary request errors, HTTP auth/error
  cleanup, malformed-response state preservation, and modern stateless calls.
- Prove the behavior through focused client tests and an isolated generated
  consumer package using only public APIs.

## Non-Goals

- Change router-side initialize validation or session allocation.
- Change HTTP 401, 403, or 404 session cleanup semantics.
- Reject or throw for otherwise valid JSON-RPC initialize error envelopes.
- Add a new MCP protocol extension.

## Verification

- Pre-change `bin/test-fast`.
- Fail-first public-client regression for a JSON-RPC initialize error carrying
  `MCP-Session-Id`.
- Focused client analysis/tests and generated consumer-package smoke.
- Full `bin/verify` before handoff.
- Exact-head hosted workflows and strict deployment-chain audit after push.

## Progress

- 2026-08-04: Selected after router-side tentative initialize cleanup. The
  router now omits generated session identifiers from rejected initializes,
  but the public client still captures a valid-looking response session header
  before it returns a valid JSON-RPC error envelope. A non-conforming server or
  intermediary can therefore poison later client requests with a session that
  was never established.
- 2026-08-04: Pre-change `bin/test-fast` passed analysis, core/MCP/client
  suites, all 96 benchmark tests, and every isolated and globally activated
  consumer/CLI smoke. The fail-first client regressions reproduce both public
  paths capturing rejected response sessions: the typed helper retains
  `rejected-initialize-session`, and generic POST retains
  `generic-rejected-session`.
- 2026-08-04: Validated JSON-RPC initialize errors now validate response
  headers without adopting them, restore the prior protocol version, and clear
  Streamable session and resume state. Successful initialization and ordinary
  POST response capture still use the existing path. Focused client analysis,
  all Streamable client tests, shell validation, and the isolated generated
  consumer-package smoke pass. Advisory local review prompted explicit
  protocol non-negotiation documentation and malformed rejected-header state
  preservation coverage.
- 2026-08-04: Full `bin/verify` passed formatting and analysis, 113 Rust core
  and 52 Rust FFI tests, all 360 Dart core tests, all 94 MCP tests, the complete
  196-case MCP/client authorization suite, all 96 benchmark tests, all 384
  router tests, native follow-ups, Chrome/Dart2Wasm coverage, and every
  isolated and globally activated consumer/CLI smoke.
- 2026-08-04: Implementation commit `696417d` is on both maintained `master`
  branches. Exact-head Dart Package Publish Dry Run `30909007328`, WAMP
  Profile Benchmarks `30909005756`, and Router Image dry run `30909023890`
  passed on their first attempts. CI `30909004375` passed on attempt 2: its
  first Full Verify attempt timed out only on the pre-existing proactive MCP
  idle-expiry subscriber-cleanup observation, while five immediate local
  reruns of that exact native test and the hosted Full Verify rerun passed
  without code changes. Final check jobs have zero annotations. Coverage
  artifact `8892772599`, WAMP artifact `8892454148`, Router Image preview
  artifact `8892258065`, and Docker build records `8892359207` and
  `8892358600` were uploaded. The comprehensive strict deployment-chain audit
  passed with both maintained remote heads at `696417d`.
