# Bounded native INVOCATION headers

The controlled profiles on runtime `290480a3` retain generic FlatBuffers header
projection/writing in native RPC forwarding. The isolated encoder change in
this commit writes common opaque INVOCATION headers through the pinned generated
table, sharing the existing RESULT metadata storage and conservative bounds.
It is a component improvement; RAM and complete transport acceptance remain
unproven for this runtime.

The predicate accepts valid request/registration IDs, one transparent body,
`ppt_scheme` plus `ppt_serializer: flatbuffers`, and optional boolean `progress`
and `receive_progress`. The complete standard CBOR dictionary is preserved.
`receive_progress` also appears in the pinned typed table; `progress` remains
metadata-only because INVOCATION has no such table field. Absent, false, true
and fallback null/custom values retain their existing meanings. Other shapes
use the unchanged generic writer and its validation.

The implementation preserves the generic 64 MiB conservative table/vector
budget, the 1 MiB metadata ceiling, source ownership, and the segmented body
alias. The larger INVOCATION table receives a metadata-sized, eight-aligned
reserve. No body generation or verification, workload, sample/window count,
copy boundary, SDK, GC/allocator policy or performance gate changes.

A public-encoder unit test fails before the change with 256 copied builder-growth
bytes at an 88-byte scheme and explicit `(progress=false, receive_progress=true)`.
It passes afterward with metadata, pinned-schema fields, full-message equality
and aliases checked. Additional tests cover unknown/null/mistyped fields, ID
limits, ordinary/mixed payload fallback, exact metadata/budget boundaries,
source drop, every fragmentation split and every truncation. All 469 core tests
and three codec integrations pass.

The [standalone component probe](2026-11-01-flatbuffers-invocation-component.rs)
measures the actual public segmented encoder, forwarding every allocation to
`System` with the original layout. Each of its 117 inputs has newly generated
body storage; counting covers encoding and initial reference-count promotion.
Decoded-message, exact metadata, generated-schema and alias checks occur outside
that counting interval. Compile the same probe against each worktree's own
`ffi-test/release/deps` libraries (`ct_core`, `bytes`, `flatbuffers`, `serde_value`,
`serde_cbor`) with `rustc --edition=2021 -O -L ... --extern ...`. This allocator
observer belongs only to the separate component executable.

Typical 25-byte scheme results from actual compiled implementations:

| Metadata flags | Before calls / requested bytes | After calls / requested bytes |
| --- | ---: | ---: |
| Neither flag | 19 / 2,217 | 6 / 360 |
| `receive_progress: true` | 23 / 2,581 | 7 / 440 |
| `progress: true` | 21 / 2,353 | 6 / 368 |
| Both true | 25 / 2,797 | 7 / 448 |

The ordinary envelope remains 160 bytes. Other equivalent layouts may differ
in padding; complete decoded controls and exact CBOR dictionaries match. A
separate pre-implementation generated-table prototype also passes 27,810
schema/metadata/message/alias cases. Its timings are component observations,
not throughput, CPU or RSS acceptance.

Both retained full campaigns on `290480a3` still fail. This new runtime requires
its own frozen canonical verification, clean CI, copy/lifetime reports and
complete strict 48-/50-case acceptance before adoption. PR #132 stays draft on
its existing head/base; issue #103 and the milestone stay open. The separate
MessagePack allocation-precision decision is not waived.
