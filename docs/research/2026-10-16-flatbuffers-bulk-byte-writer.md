# FlatBuffers bulk byte-vector backend

The standard Dart SDK remains unchanged. A VM builder implements the existing
`flat_buffers.Builder` interface so generated application models and the public
Connectanum builders retain their API. Its implementation derives from
[FlatBuffers 25.9.23](https://github.com/google/flatbuffers/blob/v25.9.23/dart/lib/flat_buffers.dart),
verified against upstream Git blob `7590bdba690c594fe095273d0f1ab110a7960475`.
The source manifest and Apache-2.0 license are retained beside the implementation.

The private backend bulk-copies independent `Uint8List` vectors of at least
256 bytes after the original SDK reservation. All other byte inputs retain the
SDK loop, including same-buffer aliases. VM source views retain their logical
offset/length and read-only inputs remain unchanged. Browser read-only buffer
wrappers hide backing identity, as reproduced by an overlap regression;
conditional export retains the standard SDK builder on web targets.

Existing managed/native wrappers observe byte-vector and growth copies once.
The SDK-derived implementation records its explicit UTF-8 staging as framing
copies, including inside an outer PPT observation scope. UTF-8 encoder internals
remain dependency-labelled. Bool vectors now encode directly from bool values,
avoiding the SDK's intermediate byte-value list. Both changes have fail-first
accounting regressions; incomplete UTF-8 staging preserves failed-copy evidence.
The native six-u64 copy ABI is unchanged. Outgoing profile validation is unchanged.

A prototype matches exact SDK wire bytes, source immutability, allocation
capacity/count and growth-copy bytes in 38,400 cases. Integrated tests include
5,184 byte-layout combinations, signed bytes, 64-bit platform outcomes, all
scalar/vector families, struct builders, nested tables, string interning,
table deduplication, reset, read-only overlap, and native-source disposal.
Seven alternating component pairs put the 64 KiB bulk writer at 0.0095–0.0121
of the SDK byte loop's time. These are diagnostics, not performance acceptance.

The metadata reader also reuses the existing UTF-8 validation result to construct
ASCII strings without a temporary byte view. All UTF-8, span and CBOR limits
remain enforced. A 30,096-case baseline/candidate decoding/error probe passes;
component decoding time ratios are 0.7376 / 0.7466 for ASCII/mixed text.
Independently validated allocation observations fall from 1,649–1,671 to
1,074–1,077 bytes per representative dictionary, with bounds below 2 bytes/op.

Checks pass: 3,386 serializer VM, 3,391 JavaScript, 3,381 Wasm and 30 native-owner
tests; analysis and all 154 mutation proofs; 51 generated artifacts and the
typed fixture binding. Independent upstream/extended readers accept 33/42
fixtures; bidirectional Python/Dart/Rust Call and all 25 public message forms
agree. Resulting-source full verification, renewed live copy accounting,
five-platform production consumers and Linux performance remain required.

The preceding `5dda2ecd` Linux campaign still fails CPU at 1.1590 / 1.1782 /
1.1633 and native-buffer allocation at 1.0634. Every original primary budget,
case, sample minimum, duration, repetition and coverage floor remains unchanged.
Actual encoded-size measurement and extension diagnostics remain outstanding.
