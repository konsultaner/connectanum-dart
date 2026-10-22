# Native FlatBuffers allocator owner tracking

## Measured problem and contract

`_NativeAllocator` constructs an identity map and inserts each `ByteData` / native
handle pair, including the usual single-allocation model. The proposed private
change stores one pair directly in nullable fields and creates the identity map
only when more allocations are live. Zero-capacity native allocations retain the same
`ByteData`-identity tracking policy. The first slot can be reused after removal;
remaining pairs stay in the overflow map. Current-buffer selection is unchanged.

Freeze finds the owner, calls the native validation/freezing operation, and only
then removes tracking. A validation failure leaves both current and owner
tracking intact. The upstream allocator's resize allocates before copying and
releases the old buffer only after successful copying. A copy failure therefore
leaves both allocations tracked until disposal. The inline slot and overflow
map preserve that behavior. Native ABI, public writes/guards, payload leases,
byte-view export rules, copy counters and schemas are unchanged.

## Private evidence

All experiments use source clones and the same ffi-test native library. The final
bundle snapshots 3,176 tracked/resolved root inputs and 346 private source/config
inputs before execution and verifies every hash and the machine-resource lease
afterward. No model inference or other cooperating local performance job runs
inside that lease. Production source is unchanged during measurement.

The one-KiB allocation probe controls a separate Dart process through stdin and collects
its heap/GC volume with the unchanged production collector. Each codec/variant
retains an empty signaling control and three 100,000-operation windows, following
100,000 actual construction warmups. Every estimated-volume arithmetic identity
and rounding bound is independently checked. All bounds are below one percent.
Full control wires and input/growth-copy counters match within each codec.

| Codec | Baseline estimated bytes/operation | Candidate | Ratio |
| --- | ---: | ---: | ---: |
| FlatBuffers | 3,079.64 | 2,871.05 | 0.93227 |
| CBOR | 6,474.45 | 6,474.43 | 1.00000 |
| MessagePack | 6,474.35 | 6,474.38 | 1.00000 |

These estimates include the retained common observation/signaling overhead;
empty controls are reported without subtracting them. The primary workload uses 64 KiB, so the component percentage is not a primary
workload gain. The approximately 209-byte reduction is managed allocation pressure, not a count of allocations,
live heap, native allocator requests, peak RSS, GC acceptance or full parity.

Ten direct allocator lifecycle checks pass on each source: zero allocation,
aligned backward subrange, first-slot reuse, mixed three-owner disposal,
five growth transitions, resize copy failure with two live allocations,
inline/map freeze failure with retry, unknown identity and repeated disposal.
Native owned-allocation and handle counters start and end at zero in every case.

A separate timing process uses the actual model construction and explicit owner
disposal, without VM-service profiling. Four shapes retain seven balanced pairs,
with one equally sized warmup per invocation: 100,000 constructions for empty,
1-KiB exact and 1-KiB forced-growth models; 1,000 for 1-MiB models. Every complete
wire and copy control matches. Local component results are:

| Shape | Median candidate/baseline time | Bootstrap 95% interval |
| --- | ---: | ---: |
| Empty body | 0.88259 | 0.87780–0.89963 |
| One KiB, exact initial size | 0.92843 | 0.90637–0.93934 |
| One KiB, initial size eight | 0.98691 | 0.95387–1.02121 |
| One MiB | 0.98963 | 0.98589–1.00426 |

Growth and large-body intervals overlap parity. These local standard-SDK/ffi-test
components do not grant Linux production throughput/CPU/RSS/GC acceptance. Raw
observations, sources, controls, wrappers and the independent final audit remain
under `out/flatbuffers-resume-20261022/builder-inline-probe/`.

## Rejected attempts and review limits

Write-guard inlining is not adopted. Its first in-process allocation profile
includes large profiler-response JSON allocations in the measured isolate and is
inconclusive. Repeating from a separate process with the production volume
collector finds no allocation reduction for any codec.

Local test advice is checked against synchronous Dart and native semantics.
A proposed concurrent/OOM test is replaced with deterministic out-of-range
resize-copy failure after the second allocation. The Qwen review exceeds its
output cap and supplies no completed review. The GLM judgment completes, but
its stated counterexamples each explicitly recover in its own analysis; source
inspection and lifecycle tests confirm no demonstrated wrong-owner sequence.
Its invented resize-failure cleanup is corrected: both buffers remain tracked
until allocator disposal. Neither response is treated as an approval certificate.

## Acceptance

The tested owner-tracking implementation is now adopted, with declarations
grouped without changing field order. Public wire/lifecycle regressions pass
with 50 focused ownership/frame/segment cases. Helper style notices are fixed;
analysis and its direct isolated rerun pass. Existing static mutation proofs
and regenerated inventory validate. A wrong-path Python test invocation is
retained as failed before execution; corrected direct runs pass 13 and 93 tests
respectively (one pre-existing runner-test skip). A parent-process error-path
coverage case is added afterward; the final 50-case rerun and clean analysis pass
with unchanged inputs. Actual-source review completes without a demonstrated
ownership defect: existing preallocated wire tests already exercise the one-owner
path, and a positive native counter assertion after freeze prevents always-zero
oracles from passing the cleanup probe. Remaining work is
canonical verification and exact-head hosted evidence. All 48 primary and
50 supplemental cases, their original repetitions/floors/budgets, the better
CBOR/MessagePack baseline and approved copy scope remain required. Existing
failed/incomplete/superseded observations are retained. This research alone
closes no issue or milestone.

Resulting-source canonical verification on `2de4ec32` passes in 23m58s, with all
3,174 source inputs and four resolved inputs unchanged and a clean tree,
including VM/live/consumer and Chrome/Dart2Wasm verification. Hosted primary and
supplemental results remain pending; the timeout diagnosis is separate work.
