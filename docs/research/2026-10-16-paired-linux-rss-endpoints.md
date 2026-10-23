# Paired Linux RSS endpoints

The strict Linux diagnostic on `c15f2185` completes 90 rows and validates all 180
allocation observations. It fails performance gates and also retains one
unavailable client lifetime-RSS value. That row reports current/sample-peak RSS
of 339,804,160 bytes, followed by three actual `VmHWM` readings of 339,664,896.
The former collector correctly refuses to invent a maximum from its live sample.
`split-rss-endpoint-minimal-repro.json` reproduces that unavailable result.

The runner uses Linux 6.17. Upstream
[`task_mem()` in Linux v6.17](https://github.com/torvalds/linux/blob/v6.17/fs/proc/task_mmu.c#L34-L65)
computes the two reported fields from a shared local RSS total and emits them
together. Its comment also warns that accounting snapshots can be inconsistent.
Reading current RSS and then HWM from different status snapshots discards this
useful pairing. The retained row does not contain the original status texts, so
it does not establish which intervening accounting update caused the discrepancy.

The default final sample now reads `/proc/PID/status` once for current RSS and
the first HWM candidate. The existing bounded retries still use actual HWM
readings, and the candidate must still cover every earlier sampled RSS peak.
Missing, invalid or failed endpoints remain unavailable. A failed final read
cannot reuse a prior current-RSS value. No maximum is derived from current RSS,
retained from an earlier HWM, or substituted from the SDK. Legacy injected readers
retain their existing behavior; a joint endpoint override is available for tests.

All 32 metrics tests pass, including 26 RSS cases. They cover coherent/equal
endpoints, a larger HWM without promoting the sampled peak, active-read ordering,
missing processes, an earlier peak greater than the final HWM, bounded actual
rereads, invalid counts, endpoint failures and mixed reader overrides. Analysis
finds no issues in the changed files. The old contradictory observation remains
unavailable and is not rewritten as passing evidence.

This is a measurement reliability repair. OS counters remain reported
observations, and resulting-source Linux evidence is still required. None of the
48 primary cases, codec comparisons, sample/duration floors, performance budgets
or copy gates changes.
