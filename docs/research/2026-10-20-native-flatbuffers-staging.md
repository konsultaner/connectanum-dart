# Bounded native FlatBuffers staging

Date: 2026-10-20. Scope: issue #103, performance PR #132.

The strict pinned-toolchain diagnostic on `53c19b72` completes all 90 rows but
fails thirteen numerical gates. All three allocation comparisons pass. Its
report is independently recomputed from the original manifest and rows. This
is diagnostic evidence, not complete primary acceptance.

The Linux CPU profile identifies control parsing and construction overhead;
writer construction is a small contributor. Source inspection finds one slot
vector per table and an additional vector collecting borrowed payload owners.
These temporary allocations do not hold application bytes and are unnecessary.

The proposed writer derives its maximum table field count from the pinned
schema at compile time. A bounded array stages slots. After the table is
finished, borrowed owners move directly into the existing deferred-vector list,
in the same reverse slot order. Validation, wire construction order, payload
owners, resource limits and copy counters are preserved. No unsafe code or new
dependency is introduced.

## Controlled reproduction

An ignored source copy contains 1,019 hashed source/fixture inputs. Only
`flatbuffers_writer.rs` differs. Both versions use the same compiler, dependencies,
configuration, probe and output target. Restoring the original writer restores
the original allocation counts. The compiler is local macOS/arm64 Rust 1.95.0;
these results are allocation counts, not hosted speed measurements.

A thread-local counting allocator wraps the public encoder. Message creation,
probe reporting and output verification occur outside the observed interval.
The probe counts allocation requests and requested bytes, including the new size
of a reallocation; it does not estimate live heap size or RSS. Ten repeated
encodings agree at each body size.

| Opaque body bytes | Segmented allocation calls, before → after | Segmented requested bytes, before → after |
| --- | --- | --- |
| 0 | 15 → 12 | 3,360 → 2,520 |
| 1,024 | 15 → 12 | 3,360 → 2,520 |
| 1,048,576 | 15 → 12 | 3,360 → 2,520 |

The application segment retains its original pointer and length. Contiguous
encoding saves two staging allocations and 680 requested bytes at each size;
its existing application-copy behavior is preserved.

All 31 FlatBuffers tests pass in the isolated proposal, including generated
verifier, malformed-buffer and segmented-owner coverage. Independent encoding
of all 25 public fixture models plus the three opaque body sizes produces 56
byte-for-byte identical contiguous/segmented streams before and after the
change. Each representation also decodes to the same message.

## Acceptance boundary

This reproduction establishes a bounded allocation improvement. It does not
establish throughput, latency, CPU, GC or RSS parity. Complete unchanged-policy
primary and supplemental campaigns, renewed production copy proofs, canonical
verification and hosted checks remain necessary. The intermittent payload
workload timeout is a separate unresolved observation.

Evidence is retained under `out/flatbuffers-resume-20261020/`, including
`writer-probe-source-manifest.json`, `writer-allocation-controlled-comparison.json`,
`writer-wire-controlled-comparison.json` and `writer-proposed-tests.log`.
