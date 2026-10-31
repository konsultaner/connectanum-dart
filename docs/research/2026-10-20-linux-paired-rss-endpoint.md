# Preserve Linux's reported RSS endpoint independently of sampled peaks

Issue [#103](https://github.com/konsultaner/connectanum-dart/issues/103) requires
measured RSS evidence and unchanged performance parity. This correction repairs
endpoint availability; it does not reduce the sampled RSS metric or its budget.

## Contract and observed failure

Linux 6.17's [`task_mem`](https://github.com/torvalds/linux/blob/v6.17/fs/proc/task_mmu.c#L37-L72)
computes `VmRSS` from `total_rss` and `VmHWM` from the larger of that same value
and the cached high-water counter. The paired status read therefore supplies
its own consistency bound. The kernel's
[`proc` documentation](https://docs.kernel.org/6.17/filesystems/proc.html)
describes RSS accounting as asynchronous and potentially imprecise. These
observations do not establish a cross-time ordering between the reported HWM
and every earlier RSS sample.

The retained encrypted-progressive artifact for source
`b8e2a0acd50b41b50f87442a3c5ba5c7573153d8` contains three measured CBOR client
examples, in bytes:

| Row | Sampled peak | Paired final RSS | Reported HWM |
| --- | ---: | ---: | ---: |
| ext_49 measured 3 | 282476544 | 269946880 | 282193920 |
| ext_49 measured 4 | 282460160 | 273375232 | 282193920 |
| ext_48 measured 4 | 283693056 | 271732736 | 283324416 |

Each HWM covers its paired final RSS. The old collector nevertheless discarded
it after three identical actual observations because it was below the earlier
sampled peak. The runner reports Linux `6.17.0-1022-azure`, image
`ubuntu24/20261012.334.1`. The cited upstream source matches its major/minor
version; Azure's downstream patches were not separately audited. The original
archive SHA-256 is
`6f160b76308cd72c6b7eead2b22510daa8393ca7dd3ff39bcb1a5755282aaa31`.
Historical failed artifacts remain failed and are not rewritten.

## Correction and unchanged safeguards

For a paired endpoint, validate the actual HWM against that endpoint's final
RSS. Preserve the historical sampled peak separately and never clamp either
value. Custom independent readers retain their previous conservative check
against the historical peak. Bounded retries still retain every actual HWM
observation; missing, nonpositive, unsafe, contradictory and failed endpoint
reads remain unavailable. Stop still waits for an in-flight sample and captures
the final current value before retrying.

The independent campaign comparator already checks HWM against final RSS. Its
RSS parity metric continues to sum the client/server sampled peaks. No
production comparator algorithm, policy file, sample/duration floor, scenario,
copy requirement, point estimate or confidence bound changes.

## Verification and limits

Before the production edit, all three captured-value regressions fail because
the collector returns null instead of the reported HWM. After the edit, all
36 collector tests and 46 comparator tests pass. Cases cover HWM equal to the
paired final RSS, HWM below a historical peak, contradictory values and retries,
unavailable endpoints, independent-reader compatibility, and preservation of
the sampled metric. A comparator regression deliberately increases sampled RSS
while leaving a lower valid HWM: the unchanged parity gate still fails.

Logs and local advisory reviews are retained under
`out/flatbuffers-resume-20261020/`. Fresh hosted observations and full verification
of this correction remain required. The preceding integrated source `9e964951`
passes canonical `bin/verify` with all 3,153 source inputs and resolved locks
unchanged. Its earlier lifecycle-timeout attempt is retained as failed; three
isolated reruns and the quiet full rerun pass without deadline changes. Neither
that verification nor this measurement correction establishes performance
parity or closes #103.
