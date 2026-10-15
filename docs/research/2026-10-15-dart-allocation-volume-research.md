# Stock Dart SDK allocation volume — 2026-10-16

The pinned local SDK is Dart 3.13.1, commit
`852b3e3608906afbe6102573cfd4407aeedd1b78`. Hosted acceptance uses 3.13.5,
commit `04bcd1036cdc799ac6564988f159ee454d42c822`.

## Rejected measurements

The 3.13.1 [class-table implementation](https://github.com/dart-lang/sdk/blob/852b3e3608906afbe6102573cfd4407aeedd1b78/runtime/vm/class_table.cc#L337)
counts current heap objects and writes the same size into `accumulatedSize` and
`bytesCurrent`. Its field name does not make it allocation volume. A controlled
80 MiB allocation followed by GC reports only 44,629,952 bytes through the prior
collector. Historical allocation ratios based on that field are invalid.

The native heap-sampling prototype preserved large one-MiB allocations after
GC, but warmed small-allocation probes missed 100 MiB of known allocation at
three sampling periods. It is rejected for acceptance and is not integrated.
No custom SDK or patched dependency is introduced.

## Integrated method

`dart_heap_gc_volume_v1` measures managed allocation pressure as:

```
heap_used_after - heap_used_before + sum(gc_used_before - gc_used_after)
```

New and old generation values are combined so promotion cancels. The pinned
[old-space collection implementation](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/vm/heap/pages.cc#L1124)
resets occupancy from marked words plus allocations during marking before
asynchronous sweeping. This supports including concurrent old collections in
the reclamation sum. The metric includes managed object overhead and allocation
pressure; it excludes native allocations and is not retained memory.

Each VM-service observer runs in a separate OS process outside both measured
PIDs. Raw group heap snapshots, collection counters, GC timeline observations,
SDK version, PID attribution and RPC timestamp brackets remain in every report.
Group changes, counter rewind, incomplete events or GC overlapping an ambiguous
snapshot bracket produce `not_measured`. After a real paired run catches one
such overlap, capture now retries only that heap boundary, at most three times.
An end-boundary retry preserves all GC events since the original start and never
reruns or discards workload operations. Exhaustion or missing evidence still
fails closed. Matching native collection-counter
deltas are required, including concurrent old marking.

Timeline heap sizes have KiB precision. The absolute rounding bound is 2,048
bytes per collection and must be at most 1% of the estimate. The independent
Python evaluator recomputes raw totals and uses candidate upper bounds versus
baseline lower bounds. Existing budgets and workload inventories are unchanged.
Legacy live-heap reports cannot satisfy the allocation gate.

## Validation and limits

A retained 16 MiB plus transient 64 MiB regression fails with the old collector
and passes with the external observer after collection. Separate small/large
allocation calibrations retain history across young and concurrent old GC.
Thirty-two pure calculation cases and process/GC/lifecycle tests cover missing
or duplicate events, timestamps, count mismatch, observer failure and PID
attribution. Independent Python tests reject forged evidence.

A clean 24-row HTTP matrix covers three outer encodings, Dart/native clients,
RawSocket/WebSocket and TLS/cleartext. All 48 process allocation reports pass
independent validation. These short correctness runs use the same FlatBuffers
inner payload and establish no performance parity. Full paired timing and Linux
CPU/RSS acceptance remain required. SDK/TLS/crypto internals remain unmeasured
under the approved standard-SDK copy scope.
