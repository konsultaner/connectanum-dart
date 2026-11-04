# Popen allocation ownership before constructor return

Five new controls exercise the unchanged direct-command producer. Three
negative controls call the real Popen initializer and then inject OSError,
RuntimeError or a False return. False produces the native class-call TypeError
after the real initializer has returned normally. The producer has no private
allocated-object reference before initialization or after these failures.
A fourth negative rebinds the initializer after capsule import: the declared
foreign hook runs once before any native initializer, rather than being refused.
The normal real-constructor control passes. Result:4FAIL/1PASS, with no missing
APIs. These are finite fault models and proposed ownership-contract failures,
not four observed SDK/kernel/RAM defects.

Four actual finite OWN Python children return signed0 through the same Popen
wait methods before unit FD/log cleanup. The child writes a private ready
file, waits for a private release directory or deadline and emits no stdout.
This intentionally avoids unit SIGPIPE from the producer's existing error
cleanup, which may close parent pipe copies before child exit. It is not an
original workload, stream-integrity, leak or global orphan demonstration.
The unit hook holds each actual instance before native I/O for cleanup only.
It never backfills the producer's missing reference or wait marker. Other
interpreter bookkeeping is not inspected or adopted.

The normal case verifies exact Popen class, argv/cwd, DEVNULL, original creator
writer, merged stderr, close_fds and environment object/declared unit delta.
Source wait markers stayFalse/null before and after root waits. Parent pipe
descriptors are registered before metadata; unit cleanup checks their original
identity/access and never closes a retired or mismatched number. An already
closed original read FD does not become reconstructed EOF. Private original
buffers, ready observations, signed wait returns before FD cleanup, remaining
reader suffixes and log bytes are retained. Error objects remain private;
saved reports contain native type labels and identity booleans. Unit known-FD/
writer cleanup is never a live release, retry, recovery or source-state retag.
The official EX lease and actual lease callback span these known finite cases,
on the current Darwin host only.

Two setup attempts precede the meaningful controls. V1 supplies an unsupported
environment keyword and omits the required lease callback: all five calls stop
before the producer body/native constructor. Its4FAIL/1vacuousPASS and zero
children are not ownership defect counts. V2 uses valid kwargs but passes
noncanonical /tmp aliases; all five stop before a native constructor and the
final boundary assertion refuses its counts. Its case reports remain, but no
summary exists. Earlier exception text was not serialized and is not rebuilt;
the canonical violation is inferred from passed arguments and the source
predicate. V3 resolves its reserved root canonically, retains the producer at
entry and reaches all five declared boundaries. Only setup-blocked,
nonnumerical controls run again; no original numerical data is retried.
All versions and their namespaces remain intact.

The selected repair is UNIMPLEMENTED. It will capture the exact class,
resolved standard allocator and initializer references, check bindings before
allocation/initialization, and retain a distinct allocated_process reference
immediately after allocation and before initializer I/O. The existing
attempt.process/self.process assignments remain after normal construction.
The initializer must return None, preserving native class-call semantics.
New stage facts and frozen DATA schema must retain an allocated but partially
initialized object without inventing pid/status/liveness or permission to call
methods. Ordinary successful argv/env/stdio behavior must match the original.
The original public spawn repr/add_note/pipe/error/end/finish policy remains
outside this narrow repair and can still mask errors or close pipe copies.
No fallback constructor, subclass, SDK/flag change, destructor/GC discard,
global bookkeeper lookup or unknown-actor cancellation is authorized.

GLM32217 design, Qwen32605 tests and Qwen33884 coordinator review complete0
and are reaped. All advice is qualified by ROOT. ROOT accepts pinning initializer/
allocator and a distinct allocated field, and corrects the suggestion to fetch
inherited __new__ directly from vars(Popen). Local descriptor observations
show the current administrative allocator is object.__new__; that is data,
not loaded-image/original-host proof. ROOT rejects the tests' before-native
fault description and treating the object as garbage: the real initializer
finishes before each injected negative. None-only return validation is required.
The review's pipe-boundary finding is false: _spawn creates the source pipe
before invoking Popen, independently of stdlib internal pipes, and every V3
boundary check passes. Its claim that False is an allowed initializer return
is false; the native TypeError boundary is intentional. No control is softened
or rerun to answer those findings. This is no model approval of the whole
current source or physical closure.

Source b21de603411cae89e1956f78057e8ff9e702b3b3a1e2fcfb4fc1b39be04f84c6
and test45087533599c3d141513bd6c60660712cd36dcc31606e15b717a2e21f399957b
remain unchanged. All23 selected source/bin hashes match before and after
controls. Only the exact held producer buffer is compiled in private capsules,
not a current20 canonical or native build. All20 helpers remain uncommitted,
uncanonical and unadmitted; production601 is unedited. No fresh source Git query
is run for these read-only controls; the prior branch/HEAD observations remain
historical. Private controllers are retained artifacts outside HELPERBUNDLE20.
Before controllers V1-V3 are saved before execution; new model controllers
are serialized after calls with separate command-before receipts. No ordering
fact is execution admission.

Next implement the retained allocator and matching meaningful regressions,
then address original spawn cleanup, historical continuation/log sealing,
transitive generic FDs, audit partial/unknown actors, writer/interpreter/
delegate/descendant coverage and the full actual officialEX controller.
Original PATH/SDK/bootstrap/first3locks/hiddenconfigs/current20canonical/new
source package/OWN native-driver-static RLIB/compiler-tool-kernel and actual
original-host credentials/access/pidfd/FDexec/inheritance/arming/metadata/role/
time/coverage remain required before ROOT-qualified immutable COMPLETE
admission and diagnostic data. No source-branch commit/push/adoption/strict
dispatch, borrowed cohort/config/native transplant, favorable redo or postGO
as preproof. Existing emit/auxiliary predicates stay closed.

Provider absent, live gate always raises, controller closed, ownershipNone,
all three flagsFalse. No actual SDK/native build/canonical/kernel/broker/
benchmark/capture, RAM cause/repair or strict acceptance. Latest assessment
free11.73GB is below12GiB: build floor CLOSED; recheck before any build.
Scoped tests use their separate1GiB floor. Cause unmeasured/no cleanup.
PR132 stays OPEN DRAFT on130; issue103 and milestone remain OPEN.
