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

## Resulting-source verification and positive replays

Frozen `bin/verify` on diagnostic head `f2dbdfa4` passes in 1,356.37 seconds,
including Chrome/Dart2Wasm, with 3,203 source/four resolved hashes fixed and a
clean tree. Log SHA-256:
`684ffdab9c61c2f10a93c7d35e5b4923ca561b2d823a64c44a606b466606b753`.
Full CI 39888953092 is running; preceding runtime55 CI passes all 38 jobs.

[Untraced focused run 39885378060](https://github.com/konsultaner/connectanum-dart/actions/runs/39885378060)
fails at 72/90 rows on ext18 FlatBuffers, preserving original processes/order/
floors/deadline and cleanup. Independent audit verifies all 3,202 sources/four
resolved contents and matching production binaries. All three snapshots qualify;
six socket records match owned inodes/tuples. The client receive buffer stays at
1,138 bytes and peer send window at 2,048. Received bytes grow by approximately
9,873/9,850 bytes per second across consecutive captures. Memory PSI is zero
and about 13 GB is available during capture; this does not rule out an earlier
transient event. The warning about a stopped worker follows driver teardown.

[Counter-enabled run 39886982363](https://github.com/konsultaner/connectanum-dart/actions/runs/39886982363)
fails at four/90 rows on the same ext18 workload. All 3,203 sources/four resolved
contents, production binaries, original limits and cleanup pass independent
audit. Three snapshots qualify, with six owned socket records and no partial or
changing-progress captures. Receive buffer is 30,603 bytes, peer window 30,720;
the sender is 99.9–100% receive-window limited while bytes continue to advance.
All 15 allowlisted counters are present as uint64 values. Namespace totals show
PruneCalled=7, RcvPruned=4, TCPRcvCollapsed=24 and zero memory-pressure events;
the prune/collapse totals stay constant during these late captures. They cannot
identify the socket responsible or establish when its buffer changed.

## Matching distribution source

The captured kernel identifies itself as `6.17.0-1022-azure`, build `#22-Ubuntu`
from 2026-07-27. The official `linux-azure-6.17` source version is
`6.17.0-1022.22`; its published tag
`Ubuntu-azure-6.17-6.17.0-1022.22` peels to
`b0db0e77d0d6d28cda0d262a66e079dc0a90143f` in the Vcs-Git named by the
[source descriptor](https://security.ubuntu.com/ubuntu/pool/main/l/linux-azure-6.17/linux-azure-6.17_6.17.0-1022.22.dsc).
The official archive/diff match the descriptor's SHA-256 values:

- Original archive: `a5623ec5af79da8807e1467e43a1888461c7a445fb1e17533fe45f0fdf4394e3`.
- Distribution diff: `cb0154101fc7e337228a00c1caae7760b88afcb033f75c01756b3669dd376c54`.
- Selected patched TCP input file: `d6f37f7335f624283cd4c66c88851ca430fd14cbfe97afbb90535808a0b54550`.

Only the normalized TCP input file's 1,558-byte patch is applied, with exit zero
and no fuzz. Earlier multi-file-selection and function-extraction helper failures
remain rejected; all tracked repository files still match verification afterward.
The matching distribution uses queued allocation plus incoming `skb->len` for
`tcp_can_ingest`, rather than upstream's incoming `truesize`. Its clamp can still
assign the receive buffer from queued allocation alone. This makes the upstream
lead more specific, but neither descriptor PGP signatures nor running kernel
machine code are independently verified, and source inspection does not identify
the code path executed by this connection.

The next private experiment bounds large unmasked WebSocket write batches while
borrowing original payload slices. It must retain exact WS bytes/opcode/FIN and
existing small/control paths. Flush/yield cadence is a candidate scheduling
change, not a proven kernel fix. Partial-frame errors/cancellation must discard
the connection and release owners; reusing a partial stream is not an acceptable
test expectation. Native conformance and actual Linux replay evidence are required
before adoption, followed by all unchanged primary/supplemental gates.

## Private bounded-write candidate

The private candidate writes unmasked payloads of at least 128 KiB in borrowed
32 KiB batches, flushing each batch and yielding between them. It preserves one
WS header/frame, opcode/FIN, small/control paths and the masked sibling. All 14
writer checks pass; the baseline passes ten and fails exactly four new bounded/
yield/flush checks. Full native conformance passes 402 unit and three integration
tests. Independent audit verifies 6,408 private inputs, identical test fixtures,
actual-core variant markers and separate executable hashes. Original tracked
sources and four resolved inputs remain unchanged during these observations.

The flush-failure check proves that queued/following/close frames are discarded
and owners are released. A blocked write retains its owner until the whole writer
task is discarded. Advisory advice to reuse a partial-frame stream is rejected.
An initial review flush-count warning is also rejected after the model corrects
itself and tests confirm unconditional flushing of all five chunks. Mutable
writer ownership spans all awaits; frame writes cannot interleave through this
function. Exact vendored TokioRustls flush drains ciphertext into the socket,
without guaranteeing peer acknowledgment or receive-window recovery.

The [Linux focused replay](https://github.com/konsultaner/connectanum-dart/actions/runs/39892063835)
runs on separate experiment commit `2be50a0b78545033f2a9da300a7d597f11994ad2`,
containing only this native writer change and its tests. Its original 90-row
schedule, floors and deadlines remain unchanged. Production runtime `984288cb`
is unchanged. Extra flush/yield costs and actual Linux improvement remain
unmeasured; private functional success does not establish performance parity.

The completed replay fails after three valid rows at
`ext_18_payload_sizes_cbor`, under the original 300000-ms deadline. Independent
audit verifies all 3,203 sources/four resolved contents, retained production
input binary hashes, unchanged driver, original schedule/floors and cleanup.
Its modified native library differs from the control as expected. Three captures
qualify, with six owned socket records and no partial/changing-progress capture.
Worker receive buffer is 35,812 bytes, peer window 35,840, with continuing transfer.
The namespace records six prune calls/two receive prunes/25 collapses and zero TCP
memory-pressure events; these are still not per-socket attribution. Archive SHA
is `f5dac5c1dcfd99e4aaece36ebc465b0fe6eda9fa6c5eb93b6f1489fe7ca68207`;
raw SHA is `93b5d2b3c9ce53ccebb85fb3871263aa9a3d38f5773ba5cb4c6677f51b7a8117`.
The candidate is excluded and never adopted. This demonstrates that bounded
write/flush/yield batches are insufficient and that the recurring failure also
affects CBOR; it does not establish that the candidate caused a new regression.
