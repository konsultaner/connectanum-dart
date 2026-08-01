# Exec Plan: Router-Hosted MCP Resource Subscription Consumer Smoke

## Status

Complete.

## Goal

Prove that a consumer can use the public router-hosted MCP client executable to
subscribe to a configured dynamic resource, publish its mapped WAMP update,
receive the resumable Streamable HTTP notification, read the resource again,
and unsubscribe without consumer-project assumptions.

## Scope

- Add explicit resource-update topic and event options to the public
  `router_hosted_client` executable, with fail-fast option validation and a
  redaction-safe dry-run summary.
- Use the typed Streamable HTTP resource lifecycle and WAMP pub/sub helpers to
  run subscribe, acknowledged update publish, GET/SSE notification polling,
  resource reread, and unsubscribe under one active MCP session.
- Add a neutral procedure-backed resource and update topic to the maintained
  router-hosted MCP example.
- Cover source-checkout, globally activated, public, bearer-protected, and
  router-forced JSON-POST response variants in the maintained smoke gate.
- Keep direct JSON catalog/read behavior lifecycle-free while the update flow
  remains an explicit Streamable HTTP opt-in.

## Non-Goals

- Infer update topics from resource metadata or WAMP registrations.
- Subscribe static resources that do not advertise resource subscriptions.
- Add a persistent resource cache or background polling service.
- Change the router resource-subscription protocol implemented in the previous
  slice.

## Verification

- Public client dry-run validation and summary smoke
- Public router-hosted client source-checkout live smoke
- Globally activated public client live smoke
- Protected and JSON-response router-hosted client variants
- `dart analyze packages/connectanum_mcp packages/connectanum_router`
- `bin/test-fast`
- `bin/verify`

## Progress

- 2026-08-01: Selected after the dynamic resource-subscription implementation
  completed. The pre-change `bin/test-fast` baseline passed, including all 91
  MCP package tests, all 178 client MCP tests, the real-router benchmark suite,
  public/global MCP client smokes, consumer-package smokes, and router native
  integration checks.
- 2026-08-01: The public client now accepts an explicit dynamic resource update
  topic and JSON event, validates the option dependency chain, and performs the
  typed subscribe, acknowledged publish, resumable SSE notification, changed
  reread, and guaranteed unsubscribe flow without changing direct JSON
  lifecycle semantics. The neutral router example now declares the dynamic
  read procedure and update topic required by the flow. The first live smoke
  exposed that the update topic also had to be present in the MCP route's
  declared topic catalog; adding that declaration made the route permission
  boundary explicit instead of relying only on WAMP realm permissions.
- 2026-08-01: Package analysis, shell syntax, diff checks, public dry-run
  validation, and the complete source/global/public/protected/JSON-response
  live client matrix passed. Post-change `bin/test-fast` also passed, including
  all maintained package, consumer-installation, live-router benchmark, public
  MCP client, and router CLI consumer checks.
- 2026-08-01: Complete local `bin/verify` passed, including formatting, 113
  Rust core tests, 52 FFI tests, 360 core Dart tests, 91 MCP package tests, 178
  client MCP tests, all 96 benchmark tests, the complete 379-test router suite,
  isolated and globally activated package consumers, every maintained
  router-hosted MCP live variant, 13 focused native-router checks, and
  Chrome/Dart2Wasm.
- 2026-08-01: Commit `89ed64c` was pushed to GitLab `origin/master` and GitHub
  `master`. Exact-head GitHub CI `30698517025`, Dart Package Publish Dry Run
  `30698517022`, and WAMP Profile Benchmarks `30698517021` passed on their
  first attempts; WAMP artifact `8818115551` was uploaded. The strict
  deployment-chain audit passed with a clean exact-head CI log scan and all
  required branch, workflow, package, benchmark-artifact, and registry gates
  clean.
