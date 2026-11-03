# Worker-only wait on one retained command

A failed, uninitialized preflight owner can now schedule a bounded wait on one
exact retained command. The worker drains the original merged output pipe and
waits on the same Popen. It does not run source/version/input audits, spawn the
next command, end/finish the producer, close its log or attempt publication.
The producer remains pending and its log remains open. Cached terminal data
only refuses another wait; it grants no actor closure or lease-release authority.

The existing busy, actual Thread-join and settled-start guards apply. Exact
producer/Popen/record/log/auxiliary handles are retained before fstat/callback
I/O. Only the serialized worker inspects partial fields. Missing/unknown fields
or observed identity drift quarantine the owner. Checks are bounded observations,
not atomic identity, writer authentication or global ABA prevention.

Observers receive immutable scalar data. Primitive values are copied and type
checked before publication. Callback return is checked again before pipe I/O;
unknown kind values are rejected before custom equality can run. Original and
per-call exceptions stay exact/private, with type-only public records. Existing
producer error hooks are unchanged. All three admission flags remain false and
actor ownership completion unknown.

One initial coordinator fails its main-marker assertion before source writes or
tests; the terminal attempt is retained. The first eight guards produce13errors
solely because the new API is absent, including timeout subtests. This is not
13production defects. Initial11guards pass: eight new cases and three required
existing callers. Three later guards fail in turn: callback drift reaches the
mocked drain boundary, an unknown kind invokes custom equality, and a post-check
non-scalar marker escapes into the cached observation. These preparation
regressions are corrected; they do not measure hangs, CPU/RAM cost or RAM cause.
The scalar edit first introduces an existing auxiliary caller error through a
wrong text-replacement target. The original auxiliary method is restored
byteexact and the pid check scoped to the new method. Final14guards pass:
eleven new command guards and three required callers. Earlier11/2/13/failed14
results remain separate, without combined or full-canonical claims.

The fixtures use actual finite OWN Python children with one merged stdout/stderr
pipe and a private directory release protocol, not GO. Source/archive/input
guards are mocked and provenance always FIXTURE. The mocked factory raises
after the actual fixture constructor returns a pending command; no original
constructor failure, canonical/native build or SDK execution is observed.
Known new fixture children naturally return0 with merged EOF and matching
stream/log digests. The next command remains unlaunched. Private fixture
teardown drains the same child, closes its known log/journal and restores
malformed or synthetic test fields; it is never a live recovery workaround.
ROOT holds the actual official EX through known fixture workers/children;
unit lease callbacks are synthetic. Not every returned view or legacy Git setup
API return is systematically serialized. No omission is reconstructed by rerun.

Gemma summary, GLM design, Qwen test advice and Qwen review complete direct0,
advisory. ROOT selects wait-only design A and rejects terminal-state retagging
to satisfy the auxiliary predicate. ROOT qualifies GLM's lock/deferred-failure/
uncertain-write descriptions and rejects Qwen's invented exception/API names,
global-lock atomicity, quarantine-close and positive-timeout suggestions.
fileno/fstat allocate no new FD; existing handles deliberately remain retained.
The selected review precedes final scalar sealing and restoration hunks; ROOT
checks the complete affected final methods and tests. No model final-current
full-source approval is claimed.

Every original module-level function/factory/emitter/gate, CommandProducer and
AuxiliaryCommand class, other original owner methods/test classes, other18tools
and selected3bins are byteexact. Only original owner init/schedule/work methods
are extended, with new methods and io import; producer/test source changes are
uncommitted, uncanonical and unadmitted. Production601 remains unchanged.
The registry/history/retained handles are process-lifetime data, not heap/RSS
bounds. HELPERBUNDLE20 stays twenty; private coordinators are separate artifacts.
No source-branch commit/push/adoption or strict dispatch occurs.

Full command/log finalization, recipe/auxiliary/unknown-actor orchestration,
physical EX lifetime, original-PATH SDK/bootstrap inputs and initial runtime
locks/configs still require completion. Current20 canonical, compiler/native/
driver/RLIB and original-host kernel/privileged access/role/clock/coverage
provenance are unproved. require_live_admission still refuses, provider absent
and live SessionController closed. No original workload/benchmark/capture,
RAM cause, repair or strict acceptance. About15.2GB is observed above12GiB;
recheck before build, no cleanup and overall space-change cause unmeasured.
