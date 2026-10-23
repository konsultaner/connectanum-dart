# Native FlatBuffers string-cache allocation

## Problem and candidate

The native reader constructs a `HashMap` for string offsets. A typical CALL,
PUBLISH or ERROR carries one routing string, so its first insertion allocates
the map even though the message needs only one cache entry.

The candidate keeps four entries inline and uses a randomized `HashMap` beyond
that prefix. The inline array is itself initialized lazily: string-free messages
do not initialize or drop four unused entries. Cached strings retain their
existing `Arc<str>` identity. The byte-vector owner, wire format, ABI, UTF-8 and
terminator checks, one-MiB string-visit budget, depth and table limits remain
unchanged. Repeated references still consume the original visit budget.

This candidate is measured privately before production adoption. The diagnostic
first retains unchanged-reader baseline `b1baf368` as
[run39779792736](https://github.com/konsultaner/connectanum-dart/actions/runs/39779792736).
The verified lazy variant is then adopted; resulting-source acceptance remains
pending.

## Allocation evidence

The probe prepares real frames outside a thread-local Rust allocator counter.
It retains first-use costs and ten steady observations for eight message shapes
at body lengths zero, one KiB and one MiB: 24 frames and 264 observations per
variant. All complete wires match and nonempty application spans remain within
the original frame. A RESULT without wire strings retains six allocations and
2,704 requested bytes. Representative one-KiB observations are:

| Shape | Calls before / after | Requested bytes before / after |
| --- | ---: | ---: |
| CALL | 9 / 8 | 2,860 / 2,752 |
| PUBLISH | 10 / 9 | 3,501 / 3,393 |
| ERROR | 9 / 8 | 2,869 / 2,761 |
| PUBLISH, three excluded authids | 28 / 26 | 5,764 / 5,448 |
| PUBLISH, eight excluded authids | 46 / 45 | 7,213 / 6,805 |

These are allocator requests, not live heap, Dart allocation, GC, RSS or complete
pipeline-copy totals. Both isolated builds reproduce the original observations;
the checked-in probe adds routing-field checks outside the counter. All 37
FlatBuffers tests pass, including new inline/overflow alias, repeated-reference
budget and malformed-string regressions.

Run the reproducible probe with a fresh output directory:

```sh
cargo run --release --locked --manifest-path native/transport/Cargo.toml \
  -p ct_core --example flatbuffers_reader_allocations -- out/reader-allocations
```

The existing `flatbuffers_encoder_component` workflow choice now runs both
encoder and reader probes with pinned Rust 1.99.0, immutable inputs, executable
hashes, complete wires and explicit diagnostic-only scope. It grants no primary
performance acceptance.

## Parser timing and retained costs

A separate executable uses the normal Rust allocator; the counting wrapper is
absent. Four cases retain seven balanced pairs, three 100,000-parse warmups per
variant and 500,000 parses per observation. Each invocation also warms
10,000 parses before its timer. Source, lock and compiler inputs
remain unchanged under the exclusive machine lease. Local Rust is 1.95.0 on
macOS arm64, so these component results cannot replace hosted Linux acceptance.

| Shape | Median candidate / baseline time | Paired bootstrap 95% interval |
| --- | ---: | ---: |
| String-free RESULT | 0.9969 | 0.9915–1.0005 |
| CALL | 0.9587 | 0.9535–0.9716 |
| PUBLISH | 0.9717 | 0.9634–0.9814 |
| PUBLISH, eight excluded authids | 0.9760 | 0.9712–0.9802 |

The RESULT interval overlaps one. This establishes neither a control-message
speed gain nor whole-workload parity. All 48 primary and 50 supplemental cases,
their original floors, better-codec baseline and resource budgets remain required.

An earlier eager-array version retains a 1.01 RESULT time ratio alongside its
allocation savings. It is superseded by lazy initialization. The first timing
attempt is invalid: a shared Cargo target reused identical executables for the
two sources. Its raw observations remain marked invalid and are never used as
evidence. The valid runs use separate target directories, distinct executable
hashes and repeated allocation controls matching both original variants.

Source snapshots, all attempted runs, complete wires, counter observations,
normal-allocator timings and independent audits remain under
`out/flatbuffers-resume-20261022/reader-*` and `source-*`. No failed observation
is rewritten or promoted to acceptance.

## Acceptance still outstanding

The preceding production source `f316941a` completes all 1,440 primary rows with
zero integrity findings and 151 numerical failures. Its protocol and encrypted
supplemental shards complete 900 and 240 rows, retaining 152 and 42 costs.
The payload shard stops after 139 of 360 rows at its original deadline; its
failed manifest does not supply final source-invariance confirmation. The
reported rows remain partial evidence, never complete supplemental acceptance.

Fresh resulting-source canonical verification, hosted lifetime/copy evidence,
and full unchanged primary/supplemental campaigns are required for any adopted
cache change. The stack-capture replay and native-buffer profile investigate
separate remaining execution and allocation failures. This research does not
close #103 or the milestone.

## Resulting-source evidence

Source `36a6df24` passes frozen full `bin/verify` in 27m22s, with all 3,172
source inputs and four resolved inputs unchanged, including browser verification.
Linux baseline `b1baf368` and candidate `36a6df24` component artifacts verify all
tracked hashes, the same resolved lock/compiler/probe and all 24 identical reader
wires. The Linux ordinary CALL/PUBLISH/ERROR difference is one allocation and
116 requested bytes; platform-dependent allocation sizes differ from the local
table above. Both retain cold and ten steady observations for every frame.

Renewed hosted lifetime/copy evidence passes all four phases, 120 owned-copy
cases and 300 short inventory rows, including E2EE/native crypto/transcode and
all 32 no-copy flags. The strict 90-row diagnostic has zero integrity gaps and
three numerical failures: Dart-value GC confidence bounds and Dart-value/native
pre-encoded RSS. All three throughput, latency, CPU and allocation comparisons
pass; its production binary hashes match the copy proof exactly. This does not
substitute for the running full primary and supplemental campaigns.

The historical `3c954a92` replay completes the entire original 360-row payload
schedule with no stall or stack capture, all 60 no-copy observations and verified
source/locks/binaries/order/cleanup. Its VM wrappers make it diagnostic only.
The earlier timeout remains unexplained and retained, never reported as fixed.

A separate private guard-inlining attempt is not adopted. The first in-process
VM allocation profile includes its own large JSON-decoding overhead and is
inconclusive. The corrected external controller uses the unchanged production
heap/GC-volume collector, 18 windows of 100,000 actual builder operations and six
empty controls, matching wires/copy counters and fixed source/library inputs.
`vm:prefer-inline` on both write guards changes no measurable allocation volume
for FlatBuffers, CBOR or MessagePack. Its raw observations and failed/incomplete
companion attempt remain retained alongside the successful narrowed retry.
