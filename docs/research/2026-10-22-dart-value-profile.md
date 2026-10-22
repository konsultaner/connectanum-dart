# Dart-value FlatBuffers profile

The renewed strict diagnostic on runtime checkpoint `2de4ec32` retains six
Dart-value failures: throughput, p95/p99, CPU, GC and RSS. All three construction
modes pass allocation gates; the two native modes retain RSS failures. No gate
is relaxed by this follow-up.

[Hosted profile 39803478045](https://github.com/konsultaner/connectanum-dart/actions/runs/39803478045)
passes on diagnostic-only head `f0875fef`. Independent audit verifies all 3,178
tracked source hashes and three retained resolved inputs, unchanged inputs and
native library, clean shutdown, sampling inside actual data windows, requested
configuration and all 18 heap/process-memory snapshots. The actual target is
`rpc_rawsocket_clear_dart_values`, with 65,536 payload bytes and equivalent
application work across all three codecs. Resolved Dart/native locks and package
configuration match the successful production copy proof. The native binary
differs because this diagnostic builds with `-C force-frame-pointers=yes -C
debuginfo=1`; it is not the production acceptance executable.

The 30-second profiled windows retain 14,454 MessagePack, 14,482 FlatBuffers and
13,292 CBOR observations. These are instrumented, ordered diagnostic windows,
not the repeated primary comparison. They cannot establish parity or replace
the strict diagnostic failures.

The FlatBuffers client has 5,922 VM samples. Only 11 exclusive ticks resolve
directly to FlatBuffers serializer files; socket/async frames dominate the VM
sample inventory. VM samples can include native/blocking stacks and are not
CPU-cycle attribution. Native perf is retained separately, with partial JIT
symbol resolution. This profile does not establish the reader's maps or native
builder guards as the next bottleneck; no speculative change is adopted.

FlatBuffers client managed heap usage falls from about 50.1 MiB after the
workload to 27.8 MiB after a GC request; router isolate-group heap usage falls
from about 88.9 to 46.0 MiB. Shared isolate-group snapshots are counted once.
RSS remains substantially above managed live heap. These snapshots do not
demonstrate an owned-buffer leak, explain RSS causally, or prove that a GC
request collected every object/finalizer. No collection or allocator trimming
is added to accepted workloads. The original-process TLS/WebSocket stall
diagnostic and full unchanged performance campaigns continue separately.

Evidence is retained under `out/flatbuffers-resume-20261022/`: artifact
`12437865171`, archive SHA256
`344b03ae61523595bfe829b6e22b2159c8f04ffb3e31b429cb43e4e81e1f231c`,
`dart-value-profile-f087-independent-audit.json`, and
`dart-value-cpu-selected.json`. This is diagnosis only; issue #103 remains open.

## Smaller-payload follow-up

The current runtime's full payload shard completes 360 rows with zero integrity
gaps and 60 no-copy observations, retaining 36 numerical costs. Its smallest
case, `ext_08_payload_sizes`, uses symmetric **10-KiB** typed payloads, ordinary
Dart values and clear RawSocket. FlatBuffers throughput ratio is about 0.8066,
CPU ratio 1.0840 and allocation ratio 1.0251 against the better codec. This is a
stronger case-specific regression than the 64-KiB diagnostic's near-parity
throughput; it warrants its own profile before adopting a reader optimization.

The profiling tool now accepts that canonical case and derives its byte count
from the checked-in extension inventory. Warmup and instrumented requests use
the same selected size. Existing defaults remain 64 KiB. New selection contracts
and the hosted 10-KiB profile are pending; no primary/supplemental case, policy or
benchmark workload changes. Payload artifact `12438197547` has archive SHA256
`764867d44aa8f25a1f8a83e109010b2054b61e402c09e9c2ec794b242ea367ae`;
the independently recomputed report is `payload-2de4-independent-audit.json`.

The first 10-KiB profile on `17f27d25` completes and independently verifies all
3,181 tracked sources/three resolved inputs, actual byte count, 18 snapshots,
sampling windows and cleanup. It retains 14,556 MessagePack, 14,560 FlatBuffers
and 14,558 CBOR observations in its three instrumented 30-second windows. This
does not reproduce the accepted shard's timing comparison. Its archive is
`ten-kib-profile-17f.zip`, SHA256
`cd95ec55179070743a01a778bb7adcf4ecba0813ccd61fac5d77e4b65a5cedae`,
with `ten-kib-profile-17f-independent-audit.json` and CPU selections retained.

## Native thread configuration correction

The acceptance driver explicitly passes one native runtime thread through
`CONNECTANUM_NATIVE_RUNTIME_THREADS` (`native/bench/src/bin/http_stream.rs`,
`configure_bench_child_environment`). The profiler previously inherited ambient
environment/default selection instead and did not record it. Previous actual
counts are unrecorded, not assumed to be any particular automatic value.

[Fail-first run 39811409005](https://github.com/konsultaner/connectanum-dart/actions/runs/39811409005)
on `5b9f63c7` sets the parent environment to nine and demonstrates that all 32
profile selection/mode combinations pass nine to the child instead of required
one. Thirteen unit tests run with 32 subcase failures; no SDK setup or workload
executes. The subsequent upload has no artifact directory, an expected cascade
rather than a benchmark observation. `profile-thread-pin-before.log` retains
the actual failure.

The repair explicitly sets one in the child environment and records that
setting in `source-audit.json`. The parent environment is untouched. Repaired
contracts pass all 13 tests in [run 39811772943](https://github.com/konsultaner/connectanum-dart/actions/runs/39811772943).
Its real profile passes independent audit of 3,181 tracked sources/three
resolved inputs, the one-thread setting, 18 snapshots, actual 10-KiB requests,
sampling windows and cleanup. It retains 14,467 MessagePack, 14,596 FlatBuffers
and 14,502 CBOR operations in three instrumented windows. These observations
do not establish a causal hotspot or replace the failing repeated comparisons.
The archive `ten-kib-profile-80b.zip` (artifact `12441070760`) has SHA256
`9a817155014eaf9ace7bc2504bc3b6333531f44e7f19845950eeeb5f822f1051`;
the independent audit and `ten-kib-pinned-cpu-selected.json` are retained.
Production benchmarks and every acceptance budget stay unchanged. Earlier
profiles remain diagnostic evidence, not comparable one-thread primary measurements.

## Native progressive E2EE follow-up

The complete `36a6df24` encrypted/progressive shard independently verifies all
240 rows with zero integrity findings, all E2EE/transcode/native-crypto copy
reconciliations and the same production binaries as the copy proof. It retains
47 numerical costs. Native cases have roughly 6–7% higher CPU and 4% higher
managed allocation than the better codec. These are separate runner observations,
not causal before/after estimates. Resulting `2de4ec32` renewal continues.

Profiling now accepts exact `ext_44_encrypted_progressive_results`: native value
construction, progressive RPC, clear RawSocket, 10-KiB data, fixed CBOR peer/PPT
serializer, `wamp` scheme, XSalsa20-Poly1305 and the synthetic benchmark key ID.
The mode and PPT fields override the ordinary profiler defaults in both warmup
and instrumented requests, with the explicit one-thread setting retained. The
same selection/mode matrix checks all request/audit fields; hosted validation
and actual capture remain pending. Accepted workloads and budgets do not change.

Encrypted artifact `12441082513`, archive `encrypted-36a6.zip`, SHA256
`9f47afe40b4f38ecf0a7fe8e03f3871281f20869762ddcf11d27fab50330aceb`,
and `encrypted-36a6-independent-audit.json` retain the original costs and proof.
