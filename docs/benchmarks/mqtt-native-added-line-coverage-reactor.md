# Native MQTT added-line coverage

**838/838 added executable production lines are covered** by the union of Cargo unit tests and instrumented Dart FFI suites. Both runs finish successfully on the same native source bytes; archived source-scope hashes match the current files. [The inventory](mqtt-native-added-line-coverage-reactor.json) records exact lines and hashes.

| Production source | Covered / executable added lines |
| --- | ---: |
| `ct_core/src/config.rs` | 11 / 11 |
| `ct_core/src/io_stream.rs` | 12 / 12 |
| `ct_core/src/lib.rs` | 676 / 676 |
| `ct_core/src/protocol.rs` | 81 / 81 |
| `ct_ffi/src/runtime/ffi.rs` | 58 / 58 |

The scope uses the Rust production filter and the patience diff against base `73d840c9`. The [Cargo LCOV](mqtt-native-added-line-coverage-reactor-cargo-unit.info.gz) and [Dart FFI LCOV](mqtt-native-added-line-coverage-reactor-dart-ffi.info.gz) permit independent recomputation. Tests, comments and non-executable lines are excluded; both collections use the current `ffi-test` artifact on macOS arm64. This is scoped added-line coverage, not full-repository or every-platform coverage.

Regressions exercise socket transfer with a partially consumed replay buffer after the old reactor shuts down, failed migration without a published connection, TCP and WebSocket negotiation failure, explicit worker overrides, cancellation of both pools, and cleanup when partial startup fails inside another runtime. Direct MQTT and independent-client integration remain separate correctness checks. A passing coverage report does not establish affected-hardware performance acceptance.
