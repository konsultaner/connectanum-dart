# HTTP/2 Headers-Queued to First-Connection-Write

Status: completed

## Context

- Commit `0a9c3c8` passed the visible hosted GitHub push chain:
  - `CI` `24893449385`
  - `kTLS Validation` `24893449381`
  - `WAMP Profile Benchmarks` `24893449378`
- Manual hosted rerun `24894437415` then ran on clean head `0a9c3c8` to answer
  whether the remaining hotspot lived after HTTP/2 headers were queued and
  before the first actual connection write.

## Goals

1. Expose the gap between queued HTTP/2 headers and the first actual
   connection write.
2. Preserve a clean push CI chain on that checkpoint.
3. Use a focused hosted rerun to decide whether the remaining multiplex
   regression is dominated by the transport-write path after
   `send_response(...)` returns.

## Outcome

- The hosted rerun answered the question directly: the remaining hotspot is not
  the post-header transport-write path.
- Worst throughput and p95 row:
  `h2_multiplexed_streams_s8`, `threads=4`
  - `response headers wait avg 24.10 -> 211.03 (+186.93)`
  - `response body first chunk wait avg 8.92 -> 72.21 (+63.29)`
  - `native headers-to-first-connection-write avg 0.16 -> 0.12 (-0.04)`
  - `native headers-to-first-chunk-dequeue avg 6.95 -> 68.54 (+61.59)`
  - `native headers-to-first-chunk-send-call avg 7.41 -> 69.35 (+61.94)`
  - `server queue-to-first-body-write avg 12.33 -> 104.86 (+92.53)`
  - `server direct-stream open round trip avg 12.29 -> 104.83 (+92.53)`
  - `server direct-stream descriptor-open call avg 0.05 -> 0.03 (-0.01)`
- Connection reuse and transport counters stayed effectively flat on the
  hotspot row, so the remaining blind spot moved back into the direct-stream
  control/open path outside `descriptorOpenUs`.
- The next bounded slice is therefore to split
  `direct_stream_open_round_trip` into request-side control-queue delay and
  reply-side delivery delay.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `python3 tool/ktls_http2_compare.py tmp/ktls-run-24894437415/extracted/baseline/bench_results.summary.json tmp/ktls-run-24894437415/extracted/ktls/bench_results.summary.json tmp/ktls-run-24894437415/rerender/comparison.json tmp/ktls-run-24894437415/rerender/comparison.md`
- `bin/verify`
