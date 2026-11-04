# Direct command attempt history and method wait witnesses

CommandProducer now retains a private history for each direct configured
command. Empty history/current/error state precedes the constructor lease
callback. Each attempt precedes command_start event, log, pipe and Popen I/O.
The exact returned log object, read FD, parent writer FD and Popen reference
are retained before subsequent operations. Earlier process/log references
survive replacement of self.process/self.log. No history is reconstructed for
older producers whose references were already overwritten.

The existing wait loop uses a bounded helper for its original same-Popen.wait
call. An exact integer METHOD return is recorded before _end_command changes
pending/returncode/time or flushes/fsyncs/closes/publishes metadata. Poll does
not create this witness. A later actual wait may return the same cached poll
status; this is accepted and does not prove a fresh wait syscall. Timeout
retains the same process and unresolved status. Malformed bool/status or
identity drift refuses without inventing zero. No extra actor, wait loop,
cancel, restart, retry, env/argv/stdio or workload change is introduced.

Private first/staged secondary errors precede original spawn reporting and
wait failure handling. New history code uses identity and no exception
repr/str/add_note/equality. The original public spawn cleanup/reporting still
uses repr/add_note and can mask public errors; this component does not claim
to fix that policy. Pipe FD numbers, creator-copy close intent/normal return,
closed log objects and wait statuses are data, not current FD authority,
child-writer authentication, descendant or physical lease closure.
There is no concurrent raw observer API, history clearing or heap/RSS bound.

Before verification selected the new subclass by class name. It accidentally
ran eight inherited existing resource controls alongside eight new history
methods:16tests,7failure occurrences and5error occurrences. These are not
twelve production defects or twelve unique cases. The breakdown is:

- Four new bodies fail because command history is absent.
- Three new methods error on the absent wait API.
- One new method errors on a missing local time import.
- Two pending-state teardown assertions fail and a processNone teardown errors.
- One inherited output-resource callback fails; seven inherited controls pass.

Those seven passing inherited controls are not rerun unchanged. The harness
now selects explicit new method names, imports time locally, performs bounded
public SAME-actor failure waits before teardown assertions, handles processNone
and records only known finite-unit writer cleanup. This is never a live
recovery or weakening of producer state.

The inherited callback exposed a separate integration defect in the preceding
reader component's private test seam. Readers belonged to _receipt_readers
but called _receipt_resource_io, whose output callback requires ownership in
_receipt_resources. A new _receipt_reader_io executes the same native
open/read/close calls. Three reader functions and five reader test classes
change only that seam name. Output membership checks remain; no cross-ledger
adoption, path/gate relaxation or native I/O behavior change occurs.

After implementation and these corrections,22selected controls pass:
8new history controls,13explicitly migrated reader controls and the formerly
failing output-resource caller. The actual direct recipe case configures
two finite Python commands; it does not contain six version probes.
The separate actual Fixture receipt caller contains six shell version SHIMS,
finite Python, tiny Git and synthetic output roles. None is installed SDK/
compiler/version/bootstrap/native/canonical evidence.

The history controls retain first and final Popen/log identity after overwrite,
observe wait status before an injected _end_command error, retain a pending
actor through actual parent-writer close followed by an injected error,
and retain an attempt before the first event fails without a direct child.
Poll-then-equal actual wait, real same-child timeout, mocked bool return and
foreign-process refusal are covered. Synthetic capsules use real finite
Popen objects; they are not actual producer constructor/admission evidence.
Parent close errors leave raw pendingTrue until the original failure wait;
history does not retag producer completion.

Gemma summary21242, GLM design21570, Qwen tests21813, debug23170 and review23971
all complete direct0/reaped/advisory. ROOT corrects the summary: configured
commands are not necessarily probes, auxiliary OBJECTS are retained before
start, and the parent writer is a creator copy. ROOT corrects GLM's ordering:
_end_command sets pendingFalse/returncode/ended_ns BEFORE log flush. Its
poll-then-equal-status and pending-actor retention checks are adopted.
Fake Popen positives, mock-only timeout proof, invented commands/error types,
syscall counts and an event-bus explanation are rejected. Teardown assertions
are satisfied by known finite operations rather than softened.

The review's proposed P0 try/except fallthrough and P1 bool acceptance are
false. Python executes that else only when the try body did not raise, and
type(True) is bool. Two NEW controls check these claims. Their first run has
one pass for bool/nonbounded rejection and one harness error: the test
callback's kind parameter collides with command_end record kind before the
intended P0 observation. After renaming the callback and retaining the finite
run early, only that blocked control passes separately. Producer bytes remain
unchanged. There is no combined24/full-final24/canonical result.

Initial pending/None teardown failures do not have a complete per-actor/FD
journal. The first review callback failure also leaves incomplete failed-
constructor/Aux/writer serialization. These limitations remain; later controls
do not reconstruct them. Subsequent known same-Popen waits, bounded public
failure completion and known writer closes are unit teardown only, never
live cleanup permission. Malformed False is saved separately from actual
later unit wait0; it never becomes a source wait witness. Raw/API returns are
not all systematically serialized. ROOT holds actual official EX through
known finite controls; no whole Git/interpreter/delegate/descendant/FD or
loaded-instruction closure follows.

ROOT checks all affected final source/tests and structural invariants.
Constructor adds history fields; _spawn/wait change and two private methods
are added. Normalizing only private wait/history calls gives the original
wait AST. Popen argv/env/stdio and pipe calls match the original AST; close
call sites and original public reporting policy remain. Other original
CommandProducer methods, AuxiliaryCommand, retained-owner classes, original
module functions except the three reader-seam calls, and original test nodes
except the explicit reader mock migration stay byteexact. Other18 tools and
selected3 bins remain unchanged. Four NEW posttest Git commands return0 with
separate EOFs: expected branch, HEAD601,20dirty helpers, production diff empty.

Final producer:
78ae89da207c41d6bf05baf51df7d431d6098e45d557cb87a587ed243557be16.
Final test:
8b7237439f925d185767b4fc07a95ccd5b26ed1dc14196366372517f69410a96.
Selected review uses the same producer before the last test additions;
it is not model full-current-source approval. ROOT independently verifies
final tests/invariants. Exact snapshots, coordinators, raw reports, advice
and all failures are retained. Private controllers are outside HELPERBUNDLE20.
All20 helpers remain uncommitted, uncanonical and unadmitted; production601
is unedited. No source-branch commit/push/adoption or strict dispatch occurs.

Independent frozen history inventory/continuation, transitive generic FDs,
audit partial actors, unknown starts, shared journal/historical writer,
interpreter/delegate/descendant coverage and full physical officialEX
orchestration remain incomplete. Existing freeze owner_emit_attempted and
old auxiliary predicates are unchanged. No status/EOF/join/closed object/
empty ledger/source-file data authorizes release/admission. Original
PATH/SDK/bootstrap/first3locks/hiddenconfigs/current20 canonical/new source
package/OWN native-driver-static RLIB/compiler-tool-kernel and actual
original-host credentials/access/pidfd/FDexec/inheritance/arming/metadata/
role/time/coverage remain required before immutable admission.
No borrowed cohort/config/native transplant, favorable redo, SDK change
or postGO as preproof.

Provider absent, live gate always raises, controller closed, ownershipNone,
all three flagsFalse. No SDK/native build/canonical/kernel/broker/benchmark/
capture, RAM cause/repair or acceptance. About11.66GB is now BELOW12GiB:
the build floor is CLOSED; recheck before any build. Scoped controls checked
the separate1GiB floor. No cleanup or cause of the free-space change is
established. PR132 stays OPEN DRAFT on130; issue103/milestone stay OPEN.
