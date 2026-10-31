# Keep a single borrowed vector header in the native envelope

## Observed work

The source/PID/window/library-audited Linux profile on `65833214` attributes
1.90% inclusive native samples to RESULT forwarding for FlatBuffers, versus
0.71% for MessagePack. These overlapping samples are diagnostic, not per-operation
CPU or acceptance results. The strict 90-row `b2fb8b63` diagnostic still fails
parity (CPU ratios 1.0099 / 1.0057 / 1.0038), despite allocation parity in all
three construction groups. Its full local verification and renewed 300 short
rows, 120 accounting cases and 36 progressive combinations pass with all 3,124
source inputs unchanged. No primary or supplemental acceptance is established.

The native segmented writer creates an empty placeholder per application vector,
then appends another allocated length/padding segment and the retained body.
RawSocket already uses scatter/gather; this is an envelope allocation and segment
reduction, not a claim to remove a syscall from every cleartext write.

## Change and ownership

When the direct message table contains exactly one encoded args, kwargs or opaque
payload vector, create its empty byte-vector placeholder before other builder
objects. The pinned FlatBuffers builder grows backwards, so that placeholder's
four-byte length is last in the final envelope, including across buffer growth.
The writer uses its ordinary typed offset, patches only that length while the
header Vec is uniquely owned, checks the terminal offset and whole-frame limit,
and returns the envelope followed by the exact original Bytes owner. Empty
bodies remain explicit segments. No application byte is copied or interpreted.

Zero-vector, multiple-vector and contiguous encoding retain their existing paths.
The general segmented fallback still has independent offset, alignment and byte
limit checks. Schema projection, CBOR validation, scalar/string/depth limits and
metadata agreement remain in force. No ABI, negotiation or wire schema changes.
FlatBuffers permits this different valid layout; exact compiler-layout identity
is not a protocol requirement.

## Verification and limits

- Baseline `bin/test-fast` passes before changes.
- A test first reproduces three segments where one envelope and one original
  owner suffice, with the original writer SHA unchanged during reproduction.
- All 386 core tests, 26 segmented FFI forwarding tests and 26 FlatBuffers FFI
  tests pass after the change, including mixed codecs and real native networking.
- Existing generated-verifier/public-model tests now require the minimal segment
  count too. New tests cover request IDs 0/1/maximum, lengths 0–39 and 128 KiB,
  args/kwargs/opaque, guarded unaligned source slices and repeated builder growth.
  Original pointers, length prefixes, semantic decode and segmented input are
  checked after original handles are dropped.
- Local companion review is advisory. The backwards-builder/unique-header
  invariants and actual generated-verifier results address its speculative
  layout/aliasing concerns. The pinned schema has no nested application vectors;
  unexpected multiple vectors still use the general fallback.

Evidence lives under `out/flatbuffers-milestone-finish/terminal-vector-*` in the
managed FlatBuffers worktree. These correctness checks do not establish speed.
Fresh frozen production-library copy/volume proofs and a strict Linux diagnostic
are required next. Final full verification, hosted CI, five-platform consumers
and the complete unchanged 48-case/1,440-row primary plus 50-case/1,500-row
supplemental acceptance campaigns remain required before closing #103.
