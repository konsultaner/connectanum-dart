# Current acceptance and recurring TLS receive-window failure

Runtime: `984288cbc511f48b3dc48704384b6d8ad9276a1a`. This note records passing
components and remaining failures; it does not accept performance parity.

## Verified checkpoint

Frozen `bin/verify` passes in 1,387.78 seconds, including Chrome/Dart2Wasm, with
all 3,202 tracked source files/four resolved inputs unchanged and a clean tree.
Log SHA-256: `d83e3c1b9836b02c55cdb3674a70c4abac904aeb50cad0d12a78438e003a4e9e`.
A fresh `bin/test-fast` also passes with exactly the same source/resolution.

The [Dart component](https://github.com/konsultaner/connectanum-dart/actions/runs/39882157891)
passes independent source, resolved-content, private-package, byte-alias,
clock-window and allocation audits: 491 functional cases per variant, 160 rows,
32 fresh worker processes and 128 measured windows. RESULT/CALL median decode
ratios are 0.937818/0.917381; managed requests fall by about 456/812 bytes per
decode. Both variants resolve the same dependencies. This run uses web 1.1.2;
the preceding component used 1.1.1. Do not combine cross-run percentages or
attribute runner/dependency changes to the implementation.

The [native component](https://github.com/konsultaner/connectanum-dart/actions/runs/39882160685)
also passes independent source/lock/compiler/binary/raw audits: 24 reader rows,
ten unchanged encoder rows and 34 identical wires. Every cold/repeated request
is nonregressing. Common reads save 672–1,176 requested bytes/up to one allocation.
Allocator requests do not establish CPU, RSS or transport parity.

The [production copy/lifetime proof](https://github.com/konsultaner/connectanum-dart/actions/runs/39882163712)
passes 120 owned cases, 300 short observations/all 32 no-copy cases, 36 groups
and 108 post-GC observations. Public leases have zero native owners before forced
GC. Four resolved contents are recovered from hash-identical retained Dart
component files; the production library matches that component's retained
library, and the unchanged driver matches the retained preceding primary artifact.
These provenance checks do not claim the copy-proof artifact itself retains
binary contents. SDK/TLS/crypto internals remain unmeasured under the approved scope.

## Remaining acceptance

[Strict diagnostic 39882166630](https://github.com/konsultaner/connectanum-dart/actions/runs/39882166630)
has 90 valid rows, zero integrity findings and eight numerical costs. CPU and
allocation pass all three cases. Dart-value GC median is 1.03000 with confidence
upper bound 1.20665; Dart-value p95/p99/RSS/throughput also fail. Native-buffer RSS
point ratio is 1.00164. Pre-encoded p99 and RSS (1.01322) fail. All declared
point/confidence budgets remain unchanged.

Full primary 39882169066 and supplemental 39882172130 remain observing. The
current payload shard fails after 20 valid rows, before a complete pass, on
`ext_18_payload_sizes_flatbuffers` at the original 300000-ms deadline. The preceding
runtime55 payload shard fails after 139 valid rows at the same workload/deadline.
Both failures retain matching raw/per-pass rows, original configurations, sample/
duration floors, input/binary hashes, stable client/server PIDs and cleanup.
The worker-stopped warning follows explicit driver teardown; it does not prove
the worker stopped spontaneously.

## Excluded proposals

An ordinary-no-PPT single-byte-argument fragmentation proposal is excluded before
private preparation or observation: the failing primary `values` configuration
already uses `x_connectanum_bench_typed` and `ppt_serializer=flatbuffers`.
The passing baseline-fast result remains valid independently of that exclusion.

[Profile 39884174360](https://github.com/konsultaner/connectanum-dart/actions/runs/39884174360)
passes independent source, resolved-content, native-clock, sampling-window,
18-memory-snapshot and cleanup audits. Full typed byte verification is the
largest codec-specific client leaf (145/1,644 sampled ticks); the MessagePack
dynamic verifier has 56/1,270. These differently sampled, instrumented runs do
not establish a causal comparison or acceptance.

A private generated getter return-type/cast experiment preserves the public
reader, full verification algorithm, all bytes and read-only aliases. Both
variants pass 76 existing cases. All 160 rows/32 workers/128 managed allocation
windows pass independent input/variant/clock audits. Worker-pair timing is mixed
(64-KiB median ratio 0.99585; 10-KiB 0.98645), and managed allocation is essentially
unchanged. No stable meaningful improvement is established; no generated,
runtime, public API or validation change is adopted.

## Kernel lead and next observation

Earlier positive owned captures on runtime c0 show a 2,072-byte client receive
buffer, 3,072-byte peer window and continued approximately 14.8-KiB/s transfer.
Those captures predate namespace environment records. Traced original replay
39883379996 and untraced focused replay 39885378060 keep the original workload
limits. Tracing can perturb scheduling; successful replays do not fix the failure.

In upstream Linux v6.17, `tcp_prune_queue` tests queued memory plus incoming skb
size, while `tcp_clamp_window` can assign the receive buffer from queued memory
alone. A netdev author reported a related zero-buffer stall and proposed including
the incoming allocation; discussion also questions large incoming skbs. This is
a lead, not proof of the running Ubuntu Azure implementation or this failure.
Sources: [v6.17 TCP input](https://raw.githubusercontent.com/torvalds/linux/v6.17/net/ipv4/tcp_input.c),
[original proposed patch](https://lists.openwall.net/netdev/2025/07/18/159),
[maintainer discussion](https://lists.openwall.net/netdev/2025/07/21/82).

The preceding diagnostic records namespace socket totals but omits TCP prune,
collapse, zero-window and memory-pressure counters. The follow-up adds bounded, allowlisted
`/proc/PID/net/netstat` observations with explicit malformed/missing/permission/
size failures and no zero substitution. These are cumulative namespace totals,
possibly including other flows; they are never individual socket attribution or
causal proof. Kernel config/version alone cannot prove an applied code path.
No SDK, sysctl, fixed receive buffer, allocator policy, timeout or acceptance
change is justified by the present evidence.

Five new regression groups reproduce the gap before repair (two failing
assertions/three missing-record errors). After repair, 30 owned Linux/service/TCP,
28 capture, eight discovery-smoke and 20 CI execution contracts pass. The tests
cover target namespace selection, exact uint64/zero values, explicit absence,
unknown-field omission, paired grammar, Unicode rejection, the inclusive 64-KiB
limit, and missing/permission failures. Advisory review has no confirmed defect;
ASCII guards and intentional safe failure behavior are checked directly rather
than relying on model statements. Full resulting-source verification and real
Linux validation remain required.
