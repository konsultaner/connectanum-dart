# Linux router JIT symbols for CPU diagnosis

The standard Dart Linux VM implements `--generate-perf-events-symbols` and writes
`/tmp/perf-<pid>.map`, containing JIT address, size and function name records.
This enables perf-report symbol resolution; it does not preserve transient code
for perf-annotate. Source: [Dart SDK Linux code observer](https://github.com/dart-lang/sdk/blob/798f73ed5d7abf4b53a2960a2c478ec019b11cc9/runtime/vm/os_linux.cc#L51).

The CPU-only profiler enables that flag on the router when Linux perf is
requested. The client is explicitly unsymbolized. The generated probe captures
the router map while its VM is alive and saves per-PID router/client reports as
well as the existing combined reports. Python checks PID attribution, map
syntax and hashes, and rejects missing, empty, malformed or foreign maps even
when the probe exits successfully. Reused starting addresses are reported.

These snapshots do not guarantee complete stack unwinding or unique JIT address
history. Native/blocking frames in Dart VM samples are not CPU-cycle cost by
themselves. The SDK flag also changes code mapping behavior. Profiles remain
diagnostic; canonical workloads, operations, duration/sample floors and primary
performance acceptance are unchanged. Mock orchestration and malformed-map
tests validate evidence handling, not actual profiling or parity.
