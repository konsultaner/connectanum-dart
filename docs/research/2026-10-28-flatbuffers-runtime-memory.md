# FlatBuffers runtime memory attribution

Product source: `28642b03087b3c89ed003e7867e635dca30df7e7`.
[Allocator capture](https://github.com/konsultaner/connectanum-dart/actions/runs/40696555847).
Case: `rpc_rawsocket_clear_dart_values`.

This diagnostic completes six fresh process pairs in the order FlatBuffers,
CBOR, MessagePack, MessagePack, CBOR, FlatBuffers. It uses the standard SDK,
the declared workloads and measured repetitions, without forced GC, allocator
trimming or heap tuning. Read-only allocator/VM snapshots perturb execution;
the result is explicitly ineligible for performance acceptance.

At `before_last_report`, the worker snapshots contain these MiB values:

| Pair | Codec | RSS | Main heap used | VM page cache | Estimated glibc arena in use | Free glibc bins |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 0 | FlatBuffers | 197.1 | 39.0 | 31.5 | 2.2 | 17.6 |
| 1 | CBOR | 198.5 | 58.9 | 19.5 | 3.2 | 18.6 |
| 2 | MessagePack | 183.7 | 61.5 | 3.5 | 2.7 | 14.0 |
| 3 | MessagePack | 179.7 | 60.5 | 4.0 | 2.8 | 11.4 |
| 4 | CBOR | 199.6 | 70.9 | 7.0 | 4.8 | 19.3 |
| 5 | FlatBuffers | 195.0 | 62.0 | 5.0 | 2.5 | 24.9 |

Router RSS is 238.7/244.4 MiB for FlatBuffers, 219.7/210.1 MiB for CBOR and
235.1/233.4 MiB for MessagePack. Estimated glibc arena usage stays approximately
4.1–4.6 MiB across all router snapshots. The estimate subtracts free fast/rest
bins from arena system bytes; it excludes separate mmap allocations and does
not classify thread caches as free.

These snapshots show different heap/cache states rather than a demonstrated
live native-allocation leak. They do not prove that all additional RSS is unused
memory: allocator counters and VM buckets are non-atomic, free-bin bytes are not
resident-byte measurements, and unclassified resident mappings remain. Do not
subtract these counters from the RSS acceptance metric.

The current paired diagnostic
[40693409305](https://github.com/konsultaner/connectanum-dart/actions/runs/40693409305)
still fails eight numerical gates. Both native modes pass throughput, latency,
CPU, allocation and GC comparisons but fail RSS. Dart values have additional
CPU/GC/throughput/latency failures. Neither this capture nor the intrusive CPU
profile replaces those results or the full primary/supplemental campaigns.

The [current CPU capture](https://github.com/konsultaner/connectanum-dart/actions/runs/40698440958)
contains unresolved hot client perf addresses. Retain client JIT symbols, as
already done for the router, before attributing those samples to an operation.
Dart VM samples can include native/blocking stacks and are not CPU-cycle
attribution. Keep every failed observation and all declared budgets unchanged.

The diagnostic also retains PID-filtered `perf script` output for the same
interior operation interval, including absolute instruction addresses. These
can be matched to each PID's JIT map even when a report displays unresolved
module-relative addresses. The fields follow the
[perf-script documentation](https://man7.org/linux/man-pages/man1/perf-script.1.html).
Reused JIT address ranges remain an explicit attribution limitation.


## Resolved client CPU samples

[Capture 40705845411, attempt 2](https://github.com/konsultaner/connectanum-dart/actions/runs/40705845411/attempts/2)
on `1c80fbf4331c6e732d24bdc4638d53c83eb9a463` retains both process maps and
absolute samples, with source/launcher/binary integrity verified. Attempt 1's
perf startup exit 255 is retained separately; the successful retry is the same
source and profiling configuration, not performance acceptance.

Matching exclusive CPU-clock sample addresses to unambiguous JIT ranges gives:

| Client codec | Samples | Body generation | Body verification | Byte-array allocation | Ambiguous JIT address |
| --- | ---: | ---: | ---: | ---: | ---: |
| FlatBuffers | 1135 | 314 | 137 | 74 | 16 |
| MessagePack | 1164 | 251 | 387 | 18 | 28 |
| CBOR | 2389 | 159 | 104 | 46 | 25 |

These are sample counts, not normalized per-operation timings. CBOR also spends
1291 samples in `Uint8List._slowSetRange`. Keep outside-JIT samples separate;
reused address ranges with different names cannot be assigned confidently.
The shared deterministic body loop is a measured optimization candidate across
all three codecs. Its word-fill candidate preserves the arithmetic reference,
input identities and copy-accounting semantics. Only the unchanged paired
campaign can determine whether that change improves performance parity.
