# MQTT broker CPU measurement calibration

The existing Linux MQTT gate reads cumulative `utime` and `stime` from
`/proc/PID/stat` and divides their sum by `SC_CLK_TCK`. Those fields are reported
in clock ticks, as specified by the
[Linux process-stat documentation](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html).
Before/after subtraction therefore retains tick quantization. This matters when
the reference broker uses only a fraction of a second of CPU.

For example, the preserved
[Intel 8370C result](mqtt-hosted-pr128-2dea8b8e.json) reports median broker CPU
times of 0.84 seconds for Connectanum and 0.20 seconds for Mosquitto: a 4.200 ratio
against the unchanged 4.000 cap. Quantization could affect a borderline decision;
this observation does **not** establish that the recorded failure was incorrect.

Linux also provides a process CPU clock through
[`clock_getcpuclockid(pid)`](https://man7.org/linux/man-pages/man3/clock_getcpuclockid.3.html).
The API returns the clock identifier for the selected process, or a positive
error number. Reading that identifier with `clock_gettime` measures process CPU
time; the process clock includes all threads, rather than just the caller's
thread. See the
[process-clock definition](https://man7.org/linux/man-pages/man3/clock_gettime.3.html).
The clock's reported resolution and its observed increments need calibration;
nanosecond units alone do not prove nanosecond accuracy.

The isolated [calibration run](https://github.com/konsultaner/connectanum-dart/actions/runs/40953523674)
uses source `71de3faca421fe3862923de3fafda2b0c47f1f19` on
`codex/mqtt-cpu-clock-proof`. It starts a child process and compares both CPU
counters around 30 short workloads. Each workload runs in a new thread that
exits before measurement, checking that its CPU time remains included. The probe
also checks the error returned for the reaped child and records every sample,
CPU model, clock resolution and tick frequency.

This is a diagnostic, and its results must be inspected before drawing any
conclusion. It changes no MQTT workload, source, budget or gate. A timer
calibration is not a matched MQTT measurement and cannot clear the Intel cap.
Any proposed measurement change still needs side-by-side live broker evidence,
unchanged numeric limits, complete raw results and full gate coverage.

## Observed calibration

The completed run used an actual EPYC 7763 host. The [complete results](mqtt-cpu-clock-calibration-40953523674.json)
retain all 30 samples. This confirms that the process clock exposes increments
smaller than the proc-stat tick; it does not establish a misclassified MQTT gate.

| Measurement | Result |
| --- | ---: |
| Proc-stat tick size | 10 ms (100 ticks/s) |
| Process-clock reported resolution | 1 ns |
| Median process CPU per workload | 5.201 ms |
| Workloads reporting zero proc-stat CPU | 15 of 30 |
| Largest absolute difference between counters | 5.377 ms |
| Exited worker threads remain accounted | Pass |
| Reaped child reports ESRCH | Pass |

The MQTT gate still uses its original counter and numeric limits. A live,
side-by-side broker measurement remains necessary before changing that method.
