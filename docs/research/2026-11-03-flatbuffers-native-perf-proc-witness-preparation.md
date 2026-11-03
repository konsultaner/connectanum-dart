# Procfs witness preparation for external native perf

The new read-only sampler witness collector passes **35 labelled synthetic
procfs/owned POSIX pipe fixtures**. It traverses a bounded owned launcher tree,
checks process instances, image bytes, credentials, argv and private pipe
endpoints, and retains malformed/partial observations. No live Linux procfs,
privileged image, actual perf, FD exec, VM API, native benchmark or capture ran.
The trusted privileged auditor transport and real attach controller are still
missing; these tests do not establish capture readiness or a production defect.

The owned branch `codex/flatbuffers-native-perf-guard` remains at HEAD601 with
six uncommitted Python tools. Production package/native sources are unchanged.
The earlier28 guard primitives and26 blocked-exec callback fixtures remain
retained without unchanged reruns. Full canonical verification of the new tools
has not started. Both original strict campaigns remain failed and unadopted.

[Root assessment and exact hashes](2026-11-03-flatbuffers-native-perf-proc-witness-assessment.json)
and [all source versions, raw logs, receipts and advisory evidence](2026-11-03-flatbuffers-native-perf-proc-witness-evidence.tar.gz)
retain this phase. All31 archive members decompress byte-for-byte, including
original failure traces. Public references identify archive members.

## What was tested and corrected

The first33 fixtures produced four assertion failures and eight errors. The
fixture initially used pathname stat through Darwin `/dev/fd` rather than the
creator's actual pipe FD metadata. Its explicit synthetic adapter now uses
`fstat` only on declared owned pipe FDs. Live Linux procfs checks were not
relaxed; synthetic fdinfo/credentials remain synthetic.

Three separate positive counterexamples also established overly strict refusals:
log growth/timestamps, advancing log position with unchanged descriptor flags,
and a valid empty noninitial exec argument. Descriptor identity now binds
its device/inode/type/flags rather than log size or position; raw metadata is
still retained. Valid argv semantics are preserved. The corrected33 passed.

Source review then led to two new actual before-failing counterexamples:

- An earlier descriptor could change while later descriptors were inspected,
  with its numeric FD set unchanged. A second bounded sweep of every endpoint
  now detects that observable change. This remains sequential observation,
  without atomicity or immunity to privileged ABA changes.
- A refused invalid image retained its original prefix/metadata but lacked an
  explicit error field. Refusal class/reason are now recorded. The model's
  short-read allegation was incorrect: the loop already accumulated every
  nonempty chunk and checked final size. No truncated-digest acceptance is claimed.

Those two tests produced one failure and one error before correction. All35
fixtures pass afterward. Further controls cover image changes at unchanged
start time, octal flags, PID/start/parent drift, task-level children, duplicate
or cyclic lineage, candidate ambiguity, extra private endpoints, access denial,
malformed/oversized inputs, unknown FD types and resource limits.

Each test execution held the official exclusive lease. The first proposed
launch was refused before any snapshot/log/test and waited for availability.
No reservation was bypassed, no numerical data reran, and no cleanup occurred.
Observed free space at the final suite was19.48GB, above the12GiB full-build
preparation floor; small fixtures use their separate1GiB floor.

## Witness scope and qualified review

Live source mode requires a privileged Linux procfs reader. Fixtures carry an
explicit synthetic evidence class. The collector reads only the declared owned
anchor tree and task children, not global PIDs or process environments. Actual
image bytes are read through an opened procfs executable FD and checked against
before/after identity. Read/size/lineage failures retain bounded raw evidence
and refuse; inaccessible root processes are never silently skipped.

Exactly one expected-image sampler must have the exact declared argv/effective
credentials and control-read FD0/ACK-write FD1. It may equal the sudo anchor
after exec or be its descendant; sudo's PID is never assumed to identify perf.
Other endpoints for these channels in the observed launcher tree refuse,
including a monitor retaining them. Unknown descriptors remain in the evidence.
The observed tree is not a global FD-owner census or an authenticated atomic
kernel snapshot. The wrapper is independently checked for sampler endpoints.

GLM test advice and source review completed. Its long-log debug attempt reached
a token limit without a completed assessment; that failure is retained and
is not backend unavailability or approval. Root verified all executed logs
and source hashes. The review's unbounded-queue/refuse-before-observation claim
is rejected: process/child/depth caps bound traversal, and partial observations
are intentionally preserved. Its suggested33-node chain would hit the depth
limit first. The review only saw a fixture excerpt; it cannot approve complete
test coverage. A compromised procfs mount or privileged adversary is outside
the guarantees of a regex or repeated snapshot.

## Next integration boundary

Implement the trusted scoped privileged auditor transport and external attach
controller. Admit strict live schemas, reject fixture provenance, bind the
actual sampler image/process/lineage/endpoints, then integrate enable/ACK,
exclusive consumed marker and exact GO+EOF with the original-UID blocked child.
A persistent launcher retaining private endpoints must fail before data; do not
waive that guard. Loaded role/image evidence is also still pending. Never launch
the driver as a `sudo perf` child or infer recording identity from its launcher.

The original source-policy binding still preserves full48-derived11-case order
and all proposed330 reports, selected after original results. Own source/native/
driver/archive/actual locks/generated configs/staticRLIB/tool/kernel provenance,
full canonical verification, meaningful guards, qualified review, immutable
declaration and bounded real Linux controls over owned non-benchmark processes
are required before diagnostic data. No original gate/workload rerun is authorized
by these fixture results. Whole-life native samples cannot establish managed
allocation stacks, gate-interior CPU, physical RSS, causal repair or acceptance.
