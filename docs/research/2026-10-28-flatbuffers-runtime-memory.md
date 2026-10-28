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
