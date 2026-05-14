# Native HTTP Namespace Route Mapping

Status: complete

## Goal

Close the remaining HTTP bridge namespace auto-mapping readiness item by adding
native runtime evidence that namespace routes enqueue the deterministic WAMP
realm/procedure target before Dart dispatch.

## Scope

- Add a native HTTP/1.1 route regression for `type: namespace`.
- Assert the queued request summary includes the expected realm, procedure,
  path, query, method, and protocol.
- Mark the roadmap namespace auto-mapping item complete once focused and full
  verification pass.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-14.
- `cargo test -p ct_core http_namespace_route_maps_path_to_wamp_procedure_before_dispatch`: passed on 2026-05-14.
- `bin/verify`: passed on 2026-05-14.
