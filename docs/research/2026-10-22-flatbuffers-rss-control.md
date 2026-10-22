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
