# Internal PPT byte views

A diagnostic server CPU sample identifies `_lazyPayloadFromTransferredWithPpt`
calling the full CBOR decoder to recover an opaque singleton binary argument.
The old helper also clones the complete encoded input with `toList()` and clones
CBOR binary values again. The benchmark's ordinary internal echo needs only the
packed bytes. Client-only samples do not identify this server-side cost.

## Change and limits

An internal helper accepts exactly a fixed singleton-array header followed by a
definite CBOR byte string or MessagePack binary value filling the entire logical
input range. It retains an immutable subview. Bounds and length-prefix arithmetic
are checked before constructing the view; eight-byte CBOR lengths cannot overflow
an intermediate integer. Other forms, truncation, oversized lengths, trailing
bytes, JSON and typed FlatBuffers fragments decline to the existing decoder.
The application schema remains opaque.

Transferred payload reconstruction first reuses an existing packed body, then
tries the view when materialized arguments and outer keyword bytes are absent.
Other cases retain the existing fallback. The fallback CBOR decoder receives
its Uint8List directly, removing an unnecessary boxed-list clone. Keyword,
indefinite-container and noncanonical-array handling is not narrowed.

The native byte export retains its existing ownership contract. This helper
does not extend a foreign database transaction or adopt foreign memory.

## Reproduction and validation

Nineteen helper cases first fail against an unavailable view. More importantly,
the public native RPC test fails on unchanged source for FlatBuffers and CBOR:
a 4,136-byte body occupies a fresh exactly 4,136-byte allocation. MessagePack
already retains its encoded storage at that boundary. The repaired three-codec
test verifies retained allocation extent, immutable contents and a valid body
after closing its native message and sessions.

Twenty helper cases pass for empty/large bodies, guarded offset subviews, all
byte-length header widths, mutation-visible aliasing, malformed/trailing bytes
and unsupported shapes. The complete public PPT matrix passes 107 cases, and
nine existing internal lazy/PPT/E2EE regressions pass. Analysis is clean.

The CPU diagnostics are not acceptance evidence. One initial run misses the
worker entrypoint and captures no stacks; a corrected client run captures six
workload windows but lacks the required warmup/repetition count. The server
follow-up captures the first workloads, then stops when a tiny untimed warmup
produces zero client samples. Its failed execution and teardown are retained.
Main-isolate CPU profiling is not a Rust-thread profile. All timing/resource
comparisons from those profiled runs remain excluded.

A separate unprofiled, paired before/after diagnostic and frozen full
verification are pending. All existing performance budgets, matrix dimensions,
copy counters, sample requirements and acceptance conditions remain unchanged.
