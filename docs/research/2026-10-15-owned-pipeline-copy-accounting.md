# Owned pipeline copy accounting

The benchmark now computes E2EE totals from eight disjoint observations: client
and router Dart buffer copies, client and router native codec copies, client and
router native raw-frame copies, native crypto staging/bridge copies, and transport
copies. PPT and portable-crypto diagnostics are already part of Dart totals and
are not added again. Plaintext/key setup, metadata string buffers, native SHA
input/digest staging and Dart SHA FFI buffers remain observable, including when
the selected transport uses Dart.

Mixed-serializer totals cover actual router serializer and dispatch buffer work
in that window. They sum router Dart, native codec and native raw-frame copies.
They do not subtract a homogeneous reference window, and do not count application
client serialization as router transcoding. `boundary` records this definition.
Transport bytes remain separate; E2EE includes them once and also exposes a
non-transport subtotal. These totals are overlapping views of the same window,
so E2EE and transcode totals must not be added together.

Counter windows require monotonic before/after observations. Router observations
require a stable positive boss generation, the same nonempty worker set, fenced
asynchronous work and successful workload quiescence. The producer and independent
Python release checker recompute all component subtotals. Missing, negative,
rewound, failed, malformed and unavailable observations cannot certify zero.

The native codec struct is still ABI v1, six u64 values, 48 bytes. A new optional
`ct_codec_copy_metrics_coverage_version()` scalar returning 1 identifies the
expanded observation inventory. Libraries with the old layout but without this
capability remain usable; their codec observations cannot certify complete owned
coverage. Dart snapshot maps add `coverage_version` metadata; that scalar is not
summed as bytes. Unknown layout or coverage versions are rejected before invoking
the snapshot. Live compatibility with the older production b43a0a56 library passes.

The approved scope is `connectanum_buffer_boundaries_v1`, using the standard Dart
SDK. SDK runtime/socket/masking/TLS, Rust runtime and serializer/crypto/file I/O
internals are explicitly labelled according to the active path. They remain
unmeasured. Copies of buffers explicitly performed by Connectanum are included;
reference aliases, scalar encoding and dependency-internal allocations are not
source-buffer copy bytes. This is not a whole-machine zero-copy claim.

Full `bin/verify` passes with HEAD 5516546f and all 3,082 tracked/intended-new
input hashes unchanged, including Rust, VM/live, packaging, core Chrome/Wasm
and 2,859 client browser cases with twenty declared native-only skips. Focused
717 benchmark, 86 client and 35 router cases pass. Sixteen synthetic Dart
producer combinations pass the independent Python validator; adversarial tests
reject invalid counters, forged totals, unsupported coverage, incomplete owners
and incorrect dependency labels.

All 120 actual benchmark HTTP rows pass independent copy validation, spanning
both providers/ciphers, RawSocket/WebSocket, TLS/cleartext, RPC/file transfer,
CBOR encrypted pub/sub/progressive results, typed encrypted pub/sub, and mixed
JSON/MessagePack/CBOR peers. The [checked proof](2026-10-15-owned-pipeline-live-proof.json)
records configurations, subtotals, source/library/report hashes and clean
process exits. This is correctness/copy evidence, not timed performance acceptance.

These extra checks reproduce a benchmark-only bug after the frozen full run:
identity matching reads decoded `event.arguments`, while verification read raw
`event.payload.arguments`. All eight native typed encrypted pub/sub variants
fail first and pass after changing that one accessor. All sixteen typed pub/sub
HTTP cases pass after the fix. The client/crypto implementation is unchanged.
The frozen full result predates this accessor and its eight added regression
cases; final combined verification and hosted acceptance remain pending. Typed
progressive benchmark rows are explicitly unsupported by the existing runner;
that failed exploratory run is retained and excluded from accepted coverage.

A separate fail-first comparison regression proves missing CPU/allocation/RSS
observations previously displayed a 1.0 ratio and passing metric row. Such rows
now retain null observations and display **unmeasured / FAIL**. No samples,
durations, parity thresholds, resource budgets or mutation floors change.

Performance parity remains open: the preceding production reply diagnostic
retains roughly 0.84 throughput ratios. Historical SDK `accumulatedSize` fields
are live heap inventories and cannot establish allocation-volume acceptance.
See the [allocation investigation](2026-10-15-dart-allocation-volume-research.md).

## Allocation and portability checkpoint (2026-10-16)

Frozen full verification at `24f4276b` passes with all 3,092 source inputs and
HEAD unchanged. All five production artifact platforms pass 170 independently
audited consumer cases with zero skips. That source includes the typed pub/sub
verifier correction described above. The following `c2ff8817` test-only repair
uses the portable builder in two new browser reference cases; 155 focused JS
cases pass. Resulting-source hosted coverage is still pending.

The scalar-metadata follow-up preserves complex-value fallback and wire format.
All 180 process allocation reports in its short paired diagnostic independently
validate against raw heap/GC observations. That diagnostic still fails parity;
its allocation ratios range from 1.0556 to 1.1777. The managed typed fixture now
uses the public observed builder so its explicit body-vector copy is included.
Dependency-internal memory remains outside the approved copy scope.
