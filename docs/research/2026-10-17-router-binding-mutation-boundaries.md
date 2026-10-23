# Router metadata parser mutation boundaries

The full hosted CI run on `b8e2a0ac` fails the router-message-binding mutation
gate: 94.5904173106646% against the unchanged 95% assertion requirement.
Its complete two-shard union contains 816 mutants: 621 killed, 169 compile
errors and 26 survivors. Nine kills contain only test errors; those do not count
as matcher assertions. No threshold, source selection or equivalence changes.

New regression cases cover valid ASCII DEL (127), a final two-byte zero CBOR
text length, binary keys whose bytes match known text keys, and unsupported
additional-length values 26–31 with matching apparent character data. Fast
metadata binding must avoid a lazy loader for fully represented valid inputs
and reject malformed dictionaries at binding time. A separate public binding
case verifies that validated metadata works without an available raw frame.

Exact source-restored replays now kill four formerly surviving mutations with
completed reporter output and real matcher failures: `31ed2501884ff454a739`,
`e0fd6bb35b4e2381eaac`, `cbc0b38a2181258f8189`, `b421c4271b090c48e9f0`.
The restored baseline passes. Evidence: `router-mutation-boundary-replay/audit.json`
under the managed worktree's `out/flatbuffers-milestone-finish`.
A subsequent attempt to kill `7ad86d7df8c4660300ad` does not kill it: its
constant expression is 1 shifted by zero, so both shift directions equal one.
That attempt is preserved as a failure, not reported as a kill or full gate.
No equivalence exemption is added. Full resulting-source mutation CI is pending.

The preceding `b8e2a0ac` passes frozen full `bin/verify` and all production
copy/volume probes: 300 short supplemental rows, 120 accounting cases and 36
progressive combinations, with all 3,126 inputs unchanged. All 190 production
consumers pass on five platforms with archive/library/manifest/log hash audits.
These correctness checks are separate from performance acceptance.

Its strict 90-row diagnostic fails parity (CPU 1.0098 / 1.0037 / 1.0046),
with all allocation comparisons passing and additional latency/throughput/GC/RSS
failures. Complete primary run 38982148476 and supplemental run 38982150588
are now executing the unchanged 48-case/1,440-row and 50-case/1,500-row matrices.
The supplemental payload-size shard stops after 192/360 rows with an HTTP
workload timeout in `ext_18_payload_sizes_flatbuffers`; the worker-stopped warning
occurs during teardown. Root cause is under investigation; no crash, OOM,
acceptance or omitted-case waiver is inferred from that warning.
