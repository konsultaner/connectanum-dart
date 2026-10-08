# First hosted FlatBuffers primary result

The [hosted campaign](https://github.com/konsultaner/connectanum-dart/actions/runs/37582544124)
for frozen source `a5c6aaf9a475ac983ca2397a063646d600f3ba1f` completes all 1,440
scheduled rows: 48 cases, three codecs, three warmup passes and seven measured
passes. Every pass contains 144 rows. The driver exits 0 and its process group
stops; the manifest reports no overlap, unchanged inputs and a clean checkout.
[Uploaded evidence](https://github.com/konsultaner/connectanum-dart/actions/runs/37582544124/artifacts/11480699094)
retains the manifest, policy, rows, comparison, logs and production executables.
Uploaded policy and executable hashes verify. A local replay with that policy
reproduces every case, finding and metric result exactly.

The comparison fails with 2,129 findings. Throughput, p95/p99 latency, CPU and
allocation gates each fail in all 48 cases; sampled RSS fails in 36. The median
across the 48 throughput case ratios is 0.704 against the better binary baseline.
That aggregate describes the report and does not replace any per-case gate.
There are 756 missing transport-copy, 504 missing TLS-copy and 252 missing
WebSocket-mask-copy observations, plus 336 zero-baseline GC comparisons.
Five measured windows are below the required 10,000 ms: 9,999.973–9,999.991 ms.
The minimum stays strict; these rows are not rounded into acceptance.

All 1,008 measured rows record zero total client/server GC events. A separate
Dart 3.13.1 VM-service probe forces collections using
`getAllocationProfile(gc: true)` for every application isolate. Its raw timeline
contains `CollectNewGeneration`/`CollectOldGeneration`, category `GC`, phases
`B`/`E`, while the existing collector returns zero count and pause time.
A positive-metric regression fails. The collector filters event names containing
`gc` and complete-duration events, so it ignores these actual collection spans.
The [pinned Dart VM implementation](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/vm/heap/heap.cc)
places collection timing inside its GC safepoint operations. Nested GC subspans
and concurrent background work must not be double counted as pause time;
unknown or incomplete traces must remain unmeasured. No collector source repair
is included in this result checkpoint.

This is failing evidence for the recorded source. It does not establish newer
source performance, complete copies or milestone acceptance. Every original
supplement, all eight normative copy fields, all primary cases and all declared
parity/resource budgets remain required. The next benchmark work must repair
measurement and actual performance before a new complete campaign.
