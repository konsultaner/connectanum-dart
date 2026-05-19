# HTTP Route Method Action Maps

Status: complete

## Goal

Close the HTTP bridge routing gap where native route config already supports
method-specific targets, but Dart router settings could only duplicate one
action across every allowed method.

## Scope

- Add method-specific HTTP route actions to router settings.
- Parse native-style route `methods` maps and explicit `method_actions` maps.
- Serialize method-specific targets into native `http_routes[].methods`.
- Keep Dart synthetic runtime method matching aligned with the method-action
  allow list.
- Add focused Dart tests for config parsing, native config output, and runtime
  method matching.

## Verification

- Pre-edit `bin/test-fast`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_json_test.dart --name "method-specific HTTP route actions" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_config_loader_test.dart --name "native-style HTTP method action maps" --chain-stack-traces`: passed on 2026-05-14.
- `dart test packages/connectanum_router/test/router_runtime_test.dart --name "method-specific HTTP route actions" --chain-stack-traces`: passed on 2026-05-14.
- `git diff --check`: passed on 2026-05-14.
- `bin/verify`: passed on 2026-05-14.
