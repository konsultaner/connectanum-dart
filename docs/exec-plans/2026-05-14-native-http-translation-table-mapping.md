# Native HTTP Translation Table Mapping

Status: complete

## Goal

Close the HTTP bridge translation-table readiness parent with native runtime
evidence that explicit path/method/protocol mappings enqueue the intended WAMP
realm/procedure target before Dart dispatch.

## Scope

- Add a native HTTP/1.1 route regression for explicit `translation` targets.
- Cover a default target plus a method-specific override on the same route.
- Assert the queued request summary includes the expected realm, procedure,
  path, query, method, and protocol.
- Mark the roadmap translation-table parent complete once focused and full
  verification pass.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-14.
- `cargo test -p ct_core http_translation_route_maps_method_to_wamp_procedure_before_dispatch`: passed on 2026-05-14.
- `bin/verify`: passed on 2026-05-14.
