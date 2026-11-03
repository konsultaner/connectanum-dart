# Owned emitter call signature repaired; live admission remains closed

The retained preflight worker passed two arguments to both emitter interfaces.
The real `emit_receipt(run)` takes one argument and derives phase from producer
provenance; `emit_fixture_receipt(run, phase)` takes two. The non-fixture branch
would raise `TypeError` before producing an own receipt. No actual canonical
build or real emission reached that branch in this investigation.

The worker now preserves each interface's argument count. Public emission also
rejects a canonical/production phase mismatch before scheduling or consuming
the owner's terminal attempt. Existing synchronous factories, real and fixture
emitter wrappers, receipt/source audits, output predicates and other owner
methods remain byte-for-byte unchanged.

Five new boundary tests initially produce four failures and one pass: the two
one-argument interfaces fail with actual Python argument errors, both wrong
phases miss synchronous refusal, and the fixture two-argument branch passes.
After the fix, eight selected tests pass: five new boundary guards and three
required existing ownership/emission callers.

A final explanatory comment and actual-signature `autospec` mocks strengthen
future signature-drift coverage. The same selected eight pass at this final
epoch, never combined16 or fullcanonical. All source epochs and failures remain
in the [evidence](2026-11-03-flatbuffers-native-perf-owned-emission-dispatch-evidence.tar.gz);
the [root assessment](2026-11-03-flatbuffers-native-perf-owned-emission-dispatch-assessment.json)
states the exact scope and limits.

The tests MOCK the selected canonical/production factory interfaces to delegate
to finite OWN fixture construction. Every actual producer keeps fixture
provenance; nothing is retagged. Emitters are mocked against their actual
one/two-argument signatures and return fixture-interface-only data. No valid
own receipt or input-receipt file is created, and no actual canonical/production
factory, native build, SDK, original-host control, benchmark or capture runs.
Existing fixture Git setup API returns are not all separately serialized.

Gemma's new census/declaration summary and Qwen test advice complete and are
qualified against source. Root rejects advice to retag fixture provenance.
Qwen reviews the behavioral fix before the final comment/autospec changes;
root checks those final changes and complete affected methods/tests.
Its phase-test concern retracts itself: the actual before failures show those
tests catch permissive behavior. No optional/unified emitter API is introduced,
and no performance overhead is measured.

Only the producer/test pair changes; the other eighteen tools, production601
and selected verification scripts remain unchanged. All twenty tools stay
uncommitted, uncanonical and unadmitted. Earlier Darwin lease cases stay bound
to their historical source epoch and do not prove current emitter execution.
No earlier suite, actual method case, review or numerical campaign is rerun
unchanged.

Available space is about8.7GB, below the unchanged12GiB build floor; no cleanup
occurs and space-change cause remains unmeasured. Full independent orchestration,
current own canonical/source archive/native/driver/RLIB/locks/configs/SDK/
compiler/tool/kernel provenance, original-host controls and immutable complete
admission remain required. Live provider, admission and controller stay closed.
No RAM cause, repair or strict acceptance is established. PR #132 remains open
and draft; issue #103 and its milestone remain open.
