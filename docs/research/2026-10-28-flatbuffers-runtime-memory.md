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


## Shared construction and metadata follow-up

[Diagnostic 40710916340](https://github.com/konsultaner/connectanum-dart/actions/runs/40710916340)
on `8fdc0ad00f2c3d49d401fe8304d9e378d35705d1` completes all 90 rows with no
integrity findings beyond diagnostic ineligibility. Native-buffer construction
passes all seven numerical comparisons. Eight findings remain elsewhere:
Dart-value CPU/p95/p99/RSS/throughput, and pre-encoded RSS plus GC/p99 confidence
limits. Keep all observations; the shared word-fill optimization is not parity.
[Owned-copy proof](https://github.com/konsultaner/connectanum-dart/actions/runs/40710922147)
passes 120 live cases, 300 inventory rows and 32 zero-avoidable-copy observations,
including complete owned E2EE/transcode accounting and unchanged input receipts.

A private local live control varies only the public router worker poll interval,
checking every echoed 64-KiB byte. With the original 1-ms interval, 100-RPC means
are 4.8–5.4 ms; a 10-ms interval gives 23.7–24.2 ms; zero interval gives
0.5–0.9 ms after warmup. These macOS controls show a shared scheduling floor.
The busy zero-interval control is not a production recommendation and changes
neither campaign configuration nor acceptance criteria.

The next candidate removes redundant retained dictionaries only when a fresh
RESULT/EVENT/INVOCATION model completely represents the two-text PPT dictionary.
Native binding also matches the whole bounded CBOR span and guards every other
native control field/flag. Other dictionaries retain existing semantics and
validation; payload vectors and their lifetime anchors are unaffected.

Local source-compiled kernel probes run before/after/after/before, each with nine
20,000-operation passes, discarding the first four passes in every process:

| Component | Baseline run medians (microseconds) | Candidate run medians | Ratio of median run times |
| --- | --- | --- | ---: |
| Native RESULT binding | 30868, 30638 | 2057, 2145 | 0.068 |
| Dart RESULT reader | 53185, 53402 | 39732, 39314 | 0.742 |

The native baseline/candidate kernels have SHA-256
`f903bd24c94dfefd9c5e6d484bffed1f1de5adf4533c7a95288919e79a6ae35f` and
`d58e3f5cef8b973994b216549b920f1216ef5159e624e36ff1285bad0736521c`.
The Dart-reader baseline uses the `8fdc0ad0` reader with imports rewritten to
package URIs; its baseline/candidate kernel hashes are
`f5efa073803f8c90b35b1b38ee1feb0935f0558e8b16f712b7c8b89025368912` and
`23851fae73ad0ff2d134bf1cc765bcee0807ca7b21583b4df2b828eacdba1cc2`.
These control-only component timings are diagnostic, not throughput, latency,
CPU, GC or RSS acceptance for a WAMP workload.


## Native router wake direction

Full local verification passes on `c705b5bd`; product runtime is unchanged from
`66282e65`. [Its paired diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/40716746367)
passes all throughput and native-buffer numerical gates, but retains eight
findings across Dart values/pre-encoded spans. [Current CPU capture](https://github.com/konsultaner/connectanum-dart/actions/runs/40720372509)
resolves 80 FlatBuffers/101 MessagePack body-loop exclusive client samples,
versus 314/251 before word-fill changes. These separate intrusive captures are
not normalized performance acceptance. Router samples include substantial VM,
context-switch and kernel scheduling work. The live polling control above
supports investigating native readiness notification rather than busy polling.

Use an additive, coalesced void notification only after a native WAMP message
has entered its existing queue. Arm before polling: arrivals already queued are
read by the scan; later arrivals wake idle pacing. Notifications do not consume
messages or transfer payload memory. Keep the timer/default interval and older-
library fallback. Synchronize callback invocation and removal; unregister native
before closing the Dart listener, and ignore stale lifecycle generations.

The [Dart NativeCallable.listener contract](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html)
supports arbitrary native threads and asynchronous void delivery to the creating
isolate. It keeps that isolate alive until closed. The [close contract](https://api.dart.dev/dart-ffi/NativeCallable/close.html)
forbids subsequent native invocation, so callback removal must synchronize with
in-flight invocations before close. A broadcast bridge avoids replacing another
router's subscription. Test cancellation/restart, callback races and clean
process exit; retain fallback polling as a correctness backstop.


The native readiness candidate passes three coalescing/race/removal unit tests,
two live RawSocket/WebSocket FFI publication/removal cases and a native shutdown
registration test. Dart bridge tests cover incomplete optional symbol pairs,
multiple subscribers, stale queued events, cancellation/restart and a subprocess
that exits with an uncancelled subscription after bridge disposal. Live typed
RPC tests for FlatBuffers, CBOR and MessagePack complete within 500 ms with a
one-second fallback interval. All three time out against a byte-identical
legacy DLL snapshot lacking the v1 symbols; ordinary legacy polling cases pass.
The legacy snapshot SHA-256 is
`72432ae71e017dd4d8bc465d9c10069ae6fe7ea21eef02d8abf7b0c90b0203f2`.

A bounded GLM lifecycle review accepts invocation/removal synchronization but
suggests a pre-registration lost-wake concern. Source inspection and the router
pacer test disprove that scenario: `_loop` always arms and scans immediately
on start, before its first 30-second fallback wait. Queue contents are never
consumed by a notification, and arrivals during that scan get a new signal.
Clearing coalescing state on registration therefore does not lose queued work.
No notification replay or changed polling default is needed.

A root-level parallel test invocation also reproduces a pre-existing VM abort:
constructing a second native router wrapper in another isolate overwrites a
process-global legacy `Pointer.fromFunction` connection callback. The same
minimal repro aborts with the old DLL, without either readiness symbol. This is
separate from the new asynchronous listener. Canonical router verification uses
its package `dart_test.yaml` concurrency of one; 775 cases pass serially before
the added fake-runtime readiness test. Do not interpret parallel execution as
supported ownership of one native router runtime across isolates.

## Verified readiness result and sample staging

`7a5bdc76` passes full local `bin/test-fast` and `bin/verify`. Its
[paired diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/40736188467)
completes 90 rows and reduces numerical findings from eight to four. All
throughput, CPU, allocation, GC and p95 comparisons pass. Dart-values p99 is
1.009517 (upper CI 1.052674); peak-RSS ratios are 1.018890 for Dart values,
1.023226 for native buffers and 1.057052 for pre-encoded spans. Keep the original
reports, primary requirements and budgets unchanged.

The [new copy proof](https://github.com/konsultaner/connectanum-dart/actions/runs/40736194337)
passes 120 live and 300 inventory rows, with all 32 no-avoidable-copy checks and
unchanged input/binary receipts. [CPU capture](https://github.com/konsultaner/connectanum-dart/actions/runs/40737157961)
also passes; it is intrusive and includes post-workload retained-heap inspection,
so it cannot replace measured latency, memory or GC acceptance.

Source inspection excludes an unaccounted exported-byte-view hypothesis:
`NativeMessageBytes.read` uses `Pointer<Uint8>.asTypedList` with a native finalizer.
The installed standard SDK's `ffi_patch.dart` passes the view length to
`_attachAsTypedListFinalizer`, whose `ffi_native_finalizer_patch.dart` delegates
with `externalSize`. The [public externalSize contract](https://api.dart.dev/dart-ffi/NativeFinalizer/attach.html)
uses native allocation size for GC scheduling. No owner lifetime or SDK setting
is changed on this hypothesis.

A separate, concrete benchmark overhead is eager sample-map staging in worker
output and another copy of each decoded JSON map in the controller. All records
remain required. The worker can let the standard encoder invoke each sample's
existing `toJson` as it encodes the list; the reader can use JSON's existing
string-keyed maps directly. The measurement windows and workload remain intact.

An isolated AOT component builds 20,000 immutable samples and runs
old/new/new/old fresh processes. Both paths emit exactly 7,000,013 bytes with
SHA-256 `8c2657e54d10cdf069fb29410d0f32de6b5752cd7136051452cdba9152464882`.
Observed peak RSS is 58,474,496/58,523,648 bytes with eager staging and
55,328,768/55,345,152 bytes with per-item encoding. Times are 35,988/36,419 and
36,226/36,312 microseconds respectively. These are isolated component results,
not WAMP RSS or performance acceptance. No GC or allocator adjustment is used.


## Lossless worker observation representation

The lazy-map follow-up `aa090feb` still retains four findings in
[its paired run](https://github.com/konsultaner/connectanum-dart/actions/runs/40743480042):
Dart-values throughput/p95/RSS and pre-encoded RSS. Native-buffer passes all
seven comparisons; CPU/allocation/GC/p99 pass for every case. Preserve both
this observation and the different four-findings readiness report.

A further AOT control uses the actual 13-field worker record encoder/decoder.
For 20,000 samples, named JSON IPC is 7,000,013 bytes and positional IPC is
1,180,013 bytes. Reconstructed named sample JSON has the same SHA-256 as above.
Old/new/new/old encode/decode timings are 65,875/16,971/16,527/67,016 microseconds;
peak process RSS is 85,983,232/31,178,752/31,211,520/85,540,864 bytes. This models
the common worker/controller serialization stages, not the WAMP payload protocol.
The output retains every observation; its size reduction comes from encoding
field positions once rather than repeating names. No accepted workload, gate,
measurement window or resource observation is removed. These component numbers
cannot establish WAMP memory or timing acceptance.

The worker capability is negotiated per request/response as `positional_v1`.
Supervisors accept named output from older workers. New workers use the original
named output when the supervisor does not request the capability. A declared
unknown version, malformed row, or invalid copy counter fails the scenario and
cleans up its worker before recovery. Public report fields and timestamps keep
their named representation and established null/zero rules.

[Fresh native-buffer memory attribution](https://github.com/konsultaner/connectanum-dart/actions/runs/40740363467)
completes six process pairs without changed inputs. Summed peak medians are
542/560 MB for FlatBuffers, 518/515 MB for CBOR and 574/571 MB for MessagePack.
At the retained before-last-report snapshots, native external usage is negligible
outside the baseline router state. Heap capacities and free allocator bins differ;
those are not proof of payload leakage or reclaimable resident bytes. Keep the
RSS gate unchanged. A local judge incorrectly equates higher completed request
volume with more concurrent requests; concurrency is fixed in these scenarios.


## Public HTTP relay staging

The compact-record candidate `e72638be` passes full local verification and
[owned-copy proof](https://github.com/konsultaner/connectanum-dart/actions/runs/40748144948).
Its [paired report](https://github.com/konsultaner/connectanum-dart/actions/runs/40748141357)
retains eleven numerical findings, so neither the isolated component reduction
nor earlier four-finding reports establish parity. Keep every report unchanged.

The final public response still projected all samples to dictionaries before
`HttpInvocationContext.sendJson`. Internal transfer/materialization recursively
copies list/map entries but preserves ordinary immutable Dart objects. The
existing native HTTP JSON path eventually calls the standard jsonEncode, which
can project each sample's existing toJson at that point. Keeping the models
therefore removes redundant per-field map staging/cloning while retaining the
same complete named output and measurement scope.

An isolate-transfer regression with 2,048 samples checks exact named JSON bytes
through HttpResponsePayload. A real local server, using private ports and a
copied configuration, returns all samples/fields for each of FlatBuffers,
MessagePack and CBOR under values/native-buffer/pre-encoded construction.
Every echoed payload is validated by the unchanged workload runner. These are
correctness checks, not a performance result. The first private setup attempt
timed out because its readiness match ignored Dart's build-hook prefix; the
harness was corrected and its failed control log retained. Source and gates
were not changed to accommodate it.


### Recovering leaf addresses without successful unwinding

Capture `40763175368` retains primary instruction addresses in the original
perf data even when its call-chain text contains empty samples. The Linux
[UAPI sample layout](https://github.com/torvalds/linux/blob/master/include/uapi/linux/perf_event.h)
places the instruction address, PID/TID and timestamp before optional
call-chain/stack data. A private, bounded single-event reader uses that layout
and matches every existing per-PID/window sample count with zero LOST events;
JIT reuse remains explicitly ambiguous. It does not reconstruct missing stacks
or establish performance acceptance. For future exports the perf
[hide-call-graph option](https://github.com/torvalds/linux/blob/master/tools/perf/Documentation/perf-script.txt)
can preserve leaf output independently of stack unwinding. A 6.12 reader rejects
the current 7.0 recording; retain that failed offline attempt.

Fresh six-pair memory control `40763180032` has unchanged inputs and source
`2f92dcc7`. FlatBuffers peak medians are 436/422 MB, CBOR 375/387 MB and
MessagePack 411/457 MB. Main/VM-service heap capacity and cached regions differ
between snapshots. Neither subtracting cache/free memory nor interpreting
ordinary heap-used counters as fully retained live objects is justified.


## Fresh Dart-values attribution on `3a825a76`

Hosted read-only control `40783409254` completes all six fresh process pairs
with unchanged inputs (661.64 s). The case is
`rpc_rawsocket_clear_dart_values`, distinct from earlier native-buffer captures.
The chronological summed sampled-peak RSS medians are: FlatBuffers 388.29 MiB,
CBOR 393.81 MiB, MessagePack 420.05 MiB, MessagePack 421.07 MiB, CBOR
397.57 MiB, FlatBuffers 420.86 MiB. These are diagnostic observations, not paired
primary acceptance, and the two FlatBuffers observations differ materially.

Before-last-report VM main-isolate Used buckets on the worker are
39.41/63.20 MiB for FlatBuffers, 38.79/44.33 MiB for CBOR and
58.44/57.94 MiB for MessagePack. These include garbage and must not be called
retained live application data. VM Page Cache ranges from 5.5 to 30.5 MiB
across observed roles; the profiler bucket is 18.77 MiB throughout. Do not
subtract cache/free buckets from the RSS gate, force GC or change allocator/SDK
settings to improve a report. No monotonic payload-owner leak is established.

The next source-preserving paired report on `cd54760c` determines whether
removing worker JSON-string staging resolves the two previous RSS point
failures. Its actual-source AOT component preserves all 1,180,013 JSON bytes
and reduces 20,000-record peak RSS from 28.15–28.16 to 25.56 MB; this remains
component evidence rather than WAMP acceptance. Production proof `40784345437`
passes 120 live / 300 inventory / 32 no-avoidable-copy checks on that source,
including 96 live E2EE and 120 transcode cases, with unchanged inputs/binaries.

## Completed supplemental evidence and CALL candidate (2026-10-29)

Hosted CI [40788573756](https://github.com/konsultaner/connectanum-dart/actions/runs/40788573756)
on `cd54760c` passes completely. Supplemental run
[40789946129](https://github.com/konsultaner/connectanum-dart/actions/runs/40789946129)
passes all batches and aggregate evidence validation. Independent reconstruction
from all raw rows exactly matches the hosted report: 50 cases / 1,500 rows,
unchanged input and binary hashes, no integrity findings and 194 numerical
diagnostic findings. These supplemental findings remain visible; successful
execution is not primary parity acceptance. No cross-batch absolute costs are
pooled, and the obsolete-source partial artifacts remain retained.

A role-level audit of the current three-case report shows no single common
client-only RSS excess. FlatBuffers client/server sampled-peak medians in MiB
are 257.59/298.50 for Dart values, 264.86/300.03 for native buffers and
260.10/288.58 for pre-encoded spans. Corresponding MessagePack medians are
266.27/291.23, 272.47/297.85 and 258.40/287.81. These separate medians are
attribution only: summing them does not reproduce the paired comparison metric.
Keep the original paired RSS failures; do not infer a retained leak or remove
server/SDK costs from the gate.

The next guarded encoder candidate uses pinned generated CALL/Message builders
when the complete supported body has only request, procedure, opaque payload
and numeric PPT controls. All other shapes retain the complete generic schema
walk. Deferred payloads retain the original parts, borrowed vectors keep their
builder owner, metadata uses the same copy-accounted vector writer and field
order remains exact. Tests compare all three storage forms with the generic
writer's same-wire absent optional field, including zero/max IDs, every scheme,
empty/64-KiB bodies, Unicode/lone surrogates and invalid inputs.

An actual-source AOT component performs full preparation plus native-reference
prefix construction. Generic/generated/generated/generic 500,000-encode times
are 903,561 / 647,371 / 660,594 / 878,720 us, with identical 192-byte prefixes.
Peak RSS is 18.86 / 19.02 / 18.83 / 18.87 MB and is inconclusive. This is a
component improvement only; it does not establish WAMP latency, RSS or primary
acceptance. The native/profile and focused serializer tests pass; full and
hosted evidence must be renewed. Companion review remains lease-blocked.

## Completed CALL evidence and request-frame retention (2026-10-29)

The generated CALL runtime `775103e8` passes production copy proof
[40872810450](https://github.com/konsultaner/connectanum-dart/actions/runs/40872810450):
unchanged source/binaries, 120 live (96 E2EE, 120 transcode, 48 native crypto),
300 inventory and 32 no-avoidable-copy checks. Paired diagnostic
[40872805498](https://github.com/konsultaner/connectanum-dart/actions/runs/40872805498)
completes 90 rows and retains four numerical failures: Dart-values RSS 1.006949,
p99 upper confidence 1.232432, GC upper confidence 1.109514, and pre-encoded RSS
1.008483. Native-buffer passes all seven metrics in this report. This does not
waive the original full matrix or establish final acceptance.

CPU/heap attempt 1 of
[40873091455](https://github.com/konsultaner/connectanum-dart/actions/runs/40873091455)
retains completed FlatBuffers and MessagePack profiles. CBOR native perf never
produces a complete capture; cleanup reports exit 255. Inputs and binaries are
unchanged, all owned processes stop, and no interference is recorded. Keep the
failed attempt and retry instrumentation once. It is never timing acceptance.

The actual idle-worker snapshots retain 23,934 WampSample instances after the
FlatBuffers response, including after diagnostic-only collection. The long-lived
stdin async loop retains its preceding response's local sample list. An isolated
actual-model scaffold reproduces the loop pattern in inline/handler/handler/inline
order: inline retains 20,000 instances / 2,240,000 bytes; separately awaited
request handler retains zero, after diagnostic-only collection. All four output
streams contain exactly 1,428,904 bytes with SHA-256
ad34754a6760ff54dde2ae5a0787178101cba5743b7c0fb1d29b1e16348b907c.
This establishes reachability for the pattern, not an RSS/GC/latency pass.

The follow-up moves the unchanged per-request try/catch to a separately awaited
function. Samples can become unreachable before the loop awaits another input;
all responses, snapshots, metric windows, LF/flush and shutdown/error ordering
remain intact. A real production-worker sequence covers malformed JSON,
unsupported encoding, compact success, named success and STOP. It and 143
boundary/lifecycle cases, analysis and 167 mutation proofs pass. No collection
or allocator setting changes are introduced. Reject the companion test advice
suggesting a forced-GC RSS threshold; liveness diagnostics cannot substitute
for the unchanged paired RSS gate. Actual-worker memory and full verification
still need renewal on this source.

Local full verification of the CALL checkpoint stops when a test kernel cannot
be written (ENOSPC). This is not a passing checkpoint. Completed historical raw
reports are losslessly gzip-compressed with round-trip SHA-256 verification and
receipts; all data and hosted reports are retained. Unrelated task files are not
removed. The incomplete artifact extraction is retried to a fresh directory
because gh refuses existing files.

## Actual worker release and supervisor report graph (2026-10-29)

On runtime `69193827`, the complete local actual-worker CPU/heap capture exits
zero with unchanged source/library hashes, no memory findings and clean process
shutdown. All three client codecs retain zero WampSamples after diagnostic-only
collection. Native perf is not measured on this macOS capture; it is never
performance acceptance. The existing last-result queue hypothesis is separately
falsified by an actual-model queue/barrier/barrier/queue scaffold: every variant
retains zero after diagnostic collection. No production queue change is made.

A real supervisor request retains all 2,000 completed sample models after the
response and diagnostic collection. VM-service retaining-path inspection points
through the internal response lazyPayload/argumentsKeywords/body/samples graph.
A private prototype encodes the same report with JsonUtf8Encoder before internal
routing and sends standard bytes with the original application/json; charset=utf-8
header. It retains zero supervisor samples in the equivalent probe. The adopted
follow-up also retains zero, and all nine actual HTTP codec/construction pairs
retain complete named sample fields and JSON charset. Reporting uses the normal
defensive bytes response API; no claim of zero-copy reporting or measured SDK
internals is made. All snapshots/windows remain before report encoding.

The worker extraction invalidates the private native-view diagnostic's old
textual anchor/library scope. Full verification and hosted copy prerequisite
`40877485342` reproduce that exact failure. The shadow patcher now threads the
library path into the per-request function, preserving the capture's original
post-window point and refusing missing/ambiguous anchors. All 14 patcher tests
and 14 production copy-tool tests pass. This tooling repair does not alter
production frames, payloads, native ownership or benchmark policy.

Focused companion review completes with no concrete finding. Its additional
claim that JsonUtf8Encoder stages a JSON string is rejected: it directly emits
UTF-8 bytes. Its speculative sendJson/sendBytes cleanup difference is checked
against both delegating through HttpResponseUtil.respond. The diagnostic-only
liveness evidence does not replace the remaining paired RSS/confidence gates.

## Reject early byte staging; retire the forwarded envelope (2026-10-29)

The early report-encoding candidate `f204100d` passes full bin/verify and
production copy proof [40880838998](https://github.com/konsultaner/connectanum-dart/actions/runs/40880838998)
(120/300/32, unchanged source/binaries), but paired diagnostic
[40880833788](https://github.com/konsultaner/connectanum-dart/actions/runs/40880833788)
has eight numerical failures. Its raw recomputation exactly matches the hosted
comparison. Retain that result and reject/revert the early byte staging; no
point/confidence gate or workload is changed. bench_main returns byte-for-byte
to `69193827`. That preceding report independently reproduces three failures
(Dart GC confidence and two RSS points) and a passing Dart p99 gate.

Deeper retaining-path inspection identifies a private result envelope under an
isolate-object-store [portId, responseMap] root, pointing through the transferred
lazyPayload/argumentsKeywords/body/samples graph. A narrower prototype forwards
the response first, then removes application-payload references only from the
received private envelope. SendPort's immediate snapshot preserves the full
forwarded graph; nested application maps/bytes are not mutated. The equivalent
actual 2,000-sample probe retains zero WampSamples without report-byte staging.

The helper returns the same error/final/progress decision as the previous loop.
It never retires data before a successful send, preserves strict malformed-
progress validation after forwarding, and tolerates immutable envelopes. Shared
protocol-key constants prevent divergence. Nine actual SDK contract tests cover
same/cross-isolate snapshots, details/PPT, progress/error/final/default/unknown
flags, immutable nested/outer maps, transferable ownership, failed-send atomicity
and SDK closed-port drop behavior. All 785 selected native/router regressions,
all nine actual HTTP codec/storage pairs, analysis and 167 mutation proofs pass.

GLM's suggested same-isolate alias exception is disproved by the actual SDK
contract test and local SDK send documentation. Its missing-field-test concern
is addressed by progressive/details/PPT assertions. Qwen's port-closure and
strict-progress concerns do not establish regressions: real closed-port sends
retain SDK drop behavior, and invalid progress was already rejected after send.
Do not adopt coercion or swallow send failures. The current caller never reads
retired payload fields after the helper. Final full and hosted measurements
must still be renewed; none of these liveness checks establish parity.

## Current-source verification and remaining performance gates (`dec17f8b`)

Full `bin/verify` exits 0 on the forwarded-envelope candidate, including
Rust/FFI, VM/native, installed consumers and Chrome/WebAssembly. Hosted
production proof `40891602695` passes all private native-view control phases
and 120 live / 300 inventory / 32 zero-avoidable-copy checks. The live rows
include 96 E2EE, 120 transcode and 48 native-crypto checks; the short inventory
includes 96 E2EE, 60 transcode and 72 native-crypto checks. Revalidating the
downloaded raw rows reproduces these counts, stable worker identities, raw
stream hashes and cleanup. Source/binary unchanged receipts are true.

The independent source audit verifies 3,216 tracked source inputs against the
candidate and three generated lockfiles against their retained Linux copies.
`.dart_tool/package_config.json` has a hosted unchanged digest receipt but no
retained contents; do not claim its bytes were independently reconstructed.
The first two private audit attempts are retained: comparing the generated
Linux Cargo lock to the macOS lock was invalid, and requiring retained package
configuration contents was unsupported. Neither is a production proof failure.

Diagnostic `40891596427` completes 90 rows and is independently reproduced
exactly, including retained production binary, scenario, router, policy and
lock hashes. Seven numerical gates still fail:

| Case | Metric | Median FB/better-baseline ratio | 95% interval |
| --- | --- | ---: | --- |
| Dart values | throughput | 0.981533 | 0.968920–0.988545 |
| Dart values | p95 | 1.006623 | 0.964346–1.027778 |
| Dart values | p99 | 1.158683 | 1.086290–1.318127 |
| Dart values | CPU/op | 1.014461 | 0.999017–1.020807 |
| Dart values | summed sampled peak RSS | 1.006334 | 0.989323–1.023553 |
| Native buffer | summed sampled peak RSS | 1.002064 | 0.988079–1.015034 |
| Pre-encoded span | summed sampled peak RSS | 1.019546 | 0.995247–1.031802 |

The only non-numerical finding is diagnostic ineligibility for primary
acceptance. The liveness fix remains useful, but does not resolve these RSS
or timing gates. Do not rerun this unchanged numerical campaign for a better
result. Fresh current-source Dart-values CPU attribution `40896349976` is
queued/running; preserve failed reports, the strict policy and all workload
floors. Full 48-case primary and refreshed 50-case supplemental acceptance
remain pending, as do current-source CI results.

CPU capture `40896349976` attempt 1 fails before FlatBuffers perf readiness.
MessagePack capture completes; FlatBuffers has a 45,504-byte perf header and
empty perf log. Source/library hashes stay unchanged, the probe exits 255,
and the server/process group exits cleanly. The reported `perf record exit
255` comes from `finally` cleanup and can mask the original capture error;
neither a native-library crash nor a permission failure is established.

A minimal Dart repro confirms that the old cleanup replaces a primary
readiness exception. The diagnostic template now preserves primary capture
error identity/stack, awaits cleanup and reports secondary cleanup errors
separately. Cleanup-only failure remains fatal. The actual generated probe is
imported into seven executable Dart contract cases; the complete 19 Python
tests pass. Restoring the old finally semantics in a private negative control
fails the readiness-identity assertion. No perf arguments, readiness deadline,
measured windows, workload settings or release thresholds change. A source-
attributed capture is still required; no failed numerical report is rerun.

The paired acceptance rows retain aggregate GC counters but no per-operation
timestamps; they cannot establish GC/tail-latency co-occurrence. The next CPU
capture therefore exports the existing VM trace for the already selected
calibrated interval after measurement. PID, role, requested VM range and wall
capture time are labelled separately. No stream is enabled, no GC is requested,
and retained-buffer completeness is explicitly not inferred.

A broad companion review times out and is incomplete. The focused guard review
completes with no concrete findings. Trace-export review raises missing-cleanup
and blocking-I/O concerns; source inspection resolves both: the existing outer
finally disposes every service, and synchronous file output occurs in the
separate diagnostic probe after the measured/native perf window. Its empty-
sample note acknowledges the existing check is correct. Do not treat those
unverified claims as product regressions or relax fail-closed attribution.

## Preserve native profiler failures and expose VM-only attribution

Follow-up `40899272991` on diagnostic-only `1b53f9cf` verifies the error fix:
the primary error is `perf exited before readiness: 255`; stopping failure is
logged separately. MessagePack perf has only a 47,840-byte header. VM snapshots
identify router PID 5757/client PID 5849; perf warns about PID/TID 5867. Inputs
and library remain unchanged and the server exits cleanly. The warning alone
does not establish the fatal cause: the upstream
[evsel implementation](https://gbmc.googlesource.com/linux/+/70087d2200d4a3bd31812ab4578c9ec70ea344af/tools/perf/util/evsel.c)
emits it on its recovered missing-thread path. Do not invent a library crash,
replace a failed numerical report or change the acceptance campaign.

The tool already supports profiling without native perf. The separate manual
`flatbuffers_vm_profile` campaign exposes that mode without changing the
existing native campaign, declared profile case, memory settings or workloads.
Its summary explicitly labels native stacks unmeasured and partial captures
incomplete. Native perf setup is skipped only in this mode; actual generated-
probe contracts now run after the pinned Dart SDK and dependency bootstrap.

The real capture-step shell executes in tests for both modes, including an
unset native-perf path and a path containing spaces. It initially reproduces
an empty-array/set-u failure under macOS Bash; using a populated common argument
array fixes it. All 21 CI execution tests, 19 profile-tool tests and 167 mutation
proofs pass. Companion review's empty-array concern is therefore verified and
resolved. Non-dispatch jobs are excluded by the job condition, and bootstrap
failure remains a failed job rather than a skipped-success contract claim.

The current paired data also narrows the Dart-values CPU attribution. Median
client CPU is 213.95 us/op for FlatBuffers versus 221.30 for MessagePack;
router CPU is 639.87 versus 626.54. Server GC totals are approximately equal
(3.522/3.525 us/op), but aggregates cannot establish tail co-occurrence.
Ordinary CALL options already have no extra controls and use the generated
path; do not broaden that path without new evidence. These per-process
absolute medians are diagnostic and must not replace paired ratio gates.

## Completed runtime CI and current-source VM attribution

Runtime CI `40891584949` passes every job. Full local `bin/verify` also passes
again after the diagnostic guard and trace changes. VM-only `40901845935` on
`d1b395e7` completes all three codecs with unchanged source/library receipts,
verified calibrated CPU windows, retained memory snapshots and clean exits.
Native stacks are explicitly unmeasured. The seven accepted-policy numerical
misses are unchanged; none of this establishes parity.

Normalized VM ticks show similar managed costs, not a clear new Dart bottleneck.
FlatBuffers/MessagePack client body generation is 3.964/3.635 ticks per 1,000
operations; body verification is 3.843/4.959. Ticks are not per-operation CPU
time. The companion summary reverses one comparison sign; raw values above
control the conclusion. After diagnostic collection the shared router heap is
39.98/39.71 MB, with no large retained payload arrays (FlatBuffers typed byte
arrays total 0.77 MB; external usage 21,696 bytes). Do not sum duplicated
isolate-group heaps or infer complete absence of leaks from these snapshots.

Using actual operation timestamps, GC B/E pairs and conservative clock offset
bounds, 21 of 110 selected FlatBuffers p99-tail operations certainly overlap
router user-group GC; 44 possibly overlap. There are no unmatched boundary
events, but other GC types/coverage are not inferred. Clock uncertainty is
1.1–1.4 ms, so possible overlap is not causation. This cannot explain every
tail. These are profiled diagnostic windows, not the accepted paired campaign.

Older `775103e8` native captures use the exact same library SHA-256
`184b27610bc3ca1cdef48ceff4fe4c9b58f50ade54c503c01e2940690c5ed609`.
Native/core/client source is unchanged; router reply lifetime code differs.
The bounded offline reader reproduces every per-PID/window sample count with
zero LOST events. Rust-library leaves are 227/3,714 FlatBuffers router samples
and 151/2,738 MessagePack samples; managed code, VM/runtime and kernel work are
larger categories. Keep reused JIT addresses ambiguous. These older captures
cannot accept current-runtime performance.

Native DWARF capture completes 23,934/21,909 total operations for these codecs,
versus 66,350/65,741 in the VM-only capture. This suggests substantial profiling
perturbation; different captures do not quantify its causal cost. To improve
native attribution, the hosted diagnostic explicitly requests frame-pointer
unwinding from the already frame-pointer-enabled Rust library. CLI default
DWARF remains available. The selected method is recorded in the source audit;
verbose startup output preserves counter-open errors. The
[upstream perf documentation](https://github.com/torvalds/linux/blob/master/tools/perf/Documentation/perf-record.txt)
describes DWARF stack dumps (8 KiB default) and the frame-pointer requirement.
SDK/JIT or cross-language unwinding may remain incomplete. Neither startup
reliability nor reduced overhead is established until the capture completes;
the companion's prospective guarantee is not accepted as evidence. All 19
profiler tests and 21 actual CI execution tests pass; focused review finds no
verified bug. No production path, policy, floor or accepted workload changes.

Supplemental `40906173218` now measures all three shards on frozen runtime
`d1b395e7`, in parallel with attribution. This completes pending TLS/payload/
E2EE/transcode cost reporting, not primary acceptance. Preserve old reports,
every new difference and per-shard provenance; the full 48-case primary still
waits for a passing diagnostic. Any later runtime change requires fresh final
evidence rather than treating this diagnostic report as an exemption.


## Fragmented application-model candidate

The private Dart-only prototype reproduces one concrete staging copy: the
64 KiB body is copied into its application FlatBuffer before sending. Prototype
v1 fails byte equivalence at non-eight-byte lengths because it omits finish
alignment with a file identifier. Retain that failed result. Corrected v3 passes
72 exact-byte vectors, including high/zero uint32 identities and unaligned
read-only inputs. It records 65,536 vector-copy bytes for the ordinary builder,
zero body-vector bytes for the fragmented model and an explicit 40-byte owned
prefix snapshot. These are correctness/copy counters, not performance results.

The production candidate generalizes this as `FragmentedPackedPayloadSource`,
`PackedPayloadParts` and `buildFlatBufferPayloadParts`. The source snapshots its
outer list, borrows the body, caches/counts contiguous fallback and grants no
native pointer trust or external lease. The application helper owns the small
prefix and preserves nested strings, tables and float64 alignment. The same
CBEN table/body constructor now uses this public path only for Dart-values rows;
native/pre-encoded constructors and all workloads/timers/observations stay put.
149 integration cases pass; explicit identifier and nested-alignment tests also
pass. The missing mutation support inventory was caught and repaired rather
than excluding the new tests. Companion tests/review are blocked by the shared
machine lease. All 49 core and 48 Session/E2EE Chrome/WebAssembly cases pass from their
canonical package roots; direct workspace-root loading timeouts are retained.
Canonical full verification and fresh hosted evidence are pending.

Frame-pointer profile `40907942373` completes successfully on `face31c9`, with
all calibrated windows verified, unchanged inputs/library and clean process
exit. Perf files shrink to roughly 11 MB each, but total throughput remains
strongly perturbed (FlatBuffers/MessagePack 22,727/23,286 operations, versus
66,350/65,741 in VM-only capture). Different captures cannot quantify causal
overhead. Do not treat storage reduction as a demonstrated latency fix or use
these sampled runs for acceptance. Keep native JIT/cross-language attribution
limits explicit. No new profiler changes are justified by this observation.


## Paired fragmented-model result and pre-encoded staging

`40922533817` completes 90 rows on `490f60bf`. Independent recomputation exactly
matches hosted output and verifies retained scenarios, policy, locks,
configuration and binaries. Five numerical failures remain: Dart-values
throughput 0.995779, p99 1.114498, GC 1.212659 and RSS 1.020991; native
pre-encoded RSS 1.006725. Native-buffer passes all seven metrics; Dart CPU/p95
and allocation pass. Separate hosted campaigns do not establish causal changes
from point estimates alone. Keep every earlier failure and strict threshold.

Client Dart-values median allocation is about 151,968 bytes/op for FlatBuffers
and 283,396 for MessagePack; router values are 217,358/217,391. Client GC pause
is 3.61/2.16 us/op, router 3.50/3.51. FlatBuffers has roughly 48–53 minor
collections per row versus MessagePack 95–100; excess cost is not explained by
more collections or old-generation events alone. VM-only `40926807868` uses the
existing diagnostic on this changed runtime without new profiling features.

The pre-encoded constructor still copies its Dart body into a contiguous Dart
application model before copying that model into native storage. A fail-first
runner test reproduces exactly 65,536 staging bytes. Complete encoded Dart
parts are equally valid pre-encoded input: use the existing public native
builder to copy them sequentially into one frozen owner. Every encoded byte,
including schema prefix/padding, remains counted as native input. Schema
construction stays in Dart, unlike direct native construction. The data,
identities, CBEN bytes, validation and all observation/timing windows stay fixed.
56 focused cases pass, including empty/tail boundaries and exact copy counts;
canonical and hosted verification remain required. This is a copy result,
not acceptance of RSS, GC or latency. Retain supplemental `40925767834` on the
preceding constructor; it cannot accept this follow-up's changed runtime.


Focused GLM review completes after local resources become available. Its first
larger answer hit the output cap and is not accepted as a completed review;
the narrower follow-up is retained. Source inspection rejects all three alleged
findings: observation is already guarded by owner != null for every serializer;
lease and owner disposal use the same idempotent handle; unfrozen builders are
released by the existing finally block. All-codec rejected-call tests now cover
both owned constructors. No ownership relaxation or changed cleanup follows
from this advisory output.

VM-only `40926807868` passes with unchanged source/library, verified windows and
clean exits. Post-GC-request client snapshots show zero PackedPayloadParts,
packed-source payloads and WampSamples. FlatBuffers/MessagePack user heap usage
is about 27.5/26.7 MB, capacity 62.9/46.0 MB; capacity is not resident/live usage
and must not be subtracted from RSS. The selected client GC intervals are
262/197 us median, router 791.5/472 us. Sampled clock uncertainty is roughly
1–1.7 ms, and partial overlap is not causation. These perturbed windows do not
reproduce the acceptance run's full client GC cost or accept its better sampled
p99. No complete remaining-tail explanation is established.


The bounded generic-core Qwen review also completes. Its alleged cross-thread
cache race does not apply to this synchronous getter on a Dart isolate; there
is no await or shared mutable Dart object. Padding remains below the checked
64 MiB whole-model bound, application schema validation is explicitly owned by
the callback, and prefix copying/lifetime are documented and counted. The
suggested vector.start/end methods do not exist. No verified production defect
follows from these claims. The helper's existing portable WAMP uint64 range is
now explicit; wider opaque application fields remain forwardable via a source
built with the application's own builder. All 59 focused model/source cases pass.


## Complete cost report and narrow decoder follow-up

Supplemental `40906173218` completes all shards and its merge job on `d1b395e7`.
Independent per-shard audits verify 30/12/8 cases and 900/360/240 rows, pinned
inputs/scenarios/policy/configuration/locks and production binaries. Recomputed
aggregate comparison and provenance exactly match hosted output: 50 cases,
1,500 rows, no integrity findings and 193 numerical diagnostic findings. Absolute
costs across runners stay not_comparable; this never accepts primary parity.

`9bf3235c` diagnostic `40929890341` is independently reproduced from all 90 rows.
Eight gates fail: Dart throughput 0.984728, p95 1.007360, CPU 1.011071, GC
1.161253 and RSS 1.029451; p99's point 0.972737 passes but upper bound 1.197151
fails. Native-buffer RSS point 0.994958 passes but upper 1.050847 fails;
pre-encoded RSS point 1.011707 fails. Native non-RSS gates pass. Keep the earlier
five- and seven-failure reports; separate campaigns cannot establish causality
from their point differences. Copy improvements alone do not accept performance.

The current decoder creates a fresh typed Result/Event/Invocation from an
already validated/metadata-agreed frame, then repeats projection even when the
complete metadata is exactly two PPT strings. The output is discarded. A narrow
guard skips only that duplicate work. Frame validation/agreement and every other
history/default/custom path remain unchanged. GLM's conditional advice identifies
future model round-trip drift; explicit model -> projection and post-edit tests
cover all three classes plus normal/max IDs. Broad VM serializer/Session (3,593)
and browser model/history (136) tests pass, with all 167 mutation proofs valid.
Private baseline/candidate byte/error corpora match 96 valid and 488 mutated
inputs. The initial script's Object/PPTOptions inference failure is retained.

The first component timing attempt is refused by the shared resource lease.
Another capture is invalid because own unit/browser tests overlapped it; it is
rejected in full and preserved. Once those tests exit, an isolated resource-
leased ABBA capture records 354,969/352,194 baseline and 296,254/296,057 candidate
microseconds per 200,000 decodes, with identical checks and pinned reader hashes.
This is about 16% lower local decoder time, not end-to-end or RSS acceptance.
It uses standard local Dart 3.13.1/macOS, no forced GC or tuning. Full canonical
and final-source hosted evidence remain required before adopting the follow-up.

## Decoder checkpoint 828721fd (2026-10-29)

Full local bin/verify exits 0 (`/tmp/connectanum-ppt-projection-full-verify.log`).
Hosted copy proof 40941222405 passes and the independent audit verifies 3,224
inputs, 120 live / 300 inventory / 32 zero-avoidable-copy checks, all E2EE,
transcode and native-crypto counts, raw hashes, stable PIDs and cleanup.
All three positive native-view phases and the intentional negative control
verify. Package configuration is digest-only, and dependency internals remain
unmeasured. Local audit logs are `/tmp/connectanum-flatbuffers-copy-8287-independent-audit.log`
and `/tmp/connectanum-flatbuffers-copy-8287-private-phases-audit.log`.

Paired 40941226221 completes 90 rows and is independently reproduced exactly
(`/tmp/connectanum-flatbuffers-diagnostic-8287-independent-audit.json`). Three
numerical misses remain: Dart-values RSS 1.0161129493, CI
[1.0015429753,1.0220331655]; native-buffer p99 1.0346435710, CI
[0.8002520479,1.3305243446]; pre-encoded RSS 1.0019252925, CI
[0.9923918248,1.0178649964]. Every throughput, CPU, p95, allocation and GC gate,
and Dart-values p99 passes. These are distinct paired campaigns, so the point
changes are not causal attribution. No threshold, workload or measurement-window
change is justified by these results.

Pinned Dart [3.13.5 scavenger source](https://raw.githubusercontent.com/dart-lang/sdk/3.13.5/runtime/vm/heap/scavenger.cc)
confirms that `Scavenger::PrintToJSONObject` publishes GC `time` using
`MicrosecondsToSeconds(gc_time_micros())`. The benchmark's seconds-to-microseconds
conversion is consistent with that source. Existing isolate-group deduplication
is also present; neither a unit error nor duplicate group counting has been
established. No SDK flags or allocator tuning are introduced.

## Scoped native initialization and hidden owner-probe coalescing (2026-10-29)

Fresh baseline `bin/test-fast` exits 0. A minimal actual-constructor repro
observes 65,536 Dart body input-copy bytes for each of FlatBuffers, CBOR and
MessagePack. The first private timing overlaps that baseline and is unleased;
it is rejected in full before use (`/tmp/connectanum-direct-native-body-correctness-only-rejected-timing.txt`).
Refused shared-lease admissions run no measurement. All later component timings
acquire the common machine lease, retain every result and verify unchanged
private source/package configuration and native library hashes. They never
accept throughput, latency or RSS.

Ordinary guarded FB putUint32 loops cost about 341–345 ms/1,000 constructions
versus 34–38 ms for staging/copy, so they are not adopted. Sequential scoped,
per-word callback and indexed/batched prototypes also regress. A guarded word
writer with a final private typed-data field and closed check reduces the
component penalty to about 6–7% (34.7/36.9 vs 33.6/33.6 ms); this is a candidate
tradeoff for eliminating the 64 KiB Dart allocation, not an end-to-end win.
The final private component receipt is
`/tmp/connectanum-native-vector-guarded-final-word-component-timing-v1.log`.

Public candidate APIs `writeByteVector`, `writeByteRange` and scoped byte/word
writers expose no raw pointer, typed-data or buffer. Scalar stores generate
output values; explicit source-byte copies and allocator growth remain counted.
All writers close before publication. Callback/copy/Future failure blocks
publication until reset/dispose (fixed-size builders permit disposal only).
Fresh native allocations zero all capacity (`owned_buffers.rs::allocate`,
storage.resize(length, 0)); growth copies only the previous used tail. The new
reserved vector lies entirely before that copied tail. Every reset permanently
enables explicit vector-span clearing, even if reset fails. Fixed byte-range
updates intentionally preserve existing initialized values and have no reset.

All three native benchmark constructors use the same existing Dart word/body
algorithm inside the original preparation window. No native/Rust pattern
generator, body cache, shortened loop or observation change is introduced.
Generated CBEN and CBOR/MP PPT bytes stay identical. The latter allocate up to
three leading alignment bytes outside the frozen wire span; every transmitted
byte and wire size stays unchanged. Ordinary Dart-values and pre-encoded groups
retain their earlier semantics. The original nonempty native fixture assertions
fail first at expected zero vs 1 / 1,024 / 65,536 copied bytes. The candidate
passes 215 model/live transport cases and 69 ownership cases, including maximum
IDs, nonaligned/binary-width boundaries, source-copy failure, mutation rejection,
all escaped writers, growth/reset and ordinary/void-typed Future rejection.
The standalone native GC child retains closed facades after their allocation
and handles have actually reached zero; both public writes still throw after
collection. No forced GC enters any benchmark or acceptance run.

Completed GLM design/review advice is verified against source and tests. Its
claim that retaining a guarded private facade inherently permits post-close
native access supplies no public access path; all setters check the closed flag
before data access, as existing disposed native builders do. The actual freed-
allocation child probe verifies this boundary. Its reset/growth arithmetic
concern is disproved by the allocator contract, span arithmetic and exact SDK
byte goldens. The later review itself retracts its span/freeze/index concerns,
but conflates fixed-size byte-range updates with the separate FB reset API.
Clarify and test preservation of untouched fixed-range values. Qwen's fixture
review assumes ByteData scalar stores need alignment and that explicit-length
word views need a multiple-of-four total buffer; neither assumption applies.
Existing scalar code and the new bounded fallback handle unaligned data, and
exact full/partial-vector boundary tests pass. Advisory logs are
`/tmp/connectanum-guarded-word-region-design-judge.log`,
`/tmp/connectanum-native-body-public-api-review.log` and
`/tmp/connectanum-native-body-fixture-review.log`.

Source inspection then finds a separate actual staging copy in
`_nativePptPayloadOwner`: it reads packedPayloadBytes before checking whether the
owner can be a trusted native candidate. A real 64 KiB Native RawSocket Session
RPC with a fragmented source succeeds but fails the no-contiguous-getter
assertion (expected 0, observed 1). Move only that getter behind the existing
encoding/native-owner checks; preserve exact byte identity, owned-view marker,
lease handling and lazy-owner cycle traversal. The regression now reads zero
contiguous bytes and echoes identical data/handshake/Goodbye codes. All 74 related
native frame/profile/Session tests and all 167 mutation proofs pass. Focused
review finds no concrete defect; its residual identity/type conditions are
unchanged intentional trust checks. This directly removes an unnecessary
coalescing operation; it does not itself accept RAM parity.

The first new full verification is superseded before completion to reproduce
and fix this additional bug. Its log and explicit supersession note are kept;
no failed numerical report is discarded. Renew full frozen-source verification,
copy evidence and the original paired gates before adoption.

A further fail-first port test shows that the initial scoped facades can be
sent as message snapshots while active. Mark both scoped types Finalizable,
matching native builders, so a cloned active guard cannot cross isolate
boundaries. The transfer is now rejected, and all 70 ownership cases pass.
This changes no native ABI and retains the actual freed-allocation GC proof.

Latest completed checkpoint CI is green: both 9bf3235c run 40929882938 and
828721fd run 40949419438 pass all 38 jobs. Supplemental b7a6 run 40925767834
also finishes all three shards and merge. Independent audits reproduce 30/900
protocol, 12/360 payload-size and 8/240 encrypted-progressive cases/rows. All
retained inputs, binaries and comparisons verify. Aggregate comparison AND
provenance match hosted output exactly: 50 cases / 1,500 rows / zero integrity
findings / 195 numerical diagnostics, without pooling absolute runner costs.
The first aggregate summary formatter used the wrong key after both equality
assertions passed; its failure log is retained. Correct schema-key reproduction
succeeds in `/tmp/connectanum-flatbuffers-supplemental-b7a6-aggregate-audit-v2.log`.
These reports are checkpoint costs and do not accept the changed native model
constructor or owner probe. Renew final-source evidence under unchanged gates.

## Private diagnostic directive-order repair (2026-10-30)

Copy run 41056032556 stops before any negative-control row because its privately
patched native_buffers.dart places the attribution constant immediately after
native_owned_segments.dart, before the newly added native_writable_bytes.dart
part. The retained server log states: Directives must appear before any
declarations. This is a private instrumentation compilation failure, not a
production ownership or numeric result. Keep
`/tmp/connectanum-flatbuffers-copy-ef61-failed` and the failed workflow/log.

The actual/current plus synthetic future-part test fails first. Inserting the
marker before the unique first declaration documentation anchor keeps all
imports/parts above it and retains replace_once drift/ambiguity refusal. All
15 contracts and 167 mutation proofs pass. A privately copied complete client
library with the new marker analyzes cleanly. Its first local analysis resolved
both /tmp and /private/tmp URIs as distinct libraries; canonical paths repair
that harness-only alias and the failure log remains. Bounded local debugging
correctly requests the retained server compiler log; no readiness timeout is
relaxed. Production Dart, binaries, policies, lockfiles, scenarios and timing
windows are unchanged. Preserve numerical run 41056036677; only the failed
copy workflow needs renewal after this tooling-only repair.

## External connectivity blocker (2026-10-30)

Frozen numerical run 41056036677 completes with failure status. Its retained
artifact metadata is reachable intermittently: artifact 12977897282,
`wamp-flatbuffers-primary-ef61b156fb61572d7f4f0baf109e1393386fc2cd-1`,
21,792,130 bytes. Repeated authenticated API/ZIP requests hit TLS handshake
timeouts or connection resets from this Mac, including Azure storage. The
failed-step log cannot be fetched either. Do not infer the remaining numerical
gates without raw data. No unchanged numerical rerun is dispatched.

A bounded resumable range fetch obtains a signed download location but cannot
retrieve its first byte after five retries; URLs and credentials are deliberately
not logged. The attempt lives only under /tmp and changes no repository/runtime
code. The desktop check-diagnostics connection is also unavailable; the public
web tool cannot read the run API. Network context/restoration is requested via
an asynchronous user question.

Full tooling-head bin/verify passes all earlier tooling/VM/native/live/router
checks, then exits 124 after three 180-second attempts to resolve/download the
MCP consumer dependencies from pub.dev. Retain
`/tmp/connectanum-native-marker-full-verify.log` and its `.exit` sidecar. This is
an environmental failure, not a passing verification. The preceding runtime
full run reaches all consumer and both browser successes. Renew consumer/full
verification after network recovery. Source SHA 2d0ee379 has identical packages,
native code, dependencies and lockfiles to numerical runtime ef61b156.

Copy renewal 41057771623 and current-head CI 41057774775 continue remotely;
latest completion status is not retrievable. Keep #103 and PR #132 open/draft,
and retain these exact runs for auditing once connectivity returns. All local
runtime changes are already pushed; only current status documentation is dirty.


## Explicit receive-payload storage release (2026-10-30)

The ef61 retained rows locate most remaining RAM excess in the client process.
A source-identical direct FFI repro on 2d0ee379 creates an opaque 65,536-byte
FlatBuffers result, attaches the normal Session anchor and observes its Rust
StoredMessage with the existing weak observer. `releaseNativeMessagePayload`
returns true but the weak observer remains alive (1). This is a release gap,
not evidence of a monotonic leak: SDK-owned exported references wait for GC.
The API already requires callers to stop accessing every view after release.

Group client message exports under an optional explicit byte lease. Ordinary
`NativeIncomingMessage.release()` and the shared router byte reader retain their
exported-view contracts. Only explicit payload release disposes the client's
export group. A separate export lease remains valid. Native frame allocations
used by Dart RawSocket receive also acquire a detachable allocation owner,
shared across bounded aliases; the same explicit API ends that allocation's
lifetime and later native pointer lookups fail closed. No allocator, SDK,
workload, body, observation window or gate changes occur.

All five native serializer/opaque regressions fail first with a live owner
after release. All ten candidate cases, including independent owners, pass.
The identical direct repro now reports 0 immediately, without GC. The Dart
external-frame regression fails first (release falsely returns false) and
passes after the fix. All 405 focused file/crypto/lifetime tests and 94 socket
cases pass; the latter includes a fragmented FlatBuffers result followed by
an independent frame. A child GC proof retains only a derived immutable
ByteData after both the incoming wrapper and root facade die, then observes
StoredMessage destruction after that last view is dropped. GC is requested
only in the lifetime regression process, never in acceptance. Focused analysis
is clean and all 167 mutation equivalence proofs remain valid.

The fresh preceding canonical `bin/test-fast` exits 0. Full `bin/verify` runs
on the candidate; preserve its final exit sidecar. Local companion requests
initially refuse the shared resource lease held by another project; do not
bypass it. A later Qwen review obtains the lease but exceeds its output bound;
retain that failed advisory attempt and request a bounded GLM safety audit.
No numerical acceptance is claimed until a changed-runtime campaign completes.

The completed GLM audit raises three advisory concerns; source verification
rejects them as defects. Every export's native token is an acquired Arc to the
same StoredMessage; any surviving old export already pinned the complete
message, so grouping exports adds no additional payload-allocation retention.
The C contract explicitly permits repeated token addresses, each representing
a separate acquired reference; releasing each once is required, and the ten
weak-observer tests cover the multi-export and independent-scope cases. The
retained-owner predicate returns false after release; it cannot become true
as claimed. Raw typed-data reads after explicit release are forbidden, not
revocable; do not test them by dereferencing freed native memory. Existing
GC-only and double-release proofs cover the valid contracts.

Master integration includes MQTT merge ef822e08. Preserve both required CI lane
inventories, both callback cleanup paths, MQTT dispatch once inside the guarded
WAMP boss loop, both newly adjacent test blocks and the previous decoded-CBOR
file-chunk fix. Full analysis and both Rust formatting checks pass. CI contract
tests pass 23 cases. Mutation preflight initially rejects stale source hashes;
map the 12 original AST mutations only through byte-identical containing source
blocks (five drain, seven settings proofs). The whole 158-line selected drain
region is identical after an eight-line insertion, so shift its range by eight.
The full 167 proofs validate again; no proof or scoring threshold is waived.
Pre-merge full verification is intentionally superseded at tooling (exit 143),
with a structured termination receipt; rebuild native code and rerun on the
merged candidate. The first standalone build helper mistakenly runs under zsh,
which lacks BASH_SOURCE; the corrected invocation uses bash explicitly.

Merged client verification exposes seven reproduced file-prefix integration
failures: the newer fragment serializer splits an empty binary CBOR argument
into its prefix and zero-length body, producing four fragments rather than
master's expected three. Accept both exact valid layouts without coalescing the
file body, retain nonempty/malformed/oversize guards, and account the three
small control/header copies. A regression verifies both three/four-fragment
inputs, unchanged decoded bytes and exact prefix.length-1 coalescing bytes.
All 480 combined file/lifetime/client cases pass after the repair. The other
merged router/MQTT suite passes 667 cases with seven optional Paho skips; Rust
HTTP CLI passes all ten. Initial post-merge local-debug/review requests are
again refused by the shared resource lease; do not bypass it. Master WAMP
diagnostics 41105562735 reports failure at its run step, but hosted logs cannot
be retrieved (HTTP 403 from the log receiver); keep this read failure recorded
and verify the merged candidate's actual workflows before readiness.

The completed 2d0ee379 memory artifact is independently audited: 3,224 input
contents (including all three retained generated files), the native library
digest and all 18 memory snapshot hashes agree. Recomputed memory attribution
matches hosted JSON exactly after tuple/list normalization; retain the first
raw Python equality failure rather than hiding it. No integrity findings occur.
FlatBuffers client externalUsage is 29,640,464 before / 34,165,208 after workload
/ 112 after the diagnostic GC request; CBOR is 6,296,352 / 5,902,848 / 112 and
MessagePack is 112 throughout. This is lifetime attribution, never acceptance.

Frozen merged runtime 40f8cec5 is pushed. Full CI 41112069093, owned copy
41112073189 and paired diagnostic 41112077193 are dispatched. Local full
verification exits 1 at the tooling suite; hosted Fast Checks fails similarly.
The single failure is the old hard-coded 1100–1257 mutation-range expectation
after the already proved +8-line source insertion. Update only its expectation
to 1108–1265; all 93 contracts pass (one platform skip). No production, benchmark
policy/scenario or instrumentation changes occur. A successful local Qwen debug
agrees with this source-verified diagnosis. Renew correctness CI/verification
on the tooling head, leaving both numerical and copy campaigns untouched.


### Completed merged-runtime evidence and owner precedence (2026-10-30)

Paired 41112077193 is independently reproduced exactly (90 rows, three cases),
with retained policy/scenarios/locks and native digests verified. Native-buffer
RSS passes, median 0.9993, CI [0.9858, 1.0240]. Retain four numeric findings:
Dart-values p99 0.9772209567 [0.9328537170, 1.1998468606], GC 0.9072043762
[0.7838200752, 1.1617671870], RSS 1.0180264809 [1.0140671904, 1.0850607930],
and pre-encoded RSS 1.0049883897 [1.0022969898, 1.0107649544]. No integrity issue
or acceptance-policy change; diagnostics cannot establish primary acceptance.

Copy 41112073189 independently verifies 3,277 input contents, 120 live / 300
inventory / 32 zero-avoidable checks, E2EE/transcode/native-crypto observations,
all raw hashes, PIDs, exits and cleanup. Three native-view phases each pass six
rows; negative control produces its expected single failure and no rows. The
initial formatter assumes an optional negative-only field and raises KeyError;
preserve that error and use explicit optional-field handling.

Dart-values memory attribution 41116315782 retains 18 snapshots and reproduces
hosted attribution exactly. After-work native wrapper/allocation counts are
zero, externalUsage is 160 bytes, and retained WampSample objects disappear after
diagnostic GC. Heap capacity and RSS must not be equated, and this diagnostic
GC must not enter acceptance. Full profile source/native input audit is pending.

Full verification da46d7f6 exits 1 on two encrypted FlatBuffers file metadata
cases merged from master. Decode/authenticate CBOR PPT before validating decoded
metadata; ciphertext storage can remain attached to the decoded invocation.
Reject unauthenticated plain opaque headers as before. Both live cases pass.
Fail-first release tests also expose that a replaced public anchor can point to
a different native allocation: retained storageOwner must take precedence. The
wrong-allocation and ordinary-Dart-owner cases pass after this correction.
512 lifetime/file and 186 socket/file cases pass; canonical live RPC uses an
external FlatBuffers peer and checks actual backing ownership. Preserve earlier
private tests' wrong-peer and always-native assumptions as invalid diagnostics.
Renewed full verification is running; current CI has four MQTT cleartext profile
misses under unchanged MQTT budgets/source, while master's corresponding job
passes. This remains a readiness blocker pending attribution and verification.
