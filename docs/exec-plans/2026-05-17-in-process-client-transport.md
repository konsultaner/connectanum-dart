# In-Process Client Transport

Status: first transport-foundation slice implemented locally. The client package
now exports a bounded in-process transport pair and the standard fast/full test
gates run its focused test directory.

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

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-17.
- Focused `dart test packages/connectanum_client/test/transport/in_process -r expanded`:
  passed on 2026-05-17.
- Focused `dart analyze packages/connectanum_client/lib/src/transport/in_process_transport.dart packages/connectanum_client/test/transport/in_process/in_process_transport_test.dart packages/connectanum_client/lib/connectanum.dart`:
  passed on 2026-05-17.
- Post-edit `bin/test-fast`: passed on 2026-05-17.
- Full local `bin/verify`: passed on 2026-05-17.

## Remaining

- Add the router-side adapter that maps a `RouterSession` or internal router
  endpoint onto the in-process transport pair.
- Use the adapter to run remote-auth delegate calls over the embedded transport
  instead of TCP where configured.
- Add an auth-server/router smoke that exercises the embedded path end to end.
