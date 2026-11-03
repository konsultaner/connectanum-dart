# Source-frozen command producer preparation (2026-11-03)

The new producer passes **23 OWN non-benchmark cases** using tiny committed Git
repositories and finite Python children. No actual new-tool canonical, native
build, Linux/root/perf/kernel/VM/benchmark or diagnostic capture ran. Fixed recipe
factories are source plus mocked argv observations, not executed builds.

It reserves a new terminal run directory before commands, checks clean committed
source and runtime paths, validates the predeclared source archive digest and
all committed blob/type/mode entries, pins input hashes and records actual
child argv/cwd/logs/signed exit/spawn failures. Source/inputs recheck after natural
exit. Log/archive hashes stream in bounded chunks. Existing/partial evidence
remains terminal; no overwrite/retry/reclaim or process cancellation is used.

Four actual tool counterexamples are fixed: a post-spawn journal fault lost the
waitable handle, wait budgets restarted across commands, full logs loaded into
memory, and a known natural exit status was not recorded before uncertain log
closure. Post-spawn faults now retain the owned pending child and deferred error;
no following command runs. The per-call remaining budget decreases, and status
precedes close. The first failing finite child was naturally reaped through its
retained known handle by explicitly labelled fixture teardown. That is not a live
controller workaround or a campaign cancellation.

The initial missing-module error is feature absence. The first17 cases had two
fixture assertion mistakes (two committed files, and already-terminal spawn
failure); those corrections are distinguished from source fixes. Before-failing
20-case and separate close-status evidence, every source version/log/receipt and
regular fixture byte are retained. Symlink nodes are described as metadata.
[Root assessment and every member hash](2026-11-03-flatbuffers-native-perf-build-producer-assessment.json),
[exact source/log/receipt/fixture/advice archive](2026-11-03-flatbuffers-native-perf-build-producer-evidence.tar.gz).

The first GLM source review reached its token limit without a final assessment.
A later bounded review completed but its constructor/spawn claim is false:
actual retained spawn failure is terminal failed/null, with no conflicting
failure.json. Event writes already flush and fsync. No deletion or retry advice
was adopted. Bounded continuation waits are intentional; there is no cumulative
cancellation policy. Advice is not approval. The initial unsupported helper CLI
option failed before any backend request, and its corrected invocation is retained.

Outputs are explicitly **command evidence only**, with capture_ready=false. They
are not the completed canonical/production receipts required by input admission.
Actual SDK/tool identity, full verification breadth, original-worktree source/
archive/native/driver/RLIB/generated configs, descendant cleanup/log completeness,
loaded-role/native-image association and Linux capability remain unproved. A
waited direct child/file snapshot does not establish these facts or physical RAM
cause. Inherited environment values are not copied into metadata; child output
is retained and is not promised universally secret-free.

Owned HEAD601 now has fourteen uncommitted tools; production packages/native
remain unchanged. Helper bundle12 is unchanged because this producer is outside
its dependencies; the future own source census must bind all14. Prior guard and
Session proofs were not rerun. Last free21.29GB exceeds12GiB;
no cleanup/new-tool canonical/strict dispatch or runtime adoption. Both original
strict campaigns stay failed, PR132 draft. Complete trusted receipt production,
immutable admission, actual role/image association and appropriate own canonical/
provenance plus bounded real Linux non-benchmark controls before diagnostic data.
