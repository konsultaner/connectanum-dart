# WAMP and Mutation Diagnostic Repair

Status: active.
Started: 2026-11-19.
Base: `0a3d96e663363e8d1830baeb127cf4e33c6bbf41` (`github/master`, merged PR #138).
Branch: `codex/fix-wamp-mutation-diagnostics`.

## Objective and acceptance

Repair the WAMP and mutation diagnostic failures and prove the complete final
workflow inventory green. Preserve all numeric thresholds, 95% assertion gates,
complete mutation inventories/operators, existing tests, workload sizes,
repetitions, deadlines, queue bounds, warm-up/drain intervals and evidence rules.
Do not hide failures by disabling diagnostics, filtering survivors, or adding
unproven equivalence/exclusion entries. Production GC/allocator tuning is outside
this repair. Preserve unrelated work on `codex/mutation-runner-speed`.

- [x] Complete fresh-master `bin/test-fast` baseline.
- [ ] Reproduce each failure with a focused regression or minimal matched case.
- [ ] Fix native restored-baseline failure and demonstrate complete clean inventories.
- [ ] Fix full MessagePack VM/web and MCP/CLI diagnostic assertion failures.
- [ ] Fix WAMP fragmentation/file-transfer throughput against original floors.
- [ ] Run focused validation, local companion review and complete `bin/verify`.
- [ ] Publish a reviewable branch/PR and run all diagnostic and regular workflows.
- [ ] Audit every final workflow/job, with no unresolved failed required work.

## Original evidence

Merge `0a3d96e6` passes all 55 mandatory CI jobs, all sixteen gateway shards,
ObjectBox, package dry runs, kTLS validation and the standard WAMP benchmark.
Its diagnostic workflows remain red:

- WAMP run 44530794223: fragmentation and file-transfer gates each report five
  findings against unchanged 2,000-Mbps floors. Payload-mode throughput also
  crashes at the large CBOR PPT RPC (`NativeByteSnapshot.toCbor`), then times
  out. Both heavy file-transfer and RawSocket gates pass.
  Artifact 14533488631 digest:
  `31f8796d855f6d190cd6eaa62743a8563dd841862de31306e7683e01fb7a02e2`.
- Mutation run 44530794131: four native jobs fail restored-baseline validation;
  MessagePack VM/web scores are 3.1111%/88.4444% against 95%; native MCP CLI
  adjusted score is 68.9773% against 95%. E2EE web is cancelled and the full MCP
  job is still running at initial inspection. No incomplete result is accepted.
- Read-only audit: `/tmp/connectanum-master138-ci-audit-20261119.json`.
  Bounded GLM triage: `/tmp/connectanum-master138-compact-triage-20261119-result.txt`.
  These logs establish failure signatures, not an SDK regression or matched
  performance cause. Ollama's first broad triage timed out; the independent GLM
  triage completes and is checked against raw logs.

## Working record

A fresh isolated worktree starts at fetched `github/master`; the user's original
worktree and unrelated mutation-runner history are unchanged. Initial bootstrap
and `bin/test-fast` complete successfully (43 passing suite markers, final
zero-copy worker suite 11/11). Native isolation omitted both schema JSON files
and 42 binary FlatBuffers fixtures; compile-time and runtime fail-first tests
now cover copying and tamper detection. A real lazy echo handler reproduces the
WAMP PPT crash before carrier materialization; all eight new transport/mode/codec
cases pass afterward. The first native campaign is retained as a rejected
missing-binary-fixture run. Full native and MessagePack inventories are running. Qualifying source/test/tool files and original
policies will be fingerprinted for each accepted run; rejected/interrupted
experiments retain their separate evidence.

### First repair evidence

- Native fixture v2 now compiles and restores all 60 WAMP baseline tests. Its
  complete 402-mutant inventory remains red: 207 assertion kills, 117 errors,
  69 compile errors, six survivors and three timeouts. The audit remains strict;
  crashes/timeouts do not earn assertion credit. Raw evidence is retained at
  `/tmp/connectanum-diag-native-wamp-v2-20261119`.
- The six survivors comprise a redundant empty-slice copy guard, eager CBOR
  payload decoding guards, an OR/XOR-equivalent integer assembly loop and two
  unreachable null match arms already precluded by map admission checks.
  Reader timeouts come from corrupt progress/index updates. Standard checked
  slice/byte readers and explicit allocation/progress assertions are next.
- WAMP regression now uses the actual lazy benchmark echo handler. Original
  CBOR PPT fails with `NativeByteSnapshot.toCbor` then RPC timeout. Materializing
  internal carriers before PPT/wire conversion passes eight workload cases and
  four additional byte-exact RPC cases with nested 64-KiB binary values whose
  results remain independent after input mutation and session closure.
- MessagePack has a real stateless portable backend shared with production
  fallback and VM/Chrome tests. A one-shot iterable fails on the original JS
  delegate-then-retry path; selecting portable encoding before consumption fixes
  it. All 202 Chrome cases pass. A BigInt reference checks signed/unsigned word
  pairs around +/-2^53 and representative high/low boundaries on both runtimes.
  Complete VM v4 inventory: 205 selected, 196 viable, 182 assertion kills and
  14 survivors, raw assertion score 92.8571%, still below the unchanged gate.
  Candidate equivalence proofs are reviewed separately; no unproved waiver or
  changed kill classifier is accepted.
- MCP CLI positive tests assert completion. The real-router response proxy now
  exercises wrong status, session-header and body diagnostics; all 404 HTTP and
  option cases plus 118 native-router cases pass. A bounded protocol oracle
  asserts one resource-notification poll and aborts unexpected repeat requests,
  so corrupt filter mutants cannot hide behind a five-second polling timeout.
- Original full MCP job finally completes at 18:55 UTC: 2,308 selected, 1,719
  viable, 1,227 conventional kills, 492 survivors (470 CLI), raw strict score
  70.8551%. Complete artifact 14564173801, SHA256
  `e0dab1634d60f1cfadc8a7838bcf0990cfcfc6618fba281f8ab449e587790957`.
  Its existing test scope omits native CLI integration; add those tests without
  removing any existing source/operator/test or relaxing deadlines.
- File IO profiling alternates both methods over identical 64-MiB inputs, four
  reads each, six measured rounds: readInto median 109,015.5 us versus owned
  read buffers 52,962 us (individual ratios 1.83--2.18). This is exploratory,
  not hosted throughput qualification. The owned-buffer regression fails on
  original code, then all 98 file-transfer cases pass after eliminating the
  extra destination copy. Partial-read assembly, reopens, EOF, cancellation and
  error cleanup preserve the original chunk and backpressure contracts.
- Local GLM review completes. Its proposed negative-boundary correction is
  rejected: -2^53 + low is inside the range for low >= 0, independently proved
  by BigInt tests on VM/JS. Its map-cast warning is precluded by the marker/type
  guard, glob on a missing directory returns an empty iterator, and decode input
  is a buffered Uint8List rather than a consumable stream. Broad local-model
  requests timed out or hit output limits; bounded tests/arithmetic reviews work.

No source is pushed and no final workflow qualification is claimed yet.

### Reviewable checkpoint

The full local MessagePack VM v5 run completes all 205 mutants and passes the
unchanged adjusted 95% gate at 95.2880%, preserving raw score 92.8571%, all 14
observed survivors and five independently checked source-hash-pinned functional
proofs. See [the proof record](../msgpack_mutation_evidence.md). No crash/timeout
classifier, numeric budget, operator scope or source range changes.

The full MCP target retains all existing sources/tests and adds the native CLI
integration it previously omitted. Existing MCP cases retain the five-second
per-test default; the added integration file declares its existing native CLI
20-second timeout. Clean/restored full MCP baselines pass with all 2,308 mutants
still inventoried and the native binary unchanged. CLI-native deadlines stay
20 seconds per test and 45 seconds per complete command sequence.

Slow diagnostics now partition complete inventories: eight web shards each,
sixteen full MCP shards and eight native CLI shards. Original 60/360-minute
job deadlines and 45-minute Rust deadlines remain unchanged. One same-run
ffi-test artifact is checked against source, toolchain, dependency lock and
binary identity in every native shard and its independent aggregate. Tests
reject missing/replaced native artifacts and missing unchanged receipts, along
with existing duplicate/incomplete/tampered inventory/log/source/test cases.

Focused checkpoint checks: 62 native WAMP tests, 99 file-transfer tests, 202
Chrome codec cases, 404 CLI HTTP/options cases, 118 native CLI cases, complete
MCP baselines, native mutation tooling and 114 mutation-runner/CI execution
contracts (one existing host-specific skip). Final full bin/verify and hosted
all-workflow qualification are still outstanding. The first hosted checkpoint
is an explicit draft, not a claim that all diagnostic targets are green.

### Hosted checkpoint findings

Draft PR #139 at `2fe7337a` retains the complete diagnostic scope. MessagePack
VM and all eight browser shards pass. WAMP run 44598752416 completes all eight
scenarios: the PPT crash is gone, but fragmentation (nine findings), buffered
file transfer (four) and heavy RawSocket lifecycle (one) still miss unchanged
2,000-Mbps floors. Artifact 14568525535 SHA256:
`78fd8a8afcda067373345b104bcdd46e6f7d3165973c1b0c4f08c5a2bd75cd88`.

The hosted full MCP baseline exceeds its original 45-second command deadline.
The full native integration is now scheduled first and independent Dart test
file isolates overlap at concurrency two. A local matched complete run is
27.26 seconds serial, 21.86 seconds at concurrency two, and 19.46 seconds with
the native file first. All files, assertions, mutation inventories, five- and
20-second per-test timeouts and the total 45-second deadline remain unchanged.
This timing is exploratory until hosted qualification completes.

Two frozen-input full verification attempts are retained: the first reveals
four missing serializer helper manifests and obsolete exact workflow-upload
counts; the second passes those and detects the test-only allocator module
changing a historically coverage-pinned MQTT source. Move that observer under
WAMP's test module and restore `ct_core/src/lib.rs` byte for byte. The exact
historical coverage-hash assertion remains intact. No final green claim yet.

The CLI-native baseline also times out in the checkpoint: its separate HTTP,
option and native processes consume 11.44, 2.13 and the remaining 31.43 seconds.
Use the existing single Dart test-command mode for this target, with two
independent test-file isolates and native first. Preserve all three files and
20-second per-test / 45-second whole-command limits. The original assertion,
load/error/timeout classification code is untouched; concurrent test-file
reporter evidence uses the same fully completed command classifier as full MCP.

Overlapped clean/restored baselines pass locally for full MCP (2,308 selected)
and CLI-native (1,207 selected), both with unchanged native binary receipts.
The concurrent real-reporter regression confirms assertion/mixed failures,
error-only failures, elapsed test deadlines and abrupt process exit retain their
original strict classifications. The focused local review identifies no verified
correctness defect: every execution/listing path builds the validated command;
config bytes and recorded commands already bind independent shard auditing.

### Native progress, strict batching and JSON input ownership

The complete local RawSocket repair run preserves all source/test/tool inputs
through clean, mutant and restored phases: 92 generated, 87 strict assertion
kills, five compile errors, zero survivors/errors/timeouts. Shared portable
sendfile result/progress handling replaces duplicated host-specific loops;
only the actual syscall signature remains platform-specific. Kernel counts,
EOF, explicit file offsets, interruption and permanent error identities retain
coverage. The existing zero-survivor gate remains per host; no cross-host OR
waiver is introduced.

Complete WAMP v3 records 241 assertion kills, 76 compile errors, 12 errors and
two survivors (331 total). The failures identify unchecked header slicing,
a pointer-derived test offset lacking a preceding ownership assertion and a
custom UNREGISTERED test panic. Safe range access and standard assertion
oracles address those cases; a populated generic payload test checks the last
unexercised helper against independent wire encoders. All 426 native Core tests
pass afterward; complete post-fix mutation evidence is still required.

Three hosted native jobs exceed their original 45-minute deadlines. Complete
inventories are now distributed across four RawSocket/eight WAMP batches per
host with unchanged 30-second mutant/180-second build limits. Every batch
retains clean/restored full test inventories and its complete pinned candidate
inventory. The independent aggregate regenerates that inventory, rejects
missing/duplicate/tampered evidence, reclassifies raw logs and requires zero
survivors with no errors/timeouts. Original whole-component users retain their
95% API; diagnostics explicitly use `--require-all-killed`. One same-run Cargo
lock is shared across batches and their per-host aggregates. Dynamic binary
fixtures are hash-bound alongside the schema/TLS fixtures. Real tiny Rust
fixtures verify both narrow target batches and all original test deadlines.

New E2EE tests preserve preflight-validated plaintext/ciphertext when an
application key policy replaces arguments, and authenticate a typed XSalsa
payload above the legacy wrapper's one-MiB cap. All 169 browser cases pass;
focused, explicitly partial counterexample replay kills three former survivors
with assertion evidence. Full-inventory browser qualification remains required.

Actual JSON file CPU samples identify the String-to-byte conversion. The
native String accelerator fills one native ASCII input allocation and reuses
the existing owned-output decoder; explicit app byte/String decoders and the
generic fallback stay authoritative. All 65 browser JSON / three native
boundary tests pass, including Unicode outside the encoded span, malformed
canonical input, independent mutable results and explicit release. Four
alternating matched canonical local runs improve WebSocket data median
1,068.733 to 980.729 ms and lifecycle 1,146 to 1,071 ms; these are exploratory
Mac observations, not hosted floor qualification. A separate event-loop pacing
candidate is rejected after poorer measurements and is not shipped. Temporary
VM CPU instrumentation and profiling subsets remain outside the branch.

The superseded hosted checkpoint is cancelled after its completed artifacts
are retained, freeing runners for the current source. PR #139 remains draft;
no merge or release is authorized for it. All numeric policy JSON files,
workloads, serializer/security matrices, queue bounds and GC defaults remain
unchanged. Final quiet `bin/verify`, review and complete final-head workflow
qualification remain outstanding.

### Checkpoint f604 hosted results and ordinary MCP success oracles

Checkpoint `f604a27e` publishes the native repair and complete native batching.
Its WAMP run 44615131514 still fails fragmentation, buffered file transfer and
heavy RawSocket lifecycle floors. Artifact 14574519151 SHA256:
`2ca9dedffe4cf7a761289396e94ee2104389dd7ff2d3f1e20a6e245692852190`.
All eight workloads execute; the same 2,000-Mbps floors are retained. The native
String adapter alone does not qualify the affected paths. Final optimization
and hosted proof remain outstanding; no successful WAMP claim is made.

Core browser coverage at `a4d6dd92` reports 177/182 MessagePack codec lines,
97.253%, below its unchanged 97.29% floor. Pairing each legal width and exact
byte-data reader removes the unreachable invalid-width branch. A real Chrome
probe now covers 178/182 (97.8022%). A complete 205-candidate VM mutation run
passes again at 95.288%, including clean/restored baselines and the same five
revalidated hash-bound functional equivalences. Final hosted coverage is pending.

MCP partial results reveal a test-oracle gap: the standard `completes` matcher
forwards deliberate CLI `StateError` validation rejections as test errors. The
success helper now explicitly asserts that a valid exchange is not rejected by
that product validator. Other exception classes and deadlines retain their
original classification. A completed child exit 255 is treated as a public smoke
rejection only with explicit unhandled MCP/example-smoke stack evidence; compiler
exits, signals, missing assets, unclassified failures and any nested timeout still
fail setup. All 20 classification-boundary tests pass. Focused replay detects the
former WAMP-metadata setup failure with ordinary assertion evidence, while the
strict runner classifier is unchanged. This is a partial counterexample replay,
not full-target qualification.

A SHA256-pinned fixture retains all 208 real public-router HTTP exchanges and
exact CLI output. Fast protocol regressions check every baseline request/output,
single-response faults, exact rejection diagnostics and cleanup-only behavior.
The native integration cases remain intact; every target executing the new CLI
suite explicitly snapshots/hashes the compressed fixture. The full current CLI
inventory is being replayed independently to identify remaining negative cases.
Complete final-head MCP/native/browser campaigns and quiet bin/verify remain
required; PR #139 stays draft.

The hosted RawSocket batches expose colored compiler diagnostics rather than a
new native survivor: three actual `error[E0277]` build failures on each host
contain ANSI escapes from GitHub's `CARGO_TERM_COLOR=always`. Every native
campaign and restored command now explicitly requests `CARGO_TERM_COLOR=never`
before capturing raw evidence. The strict classifier, phase/status checks and
zero-survivor policy are unchanged. All 57 native tool tests pass; a current
raw batch under an inherited `always` environment remains to be replayed.

The first complete fast CLI replay is diagnostic only: all 1,207 disjoint
candidates are retained (697 detections, 327 compile failures, 183 survivors).
This configured CLI-only target omits no test from its own inventory but does
not replace the mandatory native/full MCP aggregates. Of the 148 previously
non-assertion/undetected partial native cases, 71 now have fast-test detections.
Further regressions observe actual owned HTTP clients even when idle, retain
original infrastructure exceptions and reap leaks after recording the failure.
They add the existing 1,024-page catalog boundary and procedure-only/topic-only
metadata cases. No source/operator or native suite is removed and no deadline
is extended. Final complete-native/full-MCP scores remain unqualified.

The complete MCP/CLI inventories now use 32/16 disjoint hosted shards rather
than 16/8. This preserves every configured test, source and operator and each
original 60-minute job / 45-second command / five- or 20-second test deadline;
full native sessions are still exercised for every assigned mutant. The same
independent full-inventory aggregates require all shards, reclassify raw logs
and enforce the original 95% threshold. Partitioning reduces total per-job work
instead of extending any execution deadline. No release workflow is dispatched.

Current local controls pass: 451 fast CLI tests, 20 child-smoke classification
boundaries, clean/restored full MCP and native CLI baselines (2,308 / 1,207
inventoried mutants), and 117 mutation-runner/CI contracts (one existing skip).
The RawSocket batch replay under inherited `CARGO_TERM_COLOR=always` now has
20 assertion kills, three compile failures, no errors/timeouts, clean evidence.
The proxy enforces its existing one-poll oracle before forwarding, so an
unexpected empty upstream SSE wait cannot masquerade as mutation evidence.

Native full-frame and deferred JSON binding now use the SDK's fused UTF-8/JSON
decoder, retaining normalization, strict malformed-input handling and ownership.
All 1,895 binding cases pass on VM and real Chrome/Wasm, including BOM/nonzero
offset views, large strings, Unicode/surrogates, binary markers, malformed UTF-8,
trailing data and retained decoded values after input mutation. A matched AOT
microcomparison reduces 16 four-MiB decodes from about 80 to 31 ms; this is not
hosted throughput qualification. Canonical native JSON pub/sub comparisons and
a separate file-write backpressure experiment remain exploratory. The earlier
fused JSON encoder prototype was slower and is not shipped. No temporary CPU
profiling code, pacing timer, allocator setting or GC override is included.


### 20 November: completed-product oracles and measured native candidates

The b6 checkpoint's WAMP diagnostic run 44628365501 completes all eight scenarios;
six pass, including both heavy cases. File-transfer RawSocket JSON lifecycle,
WebSocket CBOR/MessagePack lifecycle and WebSocket JSON data/lifecycle still miss
the unchanged 2,000-Mbps floors. TLS JSON fragmented pub/sub lifecycle and TLS
CBOR contiguous pub/sub data/lifecycle also remain below that floor. Retained
artifact 14581311683 SHA256:
`b2fd5b6a00b845dbb69c714555d49846731ea192dc4884640ef69e885dd9bb0f`.
This is a failed checkpoint, not final qualification.

Hosted MCP shard 26 times out its clean baseline without test failures. Ten
new positive metadata cases repeated complete native CLI sessions. Preserve all
ten names and operation assertions, but lazily capture four completed transcripts
by response shape; each non-wrapped capture rewrites count/list/get together and
asserts all three responses and final session deletion. Sessions remain sequential,
with original test concurrency and deadlines. Clean/restored full-MCP baselines
pass locally with all 2,308 source/operator candidates inventoried. That baseline
predates the final extra declaration/header controls and must be repeated.

Compatibility proxies preserve discovery/nested paths and assert initialization,
negotiated subscription/poll session identity and consumption of a delivered
resource update before forwarding another SSE poll. Completed exit-255 public
smoke errors have narrow product/frame oracles; nested infrastructure exceptions,
signals, compiler failures and ambiguous HTTP 500 responses retain setup-error
classification. An eligible HTTP 500 needs a separate pure, valid catalog/server
construction to fail with ArgumentError/FormatException. No network callback is
invoked or operation retried. The runner's strict classifier is untouched.
All 146 boundary controls pass. Six selected product counterexamples pass
full-native replay with clean/restored controls and unchanged native artifact
receipts: empty event-buffer removal, form elicitation rejection, default/explicit
completion capability validation, generic API pagination and request-state type
validation. All 2,308 candidates are inventoried per replay; these partial
replays do not qualify the complete target score.

Recorded real-protocol tests also preserve existing content when a resource adds
an entry or annotations, reject structurally unchanged rereads and reject invalid
publication topic/acknowledgement/id fields. All 47 recorded protocol cases pass.
Four former CLI survivors (`a3c82f7a61103289efa6`, `c7007c2ac721df42cd3f`,
`ffdfa55db8119f918cb9`, `8315b0addef074d0785e`) now have strict assertion kills
with clean/restored controls, complete 1,207-candidate inventories and one selected
counterexample per replay. These are partial replays, not whole-target scores.

The b6 main CI VM coverage job reports a test casting an already decoded public
PPT Event argument to TransferableTypedData. The regression now inspects owned
binary wire arguments, retains packed-byte equality before and after public
access, and checks both decoded positional/keyword values. The focused case
passes. No production PPT behavior is changed.

`bin/test-fast` completes successfully before the native production change.
A new segmented CBOR allocation regression fails beforehand with a 131,072-byte
scratch allocation. Standard serde borrowing from a complete current segment
removes that allocation; split values retain the standard IO-reader path. Reader
position, bounds, malformed/all-split and pointer/encoding checks remain in scope.
All 429 Core tests then pass. No custom CBOR validator or frame flattening is added.

The FFI's canonical base64 engine uses pinned base64 0.23.1 SIMD with runtime CPU
dispatch and the same padded standard alphabet/strict decoding configuration;
other architectures retain its scalar standard engine. The official
[SIMD engine documentation](https://docs.rs/base64/0.23.1/base64/engine/simd/struct.Simd.html)
was checked. An exact dev-only 0.21.7 reference independently checks every length
through 1,024, large inputs, vector/tail boundaries, invalid bytes in every lane,
padding/discarded bits and independent mutable FFI ownership. All six base64-filtered
FFI tests pass. Earlier four-round canonical local comparisons show RawSocket JSON
file data median 377.344 to 292.8 ms, WebSocket JSON 830.581 to 751.803 ms;
borrowed-only TLS CBOR contiguous pub/sub data 1,376.458 to 858.45 ms. These Mac
observations select candidates; final-source Linux/hosted qualification is pending.
TLS read-ahead, extra drain barriers and other slower prototypes are rejected.

Local advisory review finds no verified production defect after checking its
suggestions against the actual split-value tests, outer progress guard and strict
base64 differential controls. Five of six historically pinned MQTT source files
remain byte-identical; the FFI import changes the sixth. Fresh actual FFI coverage
retains all 979 covered MQTT statements. The first collection is invalidated by
a concurrent MCP test edit and explicitly discarded. A second frozen-input
Dart FFI collection and the complete instrumented Cargo workspace pass, including
all 429 Core / 310 FFI unit cases. The changed FFI file's 58 original statements
are covered exclusively by fresh measurements; source-record extracts for five
byte-identical files retain the historical Linux evidence. The original proof
and archives stay immutable. The new current-source inventory and regression
require exactly the same six files, the exact original statement mapping and
979/979 coverage, verify byte-for-byte extraction and recompute both measurement
channel counts. No historical hashes, statements or thresholds are waived.

Before readiness: complete current-source native/MCP/browser diagnostic campaigns,
run quiet frozen-input `bin/verify`, and
require every workflow family on the final head to pass. PR #139 remains draft;
no merge or release is authorized.

All 67 checked-in budget/scenario files are byte-identical to freshly fetched
`github/master` (`0a3d96e6`), which is contained in this branch. Local current
coverage-receipt validation passes, with all 29 packaging/tooling tests also
passing before the final additional scope/channel assertions. The final focused
receipt audit passes those stricter assertions. Complete hosted qualification
and quiet `bin/verify` are still pending; publishing this checkpoint is not a
readiness or all-green claim.


### Follow-up checkpoint: remaining current-source diagnostics

Checkpoint `e3bbb70a` passes three ObjectBox hosts, publishing dry runs and the
regular WAMP profile workflow. WAMP diagnostics run 44644466139 still fails;
artifact 14588213397 SHA256
`5067160ba2c9b3e14e465db494cd96554a8de0a2f56ad48c4eef153ad6f2db1a`
retains all eight scenarios. RawSocket JSON file lifecycle and native contiguous
CBOR now pass. Remaining file lifecycle rates are WebSocket CBOR 1,986.57 and
MessagePack 1,774.78 Mbps; WebSocket JSON data/lifecycle are 1,468.78/1,216.70.
TLS native JSON contiguous lifecycle is 1,954.92; fragmented JSON data/lifecycle
are 1,610.98/1,475.43 and fragmented CBOR lifecycle is 1,820.67 Mbps. Every floor
remains 2,000 Mbps. This checkpoint is not qualified for readiness.

The local frozen `bin/verify` at e3 is explicitly interrupted after 3m38s when
newly completed b6 artifacts reveal two further product-oracle classes. No file,
head or clean-worktree status changes during that attempt, but termination with
SIGTERM is not a passing verification. The e3 mutation run is cancelled as
superseded; useful completed b6 diagnostics remain available. Repeat complete
verification after the remaining changes are selected.

Completed valid example calls now recognize the specific input-response object
validation and missing generic API-list tool errors, with the same private smoke
frame and nested-infrastructure exclusions. Pure declarations cover both default
and positive limits, auto/explicit capabilities and valid resource templates.
All 166 classification boundary controls pass. Three additional full-MCP selected
replays (2,308 inventoried each) detect input-response validation, missing API-list
tool and positive event-buffer limit rejection; a fourth detects template-registry
rejection. All clean/restored baselines pass and native binary receipts stay
unchanged. These are partial counterexample replays, not complete campaign scores.

Rejected metadata batches now enforce the existing no-following-request assertion
before forwarding another native exchange. Both forwarding modes have mock
upstream coverage; all ten positive metadata cases remain and pass. The original
slow b6 metadata counterexample times out. At e3 it is assertion-killed locally
in 37.776 seconds; early enforcement reduces that to 25.432 with the same full
native CLI test scope, 1,207-candidate inventory, original 45-second command
limit and clean/restored controls. No test case or native exchange before the
injected rejection is removed.

Strict kTLS run 44644478764 fails because the Azure Linux 7.0.0-1020 kernel
advertises `espintcp mptcp` but no `tls` ULP. Artifact 14588500788 SHA256
`058cd76fd88f6978f93c69f8eab1e8bf6699e800d379bed55202997e6cdbe2f6`
confirms both require/enable flags remain 1. The runner now loads the TLS module
when absent and verifies that it is advertised before executing the same strict
HTTP/2 workload. There is no userspace fallback or skipped kTLS qualification.
The [kernel TLS interface](https://docs.kernel.org/networking/tls.html) requires
setting the TLS ULP on an established TCP socket; runner preparation precedes
that unchanged production handoff. Hosted confirmation is still required.

Remaining work is WAMP WebSocket file/TLS-fragmentation throughput, complete
current-source MCP/native/browser campaigns and final quiet `bin/verify`.
All numeric policy, workload, source/operator inventories and original deadlines
remain unchanged. No merge or release is made.


### Further diagnostic evidence (20 November)

Strict kTLS run [44649902504](https://github.com/konsultaner/connectanum-dart/actions/runs/44649902504)
passes at `0095bf40` after loading the runner's TLS kernel module. Both strict
flags, the workload and its gates remain unchanged.

The completed b6 mutation run has 101 jobs: 62 pass and 39 fail. Both native
complete gates pass on Linux/macOS. MCP/native CLI aggregates reject incomplete
or incompatible shard evidence and do not establish a full campaign score.
MessagePack browser aggregation is complete but reports 181 assertion kills,
15 survivors and nine compiler rejections, with the same five historical
functional proofs: adjusted assertion score 94.7644%, below the unchanged 95%.
Artifact 14589479693 SHA256
`19956d39ebafd775c989b9b31ed0b7d6f64b29de4b2319bd14f1ffe2f22b4acb`
is retained locally with its checksum verified.

A new public serialization regression covers a nested iterator updating a later
entry in its enclosing List. The original encoder visits live List entries;
an unnecessary List snapshot loses that update. Independent expected wire bytes,
decoded values and one traversal are asserted. All 204 MessagePack browser tests
pass. Selected browser replay `61e6321a7eaf430d5d53` inventories all 205 original
mutants, assertion-kills this counterexample and passes clean/restored baselines.
This is a selected replay; the full new browser score remains pending. Local
advisory review was checked against the actual assertion/log: its claim that a
snapshot could pass contradicts the observed `updated`/`before` failure.

Additional exploratory performance candidates are rejected: unmasked vectored
continuation writes do not improve JSON file throughput and regress cleartext
fragmented scenarios; copying JSON String input through Utf8Encoder is slower.
A Sonic parser prototype also shows no macro gain and is not shipped. Its
[checked APIs and UTF-8 policy](https://github.com/cloudwego/sonic-rs) and
[borrowing contract](https://docs.rs/sonic-rs/0.5.11/sonic_rs/struct.LazyValue.html)
were inspected; no alternate JSON parser, compiler CPU flag or new dependency
is added to the production change. Original budgets/workloads stay identical.


### Current native and protocol repair checkpoint

The `0095bf40` WAMP mutation batches on both hosts expose the same remaining
non-assertion failure: replacing `Read::read` with `Ok(1)` makes `read_to_end`
report false progress forever. The regression now asserts the zero-length read
contract immediately before the original drain, retaining every earlier assertion
and the original 30-second native deadline. The full 358-candidate inventory is
retained; the selected counterexample is assertion-killed, with clean/restored
baselines and frozen source receipts. Linux artifact 14593751223 has SHA256
`ba080efbca3b7acfc5af8ab916b3cdfa155c8e947ee7318bbbace820c9ed6dc4`;
macOS artifact 14594276511 has SHA256
`f3f4ec742d75db13eb05a7846374866b80ea804e2124800606b10a6ac347740c`.
This is a selected replay, not a full current-source campaign result.

CBOR cross-segment validation now retains one shared suffix allocation, using
standard serde validation and a 64-byte stack preview for short split metadata.
Payload slices reuse that validation storage; the public raw frame retains its
original segments. A fail-first regression observes 131,072 allocated bytes for
a 65,576-byte wire frame before this repair. The corrected path asserts total
allocation at most wire size plus 16 KiB, exact payload bytes and original raw
segment pointers. Existing aligned borrowing/allocation tests remain unchanged.

TLS preserves Ring's exact ordered cipher-suite IDs, key exchange groups,
signature verifier mappings, RNG and key provider, replacing only each available
record implementation with AWS-LC for the same suite ID. Rustls explicitly
supports [mixing provider components](https://docs.rs/rustls/0.23.45/rustls/crypto/struct.CryptoProvider.html).
No TLS version or negotiated algorithm is added or reordered. The first explicit
process provider remains authoritative. HTTP/3-only initialization is tested in
a fresh process; every supported TLS 1.3 suite has bidirectional Ring interop,
record-boundary, ALPN, application-data and corrupt-tag rejection coverage.
All 432 Core tests, the new HTTP/3 process regression and three serializer
integration tests pass. The six pinned MQTT production sources remain unchanged.

The native canonical base64 String path uses public synchronous
`Dart_StringToUTF8`/`Dart_IsError` callbacks inside the documented
[Handle FFI scope](https://api.dart.dev/dart-ffi/Handle-class.html).
The scoped copy is consumed before return; decoded bytes have independent native
ownership. Only entirely ASCII strings take this path; Unicode contexts and older
native libraries retain their tested scalar fallback. Actual UTF-8 bounds are
checked before slicing. All ten focused Rust FFI cases pass, including malformed
canonical forms, vector boundaries, ownership after input changes/free, missing
APIs, invalid ranges, empty storage and missing nonempty API storage. Three Dart
native tests pass with both the new and old native libraries. All 65 recorded CLI
protocol controls pass, including empty and null catalogs and missing responses.

Matched exploratory four-round comparisons select the native candidates:
cleartext CBOR 4-KiB fragmentation data median 665 to 594 ms; TLS JSON/CBOR
medians improve about 10--12 percent. With the same new native library on both
sides, the public-API String worker reduces WebSocket JSON file data median
874.35 to 700.34 ms, while RawSocket JSON remains 391 to 392 ms. These are local
candidate comparisons, not hosted floor qualification. CPU profiling is kept
outside the product and qualifying runs. Local advisory reviews find no verified
new correctness defect: pre-existing SNI fallback is outside this change; serde
rejects incomplete values before advancing, offsets remain original absolute
positions, TLS 1.2 is disabled by the unchanged feature set, and the Dart mutation
fixture is always nonempty. No new waiver or relaxed classifier is introduced.

Remaining work: complete current-source hosted mutation campaigns and all WAMP
floors, finish quiet frozen-source `bin/verify`, then audit every workflow/check
on one final commit. PR #139 remains draft; no merge or release is authorized.
