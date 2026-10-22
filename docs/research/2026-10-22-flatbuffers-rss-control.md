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
