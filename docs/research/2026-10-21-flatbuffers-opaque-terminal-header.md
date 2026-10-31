# Dart opaque FlatBuffers terminal header

## Change and wire contract

`Serializer.serializeFragments` previously returned three pieces for an opaque
body: an envelope containing an empty placeholder vector, a separate vector
header and the original application bytes. It now writes that empty vector first
in the backwards builder and uses the existing same-builder vector reference.
After finishing the envelope, its final length word describes the following
original body. The result contains two pieces and eight fewer wire bytes.

These pieces form **one FlatBuffer and one WAMP frame**. The first piece is not
a standalone message. The root offset remains at the start; only the final
vector-length word changes. A fresh private field map is modified, and caller
bytes remain untouched. The original path remains available if the builder
cannot provide the required layout/alignment. Ordinary argument containers,
multiple vectors, schemas, public builder defaults and native ABI are unchanged.

This applies the existing native writer's terminal-vector approach at the Dart
serializer boundary. It does not adopt foreign/database allocations or extend
ObjectBox transaction lifetimes.

## Evidence and limits

The original public serializer and isolated candidate are compared on 93 cases,
with ten observations per variant: all 25 public models, opaque bodies through
one MiB, arguments/keywords, encoded binary prefixes, forty alignment cases,
metadata growth, long URIs and forwarding metadata. Independent validation
checks decoded fields, original span identity and mutation visibility, and the
exact 64-MiB frame limit plus one-byte-over rejection. The 55 opaque cases remove
one fragment/eight bytes; the other 38 retain identical complete wires.
For two long-URI growth cases, the new builder preserves four extra **header**
bytes during resizing. It does not copy application data.

A separate, balanced, seven-pair component run uses three 100,000-encode warmups
per variant and 300,000 encodes per measured observation. All 3,169 tracked
inputs, four resolved inputs and private probe sources remain unchanged under
the exclusive machine lease. It measures an encoder with reused application
input, without networking or whole-workload preparation:

| Case | Median candidate/baseline encoder time |
| --- | ---: |
| Empty CALL | 1.0067 |
| Arguments and keywords | 1.0107 |
| Opaque one-MiB body | 0.9614 |
| Opaque body with 200-byte custom metadata | 0.9674 |
| Opaque body with a 512-character URI | 0.9745 |
| Ordinary binary-prefix body | 1.0107 |

The fallback costs remain reported. These component results establish no
throughput, latency, CPU, allocation/GC or RSS acceptance for #103. The original
48-case primary and 50-case supplemental campaigns, better CBOR/MessagePack
baseline, floors, repetitions and budgets remain required.

Rejected experiments are retained: a fixed 256-byte initial envelope adds
growth allocations for medium metadata/URIs; general-writer terminal-vector
variants regress empty-control component time by 4.38%, 2.37% and 2.91%.
No rejected writer or public builder-default change is adopted.

Local raw observations, source manifests, complete wires, failed setup attempts
and independent audits are retained under
`out/flatbuffers-resume-20261020/opaque-terminal-*`,
`managed-capacity-component*` and `terminal-vector-v*-evidence/`.

## Verification status

The added two-piece assertion first fails on the original three-piece output.
After the change, all 134 focused cases and all 3,395 serializer VM cases pass;
analysis, all 154 existing static mutation proofs and all 67 Chrome/Dart2Wasm
fragment cases pass. An initial browser command from the workspace root fails
to load test assets; the canonical package-directory invocation passes. The seven payload
message types retain their exact read-only body views and metadata. The exact
aggregate bound accepts the boundary and rejects one additional byte.

Run the fragment contracts from their package directory:

```sh
cd packages/connectanum_core
dart test test/serializer/flatbuffers_fragments_test.dart
dart test test/serializer/flatbuffers_fragments_test.dart -p chrome --compiler=dart2wasm --timeout=5m --concurrency=1
```

Frozen complete `bin/verify` now passes on `f316941a` in 22m33s, including
full Chrome/Dart2Wasm suites, with all 3,170 tracked source files and four resolved
inputs unchanged. The resulting-source
[lifetime/production-copy renewal](https://github.com/konsultaner/connectanum-dart/actions/runs/39533302910)
passes independent audit of four phases, 120 owned cases, 300 short inventory
rows and all 32 no-copy observations. Public native workloads prohibit byte-view
export and leave zero tracked owners before GC. These short rows establish no
performance acceptance.

The resulting-source [90-row diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/39533305805)
retains zero integrity gaps and six numerical failures: all three RSS comparisons,
Dart-value CPU, and Dart-value GC/p99 confidence bounds. All throughput medians
pass. Its actual native library and driver hashes match its copy proof exactly.
The [full 48-case primary](https://github.com/konsultaner/connectanum-dart/actions/runs/39534974873),
[50-case supplemental](https://github.com/konsultaner/connectanum-dart/actions/runs/39534977336)
and [full CI](https://github.com/konsultaner/connectanum-dart/actions/runs/39533299518)
remain pending. No acceptance, regression waiver or cross-runner causal claim is
inferred from component results or changes in diagnostic failure counts.

## Further probes retained outside production

A separate byte-vector access probe compares the current verifier with the same
checks after an explicit `Uint8List` narrowing. It retains 112 observations
across four body lengths, writable/read-only inputs and seven balanced pairs.
The narrow form shows no consistent gain, including a 1.0010 time ratio for the
one-KiB read-only case and an empty-body writable cost. This does not establish
a benefit for changing generated getter types; production and benchmark checks
remain unchanged.

An adaptive envelope-capacity prototype uses already-encoded metadata and URI
lengths, capped at the original 1,024-byte default. Its first version adds a
310-byte header-growth copy for four forwarding principals and grows backing
from 1,024 to 1,456 bytes; the failed audit is retained. A conservative revision
accounts for duplicated typed metadata. All 138 complete wires, original body
spans, decoded fields and exact aggregate bounds match the current serializer
across 2,760 component observations, including ASCII/multibyte URI and metadata
boundaries. Backing decreases to 512 bytes in 51 cases; 87 remain unchanged, with
no additional observed growth copies in that inventory.

A separate seven-pair encoder-only run retains all 84 observations, with three
100,000-call warmups and 300,000 encodes per observation. Median time ratios for
opaque one-MiB, 200-byte metadata and 512-character URI cases are respectively
1.0099, 1.0117 and 1.0201. The smaller backing is a measured tradeoff, with no
whole-workload evidence for adopting it. It stays outside production, and public
builder defaults remain unchanged. These are component observations, not new
acceptance gates or a waiver of existing whole-workload budgets.

Both follow-ups preserve all 3,170 source files and four resolved inputs under
the exclusive machine lease. Their sources, failed attempts, complete wires,
observations and independent audits remain under
`out/flatbuffers-resume-20261020/typed-vector-verify-*` and
`adaptive-envelope*`. The timing receipt's generic `probe_sha256` labels its
component fixture; `experiment_inputs_sha256` separately retains the actual
executed timing source and wrapper hashes. The command and full source manifests
are authoritative for that component-only run.
