# Native perf session lifecycle preparation (2026-11-03)

The helper/auditor/controller source now implements a private named listener,
post-privilege helper connection, source-bundle handshake, same-PID pinned ELF
exec, direct sampler identity/FD audit transport and two-phase enable/ACK/marker/
GO lifecycle. **22 owned unprivileged POSIX/synthetic fixtures pass.** They use
exec callbacks and synthetic credentials/process witnesses. No actual Linux,
root, pidfd, ELF exec, perf/kernel, VM API, native benchmark or capture ran.

The owned branch remains HEAD601 with ten uncommitted tools. Production package
and native sources are unchanged. Earlier28/26/35/26 distinct component suites
were not rerun. No runtime candidate was committed/pushed/adopted, strict work
was dispatched or acceptance data retried. The original failed48/50 and alias
regression constraint remain unchanged.

## Executed failures and corrections

The first16 suite had15 passes and one error before an audit report: its fixture
attempted tuple/list concatenation when altering argv. Correcting that fixture
allowed the intended wrong-argv refusal. Three new counterexamples then found
an unverified sampler FD2 log, premature sampler cleanup after a GO/EOF close
error, and secondary evidence-write failure masking the primary refusal.
The19-case before run records two assertion failures and eleven errors: one
primary-error witness and ten separate fixture socket-copy errors. Regular file
bytes and socket-node metadata are now retained separately. The first state fix
introduced one19-case positive-path error; checking the actual two completed
phases instead of the earlier state fixes it, yielding19 passes.

Qualified source review led to three more controls. A low-numbered pinned ELF
already refuses before stdio mapping, and natural driver wait timeout/rearm
controls pass. A stale controller ACK test first hit a different exception class
with a regular FD; a different actual owned pipe then reproduced **enable before
identity refusal**. The existing post-read check already preceded gate admission;
there was no false GO witness. A pre-enable/pre-read check now also refuses the
wrong pipe, yielding22 passes.

The release-attempt state is conservative: complete or partial GO and close
errors may have started the owned driver. Sampler endpoints remain open until
its natural exit is reaped through the controller, including after a bounded
wait times out. No kill, marker reset/reclaim, replacement helper, report retry
or workload retry is introduced. Post-ACK marker creation remains intentional.

## Evidence and limits

[Root assessment and every member hash](2026-11-03-flatbuffers-native-perf-session-assessment.json)
and [exact executed source/log/receipt/fixture evidence](2026-11-03-flatbuffers-native-perf-session-evidence.tar.gz)
retain all seven executed source versions and results. The first16 temporary
fixture tree was cleaned without systematic raw-file retention; its exact
source/log/receipt remain. Later regular fixture files remain; live socket nodes
are represented by metadata, not cloned capabilities. Initial socket-copy errors
and all partially copied files are retained. No claim of complete first16 raw
transcript retention is made.

GLM design/review advice is qualified against source and actual tests. The
low-FD overwrite allegation misses an existing refusal; the cleanup-state
allegation does not establish a defect; bool-timeout advice self-retracts.
Only the narrower ACK ordering concern is adopted after a real failing witness.
Two reachable Qwen requests hit token limits without saved final advice; this
is not backend unavailability or approval. All sessions are complete/reaped.

The implementation is not a ready capture tool. Actual loaded role/native-image
records, complete capture admission/provenance and natural sampler completion,
new-tool full canonical verification/source/locks/generated configs/native/
staticRLIB archive, qualified final admission review and immutable declaration
remain required. Real bounded owned **non-benchmark** Linux credential/access/
pidfd/FDexec/inheritance/arming controls must precede any data. UID0 and synthetic
procfs/peer claims do not prove capability; child enumeration is supporting only.
Driver UID/GID/env, all original workloads/control requests, SDK/GC/allocator/
worker policies, windows, fresh bodies and complete verification remain fixed.

Last fixture free space was17.56GB, above the12GiB full-build floor. No cleanup
occurred; recheck before builds. The earlier exact601 before-edit canonical does
not verify these new tools. Whole-life native samples would not establish managed
allocation stacks, gate-interior CPU, physical RSS, cause or strict acceptance.
[Prior direct handoff](2026-11-03-flatbuffers-native-perf-handoff-preparation.md)
and [frozen source policy](2026-11-02-flatbuffers-601-native-perf-source-policy-binding.json)
remain separate evidence.
