# Blocked launcher preparation for native perf diagnostics

The new blocked-exec component passes26 focused POSIX fork/pipe/exec-callback
fixtures. Four actual before-failing counterexamples are retained and corrected.
This adds a token consumer to the earlier28 guard primitives. The real external
perf attach controller and privileged sampler identity collection are still
missing. No benchmark, actual FD exec, Linux perf/kernel capability probe,
VM profiling RPC or diagnostic capture ran.

The owned worktree remains on `codex/flatbuffers-native-perf-guard`, HEAD601,
with four uncommitted Python tool files. Production package/native sources
remain unchanged. Its previously completed exact601 before-edit verification
is distinct from verification of these new tools; full canonical verification
of the tool source has not started. The published601 runtime remains frozen
and unadopted, and both original strict campaigns remain failed.

[Root readback, exact source hashes and qualified advice](2026-11-03-flatbuffers-native-perf-blocked-exec-assessment.json)
and [all source versions, raw logs, receipts and advisory evidence](2026-11-03-flatbuffers-native-perf-blocked-exec-evidence.tar.gz)
retain this phase. Every archive member decompresses to its original bytes;
original traceback text inside raw logs is preserved. Public references identify
archive members. The local admission receipt has a separate basename projection.

## Executed counterexamples and corrections

The first20 callback fixtures passed. Subsequent review and root inspection
produced four new actual counterexamples: three assertion failures and one
bounded-wait error. Each now passes in the26-fixture suite:

- A raising exec callback lost its primary refusal reason after its READY FD
  closed. The child now writes its refusal to the declared log before trying
  the protocol FD.
- Opening a FIFO consumed marker blocked. A nonblocking open now precedes the
  regular-file/owner/exact-byte checks. The initial hung owned fixture was
  reaped by test cleanup; no campaign was cancelled.
- Set-ID mode bits on the declared image were accepted. They now refuse before
  fork. The test only changes permission bits on an owned non-ELF fixture; no
  privileged image executes and no credential transition occurs.
- Retargeting the declared driver symlink was accepted while the correct old
  image FD stayed pinned. The child now requires the original argv pathname
  to resolve to that inode after GO. The counterexample proves missing path
  drift rejection, not execution of substituted bytes.

Additional controls cover invalid specifications, writable regular logs,
exact token bytes plus EOF, marker corruption/symlinks/directory replacement,
image bytes/path changes, credentials/environment, signal mask, private-FD
closure, timeouts and no Linux FD-exec fallback. Callback fixtures explicitly
simulate close-on-exec; they do not exercise a real executable image or kernel
sampling. One integration fixture uses the actual arming state machine and
real blocked child with a synthetic sampler acknowledgement.

Official exclusive leases covered every test execution. A post-fix admission
refusal preceded all outputs/tests; work waited for availability. The later
readback utility twice failed before writing its archive/assessment because
of log-newline and snapshot-layout assumptions. Both corrections are retained;
no test, data, source or acceptance evidence was rerun to repair those reads.

## Consumer contract and review limits

The child preserves original effective UID/GID, environment hash, argv, cwd
and signal mask. It uses the original session/devnull/log contract and closes
unrelated descriptors before READY. Driver bytes are pinned and checked before
READY and after GO. Real mode requires Linux FD exec and an ELF image, without
a path-exec fallback. GO requires exact declaration hash/nonce bytes and EOF.
The controller closes its writer after the complete token; holding it open
causes an intentional bounded refusal. Existing/partial consumed markers remain
terminal. Marker creation between READY and GO is the intended post-ACK step.

GLM test advice and source review completed and were qualified by root against
the source and executed counterexamples. Its close-before-GO advice is rejected;
EOF follows the complete token. The framing concern self-retracted, and the
bounded EOF wait and intended post-ACK marker creation are not defects. The
primary-error concern is accepted with the actual closed-FD behavior established
by the test. These advisory outputs do not approve a capture.

## Remaining work

Implement actual sampler discovery, process/image/lineage/private-FD witnesses
and the external attach controller. The driver must remain at its original
unprivileged UID/GID/environment; privileged perf attaches to the blocked PID.
Do not treat a sudo launcher PID as the actual recorder. Sampler control/ACK
pipes must remain distinct from workload streams, regardless of numeric FDs.

The [frozen source-policy binding](2026-11-02-flatbuffers-601-native-perf-source-policy-binding.json)
still filters the original full48 schedule into all six focal variants plus
all five original RSS passing controls, preserving codec order and all proposed
330 reports. Selection followed original results; only a future declaration
can precede new diagnostic data. All original failures remain retained.

Observed free space recovered to20.23GB at the final fixture execution, above
the12GiB full-build preparation floor. No own cleanup occurred and the cause
of recovery was not measured. Small fixtures used their separate1GiB floor.
Full verification remains pending controller completion, own source/native/
driver/archive/locks/generated-config/staticRLIB/tool provenance, meaningful
guards, qualified review, an immutable declaration and bounded real Linux perf
controls over owned non-benchmark processes before data.

There is no new production defect, RAM cause or performance result. Whole-life
native instruction samples would include startup/warmups/observers/cleanup;
they cannot prove managed allocation stacks, gate-interior CPU, per-operation
allocation volume, physical RSS, causal repair or strict acceptance.
