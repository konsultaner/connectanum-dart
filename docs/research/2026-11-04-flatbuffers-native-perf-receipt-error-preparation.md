# Preserving receipt errors without invoking exception hooks

Receipt/audit cleanup and failure publication used repr and add_note on error
objects. A custom hook could replace the original error before a retained
owner observed it. A new private receipt history records the exact primary,
stage and ordered secondary occurrences. Constructor initialization is empty
and precedes its lease callback. The objects remain private for process life;
there is no concurrent observer API, clearing, TTL or retry. Explicit secondary
occurrences retain their stage even when they use the primary object itself.
Identity checks use is; no error equality, repr, str or add_note is needed.

The existing receipt-failure primary_error key stays a string, now containing
only the native exception type name. A native type-name descriptor avoids
custom metadata lookup. Publication names the same earliest retained object
that is re-raised. If an output context close replaced an earlier retained
copy error, the earlier object wins; otherwise the caught error is re-raised.
A failure publishing failure metadata remains an exact private secondary.
Partial publication bytes are not overwritten and the attempt stays terminal.
An already retained private receipt failure additionally refuses a new emit.

Audit and per-input-FD cleanup now track an explicit LOCAL body error before
closing. sys.exception could instead expose an exception handled by the
caller's outer except block. The complete-output BODY also records errors
before its context closes, covering input-open and final flush/fsync failures
that occur outside the per-FD read try. Ordinary successful receipt emission
inside a caller's handled exception leaves private error history empty.

These are tracked receipt/audit/copy boundaries. This component does not
globally repair or prove arbitrary nested-helper internal error masking.
The existing close policy is unchanged: buffered audit/output close may
implicitly flush after an earlier write/flush failure. Receipt writer
inventory and uncertain-I/O quarantine still require independent work.
No physical FD/actor/descendant closure, durability or actual EX-release
authority follows from retaining an error.

The source/success/provenance/context/input/SDK/recipe/output gates remain.
No fixture is retagged as live; no receipt reset/retry or publication replay
is added. Old auxiliary predicates and owner_emit_attempted inventory refusal
remain. Provider absent, live admission always raises and live controller
closed, with ownershipNone and all three admission flagsFalse.

The retained stages are distinct:
- Seven new BEFORE controls fail, with actual exception-hook/primary-identity
  problems. These are not seven RAM/canonical production defects.
- Initial9 controls pass:7new and2required existing emitter callers.
- Two NEW controls then fail. An input-open error is still masked by actual
  output-context close. The initial implementation also INTRODUCES false
  ambient-handler error history by recording inherited sys.exception.
- After explicit local error tracking and whole-body retention,4targeted
  controls pass separately:2new and2affected audit/copy cleanup callers.

Nine new test cases exist. This is not combined13 or full-final11/canonical
verification. The existing required callers cover successful Fixture receipt
links and permanent partial-publication refusal. No unchanged suite or model
request is repeated to fill missing evidence.

Controls use a real tiny owned Git source, actual finite Fixture producer,
six shell version SHIMS and a finite Python recipe with synthetic output
roles. These are not installed SDK/compiler/version validation, bootstrap,
native build or canonical evidence. Negative source/publication/Path-context/
FD-close boundaries are mocked. Audit/output/FD-close controls close the
actual own native handle before injecting an error. Input-open refusal
creates no input FD. Failure bytes remain terminal, and no next publication
attempt or second artifact read is allowed.

New setup Git command arguments, signed same-Popen statuses, both output
EOFs and complete raw stream files/hashes are retained. Available LAST recipe
and auxiliary Popen handles receive actual final waits; auxiliary stream
EOF/FD/path/digest observations are retained. The existing producer
overwrites previous command Popen handles. Earlier version/command records
report0; they do not reconstruct handles or a complete per-actor wait journal
and do not prove SDK execution. Required legacy setup/API returns are not
all systematically serialized. Serialized error identity results are
booleans/stages/types, not persisted exception objects.

ROOT holds actual official EX through known finite controls. Fixture lease
callbacks are synthetic. No cancel, kill, reset, buffer/log replay or live
workaround occurs. Full Git, shell-shim, interpreter, delegate, descendant,
FD or instruction closure is not proved. Process-life error history is not
a heap/RSS bound.

Gemma orientation completes direct0/reaped. ROOT corrects its source reading:
_emit requires success, an audit can fail before any row, local writer close
is not durable ownership inventory, and _finish clears log/events references
while retaining the last Popen. Pure object inventory is not invalid merely
because an audit failed, and no nonrepudiation/global authentication follows.

GLM architecture and Qwen test advice complete direct0/reaped/advisory.
ROOT accepts first-before-close, publication matching the re-raised object
and a defined private observation point. Constructor starts with NONE, not
constructor-failure history. ROOT rejects hook-once advice (the target is
ZERO), fake echo Git setup, guessed fields/commands and dropping a secondary
occurrence solely because it is the same error object.

Qwen's17734character selected diff review reaches token limit1700/direct1.
Stderr reports6015visible characters; stdout is empty and the full partial/
final assessment is absent. The backend is reachable and the helper reaped;
no unavailability or approval is inferred. Its3209/40ef epoch precedes the
new input-open/ambient tests and final6ae7/29a4 source. ROOT independently
identifies those cases and inspects all final changed code/tests. No model
full-current-source approval is claimed.

Administrative failures stay retained. An initial functions JavaScript parse
fails before nested tools, filesystem/source writes or actors; its full tool
body is not a regular file. The first ROOT assessment rejects legitimate
str(run.repo) with an overly broad no-str assertion before stage/Git work.
Earlier structural assertions are reached, but individual predicate returns
are not all separately serialized; no reconstruction or repetition follows.

The first retained-report finalizer corrects the exception-operand guard,
then fails on an f-variable shadow after the first branch Git
communicate/wait and before saving that Git's PID, signed status or buffers.
Those fields remain NULL/unknown, never invented0. Exact controllers remain;
full raw CLI tracebacks are not regular files. A distinct second finalizer
consumes retained JSON reports only. It does not rerun branch Git, AST,
tests, models, old archives or stream-content audits to fill omissions.
HEAD/status/tracked-production-diff Git execute for the first time and
return0 with separate output EOFs. Current HEAD601 and twenty dirty helpers
are observed; the current branch return is unknown. The earlier expected
branch contract is not relabeled as a new observation.

Only producer/test change. CommandProducer constructor adds three private
initializers; _receipt_source_audit/_emit change and _retain_receipt_error
is new. All other CommandProducer methods, AuxiliaryCommand, retained-owner
classes, other original module functions/factories/public emitters, original
test classes, other18 tools and selected3 bins stay unchanged. Existing gates
are preserved except the stricter receipt-error terminal refusal. Production
tracked diff is empty; native outputs/instruction closure are not newly
proved. All20 helpers remain uncommitted, uncanonical and unadmitted;
private controllers are outside HELPERBUNDLE20.

Exact original/before/implemented/boundaries-before/boundaries-fixed20+3bin
snapshots, actual coordinators, fixtures, raw streams, model advice and both
failed/final finalization namespaces are retained. Final producer6ae7a77e
and test29a41666 full hashes are in the assessment. No source-branch commit/
push, adoption or strict dispatch occurs.

Full physical officialEX orchestration remains incomplete, including receipt
resource/writer uncertainty, audit partial actors, unknown starts and whole
historical/delegated actor/writer coverage. Original PATH/SDK/bootstrap,
first3locks/hiddenconfigs, current20 canonical/new source epoch package,
OWN production native/driver/static RLIB/compiler/tool/kernel and actual
original-host credentials/access/pidfd/FDexec/inheritance/arming/metadata/
role/time/coverage provenance remain required. No borrowed cohort/config/
native substitution, SDK change or future postGO data as preproof.

No actual SDK/native build, canonical, original-host kernel, broker,
benchmark/capture, RAM cause/repair or strict acceptance. About15.03GB is
observed above12GiB; recheck before build. No cleanup or space-change cause
is established.
