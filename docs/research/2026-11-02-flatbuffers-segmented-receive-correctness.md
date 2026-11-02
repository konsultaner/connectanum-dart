# Segmented FlatBuffers receive views (2026-11-02)

The native WebSocket receive path preserves prefix/body continuation pieces,
but the pre-change FlatBuffers parser coalesced the whole frame before generic
validation. The isolated branch `codex/flatbuffers-segmented-decode-views` starts
at `600e82f56d3da6ac998eeb5a60fec175354215ca` and keeps that validation while
preserving segmented input. Fields inside one segment borrow their `Bytes`
owner. Only a field crossing segments is gathered. Byte-vector bounds checks
do not materialize the body before the single existing `slice_or_copy` call.
Contiguous parsing stays borrowed; a sparse index bounds segment lookup work.

Fresh bootstrap and full pre-change fast regression pass first. After correcting
a process-global copy-counter test race with a test-local mutex, the test-only
result is exactly one alias failure / one contiguous control pass, with 10,416
coalesced bytes. After correction, the same regression retains the original
application pointer with zero coalescing/range-copy bytes. A separate necessary
two-byte crossing field copies exactly two bytes. All full-body checks remain.

Verification passes on the own rebuilt native library `3170141d…`: 474 core
Rust tests, two alias regressions, three codec integrations, 319 FFI tests,
615 router-runtime tests, 22 actual native WebSocket tests and 115 MQTT tests,
including seven actual Paho cases. The new fresh 1 MiB FFI test checks metadata
peek, original body pointer, no whole-frame cache, view survival after routing
release and cleanup after view release. Existing fixture/truncation/byte-mutation
checks now also require identical segmented/contiguous messages or errors.
Bounds/alignment, cycle/depth, string/element/ID/enum, metadata/payload validation
and ownership policies remain intact.

Retained setup/test failures include the counter race, an empty-test assertion
compile error and a boundary-test filter matching zero tests. Both actual named
boundary tests execute in the final 474-test pass. A wrong-directory MQTT run
failed to find package-relative Python/certificate fixtures; the corrected
package-directory run passes all 115 cases using the same actual native bytes.
No production fix or numerical rerun was needed for these invocation issues.
Completed GLM and root review find no confirmed remaining source-level defect;
a later token-limited advisory is retained as incomplete, with no approval claim.

This is component correctness, copy and lifetime evidence. Own frozen canonical,
copy/lifetime campaign, CI, controlled before/after measurements and complete
strict final-runtime 48/50 acceptance remain required. No source adoption,
RSS parity or transport-speed repair is claimed. All original benchmark results,
body verification, windows, samples, SDK/GC/allocator/worker and gate policies
remain unchanged. PR #132 remains draft on its existing head and base.

[Input hashes and verification receipts](2026-11-02-flatbuffers-segmented-receive-correctness-audit.json).
