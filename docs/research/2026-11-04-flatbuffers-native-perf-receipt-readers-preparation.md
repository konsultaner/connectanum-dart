# Direct receipt reader ownership: design and before controls

Receipt output/copy-input resources are retained by the preceding raw-FD
component. Direct calls from receipt emission/auditing to _read_json,
_regular_hash, _file_snapshot and _read_bound_metadata still open local
descriptors outside that ledger. Their finally blocks consult inherited
sys.exception and may call exception repr/add_note during close failure.
This preparation does not implement reader ownership or change source.

Three NEW finite controls execute the current generic _read_json function.
Two fail and one passes; there are no missing-API errors:

- Inside a handled ambient exception, a valid JSON read is followed by actual
  native close and an injected close OSError whose repr raises a hook error.
  The helper exposes the hook error instead of the intended close error.
- An exact injected digest-body error is followed by actual native close and
  the same close-fault model. The hook error replaces the intended body error.
- A normal successful read inside the ambient handler returns the expected
  JSON object, closes the descriptor and invokes no hooks.

Each negative performs the actual native close before injecting the error.
The observation retains exact returned FD numbers, held FD/path identity,
native-close normal return, post-call EBADF observation, error identity
booleans, native type names and hook occurrence strings. Error objects remain
private in process. A numeric FD/EBADF observation is not general lifetime,
descendant/writer or physical lease-release proof.

These are actual finite file/function fault-model controls in the current
administrative Python process. They are not an observed original SDK/build
failure, native benchmark, RAM cause or count of canonical production defects.
No recipe, Git, SDK/compiler/version command, child or worker thread is
requested by the controls. The entire producer module's exact held-source
buffer is compiled to obtain the original function; this is not validation
or execution of all20 helpers, compiled native images or canonical commands.
Source buffer SHA256 is
5847df17f0a3acac8a7d54b942c5096a52e13ffa248812cbd12cbccd53d7dfb0.
The source read retains FD/path/before-after metadata and actual close facts.
ROOT holds the real official EX through these controls. The controls finish
without cancelling, restarting, re-reading a failed purpose or repairing
old missing serialization.

The selected design is an independent, purpose-keyed reader ledger for direct
receipt calls, sharing the existing durable receipt quarantine. A record must
precede open, the exact raw return must precede callback/metadata I/O, and
original ledger/record/FD/path/progress references must be bound around each
callback. Distinct predeclared purposes may inspect the same file for their
different existing checks; a duplicate or failed purpose remains terminal.
This is never an idempotency justification for retries or favorable reruns.
Output-ledger exclusive-path rules remain unchanged.

Native close intent precedes the call. Every BaseException from close must be
retained as unknown-close/quarantine before choosing which original error to
re-raise. Exact primary and staged secondary occurrences remain private, with
zero repr/str/add_note/equality. Unknown-close suppresses new opens/publication
and never recloses. A read error may permit one identity-checked close without
re-reading or inferring consumed bytes. No empty ledger/closed scalar grants
release. The generic helpers outside direct receipt call sites are intended
to remain byteexact.

Future JSON receipt readers intentionally gain regular-file, owner/mode/path/
size and before-after identity checks. The current generic _read_json does not
already implement those checks. This is a proposed scoped tightening, not an
assertion that its omission was deliberate or that every role has identical
historical checks. Existing JSON digest/size/object/duplicate/nonfinite
semantics and the other helpers' existing constraints must be preserved.
Hash/snapshot reads must stream without collecting an entire16GiB log.
No exact heap/RSS bound follows from bounded chunk/count accounting.

GLM architecture completes direct0/reaped. ROOT accepts explicit close-error
retention before public suppression and the need to document stricter JSON
identity checks. ROOT rejects its rationale that reads are idempotent as
permission to repeat a failed observation. Its claim of a pre-open fstat
phase is imprecise: fstat needs an already retained descriptor. No inference
about why the existing JSON helper lacks identity checks is adopted.

Qwen test advice completes direct0/reaped/advisory. ROOT corrects the suggested
negative boundary: the repr hook is on the close error, not ProducerError;
native close must actually occur before injecting failure. Merely making
os.close raise could leave a live descriptor and does not establish the same
observation. Suggested guessed test command/module names are not used.
A non-OSError close BaseException remains a future required implementation
control; it was not executed in these three controls.

The design and wrappers are UNIMPLEMENTED. No new source branch commit/push,
adoption, source epoch package, canonical execution or strict dispatch occurs.
Current producer5847/test0f2 and all20 helpers remain uncommitted, uncanonical
and unadmitted; production601 remains unedited. No fresh source-branch/HEAD
observation is manufactured by this phase. Prior source-branch observations
retain their own epochs; old missing return serialization remains missing.

Next implement the retained direct-reader boundary with meaningful before/
after controls and actual Fixture receipt callers. This still cannot complete
transitive helper FD, audit partialactor, unknown-start, historical recipe/
Git/interpreter/delegate/write-end/descendant coverage or independent physical
officialEX orchestration. Owner_emit_attempted refusal and old auxiliary
predicates remain. Original PATH/SDK/bootstrap/first3locks/hiddenconfigs/
current20 canonical/OWN native-driver-static RLIB/compiler-tool-kernel and
actual original-host credentials/access/pidfd/FDexec/inheritance/arming/
metadata/role/time/coverage remain required before immutable admission.
Provider absent, live gate always raises, controller closed, ownershipNone
and all three flagsFalse. No SDK/native build/kernel/broker/benchmark/capture,
RAM repair or strict acceptance. Recheck12GiB before any build; no cleanup
or cause of free-space changes is established.
