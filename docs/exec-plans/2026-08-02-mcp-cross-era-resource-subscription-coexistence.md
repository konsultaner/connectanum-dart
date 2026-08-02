# Exec Plan: MCP Cross-Era Resource Subscription Coexistence

## Status

Completed.

## Goal

Prove that a router-hosted MCP `2026-07-28` request-scoped listener and a
compatibility-era Streamable HTTP session can subscribe to the same configured
dynamic resource at the same time, receive the same WAMP-backed update, and
release their ownership independently without interrupting the other consumer.

## Scope

- Add a native-router regression that keeps a modern resource-update listener
  open while the same public endpoint and principal initializes a Streamable
  session and subscribes to the same resource.
- Prove both protocol-era consumers receive an update from one acknowledged
  WAMP publish.
- Prove Streamable unsubscribe or session deletion leaves the modern listener
  usable, and modern listener close does not disturb an active Streamable
  resource subscription.
- Keep the endpoint's underlying WAMP subscription ownership bounded and prove
  final cleanup leaves no subscriber behind.
- Extend the isolated generated consumer package through the same public and
  protected lifecycle without private project assumptions.

## Non-Goals

- Add a new MCP protocol extension or change resource subscription wire
  formats.
- Add replay semantics to modern request-scoped listeners.
- Change production route-resource semantics, WAMP authorization policy, or
  consumer storage and refresh policy.
- Merge modern listener state into compatibility-era MCP session state.

## Protocol Constraint

The official WAMP specification permits a broker to return the existing
subscription ID when the same session subscribes to an already-subscribed
topic, and explicitly permits multiple local event handlers on that one
subscription. The client and router-internal session therefore need to retain
handler identity separately from the broker subscription ID and send
`UNSUBSCRIBE` only after the last local handler is released. See the
[WAMP publish/subscribe specification](https://wamp-proto.org/wamp_latest_ietf.html#name-publish-and-subscribe).

## Verification

- Focused native-router cross-era resource subscription regression.
- Consumer-package boundary tests.
- Isolated generated consumer package against the native router.
- `bin/test-fast` before and after the change.
- `bin/verify` before handoff.
- Exact-head GitHub CI, Dart package publish dry run, WAMP benchmark workflow,
  and strict deployment-chain audit after the implementation push.

## Progress

- 2026-08-02: Selected after both roadmaps confirmed additional MCP extensions
  are demand-driven. Existing live-router coverage tests modern listeners and
  Streamable dynamic-resource subscriptions sequentially, but does not prove
  concurrent delivery or cleanup independence on the same WAMP update topic.
- 2026-08-02: Pre-change `bin/test-fast` passed. A focused native-router
  regression then reproduced the defect: Streamable subscribe replaced the
  active modern resource handler, so the next acknowledged WAMP publish timed
  out on the request-scoped listener.
- 2026-08-02: Root cause was cross-endpoint reuse of one router-internal WAMP
  session. The broker correctly returned the same subscription ID, while both
  the public client session and router-internal session retained only one
  handler per ID. They now fan out to every local handler and release an exact
  handler without sending `UNSUBSCRIBE` until the final owner leaves.
- 2026-08-02: Router MCP endpoints now share modern and Streamable ownership
  for a configured resource within one endpoint, carry exact local handler
  identity through MCP WAMP subscriptions, and route configured dynamic reads
  through the standard authorized call delegate so router-provided WAMP meta
  procedures work without a separate application callee.
- 2026-08-02: The focused client regression passed with the full 69-case VM
  file, all 94 MCP tests passed, the focused native-router lifecycle passed in
  both cleanup orders with no final subscriber, and all 19 consumer boundary
  tests passed. The isolated generated router CLI consumer analyzed cleanly and
  completed the public and bearer-protected cross-era lifecycle against the
  native router without private project assumptions.
- 2026-08-02: Post-change `bin/test-fast` passed, including 360 core tests, all
  client and MCP authorization suites, 94 MCP tests, 96 benchmark tests, the
  complete router fast suite, and generated consumer smokes. Full `bin/verify`
  then passed formatting and analysis, Rust core and FFI suites, Dart VM and
  Chrome/Dart2Wasm coverage, all generated and globally activated consumer
  smokes, and the complete router suite. The implementation is ready to push;
  exact-head hosted workflows and the strict deployment-chain audit remain.
- 2026-08-02: Commit `86cf956` was pushed to GitLab and GitHub. Exact-head
  GitHub CI `30728291345`, Dart Package Publish Dry Run `30728291363`, and WAMP
  Profile Benchmarks `30728291375` passed on their first attempts. CI uploaded
  coverage artifact `8827275787`, WAMP uploaded benchmark artifact
  `8827184987`, and the strict deployment-chain audit passed with a clean CI
  log scan and all required gates clean.
