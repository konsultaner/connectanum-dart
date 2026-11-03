# Closing retained parent writer objects after a failed command

A failed, uninitialized owner can now seal its two retained parent writer
objects after the existing command-wait component has observed an actual
signed Popen wait result, merged EOF and an empty output buffer. The serialized
worker retains the exact log FileIO and journal BufferedWriter/raw FileIO
before metadata or callback I/O. Observers receive immutable, typed primitive
rows through parent_writer_observations(); they receive no raw handles.

seal_parent_writers() consumes one attempt before Thread creation/start.
The existing busy, real Thread-join and settled-parent-start guards apply.
A fixed exclusive namespace is created before writer artifact metadata.
Existing, partial and refused namespaces remain terminal. The worker rejects
borrowed closefd=False wrappers, per-instance method shadows, aliases and
observed FD/path drift. Each step rechecks the mutable lease callback and held
objects outside the observer lock. These are bounded observations, not atomic
identity, global ABA prevention, writer authentication or write prevention.

Each writer gets one explicit flush stage. A failed flush quarantines that
writer without fsync or close. After a successful flush, fsync is attempted;
an fsync error can still permit one close after fresh revalidation. A close
attempt is marked before invocation and never repeated. Native close can
itself flush, so this is not a one-flush-syscall claim. Normal method return
and the object's closed property remain separate; a normal return with the
object still open now records an error and quarantine.

This ordering follows new primary research. Python documents flushing as part
of close, and the selected CPython buffered-close implementation calls flush
before raw close. Calling close after an explicit flush failure could therefore
attempt another flush. Full reference bodies and the selected C excerpt stay
local; public evidence retains URL/hash/stat receipts. These references do not
attest the installed interpreter or loaded instructions.
[Python 3.14 I/O documentation](https://docs.python.org/3.14/library/io.html),
[CPython v3.14.4 buffered close](https://github.com/python/cpython/blob/v3.14.4/Modules/_io/bufferedio.c#L545-L600).

The raw producer remains pending and unfinished, with process and writer
references retained. No end/finish, event emission, new command, audit,
receipt, publication or parent-log content read/hash is added. The original
auxiliary eligibility predicate stays byteexact and still refuses recipe
pending state. The older command observation is historical last-after-wait
data; separate writer rows describe later object-close observations. Neither
is a whole actor inventory or physical EX-release permission. Original and
new exceptions stay exact/private with type-only public data, without custom
repr, str or add_note hooks. Ownership remains unknown and all admission
flags false.

The initial thirteen new guards produce thirteen missing-API errors, not
thirteen production defects. Initial sixteen selected tests pass: thirteen
new cases plus three required existing callers. A new mocked normal-return/
still-open-object guard then fails. After correction, final seventeen pass:
fourteen new parent-writer guards plus the same three required callers.
Earlier sixteen and later seventeen are separate, without combined33 or
full-canonical claims.

Fixtures use actual finite OWN Python children, one merged stdout/stderr pipe,
private directory releases rather than GO and FIXTURE provenance. Source,
archive and input boundaries are mocked; the factory fault occurs after the
actual fixture constructor returns pending. No original constructor, SDK or
build failure is observed. Recorded new known children naturally return0 with
merged EOF and matching stream/file digests; the next command stays unlaunched.
The positive source API closes both actual retained objects before fixture
cleanup, with assertions and pre-cleanup closed-property records. The inherited
fixture_only_log_close field is a policy tag, not an actual close journal.
Failure-only fixture drain/close, malformed-field restoration and borrowed-FD
cleanup are never live workarounds. ROOT holds actual official EX through known
fixture workers and children; unit lease callbacks are synthetic.

Initial BEFORE parent pre-cleanup observations were not serialized. Returned
views and legacy Git setup returns are not all systematically serialized.
No missing observation is reconstructed or filled by rerun. Object properties
and method returns do not establish kernel close counts, absolute durability,
all writers/descendants, delegated instructions or physical lease closure.
Process-lifetime owner/history/handle retention is not a heap/RSS bound.

GLM94684 design and Qwen42083 test advice complete direct0 and are advisory.
ROOT accepts explicit journal binding and flush-failure quarantine; rejects
the claim that a Thread.start exception proves no worker, mandatory producer
state retagging and mocked positive-close proof. ROOT changes the unexecuted
initial close-after-flush-error plan before implementation using the primary
sources above. Qwen27697 full-diff review reaches a token limit/direct1;
its full partial/final assessment is absent. The backend is reachable, not
unavailable or approving. A distinct final selected error-path review64151
completes direct0 on the current implementation. ROOT rejects its missing
fsync-to-close revalidation claim because every loop step revalidates, and
rejects global-lock, GC-lifetime and lost-first-error claims after source
inspection. ROOT checks complete final affected methods/tests and AST/file
invariants; no model final full-source approval is claimed.

Only the producer/test pair changes. Original module-level functions,
factories, emitters, gates, CommandProducer/AuxiliaryCommand classes, other
original owner methods/test classes, other18 tools and selected3 bins remain
byteexact. Owner init/schedule/work extend to dispatch the new worker phase.
All20 helpers remain uncommitted, uncanonical and unadmitted; production601
stays unchanged. HELPERBUNDLE20 stays twenty and private coordinators remain
separate artifacts. No source-branch commit/push/adoption or strict dispatch.

Independent recipe/auxiliary/unknown-actor orchestration and physical official
EX lifetime remain incomplete. Original PATH/SDK/bootstrap inputs, first
runtime locks/configs, current20 validation/canonical, production native/
driver/static RLIB and original-host credential/access/pidfd/FDexec/inheritance/
arming/metadata/role/time/coverage provenance still require completion before
immutable complete admission or any diagnostic data. The live gate refuses,
provider is absent and live SessionController closed. No actual canonical,
SDK/native build, original-host kernel control, broker, benchmark or capture,
RAM cause, repair or strict acceptance. Latest assessment observes about17.95GB,
above12GiB; recheck before build, no cleanup and space-change cause unmeasured.
