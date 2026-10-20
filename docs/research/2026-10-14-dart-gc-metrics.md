# Native VM heap counters for benchmark GC metrics

A live Dart 3.13.1 probe allocates 16 MiB in a stable application isolate and
forces collection through the VM service. The old collector reports zero
collections and pause microseconds despite real GC activity. Its timeline filter
requires names containing `gc` and complete `X` durations, while this VM emits
collection names and paired begin/end scopes.

A stronger completeness check then exposes two distinct attribution hazards.
The [pinned VM implementation](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/vm/heap/heap.cc)
updates the shared heap's collection/time counters in `RecordAfterGC` and emits
the same notification on every non-system isolate in the group. Timeline stages
also include parallel worker activity and concurrent-marking setup; summing
arbitrary stage durations or counting notifications separately is inaccurate.
The observed main/worker snapshots have the same group ID and GC counters.

The final collector uses cumulative native heap counters, sampled once per
observed isolate group. New/old-generation collection counts and times come
from the VM's `_heaps` extension. The pinned [old-space serializer](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/vm/heap/pages.cc)
and [new-space serializer](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/vm/heap/scavenger.cc)
expose cumulative microseconds as seconds. The collector converts to
microseconds and computes nonnegative per-generation deltas. These measure
foreground GC phases as recorded by the VM, including concurrent-mark setup,
rather than background worker CPU or whole asynchronous-cycle wall time.

Allocation-profile reset/read also uses one representative per shared heap.
Every selected application isolate is still monitored for creation/shutdown;
profiling deduplication does not weaken the stable-isolate requirement. The
supervisor observes the worker through its VM service from another isolate or
process, preserving the existing profiling architecture.

Missing group metadata prevents collection. Missing SDK extensions, malformed
counts/times, missing or changed groups, rewound counters and unsettled GC
notifications remain unavailable. Valid unchanged native counters produce zero;
missing evidence cannot. The extension is SDK-specific: unsupported versions
fail closed, and the exact SDK remains part of campaign attribution.

The live forced-GC regression requires positive counts and pause microseconds.
Focused tests cover group deduplication, both generation units/deltas, missing
and invalid metadata, overflow and counter rewind. The supervised source WAMP
worker remains in the regression flow. All 35 focused cases pass locally.

Reproduce with `dart test packages/connectanum_bench/test/dart_vm_metrics_test.dart`
and `dart test packages/connectanum_bench/test/dart_vm_gc_heap_metrics_test.dart`.
Failure, success and actual trace/snapshot logs are retained under
`out/flatbuffers-milestone-finish/`. The original zero measurement fails both
directly and in canonical verification before repair; the discarded timeline
reconciliation experiment is retained as diagnostic evidence.

Historical campaign rows remain unchanged. The complete hosted campaign at
`a5c6aaf9` still fails; recorded zero GC results cannot serve as current resource
evidence. Its separate throughput/latency/CPU/allocation regressions and missing
copy fields remain required work. The policy and its original duration, sample,
confidence and parity gates are unchanged.
