# Sealing exact frozen known log objects without advancing the pipeline

A new permanently terminal owner action, seal_known_actor_logs(), seals the
current frozen recipe log, retained auxiliary stdout/stderr logs and producer
journal. known_log_observations() returns cached immutable primitive rows.
This is an object-level source component. It does not complete physical
ownership or permit releasing the actual official EX lease.

Every frozen recipe and retained auxiliary needs a private selected-wait
record: exact-int method status matching the current cached Popen status,
EOF, empty buffers, readFDNone and exact read close_confirmedTrue. Historical
read close confirmation null refuses; it is never reconstructed. This field
is distinct from auxiliary write_close_confirmed. Missing/unstarted/unknown
actors, uncertain I/O and private/global quarantine refuse. Public wait-cache
rows do not authorize sealing.

One attempt is marked before Thread creation/start. Existing busy, real
Thread join and settled-start guards remain. Every later producer action
refuses, including after partial failure or failed cache publication. The
worker retains all candidate original writer objects, actor records and exact
per-actor stream containers/tuples before callback or fstat. A fixed exclusive
owned-known-logs namespace precedes writer artifact metadata. Existing or
partial namespaces stay terminal; there is no overwrite, reset or retry.

Exact FileIO/BufferedWriter/raw objects must own their FDs, have no instance
I/O shadows and have distinct raw objects, FDs and device/inodes. SAME log
means each actor's own original log; cross-role aliases receive no exemption.
The original lease callback runs outside the observer lock. After it, all
known layout, wait, pending/result, stream/hash/buffer and held-FD/path/
single-link/noninherit/write-only observations precede native I/O. All
writers are checked before the first flush. Checks run again after fallible
cache publication and before each native step.

Each writer has one explicit flush stage. Flush failure stops/quarantines
without fsync or close, because buffered close could flush again. A successful
flush permits fsync and one revalidated close. Fsync failure retains its exact
primary error, can permit that writer's close, then stops before the next
writer. Close intent precedes the native call. Normal return and actual
closed properties are distinct; returning with an open object quarantines.
Close-then-raise records the observed closed property but grants no successful
return/close confirmation and never retries. Native close may implicitly
flush. These facts do not count kernel flush/close calls or prove durability.

A private expected-closed table advances only after a normal close and both
native objects observed closed. The existing wait guard has a scoped optional
sealing context. Its normal wait path keeps the original callback and checks.
Only an exact previously closed log skips its log FD operations, after exact
object/raw/closed and retained log_fd/log_identity checks. Read-FD and mutable
progress checks remain. Subsequent open writers still receive held-FD/path
checks. This is bounded observation, not global atomicity/ABA, authentication
or prevention of foreign mutations.

No end/finish/_complete, audit, next spawn, input/version probe, log-content
read/hash, auxiliary result/build receipt or publication occurs. Producer and
auxiliary pendingTrue/finishedFalse/resultNone and exact object references
remain. Old inventory/wait rows remain historical. Original owner error and
new exact first/secondary errors remain private, with TYPEONLY public data;
no repr, str or add_note hook is used. Observation rows are cached attempt
facts, never live re-derivations of writer state. Attempt/private-quarantine
flags retain refusal authority if public cache publication fails.
OwnershipNone and all three admission flagsFalse remain.

The retained test stages are separate:
- Before14 new controls yield14 missing-method/helper API errors. They are
  not14 production defects.
- Initial16 run yields15pass and1new test assertion failure. The test assumed
  tuple-container identity from a wait-view factory. Actual row objects stay
  unchanged, while the factory returns a new tuple. The assertion is
  corrected;1control passes separately with implementation byteexact.
- A new synthetic callback drops a private stream group and injects a raw
  buffer marker.1guard fails: mocked native writer I/O attempts pass the
  omitted progress checks. No actual wrong-FD I/O or lost production data is
  observed. Exact stream containers/tuples, cardinality and roles are now
  retained/checked.2targeted controls pass separately.
- Two new unknown-role/recipe-key controls fail because custom equality is
  actually invoked. Type checks now precede role equality and recipe
  dictionary lookup.3targeted controls pass separately.

Seventeen new test cases exist, plus two required existing callers in the
initial16. These are not combined full-final17/19 or canonical results. The
required callers exercise ordinary capacity drain/default wait behavior and
the earlier parent-writer sealer. No unchanged suite or model review is
repeated to fill omissions.

Controls use actual finite OWN Python/Popen actors, FIXTURE provenance and
mocked source/archive/input boundaries. Faults occur after an actual fixture
constructor returns or after auxiliary launch; no original SDK/build failure
is observed. Private release directories are not GO, and children have
self-deadlines. Positive source API calls close all actual known writer
objects before fixture teardown/assertions. Raw pending/result state and
next-sentinel refusal remain checked. Negative I/O seam mocks, synthetic
metadata restoration and direct known-FD/log/journal cleanup are unit
teardown only, never a live workaround.

ROOT holds actual official EX through known fixture threads/children. Lease
callbacks are synthetic. New row/lifecycle reports precede cleanup. New
teardown records actual signed same-Popen final waits, separate suffix files
and saved original buffers without replaying original logs/buffers. Retained
stage actor rows are all actual0; counts and exact stream metadata are in the
assessment. Negative prefix/buffer/suffix is not complete original stream
integrity. Legacy setup/API returns and all private FD scalar observations
are not systematically serialized. No omissions are reconstructed.

Gemma orientation completes direct0; ROOT corrects its invented new-versus-old
comparison and writer creation: selected source is the existing parent sealer
retaining already-existing objects. GLM architecture advice and Qwen test
advice complete direct0/reaped. ROOT accepts the closed-log-before-fileno,
retained identity, both-closed and preserved read-guard points. ROOT rejects
a cross-role alias exemption and notes that one-attempt refusal already
excludes resealing. Test advice is qualified: real finite positive actors/
native I/O, not synthetic positive Popen; os.fsync is not writer.fsync;
instance I/O shadows are refused; one explicit method stage is not a kernel
call count.

Qwen's33714character full selected diff review reaches its token limit/
direct1. Stderr reports9275visible characters; stdout is empty and the full
partial/final assessment is absent. The backend is reachable, the helper is
reaped, and no unavailability or approval is inferred. The request is not
repeated. Its source epoch0bc7/6e80 predates the new stream-group/type guards.
ROOT independently identifies those new regressions and inspects every
affected final method/test and AST/file invariants. No model full-current-
source approval is claimed.

Only producer/test change. Original module functions, factories, gates,
emitters, CommandProducer/AuxiliaryCommand classes including the earlier
wait witness, other original owner methods/test classes, other18 tools and
selected3 bins remain byteexact. The owner init/schedule/work and scoped wait
guard extend; new log-seal methods are separate. Exact original/before/
implemented/test-corrected/newguard-before/final/types-before/types-fixed20+
3bin snapshots, coordinators, fixture streams and advice are retained.
Final producer c85869a4/testbbef2b3f full hashes are in the assessment.
All20 helpers remain uncommitted, uncanonical and unadmitted; private
controllers are outside HELPERBUNDLE20. Four post-test own Git commands return
natural0 with separate output EOFs: branch, HEAD, status and tracked production
diff. HEAD stays601, twenty helpers stay dirty and the tracked production
diff is empty. This is not a new native-output/instruction-closure proof.

An independent physical official EX controller remains incomplete, including
receipt-audit failures, unknown starts and whole historical/delegated actor/
writer coverage. Freeze still refuses owner_emit_attempted. Log object
closure, status, EOF, call join, empty ledger, source archive and Gitclean
never grant physical release or admission. Runtime original PATH/SDK/
bootstrap, first3locks/hiddenconfigs, current20 validation/canonical/source
epoch package, OWN production native/driver/static RLIB/compiler/tool/kernel
and actual original-host credentials/access/pidfd/FDexec/inheritance/arming/
metadata/role/time/coverage provenance remain required. No borrowed cohort/
config/native substitution, SDK change or future postGO data as preproof.

Provider remains absent, live admission always raises and live controller
stays closed. No actual SDK/native build, canonical, original-host kernel,
broker, benchmark/capture, source-branch commit/push/adoption/strict dispatch,
RAM cause/repair or acceptance. About15.09GB is observed above12GiB; recheck
before build. No cleanup or space-change cause is established.
