# Hosted FlatBuffers file transfer diagnostic

[GitHub Actions run 39429761119](https://github.com/konsultaner/connectanum-dart/actions/runs/39429761119) tested commit `1c53c153ab2c1be638a7b57ad619f6f3f7a53210` on Linux, AMD EPYC 7763 (four available CPUs), with one router worker and one native runtime thread. All eight native FlatBuffers 64 MiB file workloads completed 16 samples and passed the existing 2 Gbit/s data-window and lifecycle gates. Rates below are Gbit/s; higher is better.

| Native path | Sustained | Full lifecycle | Samples | Client peak RSS (MiB) | Measured transport copies (bytes) |
| --- | ---: | ---: | ---: | ---: | ---: |
| RawSocket clear | 7.779 | 6.905 | 16 | 358.3 | 16,784 |
| RawSocket TLS | 5.037 | 4.748 | 16 | 363.0 | n/a |
| WebSocket clear | 6.953 | 6.439 | 16 | 358.8 | 122,536 |
| WebSocket TLS | 4.669 | 4.435 | 16 | 364.7 | n/a |
| RawSocket E2EE | 7.190 | 6.664 | 16 | 365.2 | 21,680 |
| RawSocket TLS + E2EE | 4.600 | 4.378 | 16 | 369.2 | n/a |
| WebSocket E2EE | 6.357 | 5.920 | 16 | 369.4 | 1,073,944,712 |
| WebSocket TLS + E2EE | 4.482 | 4.252 | 16 | 369.3 | n/a |

The full eight-scenario diagnostic ended red: six scenarios passed, while the file and WebSocket fragmentation gates failed on other workloads. The [file gate](file-gate.md) records three misses in Dart buffered JSON file transfer (lowest sustained 1.141 Gbit/s). The [fragmentation gate](fragmentation-gate.md) records eight misses in native JSON/CBOR WebSocket Pub/Sub (lowest lifecycle 1.650 Gbit/s). These findings do not implicate the new FlatBuffers file rows. The existing 2 Gbit/s budgets were retained.

The measured copy counter includes 1 GiB for WebSocket E2EE without TLS; this transport path remains a copy optimization candidate despite passing the throughput gate. TLS copy behavior is not instrumented, so `n/a` does not mean zero copies. RSS is a client process peak, not incremental allocation. This Linux run uses different hardware and Dart versions from the [local three-pass measurement](../wamp-flatbuffers-file-segments-2026-10-20/README.md), so its rates are not a before/after comparison.

The [original file records](file-results.jsonl.gz), [transformed file summary](file-summary.json.gz), [scenario summary](diagnostics-summary.tsv), and [host details](host-info.txt) preserve the evidence. The full artifact, including other scenario records, is downloadable from the GitHub Actions run. Use `shasum -a 256 -c SHA256SUMS` in this directory to check the committed files.
