# Exec Plan: WAMP Transport Interop Coverage

Status: completed
Owner: Codex
Created: 2026-04-23
Last updated: 2026-04-23

## Goal

Protect the shipped WAMP client transports with live router integration
coverage, especially the pure Dart RawSocket path on macOS and mixed
RawSocket/WebSocket routing, so transport-level correctness is exercised beyond
serializer-only and router-state conformance tests.

## Scope

- In scope:
  - add focused live-router tests for the pure Dart RawSocket client path
  - cover mixed RawSocket/WebSocket WAMP routing with real client sessions
  - verify serializer interop on those transport paths where it is already
    supported by the shipped listeners
  - refresh project state and roadmap notes after verification
- Out of scope:
  - new benchmark or performance-budget work
  - broader upstream conformance-runner expansion while the upstream vector
    format is still unstable
  - native transport/runtime feature changes unrelated to transport interop
    correctness

## Files Expected To Change

- `packages/connectanum_router/test/publish_ack_test.dart`
- `packages/connectanum_router/test/router_integration_websocket_test.dart`
- `docs/project_state.md`
- `docs/exec-plans/2026-04-23-wamp-profile-transport-performance-readiness.md`
- `docs/exec-plans/2026-04-23-wamp-transport-interop-coverage.md`
- `ROADMAP_NEXT.md`

## Preconditions

- `bin/test-fast` is green before transport-interop edits. Confirmed on
  2026-04-23.
- The WAMP profile transport performance-readiness plan is complete and hosted
  GitHub validation is green through commit `175ae0a`.

## Plan

1. Close the completed WAMP benchmark-readiness plan in checked-in docs and
   point project state at this interop-coverage milestone.
2. Add focused live-router coverage for the pure Dart RawSocket path and
   mixed-transport WAMP routing on the macOS-supported local path.
3. Run targeted transport tests and `bin/verify`, then refresh state and
   roadmap notes with the new interop baseline and any remaining gaps.

## Verification

- `bin/test-fast`
- targeted `dart test` runs for the new/updated router integration files
- `bin/verify`

## Decision Log

- 2026-04-23: Use focused live transport tests rather than waiting for broader
  upstream conformance vectors. The shipped serializer and router-state gates
  already exist; the remaining gap is end-to-end transport coverage.
- 2026-04-23: Prioritize the pure Dart RawSocket client path because the
  native/bench transport lanes already have broader Linux-only coverage, while
  the Dart RawSocket path is a shipped surface that should be verifiable on the
  current macOS host.

## Handoff

- Completed. The router package now has host-supported live WAMP transport
  interop coverage beyond the existing serializer and state-layer conformance
  gates.
- `packages/connectanum_router/test/publish_ack_test.dart` now exercises the
  pure Dart RawSocket publish-ack path across JSON, MessagePack, and CBOR
  against a live router.
- `packages/connectanum_router/test/router_integration_websocket_test.dart`
  now covers mixed RawSocket/WebSocket publish, call, and error routing across
  rawsocket JSON + CBOR clients and a websocket MsgPack client on the current
  macOS-supported path.
- Verification passed with `bin/test-fast`, targeted router-package
  integration tests from `packages/connectanum_router`, and full `bin/verify`.
