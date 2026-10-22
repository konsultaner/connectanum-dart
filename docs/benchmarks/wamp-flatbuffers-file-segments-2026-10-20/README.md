# Native FlatBuffers file transfer checkpoint

This three-pass local run repeated every 64 MiB file workload from the matched four-serializer snapshot after enabling native FlatBuffers file segments. All 120 records completed with the expected sample counts. Each rate below is the median sustained rate in Gbit/s; higher is better.

| Path | Before | After |
| --- | ---: | ---: |
| RawSocket clear | 2.277 | 22.378 |
| RawSocket E2EE | 0.593 | 20.888 |
| WebSocket clear | 2.291 | 22.156 |
| WebSocket E2EE | 0.594 | 19.182 |

Median client peak RSS for the RawSocket clear path fell from 185.5 to 159.4 MiB;
for RawSocket E2EE it fell from 178.8 to 112.6 MiB. These are process peaks
from each local run, not a controlled allocation profile.

The RawSocket clear FlatBuffers run sent 1 GiB of file data through native buffered file segments and recorded about 16 KiB of measured transport copies from Dart to native. The E2EE run recorded about 22 KiB; crypto and codec dependency copies are not fully instrumented. These results establish the file path improvement on this host, not a hosted release gate or zero-copy claim. Dart buffered FlatBuffers file rows remain slow and are included in `summary.json`.

| Run setting | Value |
| --- | --- |
| Source commit | `b6b79464` (clean during measurement) |
| Host | Apple M3 Ultra; macOS 26.7.1; Dart 3.13.1 |
| Router workers / native runtime threads | 1 / 1 |
| Workloads | 40 per pass; 3 order-rotated passes |
| Runner SHA-256 | `30bd1286f0a4b29b43bec4f31ab592373685e06a84dd6c9c65d99e1e86cf5847` |
| Native FFI SHA-256 | `62869e4bce8ff61e824cb464243249fbe2e1fdcb860b512daa2e47d63f00c373` |

The [summary](summary.json) contains every run and median. `pass1`–`pass3` JSONL files are the original records; the matching TOML files preserve workload settings. Rates use `8 × dominant bytes ÷ elapsed milliseconds ÷ 1,000,000`. The file measurements in the [package throughput table](../../../packages/connectanum_bench/README.md#wamp-throughput) use these medians.
