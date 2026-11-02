# CPU observation method and draft native perf diagnostic

Subsequent [guard-only preparation and retained counterexamples](2026-11-03-flatbuffers-native-perf-guard-preparation.md)
now supersede this note's original no-implementation stage. The controller and
kernel capability proof remain incomplete; there is still no capture readiness.

The proposed terminal JIT CPU-profile RPC is rejected under the current GC
constraint. No target RPC, workload or capture ran. The next method is a draft
external native-function diagnostic; no helper implementation or guard test
has run, and capture readiness is false. Runtime601 remains unchanged.

## Why a terminal service read is insufficient

The frozen observed workload uses `dart run`. Exact SDK3.13.5 source routes
`getCpuSamples` through common profile construction, which creates a processed
sample buffer and code lookup table. Its JIT branch enters heap iteration.
The `_code` option affects serialization after construction, so false does not
avoid this path. The inspected Perfetto route shares profile construction.
[Profiler service](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/profiler_service.cc),
[code lookup and processed buffer](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/profiler.cc).

Heap iteration can assist and finalize already-pending old-space GC. Reading
after every work/metric window does not establish that this conditional path
is unreachable. This is source reachability, not an observed collection or
measured observer overhead. Switching the original JIT workload to AOT is not
a valid workaround. [Heap iteration](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/vm/heap/heap.cc).

The frozen launcher already uses `--observe` when collecting VM metrics; the
SDK option enables the profiler. This establishes source provenance, not an
actual target capability probe. No flag was changed or service queried.
[Observe option](https://github.com/dart-lang/sdk/blob/3.13.5/runtime/bin/main_options.cc).
[Exact source hashes and qualified root decision](2026-11-02-flatbuffers-601-CPU-method-assessment.json).

The existing `profile_wamp_serializers.py` is unsuitable for unchanged reuse:
it sets the profiler flag, clears CPU samples, reads CPU profiles and adds
JIT-symbol launch flags for native perf. Its optional memory mode also requests
allocation profiles and a post-workload GC. Turning memory mode off does not
create the required native-only path. The frozen tool and old captures remain
untouched. Keep the actual WAMP workload/control request; separating observers
does not mean bypassing the workload.

## Draft scope and before-data requirements

The proposed question is narrower: can external OS instruction-pointer samples
identify native CPU functions worth investigating? It cannot identify Dart
allocation classes, full managed stacks, exact allocation volume or an RSS
cause. The own retained production0B23 ELF has symbol/text tables and native
FlatBuffers/FFI symbols. This is a static capability lead, not a measured hot
function or proof of a future loaded image.
[Static symbol inspection and limits](2026-11-02-flatbuffers-601-native-symbol-availability.json).

The draft includes all six construction/implementation variants of the
previously inspected cleartext RawSocket RPC family and all five original
primary RSS passing controls. Each retains all three serializers, three warmups
and seven repetitions: a proposed330raw reports. The exact case IDs and the
selection source are retained in the [draft plan](2026-11-02-flatbuffers-601-native-perf-draft-plan.json).
Selection used already-existing original results. A later declaration would
predate only new diagnostic data; it would not predate those original results.
All original48/50campaign cases, rows and failures remain preserved separately.

The proposed controller records flat native instruction-pointer samples over
an owned execution tree with Linux perf, without a VM profiler/heap RPC, sample
reset, symbol-generation flag, frame-pointer build change or runtime edit.
Original fresh bodies/patterns, full verification, duration/sample policies,
workers, SDK, GC and allocator remain required. This is a new diagnostic design,
not a rerun or replacement of either strict campaign.

Before any application work, an owned wrapper would remain blocked before
exec of the exact frozen driver. Dedicated sampler control/acknowledgement FDs,
actual sampler identity and a one-shot barrier must establish arming order.
The wrapper must close sampler control/ack FDs before announcing its blocked
state, so target stdout or inherited descriptors cannot spoof readiness. These
are proposed requirements, not implemented guarantees.

Pending preparation must establish:

- Exact driver argv/env, scenario inventory/order, fresh-body and window policies;
  own source/archive/native/driver/actual lock/generated-config/static-RLIB
  provenance and appropriate verification. Keep local and hosted cohorts distinct.
- Meaningful synthetic refusal/ordering/identity/output-preservation tests,
  followed by a bounded real kernel perf capability control over owned synthetic
  processes before benchmark data. Mocks alone cannot establish inheritance.
- Actual process instances, lineage, exec identity and loaded native image;
  both roles must match their reports. Preserve every unknown, unmatched,
  unresolved, lost and partial record. Static symbols cannot replace this proof.
- A bounded disk/resource plan, official leases and hosted concurrency rules,
  qualified review, immutable declaration and a consumed marker before data.
  Refusals and failures remain; no automatic retry, fallback flags or host selection.

Samples cover whole execution, including startup, warmups, observers and
cleanup. They are not gate-interior CPU ratios or per-operation costs. No
trimmed subset, native-function count or new instrumented timing can establish
RAM repair or strict parity. Original strict failures remain authoritative.

Qwen's test advice is qualified in the [root draft assessment](2026-11-02-flatbuffers-601-native-perf-draft-assessment.json):
its commands are hypothetical; use synthetic PID metadata and injected I/O
faults rather than forcing PID recycling or filling the real disk. No advice
constitutes approval. The next step is isolated helper/guard preparation after
binding exact source policies. No new capture or production fix is ready.
