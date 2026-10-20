# Native FlatBuffers table cache

Date: 2026-10-20. Scope: issue #103, performance PR #132.

The checked reader memoizes tables by `(byte offset, schema reference)`, retaining
their computed height and owned field tree. Ordinary frames contain a root and
one message table. Those frames previously allocated and hashed a fresh table
map even though its key set is tiny.

The reader now stores its first four entries inline. Further distinct tables
use the existing randomized HashMap. Entries are never evicted or migrated;
updates stay in their original partition. Lookup work is bounded by four inline
comparisons followed by ordinary hashed lookup. Table identity, cycle/depth
checks, cached heights and the 10,000-distinct-table limit remain unchanged.
Strings retain their existing cache and field dictionaries remain BTreeMaps.
No public API, native ABI or wire-format change is introduced.

## Reproduction and validation

An isolated source copy changes only the reader implementation and its new
resource regression. The generated FlatBuffers builder independently constructs
valid frames containing forwarded principals. Both baseline and candidate:

- Accept 10,000 distinct tables, including the root and CALL table.
- Reject the next distinct table at the existing limit.
- Accept 10,001 references to five shared principal tables.

All 32 FlatBuffers tests pass, including malformed-frame and lifetime coverage.
All 56 independently generated contiguous/segmented streams remain byte-identical
across 25 public models and three opaque body sizes.

A thread-local allocation probe wraps the public decoder after preparing its
input. Across body sizes 0, 1,024 and 1,048,576 bytes, ten repeated observations
agree: allocation requests fall from seven to six and requested bytes from
2,844 to 2,704. Returned application slices remain inside the original input
allocation. Restoring the original implementation restores the original counts.
This measures requested native heap allocations, not live memory or RSS.

Seven alternating local microbenchmark pairs use 500,000 public codec operations
per batch, fixed typed metadata and a one-KiB opaque body. The median parsing
time ratio is 0.9475 (individual ratios 0.9337–0.9579); unchanged encoding has a
median ratio of 0.9915. The local platform is macOS/arm64 with Rust 1.95.0.
These short component measurements are not end-to-end or parity acceptance.

An alternative sorted-vector field dictionary was rejected: it reduced native
allocation bytes but parsing became 3.4% slower. That representation is absent
from the delivered reader.

## Benchmark execution

Paired diagnostics and full payload stack replays now use separate concurrency
groups. Each still has its own isolated hosted VM and keeps its original
process lifetime, inventory, repetitions, duration, sample floors and deadlines.
This lets a new paired diagnostic proceed while an unrelated long stack replay
continues. Full primary/supplemental acceptance remains required; no historical
failed or incomplete run is promoted to acceptance.

Evidence is under `out/flatbuffers-resume-20261020/`, including
`inline-cache-micro-result.json`, `inline-cache-allocation-wire-audit.json`,
`inline-cache-resource-tests.log`, `inline-cache-resource-baseline.log` and the
review disposition. Frozen full `bin/verify` passes on resulting source
`28fa8011` in 23m41s with all 3,159 source inputs and locks unchanged. Renewed
production proofs pass all 120 copy cases and all 300 short supplemental rows,
including 32 zero-avoidable-copy observations, with unchanged binaries.

The full-floor ninety-row Linux diagnostic independently recomputes with no
integrity findings and eleven numerical gate failures. Both optimized native
construction paths pass throughput, CPU and allocation comparisons, but all
three RSS comparisons fail. The pre-encoded p99 confidence bound also fails
even though its median ratio is below one. Component improvement does not
accept those budgets. Full current-source campaigns remain queued/running.


All 38 hosted CI checks pass on this source in run
[39466446961](https://github.com/konsultaner/connectanum-dart/actions/runs/39466446961).
Full primary and supplemental measurements remain separate; this does not
establish performance parity.
