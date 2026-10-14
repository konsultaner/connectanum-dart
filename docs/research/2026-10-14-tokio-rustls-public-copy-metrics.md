# Public Tokio-Rustls extraction and optional metrics

The original pinned Tokio-Rustls 0.26.6 observer counts only internal
`Stream::poll_read`. Both public client/server `TlsStream::poll_read` methods
instead call `poll_fill_buf` and copy into their caller's `ReadBuf` directly.
Their initial and batched `put_slice` operations bypass that observer.

Two public-reader tests first report zero instead of three copied bytes.
Four hooks now count the selected length immediately after those successful
copies. The public paths borrow from the internal `poll_fill_buf`, so they do
not double-count the existing internal read hook. The source manifest retains
original upstream digests and records the two additional modified files;
licenses, pinned version and ownership behavior remain unchanged.

Both reader tests cover prefilled, bounded output; repeated borrowed views and
pointer offsets after consumption; 32,769-byte multi-record input; remaining
copied bytes; empty reads and EOF. The observer-enabled vendor suite passes all
16 cases and the disabled suite all 11 cases. Existing pending/error tests
remain included. Actual native TLS network tests additionally verify positive
global extraction observations; exact per-operation assertions use thread-local
test counters rather than concurrent process-wide totals.

`ct_tokio_rustls_copy_metrics_snapshot(uint64_t *out)` returns this cumulative
process-wide source observation through a separate optional scalar ABI.
Null output is rejected; surrounding memory guards remain unchanged. The
six-field, 48-byte Rustls structure and old 24/40-byte transport snapshots
are untouched. Both Dart runtimes optionally resolve the symbol, propagate
null when unavailable and retain established delta/reset semantics. A real
published beta.8-library probe exercises missing-symbol fallback.

The client worker and router merger report the new field separately under
`known_own_copy_breakdown`. Negative or unavailable observations remain
unmeasured. It does not substitute for `tls_copy_bytes`, `transport_copy_bytes`
or complete copy coverage. Rustls growth, other record/crypto copies and Dart
SDK internals remain unmeasured. The complete primary performance campaign
still requires all original metrics and parity budgets.

The independent Python peer also moves from cbor2 5.7.1 to 5.9.0. The
[upstream security advisory](https://github.com/advisories/GHSA-3c37-wwvx-h642)
identifies 5.9.0 as the first fixed version for uncontrolled recursion.
Both requirements and runtime version admission use the new exact pin.
Fresh fixture checks pass 33 unmodified upstream and 42 extended fixtures,
bidirectional Python/Dart/Rust calls, and contiguous/segmented output for all
25 public message types. The live negotiated-profile peer passes RawSocket
and WebSocket using the same pinned dependencies.

Scoped failure, success, build and peer logs are retained under
`out/flatbuffers-milestone-finish/`. Full resulting-source and hosted evidence
are recorded in the active execution plan after completion.
