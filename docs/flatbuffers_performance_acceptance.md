# FlatBuffers performance acceptance contract

Status: acceptance contract for milestone issue #103. The runner exposes the
three construction groups for typed RPC and pub/sub and records payload-preparation
and native-builder copy counters. Native FlatBuffers callers pass owned typed
FlatBuffers spans directly into the native FlatBuffers frame path for two
construction groups. Native-path copy attribution is now partial; complete
cross-client coverage and the paired performance campaign are unfinished. No
parity result is accepted.

The runner selects a group with `payload_construction = "values"`,
`"native_buffer"`, or `"pre_encoded_span"` and requires
`ppt_scheme = "x_connectanum_bench_typed"`. Typed rows are restricted to RPC and
pub/sub and the CBOR, MessagePack or FlatBuffers PPT serializers. Every operation
uses a unique worker/iteration identity and validates the returned or delivered
body. The 18-case live echo matrix establishes this behavior for RPC and pub/sub
over RawSocket with the Dart caller, CBOR WAMP envelope, all three PPT
serializers and all three construction groups. A separate 12-case matrix covers
typed FlatBuffers PPT over RawSocket/WebSocket, Dart/native callers and all three
outer serializers, but does not exercise these runner construction groups. The
runner now adds 12 live native-caller cases with a FlatBuffers WAMP envelope,
RPC/pub-sub, all three PPT serializers and both `native_buffer` and
`pre_encoded_span` groups over two iterations. The FlatBuffers PPT owned groups
use the retained native span path; CBOR and MessagePack PPT remain serializer
fallback rows. These matrices are correctness evidence, not a performance run.
Typed runner groups still lack WebSocket and TLS coverage.

`latency_ms` covers construction, serialization, transport, receive-side decode,
and response/event validation. `payload_preparation_us` measures runner-side
construction only. For `values` and `native_buffer` with dynamic CBOR/MessagePack
PPT, it ends before PPT serialization. For `pre_encoded_span`, it includes PPT
serialization and copying the resulting bytes into the frozen native owner.
`native_builder_input_copied_bytes` and `native_builder_growth_copied_bytes`
measure only FlatBuffers/native-buffer builder input and growth. They do not
measure codec, transport, TLS, WebSocket, E2EE or receive-side copies and cannot
by themselves satisfy the copy-evidence gate below.

For a native caller with a FlatBuffers WAMP envelope and typed FlatBuffers PPT,
the `native_buffer` and `pre_encoded_span` runner groups now construct a packed
payload with the exact frozen `NativeOwnedBuffer` view. Session sends that view
as a retained native frame span and rebuilds only the control envelope. Focused
ownership tests and the live runner matrix verify that selection and lifetime.
This proves Dart-side view identity at frame submission; it does not prove that
WebSocket masking, TLS, coalescing or kernel output avoid copies. All Dart
callers, other WAMP envelopes, and CBOR/MessagePack PPT rows keep their current
serializer paths, where ordinary native segmented sends copy Dart fragments.
Keep those rows explicit until matching shared ownership/segment optimizations
and end-to-end copied-byte evidence exist. Issue #96 remains open for supported
paths and acceptance work still outstanding.

The runner integration and current copy-counter follow-up pass `bin/test-fast`
and full `bin/verify` on 2026-10-05, including Chrome WebAssembly and live WAMP
coverage. These are correctness checks, not timed results or parity acceptance.

## Copy-counter coverage

The native runtime exposes process-wide deltas for payload bytes copied into
WebSocket masking scratch buffers, payload bytes copied into unmasked WebSocket
coalescing buffers, and plaintext bytes accepted by Rustls writers. WebSocket
headers are excluded from the mask/coalescing counters. The separate Rustls
counter reports accepted input volume, including any WebSocket framing passed
through that writer; it is not a measured memory copy. In-place XOR, kernel
socket writes, and KTLS are not counted. The benchmark also counts explicit
Dart-to-native `setAll` copies in native client and router send APIs. Owned
native-buffer submissions do not increment that counter.

`transport_copy_bytes` sums measured copy operations on the active cleartext
path across the client worker and router process. A payload can be counted again
at a later layer, so this aggregate is copy traffic, not unique application
bytes. Builder input/growth and any transcode copies stay separate. TLS rows
keep `transport_copy_bytes` and `tls_copy_bytes` as `not_measured` because the
current Rustls counter does not measure copies. The separate
`tls_plaintext_accepted_bytes` value is a throughput diagnostic. Snapshots use
before/after deltas around one benchmark command.

Missing active-path counters fail closed. Older native libraries without the
optional snapshot symbol leave affected fields `not_measured`. Dart-managed
socket masking, TLS copies and mixed-serializer router transcodes remain
`not_measured`; those rows cannot pass the copy gate.
The current counters therefore provide native-path attribution only and do not
complete the required coverage or establish FlatBuffers parity.

## Campaign evaluator status

`tool/wamp_serializer_compare.py` validates a prepared campaign manifest and
its JSONL reports. It checks source/dependency/platform metadata, non-overlap,
recorded codec order, workload and iteration identity, minimum duration/sample
counts, client and server-process resource evidence, copy evidence, paired
ratios and deterministic bootstrap confidence intervals. The server process
contains both `RouterBinding` and the HTTP benchmark controller; its metrics are
not labelled as router-only. Reports retain client and server blocks separately,
while resource ratios sum CPU, allocations and GC pauses per operation. The
`summed_sampled_peak_rss_bytes` metric adds each process's highest 50 ms RSS
sample; it is not simultaneous combined RSS, because the process peaks may occur
at different times. Each workload runs one throwaway iteration before the
measurement window so lazy router isolates are present before server profiling
starts. The collector profiles every application isolate present at the window
start and rejects isolate-set changes or incomplete GC timelines. Process CPU
ticks and RSS sampling use Linux `/proc`; those fields remain missing on other
platforms and block acceptance. The machine-readable policy is
`native/bench/artifact_gate/wamp_flatbuffers_performance.json`; eleven focused
unit tests pass. The evaluator does not schedule or execute a campaign, and no
manifest or measured comparison result exists yet. The report must not be used
to claim parity until the complete primary matrix runs with no missing metrics.

The relative gate currently requires no point-estimate regression versus the
better binary baseline for CPU, allocations, GC pause and peak RSS as well as
throughput and latency. Separate absolute per-row CPU/memory ceilings are still
undeclared, and current Dart-managed TLS/socket and mixed-codec transcode copy
paths are unmeasured. Those rows remain blocked until instrumentation and policy
are complete.

## Comparable workloads

Compare identical application data and operations in three separate construction
groups: ordinary Dart values, buffers built in native storage, and immutable
pre-encoded spans. Make shared ownership and segmented submission optimizations
available to CBOR and MessagePack too. Label ordinary FlatBuffers envelopes with
CBOR argument fragments separately from typed FlatBuffers PPT. Typed fixtures need
an explicit application schema containing worker/iteration identity; keyword
containers are not valid typed PPT fixtures. Validate equivalent field values,
binary spans, ordering and responses for every codec.

Primary rows are RPC and one-subscriber pub/sub with 64 KiB payloads, across
RawSocket/WebSocket, cleartext/TLS, Dart/native clients and all three construction
groups. Each complete row compares FlatBuffers with both CBOR and MessagePack.
An unavailable optimized path is an explicit missing row, not an ordinary-value
comparison. Report small controls, 10 KiB, 100 KiB, 1 MiB, eight-way fan-out,
progressive results, mixed codecs, masking/fragmentation and encrypted PPT as
separate diagnostic rows. A diagnostic failure still requires an explanation and
resolution; passing primary throughput does not clear a correctness failure.

## Repetition and attribution

Compile workers before timing. Use three warmup passes and at least seven paired,
interleaved repetitions per codec/scenario. Each measured repetition lasts at
least ten seconds and contains enough observations to support its percentiles.
Record exact source/artifact, scenario/configuration and dependency hashes;
toolchains, CPU/OS/runner, virtualization, load, overlap and thermal/power state.
Do not time performance rows concurrently with builds, tests or mutation jobs.

Retain every observation. Increasing repetitions or duration requires a new
explicit campaign; do not select favourable runs from failed campaigns. Publish
the codec order and deterministic schedule. Estimate paired 95% confidence
intervals and retain the computation inputs and method.

## Gates and copy evidence

For every primary row, require median throughput ratio at least 1 and median
p95/p99 latency ratios at most 1 against the better of the two binary baselines
for each metric. The proposed 5% noise allowance applies only to confidence
interval bounds: throughput lower bound at least 0.95 and latency upper bounds
at most 1.05. It does not permit a regressing point estimate. Wide intervals are
inconclusive and block acceptance. Display raw ratios and both baselines; do not
aggregate away a failing row.

Require zero avoidable bulk payload copies at documented optimized boundaries,
using pointer/allocation identity or independently checked copied-byte counters.
Report builder growth, cryptography, TLS, masking, coalescing and transcoding
separately. A retained frame owner or fragment count alone is not copy evidence.
Report CPU, allocations/GC, live and peak retained bytes, wire bytes and latency
distributions. Missing metrics cannot pass. CPU/memory regressions need explicit,
measured budgets before release acceptance; those budgets remain undeclared.

Every repetition must validate payload and sequence identity, drain consumers and
prove final buffer release. Keep failed results, teardown evidence and complete
configuration. Hosted CI must publish exact-head comparisons and enforce the
same declared machine-readable policy. Shared-host noise, unexecuted construction
groups or missing ownership metrics must remain visible limitations.
