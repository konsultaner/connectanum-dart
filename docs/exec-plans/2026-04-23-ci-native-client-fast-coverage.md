## Goal

Restore a clean branch CI baseline by making the native client E2EE coverage
deterministic in the canonical root test scripts.

## Scope

- reproduce and fix the current GitHub `Fast Checks` failure on `add-router`
- make `bin/test-fast` provision the native client runtime before client tests
  that require `ct_ffi`
- include the dedicated native client E2EE provider regression in the canonical
  root verification flows
- keep local/package runs graceful when the native client runtime is genuinely
  unavailable
- update checked-in repo state to reflect the CI-clean priority and the latest
  known hosted status

## Non-goals

- advancing the paused HTTP/3 backpressure tuning work before branch CI is
  green again
- broad refactors of the native loader or provider API beyond what is needed
  for deterministic verification

## Verification

- `bin/test-fast`
- focused Dart tests for the touched client native-provider paths
- `bin/verify`

## Status

- completed

## Findings

- GitHub Actions `CI` runs `24822621244` (`eb9c427`) and `24822956656`
  (`5c0e7ec`) both failed in `Fast Checks` because
  `packages/connectanum_client/test/client_test.dart` now includes
  `publishLazyPayload supports a native session E2EE provider resolver`, which
  constructs `NativeWampCborXsalsa20Poly1305Provider` before `bin/test-fast`
  has built or exported `libct_ffi.so`.
- The root scripts were also missing the dedicated
  `packages/connectanum_client/test/transport/native/e2ee_provider_test.dart`
  regression entirely, so the canonical verification flow was not covering the
  standalone native provider surface at all.
- The repair landed locally in three parts:
  `bin/common.sh` now exposes `ensure_native_client_test_runtime()`,
  `bin/test-fast` now provisions the native client runtime before running the
  client suite and includes `e2ee_provider_test.dart`, and `bin/test-all` now
  includes that same dedicated native provider regression in the full flow.
- The native-only client tests are now explicit about availability too.
  `client_test.dart` skips the one native-session-provider resolver case when
  `libct_ffi` cannot be loaded, and `e2ee_provider_test.dart` skips the whole
  group with the same reason instead of failing with a raw `DynamicLibrary`
  load exception during ad hoc local runs.
- Local verification is green on the repaired tree:
  the focused native-provider tests, `bin/test-fast`, and `bin/verify` all
  pass.
- Hosted branch CI confirmation is now complete too. GitHub Actions run
  `24823387475` on commit `06f3b43` passed both `Fast Checks` and
  `Full Verify`, closing the repair.
