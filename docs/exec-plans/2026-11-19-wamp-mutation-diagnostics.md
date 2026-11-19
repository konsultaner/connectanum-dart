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
