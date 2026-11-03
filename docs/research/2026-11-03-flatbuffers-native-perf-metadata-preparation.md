# Binary perf metadata reader preparation (2026-11-03)

Twenty-seven new synthetic-file/OWN filesystem cases pass for a streaming,
read-only PERFILE2 metadata decoder. No actual perf file, Linux/root/kernel
control, native build, VM/benchmark/capture or numerical campaign ran.
**This is format decoding only. It always returns capture_ready=false.**

The reader handles a single flat software CPU-clock layout and sample-ID
trailers. FORK/EXIT body PIDs and times remain separate from sampling context.
SAMPLE identifier comes first; metadata identifier comes last. MMAP2's explicit
misc bit14 chooses its build-ID union. All decoded64-bit numbers use decimal
strings. Attribute bytes and ID sections, source identity and complete raw file
SHA are bound; all available data bytes remain as ordered offset/length/SHA
references, including unknown, malformed, lost and partial records. Callers
must retain the original file. Unsupported layouts remain opaque, compression
is not guessed, and no timestamp sorting or favorable attribute selection occurs.

Exact versioned primary sources define the [UAPI record layouts](https://raw.githubusercontent.com/torvalds/linux/v6.8/include/uapi/linux/perf_event.h),
[file header](https://raw.githubusercontent.com/torvalds/linux/v6.8/tools/perf/util/header.h)
and [attribute/ID-section serialization](https://raw.githubusercontent.com/torvalds/linux/v6.8/tools/perf/util/header.c).
URL/hash/size receipts are public; full third-party sources remain local.
Those source definitions do not prove actual installed-tool/kernel compatibility,
recording inheritance, loss coverage, role lineage or loaded-image bytes.

The initial missing-module error establishes feature absence. First22 had19
errors from noncanonical Darwin fixture paths, with3early negative passes;
canonical fixture setup fixed those without relaxing the live guard. The next
failure used an empty data section as an overlap counterexample; the fixture
now supplies actual overlapping bytes. A new count check first referenced a
missing field, then an actual counterexample demonstrated an invalid-size tail
counted as one record. Source now counts only fully framed records and marks
remainder count unknown. Twenty-three pass after that fix; four new source/
error controls complete27. Every executed source, log and regular fixture is
retained. Special nodes retain metadata, not cloned capabilities.

[Root-qualified assessment and every member hash](2026-11-03-flatbuffers-native-perf-metadata-assessment.json),
[all seven executed combined versions and retained evidence](2026-11-03-flatbuffers-native-perf-metadata-evidence.tar.gz).
Local advice is advisory. Root rejects union guessing and attribute stride>136
suggestions: explicit bit14 and the additional16-byte ID descriptor apply.
The final model review reached its token limit without a saved assessment;
that is not backend unavailability or approval. Root reviewed source and tests.

Prior14 Python tools are byte-identical and were not rerun. Sixteen tools remain
uncommitted on HEAD601, production/helper12 unchanged. No new-tool canonical,
source commit/push/adoption or strict dispatch. Last free19.03GB exceeds12GiB;
no cleanup. The original before-edit baseline does not verify these tools.
Actual role/native-image association, original launch/source/config receipts,
complete immutable admission/orchestration, own verification and real bounded
Linux controls remain mandatory before diagnostic data. Whole-life samples
cannot establish managed allocations, physical RSS, causal repair or acceptance.
Both strict campaigns remain failed; PR132 stays draft/unadopted.
