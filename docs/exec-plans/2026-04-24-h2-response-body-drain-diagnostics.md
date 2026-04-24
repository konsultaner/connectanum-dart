# HTTP/2 Response-Body Drain Diagnostics

Status: in_progress

## Context

- Commit `a88a8b7` is green on the hosted push chain:
  - `CI` `24874851886`
  - `kTLS Validation` `24874851872`
  - `WAMP Profile Benchmarks` `24874851879`
- Manual hosted run `24875528924` closed the broader request-path hypothesis
  on `native/bench/scenarios/h2_ktls_multiplex_scaling.toml`:
  - `stream acquire wait avg` improved slightly on the hotspot row
  - `request enqueue avg` stayed negligible
  - `response headers wait avg` stayed effectively flat
  - `response body read avg` and `response body read p95` exploded on
    `h2_multiplexed_streams_s8` at `threads=1`
- The remaining regression is therefore in the response-body drain itself, but
  the current artifacts still do not separate first-body-byte wait from the
  sustained body-drain tail or show the chunk shape observed by the client.

## Goals

1. Split the HTTP/2 response-body drain into narrower diagnostic signals.
2. Keep the push CI chain green on the next instrumentation checkpoint.
3. Rerun the focused hosted `kTLS HTTP/2 Benchmarks` workflow and decide
   whether the remaining regression is dominated by first-body-byte delay, the
   sustained body-drain tail, or an unexpected chunk-shape change.

## Planned Changes

1. Extend the HTTP phase timing model with response-body-drain sub-phases and
   chunk-shape counters on the HTTP/2 client path.
2. Surface those new signals in the transformed artifact summaries and compare
   output.
3. Push the new checkpoint on a clean head and rerun the focused hosted
   multiplex benchmark.

## Progress

- The local instrumentation slice is now in place:
  - HTTP/2 bench samples record response-body first-chunk wait, tail-read
    time, observed chunk count, and first-chunk bytes
  - transformed summaries and `tool/ktls_http2_compare.py` now expose those
    metrics in the phase focus lines and a dedicated
    `HTTP Response-Body Diagnostics` section
- Rerendering historical hosted artifact `24875528924` stays backward
  compatible; the new fields show `n/a` there because that summary bundle was
  generated before this instrumentation existed.
- The next remaining step in this plan is the clean pushed checkpoint plus the
  focused hosted rerun on that exact head.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- rerender hosted artifact `24875528924`
- `bin/verify`
