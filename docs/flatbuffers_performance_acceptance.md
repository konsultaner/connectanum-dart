# FlatBuffers performance acceptance contract

Status: acceptance contract for milestone issue #103. The campaign executor is
implemented and has completed a Linux diagnostic run. The workload runner exposes the
three construction groups for typed RPC and pub/sub and records payload-preparation
and native-builder copy counters. Native FlatBuffers callers pass owned typed
FlatBuffers spans directly into the native FlatBuffers frame path for two
construction groups. Native CBOR/MessagePack callers now retain owned
`native_buffer` and `pre_encoded_span` PPT bytes through the shared segmented
native submission ABI; small serialized header copies remain counted. The
fixed CBOR/MessagePack native fixture now writes the complete existing PPT
structure directly in native storage. Its body input copy remains counted;
it does not build a Dart map or serialize the full payload again at send time.
Native-path copy attribution is now partial; complete
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
use the retained native span path. CBOR/MessagePack PPT with a FlatBuffers
outer envelope remains a serializer fallback in that matrix; CBOR/MessagePack
outer envelopes now retain both owned construction groups through native PPT.
The expanded native Session matrix covers both groups, RPC/pub-sub and
RawSocket/WebSocket with CBOR/MessagePack envelopes. These
matrices are correctness evidence, not a performance run.
The campaign diagnostic adds typed construction-group coverage for WebSocket
and TLS, as described below; the complete primary matrix remains unaccepted.

`latency_ms` covers construction, serialization, transport, receive-side decode,
and response/event validation. `payload_preparation_us` measures runner-side
construction only. For `values` with dynamic CBOR/MessagePack PPT, it ends before
PPT serialization. For `native_buffer`, it includes complete model/PPT encoding
in native storage and the single body input copy. For `pre_encoded_span`, it includes PPT
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
callers use their normal serializer/transport paths. Native CBOR/MessagePack
envelopes with matching PPT reuse exact owned spans in both construction groups;
the newly encoded control fragments still get copied and counted. Other native
envelope/PPT combinations keep their regular serializer paths, where ordinary
native segmented sends copy Dart fragments. Full SDK/socket/TLS/transcode copy
evidence remains incomplete. Issue #96's supported native-buffer
contract is complete; the cross-codec benchmark requirement remains under #103.

The native dynamic fixture supports the existing uint32 identity fields,
fixed ASCII field names and binary body up to 64 MiB. It emits the same
`{args: [{worker, iteration, body}], kwargs: null}` shape as the regular
serializers. Integer and binary-length headers follow
[RFC 8949 section 3](https://www.rfc-editor.org/rfc/rfc8949.html#section-3) and
the [MessagePack specification](https://github.com/msgpack/msgpack/blob/master/spec.md).
Exact native bytes, independent regular decoding, body input-copy counts and
exported-view lifetime are checked against 140 boundary vectors. This is an
encoder for the benchmark model; the public serializers remain unchanged.
The packed payload has an explicit lazy decoder for application access.

The native-construction follow-up passes fresh `bin/test-fast` and `bin/verify`
on 2026-10-06. All 1,541 Linux benchmark cases pass without native skips; targeted
benchmark coverage is 2,981/3,033 lines (98.286%), above the unchanged 98% gate,
with no benchmark findings. The codec is 122/122 lines. This targeted report
leaves other packages unmeasured and does not accept whole-repository coverage.
Both existing typed ciphers, mixed-serializer encrypted pub/sub and native CBOR
encrypted file transfer also pass; the new constructors use the unencrypted
custom typed scheme. Full crypto copy attribution remains incomplete.

The runner integration and current copy-counter follow-up pass `bin/test-fast`
and full `bin/verify` on 2026-10-05, including Chrome WebAssembly and live WAMP
coverage. These are correctness checks, not timed results or parity acceptance.

The registered WAMP Profile Benchmarks workflow also has an explicit manual
`flatbuffers_primary` choice for the unchanged full 1,440-row campaign. It
retains production binaries, source/lock/policy hashes and failed reports on a
hosted Linux runner. The six-hour job budget includes a 330-minute executor
deadline; incomplete execution remains failed evidence. Local workflow checks
are not hosted timing acceptance. See [hosted campaign usage and limits](research/2026-10-07-hosted-flatbuffers-primary-campaign.md).

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

The Dart benchmark worker also records Connectanum-owned RawSocket frame
payload copies, small-fragment coalescing, pre-handshake queue copies, and
WebSocket fragment coalescing. These counters are scoped to one workload
window. They do not infer copies inside `dart:io`, socket/TLS implementations,
or WebSocket masking performed by the Dart SDK.

Small RawSocket fragments now go directly into the framed buffer in one payload
copy, so their intermediate fragment-coalescing counter stays zero. FlatBuffers
also implements the ordinary fragment API for encoded args/kwargs and opaque
bodies. The [actual socket diagnostic](research/2026-10-06-dart-flatbuffers-segmented-send.md)
observes full external body reuse and partial-view SDK copies separately; it does
not turn the known-own lower bound into complete transport coverage or accept a
timing campaign. Contiguous and segmented codec output are checked independently
with Rust/Python readers.

Native prefetched input staging and replay now have separate observed counters.
The optional `ct_transport_copy_metrics_snapshot_v2` supplies them without
changing the old 24-byte snapshot ABI. Missing counters remain unavailable.
Reports claiming complete transport coverage must retain numeric nonnegative
router input counters, and native callers must retain their own input counters.
The comparator rejects older complete-coverage labels without this evidence.
The prepend path copies an unread remainder once instead of twice; this does
not establish performance parity. See [source and checks](research/2026-10-07-native-prefetched-input-copies.md).

`transport_copy_bytes` sums measured copy operations across the client worker
and router process for the active cleartext path. A payload can be counted
again at a later layer, so this aggregate is copy traffic, not unique
application bytes. Builder input/growth and any transcode copies stay
separate. Each report includes a `known_own_transport_copy_bytes` lower bound
and a per-path breakdown even when the full transport total cannot be measured.
The evaluator accepts a numeric transport total only when
`coverage.transport_copy_bytes` is `complete_connectanum_owned_path` and
`coverage.unknown_boundaries` is empty. Missing or partial coverage fails the
campaign gate.

TLS rows keep `transport_copy_bytes` and `tls_copy_bytes` as `not_measured`
because the current Rustls counter measures accepted plaintext, not copies;
`tls_plaintext_accepted_bytes` is a throughput diagnostic. Mixed-serializer
router transcodes are also not measured. Snapshots use before/after deltas
around one benchmark command. Older native libraries without the optional
snapshot symbol leave affected fields unmeasured, so those rows cannot claim
complete coverage or establish FlatBuffers parity.

The client worker now snapshots optional native crypto staging counters separately
from its transport counters. Native XSalsa encryption constructs the existing
`nonce | tag | ciphertext` layout in one output allocation using detached crypto;
it avoids the earlier payload shift and second ciphertext output copy. Copied
decryption stages only the ciphertext body. AES retains its existing wire layout;
its copied decrypt stages the attached tag as part of the message, while eligible
consuming AES decryption reuses storage. Nonce/tag construction and cipher
computation are outside these bulk staging counters.

`known_e2ee_staging_copy_bytes` is a lower bound combining process-wide native
staging, the client worker isolate's explicit crypto FFI copies, native-provider
ciphertext coercion and portable-provider wrapper copies. The breakdown names
these scopes individually. Native-provider coercion counts completed CBOR byte-list
conversions and the exact prefix copied by typed FlatBuffers validation, including
a prefix copied before rejection. Existing `Uint8List` and bounded subviews are
reused and report zero coercion bytes. This isolate-local Dart counter is available
independently of the optional native staging ABI. Failed legacy CBOR conversions,
other isolate bridges/wrappers, crypto dependency internals, serializer and framing
transformations remain unmeasured. Encrypted
rows keep `e2ee_copy_bytes` as `not_measured`. The comparator requires that field, rejects
an encrypted row marked `not_applicable`, and accepts numeric totals only with
complete pipeline coverage and no unknown boundaries. ABI v1 requires both its
version and snapshot symbols; older or unknown versions produce unavailable
native measurements without reading an incompatible struct.

The portable AES provider writes ciphertext and tag directly into its final
nonce-prefixed buffer through PointyCastle `processBytes`/`doFinal`. It avoids the
former whole ciphertext/tag assembly copy and returns a view limited to the
bytes written. Both portable CBOR providers also avoid the former plaintext and
outbound ciphertext wrapper clones. These changes preserve the CBOR profile,
wire layouts, caller inputs and mutable outbound ciphertext behavior.

The portable counters collect only during the worker's workload window. They
measure the remaining XSalsa `EncryptedMessage`-to-`Uint8List` materialization and
plain-list ciphertext coercion, including the prefix already copied before an
invalid byte. XSalsa retains that wrapper copy to preserve mutable output; the
pinned pinenacl 0.6.0 `ByteList` backing storage is an unmodifiable view. Its
internal staging/return copies are not instrumented. PointyCastle 4.0.0 also
uses internal block buffers and copies computed block output; those copies
remain unmeasured. A zero portable-wrapper count therefore cannot certify a
zero-copy encryption pipeline. Missing portable snapshots stay unavailable,
and the aggregate total continues to fail the complete-coverage gate.

Typed XSalsa receive also avoids pinenacl's default 1 MiB
`EncryptedMessage.fromList` limit. The provider's existing 64 MiB ciphertext
preflight remains authoritative; it passes the nonce and an explicit-length
body wrapper to the same authenticated primitive. Tests exercise the old limit,
the next byte, 2 MiB spans, all truncated nonce/tag lengths and native/portable
interop in both directions. The legacy CBOR receive wrapper is unchanged.

An explicit peer serializer equal to the client serializer is homogeneous;
only a different peer codec retains the unmeasured transcode marker.
Live worker tests cover both classifications, including CBOR-to-JSON encryption.

The benchmark accepts explicit typed FlatBuffers E2EE RPC/pub-sub scenarios and
selects the matching Dart/native version-2 provider. Its omitted serializer still
defaults to the existing CBOR version-1 profile. All three construction modes can
exercise typed encryption; typed E2EE file transfer remains unsupported.

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
`native/bench/artifact_gate/wamp_flatbuffers_performance.json`. Scheduling and
execution are provided by `tool/run_wamp_serializer_campaign.py`. No complete
primary comparison result exists yet. The report must not be used
to claim parity until the complete primary matrix runs with no missing metrics.

The relative gate currently requires no point-estimate regression versus the
better binary baseline for CPU, allocations, GC pause and peak RSS as well as
throughput and latency. The declared resource budgets require point ratios at
most 1.0 and 95% confidence upper bounds at most 1.05, as encoded in the policy.
The policy has no separate absolute CPU/memory ceilings. Current Dart-managed
TLS/socket and mixed-codec transcode copy paths are unmeasured; those rows remain
blocked until instrumentation and the controlled comparison are complete.

## Executing a campaign

Build the release Rust `http_stream` driver and the matching native library, and
resolve Dart dependencies before execution. On a quiet Linux runner with a clean
checkout, use:

```sh
python3 tool/run_wamp_serializer_campaign.py \
  --output /tmp/connectanum-wamp-campaign \
  --driver native/bench/target/release/http_stream \
  --native-lib "$CONNECTANUM_NATIVE_LIB" \
  --runner-image '<exact runner image identifier>'
```

The output directory must be new. Defaults generate all 48 cases, three warmup
passes and seven measured passes, with 10-second windows and at least 1,000
observations per row. The minimum data-window time is four hours, before startup
and metric collection. Codec order varies deterministically in balanced blocks;
the three codecs for each case run consecutively. One driver and one source-mode
Dart worker remain alive across every pass. Source VM mode is required by the
allocation/GC collector; release driver/native builds precede execution and JIT
warmup uses the recorded warmup passes.

The executor records real workload timestamps, validates ordered attribution,
and retains flushed raw JSONL, per-pass reports, scenarios, dependency locks,
configuration, policy, logs and an atomically updated manifest. Reports include
the actual prepared codec, TLS, PPT and construction configuration. The evaluator
checks these settings against the declared case and requires all 48 distinct
primary matrix dimensions. Driver/native-library, source, lock, configuration,
policy and scenario hashes are checked again after execution. `--results-only`
avoids retaining and rewriting the driver's growing aggregate report history.

Known build/test/mutation processes visible through Linux `/proc` are rejected
before and during execution. A file lock prevents another executor in the same
filesystem context. These safeguards do not prove an exclusive physical host or
detect all workloads outside a container's process namespace. Primary evidence
still requires a controlled runner and inspection of recorded host state.
Cancellation, timeout and partial failure retain evidence and terminate the
driver's process group; completion requires successful exit, every planned row
and confirmed process teardown.

`--prepare-only` emits inputs without running benchmarks. `--diagnostic` permits
short windows, a dirty checkout and exact `--case` subsets. Diagnostics always
fail primary acceptance, even if numerical ratios look favorable. Missing metrics
and incomplete execution also fail; the checked-in performance policy is
unchanged. Both canonical verification scripts run the executor and comparator
regression suites.

The Linux arm64 diagnostic completes 120 real reports: four cases, all three
codecs, three warmup and seven measured passes. It covers Dart/RawSocket RPC
values, native/TLS RawSocket RPC pre-encoded spans, Dart/WebSocket pub-sub
pre-encoded spans, and native/TLS WebSocket pub-sub native buffers. Each codec
has 40 reports. All reports use one client PID and one server PID, input hashes
stay unchanged, and concatenated pass files exactly match the raw driver JSONL.
The driver exits 0 and process teardown completes. Its 200 ms/10-minimum-sample
windows deliberately fall below policy; the real comparison exits 1 with 370
findings, including diagnostic/dirty-source status, insufficient duration/sample
counts and missing transport/TLS/SDK copy evidence. No parity is accepted.
Evidence is retained under `/tmp/connectanum-flatbuffers-campaign-diagnostic-02`.
The first diagnostic is retained separately as `diagnostic-01`: interruption after
31 reports exposed the per-workload helper restart and motivated explicit reuse.

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
distributions. Missing metrics cannot pass. CPU/memory point-estimate
regressions fail the declared relative budgets; the 5% confidence-bound allowance
does not waive a regression.

Every repetition must validate payload and sequence identity, drain consumers and
prove final buffer release. Keep failed results, teardown evidence and complete
configuration. Hosted CI must publish exact-head comparisons and enforce the
same declared machine-readable policy. Shared-host noise, unexecuted construction
groups or missing ownership metrics must remain visible limitations.
