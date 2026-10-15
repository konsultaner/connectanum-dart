# Native MQTT added-line coverage — 2026-10-15

The current MQTT branch has **767/767 newly added executable Rust production lines covered** by the union of the Cargo `ffi-test` unit suite and the instrumented Dart FFI transport suites. Both collections completed on the same source bytes; their `source-scopes.json` hashes match the files in this report. Local final-source `bin/verify` and `bin/check-format` pass. [The line inventory and report hashes](mqtt-native-added-line-coverage-2026-10-15.json) preserve the exact scope. The filtered [Cargo LCOV](mqtt-native-added-line-coverage-2026-10-15-cargo-unit.info.gz) and [Dart FFI LCOV](mqtt-native-added-line-coverage-2026-10-15-dart-ffi.info.gz) are archived for independent recomputation.

| Production source | Covered / executable added lines |
| --- | ---: |
| `ct_core/src/config.rs` | 11 / 11 |
| `ct_core/src/lib.rs` | 617 / 617 |
| `ct_core/src/protocol.rs` | 81 / 81 |
| `ct_ffi/src/runtime/ffi.rs` | 58 / 58 |

The scope is the added lines under `native/transport` versus base `73d840c9`, selected with `git diff --patience --unified=0`. The Rust production coverage filter excludes tests, comments and non-executable lines. The patience diff keeps an unchanged HTTP/3 block, which the default diff algorithm presents as moved additions, outside this MQTT change. For every in-scope executable line, the report takes the higher hit count from `bin/test-native-coverage` and `bin/test-native-ffi-coverage`. Neither report alone covers the complete live boundary: Cargo tests cover 685/767, while the FFI suite covers the remaining listener and transport paths. The FFI collector completed and checked the native library and input hashes throughout its Dart suites.

New deterministic regressions cover MQTT TCP receiver teardown, WebSocket idle and malformed-frame paths, the notification-reset race, FFI chunk-copy bounds and missing-connection error mapping, plus MQTT protocol identity in connection events and metrics. This is native **added-line** coverage for the current QoS 0 implementation; it does not claim full repository coverage, complete MQTT protocol behavior, or a passing performance release gate. The hosted direct-MQTT gate remains red on EPYC 7763, and the WAMP↔MQTT gateway and translation benchmark remain unfinished.
