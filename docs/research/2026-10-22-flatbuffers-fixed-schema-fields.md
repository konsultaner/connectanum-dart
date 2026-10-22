# Contiguous native FlatBuffers schema fields

Runtime checkpoint: `08efcd5b554c8eb3190084d1932ac2e02ccc23ae`.

The checked native reader built a BTreeMap for every root and message table,
including absent/default fields. Schema field names and counts are pinned.
`Fields` now stores sorted `(static name, Value)` pairs in one vector, reserving
known table sizes. Binary lookup, duplicate replacement, extension, mutable
lookup and removal preserve the previous map behavior. Application dictionaries
retain their existing maps. Validation budgets, schema, ABI and shared Bytes/Arc
ownership are unchanged.

The schema-wide regression compares forward/reverse insertion, replacement,
extension, mutation, removal and ordering against BTreeMap. A separate regression
checks duplicate keys and shared nested table/byte aliases. Segmented composition
continues to mutate owned field trees through `Arc::make_mut`.

## Component evidence

The [Linux component run](https://github.com/konsultaner/connectanum-dart/actions/runs/39823418784)
passes all 39 focused native tests. Independent audit verifies 3,183 committed
source hashes, the resolved Cargo lock, Rust 1.99.0, executable hashes and the
unchanged allocation probes. The earlier `36a6df24` component has the same
compiler/lock/probes; only the three native schema-field storage users differ.
All 24 reader wires and ten encoder wires are identical.

Across 24 reader fixtures (cold plus ten steady observations each), requested
allocator bytes decrease by 552–1,368 and request count by 1–3. For example,
RESULT changes from 2,704 bytes/six requests to 1,816/five; CALL from 2,752/eight
to 2,200/seven; PUBLISH from 3,393/nine to 2,657/seven. The ten encoder fixtures
request 720 fewer bytes each, with unchanged steady allocation counts. Empty,
one-KiB and one-MiB payloads retain their existing byte-span alias checks.

These are native allocator requests, not Dart allocations, live heap, RSS,
whole-workload timing or performance acceptance. Archive SHA-256:
`312935b09409fbd4d3038a7b71922713c6f2466e0d0eb6bd83ef4eb081962bb7`.

## Verification and remaining work

Frozen local `bin/verify` passes in 24m19s, including browsers; all 3,183 sources
and four resolved inputs remain unchanged. Verification-log SHA-256:
`20fc8a86852595a556049773972910e54f357d5ab195dd78c2819657d7ab8901`.
The [production copy proof](https://github.com/konsultaner/connectanum-dart/actions/runs/39823839721)
passes independent audit of four phases, 36 snapshot groups/108 post-GC
observations, 120 owned cases and 300 short rows, including all 32 no-copy
observations. It does not accept timing.

The [strict diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/39823834690)
completes 90 rows with zero integrity gaps and six numerical failures: Dart-value
throughput/CPU/GC, and RSS in all three construction modes. Allocation and
p95/p99 pass in every mode. Other runners' absolute metrics are not pooled.
The separate older primary campaign completes 1,440 rows with 187 numerical
failures and no integrity gaps. Full current-runtime acceptance remains pending.

## TLS stall evidence

The original-process replay reproduces the one-MiB Dart/TLS/WebSocket stall at
257/360 rows. Three owned socket captures show server transmit queues of
497,155/953,806/363,982 bytes and timer code 04, while client kernel receive
queues are zero. The [kernel's proc TCP documentation](https://docs.kernel.org/networking/proc_net_tcp.html)
identifies timer code 4 as a pending zero-window probe. This narrows the observed
condition; it does not identify the application or SDK cause. The local SDK's
HTTP client already sets TCP_NODELAY. A Nagle workaround is not justified by
these observations.

More detailed owned-connection observations could use the documented TCP/window
and socket-memory fields of [ss](https://man7.org/linux/man-pages/man8/ss.8.html),
with bounded collection and verified endpoint/inode identity. That additional
collector and any transport-framing experiment remain unimplemented. A reduced
90-row replay passes but cannot accept the full schedule or prove a causal fix.

## Campaign scheduling follow-up

Primary and supplemental job concurrency groups are now qualified by source
revision. Each paired process set remains on its job's hosted VM; other revisions
can finish independently. The declared workloads, process counts, floors,
budgets, deadlines and comparisons are unchanged, and running observations are
never cancelled. Absolute costs from different runners remain separate.

[GitHub's concurrency contract](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
permits `github` context in job-group expressions and describes same-group
pending replacement and `cancel-in-progress` behavior. The workflow keeps
`cancel-in-progress: false`. [Standard hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)
use fresh VMs; these jobs retain their existing `ubuntu-24.04` selection.
All 14 existing CI-execution contracts pass after the scheduling change.
