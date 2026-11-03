# Indexed partial auxiliary waits stay inside the retained worker

A new source component lets a failed, uninitialized preparation owner continue
a bounded wait on one retained auxiliary. It addresses the boundary established
by the earlier fault fixture: a constructor Thread can join while an auxiliary
child remains alive, and the ordinary initialized-producer wait refuses.
The new component remains uncommitted and unadmitted; it is not a production
RAM repair or a complete preflight controller.

The public call takes an exact nonnegative integer index and the existing
bounded timeout. It uses the same scheduler busy, real-worker-join and settled
start guards as other phases. Only a failed, uninitialized registered owner is
eligible. The worker alone inspects partial producer fields. A recipe child,
missing fields or unknown state refuses; the observer never reads partial
producer state or raw descriptors.

The worker retains a tuple of exact auxiliary handles before choosing an
index. It checks identity before and after waiting on that same selected
auxiliary. Detected ledger drift permanently quarantines this continuation.
These are bounded observations, not atomic identity, external-write prevention
or authentication. Unknown or nonselected actors do not become absence or
closure proof.

Selected observations contain immutable cached scalars: index, PID, nullable
direct status, pending/finished, two EOF fields and observation stage. A
terminal observation only refuses another wait; it grants no actor closure
or physical lease-release authority. No new source audit, recipe, SDK command,
restart, cancellation, state reset or terminal publication retry is introduced.

The original constructor exception stays privately retained. A later wait
exception and an observation error also remain exact private objects, with
only their types published in the call record. An additional guard catches
a custom exception add_note hook being invoked while preserving an observation
failure. The correction retains that secondary privately instead of invoking
an arbitrary exception hook. This is a source blocking/primary-loss regression;
no actual hang duration or RAM impact is measured.

Eight new guard tests initially produce fifteen errors solely because the
new API is absent. Eight invalid-argument subtests account for the seven
additional errors. These are not fifteen production defects or teardown
failures. The initial implementation passes sixteen selected guards: eight
new partial-auxiliary tests, five current emitter callers and three required
owner callers. The new exception-hook guard then fails separately. After
correction, two selected guards pass separately. A further concurrent-caller
guard passes once, with the implementation unchanged. This is not a combined
nineteen-test run or full final canonical verification.

The tests use fresh finite owned Python children and actual auxiliary
machinery, with a mocked source guard and one declared wait escape. Actual
producer provenance remains fixture; source/archive placeholders are not
canonical provenance. Known fixture workers and children naturally complete
under root's actual exclusive lease. Unit callbacks remain synthetic.
Fixture-only direct teardown waits preserve known children even for before
failures; they are not live continuation or admission workarounds. Selected
before/after lifecycle views, raw streams and direct known actor outcomes are
retained. Existing required caller Git setup returns are not all separately
serialized. Earlier actual Darwin/Linux methods are not rerun or relabeled
as current-source execution admission.

Original module-level functions, factories, emitter bodies and gates, all
original test classes, the original registration/error/ordinary-wait/emission
methods, the other eighteen tools and selected three verification scripts
remain byteexact. Only the producer/test pair changes. Production601 is
unchanged. All twenty tools remain uncommitted, uncanonical and unadmitted.

The design, test planning, failure clustering and selected-diff review requests
all complete with direct status zero. Their advice remains advisory. Root
rejects the alleged setup-busy gap: busy is set before Thread creation, and
unjoined/uncertain workers remain blocked. Root also rejects a lock as global
ledger-mutation protection, extra auxiliary locks for unsupported external
raw callers, snapshot mutability claims, owner-history eviction and exception
chaining that invokes arbitrary hooks. Root accepts and runs a deterministic
concurrent-caller guard. The model reviews the current implementation before
that last test addition; root checks the final test and complete affected
methods, without claiming model-final-current full-source approval.

Actor ownership remains unknown, initialized remains false, and capture,
source-admission and live-admission flags remain false after auxiliary
completion. The caller must physically retain the official exclusive lease
through every known actor. Recipe actors, unknown partial starts, complete
current own canonical/source/native/driver/RLIB/locks/configs/SDK/compiler/
tool/kernel provenance, original-host controls and immutable complete admission
remain further work. The live provider is absent, admission always refuses
and the live controller stays closed.

Observed space is about10.5GB, below the unchanged12GiB build floor. No cleanup
occurs; space-change cause is unmeasured. No canonical/native build, original
kernel target, broker, benchmark, capture or strict dispatch occurs. No RAM
cause, causal repair or performance acceptance is established. PR #132 remains
open and draft; issue #103 and its milestone remain open.
