# Owned buffer observations and packed reply retention

The live clone traces identify a reply representation loss: Invocation.respondWith
reuses the packed bytes but retains an ordinary argument wrapper. The FlatBuffers
writer consequently re-encodes that wrapper as CBOR, and the receiving native
client copies the model during application decode. Retaining the original
matching packed lazy view preserves the opaque vector and its source owner.
Encrypted replies continue to use the outbound provider and fresh nonce policy.

Twelve reply regressions pass, including success/error, empty/64 KiB bounded
spans, exact CBOR/MessagePack/JSON bytes, plain replies, error context and retry.
For two native 64 KiB RPCs, clone bytes fall from 268,847 to 6,531: 262,316
actual bytes of redundant model copies disappear. The initial 8,968-byte total
was a narrower observation before native model construction was instrumented;
it is not a whole-pipeline total. With construction counted, the current probe
observes 140,040 Dart bytes, including 133,093 byte-vector bytes. No macro
performance improvement or parity is claimed from this functional probe.

Cumulative Dart observations are opt-in and isolate-local. Each field counts
logical source bytes at actual explicit buffer operations. Scalar encoding,
object graph allocation and dependency internals are separate. Nine categories
cover clones, coalescing, FlatBuffers vectors/growth, isolate transfer, framing,
keys, PPT and portable crypto. Unknown allocators and failed partial operations
prevent complete observations. Dedicated PPT scopes suppress generic primitives
and report once into the cumulative PPT field, including outside a dedicated
benchmark window. Dedicated PPT/provider and builder diagnostics are overlapping
subsets; they must not be added again. A fail-first case reproduces the former
zero outside an active PPT window. Model vectors and native allocator growth
have exact-once regressions.

Router boss and state store share the main isolate. Observed workers are enabled
before authentication/processing; snapshots fence previously submitted async
commands and hold later commands. Snapshot replies use the worker's ordered boss
event port, after preceding worker sends. Missing workers, generation changes,
failed work and timeout fail closed. The server also requires successful workload
quiescence. These observations currently remain individual components; a full
pipeline aggregate is not yet certified.

The separate optional native codec ABI v1 contains six uint64 fields (48 bytes):
vector, UTF-8 string, allocator growth, segmented parser reads, encoded metadata
appends and key material. Existing raw-frame v1 (32 bytes), crypto v1 and other
published layouts remain unchanged. Missing or unknown versions are unavailable,
never zero. The native FlatBuffers allocator copies its old suffix into new
storage at growth and preserves collapse-to-Vec ownership. CBOR/MessagePack
metadata prefixes reserve their metadata plus a 37-byte upper bound for scalar
headers; binary wrappers reserve ten bytes. Explicit encoded appends are counted;
these sites do not rely on implicit Vec relocation. Dependency encoding internals
remain unmeasured under the approved standard SDK scope.

Current checks: 371 Rust core, 294 FFI, 3,383 shared serializer/PPT cases, twelve
reply cases, exact native vector/growth checks and thirteen live router/copy,
portable/native, both-cipher, typed/CBOR and encrypted-file cases pass. ABI guards
and fresh-process key probes verify layout rejection and the two native key
copies. Workspace analysis exits zero with existing informational lint notices.
The first full native run finds the new missing crate re-export, repaired before
the passing run. An earlier test assumes zero metadata vector bytes; the source
actually copies the one-byte empty options dictionary, now checked explicitly.

The preceding control-construction diagnostic improves native throughput ratios
from about 0.80 to 0.82–0.83, but allocation and latency still fail. All paired runs
remain macOS diagnostics, not the full Linux acceptance campaign. New-source full
verification, production artifacts, audited E2EE/transcode aggregation and parity
remain open. Evidence is retained under ignored out/flatbuffers-milestone-finish;
no threshold, inventory, campaign case, duration or minimum sample is reduced.


The completed hosted predecessor has 39 passing checks. Client message-binding
mutation fails at 94.3359375% against 95%; Full Verify is its downstream aggregate.
A 24-case binary storage matrix exposes a real ERROR guard bug: its message text
was interpreted as a PPT scheme. ERROR now checks its actual metadata. Ordinary
CBOR/FlatBuffers values remain independent copies; MessagePack retains its prior
decoder behavior. The initial matrix incorrectly assumes ordinary MessagePack
bytes are mutable; that assumption is removed, without changing that codec.
All 1,910 binding cases pass. Four exact preceding survivors fail by assertions
with input restoration verified. The first replay hits local temporary-storage
exhaustion; removing only this task's rebuildable Rust debug caches allows the
complete four-case replay to pass. The full inventory and hosted gate remain
required; these four cases alone do not certify the gate.

A self-versus-external idle VM diagnostic finds 2–3 measured GCs with self
observation versus 0 for external observation. Both allocation totals are large
and the external totals grow by 61,872 bytes per window despite reset requests.
This is a measurement lead, not proof of allocation semantics or a correction.
Profiling overhead/baselines must be investigated before accepting resource
parity; no budget is changed. The full raw observations and standalone repro are
retained in ignored output. The prior long local review attempts time out or
receive incomplete function ranges; their output is not accepted as a completed
review. The smaller complete-function review remains advisory.


The complete client-binding campaign now passes: 633/633 generated/selected,
500 killed, 117 compile errors, 16 survivors, no runner errors/timeouts; adjusted
assertion score 95.93023255813954% at the original 95% floor. Its clean/restored
baselines pass and pinned client/core inputs are unchanged. Changes to the
independent tooling inventory guard and unrelated router worker are audited
separately; the whole repository did not stay unchanged throughout that scoped
campaign. The first full frozen verification fails only on the independent
wrapper inventory guard, fixed by adding the new test to the expected set.
The second frozen run reaches three failing public JSON/FlatBuffers PPT cases.

Retaining a packed FlatBuffers reply exposes a router fallback gap: JSON sends
a bare binary string instead of its required singleton Arguments list. The
router now creates a shallow view of the seven payload message types, retains
the same binary span and original owner, and serializes ordinary Arguments.
This preserves the source representation for other fan-out destinations and
leaves the JSON codec API unchanged. Fourteen unit cases fail first on the old
wire shape, then pass for empty/bounded 4096-byte spans, all seven control types,
metadata/progress/error fields and unchanged original FlatBuffers fragments.
All 107 public mixed/PPT/E2EE cases pass, including the three full-run failures.
A bounded local review finds no confirmed defect; its speculative anchor concern
is checked against the actual strong storage-anchor implementation.
The [WAMP payload-transparency structure](https://wamp-proto.org/wamp_latest_ietf.html)
requires one binary item in Arguments; JSON uses the binary-string convention.
Fresh full verification and complete pipeline/performance evidence stay required.
