# Raw-frame ownership and exact benchmark buffers

The native raw-frame regression reproduces an unnecessary copy for a single
segmented `Bytes` span. Returning that span preserves its pointer, bounded range
and owner; the owner releases only after the final derived view is dropped.
Multiple spans still coalesce. Reversed range requests now return unavailable
instead of panicking, reproduced with the previous range guard.

Four cumulative native counters distinguish actual coalescing/range copy bytes
from requests for contiguous segmented frames. Already contiguous frames do not
increment request counters. The additive optional v1 C snapshot is 32 bytes;
existing APIs are unchanged and older libraries return unavailable in Dart.
Snapshots do not fence in-flight parsing, so these are partial diagnostics, not
complete per-workload copy acceptance. Benchmark client/router deltas fail closed
on unavailable, invalid or rewound observations.

All 366 Rust core cases, three focused raw-frame regressions, the C ABI guard
case, 46 fixture/report cases, and 117 public router/native PPT cases pass.
Fresh-process probes cover both Dart runtimes against the rebuilt library and
an older production library. Three live RawSocket codec observations pass and
report zero at these raw-frame boundaries. The singleton optimization therefore
does not establish an improvement for those unfragmented workloads.

The pinned benchmark payload writes three slots and needs 40 bytes plus its
8-byte-aligned body. Exact initial sizing preserves wire bytes and produces a
whole Dart backing array. The old sizing fails the new backing-range assertion;
54 probe models and the checked-in boundary/value matrix pass with exact sizing.
No timed throughput improvement is claimed yet.

Evidence remains under ignored `out/flatbuffers-milestone-finish/` with prefixes
`raw-frame-`, `fixture-capacity-` and `bench-exact-capacity-`. Complete owned
E2EE/transcode accounting, fresh frozen full verification, current production
artifacts and the full Linux parity campaign remain required. Issues #100,
#101 and #103 remain open.
