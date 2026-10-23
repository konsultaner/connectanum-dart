# Temporary FlatBuffers table storage

The preceding runtime's complete primary run 39847823235 on `ad8ea5e5` has
1,440 independently validated rows/48 cases and zero integrity findings, but
143 numerical costs. The dictionary-plan candidate's strict run 39874514230
passes every timing/CPU/allocation comparison in its three selected cases;
Dart GC confidence and pre-encoded RSS still fail. Neither result accepts parity.

## Candidate

Dart's internal wire-table reader now omits absent optional reference fields.
It retains every scalar/default/false/zero value. Ordinary map lookup still
returns null for a missing reference; the public decoded CBOR metadata map is
separate, fresh, mutable and preserves explicit nulls. Frame validation checks
non-null payload/args/kwargs vectors directly, independent of payload-key
presence. Mixed transparent and ordinary payloads still fail before a view is
returned. Wire vectors keep their original backing storage.

Native agreement now estimates temporary projected-field capacity from the
metadata dictionary, bounded by the pinned schema size. Empty metadata starts
without an allocation. The encoder keeps its original reservation and both paths
use the same projection/conversion/validation body. This changes allocator
requests, not schema, ABI, payload ownership or copy instrumentation.

## Controlled evidence before adoption

Baseline is `2646ee698e76e76df14819176202ead4a6903d74`, a docs-only successor of
verified runtime `55ae6f4d`. Frozen baseline `bin/test-fast` passes with all 3,201
sources/four resolved inputs unchanged. Earlier frozen `bin/verify` on `02840d2d`
passes in 22m54s, including Chrome/Wasm. These are baseline results, not final
verification of the new candidate.

Private Dart baseline and corrected candidate each pass 491 tests. Their private
package selection and all 99 library files are verified; exactly the frame and
wire reader modules differ after removing variant markers. A deliberately
incomplete null-omission variant fails 52 CBOR rejection cases. The added checks
cover all seven payload-bearing message tables, empty/truncated/wrong-root CBOR,
non-string kwargs keys, scalar defaults, byte aliases and independent mutation
of public metadata with explicit nulls. The initial private wrapper's nullable
map compile failure is retained; its Call-specific assertions now explicitly
assert non-null metadata rather than skipping checks.

Native variants have separate build directories and actual-core markers checked
by a private test and each executable outside allocation measurement. Each passes
39 existing conformance cases plus its marker check. All 24 reader, ten encoder
and 42 broader fixture observations retain the first and all ten repeated
counts. Every request count/volume is nonregressing after the bounded estimate;
encoder requests remain identical. The broader fixtures retain identical
accept/reject outcomes: 22 accepted, 20 rejected by the profile. All 56 emitted
wire files are byte-identical, and reader probes retain nonempty payload aliases.

Representative native allocator requests per parse, independent of body size:

| Frame | Before bytes / calls | Candidate bytes / calls |
|---|---:|---:|
| RESULT | 1,816 / 5 | 1,032 / 4 |
| CALL | 2,200 / 7 | 1,248 / 6 |
| ERROR | 1,649 / 7 | 977 / 6 |
| PUBLISH | 2,657 / 7 | 1,481 / 6 |

This is a macOS ARM64 allocator component, not Linux RSS or transport timing.
The original empty-capacity prototype requested 56 extra bytes for the valid
three-field Abort fixture; the schema cap removes that regression. Its failed
candidate remains retained. An earlier shared Cargo target produced identical
baseline/candidate binaries without establishing candidate selection; that
comparison is excluded. The broader fixture probe also retains its initial
failed cold-equals-repeat assumption. Cold and repeated counts are now reported
separately and every observation participates in the comparison.

## Remaining validation

Seven component-isolation contracts and 154 existing mutation proofs pass. The
component runner supports only the declared frame/projection pair, frame/wire
reader pair or their cumulative three-file change, with an explicit full-SHA
baseline. Unrelated/single/empty module changes remain rejected. The before-change
sparse-pair test fails; all seven resulting contracts pass after extension.

Qwen's validation-order/key-presence questions are checked against direct field
lookups, the separate public CBOR dictionary, the unchanged rejection order and
the negative controls; no demonstrated defect remains from those questions.
GLM also finds no confirmed correctness defect. Its baseline-acceptance wording
is not adopted: the old reader inserted payload:null and rejected malformed
CBOR; only the deliberately incomplete variant skipped that validation.
Resulting-source focused/full verification,
Linux component, production copy/lifetime and unchanged complete primary and
supplemental campaigns remain required. No performance or release acceptance is
claimed by these functional and allocator results.


Resulting-source analysis exits 0 (informational repository lints remain), all
3,456 serializer cases and 39 native conformance cases pass. Freshly compiled
actual-source reader/encoder observations match the audited private candidate
exactly. The 38.83-second focused sequence preserves all 3,202 source/four
resolved hashes. Twenty CI execution contracts also pass. This still does not
replace frozen full verification or hosted performance/copy acceptance.
