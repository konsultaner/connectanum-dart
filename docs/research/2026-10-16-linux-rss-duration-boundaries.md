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

## Following Linux observations

Source `25862a53` passes frozen full `bin/verify` with all 3,098 inputs and HEAD
unchanged. Its 90-row Linux campaign has 180 independently validated allocation
observations and valid RSS/duration/sample boundaries, but numerical parity fails.

The concrete word writer at `5dda2ecd` reduces Linux CPU ratios to
1.1590 / 1.1782 / 1.1633. Native-buffer allocation remains 1.0634. All 120 renewed
copy cases and 170 audited five-platform consumer checks pass; `bin/test-fast`
and focused VM/JavaScript/Wasm ownership regressions pass. Full verification of
the writer remains required. No primary acceptance is claimed.

One MessagePack client endpoint in the following 90-row diagnostic is null for
the lifetime maximum, with live/sampled peak 414,035,968 bytes. The rejected raw
maximum was not retained, so its exact cause is unproven. Linux documents
[asynchronous, approximate RSS accounting](https://www.kernel.org/doc/html/v6.10/filesystems/proc.html)
and labels both [VmRSS and VmHWM inaccurate](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html).
This supports handling transient inconsistent readings; it does not justify
inventing an upward maximum or accepting a missing value.

The sampler now rereads only a positive below-peak maximum, up to three actual
reads total, with an event-loop turn between attempts. Equal maxima, missing
values, exceptions and invalid values stop immediately. Persistent contradiction
remains null. All attempted readings survive Dart/Rust report serialization.
Two deterministic regressions fail before this change and pass afterward;
an equality/exception test rejects the advisory review's two control-flow claims.
All 30 focused Dart and 32 Rust library / 139 Rust driver cases pass. Budgets,
sample windows and 50 ms sampling remain unchanged.

The comparison also labels application-byte totals as `wire_bytes`. Actual
encoded WAMP message volume still needs a separate measured boundary; renaming
logical bytes alone cannot satisfy the encoded-size reporting requirement.
