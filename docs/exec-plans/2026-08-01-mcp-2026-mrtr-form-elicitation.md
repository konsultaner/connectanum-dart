# Exec Plan: MCP 2026 MRTR Form Elicitation

## Status

Completed.

## Goal

Let a downstream application complete a router-hosted MCP tool call that needs
non-sensitive user input, using the `2026-07-28` multi round-trip request
(MRTR) contract without adopting deprecated Roots or Sampling features.

## Scope

- Add typed public client models for form-mode `elicitation/create` input
  requests and responses, including restricted flat-schema and accepted-content
  validation.
- Add bounded `tools/call` helpers for ordinary and direct JSON HTTP calls that
  advertise form elicitation only for the individual request, invoke an
  application callback for every named input request, and retry with a fresh
  JSON-RPC ID plus exact opaque `requestState` echoing.
- Extend MCP tool requests/results with optional input responses, opaque request
  state, request-scoped client capabilities, and an input-required result.
- Define an explicit WAMP bridge contract through `x_mcp_*` call/result detail
  fields so a router-hosted WAMP procedure can receive MRTR retries and return
  form elicitation input requests without private application assumptions.
- Enforce request-scoped form capability support before returning input
  requests. Missing support uses reserved error `-32021`, required capability
  data, and HTTP 400 for modern stateless requests.
- Cover protocol models, WAMP mapping, client retries, router dispatch, native
  HTTP behavior, and isolated consumer-package usability.

## Protocol Direction

- This slice supports only form-mode `elicitation/create`. Roots and Sampling
  are deprecated in the 2026 specification; URL-mode elicitation has a larger
  browser/identity security boundary and remains separate.
- The public retry helper advertises `{elicitation: {form: {}}}` in the
  request-scoped client capabilities it controls. It does not mutate global
  client capabilities or infer support from an earlier request.
- A retry keeps the original method arguments, answers every named input
  request, echoes `requestState` byte-for-byte when present, and uses a new
  JSON-RPC request ID.
- Router-to-WAMP call details use `x_mcp_client_capabilities`,
  `x_mcp_input_responses`, and `x_mcp_request_state`. A WAMP result requests
  another round with `x_mcp_result_type: input_required`,
  `x_mcp_input_requests`, and optional `x_mcp_request_state`.
- Form elicitation is for non-secret values only. Sensitive credentials,
  payment data, and third-party authorization remain out of scope.

Primary MCP references:

- <https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr>
- <https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation>
- <https://modelcontextprotocol.io/specification/2026-07-28/schema>

## Non-Goals

- Implement URL-mode elicitation, Roots, Sampling, Tasks, or Apps.
- Persist MRTR state in the router or interpret the server's opaque
  `requestState`.
- Automatically render a user interface or collect input without an explicit
  consumer callback.
- Retry without a round limit or automatically recover arbitrary malformed
  server input requests.

## Verification

- Focused `connectanum_mcp` tool-result, request, and WAMP delegate regressions.
- Focused `McpStreamableHttpClient` model, retry, validation, and direct JSON
  regressions.
- Router request-scoped capability, reserved-error, retry-forwarding, and
  successful final-result regressions.
- Public IO entrypoint plus isolated client/consumer package checks.
- Real native router-hosted public and protected HTTP smoke.
- `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected from both roadmaps after the stateless
  `subscriptions/listen` milestone reached exact-head hosted green evidence.
  Official schema and feature research narrowed implementation to form
  elicitation because it is active, useful to consumer applications, and does
  not require adopting deprecated Roots or Sampling protocols.
- 2026-08-01: Pre-change `bin/test-fast` passed, including workspace analysis,
  package suites, live WAMP integration, isolated package consumers, globally
  activated commands, and maintained router-hosted MCP smokes.
- 2026-08-01: Added typed request-scoped capabilities, input requests,
  responses, opaque state, restricted form-schema validation, and bounded
  ordinary plus direct JSON client retry helpers. Each retry preserves the
  original arguments, echoes the exact opaque state, and uses a fresh JSON-RPC
  ID.
- 2026-08-01: Added the public `x_mcp_*` WAMP detail contract and routed it
  through both the hosted MCP server and direct JSON endpoint. A missing form
  capability now returns reserved error `-32021`, with HTTP 400 on the modern
  stateless endpoint.
- 2026-08-01: Focused MCP, client, WAMP-delegate, native-router, and generated
  consumer-package regressions passed. The native and isolated consumer smokes
  prove two-round form elicitation through both standard and direct JSON
  router endpoints without retaining an MCP session.
- 2026-08-01: Post-change `bin/test-fast` and complete `bin/verify` passed,
  including Rust, Dart VM, live WAMP, generated package, native router,
  Chrome, and Dart2Wasm coverage.
- 2026-08-01: Commit `dc89c4d` was pushed to GitLab and GitHub. Exact-head
  GitHub CI `30711625725`, Dart Package Publish Dry Run `30711625706`, and
  WAMP Profile Benchmarks `30711625694` passed on their first attempts.
  Coverage artifact `8822252505` and WAMP artifact `8822121595` were uploaded,
  and the strict deployment-chain audit passed with a clean exact-head CI log
  scan and every required branch, package, and benchmark gate clean.
