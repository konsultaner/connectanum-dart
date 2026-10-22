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
