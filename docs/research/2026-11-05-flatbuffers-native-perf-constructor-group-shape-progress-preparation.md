# Failure-group tuple shape before constructor deferral

The native helper returns a plain tuple containing five elements: owner, guard, refusal callback, primary error and secondary-error list. The constructor previously checked only for explicit None and bool returns before reading pending. This new scope checks tuple kind and arity; it does not validate callable fields or authenticate the tuple's origin or ownership.

## Declaration and actual before result

The five cases were declared and their exact test names checked before execution. The actual before run at producer 534c16bd6ba26f0b42d390341243204b1ac970004cb7c7ecaf65da7386bd1cd6 and test 0bc3ab5ee15ef12475f1cb2209089a26a51877aac6420e4ab01ab811bd4af4d6 is **4FAIL / 1PASS / 0ERROR**, retained without replay.

Each negative case completes the real failure-group helper inside ROOT, retains its native tuple, then returns one known invalid shape to Source on the first callback: an empty tuple, four-element tuple, six-element tuple or list containing the five native elements. Later callbacks delegate the native helper unchanged. The actual complete original spawn has already returned None inside ROOT before ROOT raises First. Its native Popen object has returned and the durable stage is spawned.

Before the change, every invalid shape was accepted. Each case records three helper calls, 59 subsequent attribute reads and a returned Source owner. ROOT records the unexpected return and asserts refusal; it never adopts the owner or invokes Source.wait on it. The saved native tuple is never filled into Source or invoked by ROOT. These are four controlled cases of one refusal gap, not four spontaneous kernel faults or evidence of the RAM cause.

The new healthy control completes the actual whole archive operation, then ROOT raises First before input checking or recipe launch. The native five-tuple preserves First and failure.json contains First. Five actual Auxiliary actors and zero recipe actors are observed. This is distinct from the earlier reserved-event, command-spawned-event and input-drift controls.

## Minimal change and after result

Only the constructor condition changes:

```python
if type(group) is not tuple or len(group)!=5:raise error
```

The existing acquisition exception guard remains. None and bool values continue to raise the already-known original First. The new check precedes pending, deferral and preservation lookups. In each negative after case, there is one helper call, zero subsequent attribute reads and no returned Source owner. Pending remains True, finished False and failure_attempted False; these fields are data, not proof of liveness or ownership.

At producer 6e04cefc79c8c4725d72a19a931903fb2d1eb5b382b2916960c75c603fbc1706 and test 3661f72f372c91cd152c6808074e191dd5dbd66ece8198f8ea72cc915acbfffa, the single selected after run is **7PASS / 0FAIL / 0ERROR**: matching NEW5 plus the missing-executable/null-status and post-spawn-journal-error/natural-wait constructor callers. The old test prefix is byte-exact; reverse-projecting the one condition restores the whole prior Source. The other eighteen helpers and three root scripts are unchanged. No earlier completed suites or before cases were replayed or aggregated into a current canonical result.

## Native actors, handles and limits

There are five new direct views per phase. Each phase records 29 original bound-wait rows: four negatives with five Auxiliary actors and one recipe actor, plus the five-Auxiliary control. All recorded waits have signed integer status zero, possibly cached. The parent after controller's 40 rows overlap the same 29 new rows and add 11 affected-caller rows; they are not forty additional actors.

Each phase separately retains 35 setup Git commands with natural zero, both EOFs and full stdout/stderr SHA and size. Popen objects, original bound waits, creator pipe identities and FileIO handles are retained before Source publication or I/O. Each negative's actual existing nonblocking read FD yields the full eighteen bytes GS-v1-outGS-v1-err and EOF before ROOT closes known handles after evidence and assertions. Per phase ROOT closes four creator pipe ends and eight file handles whose saved dev/inode still match. The healthy control's Source closes are not repeated.

Ten before and fourteen after parent official Darwin EX identity observations return None. This is scoped unit evidence, not independent physical EX, original Linux credentials, atomic ABA proof, complete FD/interpreter/delegate/descendant closure or runtime admission. Failure before the saved view or during ROOT wait/read can still mask an earlier error or prevent later cleanup. Setup/internal FD/API returns are not all serialized. No missing statuses, actor returns or buffers were reconstructed; there was no global PID scan, kill, reset, retry or full-reap claim.

## Advisory models and ROOT qualification

Qwen 25123 returned natural zero with 1711 stdout bytes and 398 stderr bytes. GLM 26136 returned natural zero with 3888 stdout bytes and 1370 stderr bytes. Both helper outputs reached separate EOF, were naturally reaped, and contain full answers. Their advice is qualified rather than whole-current approval.

Qwen's proposed ProducerError and invented pytest command were not adopted: the contract raises the original First, and the actual observed failure is owner publication. Its suggested closure/equality test was outside scope.

GLM exceeded the requested two findings. Its five-tuple element/callable concern is a prospective contract gap outside this kind/arity change; the constructor does not call group[1](). Its reset-quarantine and pop recommendations conflict with permanent refusal and process-life strong ownership, and were rejected. Tuple construction literally precedes registry insertion, contradicting its partial-registration claim. Secondary row metadata failures deliberately leave First primary. The completed-archive control is not an archive-operation failure. Finished and other fields remain data, never authority to clean up or release EX. Early registration, binding interiors, hostile restoration assignments and transitive actors remain unproved. The full frozen answers and ROOT qualifications are retained without model retry.

## Source and acceptance boundary

ROOT freshly verifies all 23 declared hashes and four Source Git results: HEAD 601108ea6216464bd00ae29c16cfaf0a59c71db6, the owned branch, exactly twenty untracked helper files, and no production packages/native diff from 601. This is source data, not compiled canonical validation or admission. The isolated runtime checkout is untouched. The planning controller was defined before its operation; its disk copy was saved after the planning call, so it is not evidence of a controller file preceding that call. A later startup checkpoint/skill read without a lease is data only, never resource authority.

The fresh ROOT storage observation is 274039500800 free bytes. The one-GiB test floors were checked before each unit phase. Storage remains subject to recheck and grants no build, capture or deletion authority; changes outside the prior completed cleanup have no measured cause.

Strong groups, closures and raw chunks remain retained for process life. The eighteen-byte fixture and logical callback counts are not heap/RSS, allocation volume, timing or leak-cause measurements. No memory bound, RAM repair, trim, reset, eviction or deletion authority follows.

All twenty helpers remain uncommitted, uncanonical and unadmitted. The provider is absent, the gate always refuses, the controller is closed, ownership is None and all three admission flags remain False. There was no Source commit, push, adoption, SDK/native build, kernel/broker/benchmark capture or strict dispatch. Original-runtime immutable admission, RAM repair, final strict 48/50 and clean final CI remain incomplete. PR132 stays open and draft on base PR130; issue103 and its milestone remain open.

## Documentation lease refusal

The first publisher was refused by the official EX lease because a local companion request was active. The refusal occurred before entering the publisher body, so there were no publication-namespace files, Git commands, archives or body edits. Its actual tool return and controller remain frozen. A fresh v2 publication namespace was prepared; the Source, tests and model calls are not repeated, and no other reservation is bypassed. The conflict is not evidence of model backend unavailability.

The evidence archive contains 1218 selected regular members, all verified byte-exact. Archive SHA256: 9a0dd75cbd956a6fd13c0ea075c261ba8de40c2119417bf893c68fbf12882621. Publication/readback receipts created afterwards are outside this snapshot.
