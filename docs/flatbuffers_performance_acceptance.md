# FlatBuffers performance acceptance contract

Status: proposed contract for milestone issue #103. The benchmark runner policy
and complete instrumentation are still unfinished. No parity result is accepted.

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
