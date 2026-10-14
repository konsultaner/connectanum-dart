# Borrowed outbound FFI copies

The standard-SDK scope still requires copies performed by Connectanum itself.
Source inspection finds that the router's ordinary send first fills a native
staging allocation in Dart, then `ct_send_message` performs another
`Bytes::copy_from_slice` in Rust. The existing Dart-to-native counter observes
only the first copy. Native clients normally use the established owned-send
API, which adopts the Rust allocation instead.

A separate optional scalar export,
`ct_ffi_borrowed_send_copy_metrics_snapshot(uint64_t *out)`, observes the eight
actual borrowed-input copy sites: ordinary and fragmented sends, and the
prefix/suffix inputs of raw, base64 and native-E2EE file sends. It preserves
all existing 24/40/48-byte snapshot layouts. Copies count even if later file
lookup or enqueueing fails; validation before the copy contributes zero.
The thread-local Rust test oracle avoids parallel-test noise. The process
snapshot is cumulative and does not synchronize concurrent operations.

The fail-first tests report zero instead of three bytes for rejected sends
and zero instead of five for file wrappers. All five cases pass after the
source hooks, including zero-copy owned submission, early rejection, partial
prefix work before suffix rejection, null output and adjacent-storage guards.

Both Dart runtimes retain the optional observation and nullable deltas.
`ffi_borrowed_send_input_copy_bytes` is separate from Dart staging, builder,
TLS, serializer and crypto counts. Native client and router totals require
this field. Absence of the observer leaves owned coverage partial; older
libraries remain usable but cannot certify complete copy accounting.
No accepted campaign predates this refinement of the unpublished v1 scope.
Numerical performance/resource and sample/window budgets stay unchanged.

The router now uses the existing allocator/free/owned-submit triad when all
three symbols are available. It fills that allocation once and submits it
with validated positive signed-32-bit length and non-null allocator output.
Rust consumes this valid allocation on enqueue success and failure. Dart must
not infer ownership from an error code: rejection can happen after adoption.
Only failures before submission free locally. Empty sends and the older
borrowed ABI retain their supported behavior. Original application or database
storage is never transferred through this API.

A real isolated Dart ABI probe checks three copied bytes from borrowed C
submission, then three Dart staging bytes and zero additional Rust bytes from
the router's owned submission on rejection. Old-library tests require null
observations and nullable deltas, preserving the ABI compatibility contract.
Qwen test planning/review and GLM design advice are advisory. GLM's suggested
error-code-dependent cleanup is rejected against source: the helper validates
its arguments before submission, and freeing valid consumed input on an error
would double-free. Full resulting-source verification passes at exit 0; GuardMalloc passes 87
cases with 266 source/lockfile hashes, group logs and executable verified.
The older production ABI also passes, with the absent observation remaining
null. New-head hosted acceptance remains required.
E2EE/transcode pipeline gaps and actual performance parity remain open.
