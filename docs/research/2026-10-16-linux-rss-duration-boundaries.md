# Linux RSS and minimum-duration boundaries

The 90-row hosted diagnostic at `249e0c8a` completes real 10-second windows,
three warmups and seven paired repetitions, but fails performance acceptance.
It also reproduces two measurement defects. No historical result is rewritten.

The child emits `ProcessInfo.maxRss` before the supervisor takes its final RSS
sample. One native row reports a later live RSS of 334,946,304 bytes against an
earlier lifetime maximum of 324,538,368. The supervisor now reads Linux
`/proc/<pid>/status` `VmHWM` after awaiting the active sample and the final
`VmRSS` read. The same PID supplies the observations. Missing, failed,
out-of-range or contradictory final readings stay unavailable. The 50 ms
sampled window peak remains separate; no maximum is inferred upward from it.
Server reports use the same end boundary. Non-Linux diagnostics retain their
existing process observations and remain ineligible for primary acceptance.

RSS endpoints can now remain null through both Dart and Rust reports without
losing CPU, allocation or GC observations. The driver previously rejects such
reports with `invalid type: null, expected u64`; a fail-first regression retains
the other measurements after repair. Missing endpoints produce no zero-valued
Prometheus series. Client output adds explicit lifetime-maximum and sampled
window-peak labels, while preserving the legacy lifetime `kind=peak` series.
The paired RSS gate still uses summed sampled window peaks.

The duration scheduler previously tests only its own stopwatch. That can expire
before the completed samples cover the required interval. A deterministic
regression pauses completion logging for 80 ms: the old scheduler accepts a
30 ms workload with only 2.578 ms of sample coverage. The repair schedules
additional real operations until both elapsed time and the actual sample span
reach the unchanged minimum. Invalid sample timing fails closed. No padding,
synthetic timestamps or numeric tolerance is introduced.

All 139 Rust driver tests, 31 Rust library/artifact tests, 93 focused Dart tests,
35 comparison tests and analysis pass. Mutation preflight retains all 154 proofs.
The earlier new-metadata-test inventory omission is repaired in all four
serializer mutation targets and the shared suite; all 87 script checks pass.
Local review and the bounded GLM judge find no confirmed boundary defect.
Unexpected programmer errors still propagate instead of becoming valid numbers.
Resulting-source full verification and new hosted evidence remain required.

The following `188d33cd` hosted diagnostic still fails: CPU ratios are
1.3392 / 1.2398 / 1.3218 and allocation ratios 0.9618 / 1.0637 / 0.9601 for
managed / native-buffer / pre-encoded construction. CPU sampling on the current
runtime, without allocation tracing, identifies `writeListUint8` as 140 of 578
client CPU samples in its FlatBuffers interval. This is a hotspot observation,
not accepted throughput evidence. All source inputs remain unchanged during
that profile. The next optimization must address that measured cost without
weakening ownership, interoperability or read-only-input behavior.

Every original performance budget, primary case, duration, repetition, sample
minimum, mutation inventory and coverage floor remains in force. The full
campaign must run again after measurement repairs and credible diagnostic parity.
