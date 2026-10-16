# Immutable FlatBuffers byte-vector views

The pinned Dart runtime returns a lazy list for a byte vector. Each element
access goes through the list and ByteData reader. Connectanum now provides
`FlatBufferUint8ListReader` through `flatbuffers_serializer.dart`: it validates
the forward reference and declared length, then returns an immutable Uint8List
view of the same storage. `flatBufferContext` preserves the input's logical
range rather than exposing the remainder of a larger backing allocation.

Both pinned generation scripts select this reader. WAMP schema slots, compiler
version and wire bytes stay unchanged. Ordinary generated application schemas
can use the same helper when adapting their byte-vector readers. External
storage must remain valid for the reader's lifetime; creating a view cannot
extend a database transaction. Exported Connectanum native byte views already
retain an independent native owner in their SDK backing store.

The shared benchmark payload generator writes its deterministic pattern
directly into Uint8List instead of creating an intermediate integer list. This
applies to all codecs. FlatBuffers reserves the known model size plus aligned
control space; explicitly requested small native builder sizes remain useful
for growth/error tests. Encodings remain identical to the pinned model and to
the regular CBOR/MessagePack reference encoders.

Scoped VM tests cover aliasing, mutation rejection, nonzero offsets, empty
vectors, exact-range bounds and malformed forward references. Chrome/Dart2Wasm
passes 79 binding/view cases. The initial root-level browser invocation fails
its hybrid loader paths; the package-root invocation is the accepted result.
Fresh Python/Dart/Rust interop passes 33 upstream and 42 extended fixtures,
bidirectional calls, and contiguous/segmented output for all 25 public types.
Complete serializer mutation inventories include the new test without dropping
existing support files, targets, deadlines or thresholds.

An ignored read-only prototype checks identical contents, immutable writes and
storage aliasing. It reads a 64 KiB vector faster in JIT and compiled execution;
these micro timings are not protocol acceptance evidence. A separate attempted
builder optimization using repeated public word writes tests slower and is not
included.

The actual before/after diagnostic runs three RawSocket cleartext RPC cases,
three codecs, three warmups and seven measured passes: 90 rows per campaign.
They use the same rebuilt driver and verified `fc808e92` production library,
balanced codec order, one client process and one server process. The first
attempt rejects an outdated driver before executing any rows; that failure is
retained. Candidate changes are restored after the baseline through a recorded
stash. The candidate's dirty source state makes it diagnostic evidence only.

| Construction/client | Throughput ratio before | Ratio after | FlatBuffers throughput change |
|---|---:|---:|---:|
| Dart values/Dart | 0.653 | 0.641 | 1.004 |
| Native buffer/native | 0.787 | 0.823 | 1.063 |
| Pre-encoded span/native | 0.799 | 0.833 | 1.053 |

Ratios compare FlatBuffers with the better CBOR/MessagePack baseline. The two
native paths improve modestly. The Dart-value path does not improve usefully;
its allocation ratio worsens from 1.496 to 1.618. GC ratios also worsen in this
short diagnostic. All observed point estimates remain below the performance
requirements. Neither campaign passes: one-second/150-minimum-sample rows and
macOS's unavailable Linux CPU/RSS evidence are insufficient. Placeholder ratios
for unavailable CPU/RSS are not measurements.

Owned transport counters are complete on the sampled paths and the declared
native FlatBuffers send boundary reports zero payload copies. This does not
accept whole-pipeline copying, E2EE/transcodes, the other 45 primary cases or
performance parity. Raw manifests, rows, logs and comparison reports remain
under `out/flatbuffers-milestone-finish/`. Further profiling and a fresh full
Linux campaign are still required.
