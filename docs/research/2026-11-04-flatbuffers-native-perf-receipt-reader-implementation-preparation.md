# Owned direct receipt readers

Receipt emission and source auditing now route their direct JSON/hash/snapshot/
metadata reads through an independent private reader ledger. The generic
_read_json, _regular_hash, _file_snapshot and _read_bound_metadata functions
remain byteexact for their other callers. This does not cover descriptors
opened transitively inside those other functions or audit actors.

The constructor initializes reader state before its lease callback. A reader
record precedes open; the exact raw returned FD precedes callbacks, fstat or
read. Original ledger/ordered-record/field/directory/callback references are
bound around callback I/O. Every purpose is permanently terminal. Existing
distinct purposes may inspect the same path; no failed-purpose retry,
pipeline restart or numerical rerun follows.

Readers check regular type, owner/mode, FD/path identity including stable link
count, noninheritance, read direction, size and known position. JSON receipt
reads deliberately gain canonical path and before/after identity checks.
Hash inputs remain nonempty; snapshots allow empty logs and stream up to the
existing16GiB bound. Metadata retains full size/SHA checks and32MiB maximum;
JSON retains2MiB/digest/object/duplicate-key/nonfinite checks. JSON/metadata
bytes and last-read/error/resource history remain private for process life,
without an exact heap/RSS bound. Hash/snapshot does not collect the whole body.

An unknown read refuses another read. It may permit one same-FD identity-checked
close, without rereading or inferring consumed bytes. Close intent precedes
native close; any close BaseException becomes an exact private failure and
quarantine before choosing the earliest re-raise. Unknown close never recloses
or permits another open/report. Owner first/secondary history is retained
before modifying possibly damaged reader dictionaries. Fixed native stage
labels and type checks avoid custom iteration or concatenation hooks.
No repr/str/add_note/error equality is needed. These are bounded observations,
not atomicity, global ABA prevention, authentication or write prevention.

Existing source.tar publication deliberately uses an exclusive hardlink.
The initial new reader wrongly required one link and rejected this existing
path. The corrected reader preserves a stable positive link count, including
the actual archive's two links. No copy, unlink, ownership retag, source-archive
policy change or writer single-link relaxation occurs.

The retained stages are separate:

- The consumed generic JSON preparation at c1100806 has2FAIL/1PASS. Its controls
  are not rerun unchanged.
- Initial implementation7 yields6new unit passes and1required existing actual
  Fixture emitter error from the introduced single-link reader constraint.
- A NEW hardlink regression fails. After correction,2targeted controls pass:
  the hardlink and a new actual Fixture receipt integration caller.
- Three NEW strict controls fail: custom binding iteration, custom error-stage
  concatenation and a dropped error field masking the exact callback error.
  Typed bindings/native stage labels/owner-first retention yield11selected
  passes at producer706d/test6e27.
- A NEW unknown-read control then fails: another mocked native read is
  attempted after a read error left the known position unchanged. A final
  guard refuses further reads while preserving the identity-close exception.
  These2targeted controls pass separately at final9c771/test29a959.

Thirteen new declared test methods exist. The11selected result precedes the
last gate/test additions; it is not combined13 or a full-final13/canonical
result. The final change is the nonclosing unknown-read refusal, with its
negative and identity-close positive. ROOT inspects the complete affected
final methods/tests and that final hunk.

Unit controls use explicit SYNTHETIC owner fields, actual finite owned files/
raw FDs/native close before injected faults, and mocked callback/read seams.
They do not prove actual owner constructor or SDK/build provenance.
The actual integration caller runs a finite owned Fixture producer with tiny
Git source, six shell version SHIMS, finite Python and synthetic output roles.
Its Fixture receipt, reader EOF and native-close rows are observed before
cleanup/assertions. It is not installed SDK/compiler/version/bootstrap/native/
canonical evidence. ROOT holds actual official EX through known finite
controls and children; fixture callbacks remain synthetic.

Initial failed existing Fixture cleanup did not systematically serialize or
explicitly close that known reader FD before coordinator natural exit.
This limitation remains; no FD closure reconstruction or full closure claim
is made. Traceback/source and a later selected nlink2 stat observation are
retained as their own evidence. Individual runtime predicate returns are
not reconstructed from that later data. The source _make_archive explicitly
uses os.link. Later integration observations are new, not repairs of old gaps.

Available LAST recipe/auxiliary Popen waits and auxiliary EOF/FD-path/digests
are retained through inherited Fixture reports. Earlier overwritten command
handles and legacy setup/API returns are not all serialized. Error identity
booleans/types persist in reports, not exception objects. Negative known-FD
cleanup and synthetic field restoration are finite unit teardown only,
never a live workaround or lease-release permission. No source flags are
retagged. The mocked negative reads do not establish actual wrong-FD data loss.

Qwen's selected seven-method review completes direct0/reaped at ece585/19e0,
before strict and unknown-read additions. ROOT rejects its automatic close
after unconfirmed identity and its incorrect None/False interpretation:
after open succeeds, the exact FD and openTrue remain retained even when a
later guard fails. The review retracts its alternative offset/type/bound/
None/suppressed-secondary findings; no actionable P2 is established.
ROOT independently adds the later regressions and checks all final affected
source/tests and AST/file invariants. No model full-current-source approval
is claimed. Earlier GLM design/Qwen tests advice remains consumed.

Only producer/test change. Constructor adds two reader initializers;
_receipt_source_audit/_emit direct reads change and reader helpers are new.
Other CommandProducer methods, AuxiliaryCommand, retained-owner classes,
all other original module functions/factories/gates/public emitters, all
original test nodes, other18 tools and selected3 bins remain byteexact.
Four NEW posttest Git commands return0 with separate EOFs, observing expected
branch, HEAD601, twenty dirty helpers and empty tracked production diff.
No new native output/instruction closure follows.

Final producer:
9c771de5d79774bcb7980a364e34099f1b15c036891e9af538749de6fd49544a.
Final test:
29a959e71e741be826ede475abe64192f9e3359329b5f12c465f76b07a8f1c5e.
All20 remain uncommitted, uncanonical and unadmitted. Production601 is unedited;
private controllers are outside HELPERBUNDLE20. Exact stage snapshots,
coordinators, raw reports, fixtures and advice are retained. No unchanged
control, model, old archive, benchmark or missing serialization is repeated.

Transitive generic FDs, audit partial actors, unknown starts, historical
recipe/Git/interpreter/delegate/write-end/descendant coverage and independent
physical officialEX orchestration remain incomplete. Freeze owner_emit_attempted
and old auxiliary predicates are unchanged. FD close/status/EOF/join/empty
ledger/source-file data do not authorize EX release or admission.
Original PATH/SDK/bootstrap/first3locks/hiddenconfigs/current20 canonical/
new source-epoch package/OWN native-driver-static RLIB/compiler-tool-kernel
and actual original-host credentials/access/pidfd/FDexec/inheritance/arming/
metadata/role/time/coverage remain required before immutable admission.
No borrowed cohort/config/native transplant, favorable redo, SDK change or
postGO as preproof.

Provider absent, live gate always raises, controller closed, ownershipNone
and all three flagsFalse. No SDK/native build/canonical/kernel/broker/
benchmark/capture, source-branch commit/push/adoption/strict dispatch,
RAM cause/repair or acceptance. About13.83GB remains above12GiB; recheck
before any build. No cleanup or space-change cause is established.
PR132 stays OPEN DRAFT on130; issue103/milestone stay OPEN.
