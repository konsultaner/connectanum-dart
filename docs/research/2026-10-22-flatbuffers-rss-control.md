# Fresh-process RSS discrimination

The independently audited 90-row strict diagnostic on `c0aef5fa` has zero
integrity findings and passes throughput, p95/p99, CPU, managed allocation and GC
in all three cases. Two RSS costs remain: Dart values (ratio 1.00824456) and
native buffers (1.01881515). Pre-encoded spans pass every metric. These three
cases do not establish full primary acceptance.

The existing raw rows show process-memory history and non-monotonic drift.
For example, native-buffer FlatBuffers has a lower median absolute peak than
both control medians, yet fails the required paired best-baseline comparison.
This does not justify changing that comparison, subtracting starting RSS in the
gate, treating drift as proven causation, or accepting the milestone.

`tool/diagnose_wamp_rss.py` tests a narrower explanation. It executes the exact
canonical 64-KiB case in six independent process pairs, ordered FlatBuffers,
CBOR, MessagePack, MessagePack, CBOR, FlatBuffers. Each pair retains the real
three warmups, seven measured rows, ten-second/1,000-sample floors, runtime and
router pinning, 300-second workload and 19,800-second campaign deadlines.
There is no forced GC, allocator setting or CPU profiler. The only intentional
experimental difference is a fresh process pair per single-codec segment.

Every pair retains raw reports, command/scenarios, process identities, RSS
before/peak/after and cleanup evidence. Root sources, retained resolved contents,
production binaries, policy and scenarios are checked against fixed hashes.
Incomplete rows, wrong workload/configuration, missing RSS, overlapping/replayed
timestamps, changed inputs, driver failures and failed cleanup stop new pairs
and retain the failure. Launch/wait exception regressions verify the original
error is preserved without a missing-exit-code error, and logs are redacted even
on wait/cleanup failures.

Two fresh process pairs per codec are experimental units; their measured rows
are nested observations. Absolute metrics from other runners must not be pooled.
The workflow labels this diagnostic separately and never invokes acceptance on
its output. Its result always has `primary_acceptance_eligible: false`. The
unchanged complete primary and supplemental campaigns remain required.


## Real report-shape and process-reuse corrections

The first hosted controls 39852830342 and 39852833821 finish one ten-row
FlatBuffers segment each, then fail validation. Their driver exits and process
group cleanup succeed. Both failures are retained and grant no comparative
memory or parity evidence. Two defects in the new diagnostic are identified:
it expects per-sample microsecond timestamps that WorkloadSample does not
contain, and omits the canonical driver's explicit worker-reuse environment.
The first defect masks the second: the raw reports show ten distinct client
PIDs rather than one stable client within the pair.

Separate regressions reproduce both defects before repair. Validation now reads
integer started_at_ms/completed_at_ms on WorkloadReport, retaining missing,
invalid, overlapping and replayed-row rejection. Samples follow the production
report shape. All sixty archived strict rows for the two cases/three codecs
pass the repaired full validation without mocking configuration/evidence checks.
The driver receives and records the same two environment keys as the canonical
campaign: skip native rebuilds and reuse the WAMP worker. Eighteen focused
contracts pass, including environment, real-shape and error retention tests.
The new controls must run again in full; the old failed segments are not reused
as successful process pairs. The initial local verification is stopped before
editing, solely within its verified owned process group; its incomplete result
is not claimed as passing. No started benchmark observation is canceled.
Advisory follow-up review is resource-blocked by another task's native lease;
manual source checks and actual archived-report validation remain separate proof.


## Successful fresh-process controls and passive attribution

Corrected native control 39854187635 (artifact 12460435216) and Dart-value
control 39854191150 (artifact 12458709768) both complete successfully. Each
independent audit verifies 3,193 sources, four retained resolved contents, the
production binaries already audited in the copy proof, exact scenarios, all
60 rows (18 warmup/42 measured), stable per-pair process identities and cleanup.
Archive hashes are respectively
`eca2c33f94021522db7709d3a4fab5a13d415dd83ba637a7c79b29976e7a4700`
and `57d9f9993153a21789ba83769abc84f179ab389b4e47f42c4a62ba100c53fb2f`.
No values are pooled across the two runners.

FlatBuffers exceeds CBOR in both fresh process pairs for each case. In the
native case, summed median peaks are about431/437 MiB versus CBOR 408/418 MiB;
in the Dart-value case, about391/393 MiB versus 377/368 MiB. These are two
experimental units per codec, not 42 independent replicates. They cannot accept
parity or quantify the original paired RSS gate, but simple workload history
alone does not explain the repeated excess.

The difference is mainly client RSS and exceeds the difference in reported
live managed-heap usage. Young-collection occupancy is about 30–32 MiB for all
codecs, and the existing observer already clears its GC-only timeline each
window. No new-space capacity, timeline leak or native-owner leak is inferred.
Existing CPU profiles have additional instrumentation and cannot substitute for
production memory attribution.

Optional `--memory-attribution` observes the unchanged production processes after
the third and ninth complete report lines. It checks report PIDs against owned
observer/driver process identities before and after reading standard VM memory
buckets and bounded `/proc/PID/smaps`. Each snapshot binds to the exact report
line hash. Partial lines wait for completion; failed snapshots and missing
stages stay explicit failures. The observer stops/joins before process cleanup.
Default controls are unchanged and all outputs remain ineligible for acceptance.

The standard [VM API](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/service/service.md#getprocessmemoryusage)
returns a tree of VM-known memory buckets. Bucket names may change and sizes
include children; parents and descendants must never be summed. The pinned
[implementation](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/service.cc#L4996)
includes profiler/timeline/zone/page-cache and isolate-group heap capacity.
Its heap Used sub-bucket approximates new-space capacity, not exact live usage.
These observations are non-atomic and do not promise a complete RSS reconciliation.
They do not measure dependency-internal buffer copies or change approved copy scope.

A real owned Linux smoke must validate the standard API and maps before running
the optional full control. There is no forced GC, CPU profiling, SDK patch,
socket change, allocator setting or changed workload/acceptance limit.


Ten memory-observer contracts, 20 RSS-control contracts, seven smoke contracts,
17 CI contracts and the existing 53 capture/discovery contracts pass (107 total).
Review identifies a possible stage collision outside the fixed policy; invalid
counts now reject before thread creation. A new CRLF/raw-line-hash regression
fails before switching the tail reader to binary bytes and passes afterward.
Other advisory claims about text reads, partial-line handling and file closure
are independently checked against source/tests and rejected. API-only smoke
passes 15 memory buckets on local macOS Dart 3.13.1, with exit 0 and reader cleanup;
this does not establish Linux ownership/maps behavior or pinned 3.13.5 evidence.
The new hosted mode requires that real Linux smoke before observing any rows.


## Owned Linux attribution and next allocator check

Native run 39859717261/artifact 12461692184 and Dart-value run
39859720623/artifact 12462355617 pass independent audits. Each has sixty rows,
twelve complete boundary snapshots/twenty-four owned role observations, 3,195
fixed sources/four retained resolved contents, stable process/observer/start
identities, exact report-line hashes and production binaries matching the
current copy proof. Archive hashes respectively:
`37910bf87a60ca77100d1c0a9c30aea7f4be37df721bcf16327022c6ce5fbdf7`
and `394e3160289da34b45afe7ba02feea81bcaeac07c13eabfdd1a67fc786bda4d3`.

For native-buffer client snapshots after report nine, FlatBuffers RSS is
223/220 MiB, versus CBOR 212/213 MiB. Unnamed anonymous mappings contribute
92/88 MiB versus 79/83 MiB; named Dart heap mappings are approximately
87/88 versus 90/87 MiB. The mapped FFI library is about 2.05 MiB resident for
all codecs. These are non-atomic diagnostic snapshots, not peak reconciliation
or acceptance. The Dart-value snapshots have more variable codec differences.
Mapping alignment suggests allocator arenas but does not prove allocation
liveness, fragmentation or a leak.

Existing CPU-profile snapshots report externalUsage 112 bytes after each
workload and after requested GC for every codec. Their additional instrumentation
prevents accepting RSS or inferring unprofiled native-buffer liveness from them.

Optional `--allocator-attribution` therefore adds standard per-isolate memory
usage (including externalUsage, preserving isolate/group references without
summing shared heaps) and glibc counters to the existing owned observations.
Temporary wrappers register one diagnostic service extension and invoke the
unchanged production entrypoints. No production library export or public
package API changes. The driver scenarios, workload limits and policy stay fixed;
wrappers and all inputs are hash guarded. Its outputs remain ineligible for
acceptance and cannot be pooled with uninstrumented controls.

The [glibc malloc_info contract](https://man7.org/linux/man-pages/man3/malloc_info.3.html)
provides all-arena XML counters, supports open_memstream and is thread safe.
The probe closes the stream, copies bounded XML and frees both the stream buffer
and pointer slots on every exit. The parser retains raw XML and uses only direct
root totals, never double-counting per-arena totals. These counters are not RSS
or exact live allocations; thread caches are not represented as free bins.
[mallinfo2](https://man7.org/linux/man-pages/man3/mallinfo.3.html) excludes other
arenas and is unsuitable for this all-arena question.

Before any workload, a separate process must observe a controlled 64-MiB native
allocation and deallocation, then real Linux smoke verifies the authenticated
extension, expected VM/observer PID, bounded counters, standard memory usage and
maps. Unsupported versions, malformed counters, missing/wrong isolate or owner,
API errors and identity changes remain failed observations. There is no malloc
trim, allocator tuning, forced GC, SDK patch, socket change or profiler flag.
The local companion test/review attempts and local analysis are resource-blocked
by another task's machine lease; no advisory approval or analysis pass is inferred.
