# HTTP/2 Phase Timing Hosted Rerun

Status: in_progress

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
