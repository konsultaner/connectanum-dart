# Borrow small native FlatBuffers metadata lookup keys

The source/PID/window/library-audited `65833214` Linux native profile includes
metadata projection on both parse and RESULT encoding. Source inspection finds
that each projected field allocates a temporary serde-value String, including
fields absent from a two-entry PPT dictionary. These are real explicit UTF-8
copies, observed by the existing logical-source-byte copy counter.

For dictionaries with at most eight entries, look up exact borrowed string keys
through a bounded scan. Return the original map value by reference. Larger maps
keep the existing BTreeMap lookup, including its actual copied-key accounting.
This avoids a temporary allocation for common small controls without introducing
a cache, static lifetime, normalization, schema shortcut or large-map linear scan.
String-copy counters count actual copies, not lookups: the decrease is expected
because the key is no longer copied. No replacement estimate is recorded.

A fail-first test observes 16 copied key bytes for three lookups before the fix.
Afterward the same lookups copy zero bytes at sizes 0–8 and retain the old 16-byte
count at size 9. A real two-key PPT RESULT projection preserves both enum values
with no copied lookup strings. Differential tests check values and exact borrowed
pointers against BTreeMap lookup for sizes 0–23, with Unicode, NUL, empty, prefix,
absent and case-distinct keys, nullable/binary/container values and non-string
entries. The length-seven/eight loops plus a non-string entry cover sizes eight
and nine too. Public encoders still reject non-string dictionary keys normally.

All 389 core tests pass. Test builds set `CARGO_PROFILE_TEST_DEBUG=0` and
`CARGO_PROFILE_DEV_DEBUG=0` to bound local disk use; production and CI profiles
are unchanged. Local companion review finds no demonstrated semantic bug. Its
copy-counter concern is resolved by checking the counter's existing documented
source-byte contract and the absence of an actual copied key. No instrumentation
is disabled or fabricated. Evidence: `borrowed-projection-lookup-*` under the
managed worktree's `out/flatbuffers-milestone-finish`.

The preceding terminal-vector source `6d9810ae` passes 300 short supplemental
rows, 120 accounting cases and 36 progressive combinations with all 3,125 inputs
unchanged. These reconcile E2EE, transcode, disjoint encoded volume and owned
copies with the frozen production library, SHA-256
`31c42e8b44897572586d719f990042b7edc3ca5d7fb11480926368975dd47ad6`.
They do not establish speed. Its strict hosted Linux diagnostic is separate.

Fresh resulting-source production proofs, strict Linux performance, final full
verification/CI, five-platform consumers and the unchanged complete primary and
supplemental acceptance campaigns remain required. No performance budget or
copy scope changes, and #103 remains open.
