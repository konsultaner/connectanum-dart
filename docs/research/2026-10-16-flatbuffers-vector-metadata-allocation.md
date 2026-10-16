# FlatBuffers vector writes and metadata allocation

The pinned Dart `flat_buffers` 25.9.23 builder writes byte vectors one element at
a time. Its public uint32 vector writer handles four bytes per iteration. With
an existing tail divisible by four, the two layouts reserve the same
`4 + roundUp(byteLength, 4)` bytes. A read-only little-endian word view can feed
that writer without an intermediate array; the byte count replaces the word
count in the latest allocation after any growth. Partial final words are zero
padded. Short, ordinary-list and unaligned inputs retain the standard byte
writer. The wire format, vector alignment and allocator ownership are unchanged.

The shared helper serves the managed WAMP builder and the guarded native builder.
The outer copy observer still records exactly the original source byte length
once. Native input-copy and allocator-growth counters retain their existing
meaning. The helper never falls back after modifying the builder.

Scalar metadata dictionaries now validate and materialize in one scan. That scan
checks the map root, inclusive 1 MiB limit, item charging, string keys, duplicate
keys, UTF-8, integer width and portable range, indefinite chunks and trailing
input. Complex and wide values retain the original complete validator and CBOR
materializer. Exact integers at both +2^53 and -2^53 remain supported. Unicode
keys retain their exact strings; no case folding or Unicode normalization is
introduced.

Before integration, an isolated comparison against source `63a802f7` passes
4,752 exact SDK wire comparisons on VM, JS and Wasm, 336 native ownership cases,
and 16,415 valid, malformed, mutated and truncated metadata inputs. All 3,358
existing serializer cases and 150 metadata/fuzz browser cases per compiler pass.
The integrated regression tests retain representative full-wire comparisons
across all eight prefix alignments, vector remainders, growth, partial/read-only
views, ordinary-list fallback, native release and source mutation. Additional
scalar cases check every truncated prefix of 32 seeded Unicode dictionaries
and both sides of the metadata byte limit.

This is correctness evidence. It does not establish throughput, latency,
allocation, CPU, GC or RSS parity. The preceding scalar-map diagnostic still
fails the unchanged budgets. New paired measurements and final combined
verification remain required. No primary case, minimum duration, sample count,
repetition, mutation inventory or coverage floor is reduced.

The preceding frozen full `bin/verify` passes at `63a802f7` with all 3,095 inputs
and HEAD unchanged. Its five-platform production consumers pass 170 cases with
zero skips and independently checked log hashes; package publishing dry run also
passes. Its macOS benchmark coverage is 97.82% (3,810/3,895), with Linux-only CPU
and RSS collector paths unmeasured locally. Hosted Linux coverage remains the
required 98% gate.
