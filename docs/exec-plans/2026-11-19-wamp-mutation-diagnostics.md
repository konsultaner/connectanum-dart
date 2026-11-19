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
