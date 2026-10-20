# Matched WAMP serializer snapshot

These are the raw measurements behind the four-column [package throughput tables](../../../packages/connectanum_bench/README.md#wamp-throughput). The tables show the median of three runs of each workload. All 312 planned workload records completed, with the expected number of samples in every record.

| Run setting | Value |
| --- | --- |
| Source commit | `73abe8f653b6482f6aaa66d5cf66842a3e670fe9` (clean working tree during measurement) |
| Host | Apple M3 Ultra, 512 GiB RAM, macOS 26.7.1 (`25G241`) |
| Toolchain | Dart 3.13.1, Rust 1.95.0 |
| Router workers / native runtime threads | 1 / 1 |
| Runs | Three passes of 40 file, 32 large RPC, and 32 WebSocket fragmentation/Pub/Sub workloads; serializer order rotated between passes |
| Runner SHA-256 | `30bd1286f0a4b29b43bec4f31ab592373685e06a84dd6c9c65d99e1e86cf5847` |
| Native FFI library SHA-256 | `62869e4bce8ff61e824cb464243249fbe2e1fdcb860b512daa2e47d63f00c373` |

Each reported cell is **data-window / full-lifecycle Gbit/s**. For each run, the rate is `8 × max(total request bytes, total response bytes) / elapsed milliseconds / 1,000,000`; the two rates use `data_window_elapsed_ms` and `completed_at_ms - started_at_ms`, respectively. The table takes the median of the three rates separately. [summary.json](summary.json) includes each run and median; the nine compressed JSONL files contain the original workload records. The nine TOML files preserve all workload settings.

FlatBuffers here means a FlatBuffers **WAMP envelope** with CBOR application fragments. It is not a typed FlatBuffers PPT parity result. RawSocket large RPC payloads are 60 MiB for all four serializers; a first 64 MiB FlatBuffers trial exceeded the codec's 64 MiB CBOR-vector limit once encoding overhead was added. WebSocket large RPC payloads remain 8 MiB. File transfers remain 64 MiB with 4 MiB chunks.

These are local diagnostic numbers. The [WAMP benchmark contract](../../wamp_profile_benchmarks.md) identifies the hosted release gates. FlatBuffers file transfer was consistently slower in this snapshot: the ten file rows measured 0.593–2.298 Gbit/s sustained for FlatBuffers, compared with 8.078–22.454 Gbit/s for CBOR. The largest three-run sustained-rate spread among all 104 serializer/workload combinations was 1.50×.

To reproduce one saved scenario from the repository root, build the native FFI library and release orchestrator, then run:

```bash
native/bench/target/release/http_stream \
  --native-lib native/transport/target/ffi-test/release/libct_ffi.dylib \
  --scenario docs/benchmarks/wamp-four-serializer-2026-10-20/wamp_file_transfer_throughput-pass1.toml \
  --results /tmp/wamp-file-transfer-pass1.jsonl \
  --results-only --router-worker-counts 1 \
  --native-runtime-thread-counts 1 --workload-timeout-ms 300000
```
