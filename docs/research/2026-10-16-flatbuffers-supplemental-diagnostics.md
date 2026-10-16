# FlatBuffers supplemental diagnostics

Issue: [#103](https://github.com/konsultaner/connectanum-dart/issues/103).

The primary acceptance inventory remains 48 cases, comparing all three codecs
for 3 warmups and 7 paired repetitions, each at least 10 seconds and 1,000 actual
samples. All checked-in throughput, latency, CPU, allocation, GC and RSS point
and confidence budgets remain unchanged. Sixteen native buffer/span cases now
explicitly require zero observed optimized payload copies; omitting a declaration
or observing a nonzero count fails the comparison.

## Supplemental inventory

`flatbuffers_extensions_v1` contains 42 cases, each paired across CBOR,
MessagePack and FlatBuffers: 1,260 total rows with the same run minima.

| Group | Cases | Coverage |
|---|---:|---|
| Small control operations | 8 | Publish acknowledgement, subscribe, register and cancellation; RawSocket clear and WebSocket TLS |
| Payload sizes | 12 | 10 KiB, 100 KiB and 1 MiB; Dart/native clients on both representative transports |
| Fan-out | 2 | Eight native subscribers on both representative transports |
| Progressive RPC | 4 | Dart/native clients on both representative transports |
| Mixed codecs | 6 | JSON/MessagePack/CBOR peers on both representative transports |
| Encrypted PPT | 8 | XSalsa20-Poly1305/AES-256-GCM; CBOR/FlatBuffers PPT on both representative transports |
| Fragmented WebSocket | 2 | Native masked 1,024-byte fragments with cleartext/TLS |

Control and progressive rows use the ordinary envelope/CBOR-argument path;
unsupported typed progressive payloads are not substituted or silently omitted.
Encrypted rows explicitly label the encrypted PPT serializer and create a matching application callee for each envelope codec. The control echo handler has no encryption provider and is not a valid encrypted application endpoint. Other rows use
the typed benchmark payload with the codec's matching PPT serializer. Human
reports retain these configurations, all per-codec resource/copy observations,
and actual accepted serialized bytes per operation, separately from logical
application bytes and transport framing.

Zero-payload controls report operations per second, not a meaningless ratio of
zero application Mbps. Supplemental numeric costs remain visible per case and
are descriptive diagnostics; they cannot establish primary acceptance. Missing
process, allocation, copy, encoded-volume or configuration evidence still fails.
Only a complete strict inventory with the pinned policy and unchanged inputs can
produce `diagnostic_complete`; it never produces primary `passed` acceptance.
The existing release comparator's primary acceptance behavior remains intact.

## Stable workers and duration support

Both the Dart workload runner and Rust driver previously rejected timed control
and progressive modes. The parent also discarded every successful helper outside
RPC/pub-sub, despite the child runtime already supporting serialized commands.
Five Dart duration cases, five parent PID cases and a Rust configuration case
first fail on these restrictions. The supported mode set now includes progressive
RPC and the four control cycles, using the existing real-operation scheduler.
Regressions require actual sample-window duration, contiguous operation identities
and empty registrations/subscriptions after cleanup.

Worker reuse remains opt-in. Failures always discard and reap the generation;
unsupported modes and default callers retain recycling. Both RPC and cancellation
failure recovery are covered. A preceding direct real-worker probe executes 370
mixed commands on one PID and exits normally; this is correctness evidence,
not benchmark timing or sufficient proof of the resulting parent path.

The new workflow mode `flatbuffers_extensions` runs the full declared inventory
on Linux and retains the complete inputs, source/artifact hashes, raw reports,
comparison JSON and Markdown. Its minimums do not change the primary policy.
Current-source live short proof, full verification and hosted results are pending.
The latest verified primary diagnostic still fails CPU and native-buffer
allocation parity; #103 and the milestone remain open.

The first short driver run stops after 18 rows on an encrypted RPC fixture
without that application callee. An isolated native MessagePack/WebSocket/TLS
AES-GCM + FlatBuffers PPT reproducer returns HTTP 500 with the control echo and
HTTP 200 with six verified samples after selecting the matching application
callee. The generated TOML regression fails first on the missing peer and now
requires it. This corrects the diagnostic setup; it is not a product crypto fix.
The failed run retains all 3,111 inputs unchanged and is not acceptance evidence.

## Renewed live correctness proof

After correcting the encrypted callee setup, the real Rust driver completes all
252 rows (one short warmup and one short measured pass) with one client PID and
one server PID. All 3,111 inputs and HEAD remain unchanged. Independent checking
verifies every declared configuration, at least four samples and 50 ms of actual
samples, all 252 encoded-volume sums, 48 encrypted/native-crypto pipelines,
28 active mixed transcodes and 32 zero-copy assertions. Homogeneous rows retain
explicit not-applicable transcode observations. The strict comparator rejects
these deliberately short settings. This is not performance acceptance.

## CPU profiling for the remaining regression

`tool/profile_wamp_serializers.py` samples the three codecs on warmed native
RawSocket cleartext 64 KiB buffer-construction RPC. It retains full HTTP reports,
Dart CPU sample tables, source and native-library hashes, process identities and
teardown evidence. Sampling must fit inside the actual observed operation sample
window. It shares the campaign host lease, detects Linux build/test/mutation
interference and rejects changed source or native libraries. Missing Linux
interference detection or native perf on other hosts is explicitly labelled.

The manual `flatbuffers_profile` workflow adds Linux perf captures and native
frame pointers/debug information. It retains the raw perf data and inclusive/leaf
reports beside the Dart sample tables. Such instrumentation alters execution;
these are hotspot diagnostics and never primary parity evidence. Native perf can
leave Dart JIT addresses unresolved, so Dart CPU samples remain separate.
The local three-codec smoke passes with distinct PIDs, unchanged inputs and full
process-group cleanup; native perf is explicitly unmeasured there. Linux capture
and the complete resulting-source verification remain pending.

The profiling invocation follows the Linux [perf record manual](https://man7.org/linux/man-pages/man1/perf-record.1.html)
for PID selection, software CPU-clock events and DWARF call chains. The workflow
installs Ubuntu's `linux-tools-generic` package and selects its actual executable,
avoiding a wrapper tied to the hosted kernel version. No SDK fork is required.

Focused checks pass: 139 Rust driver cases, 117 Dart workload/lifecycle cases,
43 comparator cases, 22 campaign/profiler-guard cases and eight synthetic
copy-evidence cases. Static analysis has only the existing informational lints;
all 154 equivalent-mutation proofs validate. The final local profiler smoke
checks that all three sampling intervals fit entirely inside real operation
windows, native/source hashes remain unchanged, and the process group stops.

## Resulting-source verification and Linux capture setup

Source `8f6f86f5` passes frozen full `bin/verify`, including JavaScript and
WebAssembly, with all 3,112 inputs unchanged. The only later application-test
change gives the preparation unit an explicit synthetic metadata root and three
lockfiles; it no longer depends on an ignored local native/bench/Cargo.lock.
All 22 campaign/profiler-guard cases and the corrected hosted Fast Checks pass.

Linux setup uses Python executable discovery because the hosted runner does not
have ripgrep. Perf files are returned to the runner's ownership before upload;
the first successful capture's upload failed because root-created files were
unreadable by the artifact action. The renewed upload retains all failed evidence.

The next capture correctly fails its sampling-window guard: collection ends
0.7507 seconds after the 15-second observed MessagePack operation window. Source,
library and process-group checks pass, with no interfering jobs. The diagnostic
operation window is now 30 seconds, retaining the same actual-window check and
five-second perf capture. This changes no primary or supplemental acceptance
minimum, repetition or numerical budget. A fresh Linux capture is required.
