# Dictionary field-plan candidate

Current-runtime payload batch 39852994229/artifact 12463981138 passes independent
input/binary/raw and exact comparison-recomputation audits: 360 rows/12 cases,
zero integrity gaps and 28 numerical costs. The two 10-KiB Dart-value cases show
CPU ratios about 1.03054 (clear RawSocket) and 1.02233 (TLS WebSocket). This
supplemental batch cannot establish primary acceptance.

Profile 39868579299/artifact 12464684028 uses the exact 10-KiB case. Independent
audit verifies 3,196 sources/three retained resolved contents, all 18 snapshots,
posthoc data/VM windows, native monotonic clocks, filtered samples and cleanup.
Archive SHA-256: 2e0f3bc3feca57cf272e44bb007d141f32fc73c8c179e0aa9c53db1aafb66162.
VM stacks associate string/map work with projectFlatBufferDictionary, frame
agreement and retention. VM sampler shares include native/blocking frames and
must not be interpreted as CPU costs; native samples also include scheduling.
These stacks select an optimization, not a causal speed claim.

The current agreement path scans every generated schema table using singleWhere
for each message, then repeats routing/envelope field filtering also performed
by projection. The candidate derives immutable ordered field plans once from
the same pinned specs/predicates and shares them. It keeps every value/default,
enum, nested-Map, conflict and unknown-metadata rule intact. There is no wire,
ABI, payload ownership, allocator or copy-accounting change.

Component baseline is the explicit full commit
b0e5d264bd44833629d1c3811cd7e539864c0e0a. The runner rejects other core-library
changes, copies both library variants, resolves every dependency URI and embeds
private selected-variant markers. Existing binding/validation/metadata/retention/
cache suites run for both variants. JIT-kernel workers verify identical wires and
shared payload storage before warmup. Eight independent worker pairs per shape
(RESULT/CALL, 10-KiB CBOR byte-vector arguments) retain four nested measured
windows and a separate control each; allocation evidence uses the stock-SDK
heap/GC validator. They are model components, not the transport/PPT campaign.
No rows are substituted for primary or supplemental acceptance.

Five integrity tests cover missing/replayed rounds, variant/PID/alias/wire
mismatches, invalid allocation evidence, dependency URI/variant selection and
explicit baseline/diff isolation. Together with the existing diagnostic/tooling
contracts, 107 focused Python cases pass. Formatting and 154 existing mutation
proofs pass. Local bin/test-fast/analysis/review attempts are resource-lease
blocked; no local Dart pass or companion approval is inferred. Hosted functional
and component results, full verification/CI, copy proof and end-to-end parity
remain required before accepting the candidate.


## Audited hosted result

[Run 39872554911](https://github.com/konsultaner/connectanum-dart/actions/runs/39872554911)
on 55ae6f4d60de540367f7e3a887adc74a961ec1bd passes pinned Dart analysis and
434 existing functional cases for each private variant. Artifact 12467405829
has SHA-256 4d70b17f4803ae6c2fe728fef4a0c559a323f7335d1493b33de320e7b6bae55f;
raw rows hash 779b5fa6e5bc3c3f967a5bfa649f22d1d434ba59c28988b30517b094b0b177be.
Independent audit matches 3,201 sources/four retained resolved contents, both
private variants/configs/kernels and the unchanged native copy-proof library.
All 160 rows/32 fresh workers, 128 measured allocation proofs, snapshot brackets,
non-overlap, wire digests and byte aliases validate; summary recomputation agrees.

Eight worker pairs per shape give median candidate/baseline decode-time ratios
0.82056280798 (RESULT) and 0.83084874541 (CALL), with about 80 fewer managed bytes
per decode. Nested windows are not independent replicates. This establishes a
component improvement, not transport/PPT performance parity. Renewed production
copy/lifetime, complete primary/supplemental gates and resulting-source full
verification/CI remain required. No floors or acceptance budgets change.


## Resulting-source verification and strict diagnostic

Frozen `bin/verify` on docs-only successor 02840d2ddea5dda9736f49fee09c86061a140bd2
passes in 1,373.69 seconds, including Chrome/Wasm, with all 3,201 sources/four
resolved inputs unchanged and a clean tree. Log SHA-256:
8cd8ececc7d693e5bafaea882c670b8db4047a4ad8cc3fa47bd58238e6777843.
Qwen review finds no demonstrated defect; the helper is not publicly exported
and the pinned specs are const. Hosted full CI remains pending.

[Renewed copy/lifetime run](https://github.com/konsultaner/connectanum-dart/actions/runs/39874511303)
passes independent input/binary/raw/cleanup audits: 36 snapshot groups/108
post-GC observations, 120 owned cases, 300 short rows/all 32 no-copy observations,
including E2EE/native crypto/transcodes. All four resolved hashes match retained
independently audited component contents; native binaries remain identical.
Artifact 12467638509 SHA-256:
f5d6b91dbfac1952475c1ef2ad9cfe6dff4284a90fa2c4f50534e8e1b488c80d.

[Strict diagnostic](https://github.com/konsultaner/connectanum-dart/actions/runs/39874514230)
has 90 valid independently recomputed rows/zero integrity findings. All three
cases pass throughput, p95/p99, CPU and allocation. Dart-value GC median is
0.91619 but its confidence upper bound 1.13284 fails; pre-encoded RSS median
1.01949 fails. Native-buffer passes every metric. This runner-specific result
neither establishes a causal RSS fix nor accepts primary parity. Artifact
12468378270 SHA-256:
0523468bab22ae7768af2d631e53758d4de5c0045cd11fa431546341c504a75e.
Full candidate primary/supplemental observations remain required and preserved.
