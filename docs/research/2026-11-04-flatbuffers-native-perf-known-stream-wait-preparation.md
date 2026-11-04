# Waiting on one frozen known actor without advancing the pipeline

A failed initialized or uninitialized owner can now continue one exact actor
after a successful checked inventory freeze. The separate serialized action
accepts recipe index0 or an auxiliary index and the existing bounded timeout.
Ordinary pipeline actions and repeated inventory freeze remain refused. The
same busy, actual Thread join and settled parent-start guards apply.

The worker retains the exact frozen producer, Popen, record/list/auxiliary
dictionary, stream, log, hash, path and FD references before callback or
metadata I/O. The original owner lease callback and checks of the complete
known-object layout, expected mutable progress, FD/path identity and direction
precede read, write, select, close and wait. These checks run outside the
observer lock. Frozen pointers remain separate from legitimate advancing
buffer/byte/hash/EOF/FD state; private expected progress advances only after
known coordinator I/O. These are bounded observations, not atomic/global ABA,
authentication, foreign-write prevention or complete physical ownership.

Recipe output uses its original merged pipe; auxiliary output uses its two
original separate pipes. Bytes drain to the same open logs and hashes.
Write intent precedes native FileIO.write; a strict positive returned count
updates the known buffer/byte/hash progress before intent clears. Unknown
read/write/count/close quarantines without replay, reclose, rebind or reset.
Unknown raw values and exact primary/secondary errors remain private.
EOF records one close attempt before clearing the raw FD slot; only normal
return confirms close. An initially observed EOF/FDNone has historical close
confirmation null, not a reconstructed successful close.

Recipe Popen.wait receives max(0, remaining time), and its exact-int return is
retained before cache I/O. Auxiliary waiting uses the existing exact-process
direct-method witness. A pre-existing witness has an explicit historical
origin. Popen can return a cached code after poll/reap; this is not a fresh
wait syscall, liveness/PIDfd or descendant/writer proof.

The action is WAIT ONLY. It never calls _complete, _end_command or _finish;
closes no log; performs no source/version/input audit or next spawn; publishes
no auxiliary result/build receipt; and does not retag pending/finished/result.
Raw producers and auxiliaries remain pending, unfinished and resultNone with
logs open. A selected terminal cache only refuses another wait. Old frozen
inventory and owner scalar rows remain historical. OwnershipNone and all
three admission flagsFalse remain. Retained histories are not heap/RSS bounds.

A new failure control exposed an authorization bug: select raised the first
OSError and secondary cache publication raised ValueError. Both exact errors
were retained correctly, but the unchanged public before_wait row permitted
another worker and read attempt despite private quarantine. Scheduling,
binding and the worker guard now check durable PRIVATE quarantine/primary
error before a new worker or I/O. If error-cache publication fails, the public
row can still be historical; public lifecycle call/observation errors are
separate. No stale public row authorizes continuation. This is a unit
preparation defect, not a measured hang, RAM cause or canonical production
failure. No custom repr, str, equality or add_note hook is invoked to expose
errors or unknown record keys.

The retained stages are distinct:
- Before12 tests produce17 missing-API errors, including five extra invalid
  argument subtest errors. They are not17 production defects.
- Initial16 pass:12 new controls and4 required callers.
- Three new guards fail: auxiliary path drift and writer-close-confirmation
  drift allow read attempts, and an unknown recipe record key invokes custom
  equality. No actual wrong-FD data read is established.
- Corrected19 pass:15 new controls and4 required callers.
- The new private-quarantine/cache-failure guard fails once.
- After the private-authority fix,2 targeted tests pass separately: that new
  guard and the actual initialized capacity caller. This is not combined21,
  combined37 or full final canonical verification.

Controls use actual finite OWN Python/Popen actors with FIXTURE provenance
and mocked source/archive/input boundaries. Factory faults occur after the
actual fixture constructor returns, or a later wait faults after actual
auxiliary launch. No original constructor, SDK or build failure is observed.
Private directory releases are not GO, and children have self-deadlines.
The capacity control checks131072A+131072B per actor against complete actual
log contents, keeps logs open and next sentinels unlaunched. Other controls
cover same-process timeout, natural78, EOF before process exit, callback
drift, malformed write count, actual close followed by injected error,
auxiliary wait fact before cache error, busy guards and exception hooks.

ROOT holds actual official EX through known fixture threads/children;
unit lease callbacks are synthetic. New teardown independently drains each
remaining known FD round-robin into separate suffix files and saves original
buffers separately. It never writes/replays an original log or buffer.
Actual same-Popen final waits0/78 and suffix metadata are retained. Negative
prefix/buffer/suffix evidence is not complete original stream integrity.
Private direct drain/FD/log/journal cleanup and synthetic-field restoration
are unit teardown only, never a live workaround. New views and required
legacy Git setup/API returns are not all systematically serialized. No
omissions are reconstructed or unchanged controls rerun to fill them.

GLM architecture advice, Qwen test advice and Qwen selected review complete
direct0 and are reaped/advisory. ROOT accepts private expected mutable
progress, witness prevalidation and first-error retention. ROOT uses unittest,
correct auxiliary indexing, positive partial writes and distinct historical
inventory versus advancing wait observations. The selected review covers
e58/6f4 before the final private-quarantine guard/fix. Its quarantine concern
leads to the new regression; ROOT rejects primary-loss claims, conversion of
exact errors to ProducerError, foreign-mutator/global-lock atomicity claims
and moving fcntl to module scope or skipping POSIX checks. Fresh primitive
cache dictionaries have no retained mutable public alias. ROOT checks all
affected final methods, the new guard and AST/file invariants; no model
full-current-source approval is claimed.

Only producer/test change. Original module functions, factories, emitters,
gates, CommandProducer and AuxiliaryCommand including the prior natural-wait
witness, other original owner methods/test classes, other18 tools and selected
3 bins stay byteexact. Final producer d87e2603 and test2fd478e8 full hashes and
all20 snapshots are in the assessment/evidence. All20 helpers remain
uncommitted, uncanonical and unadmitted; production601 stays unedited.
Private controllers are outside HELPERBUNDLE20. POSIX FD checks use a deferred
fcntl import; this is not Windows execution proof.

Independent known-log sealing and a complete physical officialEX controller,
including receipt-audit failures and unknown starts, remain incomplete.
Inventory eligibility still refuses owner_emit_attempted; this component
does not close that path. No selected status/EOF/call join/object close/
empty ledger/source archive/Gitclean authorizes physical EX release or
admission. Actual original PATH/SDK/bootstrap inputs, first runtime locks/
hidden configs, current20 canonical, own native/driver/static RLIB, compiler/
tool/kernel and original-host credentials/access/pidfd/FDexec/inheritance/
arming/metadata/role/time/coverage provenance remain required. No borrowed
cohort/config/native substitution, SDK change or future postGO data as preproof.

Provider remains absent, live admission always raises and live controller
stays closed. No actual SDK/native build, canonical, original-host kernel,
broker, benchmark/capture, source-branch commit/push/adoption/strict dispatch,
RAM cause/repair or strict acceptance. The assessment records15.96GB above
12GiB; recheck before build. No cleanup or space-change cause is established.
