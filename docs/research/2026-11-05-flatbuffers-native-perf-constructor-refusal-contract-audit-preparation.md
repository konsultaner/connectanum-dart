# Cached audit of constructor refusal completion

This is a new question about the completion contract of the failure-group refusal field. It is an audit of retained Source bytes, not a runtime regression, a Source patch or a current canonical validation.

## Inputs and nominal map

The cached producer SHA256 is 6e04cefc79c8c4725d72a19a931903fb2d1eb5b382b2916960c75c603fbc1706. Four selected symbols cover the native helper and CommandProducer's constructor, deferral and preservation methods. The fresh v2 AST map records five literal references to the helper:

- CommandProducer.__init__
- CommandProducer._defer_failure
- CommandProducer._preserve_failure
- _end_command_group.refuse
- CommandProducer._finish.refuse

The latter two native refusal bodies are retained separately. These literal references and byte hashes do not establish all runtime aliases, global bindings, metaclasses, reflective or transitive actors. The previous 6e04ce/3661f7 Source/test epoch and seven passing scoped tests are historical data. This audit does not refresh live Source, HEAD, the twenty helper files, production packages/native, runtime configuration or compiled admission.

## Conditional Source facts

The native helper returns a plain five-tuple containing owner, guard, refusal function, primary error and secondary-error list. Its refusal function sets private quarantine before secondary metadata and always raises primary in its own finally block.

The constructor's acquisition and tuple-kind/arity checks precede pending and deferral. When a later pending, deferral or preservation operation raises a different secondary error, the handler invokes group[2](secondary). There is no additional local try/finally around this invocation.

If the received field is a different callback which never enters the native refusal function, that native function's finally block does not cover the replacement. Under that unexecuted substitution assumption, a normal callback return can let the handler and initializer finish normally, while a different callback exception can escape. This is conditional Source inference, not an observed runtime counterexample, spontaneous kernel fault or RAM-cause result.

The end-command and finish refusal bodies have independent primary state and their own finally raises. Both also assign primary from group[3] inside their try blocks. The existence of a finally is therefore not complete validation of the tuple's field bindings or error identity. Deferral and preservation also acquire and unpack the group before their detailed operation wrappers. No global closure or all-input priority guarantee follows from these selected contexts.

## Prospective regression

A meaningful next test can complete the actual original spawn inside ROOT, retain actual native Popen, original bound wait, creator pipe and FileIO handles before Source I/O, then raise First. The native failure helper completes its five-tuple only inside ROOT; Source receives a tuple whose refusal field is substituted. A later actual pending lookup returns its native bool inside ROOT, then ROOT raises Secondary before Source receives that return. Compare a replacement which returns False, one which raises a different Third and a native-refusal control.

This proposal is unexecuted. It requires a new declaration, official EX, a fresh one-GiB test floor, bounded waits on the same confirmed actors and evidence before known-handle closes. Unknown constructor completion remains a permanent refusal. Do not invoke partial Popen methods, restore Source fields, adopt ROOT's native tuple or an unexpected returned owner, retry a refused namespace or reconstruct missing statuses. No Source edit is authorized by this static map alone; an actual before failure must precede a minimal change and matching after/affected-caller checks.

## Model advice and ROOT qualification

Gemma 31909 completed with status zero, 1348 stdout bytes and 324 stderr bytes. Qwen 32221 completed with status zero, 1627 stdout bytes and 477 stderr bytes. GLM 32575 completed with status zero, 1846 stdout bytes and 594 stderr bytes. All three helper processes reached separate EOF, were naturally reaped and retained full answers. Their lifecycle evidence does not establish physical EX or closure of every interpreter delegate or descendant.

Gemma's broad summary places tuple shape in the helper; the actual check is in the constructor. Guard and context checks are not proof of ownership or complete resource cleanup.

Qwen says the native refusal function's finally protects a substituted callback. ROOT rejects that conflation: a replacement which never calls the native function does not enter its finally. Its proposed finished=False assertion for a pending-False branch also conflicts with the existing finished=True assignment. Source fields remain data, not cleanup authority.

GLM distinguishes the native-only premise from the substituted-callback case. Its opening statement that the conclusion survives is qualified by that premise. Earlier-primary retention may be deliberate; the selected strong owner and identity check do not prove the proposed foreign or reused-ID case. An assertion that binds the substituted field to ROOT's saved native-refusal identity would defeat the intended boundary injection and was not adopted. Both independent finally bodies consume group[3]; their Source order is not a complete field contract.

The initial question labels _end_command and _fail were inaccurate. The saved excerpts and final map identify _end_command_group.refuse and CommandProducer._finish.refuse. The answers are retained with these corrections; no unchanged model request was repeated.

## Preparation corrections and limits

The v1 selector asserted a four-symbol/three-reference conjunction and failed after its new directory was created, before selected files, declaration, model context, command or Popen. Its actual intermediate counts were not serialized and are not reconstructed. That namespace is terminal. Fresh v2 reads the cached bytes, serializes four selected symbols and five nominal references, and performs the first actual model calls.

A JavaScript backtick parsing error rejected the first judge-controller construction before any nested tool call, file write or Popen. The corrected script made the first actual judge request. The summary controller was defined before its operation, but its disk copy was saved after that call; it is not evidence of a controller file preceding execution.

There are zero Source or test edits, new unit runs, Source HEAD/census/Git preparation, SDK/native builds, kernel/broker/benchmark captures, adoption or strict dispatches in this scope. Earlier suites, numerical campaigns, old archives and completed model requests were not replayed or aggregated. No omitted API, actor, status, error buffer or final response was reconstructed.

The fresh free-space observation is 271603425280 bytes, for artifact storage only. It is not a test/build/capture/deletion authorization, and changes outside the completed cleanup have no measured cause.

Strong groups, closures and raw chunks remain retained for process life. Heap/RSS magnitude, growth, allocation volume, timing and leak cause remain unmeasured. No fixed-memory bound, RAM repair, trim, reset, eviction or deletion authority follows.

All twenty helpers remain uncommitted, uncanonical and unadmitted. The provider is absent, gate always refuses, controller is closed, ownership is None and all three flags are False. Full independent EX, original Linux credentials, complete FD/interpreter/delegate/descendant closure and immutable original-runtime admission remain incomplete. PR132 stays open and draft on base PR130; issue103 and its milestone remain open. RAM repair, final strict 48/50 and clean final CI are still required.

The evidence archive contains 42 selected regular members, all verified byte-exact. Archive SHA256: c2d14222d9d6299bb7f13785f7c25386ef50a50071b98f192353589300c5ab26. Publication/readback receipts created afterwards are outside this snapshot.
