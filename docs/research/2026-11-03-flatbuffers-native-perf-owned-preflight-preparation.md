# Retained preflight phase calls; full admission remains closed

A new component retains an owner before a non-daemon worker starts. An optional
private constructor-entry hook registers the exact actual producer before its
lease check or file I/O. The existing synchronous fixture, canonical and
production factories keep their commands, environment deltas and output paths.

Observers receive immutable scalar snapshots. They do not inspect partially
initialized producer attributes, process handles or descriptors. Producer
construction, same-operation waits and a single emitter attempt run as
serialized worker calls outside the observer lock. A completed call does not
establish actor ownership completion, descendant exit, canonical success or
admission; the ownership-complete field stays unknown.

Attempts remain retained for the process lifetime. The registry refuses new
registrations at 64 while retaining every prior owner and its continuations;
this logical count is not a heap or RSS bound. Uncertain thread setup/start
stays quarantined. There is no discard, reset, cancel, retry or automatic GO.
The caller must retain the physical official exclusive lease throughout known
actor and worker lifetimes. This component does not provide that retention,
resolve every arbitrary partial actor or supply a live provider.

Eight initial errors reflect a missing new API, not eight production defects.
The first eleven selected tests yield ten passes and one fixture failure:
the fixture injected the pre-spawn command-start event under a post-spawn
label. No child existed at that event. The corrected fixture injects the
actual post-spawn event after the retained process and pending state.

One separately added guard then fails because the new owner calls a custom
exception representation during snapshot publication. Publication now stores
only the exception type and retains the exact exception privately. This is an
observed side effect and source blocking risk, not a measured hang or RAM cause.
Twelve selected tests pass at that epoch. Two further before guards fail for
registry capacity and thread-object setup; both are corrected.

The final epoch passes fourteen tests: eleven new component guards and three
required existing constructor/factory callers. This result is separate from
the prior canonical-output fourteen, Git78 and full canonical verification.
The guards include actual OWN finite threads and one retained Python child
with a post-spawn publication error, natural status zero and output EOF.
Lease callbacks, barriers, zero-capacity and thread faults are synthetic.
The root runner holds its official exclusive lease throughout known fixture
completion; worker-side physical lease retention is not established.

[Root assessment](2026-11-03-flatbuffers-native-perf-owned-preflight-assessment.json)
and [retained evidence](2026-11-03-flatbuffers-native-perf-owned-preflight-evidence.tar.gz)
retain all selected regular files in the new phase directory: actual source
epochs, executed coordinator text, regular fixtures, logs, advice and root
qualifications. Special nodes are metadata only. Existing fixture Git setup
returns are not all separately serialized.

A new concrete GLM design review completes and is qualified against actual
constructor boundaries; it does not establish the earlier claimed orphan
defect. The root chooses an entry hook rather than raw uninitialized-object
preallocation or a factory-plan refactor. Qwen test advice completes.
The Qwen selected-diff review completes before the last two small guard fixes;
root checks those final changes and the complete new component. Root rejects
resetting uncertain starts, eviction of retained owners and freezing a mutable
lease capability; it adopts refusal of new registrations at the fixed limit.
No model request, prior kernel proof or old numerical campaign is repeated.

Only the producer/test pair changes in this phase; the other eighteen tools
match its before epoch. All twenty remain uncommitted, uncanonical and
unadmitted. Production source601 and selected verification scripts remain
unchanged. No actual canonical/production recipe or live receipt, native build,
SDK/compiler/kernel/perf/broker control, benchmark, capture or strict campaign
runs. Available space is about8.7GB, below the unchanged12GiB build floor;
no cleanup occurs and space-change cause remains unmeasured.

Full independently owned orchestration, current own canonical/source archive,
production native/driver/RLIB, actual locks/hidden configs, SDK/compiler/tool/
kernel provenance, original-host credential/access/inheritance/arming/role/
timing/metadata/coverage controls and immutable complete admission remain
required. The live provider is absent, admission always refuses and the
controller remains closed. No RAM repair, source adoption or strict acceptance
is established. PR #132 stays open and draft; issue #103 and its milestone
stay open.
