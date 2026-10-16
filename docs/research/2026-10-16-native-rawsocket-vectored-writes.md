# Native RawSocket scatter/gather writes

Issue: [#103](https://github.com/konsultaner/connectanum-dart/issues/103).

## Reproduction and scope

Source `ef9895e9` passes frozen full `bin/verify` and the renewed 120-case
copy/encoded-volume matrix with all 3,108 inputs unchanged. Its hosted Fast
Checks pass. The preceding `1b751b72` native artifacts pass all five platforms:
170 independently audited production consumer cases with zero skips.

The Linux `f2dc00f0` diagnostic still fails CPU and native-buffer allocation
parity. Source inspection finds a concrete I/O cost: the RawSocket writer calls
`write_all` separately for the header and every prefix/suffix segment, even
though the plain transport implements vectored writes. FlatBuffers can retain
more segments than a compact contiguous encoding. This is a hypothesis about
the measured cost, not proof of its contribution to the Linux regression.

A fail-first test around the actual `spawn_connection_writer` first verifies
independent expected wire bytes, then fails with three scalar writes and zero
vectored writes where one vectored call is expected. These are AsyncWrite call
counts, not a claim about measured OS syscall counts. Raw failure logs and
source/log hashes remain retained.

## Change and ownership

On a vectored writer, the header and existing Bytes spans are submitted through
bounded batches of at most 16 stack IoSlice descriptors. Partial writes advance
those descriptors; interruptions yield cooperatively before retrying, and zero
writes fail. No header/payload coalescing buffer or byte copy is introduced.
The scalar fallback keeps its previous write_all behavior, including error
propagation. The change applies equally to all serializers. WebSocket framing,
message schemas and encoding bytes are unchanged.

The helper consumes the original Vec of owners. They remain alive through
outstanding writes and drop before subsequent file/suffix/flush processing.
Earlier prefix segments may remain owned until the prefix finishes; no early
per-segment release is promised. File placement and flush/WriteReceipt ordering
stay unchanged. Written still requires a complete frame and successful flush;
failed or cancelled completion is Abandoned, not peer delivery. Retried I/O
interruptions keep the ordinary completion/flush requirements.

Scatter/gather descriptors are scalar bookkeeping, not payload copies. Existing
owned-copy and accepted-message-volume counters keep their scope and ABI.
Kernel, SDK, TLS and crypto dependency internals remain explicitly outside the
approved owned-copy scope.

## Validation

The actual-writer regression now passes for both header widths, retaining the
original subview addresses with one vectored call and no scalar writes. All 54
RawSocket cases and seven write-completion cases pass. The full native library
suites pass 383 ct_core and 311 ct_ffi tests with ffi-test enabled.

Regressions cover partial/Pending/Interrupted writes, exact original pointers,
empty input, more than 1,024 spans with bounded batches, scalar fallback, zero
and failed writes, cooperative cancellation with exactly-once owner release,
and owner/receipt boundaries through pending flush. Existing file, deferred
preparation, suffix, TLS and backpressure tests remain active.

All 445 focused Dart native transport/frame/file/segment/restart checks pass.
Current-source full verification, renewed live ownership
proof, five-platform consumers and Linux comparisons remain required. No parity
budget, case, duration, sample minimum, repetition or coverage/mutation floor
is changed. No issue, milestone or release is closed by this component change.

## Verified checkpoint and remaining regression

Source `8be8d5c0` passes frozen full `bin/verify`, including both browser
compilers, with HEAD and all 3,109 inputs unchanged. An earlier overlapping
control probe coincided with fake CLI startup deadline failures; the isolated
10-case CLI rerun and subsequent complete quiet verification pass with no
deadline changes. The earlier failed log is retained.

All 120 renewed live copy/encoded-volume cases reconcile independently, including
96 encrypted and 48 native-crypto cases. Five production platforms pass 170
audited consumer tests, with no skips. The native workflow is a dry run.

[Linux run 38872392453](https://github.com/konsultaner/connectanum-dart/actions/runs/38872392453)
completes 90 rows with 180 valid allocation observations and valid RSS, sample
and duration boundaries. CPU ratios are 1.05537, 1.08584 and 1.07985 for values,
native buffers and pre-encoded spans respectively. Native-buffer allocation is
1.05014. Additional throughput, latency, GC and RSS gates fail. The preceding
run has higher CPU ratios, but separate hosted runs do not by themselves prove
the causal contribution of scatter/gather. Only the writer call-count and
ownership changes are directly reproduced. Primary parity remains unproven.
