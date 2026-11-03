# Natural sampler completion preparation (2026-11-03)

The session source now waits for the released driver's natural exit, closes its
sampler channels once, then requires both the owned launcher's exit and an
independent actual-sampler pidfd exit before retaining the raw artifact and exit
report. **31 changed-source integration fixtures pass**, including nine new
completion cases. These are owned unprivileged POSIX callbacks/files with
synthetic credentials/process witnesses/pidhandles. No actual Linux/root/pidfd/
ELF exec/perf/kernel/VMAPI/native benchmark/capture ran.

The six new before cases produced one assertion failure (metadata closure was
allowed before sampler natural exit) and five errors for the newly specified
APIs that were not implemented yet. This is not evidence of six production
runtime defects. After implementation those six pass. Three source-review
controls and required caller/cleanup adaptations then yield31 passes. The
historical22 Session proof is preserved unchanged; this new integration run
verifies changed completion states and callers. The distinct28/26/35/26 earlier
component suites were not rerun.

Completion keeps pending state through bounded waits, without relaunch/rearm,
marker reclaim, cancellation or repeated closure of reused FD numbers. A launcher
status alone does not prove actual sampler exit. Nonzero and signed status,
partial raw data and artifact errors remain visible. After process exit, raw
`perf.data` is bounded, opened without following symlinks or blocking on FIFO,
and checked for regular type, owner/mode, identity, size and SHA continuity.
Raw bytes are retained; this does not parse samples or establish coverage/parity.
An existing/partial completion report remains terminal without a second read or
write attempt. The actual process exit permits metadata closure even if that
final report write fails.

Official exclusive admission refused preparation before any source/test/archive
write. The refusal is retained; work resumed only after admission. Small fixtures
used a1GiB floor; last free16.98GB remains above12GiB full-build floor. No cleanup
or new-tool canonical ran. All own model/test processes are complete/reaped.

## Qualified review and evidence

A reachable GLM test request hit its token limit and saved no final advice;
this does not establish unavailability or approval. A later bounded source review
completed. Its signed-status claim identifies a test gap, not mangling in the
actual source. A new owned callback writes synthetic raw bytes and deliberately
self-SIGTERMs: actual POSIX wait-status decoding preserves the negative value.
No benchmark/campaign was cancelled. Its partial-report replay claim misses an
existing terminal entry guard omitted from the selected excerpt. The new actual
partial-write/ENOSPC test passes, preserves the first partial file and observes
one artifact read across a rejected repeat call. No report-written workaround
or retry was adopted. The initial six-test fixture cleanup needed adaptation to
the new sampler-finished state; exact prior sources/logs remain, and the final
explicit metadata-FD closure control passes.

[Root assessment, all source hashes and qualifications](2026-11-03-flatbuffers-native-perf-completion-assessment.json)
and [exact three-version source/log/receipt/fixture evidence](2026-11-03-flatbuffers-native-perf-completion-evidence.tar.gz)
preserve the full new phase. Regular fixture files are byte-exact; symlink and
special socket/FIFO nodes are represented by retained metadata, not cloned live
capabilities. [Earlier session preparation](2026-11-03-flatbuffers-native-perf-session-preparation.md)
remains a distinct historical proof.

The owned HEAD601 branch still has ten uncommitted tools and unchanged production
packages/native. Capture admission/provenance, actual loaded role/native-image
records and complete pre-GO refusal process ownership remain pending. New own
canonical/source/archive/three locks/generated hidden package configs/native/
staticRLIB/tool/kernel provenance, immutable declaration/qualified admission
review and real bounded owned **non-benchmark** Linux credential/access/pidfd/
FDexec/inheritance/arming controls remain mandatory before any diagnostic data.
The old exact601 baseline does not verify these tools. All original SDK/GC/
allocator/worker/window/fresh-body/control policies remain fixed. No source
adoption, new strict dispatch, numerical retry or performance acceptance claim.
