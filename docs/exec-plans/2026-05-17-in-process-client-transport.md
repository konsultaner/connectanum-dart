# In-Process Client Transport

Status: third router/auth-service embedding slice is implemented locally after
the first transport-foundation slice and second RouterSession-backed delegate
slice were pushed and hosted-clean. The router now supports
`rpc.transport.type: internal` for worker-safe embedded remote-auth WAMP
delegates, and the live external-client smoke is part of `bin/test-fast`.

## Goal

Start the internal router↔client transport lane without coupling it to router
runtime internals yet. The first slice provides a reusable, bounded Dart
message transport that can back a normal `connectanum_client` session and later
serve as the frame pipe for embedded router/auth-server chaining.

## Plan

- Add a paired in-process transport primitive in `connectanum_client` that
  implements `AbstractTransport`.
- Preserve WAMP messages as Dart objects, avoiding socket and serializer
  boundaries for embedded flows.
- Enforce bounded inbound queues by throwing an explicit backpressure exception
  when a peer queue is full.
- Prove message delivery, listener-attach buffering, backpressure, normal
  client session handshakes, and peer-close behavior with focused tests.
- Wire the focused test directory into `bin/test-fast` and `bin/test-all`.
- Add a router-side remote WAMP procedure delegate that can use
  `RouterSession.call` instead of opening a loopback socket.
- Prove an embedded auth-service realm can serve remote-auth HELLO /
  AUTHENTICATE calls through that delegate.
- Wire the focused embedded remote-auth smoke into `bin/test-fast` on
  native-capable hosts.
- Add worker-isolate/config wiring so live edge routers can select a
  worker-safe internal delegate lane instead of relying on main-isolate
  `RemoteAuthenticatorRegistry` state.
- Prove a live external WebSocket client can authenticate through embedded
  auth-service procedures using `rpc.transport.type: internal`.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-17.
- Focused `dart test packages/connectanum_client/test/transport/in_process -r expanded`:
  passed on 2026-05-17.
- Focused `dart analyze packages/connectanum_client/lib/src/transport/in_process_transport.dart packages/connectanum_client/test/transport/in_process/in_process_transport_test.dart packages/connectanum_client/lib/connectanum.dart`:
  passed on 2026-05-17.
- Post-edit `bin/test-fast`: passed on 2026-05-17.
- Full local `bin/verify`: passed on 2026-05-17.
- Hosted evidence for `d778896` is clean: push CI #26004300725, PR CI
  #26004301387, push Dart Package Publish Dry Run #26004300727, PR Dart
  Package Publish Dry Run #26004301397, Router Image dry-run #26004594232,
  and WAMP Profile Benchmarks #26004594238 passed on 2026-05-17.
- Strict deployment-chain audit with latest CI/logs, package dry-run, Router
  Image dry-run, WAMP benchmark, and RC-readiness reporting passed for the
  enforced gates on 2026-05-17. RC readiness remains blocked by PR review/merge,
  fresh RC tag/prerelease approval, and tag-matched release evidence; pub.dev
  remains intentionally deferred.
- Pre-edit `bin/test-fast`: passed on 2026-05-18.
- Focused `dart analyze packages/connectanum_router/lib/src/router/auth/remote_wamp_delegate.dart packages/connectanum_router/lib/src/router/router_instance.dart packages/connectanum_router/lib/auth.dart packages/connectanum_router/test/remote_auth_integration_test.dart`:
  passed on 2026-05-18.
- Focused `dart test packages/connectanum_router/test/remote_auth_integration_test.dart -r expanded`:
  passed on 2026-05-18.
- Post-edit `bin/test-fast`: passed on 2026-05-18.
- Full local `bin/verify`: passed on 2026-05-18.
- Full local `bin/verify`: passed on 2026-05-18.
- `bin/dart-package-publish-dry-run`: passed with zero warnings on
  2026-05-18.
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`:
  failed only on the known deferred pub.dev release-order blocker
  (`connectanum_client` depends on private `connectanum_core`) on 2026-05-18.
- Hosted evidence for `45be6c9` is clean: push CI #26006154488, PR CI
  #26006155386, push Dart Package Publish Dry Run #26006154487, PR Dart
  Package Publish Dry Run #26006155388, Router Image dry-run #26006447749,
  and WAMP Profile Benchmarks #26006660851 passed on 2026-05-18.
- Strict deployment-chain audit with latest CI/logs, package dry-run, Router
  Image dry-run, WAMP benchmark, native release relevance, workflow visibility,
  GHCR visibility, and RC-readiness reporting passed for the enforced gates on
  2026-05-18. RC readiness remains blocked by PR review/merge, fresh RC
  tag/prerelease approval, and tag-matched release evidence; pub.dev remains
  intentionally deferred.
- Focused `dart analyze packages/connectanum_router/lib/src/router/auth/remote_wamp_delegate.dart packages/connectanum_router/lib/src/router/router_instance.dart packages/connectanum_router/test/remote_wamp_delegate_test.dart packages/connectanum_router/test/remote_auth_integration_test.dart`:
  passed on 2026-05-18.
- Focused `dart test packages/connectanum_router/test/remote_wamp_delegate_test.dart packages/connectanum_router/test/remote_auth_integration_test.dart -r expanded`:
  passed on 2026-05-18.
- Post-edit `bin/test-fast`: passed on 2026-05-18.

## Remaining

- Decide whether the next internal lane should connect through the existing
  `RouterSession` bridge or map a lower-level internal endpoint onto
  `InProcessTransportPair`.
- Decide when `connectanum_auth_server` should own a router instance plus
  internal client lifecycle for credential-provider-backed embedded auth.
