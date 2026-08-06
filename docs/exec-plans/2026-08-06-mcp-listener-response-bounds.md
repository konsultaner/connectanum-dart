# MCP Listener Response Bounds

Status: complete; local and hosted deployment-chain evidence clean

## Goal

Prevent request-scoped MCP `2026-07-28` listeners from buffering unbounded
setup bodies or individual SSE events while preserving long-lived incremental
notification delivery and listener/auth/session isolation.

## Context

Ordinary Streamable HTTP POST, GET, and DELETE responses now share a
configurable raw-byte limit. The modern `subscriptions/listen` path owns a
dedicated HTTP client and intentionally keeps successful SSE responses open,
so it cannot apply one total response cap. Its pre-stream error and non-SSE
bodies are still read without a bound, however, and its UTF-8 `LineSplitter`
can buffer an arbitrarily large line/event before the listener validates the
JSON-RPC message.

This checkpoint reuses `maxResponseBytes` for bounded listener setup bodies and
as a per-event raw-byte limit on successful long-lived SSE streams. Resetting
the counter at each blank SSE delimiter keeps the overall stream incremental.

## Plan

1. Preserve the green fast-suite baseline and add fail-first local-server
   regressions for oversized setup bodies, oversized SSE events, exact raw
   multibyte boundaries, listener cleanup, and same-client recovery.
2. Add a raw-byte SSE line decoder that bounds each event before UTF-8 or JSON
   decoding while preserving CR, LF, and CRLF framing across chunk boundaries.
3. Apply the existing response limit to listener setup error/non-SSE bodies and
   pass the per-event limit into every request-scoped subscription.
4. Run focused package analysis and tests, `bin/test-fast`, and `bin/verify`.
5. Bundle implementation and milestone records, push both maintained branches,
   and audit the exact-head GitHub deployment chain.

## Verification

- Pre-change `bin/test-fast` passed on 2026-08-06 with 360 core tests, all 94
  MCP tests, the complete 260-case MCP/client suite, all 96 benchmark/live-
  router tests, every neutral generated and globally activated consumer smoke,
  the router CLI MCP lifecycle matrix, and focused native/router regressions.
- Fail-first local-server regressions proved that oversized listener setup
  bodies were read without the configured cap and oversized SSE events were
  delivered before any raw-byte validation. A delimiter-edge regression also
  reproduced a CRLF event being dispatched before its final framing byte was
  counted.
- `dart analyze packages/connectanum_client packages/connectanum_mcp` and all
  172 focused Streamable HTTP cases pass. The regressions now cover successful
  and error setup bodies, oversized multibyte events, exact raw-byte limits,
  CRLF framing across chunks, typed failures, listener cleanup, and same-client
  recovery without MCP session or resume state.
- The first post-change fast run encountered a transient 45-second native WAMP
  cancel-cycle timeout after unrelated local workload contention; the isolated
  case immediately passed in 8 seconds. A fresh uninterrupted `bin/test-fast`
  then passed with 360 core tests, all 94 MCP tests, the complete 264-case MCP/
  client suite, all 96 benchmark/live-router tests, every neutral generated and
  globally activated package/consumer smoke, the router CLI MCP lifecycle
  matrix, and focused native/router regressions.
- Final exact-code `bin/verify` passes with zero formatting changes; 113 Rust
  core tests plus serializer integrations; 52 Rust FFI tests; 360 Dart core,
  94 MCP, 264 MCP/client, 96 benchmark/live-router, and 387 router tests; all 13
  focused native-forwarding regressions; every neutral consumer package and CLI
  smoke; and Chrome Dart2Wasm WebSocket coverage.
- Implementation commit `96cfb49d` is on both maintained `master` branches.
  Exact-head GitHub CI `31097691761`, Dart Package Publish Dry Run
  `31097691733`, WAMP Profile Benchmarks `31097692056`, and Router Image dry
  run `31099010946` passed on their first attempts. CI uploaded coverage
  artifact `8966621915`, WAMP uploaded benchmark artifact `8966321562`, and
  Router Image uploaded preview artifact `8966658087` plus Docker build records
  `8966758876` and `8966759628`.
- The comprehensive strict deployment-chain audit exited zero after a transient
  GitHub DNS retry. Exact-head CI logs were clean, the package and native-
  release dry runs were relevant, the loaded-image MCP runtime smoke and multi-
  architecture build passed, the WAMP profile artifact was ready, and workflow
  visibility, branch protection, and the public router package were clean. A
  numeric release-candidate tag remains an explicit release-approval action
  outside this checkpoint.

## Outcome

Listener setup bodies now use the ordinary raw-byte response bound. Successful
long-lived listeners remain incremental while each complete SSE event is
bounded in raw bytes before UTF-8 and JSON decoding, including complete CRLF
framing across chunk boundaries. Full local verification and exact-head
deployment evidence are clean, and both maintained branches contain the
implementation.
