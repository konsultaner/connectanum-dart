# First-error retention across unknown failure-group acquisition

Producer before711478 is ae1d1affd969a94137b886b20f3aefd231dd2fd4f3d7d95b2fbe382db31f7d79; tests before are0265f84d36016deb2c163c8af09cf0a5578a8f4367462fbca26fb22bda406e7d. Three genuinely new cases execute once before Source edits:2FAIL,1PASS,0ERROR.

## Actual regression

For each failing case, the actual whole original spawn body completes inside ROOT, including a returned native recipe Popen, parent-writer close and durable spawned event. The body returnsNone inside ROOT and ROOT raises the unique original First. The constructor enters its catch. Its actual native failure-group function completes and returns a tuple only inside ROOT; ROOT then raises either RuntimeError or SystemExit before Source receives that tuple.

The original acquisition call sat outside the inner catch, so the later error escaped instead of First. These are two controlled variants of one first-error-priority gap, not two spontaneous native kernel bugs or a measured RAM cause.

The new positive control is an actual pre-spawn input-digest mismatch. Native hashing rejects the declared input, creates a Source ProducerError, and the normal native failure-group returns to Source. Its failure JSON retains that error; no recipe starts. This differs from the earlier post-spawn input-drift and command_spawned-event controls. Earlier6, frozen25PASS2ERROR, old2 bodies, old7 suite and the private pendingTrue2 are not replayed.

## Minimal Source change and validation

Final producer711478e0cb719a7673b1272a5a383a627b2e01ffe9d9310d0dfb66b2358a18c9 wraps only the constructor's acquisition call in try/exceptBaseException and raises its already-known original error if acquisition fails. It does not recover, retry, adopt the ROOT-only tuple, invoke its guard, format errors or proceed to pending/defer/preserve/close work. The actual post-unknown Source getter count remains0.

Both after cases raise the exact original First and retain the original later error in its exception context. Standard Python chaining preserves these objects and traceback information; no fromNone suppression or Source owner-field restoration is introduced. PendingTrue/finishedFalse/failure_attemptedFalse remain metadata data, not liveness or ownership.

Final testsf094b9072feb8248c6d612dce9f42cf8d9f4d08e5722e537e881623fd02788e3 append the exact private three-case harness. The old test prefix is exact. Reversing the acquisition change restores the whole before Source bytes. Only CommandProducer.__init__ changes; the helper body, other existing methods/classes/functions, old auxiliary predicates and owner_emit_attempted remain exact. Other18 helper files and three bin scripts retain hashes.

After selection passes5/5 once: the matching new three cases, input-symlink refusal and mutation of the caller's input dictionary after constructor success. The latter verifies normal constructor/input-snapshot behavior. No Source commit, adoption or canonical aggregate follows.

## Actors, handles and raw limits

Every new case has a new tiny fixture repository with seven native setup Git commands recorded before Popen. Full separate stdout/stderr bytes, sizes, SHA, signed0 and both EOF are retained. These21 setup commands per before/after phase are separate from Source auxiliary/recipe actors.

Native auxiliary and recipe allocation methods retain fully returned original Popen objects and original bound waits before Source publication/I/O. Native pipe creator ends and FileIO handles are recorded before I/O; the recipe read FD comes from its actual creation record. The ROOT-only group tuple is retained as data and never called or adopted. No Source method is invoked on a constructor that supplied no returned owner.

There are six new direct views:3before and3after. Each phase has17 private original-wait rows:6per post-spawn negative case and5Aux/zero recipe for the input control. All statuses are native signed0 and may be cached. Negative cases retain actual40-byte recipe raw output plusEOF, then ROOT closes2pipeFDs/4knownfiles total per phase after evidence/assertions. The input control's known files are already closed by Source and are not reclosed.

Parent after capture has31 original-wait rows, including the same17 new-case actors and14affected-caller actors. Do not add duplicates or treat this as a global actor census. Parent current official Darwin EX identity observations returnNone at6before/10after positions. These finite unit observations, EOF and FD identities do not prove full physical EX, atomic ABA, original Linux credentials, all FD/interpreter/delegate/descendant closure, ownership_complete, go_close_confirmed or runtime admission.

Unexpected failure before view, within ROOT wait/read or before later closes can leave cleanup incomplete or mask errors. No general all-error cleanup/full-reaping claim is made. Missing setup/internal-FD/API/status/error/buffer information is not reconstructed; there is no global PID scan, kill, restart, reset or retry.

## Advisory reviews and independent qualification

Qwen12075 planning completes status0, stdout524bytes, stderr320, both EOF and full answer retained. ROOT corrects its claim that1GiB is a memory fixture: it is a fresh free-disk floor. Original whole_spawn returnsNone; native Popen returns an initialized object. First-error priority over a later SystemExit is deliberate; the unit harness catches BaseException and retains the same known finite actors.

GLM13388 review completes status0, stdout4814, stderr859 and both EOF, full answer retained. Its registry-ID reuse claim contradicts the actual strong owner reference. Clearing an entry removes it rather than retaining a stale collision; arbitrary concurrent registry mutation remains unproved. Writing a secondary error to Source owner fields after unknown acquisition would reintroduce fallible metadata and is not adopted.

Its traceback-loss claim is rejected by actual saved after views: both First contexts are the original secondary objects. Its input-flag claim is also incorrect: the unknown flag is explicitly conditioned on mode!=input. Native capture still runs in the input case, with actual5Aux/zero recipe and known Source cleanup. Existing interpreter/delegate/descendant/binding limits remain. Neither model answer approves the whole current runtime; ROOT independently verifies final Source, tests, ordering, projections, contexts and raw results.

A controller-builder marker failed before any file write, unit, Source I/O or model retry. A corrected builder prepares the first actual before run. The failure is preserved as administrative preparation data, not a Source or numerical regression.

## Status and remaining requirements

Fresh selected23 hashes and four new Source Git observations record natural0/bothEOF, HEAD601108ea6216464bd00ae29c16cfaf0a59c71db6, owned branch, twenty untracked helper files and empty tracked production diff. This is Source/artifact data, not current20 compiled/canonical runtime admission. The helper bundle excludes private artifacts.

All20 remain uncommitted, uncanonical and unadmitted. No SDK/native build, kernel/broker/benchmark capture, Source push/adoption or strict dispatch occurs. The provider is absent, the gate always raises, the controller is closed, ownershipNone and all three flagsFalse. Earlier binding/interior/acquisition return shapes, concurrent ABA, historical/transitive actors and full immutable original-runtime admission remain incomplete.

Groups, strong references, closures and raw chunks last for process lifetime. Heap/RSS growth, allocation volume, timing, leak cause and memory bounds remain unmeasured. There is no RAM repair or trim/pop/reset/evict/delete authority. PR132 remains open draft against#130; issue103/milestone remain open. Original numerical quarantine, final strict48/50 and clean finalCI requirements are unchanged.

Storage free281547837440 bytes is artifact data requiring fresh future floor checks and authorizing no build, capture or deletion. Changes are not attributed to earlier cleanup.

The evidence archive contains 821 selected regular members, all verified byte-exact. Archive SHA256: 46a51dd65f1355d43f7e4b8bf53733068b5a9fa66ff6b9f39c70cbb515bffa68. Publication/readback receipts created afterwards are outside this snapshot.
