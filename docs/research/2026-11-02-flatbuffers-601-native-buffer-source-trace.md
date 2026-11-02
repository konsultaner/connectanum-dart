# Frozen601 native-buffer RPC source trace

This bounded source inspection follows the largest original primary RSS ratio,
`rpc_rawsocket_clear_dart_native_buffer` (1.0324864225694044). It establishes no
production defect or causal RSS explanation. Both strict campaigns remain
failed. No workload, measurement, test or acceptance gate was repeated.

All nine inspected files match frozen source
`601108ea6216464bd00ae29c16cfaf0a59c71db6`; its worktree remains clean. Exact
file hashes and the limits of this review are in the [source assessment](2026-11-02-flatbuffers-601-native-buffer-source-trace.json).

The selected successful path has explicit ownership transitions:

1. `BenchPayloadCodec.encodeNative` creates and fills a fresh native builder.
   `_NativeAllocator.freeze` removes the frozen owner from allocator cleanup;
   disposing the builder leaves that returned owner valid.
2. `_prepareTypedBenchPayload` obtains an independent `NativePptPayloadLease`,
   disposes the producer and retains the lease owner for the request.
3. The benchmark session adapter calls `Session.callSingleLazyPayloadView`.
   Both native and materialized final-result handlers remove the pending call.
4. `_runRpcIteration` verifies the body, then its `finally` releases received
   payload storage and the prepared request lease. Receive-storage release
   disposes its byte lease; this differs from the public request-buffer view
   contract, which preserves independently exported views after disposal.
5. The segmented sender disposes its control builder/prefix and temporary FFI
   handle array. Its ABI retains submitted frozen spans independently.
   Existing handle and message-byte finalizers already account `externalSize`.

Relevant symbols are in [the workload runner](../../packages/connectanum_bench/lib/src/wamp_workload_runner.dart),
[fixture codec](../../packages/connectanum_bench/lib/src/bench_payload/codec.dart),
[native buffers](../../packages/connectanum_client/lib/native_buffers.dart),
[message byte leases](../../packages/connectanum_client/lib/native_message_bytes.dart),
[session](../../packages/connectanum_client/lib/src/protocol/session.dart),
[sender](../../packages/connectanum_client/lib/src/transport/native/native_transports_io.dart),
[segment submission](../../packages/connectanum_client/lib/src/transport/native/native_owned_segments.dart)
and [receive runtime](../../packages/connectanum_client/lib/src/transport/native/runtime.dart).
Existing lease tests explicitly preserve exported derived views; they were
read, not rerun.

A bounded local Qwen review reached its output token limit and saved no final
assessment. Its failure log is retained locally; no model approval or finding
is claimed. The source observations above are the root agent's direct trace,
not a complete ownership audit or proof that runtime retention is absent.

Next inspect receive/control decoding and per-message metadata allocations
against the baseline paths. Preserve both roles, all repetitions and passing
controls from the [original RSS attribution](2026-11-02-flatbuffers-601-RSS-role-attribution.md).
A production edit still requires a falsifiable before-failing regression,
its own complete verification and controlled source comparison. Source code,
logical allocation counts and role peaks cannot establish a physical-memory
repair; no patch or new capture is ready.
