# Exact preflight worker joins retained; live admission remains closed

A retained worker can publish call completion before its actual Thread target
returns. A deterministic finite fixture holds that target tail on an owned
Event. The former next-phase path starts another worker and overwrites its
sole retained Thread handle while the prior target is still alive. This is an
actual unit regression in the preparation helper, not an observed canonical
build, production performance or RAM failure.

Each preparation call now has a retained record before thread creation/start.
The observer joins the exact held Thread outside the owner lock with a bounded
wait. Another producer phase requires both that join and a settled parent
start outcome. Call completion, worker join, parent start outcome and actor
ownership remain separate. Public lifecycle views contain immutable scalars;
actor ownership remains unknown and every admission flag remains false.

Setup/start uncertainty retains its attempt and handle. A join error retains
its exact exception privately and publishes only its type, independently of
the first producer error. Further observation can join that same Thread.
There is no restart, cancellation, reset, generic actor drain or GO authority.
Owner and scalar call history remain for the process lifetime. A per-call
Thread reference is released only after successful join; the latest Thread
also remains held by the owner. These logical records establish no heap/RSS
bound or physical official-lease lifetime. The caller still holds the actual
exclusive lease through every known actor.

Before correction, five selected guards produce one failing target-tail
overlap regression and four errors for the missing lifecycle API. The four
API errors are not four production defects. Fourteen selected guards/callers
then pass: five new join guards, five current emitter interface callers and
four required owner callers. Two further selected tests pass separately: a
new parent-start outcome barrier and the join-error guard strengthened to
assert that joining occurs outside the observer lock. The implementation is
byteexact between those runs. This is not a combined sixteen-test run or full
canonical verification.

All original module-level functions, factories, emitter bodies and gates,
all original test classes, four unchanged owner methods, the other eighteen
tools and selected three verification scripts remain byteexact. Only the
producer/test pair changes. Production601 remains unchanged. All twenty tools
remain uncommitted, uncanonical and unadmitted. Historical Darwin/Linux
controls retain their original source bindings; they are not current-source
execution proof.

The tests use finite owned Python/Git actors and Thread barriers under the
official exclusive lease. Existing fixture Git setup returns and every
returned unit lifecycle view were not systematically serialized. Exact
executed snapshots, logs and all selected regular fixture files are retained;
there is no reconstruction, all-descendant/all-writer or atomic identity claim.
An initial edit coordinator fails its string-match assertion before source
write or test execution; its exact code and direct failure status remain
retained. A corrected coordinator performs the declared edit.

Qwen test planning completes with direct status zero. Root accepts Event and
same-handle ideas, and rejects invented timeout/rethrow APIs, pytest commands,
termination and indefinitely blocked fixtures. The GLM design request reaches
its response limit with no saved full partial/final assessment; its outer
signed status was not retained and is not invented. The Qwen selected-diff
review reaches its token limit with direct status one and no saved full
partial/final assessment. Both backends are reachable; neither outcome is
unavailability or approval. Neither request is repeated. Root reviews the
complete affected methods and final test changes; no full model approval is
claimed.

Space remains about8.6GB, below the unchanged12GiB build floor. No cleanup or
actual canonical/build/native/SDK/original-target kernel/broker/benchmark/
capture/strict dispatch occurs. Space-change cause is unmeasured. Independent
orchestration, current own source/archive/canonical/native/driver/RLIB/locks/
configs/SDK/compiler/tool/kernel provenance, original-host controls and
immutable complete admission remain required before diagnostic data.
The live provider is absent, admission always refuses and the live controller
stays closed. No RAM cause, repair or strict acceptance is established.
PR #132 remains open and draft; issue #103 and its milestone remain open.
