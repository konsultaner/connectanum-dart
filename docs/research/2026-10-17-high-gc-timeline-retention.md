# Complete high-GC allocation windows with the standard SDK

The first complete supplemental campaign on `b8e2a0ac` exposes missing allocation
evidence at 1 MiB. Its payload-size shard stops at 192/360 rows on a Dart TLS
WebSocket workload timeout. An independent ZIP audit verifies both executable
hashes, policy/config/lock/scenario hashes and all 192 original/split rows.
There are 66 missing client and 33 missing server allocation observations.
The teardown's worker-stopped warning does not establish an earlier worker crash.

A focused local 30-row rerun completes every workload without that timeout, but
all 30 client allocation windows fail native GC-counter reconciliation. Two
server windows fail the separate negative-estimate/one-percent precision check.
The isolated timeout is therefore still unresolved. No row or gate is omitted.

## Reproduction and repair

A separate-process synthetic probe allocates 8 GiB of transient buffers without
forcing GC. With Dart 3.13.1's default ring recorder, the native counter reports
690 collections but only 631 completions remain in the timeline. The recorder's
oldest retained timestamp is later than the start boundary. Allocation correctly
remains `not_measured`. With the standard SDK's `endless` recorder, all 694
in-window native collections reconcile and the estimate is 8,598,970,880 bytes
(including managed overhead and eight retained one-MiB buffers), with a
1,421,312-byte rounding bound. Independent runs need not have equal GC counts.

The pinned [Dart 3.13.5 timeline implementation](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/vm/timeline.cc)
uses a ring by default and provides the endless recorder in the standard SDK.
Only the two benchmark source-VM launch paths now request that recorder. Before
each new window, the external observer clears prior timeline history before
any heap boundary or CPU capture. Clear failure aborts capture. No events are
cleared inside a window or between boundary retries. A dedicated benchmark VM
has one serial observer; this collector owns its timeline history.

Recorder storage contributes to the measured process RSS during a window. All
codecs use the same instrumentation. Prior-window history is removed, rather
than retained for an entire multi-hour campaign. The recorder name accompanies
the evidence. This is standard SDK instrumentation, not a custom SDK build.

Unavailable allocation results now preserve raw heap boundaries, expected and
observed collection counts, and validated GC observations as diagnostic evidence.
They remain `not_measured`, with no estimated-byte field. This will distinguish
remaining occupancy/precision failures from missing events. The allocation
formula, counter checks, one-percent precision limit, comparator, budgets,
minimum samples/duration and workload inventories are unchanged. SDK/TLS/crypto
internal copy accounting remains explicitly unmeasured under the approved scope.

## Verification

The unchanged-source `bin/test-fast` passes before this repair. A real source
worker regression naturally allocates 32 GiB and then 1 GiB across two windows
in the same process. It fails first with missing GC events and passes with the
new launch flag; native counts and conservative allocation bounds reconcile.
An actual VM-history assertion fails when clearing is temporarily removed and
passes after exact source restoration. The complete focused set passes 85 Dart
tests, analysis is clean, and all 139 release-profile benchmark-driver tests pass.
The first focused test attempt contained a test-helper declaration error; it is
preserved as a compile failure and is not counted as a behavioral reproduction.

Local evidence is under `out/flatbuffers-milestone-finish/`: `high-gc-ring.json`,
`high-gc-endless.json`, `high-gc-worker-fail-first.log`,
`high-gc-clear-causal-replay.json`, `high-gc-regressions.log`,
`high-gc-analysis.log`, `high-gc-driver-tests.log` and
`payload-sizes-independent-zip-audit/independent-archive-audit.json`.
Full resulting-source verification, the renewed 1 MiB case and performance
acceptance are still required. This repair does not claim throughput parity or
resolve the independent server precision failures or hosted timeout.

## Completed follow-up on 2026-10-19

The renewed focused `ext_18_payload_sizes` diagnostic on `1a20561d` completes
all 30 rows with every client and server allocation window measured. No timeout
or precision failure occurs in this run; it establishes no parity acceptance.
The resulting-source CI stops before test execution because the format gate
detects one unformatted test invocation. Missing coverage artifacts are a
consequence, not a failed coverage ratio. `8f6e753a` formats the invocation and
the complete 736-file format check passes. Full verification remains required.

The first full verification on `540ab37f` subsequently catches a stale synthetic
VM-service fixture: it does not respond to `clearVMTimeline`, causing an
unhandled fixture error and timeouts. That failed run is retained and stopped;
it is not a successful full verification. The fixture now returns the standard
Success response and identifies its recorder. A separate negative test requires
an unsupported clear RPC to abort `beginWindow`; removing the production clear
makes that assertion fail, and exact restoration passes. All 221 collector,
external-observer, wire and worker lifecycle cases pass. Application code and
all acceptance thresholds remain unchanged by this fixture repair.
