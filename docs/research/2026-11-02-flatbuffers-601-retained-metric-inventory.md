# Retained601 metric inventory and diagnostic-method limits

The retained structured client/server metrics provide aggregate heap, GC, CPU
and RSS evidence. They do not identify allocation classes or source stacks in
the inspected scope. This new read-only inventory preserves every canonical
stream, both roles, warmups, measured repetitions and passing controls. It
does not rerun a workload, recompute a gate or change either failed campaign.

| Original shard | Canonical streams | Raw report records | Client/server metric objects |
| --- | ---: | ---: | ---: |
| Primary | 10 | 1,440 | 2,880 |
| Protocol | 10 | 900 | 1,800 |
| Payload sizes | 10 | 360 | 720 |
| Encrypted/progressive | 10 | 240 | 480 |
| Total | 40 | 2,940 | 5,880 |

These are raw records including warmups, not 2,940 measured repetitions.
[Complete retained file inventory](2026-11-02-flatbuffers-601-retained-metric-inventory-files.json)
and [nested metric schemas, stream hashes and counts](2026-11-02-flatbuffers-601-retained-metric-inventory-schema.json)
remain available. All four shards have zero candidate class/stack field paths.
Name matching is heuristic; the complete field schemas and actual production
collector/estimator source were also inspected. Payload's additional fields
describe incomplete aggregate allocation evidence, not class attribution.

The production collector reads aggregate isolate GC heaps and GC timeline
events. Its allocation estimator combines heap changes and reclaimed-byte
observations, with the existing uncertainty checks. A GC-counter mismatch is
caught and reported as unmeasured. Neither production file requests allocation
profiles or allocation traces. No formula, precision policy or gate changes.
[Root readback and exact source hashes](2026-11-02-flatbuffers-601-retained-metric-inventory-root-assessment.json).

Ten synthetic method guards preceded raw-report access. The first utility
failed on manifest admission: warmup/measured entries are lists, not counts.
That failure occurred before opening any raw JSONL report. The corrected
utility admits exact entry paths and row counts, rejecting duplicates, missing
or extra streams. Original measurements were unchanged. Atomic exclusive
publication and its byte-identical staging file are retained. Advisory review
retractions and the accepted publication correction are qualified in the root
assessment; no model approval is claimed.

The scope excludes opaque strings, latency sample arrays, duplicate derived
driver/comparison files, logs, binaries and source archives. Their retained
filenames are inventoried separately. This is not a claim that undocumented
opaque content was exhaustively decoded. Aggregate telemetry does not establish
a source defect, an avoidable byte amount, a retained leak or an RSS cause.

## A proposed class-profile witness is unsuitable

Exact SDK3.13.5 source changes the diagnostic choice. The public class-profile
response assigns the same heap-walk counts and sizes to both current and
accumulated fields. Their differences cannot recover window allocation volume.
[Class-table implementation](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/class_table.cc).

Omitting GC/reset parameters avoids the service's explicit debugging-GC/reset
branches. The actual vm_service15.4.0 client omits false values; the inspected
server rejects other present values. This is a source inference, not an RPC
test. [Service implementation](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/service.cc).

Heap iteration still enters a GC safepoint, assists pending old-space work and
can finalize pending GC. Thus omission does not establish a GC-neutral observer.
No such RPC was invoked, and no perturbation magnitude was measured.
[Heap-iteration implementation](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/heap/heap.cc).

Heap walks count currently allocated objects; they do not by themselves prove
semantic reachability or retained leaks. Public class sizes use object heap
size; external handle accounting is separate. They are not process RSS.
[Object visitor](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/object_graph.cc).
[Exact hashes and qualified method review](2026-11-02-flatbuffers-601-retained-metric-inventory-sdk-method-assessment.json).

The class-profile method is rejected as a GC-neutral allocation-work witness.
Next inspect source-relevant stack attribution using already-enabled facilities
and original launch policies, failing closed if evidence is unavailable or
insufficient. No profiler/tracing enablement, forced GC, accumulator reset or
policy change is authorized by this analysis. No patch or new capture is ready.

Both strict campaigns remain failed. Runtime601 and the restored isolated
worktree remain clean and unadopted; PR132 remains draft on its original base.
