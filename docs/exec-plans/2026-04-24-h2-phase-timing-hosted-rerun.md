# HTTP/2 Phase Timing Hosted Rerun

Status: completed

## Context

- Commit `55f23d3` is green on the hosted push chain:
  - `CI` `24872329789`
  - `kTLS Validation` `24872329782`
  - `WAMP Profile Benchmarks` `24872329792`
- Manual hosted run `24872903498` ruled out connection churn on the focused
  `h2_ktls_multiplex_scaling` scenario:
  - `connections_opened` stayed flat at `4 -> 4 (+0)` for every row
  - `samples_per_connection_avg` stayed flat at `20.00 -> 20.00 (+0.00)` for
    every row
- The remaining hotspot is still the reused-connection HTTP/2 multiplex path,
  especially `threads=4`, but the current artifacts do not yet separate
  stream-acquire wait from the post-acquire request round trip.
- The local working tree now carries a new diagnostic slice:
  - HTTP bench samples can record optional HTTP phase timing
  - transformed artifact summaries can expose phase-timing aggregates
  - `tool/ktls_http2_compare.py` can render worst-row phase views plus a
    dedicated `HTTP Phase Timing` section

## Goals

1. Push the phase-timing instrumentation on a clean branch head.
2. Keep the push CI chain green before dispatching another manual rerun.
3. Rerun the focused hosted `kTLS HTTP/2 Benchmarks` workflow and use the new
   phase-timing section to decide whether the hotspot is dominated by
   stream-slot acquisition or by the post-acquire request path.

## Planned Changes

1. Verify and push the phase-timing instrumentation slice with refreshed state
   docs.
2. Wait for the push `CI`, `kTLS Validation`, and `WAMP Profile Benchmarks`
   runs to clear on that exact head.
3. Dispatch the focused manual `kTLS HTTP/2 Benchmarks` rerun on
   `native/bench/scenarios/h2_ktls_multiplex_scaling.toml`.
4. Record whether required-kTLS inflates `stream_acquire_wait_*` or
   `request_round_trip_*` on the worst multiplex rows.

## Verification

- `bin/test-fast`
- `cargo test --manifest-path native/bench/Cargo.toml -- --nocapture`
- `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
- `python3 tool/test_ktls_http2_compare.py`
- `bin/verify`

## Outcome

- Commit `3d85b51` (`build(ktls): capture http2 phase timing`) cleared the
  hosted push chain:
  - `CI` `24873599372`
  - `kTLS Validation` `24873599375`
  - `WAMP Profile Benchmarks` `24873599379`
- Manual hosted run `24874338657` (`kTLS HTTP/2 Benchmarks`) then reran
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` on that clean head.
- The new phase-timing section ruled out stream-slot acquisition as the main
  regression source:
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4` held
    `stream acquire wait avg 0.00 -> 0.00 (+0.00)` while
    `request round trip avg 18.20 -> 31.72 (+13.53)`
  - worst p95 row:
    `h2_multiplexed_streams_s8` at `threads=1` held
    `stream acquire wait p95 0.00 -> 0.12 (+0.12)` while
    `request round trip p95 39.13 -> 70.01 (+30.88)`
- The next bounded diagnostic slice is therefore deeper HTTP/2 request-path
  timing so the hosted artifacts can separate request upload, response-header
  wait, and response-body drain.
