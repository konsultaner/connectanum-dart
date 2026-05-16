# Exec Plan: HTTP Custom Handler Route Action

## Status

Complete on 2026-05-16.

## Goal

Close the remaining HTTP bridge custom-handler route gap so downstream
applications can attach router-hosted Dart handlers without routing through
WAMP, files, reverse proxies, FastCGI, or a separate server.

## Scope

- Add an HTTP `handler` route action with `custom_handler` and `customHandler`
  config aliases.
- Resolve handler ids from `action.delegate` or `action.options.handler`
  aliases.
- Register handlers on `Router.start` / `RouterBinding` as an immutable map.
- Dispatch matched handler routes after route auth, rate-limit, and concurrency
  middleware, and before generic WAMP HTTP bridge dispatch.
- Return structured errors for missing handler ids or unregistered handlers
  without leaking private endpoint details and without falling through to WAMP.
- Add config, native-json, and runtime tests that prove handler routes are
  router-hosted.

## Out Of Scope

- Streaming request or response helper abstractions for handler routes.
- Hot-swapping handler maps after `RouterBinding` creation.
- Public narrative documentation beyond roadmap/state bookkeeping for this
  implementation slice.

## Verification

- `bin/test-fast` passed before editing.
- Focused config/native/runtime handler and adapter tests passed.
- `dart analyze packages/connectanum_router` passed.
- Full local `bin/verify` passed before handoff.
- Hosted push and PR CI passed with `Fast Checks` and `Full Verify` green on
  `b454c22`.
- Hosted push and PR Dart Package Publish Dry Run passed on `b454c22`.
- Strict deployment-chain audit passed on `b454c22` with clean latest CI,
  hosted CI logs/annotations, and relevant hosted package dry-run evidence.
