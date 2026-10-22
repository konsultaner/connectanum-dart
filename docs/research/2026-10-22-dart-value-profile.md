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
