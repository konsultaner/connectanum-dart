# MCP Router Origin / Rate-Limit Precedence

Status: complete locally; publication and hosted evidence pending

## Goal

Ensure router-hosted MCP validates every supplied `Origin` before route-level
rate limiting, so an invalid Origin always receives HTTP 403 and cannot consume
the request budget available to an allowed consumer application.

## Context

The Streamable HTTP transport requires servers to validate `Origin` on every
incoming connection and return HTTP 403 when a supplied Origin is invalid. The
router's general route limiter currently runs before the MCP handler, so an
invalid-origin request consumes quota and can receive HTTP 429 after exhaustion.
This also lets rejected browser traffic reduce the request budget available to
valid MCP clients.

The correction must retain the existing pre-dispatch rate limit for valid MCP
traffic, its protocol/CORS/rate-limit response headers, sessionless 429
boundary, and the DELETE cleanup exemption.

## Plan

1. Preserve the preceding checkpoint's hosted evidence and run the pre-change
   fast regression matrix.
2. Add a fail-first native router regression proving invalid Origins neither
   consume quota nor become 429 responses after valid traffic exhausts it.
3. Move the MCP Origin boundary ahead of route limiting without changing
   general HTTP routes or valid-Origin rate-limit behavior.
4. Extend the neutral generated-consumer rate-limit smoke with the same 403 and
   quota-isolation proof.
5. Run focused formatting, analysis, regression, and consumer checks, then
   post-change `bin/test-fast` and full `bin/verify`.
6. Update durable project state and Serena memory, publish the implementation
   checkpoint, and audit the exact-head GitHub deployment chain.

## Progress

- 2026-08-11: Repository workflow, Serena, overlap, active-state, both-roadmap,
  and official Streamable HTTP transport preflights completed. Only the
  preceding checkpoint's expected hosted-evidence notes were dirty at startup.
- 2026-08-11: Pre-change `bin/test-fast` passes the complete fast regression
  chain, including 36 live WAMP workloads and every neutral MCP consumer and
  router CLI smoke.
- 2026-08-11: The fail-first router regression reproduced that an invalid
  Origin consumed the single request token and made the first allowed-Origin
  preflight return HTTP 429 instead of 204.
- 2026-08-11: Router binding now sends invalid-Origin MCP requests through the
  MCP handler's 403 boundary before route-rate evaluation, transport auth, or
  session processing. Valid-Origin rate limiting and DELETE cleanup remain in
  their existing paths.
- 2026-08-11: Focused router runtime and native-integration regressions,
  package analysis, shell syntax, public-artifact guards, and the isolated
  generated-consumer smoke pass. The neutral consumer smoke proves a rejected
  Origin neither receives session/rate headers nor consumes the two-request
  budget used by subsequent valid clients.
- 2026-08-11: Post-change `bin/test-fast` passes the complete fast regression
  chain, including all neutral package and executable consumer smokes.
- 2026-08-11: The first full `bin/verify` run exposed a load-sensitive,
  unrelated Streamable idle-expiry test deadline: the test expected HTTP 400
  before its 500 ms deadline but observed the already-expired HTTP 404 path.
  The exact test passed five of five isolated reruns, confirming timing rather
  than a response-path regression. Its timeout and both expiry proofs now keep
  the same semantics with enough concurrent-suite margin; five focused reruns
  and the complete 424-test router package suite pass.
- 2026-08-11: The canonical `bin/verify` rerun passes with zero formatting
  changes, 114 Rust core tests plus serializer integrations, 52 Rust FFI
  tests, 360 Dart core tests, 101 MCP tests, the complete 280-case MCP/client
  suite, all 96 benchmark tests and 36 live WAMP workloads, all 418 router
  tests, remote-auth integration, 13 native follow-ups, every neutral
  consumer/CLI smoke, and Chrome/Dart2Wasm coverage.
