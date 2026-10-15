# PPT serializer and native plaintext framing observations

This follow-up extends the approved standard-SDK boundary measurements. It
adds observations of actual Connectanum copies rather than estimating a total
from message sizes. Complete E2EE/transcode acceptance remains open.

## Provider plaintext serializers

A synchronous, isolate-local `PptCopyMetrics` scope surrounds the built-in
portable and native providers' PPT serialization/deserialization. Ordinary
outer WAMP serialization does not enter this scope. Collection is disabled
outside a benchmark window; nested scopes and exceptions restore their depth.
The worker records both of its RPC endpoints in the same isolate and retains
this breakdown separately from portable cipher, native bridge and Rust copies.

CBOR records its explicit encoded-buffer wrapping, decoded binary clones and
multi-fragment PPT coalescing. A 65-byte singleton binary body requires a
two-byte header copy and an 82-byte envelope assembly. Its canonical decoder
retains a plaintext view. General args/kwargs exercise additional encoded and
decoded copies: the fixture's 8-byte args, 9-byte kwargs, 30-byte envelope and
7 decoded binary bytes account for 54 bytes. A failed kwargs conversion still
records the five argument bytes copied before the exception.

First use also copies fifteen bytes of reusable metadata. This setup has its
own counter; subsequent calls reuse those buffers. Typed marker buffers avoid
repeated `BytesBuilder.add(List<int>)` coercions. Tests distinguish cold setup
from later payload/envelope work. FlatBuffers' typed PPT serialization retains
the input span and performs none of these copies. Crypto output computation
and dependency internals stay separate from these source observations.

The initial observation tests fail before the hooks: CBOR operations report
zero. The partial-failure test initially assumes the wrong dependency exception;
it now supplies a deliberate throwing conversion and checks exception identity.
The first implementation also needs an explicit nonnullable generic result in
both providers. These failed attempts are retained as diagnostic evidence.

## Native CBOR plaintext framing

`ct_e2ee_plaintext_framing_copy_metrics_snapshot(uint64_t*)` is an optional,
additive scalar. The existing sixteen-byte crypto struct and version are
unchanged. It records actual native file-wrapper prefix/header/footer copies
and multi-byte canonical byte-string header copies used during validation.
File reads, key material and cipher output computation are not memory-copy
observations. Header vectors reserve their complete small capacity before
writing, avoiding an unnecessary growth allocation.

The real file operation fails first at zero rather than sixteen wrapper bytes.
Nine Rust crypto cases then pass, including zero/24/256/65,536-byte file spans,
exact header and wrapper increments, rejected ranges, decryption, a null output
returning -4, old struct size and unchanged adjacent guard words. Optional Dart
lookup and nullable deltas retain absence rather than replacing it with zero.
A fresh-process probe observes availability with the rebuilt library and null
with the preceding five-platform production library.

## Validation and limits

Fresh pre-change `bin/test-fast` passes on unchanged combined head `8f1fbfb9`.
The updated focused suite passes 131 randomized VM/native cases against the matching
ffi-test library. Browser and live validation are recorded in project state.
The live worker retains explicit zero typed-PPT copies, positive CBOR serializer
copies and positive native plaintext framing for encrypted file transfer. Its
existing data-size and content checks remain in place. The unrelated regular
buffered-file-segment counter is not an encrypted-file framing oracle.

An attempted broad test run against the older production library hits tests
requiring test-only owner oracles and a local reexport install name. The matching
ffi-test retry passes; the separate production optional-ABI probe succeeds.
Resulting-source `CARGO_INCREMENTAL=0 bin/verify` passes at `7976a464`,
with Git HEAD and all 3,052 tracked hashes unchanged. The complete 315-mutant
E2EE target passes at 95.3125% with the original 95% floor and zero errors or
timeouts. All 30 randomized browser and nine live RPC/file cases pass. Cargo incremental caches
and orphaned object intermediates are cleared when disk space becomes tight;
source, executables, release libraries and retained evidence are preserved.

The broad Qwen review reaches its token limit and the GLM judge times out.
A bounded review completes without a confirmed issue. Its speculative domain,
threading and minimum-header concerns are checked against the implementation:
Dart isolate statics are independent, process and isolate counters have distinct
labels, and zero-length/one-byte headers are tested. Complete outer WAMP
serializer/framing and mixed-serializer copy accounting remain blockers. No
performance budget, matrix, inventory or acceptance threshold is changed.

The follow-up metadata review correctly identifies a test-order dependency in
the first cold assertion. A deterministic `setUpAll` fixture now captures cold
setup before any test and warms subsequent operations, so randomized test
ordering cannot select which case sees those fifteen bytes. The native tests
also warm their shared serializer explicitly. The randomized focused VM/native
suite passes all 131 cases. The review's other threading and teardown concerns
do not reproduce: isolate statics are independent and every window has cleanup.
