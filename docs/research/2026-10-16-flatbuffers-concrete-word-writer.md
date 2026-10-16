# Concrete typed-word byte-vector writing

The standard Dart SDK remains in use. The quiet CPU profile at the preceding
checkpoint attributes 140 of 578 client samples to FlatBuffers byte-vector
writing. A concrete `Uint32List.view` allows the pinned FlatBuffers SDK word
writer to copy the same bytes with fewer element operations. Unlike the earlier
rejected generic `ListBase<int>` word adapter, this is a concrete typed-data
view, including for read-only source buffers. It neither reads beyond the
logical source nor changes ownership.

The optimized path requires little-endian host storage, a typed byte input of
at least 256 bytes, and four-byte source and builder offsets. Other inputs use
the original SDK byte writer. A partial last word is assembled from its one to
three logical bytes and zero padding, then written before the full words by
the backward builder. That path is used only when existing capacity suffices;
otherwise it falls back before writing. The vector header retains the byte
element count. No schema, wire format or public buffer lifetime changes.

An independent prototype compared exact SDK output, source immutability,
capacity, allocation count and growth-copy bytes for 38,400 combinations of
length, source offset, read-only/mutable/plain-list input, preceding fields,
capacity and eight-byte alignment. All pass on the VM; the earlier 10,752-case
partial-tail prototype also passes JavaScript. Integrated regressions exercise
these boundaries through the public managed/native builders, including reset,
failed growth, source disposal and rejected writes after freeze/disposal.
The outer builders continue recording the original byte length exactly once;
allocator growth remains independently observed.

A local component experiment uses seven alternating pairs after warmup with
150 ms per writer. For 64 KiB mutable and read-only inputs, and 64 KiB + 1 byte
inputs, the median optimized/SDK writer time is 0.307–0.317. These are component
diagnostics, not end-to-end parity evidence. The complete rows are retained in
`out/flatbuffers-milestone-finish/concrete-word-vector-micro.jsonl`.

The preceding source `25862a53` passes frozen `bin/verify` with all 3,098 inputs
and HEAD unchanged. Its hosted Linux diagnostic completes all 90 rows without
the earlier RSS/duration-boundary failures. It still fails 13 numerical gates:
CPU ratios 1.3456 / 1.3173 / 1.3867 and native-buffer allocation ratio 1.0838,
among others. The diagnostic marker is a fourteenth finding. No budget is
changed and no primary acceptance is claimed.

The new writer requires renewed end-to-end and browser evidence before a
performance conclusion. The existing SDK/TLS/crypto dependency-internal copy
limitations remain explicitly unmeasured under the approved standard-SDK scope.
