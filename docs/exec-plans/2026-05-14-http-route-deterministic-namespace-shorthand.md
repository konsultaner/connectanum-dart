# HTTP Route Deterministic Namespace Shorthand

Status: complete

## Goal

Close the HTTP bridge shorthand gap for router-managed reserved-realm and
namespace routes by making Dart runtime dispatch derive the same deterministic
WAMP realm/procedure target as native routing.

## Scope

- Keep native `reserved_realm` / `namespace` route encoding aligned with the
  existing native materialization model.
- Parse route action aliases that consumers commonly use in Dart-style config
  (`reservedRealm`, `appendMethodSuffix`, etc.).
- Derive reserved-realm and namespace dispatch targets in Dart runtime matching
  when native handshakes do not already provide a target.
- Add focused config-loader, native JSON, and runtime regressions.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_config_loader_test.dart --name "deterministic HTTP route shorthand aliases" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_json_test.dart --name "deterministic HTTP shorthand routes" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "deterministic HTTP shorthand targets" --chain-stack-traces`: passed on 2026-05-14.
- `bin/verify`: passed on 2026-05-14.
