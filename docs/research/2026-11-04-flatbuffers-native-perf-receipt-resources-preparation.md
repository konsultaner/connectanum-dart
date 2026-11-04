# Receipt resources retain raw FDs and stop after uncertain I/O

Receipt metadata used buffered writers whose close could implicitly flush again
after a write/flush failure. Receipt paths now use a private resource ledger and
raw OS descriptors. A record exists before open; the exact returned descriptor
is retained before callbacks, fstat or other I/O. The paths cover the attempt,
source audit, complete log, input receipt, binding and failure report, plus
copy-input read descriptors. Other metadata/hash/read helpers remain outside
this receipt-specific ledger.

Output creation remains exclusive and terminal, using the previous 0666 plus
umask mode. Sorted JSON indentation/newline and compact JSONL formats are
preserved. Every operation checks the original callback/directory references,
held FD/path, regular single-link identity, direction, noninheritance and
expected size/offset. Active descriptors cannot alias; normally retired numeric
FDs may legitimately be reused by the kernel.

Known positive short writes advance only the unwritten suffix. Pending bytes
and offset survive an unknown write/count. That writer is quarantined: no
fsync, close, replay or failure JSON follows. Unknown open/close also prevents
further opens. A known-write fsync failure may permit one guarded close.
A read failure may permit one identity-checked close without rereading.
Close intent precedes the native call. An exception leaves close unresolved;
the numeric FD is never reclosed or treated as live after retirement.
Raw output removes this implicit userspace-buffer replay path; it does not
prove kernel call counts, durability or physical resource closure.

A NEW callback regression exposed two gaps in the first implementation.
Replacing the ledger or substituting a different FD for the same file reached
mocked native I/O. No actual wrong-FD write is established. Context checks now
retain the exact ledger, ordered record objects and each field reference
before the callback, then reject observed replacement/cardinality/field drift.
Exact string keys precede dictionary lookups; comparison uses identity.
These are bounded observations, not atomicity, global ABA prevention,
authentication or prevention of foreign writes.

The verification stages remain separate:

- Before8: one actual replay regression fails and seven missing helper/API
  controls error. These are not seven production RAM defects.
- Implemented9 pass: eight new controls and one required positive Fixture emitter.
- Five legacy negative test methods are explicitly migrated to raw-FD seams;
  ten selected existing callers pass separately. Their primary/secondary,
  partial-byte and terminal/no-second-read assertions remain. Unknown open or
  close now suppresses failure JSON; a same-primary pre-write failure leaves an
  existing empty report instead of an absent buffered report.
- Two NEW callback controls fail. After correction, the selected six yield
  five passes and one loader error because the coordinator used a nonexistent
  required caller name. This is an administrative error, not a source defect.
  The intended caller-handler control then passes separately; the five passing
  controls are not rerun.

Ten new test cases exist. No combined full-final suite or canonical result is
claimed. The replay control uses a native BufferedWriter over controlled RawIO
and real FileIO, with an error injected after actual os.write. Its BEFORE
implicit close writes the piece twice. This is a finite unit fault model,
not an observed original kernel failure, measured data loss or RAM cause.
The repaired path performs one actual write and retains unresolved ownership.
Positive Fixture receipts verify JSON bytes and all known resource retirement.
Short-write suffix, fsync, actual-close-then-error and input-close uncertainty
are also covered. Callback negatives mock native writes.

Controls use actual tiny owned Git sources, six shell version SHIMS and finite
Python recipes with synthetic output roles and Fixture provenance. They are
not actual SDK/compiler/version/bootstrap/native/canonical evidence. ROOT
holds official EX through known finite controls; fixture callbacks are synthetic.
New setup Git arguments, signed same-Popen waits, both EOFs and raw stream
hashes are retained, together with available LAST recipe/auxiliary final waits
and auxiliary EOF/FD-path/digest observations. Earlier overwritten command
Popen handles are not reconstructed. Reported zero statuses are not a complete
wait journal. Legacy setup/API returns and every private FD scalar are not all
systematically serialized.

Negative teardown closes only explicitly retained known fixture FDs and restores
synthetic fields. Source flags are never retagged. It is never live cleanup or
controller release authority. Error/resource histories remain private for
process life, with no concurrent observer API, reset, retry or heap/RSS bound.

GLM architecture and Qwen test advice complete direct0/reaped/advisory.
ROOT uses their global quarantine/no-publication and focused real-I/O controls.
The selected initial052c source review reaches GLM's1800-token limit:
direct1, stdout empty, stderr reports4483 visible characters, full partial/final
assessment absent. The backend is reachable and helper reaped, not unavailable
or approving. ROOT independently adds the callback regressions and final guard.
A first focused review command has an invalid job name and exits2 before a
backend request. Its corrected, distinct four-method Qwen review of final5847
completes0/reaped. ROOT rejects closing an identity-uncertain FD, inferring
unknown write progress, requiring atomic Python/syscall updates or relaxing
original callback identity. No model full-current-source approval follows.

ROOT checks all affected final functions/tests and structural preservation.
Only the producer/test pair changes. Constructor adds resource state; receipt
audit/emission change and resource helpers are new. Other CommandProducer
methods, AuxiliaryCommand and retained-owner classes, other original module
functions/factories/gates/public emitters, other original test methods except
the five explicit seam migrations, other18 tools and selected3 bins remain
byteexact. Four NEW posttest Git commands return0 with separate EOFs, observing
the expected branch, HEAD601, twenty dirty helpers and empty tracked production
diff. The separately declared source-edit branch check is a new purpose/epoch;
the previous phase's missing branch PID/status/buffers remain unknown forever.

Exact original/before/implemented/legacy-adapted/callback-before/callback-fixed/
caller-handler20+3bin snapshots, actual saved coordinators, fixture reports/raws,
advice and administrative failures are retained. Final producer
5847df17f0a3acac8a7d54b942c5096a52e13ffa248812cbd12cbccd53d7dfb0 and test
0f2fbb429d5471e6b56fc19dba1a167bbddb04a0be2d519d3496cc3a931e93f3
remain uncommitted, uncanonical and unadmitted with all20 helpers.
Private controllers are outside HELPERBUNDLE20. Production601 remains unedited.
No source-branch commit/push, adoption or strict dispatch occurs.

Generic helper FDs, audit partial actors, unknown starts and historical
recipe/Git/interpreter/delegate/write-end/descendant coverage still require
independent physical officialEX orchestration. Freeze still refuses
owner_emit_attempted; old auxiliary predicates are unchanged. Resource closes,
status, EOF, join, empty ledgers and source data do not authorize lease release.
Original PATH/SDK/bootstrap/first3locks/hiddenconfigs/current20 canonical/new
source-epoch package, OWN native/driver/static RLIB/compiler/tool/kernel and
actual original-host credentials/access/pidfd/FDexec/inheritance/arming/
metadata/role/time/coverage remain required before immutable admission.
No borrowed cohort/config/native transplant, SDK change or postGO as preproof.

Provider absent, live gate always raises, controller closed, ownershipNone and
all three flagsFalse. No actual SDK/native build/canonical/kernel/broker/
benchmark/capture, RAM cause/repair or strict acceptance. About13.87GB is
observed above12GiB; recheck before any build. No cleanup or space-change cause
is established. PR132 stays OPEN DRAFT on130; issue103/milestone stay OPEN.
