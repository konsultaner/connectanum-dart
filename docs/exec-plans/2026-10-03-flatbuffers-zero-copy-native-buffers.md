# FlatBuffers and zero-copy native buffers

Status: active. Started: 2026-10-03.

Current step: validate scoped native body generation and renew the unchanged
performance/copy gates. Runtime `828721fd` is the latest measured checkpoint.
Earlier sections retain checkpoint history, including rejected experiments.

## Explicit payload release investigation (2026-10-30)

- [x] Independently audit 3,225 copy inputs and 120 live / 300 inventory /
  32 zero-avoidable checks; confirm current-head CI completes all 38 jobs.
- [x] Reproduce a live 64 KiB FlatBuffers export after explicit payload release
  with the native weak observer, without GC or measurement policy changes.
- [x] Add fail-first regressions and reclaim the explicit release scope. Ten
  native owner cases, Dart native frame release, 94 sockets, 405 lifetime/file/
  crypto cases, 77 transport/frame regressions and derived-view GC pass.
  Ordinary handle release and independent exports retain their lifetimes.
- [x] Complete fresh baseline: `bin/test-fast` exits 0.
- [ ] Integrate the newly advanced MQTT master commit before final acceptance.
- [ ] Finish full verification and safety review, then evaluate a changed
  runtime with all unchanged gates. Memory attribution `41106228701` is queued;
  shared-resource lease currently blocks local companions. No bypass.

## Audited readiness checkpoint (2026-10-30)

- [x] Retrieve and independently reproduce paired `41056036677`: 90 rows,
  exact hosted result and retained input/binary verification. No integrity issue.
- [x] Confirm p99 now passes for every construction group, as do throughput,
  CPU, p95, allocation, GC and pre-encoded RSS. Keep all prior failed reports.
- [x] Confirm current-head CI `41057774775` and renewed copy `41057771623`
  both complete successfully. Copy artifacts still need independent audit.
- [ ] Resolve remaining RSS gates: Dart-values 1.0087769550
  (CI [0.9965808754, 1.0243417666]); native-buffer 1.0285043000
  (CI [0.9903861263, 1.0685564016]). No threshold relaxation or lucky rerun.
- [ ] Finish full 48-case primary, final-runtime supplemental and renewed local
  verification after the recorded dependency-network timeout. PR #132 stays draft.

## Connectivity blocker and retained runs (2026-10-30)

- [x] Preserve paired `41056036677` failure status and failed artifact/API reads:
  repeated TLS timeouts and connection resets prevent numerical auditing.
- [x] Record fresh tooling-head `bin/verify` exit 124: dependency resolution in
  the MCP consumer fails after three 180-second attempts; earlier checks pass.
  The previous runtime full run finishes all consumer and browser suites.
- [ ] Restore connectivity, audit the existing numerical artifact and renewed
  copy/CI runs, then renew failed local verification. No unchanged numerical
  campaign rerun or measurement-policy change is allowed. User network context
  is requested asynchronously; no runtime change is justified by this outage.

## Private probe directive-order repair (2026-10-30)

- [x] Retain failed copy `41056032556`: server never reaches READY. Its log shows
  a marker constant before the new Dart part, not a measured lifetime failure.
- [x] Reproduce actual/current and future-added part directive ordering with a
  fail-first contract. Move marker insertion to the first declaration anchor,
  after every directive, preserving missing/duplicate pattern refusal.
- [x] Pass all 15 probe contracts and 167 mutation proofs. A real private copied
  library analyzes cleanly; preserve the initial macOS /tmp URI alias failure
  and its canonical-path correction. Production Dart, lockfiles, scenarios,
  policy and measurement windows remain byte-identical to runtime `ef61b156`.
- [ ] Renew copy `41057771623` and full CI `41057774775` on `2d0ee379`.
  Packages/native code, dependencies and locks are byte-identical to `ef61b156`.
  Supersede only its duplicate correctness CI `41056028434` to free runners,
  retaining passed jobs/history. Fresh local verification records a sidecar exit.
  Keep paired `41056036677`
  running untouched. Do not rerun numerical campaigns on this tooling-only change.

## Guarded native body generation investigation (2026-10-29)

- [x] Renew baseline `bin/test-fast`: complete exit 0. Existing `9bf3235c` CI
  `40929882938` passes all 38 jobs; `828721fd` CI `40949419438` also passes all 38 jobs.
- [x] Minimal actual-constructor repro observes 65,536 Dart body staging bytes
  in each native codec. A private scoped-writer model produces 76 exact CBEN
  boundary vectors with zero input/growth copies and rejects escaped writes.
- [x] Retain/reject the initial unleased own-test-overlapped timing before using
  it. After the baseline exits, isolated leased scalar/stream timing is valid
  only as component evidence. Existing FB putUint32 loops are about 10x slower;
  the sequential scoped writer is 14–27% slower. A callback-per-word batch also
  regresses. None is adopted or claimed as parity. Lease-refused attempts run
  no measurements and are retained separately.
- [x] Evaluate an indexed guarded region with zero-initialized vector storage,
  closed-view checks and no raw mutable escape. No benchmark-native pattern
  generator, body caching, SDK tuning or acceptance-policy change is allowed.
- [x] Integrate a guarded word writer as a candidate. Its final private typed-data
  field and closed guard avoid per-word prepare/cursor overhead. Fresh vectors
  use the native ABI's zero initialization; every reset enables explicit span
  clearing, including if reset fails. All word writers close before publication.
  Callback/Future/copy failure blocks publication. The fixed byte-range API
  intentionally preserves untouched existing values and has no reset method.
- [x] Apply the same pure-Dart value generation to all three native codecs.
  Preserve CBEN/PPT bytes and all data, observations and timing windows. CBOR/MP
  use at most three untransmitted leading allocation bytes to align word stores.
  Their frozen spans/wire sizes are unchanged. Explicit input/growth copies stay
  counted; the complete native constructors now have zero body input-copy bytes.
- [x] Pass 215 focused model/live transport cases and the initial 67 ownership
  cases, including the standalone freed-allocation/closed-writer GC probe.
  Complete analysis exits 0 with no new diagnostics. All 167 mutation proofs
  remain valid. Source review rejects unsupported stale-view and span claims;
  document/test fixed-range preservation rather than adding unwanted clearing.
- [x] Complete all 70 ownership checks, including a fail-first isolate-port
  transfer test. Both scoped types implement Finalizable and are unsendable,
  so their active guard cannot be cloned into another isolate. The native
  child verifies closed facades retain no actual native allocation.
- [x] Reproduce a separate actual native owner-probe coalescing bug: a real
  64 KiB fragmented Session RPC invokes its contiguous getter once. Move the
  getter behind the existing owner/encoding checks, retaining every native
  identity/ownership condition. It now reads zero times, with exact echoed bytes
  and handshake/Goodbye codes. All 74 related regressions and 167 proofs pass;
  focused review finds no concrete defect. Supersede the in-progress canonical
  run before completion and retain its log; no numerical run is discarded.
- [x] Complete checkpoint reporting: b7a6 supplemental `40925767834` finishes all
  three shards and merge. Independent reproduction exactly matches comparison
  and provenance: 50 cases / 1,500 rows / zero integrity findings / 195 numerical
  diagnostics. Preserve d1b's 193 diagnostics and all earlier cost reports.
- [x] Freeze/push `ef61b156`; canonical verification completes through all
  VM/native, consumer and both browser suites with every test passing. The exec
  session expires after completion; retain the full successful test log without
  inventing a direct observed process exit status.
- [ ] Complete frozen-source hosted CI `41056028434`, copy `41056032556` and
  paired diagnostic `41056036677`. GuardMalloc and binding jobs already pass.
  No new numerical result or parity acceptance yet; apply shared APIs to CBOR/MessagePack as well. Keep
  ordinary Dart-values and pre-encoded groups semantically distinct.

## Redundant typed-PPT projection follow-up (2026-10-29)

- [x] Attribute remaining decoder work to its existing profile. Fully reconstructed
  two-string PPT details are projected again after frame dictionary agreement;
  the result is discarded. Skip only that duplicate call. All frame/schema,
  metadata-agreement and other control/history checks remain in place.
- [x] Private source clone matches 96 valid vectors and 488 mutated-input outcomes,
  including re-encoded bytes and later model edits. Preserve the initial private
  script's type-inference compilation failure and correction.
- [x] Add actual model -> projection round-trips for Result/Event/Invocation at
  normal/max IDs and partial/null/custom metadata history. All 3,593 VM
  serializer/Session and 136 browser model/history cases pass; all 167 mutation
  proofs remain valid. GLM judge/review find no concrete defect after the round-
  trip regressions, and focused local test advice is checked against real behavior.
- [x] Retain the refused timing admission. A later own-test-overlapped capture is
  rejected in full, before using its timings. After both test processes exit,
  isolated resource-leased ABBA timing records baseline 354,969/352,194 us and
  candidate 296,254/296,057 us per 200,000 decodes, equal result checks. Local
  Dart 3.13.1/macOS only; no forced GC or workload/parity claim.
- [x] Complete canonical verification on `828721fd`: full `bin/verify` exits 0,
  including native/FFI, VM, consumers and full Chrome/WebAssembly suites.
- [x] Audit hosted copy proof `40941222405`: 3,224 inputs, 120 live / 300
  inventory / 32 zero-avoidable-copy checks, all E2EE/transcode/native-crypto
  counts, unchanged source/library, stable PIDs and cleanup. Three native-view
  positive phases pass and the intentional negative control is observed.
- [x] Independently reproduce all 90 rows from paired `40941226221`, including
  exact comparison, pinned inputs/scenarios and retained production binaries.
- [ ] Fix three remaining numerical misses: Dart-values RSS 1.016113
  (CI [1.001543, 1.022033]); native-buffer p99 1.034644
  (CI [0.800252, 1.330524]); pre-encoded RSS 1.001925
  (CI [0.992392, 1.017865]). All throughput/CPU/p95/allocation/GC gates and
  Dart-values p99 pass. Preserve every previous campaign; no unchanged
  numerical rerun, threshold change, forced GC or measurement-window change.
- [ ] Complete final-source hosted CI, all 48 primary cases and the final-source
  50-case supplemental report only after the diagnostic parity prerequisite.


## Pre-encoded staging follow-up (2026-10-29)

- [x] Reproduce the remaining pre-encoded application-vector copy with an actual
  runner/owner test: expected zero Dart staging bytes, observed 65,536.
- [x] Use complete encoded Dart parts as input to the existing public native
  builder, then freeze one native owner. The full encoded model, including
  prefix/padding, is copied once and counted. Schema encoding remains in Dart;
  this stays distinct from native schema construction. Body data/IDs, CBEN
  bytes, lease identity, observations and preparation/latency windows stay fixed.
- [x] Pass 59 focused model/source cases, including both-constructor all-codec
  rejected-call cleanup, empty/nonaligned vectors,
  exact ordinary-builder byte equivalence and native input/growth copy counts.
  All 14 private native-view patch contracts and 167 mutation proofs pass.
- [x] Complete canonical verification and source/behavior review. Runtime
  `9bf3235c` complete `bin/verify` exits 0. Focused GLM/Qwen reviews complete;
  their observer, disposal, race and schema claims are disproved by actual
  contracts and tests. Keep the advisory evidence in the research record.
- [x] Renew production copy proof `40929886924`: independent audit verifies
  3,224 inputs, 120 live / 300 inventory / 32 zero-avoidable-copy checks, all
  E2EE/transcode/native-crypto counts, raw hashes, stable PIDs and cleanup.
  Three positive native-view phases pass and their negative control is observed.
  Source/binary unchanged receipts hold; package_config remains digest-only.
- [ ] Pass hosted CI `40929882938` and paired diagnostic `40929890341` on the
  changed constructor. Preserve the five-failure report and earlier supplemental
  runs. Do not waive numerical gates or start primary before diagnostic parity.
- [x] Audit VM-only capture `40926807868` on the preceding runtime to attribute
  the remaining Dart-values client GC/tail cost. Its Dart-values construction
  is unchanged by this pre-encoded follow-up; profiling never accepts parity.
  All three windows verify, inputs/library remain unchanged and cleanup is clean.
  Post-GC-request source/sample counts are zero. The sampled GC intervals do not
  explain the complete acceptance-run pause/tail cost; preserve that uncertainty.

## Fragmented application-model candidate (2026-10-29)

- [x] Reproduce the remaining application-builder staging copy. A private
  Dart-only prototype preserves all encoded bytes for 72 CBEN vectors, including
  zero/max uint32 IDs, empty/tiny/nonaligned sizes and read-only unaligned input.
  Its 64 KiB body retains input identity: ordinary builder vector-copy counter
  is 65,536 bytes; fragmented construction is zero body-vector bytes plus an
  explicitly counted 40-byte owned prefix snapshot. This is correctness/copy
  evidence only, not performance acceptance or a published API.
- [x] Preserve the initial failed prototype: it omitted the file-identifier
  alignment effect for non-multiple-of-eight lengths. Virtual tail alignment
  fixes it; do not adopt the failed layout or omit boundary vectors.
- [x] Complete fresh `bin/test-fast` before production edits. Design a generic
  fragmented packed-source interface/convenience source in a new module; keep
  the existing protected source identity and native ownership whitelist.
- [x] Add an application-schema helper for one borrowed byte vector. Own the
  small schema prefix, retain the original Dart body, validate root/footer/size,
  and document borrowed-storage lifetime. A Dart reference cannot extend an
  external database transaction's lifetime.
- [x] Preserve parts only through the existing fragment-aware send path. Keep
  ordinary serialization/fallback coalescing cached and explicitly counted;
  preserve E2EE/transcode behavior. Reuse the existing WAMP tail-vector layout
  so concatenated wire bytes stay unchanged. No Rust/ABI/schema change is needed.
- [x] Use that public generic helper in the Dart-values model constructor while
  preserving its Dart-allocated body, unique identities, CBEN schema, preparation
  timer, validation, every observation and all measurement windows. Native-buffer
  and pre-encoded constructors keep their separate declared semantics.
- [ ] Prove model/frame byte equivalence, body identity, fallback copy counts,
  caller-list snapshots, ownership/non-forgeability and VM/browser behavior;
  rerun native correctness/copy evidence and canonical local/hosted verification. Full local `bin/verify` exits 0;
  production proof `40922342731` passes and its independent audit verifies all
  3,224 source inputs plus 120 live / 300 inventory / 32 zero-avoidable-copy
  checks. All three native-view positive phases and their cleanup pass; the
  intentional negative control is observed. Corrected-source CI `40923229188`
  is pending, so this combined checklist item stays open.
- [ ] Only adopt measured improvement under the existing paired policy, then
  finish the 48-case primary. The final-runtime 50-case supplemental refresh
  runs in parallel after local verification/copy proof to complete pending cost
  reporting; retain every previous report and never substitute diagnostics for
  primary acceptance.

Current paired result `40922533817`: all 90 rows complete, independently matched
against retained inputs and binaries. Five numerical misses remain: Dart-values
throughput 0.995779, p99 1.114498, GC 1.212659 and RSS 1.020991; native pre-encoded
RSS 1.006725. Native-buffer passes every metric. Keep both earlier seven-failure
and current five-failure reports; no unchanged acceptance rerun or threshold
change. The client's GC accounts for the excess despite lower allocation;
router GC is similar. Inspect existing VM-only heap/GC attribution on this
changed runtime before proposing another optimization. Supplemental refresh
`40925767834` runs independently; it never accepts the 48-case primary.

Local heavyweight architecture advice was attempted through the approved
companion helper and refused because the native-mutation resource lease is
active. Do not bypass that gate. The current work is a bounded pure-Dart
correctness prototype and ordinary canonical tests, not local native profiling.

Implementation checkpoint: 149 focused core/client/benchmark cases pass,
including Session preservation and all three construction-source contracts.
Additional nested-table/float64 alignment and invalid-identifier guards pass.
All 167 mutation proofs and all 14 private native-view patch contracts pass.
The first integration invocation found a test API-name typo and missing explicit
native-library selection; both tests are corrected and pass. Companion test and
review helpers remain lease-blocked. Full `bin/verify` is running. A direct
dart2js browser invocation times out loading suites locally; the canonical
macOS WebAssembly package-root route passes 49 core and 48 Session/E2EE cases,
plus the unchanged browser control. Keep every failure log.
The executable combined serializer wrapper catches metrics initialization order:
keep the disabled-state contract first, then enable metrics for later groups.
The corrected wrapper passes all 3,688 cases. This is a test-only follow-up to
frozen runtime `490f60bf`, whose CI `40922324217`, production proof `40922342731`
and paired diagnostic `40922533817` are running. No measured production input changes.

## WAMP serializer compatibility

The current [WAMP Internet-Draft](https://wamp-proto.org/wamp_latest_ietf.html)
requires an implementation to support at least one serializer; its Basic
Profile defines JSON, MessagePack and CBOR bindings, while the Advanced Profile
may define more. The draft also lists FlatBuffers as a RawSocket serializer and
as an E2EE `ppt_serializer`. This supports integrating FlatBuffers alongside
the existing session serializers without adding an ObjectBox-specific wire
format. The draft is experimental and can change.

The WAMP repository's [issue #355](https://github.com/wamp-proto/wamp-proto/issues/355)
discusses FlatBuffers as an additional serializer and points to Autobahn's
WAMP-message schemas, but remains open with “Needs consensus” and describes
that implementation as alpha. Treat that issue as historical precedent, not a
normative recommendation. The current draft is the stronger compatibility
reference.

## Strict parity checkpoint and completed supplemental audit (2026-10-29)

- [x] Pass complete local verification on `cd54760c`, including all 2,832
  benchmark cases and Chrome/WebAssembly. Production proof `40784345437` passes
  120 live / 300 inventory / 32 no-avoidable-copy with unchanged inputs/binaries.
- [x] Preserve diagnostic `40784342071`: 90 rows, four numeric misses (three RSS
  points and Dart-values p99 confidence). All throughput/CPU/allocation/GC/p95
  gates pass. Do not discard the preceding two-RSS-miss report or waive gates.
- [x] Audit fresh read-only Dart-values memory capture `40783409254`, six pairs,
  unchanged inputs. Identical FB fresh-process peak medians span 388–421 MiB;
  logical heap Used buckets include garbage. No retained leak is established.
- [x] Keep the private generated CALL prototype unadopted: its ~0.3 us/frame
  saving and variable component RSS are insufficient to identify the blocker.
- [x] Confirm exact-runtime CI `40788573756` and preceding `40780584962`
  entirely green.
- [x] Complete supplemental `40789946129` on `cd54760c`: all three batches plus
  merge job succeed. Independently revalidate raw rows and pinned inputs/binaries;
  recomputed result exactly equals hosted output: 50 cases / 1,500 rows, no
  integrity findings, 194 numerical diagnostic findings. Never primary acceptance.
- [x] Retain obsolete-source `40782047961` partial artifacts; no report was
  cancelled because of a result.
- [x] Continue under unchanged strict RSS/latency budgets as requested by the
  user. No relaxation has been authorized.
- [ ] Fix the remaining three-case diagnostic performance failures and complete
  the final-runtime 48-case primary. Refresh the complete supplemental report if
  the runtime changes; retain all older reports.

## Retire forwarded reply envelopes (2026-10-29)

- [x] Preserve `f204100d` full bin/verify exit 0 and production proof
  `40880838998` (120/300/32 with unchanged inputs/binaries). Independently
  reproduce diagnostic `40880833788`: eight numerical misses, not acceptance.
- [x] Reject/revert early report-byte staging; restore bench_main exactly to
  `69193827`. Preserve every failed report and all strict budgets.
- [x] Reproduce the internal reply envelope's retained application graph. After
  successful SendPort snapshotting, retire only the private received payload
  fields, preserving forwarded contents, control flags and nested application
  objects. Actual 2,000-sample HTTP liveness is zero without extra JSON staging.
- [x] Pass nine SDK contract tests (same/cross-isolate, progressive/final/error,
  PPT/details, immutability, transferable moves, failed-send atomicity, closed
  ports, invalid/missing progress), 785 native/router regressions, all nine HTTP
  pairs, clean analysis and 167 mutation proofs. Resolve companion concerns
  against actual SDK behavior and unchanged strict validation; no code waiver.
- [x] Freeze runtime, renew full verify/copy/CI and retain the paired evidence.
  Runtime `dec17f8b`: full local verify and copy proof `40891602695` pass.
  Independent raw-row validation reproduces 120 live / 300 inventory / 32
  zero-avoidable-copy checks. Paired `40891596427` is independently reproduced:
  90 rows, seven numerical misses (three RSS and Dart throughput/CPU/p95/p99).
  CI `40891584949` passes completely. CPU profile `40896349976` attempt 1 fails before
  FlatBuffers readiness; preserve its partial MessagePack capture and unchanged
  source/library receipts. Fix the masking cleanup error before renewing it.
  The actual generated probe passes seven error/value/order cases and all 19
  profile-tool tests; restoring old semantics fails the private negative control.
  Follow-up `40899272991` preserves perf's actual pre-readiness exit 255.
  Publish the existing VM-only path as `flatbuffers_vm_profile`, with native
  stacks explicitly unmeasured. Pass both real shell argument branches, all
  21 CI execution tests, 19 profile-tool tests and 167 mutation proofs.
  Local private probe admission is blocked by the shared resource lease.
  Preserve every report and the refusal; never bypass the lease or waive gates.
- [x] Complete source-attributed VM-only profile `40901845935` on `d1b395e7`:
  unchanged sources/library, all three calibrated CPU windows, retained class
  heaps and existing traces, clean process exit. Native stacks are unmeasured.
- [ ] Resolve the seven numerical misses; only then run the 48-case primary.
- [ ] Finish fresh 50-case supplemental report `40906173218` on `d1b395e7`.
  Run the diagnostic report alongside attribution to complete pending cost
  reporting; it cannot accept primary parity. Keep the older report and every
  new numerical difference, and never pool absolute timing across shards.

## Encode completed reports before internal routing (2026-10-29)

Status: rejected after the full `f204100d` paired diagnostic; restored the
previous report-routing implementation. Liveness alone was insufficient.


- [x] Trace the supervisor's retained samples through the internal response
  lazyPayload/argumentsKeywords/body graph after a real 2,000-sample request.
- [x] Prototype, then encode the same complete report into standard UTF-8 JSON
  before routing. Preserve field order/schema, every observation, exact content
  type/charset and post-window timing. Use the existing defensive bytes API.
- [x] Confirm zero retained supervisor WampSamples after diagnostic collection
  for both the private prototype and actual follow-up; original retains 2,000.
- [x] Pass all nine live HTTP codec/construction pairs, content-type/charset,
  clean analysis and all 167 mutation proofs. Complete the focused companion
  review; reject its JSON-string staging speculation against actual encoder.
- [ ] Renew full verification and frozen-source hosted gates, including the
  repaired private native-view adapter. Never treat liveness as RSS acceptance.

## Release completed request sample contexts (2026-10-29)

- [x] Identify completed WampSample retention in the idle worker profile; confirm
  the loop pattern in a controlled actual-model probe: inline retains 20,000
  objects / 2,240,000 bytes, awaited handler retains zero after diagnostic-only
  collection. Preserve identical 1,428,904-byte output/hash. No production GC.
- [x] Move the unchanged request try/catch into an awaited function. Preserve
  all snapshots/windows, sample values, complete JSON conversion, LF/flush,
  error recovery, blank/STOP handling and outer native shutdown.
- [x] Pass the extended real-worker malformed/unsupported/compact/named/STOP
  regression, all 143 sample/boundary/lifecycle cases, clean analysis and all
  167 mutation proofs. Qwen test advice completes; reject its suggested RSS/GC
  acceptance assertion. Its review is incomplete at token limit; GLM times out. Request a smaller
  focused review and keep incomplete outputs labelled.
- [x] Verify handler statement tokens match the original exactly after ignoring
  formatting-only trailing commas. No metric-window operation is reordered.
- [x] Freeze runtime `69193827`. Actual standard-SDK worker capture has unchanged
  source/library hashes and clean exit; all three client codecs retain zero
  WampSamples after diagnostic-only collection. No production/acceptance GC.
- [x] Complete the smaller Qwen review. Its window-order concern is unchanged
  original behavior, rejected against the exact 537-token handler comparison.
- [x] Reproduce stale private patcher anchors in full verification and hosted
  copy prerequisite `40877485342`; repair its shadow-only helper/library wiring.
  Pass all 14 tests, preserving exact-one-match refusal and post-window capture.
- [ ] Renew full verification, CI and copy proof after the diagnostic tooling
  repair. Paired diagnostic `40877480175` continues on unchanged runtime.
  Keep existing gate policy.
- [ ] After a passing paired diagnostic, complete all 48 primary and refresh
  all 50 supplemental cases on the final runtime.

## Generated opaque CALL encoder candidate (2026-10-29)

- [x] Reproduce generic CALL table scratch-list/scanning costs with actual
  production preparation and unchanged native-reference prefix construction.
- [x] Add a guarded pinned generated CALL/Message writer for simple opaque PPT,
  preserving metadata bytes, schema field order, deferred payload aliasing,
  borrowed-builder identity, copy counters and complete generic fallback.
- [x] Pass 210 focused serializer cases, including exact generic-wire equivalence
  for inline/reference/deferred storage, all five scheme values, absent defaults,
  zero/max IDs, empty/64-KiB bodies, UTF-8 and lone surrogates. Invalid numeric
  doubles, unknown fields and foreign references remain rejected.
- [x] Production AOT component, generic/generated/generated/generic: 500,000
  full preparations and prefix encodes take 904/647/661/879 ms. Exact 192-byte
  prefixes match. Component RSS is inconclusive; never primary acceptance.
- [x] Keep analysis clean and all 167 source-bound mutation proofs valid.
  Local test/review/debug companion requests remain lease-blocked.
- [x] Pass 67 combined native lifetime/profile and writer checks with the canonical
  ffi-test library. The initial direct command omitted the library environment;
  its loader failure is retained, and the corrected command passes.
- [x] Pass canonical `bin/test-fast`, including all 2,832 benchmark cases.
- [x] Reproduce and fix the test-only JavaScript integral-double assumption;
  runtime code is unchanged. Pass all 49 writer tests on Chrome and clean analysis.
- [x] Complete production copy proof `40872810450`: unchanged source/binaries,
  120/300/32 with all E2EE/transcode inventories. Preserve paired `40872805498`:
  four numerical misses (Dart RSS/p99-confidence/GC-confidence; pre-encoded RSS).
  Native-buffer passes all seven. Keep all original budgets and failed reports.
- [ ] Renew full `bin/verify` after the storage failure: a benchmark test compile
  fails with ENOSPC; do not claim a full passing checkpoint. Losslessly compress
  owned historical raw reports with verified hashes, retaining all data/receipts.
  Corrected-test CI `40873583513` is queued. Native perf capture attempt 1 retains
  FB/MP but fails before CBOR; retain it and retry instrumentation once.
- [ ] Establish end-to-end improvement, then renew full primary/supplemental
  acceptance on the final runtime.

## Direct worker JSON UTF-8 encoding (2026-10-29)

- [x] Preserve `3a825a76` full `bin/verify` exit-0 checkpoint and its
  120/300/32 production copy proof. Its two RSS failures remain blockers.
- [x] Identify worker stdout JSON-string staging. Use the standard SDK UTF-8
  encoder with the same named/positional projection; preserve every field,
  byte, LF framing, flush and error response. No workload/window/SDK changes.
- [x] Pass 121 focused boundary/lifecycle cases, clean analysis and all nine
  live HTTP codec/construction pairs. Cover exact Unicode/surrogate, wide-int,
  null/zero, empty, nonfinite/unsupported/cyclic and recovery behavior.
- [x] Compare actual-source AOT components: identical 1,180,013 bytes/hash;
  20,000-record peak RSS 28.15–28.16 -> 25.56 MB and encoding
  12.47–13.63 -> 7.74–8.16 ms. Do not claim end-to-end acceptance.
- [x] Pass full verification, production copy proof and exact-runtime CI. Complete
  and independently audit all 50 supplemental cases. The paired diagnostic still
  has four numerical failures, and the final primary remains outstanding.
- [ ] Establish final primary performance acceptance. Companion tests/review are
  still blocked by the native-mutation resource lease on retry; the prior GLM
  semantic review exhausted its token limit and is not a completed review.

## Final sample JSON projection (2026-10-28)

- [x] Verify `5f54fe7d` with full local `bin/verify`. Production copy proof
  `40774536906` passes 120 live / 300 inventory / 32 no-avoidable-copy checks
  with unchanged inputs/binaries and the approved standard-SDK scope.
- [x] Preserve diagnostic `40774531252`: 90 rows, six numerical findings;
  native-buffer passes every metric, pre-encoded spans miss only RSS, and
  Dart values miss GC/p95/p99/RSS/throughput. Do not relax any gate.
- [x] Replace temporary named maps and private positional lists with read-only
  sample projections at the final standard JSON encoder. Keep public snapshots,
  all observations, worker negotiation, workloads and measured windows intact.
- [x] Pass 119 focused schema/boundary/lifecycle cases, clean analysis, the
  nine-pair live HTTP smoke and 167 source-bound mutation-proof checks.
- [x] Compare actual-source AOT components: identical named/positional JSON
  bytes; HTTP peak RSS 56.4–56.5 -> 43.8–43.9 MB and positional worker RSS
  28.4–28.8 -> 25.7 MB for 20,000 samples. Do not call this WAMP acceptance.
- [x] Pass the complete 2,830-case benchmark suite and production copy proof
  `40780581127` on `3a825a76`: 120 live / 300 inventory / 32 no-avoidable-copy
  checks, unchanged inputs and binaries.
- [x] Preserve paired diagnostic `40780577426`: 90 rows, only two RSS failures
  (Dart values 1.012515; pre-encoded 1.007746); all other metrics pass and
  native-buffer passes all seven. Diagnostic ineligibility is the only other
  finding. Keep every previous failed report and original gate.
- [x] Retry local companions after their resource lease clears. Qwen debug
  confirms numeric-comparison failure. Its review's null-presence premise is
  incorrect against the unchanged public snapshot and 256-combination test;
  derived containsKey/length findings do not apply. GLM review is running with
  that original contract supplied.
- [x] Complete full local `bin/verify` on `3a825a76`, including consumer/browser.
- [ ] Complete hosted CI on that source; no failure has been reported.
- [ ] Inspect fresh frozen-source Dart-values memory/allocator attribution
  `40783409254`; it and supplemental campaign `40782047961` are queued. Reduce
  actual memory use without changing GC/allocator settings or measured windows.
- [ ] Pass all 48 primary and 50 supplemental cases on final source before
  closing #103/milestone or marking PR #132 ready.

## Interrupt native router idle polling (2026-10-28)

- [x] Pass full local `bin/verify` on `c705b5bd`. Confirm current hosted Fast
  Checks/binding/shared-build pass; fix any remaining CI failure before features.
- [x] Audit `40716746367`: all throughput gates and all native-buffer numerical
  gates pass; eight findings remain across Dart values/pre-encoded spans. Both
  exact-runtime copy proofs `40716750991`/`40718047424` pass 120/300/32 inventories.
- [x] Audit CPU capture `40720372509` and the byte-verified live poll control.
  Preserve raw observations. Keep cases, polling defaults and budgets unchanged.
- [ ] Add coalesced optional native readiness notification after successful
  RawSocket/WebSocket queue publication, re-armed before router polling. Use
  one synchronized nullable callback and preserve timer fallback.
- [ ] Add a lifecycle-safe Dart broadcast bridge using NativeCallable.listener.
  Detect the optional ABI as a pair, unregister before closing the callable,
  ignore stale notifications and support cancel/relisten/shutdown/restart.
- [ ] Connect router pacing, cancel abandoned idle timers, and verify queued/
  in-flight wakes without transferring payloads or owners. Reproduce the old
  scheduling floor with a deliberately long poll interval before the change.
- [ ] Test native registration/coalescing/re-arm/unregister races, actual queue
  publication, old ABI, process exit and a bounded live RPC with a long fallback.
- [ ] Pass full verification/CI/copy proof and unchanged paired diagnostic;
  then pass full primary and supplemental acceptance before closing #103.

## Serializer test inventory repair (2026-10-28)

- [x] Reproduce the five missing-inventory assertions during full verification
  on `cb0c44aa`. Register the new matcher test in all four CBOR/MessagePack
  support lists and the shared serializer suite; do not omit it from testing.
- [x] Pass all 87 verification-tool and all 3,651 shared serializer-suite tests.
  Add regressions for false/zero control fields introduced after a simple PPT
  read. Product runtime and source-bound mutation proofs remain unchanged.
- [x] Obtain the now-reachable Qwen debugger's inventory diagnosis and verify it
  against the failing assertions. Broad GLM review/Qwen test planning requests
  time out; they do not count as completed review. A completed bounded Qwen
  review reports no concrete findings. The exact dictionary guard excludes
  additional keys, and encoding fallbacks preserve payload-view semantics.
- [x] Correct the new zero-value fixture: zero publisher IDs remain invalid;
  legal zero trustlevel exercises the intended round-trip. Pass all 1,982
  client/core cases and rerun all 3,651 serializer-suite cases successfully.
- [ ] Pass full local verification and replacement hosted CI.

## Source-bound mutation proof renewal (2026-10-28)

- [x] Reproduce the `66282e65` local/hosted Fast Checks preflight failure. The
  client file change shifts three unchanged mutation sites and invalidates the
  old source hashes. Preserve the failure; do not waive the gate.
- [x] Map each old mutation to an identical original/replacement/operator in
  unchanged source blocks. Recheck cache validation, root string-key policy
  call sites and null-to-integer conversion semantics; existing reasons hold.
- [x] Execute all seven mutations at the three sites in a private source
  snapshot with no equivalents. Exactly the three proven-equivalent mutations
  survive; four controls are assertion-killed. Clean/restored tests and all
  mutation input hashes pass. The expected raw 57.14%/95% failure is not a
  production acceptance report. Renew only those three IDs/hashes/reasons.
- [x] Pass the normal preflight: 157 proofs across 14 targets/11 sources.
  Extend the client guard regression to every native string slot and flag.
- [ ] Pass full local verification and replacement hosted CI. Runtime files
  remain identical to `66282e65`; retain its separate copy/performance runs.

## Complete simple-PPT metadata models (2026-10-28)

- [x] Audit diagnostic `40710916340` on `8fdc0ad0`: 90 rows, eight numerical
  failures, diagnostic ineligibility only. Native-buffer passes every numerical
  comparison; Dart values and pre-encoded spans remain blockers. Preserve all
  preceding failed observations and the unchanged budgets/case inventory.
- [x] Audit production copy proof `40710922147`: 120 live cases, 300 inventory
  rows, 32 zero-avoidable-copy checks, source/binaries unchanged. E2EE/transcode
  accounting remains complete within the approved standard-SDK scope.
- [x] Pass `bin/test-fast` on `8fdc0ad0`. Supersede its full verify during tooling
  checks for the metadata follow-up; claim no frozen-source full pass for it.
- [x] Identify eager FlatBuffers metadata history on complete two-field PPT
  RESULT/EVENT/INVOCATION models. Share the router's bounded ASCII matcher with
  native clients; guard all additional native flags/fields. The Dart reader
  recognizes the already-validated two-string logical dictionary. Preserve
  projection checks, payload anchors, extra fields/defaults/nulls and fallbacks.
- [x] Pass 1,948 client/1,896 router binding cases, 54 core metadata/retention
  cases and 37 browser cases. Cover source mutation, model edits, Unicode,
  field order/header boundaries, malformed/truncated/duplicate/tagged bytes,
  custom dictionaries and explicit null/false values. Local companion review
  remains blocked by the native-mutation resource lease.
- [x] Run precompiled before/after component probes in B/A/A/B order: median
  run-time ratios 0.068 for native RESULT binding and 0.742 for the Dart reader.
  These local component timings cannot replace the strict paired campaign.
- [ ] Finish full local verification and exact-source CI, owned-copy proof and
  paired diagnostic. Fix every remaining performance failure, including RSS.
- [ ] Pass the full unchanged primary and supplemental campaigns before
  closing #103/the milestone or changing PR #132 out of draft.

## Shared deterministic body generation (2026-10-28)

- [x] Pass full local `bin/verify` on `1c80fbf4` and confirm runtime hosted CI
  `40693398693` passes on `28642b03`.
- [x] Resolve Linux client CPU-clock samples from successful capture
  `40705845411`, attempt 2. Preserve attempt 1's transient perf startup failure.
  Shared body generation occupies 314/1135 FlatBuffers client samples, with
  ambiguous reused JIT ranges and non-JIT samples kept separate.
- [x] Before changing the loop, pass independent arithmetic-reference tests over
  all 256 seeds, word tails, large bodies, high identities and buffer independence.
- [x] Fill four successive deterministic bytes per little-endian word across
  every codec; preserve the byte loop on other hosts and for the final tail.
  All 36 payload-codec tests and targeted analysis pass. No workload bytes,
  copy counters, benchmark cases, measurement floors or acceptance budgets change.
- [x] Run the repeated local 64-KiB public-API component probe: median candidate/
  reference time ratio 0.617 versus 0.999 before. These timings are diagnostic.
  Local companion use remains blocked by the native-mutation resource lease.
- [ ] Pass full verification, exact-source hosted CI/copy proof and paired
  diagnostic. Resolve every remaining performance failure, including RSS.
- [ ] Pass the full unchanged primary campaign and supplemental accounting
  before closing #103 or the milestone and making PR #132 ready.

## Client JIT attribution and allocator evidence (2026-10-28)

- [x] Retain failed Linux capture `40703182372`: the worker-as-executable proxy
  correctly trips the existing source-worker VM-metrics guard. Preserve that
  guard. Use a profiling-only Dart-executable override instead, keeping the
  normal `connectanum_bench:wamp_client_worker` entry point and VM arguments.
  Regression assertions reproduce the wrong entry point before the correction.
- [x] Pass the revised 18 profile tests and targeted analysis. A short local
  live RPC smoke with a passthrough Dart proxy completes six rows and records
  the original VM/source-worker arguments. Its short-run policy rejection is
  expected; neither it nor the Linux-symbol-unavailable macOS attempt is parity.
- [x] Pass the complete `bin/test-tooling` suite after the client-map changes.
- [x] Audit allocator run `40696555847` on verified product source `28642b03`.
  Six fresh process pairs complete without forced GC or allocator tuning.
  Live glibc arena estimates are similar across codecs; cached VM pages and
  free allocator bins differ. These non-atomic snapshots cannot identify all
  resident memory or establish parity. Do not subtract free bins from RSS.
- [x] Capture current Dart-values CPU profile `40698440958`. Its VM samples
  include native/blocking stacks; hot client perf addresses remain unresolved
  because the existing diagnostic retains only router JIT maps.
- [x] Extend only the diagnostic launcher to request client JIT symbols on
  Linux, preserving the existing VM/worker arguments without shell parsing.
  Keep per-codec client maps, PID/source/hash attribution and launcher integrity.
  Reject missing, malformed, foreign or changing client PID maps.
- [x] Pass all 18 profiling-tool tests. Local macOS cannot validate the Linux-only
  symbol flag; its real-worker startup attempt rejects that platform-specific
  flag. Linux capture remains required. Local model testing/review is blocked
  by an active native-mutation resource lease; do not bypass that lease.
- [x] Capture Linux router/client JIT maps in `40705845411`, attempt 2, on
  `1c80fbf4`, with source/launcher/binary hashes unchanged. Resolve hot shared
  body-generation samples; preserve reused-address ambiguity. The diagnostic
  changes no runtime behavior or acceptance gate.

## Typed PPT envelope alignment (2026-10-28)

- [x] Pass full local `bin/verify` on corrected source `28642b03`, including
  native/VM, live router and Chrome/Dart2Wasm suites. Its production copy proof
  `40693403608` passes 120 live cases/300 inventory rows and 32 no-copy checks
  with unchanged source/binary receipts. Earlier `9204be2c` CI `40679539974`
  passes; current CI `40693398693` also passes.
- [x] Audit source `28642b03` diagnostic `40693409305`: 90 rows, eight numerical
  failures, no integrity findings beyond explicit diagnostic ineligibility.
  Both native modes pass throughput, latency, CPU, allocation and GC; all three
  fail RSS. Dart values retain additional CPU/GC/throughput/latency failures.
  Preserve the preceding six-failure diagnostic `40691719068` as well.
- [x] Confirm ordinary Dart body offset 196 after promotion, versus the old
  unaligned 202. Restore the privately instrumented runner byte-for-byte; the
  short macOS probe is never performance acceptance.
- [ ] Inspect allocator attribution `40696555847` and current Dart-values CPU
  profile `40698440958`, then choose the next measured production improvement.
- [x] Reproduce mixed MessagePack custom-metadata routing failures during full
  verification of `647517fa`. Its fallback emits bare binary arguments; reuse
  the existing JSON singleton list view for MessagePack without mutating the
  source message or owner. All 122 live PPT/router cases pass after the fix.
- [x] Preserve the internal retention check for direct, full-allocation payloads
  as well as wrapped subviews. Read-only contents survive message/session close.
- [x] Cancel superseded CI `40691714408` and copy proof `40691723293`. Keep
  diagnostic `40691719068` and profile `40691881742` as observations only, never
  follow-up-source acceptance. Rerun full local verification with the routing fix.
- [x] Measure the existing public generated-list construction option before
  adding an API: at 64 KiB it is roughly four times slower than typed staging
  under equal builder capacity. Do not add a generator API based on this probe.
- [x] Pass frozen-source full `bin/verify` on `9204be2c` and production owned-copy
  proof `40679548417`. Prior-source CI `40674226241` passes; current CI
  `40679539974` remains pending without reported failures.
- [x] Audit 90-row diagnostic `40679544893`: all seven numerical metrics pass
  for pre-encoded native spans; eight fail across Dart values/native buffers.
  No integrity findings; diagnostic ineligibility remains explicit.
- [x] Inspect fresh-process memory attribution `40679553230` and the preceding
  post-GC heap profiles. Distinguish used heap from cached VM pages; do not
  remove allocation owners or redesign schema retention without stronger proof.
- [x] Reproduce live FlatBuffers body offsets: 202 for ordinary Dart values,
  40 for native-buffer and pre-encoded spans. This short private macOS layout
  probe is diagnostic only and never acceptance evidence.
- [x] Reproduce the missing opaque vector for ordinary typed PPT wrappers.
  Promote one `Uint8List` with effective custom FlatBuffers PPT metadata into
  the existing opaque field. Preserve encoded args/kwargs, other serializers,
  encrypted `wamp` and cipher/key paths. Read current wrappers rather than
  caching byte identity across mutation.
- [x] Pass 143 writer/fragment tests, 299 Session/PPT/key-selection tests and
  targeted analysis. Test seven message types, empty/read-only/subview buffers,
  mutable wrapper edits and effective-metadata guards.
- [x] Preserve read-only opaque views without copying. Keep a legacy wrapped
  fixture alongside the direct layout and explicitly decode both. Pass the
  final 155 combined fragment/retention/Session tests and targeted analysis.
  Local review's proposed kwargs regression does not reproduce: the helper's
  optional kwargs default is null, while explicit/lazy kwargs have separate
  passing guard tests. Other argument shapes continue to use CBOR.
- [ ] Finish full verification, then rerun exact-source CI,
  owned-copy proof and the three-case paired diagnostic.
- [ ] Run and pass the unchanged full primary gates and supplemental accounting
  before closing #103, the milestone or the PR's draft state.

## Aligned typed payload reads (2026-10-28)

- [x] Pass full local `bin/verify` on `3950a6b1`, owned-copy proof
  `40674234871` and CPU profile `40674238323`. Hosted CI `40674226241` remains
  pending, with no current failure.
- [x] Audit diagnostic `40674230759`: all three throughput gates pass; nine
  CPU/latency/RSS comparisons still fail, plus diagnostic-only ineligibility.
  There are no other integrity findings. Keep all declared budgets unchanged.
- [x] Add a shared aligned little-endian typed-word verification path. Preserve
  ByteData reads for unaligned/other-endian input and byte-precise corruption
  diagnostics for both paths. No payload bytes, tails or workload operations
  are skipped.
- [x] Pass all 34 payload-codec tests and targeted analysis. Check all bytes of
  a read-only nonzero-offset view with matching prefix guards; a wrong-origin
  negative control accepts a corrupted first word that the real reader rejects.
  A bounded local GLM review reports no findings.
- [x] Replay the public verification APIs locally on 64-KiB canonical payloads.
  Candidate/baseline timing ratios are 0.554 FlatBuffers, 0.548 CBOR and 0.991
  unaligned MessagePack. This is a component probe, not performance acceptance.
- [ ] Complete frozen-source full verification, hosted CI and the three-case
  paired diagnostic for this candidate.
- [ ] Once diagnostic parity is credible, run the full 48-case primary and
  complete supplemental campaign, audit reports and resolve every policy failure.

## Scalar-string processing and CBOR count correction (2026-10-28)

- [x] Confirm exact-source CI `40649318425` passes on `fed23eb6`.
- [x] Audit strict primary `40635344416`: all 1,440 rows/48 cases complete,
  no integrity findings, 229 numerical parity failures. Keep the unchanged
  throughput, latency, CPU, allocation, GC and RSS gates.
- [x] Audit supplemental `40635435979`: all 50 cases complete, no integrity
  findings and 234 diagnostic performance findings. E2EE/transcode owned-copy
  counters are present; dependency internals remain explicitly unmeasured.
- [x] Remove the separate ASCII scan before writing scalar-array strings and
  enable the standard builder's ASCII option for WAMP routing fields on
  VM/native/web. Preserve normal Unicode fallback and the standard web builder.
- [x] Reproduce invalid CBOR array headers for 24–47 scalar items before
  changing behavior. Write the extended count header and include it in byte
  budgets; verify count/string-header boundaries and partial ASCII fallback.
  All 55 focused encoding/writer tests pass.
- [x] Pass full local `bin/verify` on `d6d7ae4c`.
- [x] Complete exact-source diagnostic `40668421252`: 90 rows, 12 numerical
  parity failures and the expected diagnostic-only eligibility finding. CPU
  point ratios remain 1.0267/1.0132/1.0015 for Dart values/native buffer/
  pre-encoded span. There are no other integrity findings.
- [x] Pass exact-source owned-copy proof `40668424984` and CPU profile
  `40668691198` attempt 2. Retain attempt 1's failed perf attachment.
- [x] Retain canceled warm-up runs `40668414193` (primary) and `40668418103`
  (supplemental). Free those runners for CI/profiling until diagnostic parity
  is credible; neither canceled run supplies acceptance evidence.
- [x] Reproduce CI `40668529495`'s dart2js reference-test failure. Use a
  string-only HELLO fixture with required roles rather than the SDK builder's
  unsupported uint64 accessor. All 55 focused tests pass on VM and JavaScript.
- [x] Reduce native opaque-control reserve from 1,024 to 256 bytes. The
  canonical typed CALL prefix is 208 bytes and still needs one allocation/zero
  growth; a 4,100-character procedure still grows safely and copies 16 bytes.
  All seven native frame/ABI lifetime tests pass. Verify physical alignment in
  `_NativeAllocator.allocate` and counted copies in `resize`; local GLM review
  identifies no ownership change. Keep the potential extra growth for metadata
  in the 256–1,024-byte band visible in subsequent measurements.
- [x] Complete full local verification on `3950a6b1` with the simpler
  all-builder ASCII option, smaller native reserve and browser-fixture correction.
- [ ] Finish hosted CI `40674226241` on that source.
- [ ] Resolve the focused performance gaps, then repeat exact-source primary
  and supplemental acceptance campaigns without changing the policy.
- [ ] Resolve remaining performance failures before marking PR #132 ready,
  closing #103 or completing the milestone. Passing copy accounting alone
  does not establish performance acceptance.

## Hosted browser-coverage timeout correction (2026-10-28)

- [x] Keep the core browser test suite and coverage policy unchanged while
  extending its hard command deadline from 1,200 to 1,800 seconds. Exact-head
  CI `40643065271` completed all 5,099 core browser tests but reached the old
  deadline before coverage collection completed; its preceding successful run
  took 19m32s for 5,098 tests.
- [x] Run shell syntax validation, `git diff --check`, `bin/test-fast` and
  full `bin/verify`; all pass on this working tree.
- [x] Complete hosted exact-head CI after this deadline correction:
  `40649318425` passes on `fed23eb6`.
- [ ] Preserve strict performance acceptance. The exact-source primary and
  E2EE/protocol benchmark campaigns are still running; the payload-size
  diagnostic alone showed strong 1-MiB results but unresolved 10–100-KiB
  parity misses and cannot close issue #103.

## Exact-head verifier and byte-vector candidate (2026-10-27)

- [x] Change the VM FlatBuffers byte-vector bulk copy from `setAll` to
  `setRange`; retain the existing copying and ownership contract.
- [x] Speed benchmark body verification for `Uint8List` using little-endian
  32-bit groups and a precomputed expected-word table. On a mismatching word,
  check constituent bytes so reports retain the exact corrupt offset. Keep
  generic `List<int>` verification byte-wise.
- [x] Test word-lane and trailing-byte corruption, unaligned read-only typed
  views without a body copy, and the generic-list fallback.
- [x] Run focused serializer and benchmark tests, `bin/test-fast`, full
  `bin/verify`, and `git diff --check`; local VM, Chrome/Dart2Wasm, Rust/native,
  live WAMP and consumer checks pass. The live integration matrix completed all
  2,012 cases. These checks do not establish performance parity.
- [x] Commit and push this candidate as `1101f91b38051871694722a3c29e45b7975ec4cf`.
  Dispatch exact-head CI `40526111656`, strict primary `40526116631`,
  supplemental shards `40526122419` and native-view/E2EE/transcode copy proof
  `40526128344`.
- [x] Complete the production copy proof: 120 live owned-path cases include
  96 E2EE rows, 120 transcode rows and 48 native-crypto rows. The 300-row
  inventory includes all 32 zero-avoidable-payload-copy checks. The report is
  copy-correctness evidence only and does not claim performance acceptance.
  Close issues #100 and #101 under the approved standard-SDK scope; SDK/TLS/
  crypto dependency internals remain explicitly unmeasured.
- [x] Audit the failed `payload_sizes` shard in supplemental run
  `40526122419`: job `122266082173` completed three passes, then the next
  1-MiB FlatBuffers RPC produced no samples and timed out at the unchanged
  300-second workload deadline. Three earlier 1-MiB FlatBuffers RPC passes
  completed at roughly 28.4–28.9 ms average latency. Retain this as a liveness
  failure with incomplete data, not as a parity result.
- [x] Reproduce the same 1-MiB TLS WebSocket stall in focused diagnostic run
  `40548781096` on the unchanged candidate. The three-case schedule stops at
  17/90 rows and retains three owned-process snapshots. They match router
  socket inode 31937 (`127.0.0.1:8083`) to client socket inode 32841
  (`127.0.0.1:58712`). Across the 120-second capture, the router remains
  100% receive-window-limited with `snd_wnd=3072`; its unsent queue grows from
  120,182 to 441,806 bytes. The client reports `rb2072`, and acknowledged
  bytes continue at about 14.8 KiB/s. Application threads are idle and VM
  stacks expose no runnable frames. Host memory pressure and the sampled TCP
  prune/collapse counters remain unchanged. This confirms severe receive-window
  backpressure on the owned connection, not an application deadlock or proof
  of the kernel mechanism that shrank the window. The preceding first 1-MiB
  FlatBuffers warm-up in this same replay did complete 1,000 RPCs at 24.65 ms
  average; the next FlatBuffers warm-up stalled after the adjacent CBOR and
  MessagePack passes. This confirms the failure is intermittent. The capture is
  diagnostic and cannot establish acceptance.
- [x] Pass exact-head CI `40526111656`: all 38 jobs succeeded.
- [x] Audit supplemental `protocol` shard `40526122419`: all 30 cases have
  three warmups and seven measured repetitions, exact source
  `1101f91b38051871694722a3c29e45b7975ec4cf`, unchanged inputs, no overlap and
  zero integrity findings. The diagnostic emits 157 performance findings.
  All eight small-control operations/second point estimates are below the
  faster binary baseline; CPU and p95 miss 26/30 rows, p99 misses 23/30, summed
  peak RSS misses 27/30, and throughput misses 18/22. This shard is not primary
  acceptance, but its measured regressions remain unresolved and must be
  considered before claiming the requested benchmark parity.
- [x] Audit supplemental `encrypted_progressive_results` shard
  `40526122419`: all eight cases have three warmups and seven measured
  repetitions on the exact source, with unchanged inputs, no overlap and zero
  integrity findings. The report has 46 numerical performance findings,
  including CPU misses in all eight cases and throughput misses in six. All
  applicable FlatBuffers rows contain numeric E2EE and transcode totals, with
  no unknown owned-copy boundaries; explicitly unmeasured SDK/TLS/crypto
  dependency internals follow the approved scope. This is diagnostic evidence,
  not parity acceptance.
- [x] Complete the exact-source retry of the incomplete `payload_sizes` job,
  run attempt 2, job `122381957515`. It completed the 36-row warm-up and one
  1-MiB MessagePack WebSocket measured case, then the FlatBuffers WebSocket
  request timed out. The native worker stopped while the router still had one
  invocation pending. No workload, timeout or gate was changed.
- [x] Rerun supplemental aggregation (`122393472680`); it failed because the
  payload-size shard lacked the remaining measured cases, so no complete
  50-case inventory was produced.
- [x] Obtain usable diagnostic CPU attribution. The exact-candidate hosted
  profile `40557646345` failed at `perf record` exit 255 before capturing
  FlatBuffers samples. A repeated local no-perf Dart VM profile of
  `ext_07_small_control` has a clean source audit (`1101f91b`, no changed
  inputs). Its FlatBuffers client isolate retained 295 VM CPU samples; sampled
  stacks include `serializeFragments`, `prepareWampFlatBufferMessage`,
  `encodeWampFlatBufferCbor`, `wire_writer.table`, and
  `projectWampFlatBufferMessage`. The three 30-second client runs contain
  11,209 MessagePack, 11,203 FlatBuffers, and 11,332 CBOR operations. Mean
  operation latency is 2.669 ms, 2.673 ms, and 2.643 ms respectively; client
  allocated-byte deltas are 462,641,920, 567,256,560, and 534,461,216. This is
  local macOS diagnostic evidence, not hosted parity acceptance; inclusive
  sample counts overlap and are not percentages of CPU time.
- [x] Finish the unchanged strict primary (`40526116631`): all 48 cases were
  analyzed, with 225 numerical parity-gate findings. This is a failed
  acceptance run, not evidence of an integrity or copy-accounting failure.
- [ ] Rerun the full exact-source strict and supplemental campaigns after the
  current working-tree candidate is committed and pushed.
- [ ] Audit every report, resolve all policy findings without changing the
  checked-in thresholds or workload definitions, and verify all previously
  measured codec paths remain non-regressing.
- [ ] Keep PR #132 in draft and issue #103 open until strict parity and
  supplemental performance acceptance criteria are satisfied.

Current hosted receive-window evidence: [focused capture run
40548781096](https://github.com/konsultaner/connectanum-dart/actions/runs/40548781096).
It uses the same candidate and Linux 6.17 runner family as the incomplete
payload shard. Existing older-source syscall tracing found no application
`SO_RCVBUF` or `TCP_WINDOW_CLAMP` calls, but that does not prove the cause on
this candidate. No socket option, kernel policy, workload, timeout or
acceptance budget has been changed.

## Profile-directed serializer allocation candidate (working tree, 2026-10-28)

- [x] Add bounded CBOR fast paths for short scalar argument arrays and small
  ASCII scalar keyword maps. Nested values, wide integers, Unicode, byte
  strings, and raw/pre-encoded input retain the regular encoder and structural
  validation path. Tests assert exact CBOR bytes, integer header boundaries,
  and nested-map/binary fallback behavior, including a byte vector beside a
  scalar argument.
- [x] Project schema dictionary fields directly into the message body and
  combine per-table scalar/offset scratch storage while retaining schema
  field-name and value checks.
- [x] Pass the focused FlatBuffers writer suite (54 tests), `bin/test-fast`,
  full `bin/verify`, and `git diff --check`. The fast and full verification
  runs include all 2,012 live WAMP integration cases, native/Rust tests,
  Chrome/Dart2Wasm and consumer-package smokes. The full verification preceded
  the final test-only byte-vector fallback case; the focused 54-test suite
  passed afterward.
- [x] Capture the current working tree with the no-perf `ext_07_small_control`
  diagnostic. Source inputs did not change during capture, but the report's
  Git HEAD is parent `1101f91b`; this local single-pass profile is not
  exact-head hosted acceptance. MessagePack/FlatBuffers/CBOR measured 11,024/
  10,742/10,896 operations, or 367.45/358.04/363.17 ops/s. Mean latency was
  2.714/2.787/2.748 ms and p95 was 3.633/3.865/3.742 ms. Client allocation
  deltas were 455,219,248/449,822,256/514,003,200 bytes. FlatBuffers allocation
  is within 1.2% of MessagePack in this run, but throughput and tail latency
  are still lower; the run is noisy diagnostic evidence only.
- [ ] Commit/push this candidate, then repeat exact-source CI, the unchanged
  strict primary, all supplemental shards, and the production
  E2EE/transcode/native-crypto copy proof. The preceding local profile predates
  the final nullable-scratch and integer-boundary-test correction; it remains
  directional evidence only.
- [ ] Keep PR #132 draft and issue #103 open until hosted parity and copy
  acceptance pass. The earlier exact-source copy proof closed #100 and #101;
  rerun it for this candidate before claiming those results cover this source.

## Native dispatch and typed dictionary reuse (working tree, 2026-10-28)

- [x] Replace per-message schema-table and union-reference scans in the Rust
  FlatBuffers encoder with direct union-tag lookup, retaining a table-name
  guard so schema drift fails closed.
- [x] Reuse already-typed Dart metadata maps in message projection while
  retaining the detached-map fallback for other map types. Call sites only
  read the projected dictionary or snapshot it before retention.
- [x] Reuse native Rust CBOR validation for the exact immutable argument and
  keyword spans exported from retained `StoredMessage` owners. The cache is
  keyed by byte-view identity and CBOR root policy; the decoder validates on a
  cache miss, and the public Dart frame reader never caches caller-mutable
  input. Tests cover untrusted spans, argument/keyword roots, root-key policy
  and a mutable-Dart-input writer regression.
- [x] Pass focused VM and Chrome/Dart2Wasm regressions, `bin/test-fast`, full
  `bin/verify`, formatting and `git diff --check`. Full verification includes
  Rust/native, live WAMP, E2EE/copy-accounting and consumer checks.
- [x] Commit and push the candidate as
  `b27ccc9d5ee087d11776ce0bbe7a838c21c0bfaf`.
- [x] Pass the exact-head CPU profile
  [`40635434105`](https://github.com/konsultaner/connectanum-dart/actions/runs/40635434105).
  The `ext_22_progressive` FlatBuffers client top frames no longer include
  `validateFlatBufferCbor`; UTF-8 conversion and typed-buffer growth are the
  highest sampled frames. This is diagnostic, not performance acceptance.
- [x] Pass production copy proof
  [`40635434337`](https://github.com/konsultaner/connectanum-dart/actions/runs/40635434337):
  120 live owned cases include 96 E2EE rows, 120 transcode rows and 48
  native-crypto rows. Its 300-row short inventory records all 32
  zero-avoidable-payload-copy cases. Short rows intentionally fail the timing
  policy and do not establish performance, allocation, GC or RSS acceptance.
- [x] Audit the exact-head CI mutation-gate failure in run
  [`40635344231`](https://github.com/konsultaner/connectanum-dart/actions/runs/40635344231).
  Its `client-message-binding-vm` target has adjusted assertion score 94.656%
  against the unchanged 95% threshold; conventional mutation score is 95.611%.
  There are no baseline/test execution errors. Three surviving mutations are
  behaviorally equivalent: removing `_asInt`'s null fast return reaches the
  same `return null`; changing the root-string-key default is inert for every
  call site; and forcing the validation-cache miss branch repeats validation
  over the same immutable span that Rust already validated, changing CPU cost
  only. No threshold or workload was changed.
- [x] Add source-hash-pinned equivalence reasons for those three reported
  mutation IDs in `tool/mutation_equivalents.json`. The equivalence preflight
  validates 157 proofs; 106 focused mutation-runner tests pass. Replaying the
  exact hosted mutation report with those reasons gives an adjusted assertion
  score of 95.202% and passes the existing gate.
- [ ] Complete exact-head CI after committing the equivalence-proof update.
  The current run has one mutation-gate failure; other completed jobs passed
  and the last coverage/browser-mutation jobs are still running.
- [ ] Complete the unchanged strict primary
  [`40635344416`](https://github.com/konsultaner/connectanum-dart/actions/runs/40635344416)
  and all supplemental shards
  [`40635435979`](https://github.com/konsultaner/connectanum-dart/actions/runs/40635435979).
  Both runs target this exact source commit; do not change thresholds or
  workloads.
- [ ] Keep PR #132 draft and issue #103 open until hosted CI and strict
  performance acceptance pass.

## Prior performance optimization candidate (2026-10-27)

- [x] On source `715897a6`, retain the strict result from run `40021090649`:
  all 48 cases/336 metric rows are present with zero integrity findings, but
  200 point-estimate performance findings remain. The metric thresholds and
  better-of-CBOR/MessagePack comparisons are unchanged.
- [x] Avoid ephemeral maps in common FlatBuffers WAMP message projections and
  return already-typed schema maps without a cast view or redundant key-type
  scan. Schema field-name and value validation remain active.
- [x] Reduce the FlatBuffers envelope reserve from 512 to 256 bytes, using the
  existing initial-capacity path and retaining builder growth/copy accounting.
- [x] Run focused FlatBuffers message, fragment and copy-accounting tests, then
  full `bin/verify`; all passed on this candidate. A repeated local macOS
  serialization probe showed ~12% lower small-control time and ~6–7% lower
  dynamic-value time. Treat these as component diagnostics only.
- [ ] Commit and push the candidate, then run exact-head hosted CI and the
  complete production E2EE/transcode/native-crypto copy proof.
- [ ] Run the unchanged complete strict primary and all supplemental campaigns.
  Audit every row and resolve all numerical failures; do not lower thresholds,
  omit scenarios or convert diagnostics into acceptance.
- [ ] Keep PR #132 draft and issues #100, #101 and #103 open until exact-head
  performance and copy acceptance pass. Profile run `40475920641` failed at
  Linux `perf record` (exit 255), so it provides no FlatBuffers profile.

## CBOR E2EE progressive file-transfer receiver (2026-10-23)

- [x] Reproduce the production copy-proof failure from run `40013307815` on
  source `dfc18733`: a native FlatBuffers client sending progressive CBOR E2EE
  file chunks was rejected as `connectanum.error.file.invalid_chunk`. The run
  stopped after 17/72 cases without a complete `owned_groups` inventory, so it
  provides no copy-accounting acceptance.
- [x] Trace the false rejection to the receiver's raw
  `transparentBinaryPayload` check. `toPayload()` had already decoded the CBOR
  WAMP arguments and applied PPT decryption, while retaining the transparent
  view marker. Remove that redundant representation check and validate the
  decoded one-binary-argument shape, keywords, nonempty progressive chunks,
  declared size, per-chunk limit, total accepted bytes, buffer limit and final
  digest as before.
- [x] Add a live regression for a native FlatBuffers client with a CBOR peer,
  progressive file transfer and native E2EE. Both XSalsa20-Poly1305 and
  AES-GCM pass. Assert nonzero known E2EE staging, plaintext staging and
  ciphertext staging for each cipher; keep the worker-local full E2EE metric
  labelled partial because outer serializer and transcode copies are measured
  by the production copy proof.
- [x] Complete `bin/test-fast`, the focused integration regression and all 91
  VM file-transfer tests on the current working tree.
- [x] Complete full `bin/verify` on this working tree. Formatting, native/Rust
  suites, 2,010 live WAMP benchmark cases, router tests, Chrome/Dart2Wasm and
  consumer smokes pass at exit 0. The final defensive assertion on the returned
  E2EE breakdown is covered by the focused live regression.
- [ ] Commit and push the fix, then repeat exact-head CI, the unchanged strict
  primary campaign, every supplemental campaign and the production E2EE,
  transcode and native-crypto copy proof. The strict parity and complete owned
  path copy gates are unchanged; SDK/TLS/crypto dependency internals remain
  explicitly unmeasured.
- [ ] Audit all fresh exact-head reports and resolve any measured failures.
  Keep PR #132 draft and issues #100, #101 and #103 open until performance
  parity and complete Connectanum-owned copy acceptance pass.

## Performance, profiling and E2EE copy accounting (2026-10-23)

- [x] Repair the CPU profiler's worker launch: use the declared package
  executable so spawned isolates resolve workspace packages. The profile tool
  tests pass (14 cases), and exact `ext_07_small_control` and
  `ext_22_progressive` CPU profiles complete with clean worker shutdown and
  source/input hashes.
- [x] Profile the representative workloads. Small control is dominated by
  router dispatch/timers; progressive handling includes CBOR UTF-8 scanning and
  encoding. Profiling remains diagnostic and is not parity evidence.
- [x] Reduce FlatBuffers table bookkeeping and envelope reserve allocations,
  skip fragment projection for payload-free control messages, and optimize
  ASCII-block validation without changing multibyte validation. Boundary tests
  include multibyte sequences at every block offset and malformed/truncated
  sequences; the component microbenchmark improves ASCII and sparse-Unicode
  scans. No end-to-end performance claim follows from these measurements.
- [x] Preserve native-owned ciphertext and its owner through native Session
  sends for both CBOR and typed FlatBuffers E2EE. Count Dart-to-native
  plaintext input, Rust plaintext staging, nonce/tag, ciphertext staging and
  output copies separately. Add real AES-GCM, exact counter and retained-owner
  tests, plus production probe coverage for typed FlatBuffers.
- [x] Pass `bin/test-fast` and full `bin/verify` on the current working tree,
  including Rust/native suites, 2,009 live WAMP integration cases, Chrome/
  Dart2Wasm and package consumer smoke checks.
- [x] Complete previous-source strict run `39953423478` on `9d9c26fc`: all
  1,440 rows are present and eligible, with zero integrity findings but 139
  numerical performance-gate findings. Complete supplemental run
  `39953434939`: all 50 cases/1,500 rows are present in diagnostic mode, with
  234 numerical findings. Keep these results as old-source evidence; neither
  accepts the current working tree.
- [x] Commit and push the verified source as `7621f701`. Dispatch exact-source
  CI `39992992607`, strict primary `39992996231`, supplemental campaigns
  `39992999450`, and production E2EE/transcode copy proof `39993003404`.
- [x] Audit the production proof failure on `7621f701`: a live FlatBuffers
  E2EE/progressive RPC crossed a CBOR WAMP peer, whose Rust parser rejected
  the transparent binary value as `ExpectedList("invocation.arguments")`.
  The encrypted-progressive supplemental shard reproduced the same parser
  rejection. Preserve both failures against that exact source.
- [x] Repair CBOR transparent-binary parsing in the current worktree. Contiguous
  definite payloads borrow the input span; segmented parsing retains its old
  decoder path and counts both its input read and decoded body materialization.
  Indefinite strings count only the chunks that must be coalesced. Focused Rust
  parser tests, native-message metadata tests and `bin/test-fast` pass, including
  all 2,009 live WAMP integration cases.
- [x] Extend the client and router native metadata binders to accept the same
  borrowed transparent payload view for CBOR. Add positive subview/lifetime and
  negative flag/bytes, unsupported-serializer and non-payload tests. The focused
  client/router suites pass. Full `bin/verify` passes on `86c963a3`, including
  native suites, all 2,009 live WAMP cases, Chrome/Dart2Wasm and consumer smokes.
- [x] Fix the native E2EE decrypt bridge to accept a borrowed transparent CBOR
  ciphertext alongside FlatBuffers. Verify the ciphertext remains a slice of
  the receive frame and decrypts through the public native session API with
  XSalsa20-Poly1305 and AES-GCM. Focused Rust tests and `bin/test-fast` pass,
  including all 2,009 live WAMP integration cases and ObjectBox adapter tests.
- [x] Complete `bin/test-fast` and full `bin/verify` on the corrected E2EE
  bridge. Both pass, including all 2,009 live WAMP cases, native FFI tests,
  Chrome/Dart2Wasm, ObjectBox and consumer-package smoke checks.
- [x] Commit and push the corrected, fully verified source as `a4336fcc`.
- [ ] Rerun exact-head CI, unchanged strict primary, every supplemental
  campaign and the production E2EE/transcode copy proof. Keep all timing and
  copy gates unchanged.
- [ ] Audit source `236d25e5` campaigns: CI `40006741037`, strict primary
  `40006740922`, supplemental shards `40006740888` and production copy proof
  `40006741342`. The encrypted-progressive shard hit the native CBOR E2EE
  rejection. The copy proof stopped on runner HTTP 500 before recording owned
  groups. These runs do not accept the milestone.
- [x] Push parser/binder commits `e0f5d141` and `86c963a3` (current remote
  descendant `236d25e5`); initial exact-head campaigns have been dispatched.
  The CBOR E2EE bridge fix and replacement campaigns remain outstanding below.
- [ ] Audit exact-source CI `39992992607`, strict primary `39992996231`,
  supplemental campaigns `39992999450` and production copy proof
  `39993003404`, including their input/binary hashes. These runs belong to
  `7621f701`; its copy proof failed, one supplemental shard failed on the CBOR
  parser, strict/supplemental runs are still active, and CI is queued.
  Dependency SDK/TLS/crypto internals remain explicitly unmeasured under the
  approved standard-SDK scope.
- [x] Commit the parser and router binding repair as `e0f5d141` and `86c963a3`;
  `bin/verify` passes on `86c963a3`.
- [ ] Repeat exact-source CI, production copy/lifetime proof, strict primary and
  every unchanged supplemental campaign on the pushed head.
- [ ] Fix any measured regressions and repeat the complete campaigns after every
  source change. Do not close #100, #101 or #103 or claim performance parity
  until all current-source acceptance criteria pass.

## Encrypted binary arguments as CBOR fragments (2026-10-23)

- [x] Reproduce the missing zero-copy path with a fail-first regression: an
  encrypted WAMP binary argument was re-encoded as CBOR, then copied again into
  its FlatBuffers vector.
- [x] Use the exact `ext_44_encrypted_progressive_results` CPU profile at
  `844a7913`. It has 810 client Dart samples and confirms copy work in the
  inner CBOR/E2EE path; profiling is perturbative and never parity evidence.
- [x] Let the FlatBuffers fragment path represent one binary argument as its
  CBOR prefix plus original bytes, regardless of PPT metadata. Preserve the
  outer FlatBuffers schema, the exact contiguous CBOR `args` bytes, keyword and
  lazy-CBOR paths, byte limits, and buffer-owner contract.
- [x] Test 23/24-byte CBOR-prefix boundaries, exact vector equivalence, PPT
  metadata retention, and real AES-GCM/XSalsa20-Poly1305 decrypt round trips.
  Focused writer, fragment and E2EE suites pass.
- [x] Complete fresh `bin/test-fast` and full `bin/verify` on commit `9d9c26fc`;
  both exit 0, including native router and Chrome/Dart2Wasm coverage.
- [x] Complete the exact-head production copy/lifetime proof in run
  `39953447152`: 120 owned rows (96 E2EE, 120 transcode, 48 native crypto),
  unchanged source/binary hashes and clean process shutdown. Its 300 short rows
  remain diagnostics, not timing acceptance. Dependency internals stay labelled
  unmeasured under the approved standard-SDK scope.
- [x] Previous-source CI `39953531177`, copy/lifetime proof `39953447152`, strict
  primary `39953423478`, and supplemental run `39953434939` complete on
  `9d9c26fc`. The old primary has 139 numerical findings; supplemental has 234.
- [ ] Complete replacement CI, copy/lifetime proof and unchanged strict
  primary/supplemental runs on the current working-tree source. Keep throughput,
  latency, CPU, allocation, GC, RSS and copy gates unchanged; do not claim parity
  until the reports pass. Baseline `844a7913` E2EE results have 44 numerical
  findings across eight cases and no integrity findings.

## Native sparse reader and complete kernel observation (2026-10-23)

- [x] Audit current-runtime focused19 failure: original ext18 FB deadline, 3,215
  source/four resolved/current binaries, three qualified captures with rb2072.
  Reject incomplete 1MiB kernel trace; preserve all retained records and failure.
- [x] Reproduce old metadata cap loss; pass35 private contracts with bounded64MiB
  cap. Dispatch unchanged focused retry39903748528; no observation canceled.
- [x] Audit canonical ext00 publish/ack128 untyped CPU profile39902735265:
  exact requests/source/windows/native clock/18 memory snapshots/cleanup.
  Retain small sample and instrumentation limits; existing cache alreadyinline4.
- [x] Complete fresh baseline bin/test-fast on frozen `ca020025`: exit 0,
  3,204 source/four resolved hashes fixed, 14m55s.
- [x] Privately omit absent native references; exact capacity for larger tables,
  full capacity for schemas of at most four fields. Preserve all validation.
- [x] Baseline/candidate each pass 399 unit/three integration cases. Correct the
  initial invalid Map-null fixture; incomplete Map and metadata controls then
  fail semantic assertions, with separate actual-core markers and build targets.
- [x] Audit 76 allocator inputs/836 cold and repeated observations/56 identical
  wires; no request regression. Audit 160 balanced timing rows/ten inputs.
  Nine CPU medians improve; challenge's 0.04% cost remains explicit. Exclude the
  further early-skip variant without discarding its observations.
- [x] Adopt selected tested source and semantic tests. Actual-source native
  format/tests and 34 allocator/wire observations match the private candidate;
  3,205 source/four resolved hashes remain fixed. Resolve final advisory review.
- [x] Complete full kernel replay audit: 90 valid rows/44,784 paired events,
  no trace loss/truncation; all events remain unowned without FD witnesses.
- [x] Audit separate two-second connect-hook ownership smoke: actual unprivileged
  FD inode/PID/tuple/namespace and monotonic clock match, graceful cleanup.
- [ ] Complete full resulting-runtime bin/verify, all CI jobs and renewed
  production copy/lifetime proof, retaining E2EE/transcode boundary scope.
- [ ] Review/integrate private ownership witness into original focused replay;
  attribute events before proposing any causal TLS repair.
- [ ] Pass unchanged complete primary/supplemental performance acceptance on the
  final runtime. No case, floor, repetition, deadline or better-codec comparison
  is waived; independent approval of PR #130 remains required.

## Validator memo keys (2026-10-23)

- [x] Verify baseline code/resolution equality with fully verified `f2dbdfa4`.
- [x] Stage exact integer keys with record fallback; preserve all validation and
  same-offset/different-schema identity. Reject initial fixture-import failure.
- [x] Pass 501 functional/63 JS/63 Wasm checks per variant; unsafe offset-only
  control fails three cases, including actual table-budget undercount.
- [x] Audit 160 rows/32 fresh workers/128 allocation windows, exact wires/aliases
  and source/resolution/package/window guards. Save about 63–65 bytes/decode;
  RESULT/CALL time ratios 0.98961/0.99163 are component evidence only.
- [x] Resolve advisory review; adopt exact tested runtime bytes without probes.
  Pass analysis, 3,457 serializer cases and eight component-isolation contracts.
- [x] Pass frozen full verification on `629001a6` in 22m43s, including Chrome/Wasm,
  with 3,204 source/four resolved hashes fixed and a clean tree.
- [x] Audit Linux component: 492 cases per variant/160 rows/32 workers/128 allocation
  windows/204 private hashes. RESULT/CALL ratios 1.00671/0.96892 retain the RESULT
  cost; managed savings about 65/63 bytes. No end-to-end causal speed claim.
- [x] Audit renewed production copy/lifetime: 120 owned/300 short cases/all 32
  no-copy observations, 36 groups/108 post-GC and public owners zero before GC.
- [x] Audit strict90: 90 valid rows/zero integrity findings/seven numerical costs.
  Retain RSS, Dart-value GC confidence/throughput and pre-encoded latency failures.
- [x] Complete current CI 39893888135: all 38 jobs pass.
- [ ] Complete causal TLS repair and unchanged primary/supplemental
  gates on the final runtime; preserve every started observation and budget.

## Current acceptance and TLS follow-up (2026-10-23)

- [x] Pass frozen full `bin/verify` on `984288cb` in 23m08s, including Chrome/Wasm,
  with 3,202 sources/four resolved inputs fixed and a clean tree; fresh baseline
  `bin/test-fast` also passes with identical sources/resolution.
- [x] Audit both Linux components: 491 Dart cases per variant/160 rows/32 workers/
  128 allocation windows; RESULT/CALL ratios 0.93782/0.91738 and about 456/812 fewer
  managed bytes. Native 24 reader/ten encoder rows, same wires/nonregressing requests.
- [x] Audit current production copy/lifetime: 120 owned/300 short cases/all 32
  no-copy observations, 36 groups/108 post-GC, public owners zero before forced GC.
- [x] Retain strict90's eight numerical costs despite all CPU/allocation passing;
  retain current supplemental payload's 20-row and prior55's 139-row TLS failures.
- [x] Audit current Dart profile; exclude ordinary-no-PPT proposal before measuring
  because primary values already use typed PPT. Exclude getter annotation after
  76 functional checks per variant/160 valid rows show no stable meaningful gain.
- [x] Add bounded allowlisted namespace TCP prune/collapse/window/pressure counters;
  reproduce missing/malformed/oversized/permission failures before implementation.
- [x] Pass 30 owned Linux/service/TCP, 28 capture, eight smoke and 20 CI execution
  contracts; resolve advisory review against explicit ASCII/uint64/failure tests.
- [x] Pass resulting-source full verification on `f2dbdfa4` in 22m36s, including
  Chrome/Wasm, with 3,203 source/four resolved hashes fixed and a clean tree.
- [x] Audit both untraced focused failures: 72/four valid rows, three qualified
  owned socket pairs each, original limits/cleanup; counter-enabled captures keep
  all 15 known counters and explicit namespace scope with no missing fields.
- [x] Inspect matching-version Ubuntu Azure source with checksum-matched package
  inputs and one-file patch selection; reject earlier helper failures. Preserve
  the distinction between source logic and an observed executed kernel path.
- [x] Evaluate bounded large unmasked WS writes privately: full wire identity,
  borrowed ranges, small paths, partial/error/Pending/flush/yield/cancellation and
  connection-discard/owner-release tests. Baseline has ten passes/four intended
  failures; candidate has 14 passes. Complete native suite passes 402 unit and
  three integration tests, with 6,408 private inputs/separate binaries verified.
- [x] Audit Linux focused replay 39892063835 on separate experiment commit
  `2be50a0b`: three/90 rows, original ext18 CBOR TLS deadline, three qualified
  captures/six owned socket records, worker rb35,812/peer window35,840. Exclude
  scheduling candidate; never adopt it as a fix. No observation is canceled.
- [x] Audit actual live BTF-derived inode layout, exact program render and Linux
  attach/owned cleanup. Pass 34 private contracts and actual two-second UID/env/
  argv/STOP/EOF smoke; deliberately failed observer cannot cancel sibling dummy.
- [x] Audit historical runtime55 full primary: 1,440 rows/zero integrity findings,
  exact comparison and 207 numerical failures. No current acceptance.
- [ ] Observe original current-runtime focused90 under the private read-only probe;
  match actual events to owned inode/tuple, preserve failures and every limit.
- [ ] Establish a causal TLS fix if reproduced; do not infer the Ubuntu kernel's
  behavior from upstream sources alone or change timeouts/socket/allocator policy.
- [ ] Complete full primary/supplemental acceptance on the final runtime and full CI;
  retain every started observation and required independent PR approval.

## Temporary table allocation follow-up (2026-10-23)

- [x] Pass baseline bin/test-fast on `2646ee69`, with 3,201 sources/four resolved
  inputs fixed, after full verification on runtime `55ae6f4d`/docs `02840d2d`.
- [x] Stage sparse internal Dart tables with unconditional vector validation;
  baseline/candidate each pass 491 cases, incomplete variant fails 52 CBOR cases.
- [x] Verify fresh/mutable public metadata, scalar/default/false/zero values,
  exact byte aliases and all seven payload-bearing message tables.
- [x] Reject native shared-target comparison without proven variant selection;
  use disjoint builds plus actual-core markers checked outside measurements.
- [x] Retain/fix empty-capacity Abort request regression through schema capping;
  audit all 76 inputs/cold/repeat counts, same outcomes and 56 identical wires.
- [x] Adopt only audited runtime methods and semantic tests; pass seven strict
  component module-isolation tests and all 154 existing mutation proofs.
- [x] Resolve Qwen questions by source/negative controls; GLM has no confirmed
  finding. Correct its baseline wording: old code rejected malformed CBOR.
- [x] Pass resulting-source analysis, 3,456 serializer and 39 native cases;
  actual-source allocator rows match the audited candidate, with all 3,202 source/
  four resolved hashes unchanged. Seven component/20 CI contracts and 154 proofs pass.
- [x] Complete frozen full verification on the resulting committed source.
- [x] Pass Linux components and production lifetime/copy proof.
- [ ] Pass strict diagnostic; current 90 rows retain eight numerical costs.
- [ ] Complete unchanged full primary and supplemental gates on the final runtime;
  preserve every earlier started observation and required independent PR review.

## Dictionary-field plan candidate (2026-10-23)

- [x] Use audited 10-KiB profile stacks and 360-row current-runtime payload costs
  to select repeated dictionary projection/agreement work as a concrete lead.
- [x] Derive immutable schema field lists once; share exactly the old routing/
  envelope exclusions in projection and agreement without changing value checks.
- [x] Preserve native ABI, wire schema, metadata mutation/retention and payload
  ownership contracts. Pass formatting and 154 existing mutation proofs.
- [x] Prepare isolated before/after package configs with selected-core markers,
  unchanged-wire/alias assertions, 12 existing functional suites per variant and
  balanced fresh-worker timing/allocation windows, explicitly never acceptance.
- [x] Pass five component integrity cases and 107 combined focused contracts.
- [x] Pass hosted analysis and 434 cases per private variant in 39872554911.
  Independently audit 160 raw rows/32 workers, matching wires/aliases, all inputs
  and allocation proofs. RESULT/CALL decode ratios 0.82056/0.83085, about 80 fewer
  managed bytes/decode. Local companion/verification remain machine-lease blocked.
- [x] Pass frozen `bin/verify` on `02840d2d` in 22m54s, including Chrome/Wasm;
  all 3,201 sources/four resolved inputs fixed, clean tree. Qwen review has no
  demonstrated finding; verify schema constness and no public helper export.
- [x] Audit renewed copy/lifetime 39874511303: 36 groups/108 post-GC, 120 owned,
  300 short rows/all 32 no-copy cases, exact source/resolved/native hashes.
- [x] Audit strict 39874514230: 90 valid rows, all timing/CPU/allocation pass;
  retain Dart GC CI-high 1.13284 and pre-encoded RSS point 1.01949 as failures.
- [x] Audit preceding-runtime full supplemental 39852994229: 50 cases/1,500
  rows, zero integrity findings, all 244 numerical costs retained separately.
- [ ] Complete resulting-source full CI and unchanged complete primary and
  supplemental gates; candidate runs 39874517410/39874520570 are observing.
- [x] Evaluate native agreement capacity and Dart sparse internal-table storage
  with component/functional evidence before adoption, retaining CBOR validation,
  shared aliases, scalar defaults and independently mutable public metadata.

## Fresh-process result and passive memory attribution (2026-10-22)

- [x] Pass frozen full verification on `76c4282c` in 22m59s, including browsers;
  all 3,193 sources/four resolved inputs fixed, clean tree. Core CI passes 38/38.
- [x] Independently audit both corrected RSS controls: 60 rows each, six fresh
  process pairs, exact inputs/scenarios/binaries, stable PIDs and cleanup.
- [x] Retain higher FlatBuffers RSS than CBOR in both fresh pairs for each case;
  do not attribute it solely to workload history or waive the strict RSS gate.
- [x] Prepare default-off owned VM memory buckets/maps at complete report
  boundaries; preserve snapshots/errors, source inputs and cleanup ordering.
- [x] Complete advisory review and 107 focused contracts; verify CRLF hashes
  with fail-before/pass-after and pass the local standard-VM API smoke.
- [x] Pass both pinned Linux ownership/maps smokes and independently audit
  120 rows/48 owned role observations. Most native-case gap is unnamed mappings;
  native allocation liveness versus free retained pages is unresolved.
- [x] Validate wrappers and independently audit 39869871111: allocation/free,
  owned compiled-kernel smoke, 60 rows/24 role observations, no compiler heap.
  Most arena bytes are retained free space; final external usage is 112 bytes
  for every codec. No runtime/SDK/allocator-policy/GC change or gate substitution.
- [x] Wire the four omitted diagnostic regression suites into the canonical
  tooling gate; reproduce all omissions before repair and pass after repair.
- [x] Audit failed first allocator control: 20 complete driver rows, one failed
  observation and retained 260+ MiB compiler heaps; no comparative RSS claim.
- [x] Prepare JIT-kernel wrappers, checked magic/compiler exclusion and safe
  validation phase/source locations; pass 99 focused contracts and syntax checks.
- [x] Independently audit older primary 2de4: 1,440 rows, zero integrity findings,
  exact recomputation and 144 numerical costs. Never current acceptance.
- [x] Retain kernel retry: no compiler heap in complete snapshots; one failed
  CBOR getMemoryUsage type check. Prepare safe protocol-kind/request-ID records
  with Sentinel rejection, no retries/zero substitution; 17 memory contracts pass.
- [x] Identify Collected Sentinel in isolate query; prepare one direct shared-heap
  group query, preserving IDs/refs and failure on Expired Sentinel. Pass 101
  combined focused contracts and group URL/one-query-per-group regressions.
- [x] Audit current-runtime payload batch: 360 rows, zero integrity gaps, 28
  numerical costs. Audit the exact 10-KiB CPU profile before interpreting stacks.
- [x] Implement repeated dictionary-field projection/agreement optimization;
  schema/metadata regressions and controlled component evidence pass above.
  End-to-end parity remains required.
- [ ] Complete current-head verification/CI and all unchanged acceptance gates.

## Owned receive-window and fresh-process memory discrimination (2026-10-22)

- [x] Audit real Linux smoke success and faithful replay 39845190356: 47/360
  rows, all source/resolved contents/binaries/order/floors/cleanup fixed.
- [x] Positively match three captures' tuples/inodes and counter deltas:
  client buffer 2,072 bytes, peer window 3,072 bytes, continued ~14.8 KB/s transfer.
- [x] Prepare opt-in launched-descendant socket-option tracing and fixed read-only
  TCP policy/pressure observations. Preserve original replay inputs/limits.
- [x] Prepare fresh-process six-pair RSS control, always excluded from acceptance;
  pass 15 isolated contracts, including launch/wait/cleanup and retention failures.
- [x] Retain failed initial controls; reproduce/fix report timestamp shape and
  missing canonical worker-reuse environment. Pass 18 focused cases and validate
  60 actual archived strict rows; keep failed pairs ineligible.
- [ ] Pass resulting-source review/tooling/full verification and Linux smokes.
- [x] Audit complete traced replay 39852837408: 360 rows/55 snapshots, 13,107
  setsockopt calls, no SO_RCVBUF/TCP_WINDOW_CLAMP calls. One changing-progress
  capture is excluded. This does not fix/explain earlier intermittent failure.
- [ ] Identify a causal timeout fix if reproduced; preserve acceptance policy.
- [ ] Complete all unchanged primary/supplemental timing gates and close issues
  only with required independent review and actual passing acceptance evidence.

## TCP_INFO smoke correction and remaining RSS costs (2026-10-22)

- [x] Pass frozen full `bin/verify` on `c0aef5fa` in 23m22s, including browsers;
  verify 3,189 source/four resolved hashes and a clean tree.
- [x] Audit renewed production proof: 36 snapshot groups/108 post-GC observations,
  120 owned cases/300 short cases and all 32 no-copy observations.
- [x] Audit strict 90 rows: zero integrity gaps; all throughput/latency/CPU/
  allocation/GC gates pass. Retain two RSS costs; no primary acceptance claim.
- [x] Audit the current native-buffer profile: matching source/resolved contents,
  conservative operation windows, 18 snapshots, native clocks/filter and cleanup.
- [x] Preserve failed Linux smoke 39840625793: zero benchmark rows; no selected
  owned IPv4 socket for advertised VM-service port; failed snapshot missing.
- [x] Prepare explicit owned IPv4 listener/readiness and retained failed captures.
  Pass five mocked cases and real local Dart analysis/socket acceptance/shutdown;
  adopt independent positive endpoint assertion from advisory review.
- [x] Pass all 54 combined capture/smoke contracts and 14 CI contracts.
- [x] Retry real Linux smoke and unchanged faithful payload replay; smoke passes
  and the 47-row replay failure is independently audited above.
- [ ] Diagnose/fix the two RSS costs with measured source changes; preserve
  primary/supplemental policies and all started observations.
- [ ] Complete final-source full verification/hosted CI and unchanged final
  primary/supplemental acceptance campaigns.

## Metadata reuse and bounded TCP flow diagnosis (2026-10-22)

- [x] Pass `dd6e674a` serializer cases/analysis and frozen full verification,
  including Chrome/Wasm, with 3,186 sources/four resolved inputs unchanged.
- [x] Audit its production lifetime/copy proof: 120 owned cases, 300 short
  rows and all 32 no-copy observations; verify retained resolved contents.
- [x] Audit its strict 90 rows: zero integrity gaps, twelve costs; allocation
  and throughput pass in every case. Keep parity open.
- [x] Measure private metadata-map reuse/generated enum switch: 160 balanced
  windows, eight workers per variant/shape, identical wires/storage aliases,
  about 382/392 fewer managed bytes and roughly 7% lower warm decode time.
- [x] Pass 434 cases separately on baseline/candidate, including the public
  ERROR map mutation/independent decode/lazy payload/re-encoding regression.
- [x] Complete Qwen review; verify the generated switch and local synchronous
  reader lifetime directly. No concrete finding remains.
- [x] Adopt the exact measured behavior and prepare bounded owned-socket
  TCP_INFO observations. Preserve the two failed private staging harness attempts;
  corrected staging tests pass without changes to workloads or policy.
- [x] Pass all 49 production-source capture contracts and 14 CI contracts.
- [x] Pass resulting-source formatting, analysis and 3,399 serializer cases
  with all 3,193 source/resolved inputs fixed.
- [x] Pass frozen full runtime verification on `c0aef5fa`.
- [ ] Repair the real Linux smoke preflight and finish faithful timeout replay
  as tracked above.
- [ ] Complete renewed CI/copy/strict timing, then primary acceptance on the
  final runtime. Every started earlier campaign remains available separately.

## Fixed-schema native table allocation candidate (2026-10-22)

- [x] Locate per-root/message BTreeMap allocation in the checked wire reader.
- [x] Implement sorted contiguous schema fields, reserving known table sizes;
  application maps, schema, limits, validation and byte owners are unchanged.
- [x] Add every-schema-field map equivalence, replacement/extension/order and
  nested table/byte alias regressions. Rust formatting/diff checks pass.
- [x] Pass all 39 native conformance tests and allocator components on `08efcd5b`.
  Verify same lock/compiler/probes, all 34 identical wires, 552–1,368 fewer reader
  allocator bytes/1–3 fewer requests and 720 fewer encoder bytes per fixture.
- [x] Pass frozen `bin/verify` in 24m19s, including browser suites, with all
  3,183 sources/four resolved inputs unchanged and a clean tree.
- [x] Audit renewed production copy/lifetime proof: four phases, 36 snapshot
  groups, 120 owned cases/300 short rows and all 32 no-copy observations.
- [ ] Complete full hosted CI (all completed jobs currently pass).
- [x] Complete advisory native review once the lease is available; independently
  verify Qwen/GLM claims against sorting/COW methods, fixed schema size and tests.
  No demonstrated defect remains from that review.
- [x] Audit renewed strict 90 rows: zero integrity gaps, six retained costs
  (Dart-value throughput/CPU/GC and all three RSS comparisons). All allocation
  and p95/p99 gates pass. This is not primary acceptance.
- [ ] Complete full candidate primary/supplemental timing and fix remaining costs.
- [x] Measure private reader-cache copies after baseline verification: 40 ABBA
  windows retain wire/storage identity and save about 259/456 managed bytes per
  RESULT/CALL decode. Timing is inconclusive with two workers per variant.
- [x] Pass all 433 selected cases on both configurations, including three new
  shared-string/table/schema-type/overflow regressions. Preserve the failed
  initial buffer-wrapper guard and the invalid CLI attempt as failed diagnostics.
- [x] Reproduce five baseline wrapper-inventory failures after adding the new
  test; register it in all VM/browser serializer wrappers and pass all 87 tooling
  cases, without weakening inventory equality or skipping tests.
- [x] Pass complete pre-adoption `bin/test-fast` on `de1b57f0` in 15m08s with
  3,185 sources/four resolved inputs unchanged and a clean tree; adopt the exact
  measured methods/field order without the private marker.
- [x] Pass `dd6e674a` resulting-source focused/core checks, analysis and full
  verification; dispatch hosted CI/copy/lifetime/strict and full timing.
  Copy proof and strict diagnostic are independently audited above; CI/full
  campaigns remain open.
- [ ] Run final primary/supplemental campaigns with source-qualified queues so
  independent hosted VMs can finish without waiting behind older revisions.
  Preserve every observation and all existing acceptance rules.

## Faithful payload timeout diagnosis (2026-10-22)

- [x] Preserve failed E2EE profile 39816020705: MessagePack CPU sampling precedes
  real data by about 27 seconds, correctly rejected; no FlatBuffers window.
- [x] Replace assumed startup timing with complete-request capture and
  conservative post-hoc selection. Ten clock/window regressions, 13 profile
  contracts and 14 CI contracts pass; generated Dart syntax parses. Native perf
  raw capture is retained; reports and VM samples select the data interior.
- [ ] Run resulting-source E2EE integration and independently audit clocks,
  selected timestamps, native filter/header, process cleanup and complete data.
- [x] Independently audit completed `36a6df24` encrypted/progressive shard:
  240 rows, zero integrity gaps, 240 E2EE/160 transcode/120 native-crypto copy
  reconciliations, fixed processes/inputs and matching production binaries.
  Retain 47 costs; native cases have about 6–7% CPU/4% allocation overhead.
- [ ] Verify/profile exact ext_44 native progressive E2EE with fixed CBOR PPT/
  peer serializer, XSalsa20-Poly1305 and 10-KiB application data. This is a
  diagnostic selection, not a changed workload or performance acceptance.
- [ ] Run the separately labelled 90-row reduced reproduction using declared
  ext_15/ext_17/ext_18 transitions; keep full campaigns and original floors,
  runtime/config/deadlines. This subset can never accept parity or a shard.
- [x] Reproduce profiler ambient native-thread inheritance in hosted run
  39811409005 on test-first `5b9f63c7`: all 32 mode/selection cases inherit nine
  parent threads instead of required one, before workloads. Retain the failed
  log and expected missing-artifact cascade. Pin/record one in the child only.
- [x] Verify repaired contracts (all 13 tests) and repeat the 10-KiB profile with
  the recorded pin on `80b16f4b`: 3,181 tracked/three resolved inputs fixed,
  18 snapshots and cleanup pass independent audit. No causal hotspot established.
  Actual prior thread count is unrecorded, so no causal timing comparison is
  made from earlier profiles; accepted workloads were already explicitly pinned.
- [x] Complete all 38 hosted runtime CI jobs on `2de4ec32`, including VM coverage.
- [x] Audit current-runtime payload shard: all 360 rows, zero integrity gaps,
  60 no-copy observations, stable processes, identical report and matching
  production binaries; 36 performance costs remain. This pass does not explain
  the separately reproduced intermittent stall.
- [ ] Verify/profile exact canonical `ext_08_payload_sizes` (10-KiB Dart values,
  clear RawSocket): about 19% throughput loss versus the better codec. The added
  selection keeps existing 64-KiB defaults and every accepted workload unchanged.
- [x] Pass hosted focused contracts and actual authenticated VM smoke on `f0875fef`.
  Original-process run 39803270108 reproduces the same stall after 47/360 rows.
  Audit all 3,178 sources, three lock contents, original command/config, retained
  floors/order, production binaries, all invariance flags and cleanup. These diagnostics
  do not change production Dart/Rust, workloads or acceptance budgets.
- [x] Inspect three verified router/client captures: all nine isolates return
  empty execution/async-continuation stacks, without errors. No crash or empty
  message queue is inferred; the protocol's `Stack.messages` is always empty.
- [ ] Verify added bounded owned Linux thread/TCP observations and retention of
  all four resolved inputs. Local unit/verify/model attempts remain resource-blocked;
  hosted units/real VM smoke must pass before the next unchanged full replay.
- [x] Independently audit Dart-value CPU/heap run 39803478045: 3,178 tracked
  sources/three resolved inputs fixed, 18 snapshots, actual 64-KiB request and
  clean shutdown. Profiling build flags differ from acceptance; no reader-map,
  builder-guard or retained-buffer bottleneck is established. See
  [profile research](../research/2026-10-22-dart-value-profile.md).
- [x] Independently audit checkpoint `36a6df24` failed payload shard: 85/360 rows,
  original order/floors, 14 no-copy flags, available hashes and cleanup; final
  source-invariance flag absent/unconfirmed. Same one-MiB TLS WebSocket Dart-value
  FlatBuffers deadline, no worker-crash inference from cleanup warnings.
- [x] Verify historical passing replay differs in entrypoint wrappers, listener
  settings and resolved Cargo graphs. Both use JIT, so AOT is not a difference.
- [x] Locate existing authenticated VM endpoints in owned metrics observers'
  startup arguments; a new diagnostic can preserve actual entrypoints/config.
- [x] Implement bounded original-process stack discovery and focused regressions,
  keeping legacy replay behavior, PID/ownership checks and URL redaction.
- [ ] Validate new contracts and the old-source regression check. Initial local
  fail-before attempt expires at another task's preserved resource lease without
  executing; no chronological fail-first result is claimed. Companion review is
  likewise resource-blocked. Linux CI runs units before its real VM smoke.
- [x] Run hosted focused tooling tests, real Linux discovery smoke and the full
  original schedule attempt, preserving the incomplete failed observation.
- [ ] Complete the 360-row replay after a causal fix, with unchanged floors,
  300s workload and 19,800s campaign deadlines.
- [ ] Diagnose and reproduce any captured failure before changing runtime behavior.

## Native allocator owner follow-up (2026-10-22)

- [x] Measure a private first-owner slot with identity-map fallback, using the
  external production heap/GC collector: 24 windows, matched wire/copy controls,
  about 209 fewer managed bytes per FlatBuffers construction; CBOR/MessagePack
  controls remain effectively unchanged.
- [x] Verify all 20 baseline/candidate lifecycle cases with zero native owned
  allocations/handles after each case, including freeze/resize failures.
- [x] Retain 56 balanced construction-time observations and complete wires:
  empty and one-KiB components improve; growth/one-MiB intervals overlap parity.
  All 3,176 tracked/resolved root and 346 private source/config inputs remain
  unchanged through the final isolated bundle.
- [x] Pass frozen pre-adoption `bin/test-fast` in 15m20s with unchanged inputs;
  adopt only owner tracking, preserving field order and all public contracts.
- [x] Add independent wire and isolated immediate native-cleanup regressions;
  all 49 focused ownership/frame/segment cases pass. Fix helper style notices;
  clean analysis and isolated helper rerun pass.
- [x] Validate 154 existing mutation proofs and regenerate the changed target's
  inventory. Correct the retained wrong-path tooling invocation; 13 proof and
  93 runner tests pass, with one pre-existing skip.
- [x] Verify the added parent-process input-failure coverage case; all 50 final
  ownership/frame/segment cases and clean analysis pass with all inputs fixed.
- [x] Complete actual-source review: no demonstrated ownership defect; record
  source-backed dispositions for withdrawn/inapplicable companion claims.
- [x] Pass frozen full `bin/verify` on `2de4ec32` in 23m58s: all 3,174 sources
  and four resolved inputs unchanged, clean tree, including browser suites.
- [x] Independently audit renewed `2de4ec32` lifetime/copy proof: four phases,
  120 owned cases, 300 short rows, all 32 no-copy observations and 3,174 committed
  source hashes. Production native binaries match the earlier checkpoint.
- [x] Recompute all 90 renewed strict rows: zero integrity gaps, eight numerical
  failures retained (Dart values CPU/throughput/p95/p99/GC/RSS, native-buffer RSS,
  pre-encoded RSS). All allocation gates pass; no cross-runner causal inference.
- [ ] Finish exact-head hosted CI/copy/timing renewal and full parity campaigns;
  retain running checkpoint `36a6df24` campaigns and all historical observations.

Research: [Native owner tracking](../research/2026-10-22-native-flatbuffers-inline-owner.md).

## Full-campaign failure follow-up (2026-10-22)

- [x] Confirm all 38 CI jobs pass on production source `f316941a`.
- [x] Independently recompute all 1,440 primary rows: zero integrity gaps,
  151 numerical failures; no budget or case is waived.
- [x] Audit complete protocol and encrypted shards: 900 and 240 rows,
  zero integrity gaps, 152 and 42 retained performance costs.
- [x] Preserve the failed payload shard at 139/360 rows. The one-MiB TLS
  WebSocket Dart-value FlatBuffers workload reaches its existing deadline;
  the cleanup's worker-stopped warning does not prove an earlier crash.
- [x] Dispatch unchanged full-schedule stack capture, run 39773158466.
- [x] Reproduce and fix the local tooling liveness race: a process can exit
  between `kill -0` and failed `ps`; recheck existence instead of reporting
  live unconditionally. All 16 lab tests pass without deadline changes.
- [x] Pass fresh complete precheck after the liveness repair: 15m03s, all
  3,170 source inputs and four resolved inputs unchanged. Two baseline attempts retain failures:
  an elapsed-time boundary and the optional-mirror warning. An isolated timing
  rerun passes unchanged. A concurrent mutation campaign briefly blocks the
  shared local lease; no lock is bypassed.
- [x] Measure the original native string-cache allocation before changes. A
  private lazy inline-prefix candidate removes one 108-byte allocation from
  CALL/PUBLISH/ERROR, retains all 24 wires and payload spans, and passes 37 native
  FlatBuffers tests. Original visit budgets and randomized overflow remain.
- [x] Retain invalid shared-target timing, then repeat with isolated targets and
  normal allocators. The lazy candidate avoids the eager-array control cost;
  all 56 rows and allocation controls are retained, never primary acceptance.
- [x] Add a reproducible reader allocation example to the existing hosted
  component diagnostic; production reader still unchanged at this checkpoint.
- [x] Audit the native-buffer profile: 3,173 source/dependency inputs and 18
  snapshots. Builder objects disappear after the workload; no retained-builder
  leak is established, and RSS/GC gates remain unresolved.
- [x] Publish unchanged-reader component baseline `b1baf368`, run39779792736,
  and adopt the privately verified lazy cache without schema/ABI/budget changes.
- [x] Pass frozen `bin/verify` on `36a6df24` in 27m22s, with all 3,172 sources
  and four resolved inputs unchanged, including Chrome/Dart2Wasm.
- [x] Audit Linux component baseline/candidate: same compiler/lock/probe,
  all 24 wires identical, one allocation/116 bytes saved on ordinary routing.
- [x] Renew lifetime/copy proof: four phases, 120 owned cases, 300 short rows,
  E2EE/native crypto/transcode and all 32 no-copy observations pass.
- [x] Audit current strict 90-row timing: zero integrity gaps, three costs:
  Dart GC confidence bounds and Dart/pre-encoded RSS. Every throughput,
  latency, CPU and allocation comparison passes; copy binaries match.
- [x] Audit historical full-schedule replay: all 360 rows and 60 no-copy flags,
  unchanged inputs/locks/binaries and cleanup; no stall/capture, no causal fix.
- [x] Reject private builder guard inlining after an external-controller
  heap/GC-volume experiment finds no allocation reduction. Retain the earlier
  inconclusive in-process probe and its profiler allocation overhead.
- [x] Dispatch resulting-source full primary and supplemental campaigns,
  runs 39784808712/39784813538; every original floor/budget remains.
- [ ] Complete current-source hosted CI and independently audit final full
  primary/supplemental results. Investigate measured remaining production costs.
- [ ] Complete canonical/hosted verification and unchanged acceptance campaigns
  for any adopted production fix. Keep #103 open until primary parity passes.

## Current opaque-header follow-up (2026-10-21)

- [x] Complete native writer `7a2af782` CI: all 38 jobs pass.
- [x] Complete frozen `bin/verify` on `fe72c527` in 23m22s, with all 3,169
  sources and four resolved inputs unchanged, including full browser suites.
- [x] Audit the latest native/lifetime/copy proof: four phases, 120 owned cases,
  300 short inventory rows and all 32 no-copy flags. No timing acceptance.
- [x] Audit the latest strict 90-row diagnostic: zero integrity gaps, seven
  numerical failures. Native pre-encoded passes; native-builder RSS and Dart-value
  CPU/GC/latency/throughput/RSS remain blockers.
- [x] Audit the completed earlier reader primary campaign: all 1,440 rows,
  zero integrity gaps and 173 numerical failures. Retain the completed
  1,500-row supplemental report and its 244 performance costs.
- [x] Audit current Dart-value memory/CPU attribution: all 3,172 inputs,
  18 snapshots, stable identities, actual sampling windows and cleanup.
- [x] Reject fixed-capacity and general-writer prototypes after their measured
  allocation/control regressions; retain their complete observations and source.
- [x] Validate a serializer-only opaque terminal-header prototype on 93 cases,
  original aliases, metadata, alignment and exact frame bounds. Run balanced
  seven-pair component timing; report its non-opaque fallback costs too.
- [x] Reproduce three fragments before the two-fragment regression; implement
  the opaque shortcut with the existing vector-reference API. All 134 focused
  cases, all 3,395 serializer VM cases, analysis and 154 static proofs pass.
- [x] Pass all 67 resulting-source fragment contracts in Chrome/Dart2Wasm using
  the canonical package directory; retain the failed workspace-root invocation.
- [x] Confirm all 38 full CI jobs pass on fixture-policy source `fe72c527`.
- [x] Pass frozen full `bin/verify` on resulting source `f316941a` in 22m33s,
  with all 3,170 sources and four resolved inputs unchanged.
- [x] Independently audit resulting-source lifetime/copy renewal: four phases,
  120 owned cases, 300 short rows and all 32 no-copy flags, with zero public
  native owners before GC. Timing and copy production binaries match exactly.
- [x] Audit resulting-source 90-row timing: zero integrity gaps, six numerical
  failures. Throughput medians pass; all RSS, Dart CPU and GC/p99 confidence
  bounds still block acceptance.
- [x] Retain the byte-vector type probe and both adaptive-capacity prototypes.
  The second preserves 138 complete wires and source aliases, with smaller
  backing in 51 cases but opaque encoder costs. No follow-up is adopted.
- [x] Queue the unchanged current-source full primary and supplemental campaigns.
- [ ] Complete current-source full CI and collect/audit all campaign artifacts.
- [ ] Achieve final 48-case primary parity and complete final 50-case supplemental
  evidence. Component results and historical passes cannot replace these gates.
- [ ] Retain the required independent approving review for #130 before merging
  #100/#101; leave #103 and #132 open/draft until their acceptance is achieved.

Research: [Native string cache](../research/2026-10-22-flatbuffers-inline-string-cache.md).

Research: [Dart opaque terminal header](../research/2026-10-21-flatbuffers-opaque-terminal-header.md).

## Resume after merged ObjectBox adapter (2026-10-20)

- [x] Confirm PR #133 merged at master `78f2b32b`, with hosted CI green.
- [x] Confirm the current #130/#132 source checks are green and retain failed
  historical performance campaigns as blockers.
- [x] Pass fresh `bin/test-fast` on performance source `830c34cd`.
- [x] Integrate master into #130, resolving the state-document conflict.
- [x] Carry integration `1f46c70b` into stacked performance branch #132.
- [x] Rebuild #130 native code and pass all 32 adapter tests, analysis and
  focused CI/coverage-policy/package-inventory checks.
- [x] Pass canonical verification on combined source `9e964951`; all 3,153
  source inputs and resolved locks remain unchanged. Retain the preceding
  failed lifecycle-timeout attempt and three successful isolated reruns.
- [x] Reproduce the three captured Linux paired-RSS failures before changing
  production code; preserve actual HWM independently of historical sampled RSS.
  All 36 collector and 46 comparator tests pass; budgets remain unchanged.
- [x] Pass full verification and fresh fast checks on RSS source `8104d339`;
  all 3,154 source inputs and resolved locks remain unchanged.
- [x] Confirm the full hosted CI run on `8104d339` passes as well.
- [x] Confirm exact-head #130 CI passes all 38 jobs; retain required human review.
- [x] Complete the strict 90-row Linux diagnostic and independently reproduce
  its report: all three allocation comparisons pass, eleven numerical gates fail.
- [x] Retain the renewed payload-size failure at twenty rows and its four
  allocation-precision gaps. Replay all 36 original warmup rows locally; the
  different platform/SDK does not reproduce the hosted timeout.
- [ ] Verify the opt-in hosted stack capture, then capture the Linux failure
  before cleanup and add a causal regression before application changes.
- [x] Audit the first hosted 36-row replay: no timeout or allocation gap, but
  changed runner image/kernel and actual Rust 1.99.1. Reproduce the ineffective
  compiler pin for both jobs, then set the effective environment and verify it.
- [x] Extend diagnostic traversal to the complete original scenario directory,
  preserving ordering and repeated cross-pass names. All sixteen focused tests pass.
- [x] Retain the six CLI startup failures in canonical verification on
  `53c19b72` and the passing unchanged-source isolated run. Remove repeated
  fixture compilation with a process-local immutable image cache, preserving
  every private runtime resource and deadline. Forty focused tests pass;
  compiler instrumentation confirms one compilation per process.
- [x] Pass complete frozen canonical verification on `c43f4e62`, with all 3,157
  source inputs and resolved locks unchanged. Preserve both failed Rust CLI
  attempts before the existing retry passes; the startup flake is unresolved.
  The previously blocked companion resource becomes available afterward.
- [x] Independently recompute the effective-pin ninety-row diagnostic on
  `53c19b72`: all three allocation comparisons pass, thirteen numerical gates
  fail, stable process identities and cleanup are retained. No parity is claimed.
- [x] Reproduce temporary native envelope allocations with a thread-local
  allocator probe, then replace per-table staging vectors with schema-bounded
  stack storage. Controlled restoration changes fifteen allocations to twelve
  and 3,360 requested bytes to 2,520. Original application pointers are retained.
- [x] Pass 31 isolated FlatBuffers tests and compare all 56 contiguous/segmented
  streams for 25 public models plus three opaque body sizes byte for byte.
- [x] Pass frozen full verification on writer source `40927925`, with all 3,158
  source inputs and resolved locks unchanged and no Rust CLI retry. Renew all
  120 production copy cases and 300 short supplemental rows, retaining all
  32 zero-avoidable-copy observations and unchanged production binaries.
- [x] Confirm all 38 hosted CI jobs pass on tooling source `53c19b72`.
- [x] Reject the compact-field prototype after its 3.4% parsing slowdown.
  Instead retain four table-cache entries inline with randomized overflow.
  All 32 FlatBuffers tests and 56 wire comparisons pass; controlled restoration
  changes decode allocations from seven to six and requested bytes 2,844 to 2,704.
  A local seven-pair microbenchmark improves parsing 5.2%; it is not acceptance.
- [x] Test distinct/shared table limits with independently generated frames on
  both baseline and candidate. Separate paired-diagnostic and stack-replay
  concurrency groups without changing the measurement contract.
- [x] Pass frozen full `bin/verify` on reader-cache source `28fa8011` in 23m41s,
  with all 3,159 source inputs and resolved locks unchanged and no CLI retry.
  Renew all 120 production copy cases and 300 short supplemental rows with
  identical production binary hashes and all 32 no-copy observations zero.
- [x] Audit the reader-cache ninety-row diagnostic: zero integrity gaps,
  eleven numerical failures. Native construction throughput/CPU/allocation
  comparisons pass; every RSS comparison still fails. No parity is accepted.
- [x] Complete the 360-row diagnostic with verified Rust 1.99.0: no stall,
  all 720 allocation windows satisfy the unchanged 1% limit, inputs and process
  cleanup are verified. Retain the original failure; no timeout fix is claimed.
- [x] Confirm all 38 hosted CI checks pass on writer source `40927925`.
- [x] Run a private eighteen-workload ffi-test forced-GC lifetime diagnostic:
  all tracked native owners return to zero. No owner leak is reproduced; this
  probe cannot establish timing, GC, allocation or RSS acceptance.
- [x] Evaluate avoiding eager producer Dart-view exports without weakening
  existing reusable-payload, disposal or exported-view lifetime contracts.
- [x] Confirm all 38 current reader-cache CI checks pass (`39466446961`).
- [x] Complete full primary/supplemental timing evidence (runs `39468662119`
  and `39467640642`); retain every failed gate. Both complete with zero integrity
  gaps, 173 primary failures and 244 supplemental costs; parity remains unproven.
- [x] Add an opt-in private-source producer-view lifetime probe with a throwing
  negative control and compile-time package marker. Ten tool tests, sixteen
  capture tests and fourteen CI execution tests pass.
- [x] Audit the current complete 360-row payload-size supplemental shard:
  report recomputes identically, zero integrity gaps, 32 performance-cost findings.
- [x] Observe the exact negative control on Linux; retain the positive
  variant failure at session-layer deferred materialization (`39481115738`).
- [x] Execute and independently audit the extended private session/transport
  prototype on Linux (`39481566412`): six byte-validated cases, twelve snapshots,
  zero native counters before and after forced GC, verified cleanup/invariance.
- [x] Compare the same six unchanged-API baseline cases in one Linux job
  (`39482582437`). Independent audit confirms retained producer allocations
  before GC versus zero for the prototype; all owners reach zero after GC.
  Negative control, byte checks, source invariance and cleanup pass.
- [x] Implement a separately owned, trusted disposable payload lease, preserving
  current APIs and exported-view lifetimes. Verify source identity, edits and
  clones, disposal orders, foreign/old-library fallback and E2EE/transcodes
  before using equivalent native benchmark construction paths.
  Implementation started after the matched Linux comparison: add a core packed
  byte source, retain it through session preparation, and recognize only the
  final native lease type in transport. Access to mutable message arguments
  must drop its native eligibility. Detached copies must drop source identity.
  Existing packed/deferred factories and public native helpers retain behavior.
- [x] Retain first lease candidate CI failures (`e9192132`): invalid annotations
  and stale mutation source/offset records. Remove annotations and re-audit/re-key
  the eight existing core-lazy proofs per target, adding no new equivalences.
  All 154 proofs pass static preflight; thirteen checker tests pass. Full runtime
  tests and all 393 current core-lazy mutants still require hosted execution.
- [x] On `b54db44b`, pass 142 selected core cases, eight native lease tests,
  repeated native sends without byte exports and foreign-library fallback.
  Retain the six matching-reply failures on each VM/web backend and the Dart
  fixture startup timeout. Preserve packed sources through YIELD/ERROR and
  correct fixture receive ordering, with unchanged deadlines; analysis passes.
- [x] Renew focused runtime contracts after the reply and fixture corrections.
- [x] Complete canonical/CI/mutation checks before benchmark adoption.
- [x] On `a5af2b95`, pass all 142 core and 433 client VM/browser/native contracts
  and the retained lifetime controls. Reject overridable source getters as native
  authority; use a private final core view and nonvirtual trusted lookup instead.
  Existing public interfaces remain open, with forged-interface and legacy-type
  regressions. All 144 pure-Dart core and 199 pure-Dart VM reply cases pass locally.
  Re-audit/re-key the same eight proofs per target; static preflight passes all
  154 existing proofs with a 404-mutation core-lazy inventory and no new exclusions.
- [x] Run and independently audit all four lifetime phases on `100c7624`
  (`39490332832`). All 144 core and 433 client contracts pass. The six public-API
  cases forbid byte export, dispose producers, observe actual lease owners and
  retain zero native owners before forced GC; sources/binaries/cleanup match.
  All sixteen source contracts also pass locally in Chrome/Dart2Wasm.
- [x] Retain full CI's obsolete five-file suite fixture failure (`39491312754`).
  Update the exact expected six-file inventory and both wrapper checks. All 93
  runner tests pass locally with one existing platform skip.
- [x] Independently audit the complete writer primary campaign (`39457038168`):
  all 1,440 rows meet the unchanged floors, with stable processes and zero integrity
  gaps; 169 numerical gates fail. Retain its complete raw artifact and comparisons.
- [x] Independently reproduce the complete reader supplemental report
  (`39467640642`): fifty cases, 1,500 rows, zero integrity gaps, 244 retained costs.
  All 1,500 volume, 480 E2EE, 360 native-crypto, 300 transcode and 160 no-copy
  observations validate. Do not pool absolute observations across shards.
- [x] Retain `6e490aef` full CI's core-lazy VM score failure (92.8125% against 95%).
  Add independent metadata/getter/owner assertions and an observable regression
  that wire keywords cannot expose decoded application keywords. All 147 selected
  core and nineteen Chrome/Dart2Wasm source cases pass; no production code,
  mutation thresholds, equivalences or exclusions change.
- [x] Complete all 404 VM mutants with the final test inputs: 95.3125%, eight
  additional assertion kills, unchanged source/equivalences and matching final
  test/support hashes. Clean and restored baselines pass.
- [x] Pass all 38 full hosted CI jobs on `c38ca52a` (`39500243765`). The hosted
  VM mutation report independently matches local source/test/support hashes and
  the 95.3125% score; the browser gate passes too. Retain the obsolete failed run.
- [x] Preflight the complete benchmark/proof proposal in an isolated source
  snapshot: all tooling, full analysis with thirty existing infos, fourteen
  copy-proof guards, thirteen lifetime-tool cases and all 23 shell blocks pass.
  Verify exact proposal hashes and remove the owned temporary Git clone.
- [x] Adopt explicit leases for native and pre-encoded construction in all three
  codecs. Close producers, observe actual lease owners, retain original metrics
  and preserve the frozen legacy preparation in historical diagnostic controls.
- [x] Make the original 120 owned cases and all 300 short inventory rows portable
  for hosted production renewal. Require actual package roots, immutable resolved
  inputs/binaries, no test oracles, complete counters, exact raw/pass equality and
  the specific unchanged three-warmup-floor rejection. Preserve every deadline.
- [x] Renew hosted source/lifetime and production copy proofs on `8bc62a3c`
  (`39508516372`): verify 3,167 source hashes, four lifetime controls, six public
  cases with no exported views and zero owners before GC, all 120 owned cases,
  all 300 short inventory rows and the expected warmup-policy rejection. The
  production binary hashes exactly match the paired timing binaries.
- [ ] Complete full CI on adopted benchmark `8bc62a3c`; 34 jobs are green at
  this checkpoint. Preserve the resource lease held by another task; local
  native/canonical verification and companion review remain blocked.
- [x] Independently audit strict-floor timing `39510196123`: all 90 rows, zero
  integrity gaps, six numerical failures and exact comparison recomputation.
  Native pre-encoded forwarding passes all seven diagnostic gates. Native-buffer
  construction fails RSS/p99; Dart values fail CPU/RSS/GC/p99. No parity claim.
- [ ] Attribute remaining memory costs using diagnostic class heaps, external
  usage and Linux smaps with stable PID/isolate/source/binary evidence. Keep
  forced-GC requests outside workloads and CPU windows; never use their results
  as acceptance measurements or sum shared isolate-group heaps.
  The optional probe compiles against the resolved SDK. Twelve profile tests,
  complete tooling, Python syntax and all 23 workflow shell parsers pass. Retain
  the resolved locks/package configuration and validate every snapshot's identity.
- [x] Retain the first hosted profile failure (`39514441849`): an unused Rust
  benchmark-driver lock is absent on fresh runners. Reproduce all three cases
  before repair, then pass twelve profile tests while requiring and retaining
  only the actual Dart/FFI transport dependencies. No workload ran on the failure.
- [x] Pass live Linux CPU/memory capture on `3f20fc3f` (`39514813214`);
  independently audit every snapshot, resolved input and actual sampling window
  before attributing a cost or choosing a production change.
- [x] Reproduce missing real native-build inputs in all three mocked profile
  cases. Give those tests isolated temporary Git repositories and synthetic
  resolutions; all twelve profile tests pass. Keep live dependency checks strict.
- [x] Pass eleven diagnostic, 24 campaign-runner, nine profile and fourteen CI
  checks, all workflow syntax checks, and a real three-codec one-MiB stack smoke
  with source/lock/binary invariance and owned-process cleanup.
- [ ] Confirm fresh paired-RSS evidence across every supplemental case.
- [ ] Renew owned E2EE/transcode proofs on the final frozen production candidate.
- [x] Renew 120 production copy cases and all 300 short supplemental rows on
  `f88a8f3d`, with all 3,157 inputs unchanged. All 32 declared no-copy observations
  are zero; criterion two in #103 is checked. Production inputs match the
  verified `8104d339` binary. These diagnostics do not establish speed.
- [x] Pass complete local tooling and hosted Fast Checks on isolated fixture
  repair `3e7832bf`; preserve both preceding dependency-fixture failures.
- [x] Record a pinned Linux native encoder allocation baseline for control,
  opaque, positional and positional+keyword messages at zero/one-KiB/one-MiB
  bodies. Keep input preparation outside counters, ten stable observations,
  exact borrowed-pointer checks and full wire artifacts. These allocator counts
  are component diagnostics, not Dart allocation or performance acceptance.
- [x] Retain the first Linux component-baseline failure: all native contracts,
  four lifetime controls and 34 codec tests pass; control/empty opaque counts
  match, but first nonempty `bytes` sharing changes allocator requests. Verify
  bytes 1.12.1's lazy `Shared` promotion in source. Keep the actual first-call
  observation plus ten stable later calls and exact first/steady wire equality.
- [x] Run the focused encoder-only campaign with immutable source/dependency,
  compiler and executable provenance. It bypasses no acceptance checks: final
  native/copy and complete timing campaigns remain required separately.
- [ ] Keep the first deferred-vector record inline, preserve ordered overflow,
  then verify native tests, exact wire equality, lifetimes/copies and allocations
  before paired timing. Apply only after baseline `d57a9d5e`/`39519826093`
  passes 34 codec tests and independent audit of 3,169 inputs, compiler, binary
  and ten wire frames. Single-vector steady baseline: 12 requests / 2,520 bytes;
  first nonempty Vec-backed use adds one 24-byte request. Candidate is now
  applied; its matched component/native/performance validation is pending.
- [x] Verify writer `7a2af782`: matched compiler/lock/fixture, all ten wires
  identical, exactly one request/160 requested bytes removed for cold and steady
  single-vector encoding; control/multi-vector counts unchanged. All native
  lifetime/120-owned/300-short copy proofs pass independent audit on that source.
- [x] Audit its strict 90-row run: zero integrity gaps, four numerical failures,
  exact recomputation, same production binaries. Preserve throughput/RSS/p99
  failures; component counts cannot override these gates.
- [x] Reproduce the fixture policy mismatch in source: managed builder disables
  deduplication for the single-table model, native helper retains the default
  enabled list. Verify exact model wire equality across both policies at boundary
  identities and body sizes; align only this native helper and expand hosted
  codec/model tests. Pure-Dart test and focused analysis pass.
- [ ] Renew native model bytes, ownership/copy and strict performance after this
  fixture change. Existing source7a campaigns remain separately attributed; no
  policy/case/floor/deadline/budget changes and no result is silently discarded.
- [ ] Improve measured bottlenecks, then run complete unchanged-policy primary
  and supplemental acceptance before marking #103 complete.

Existing managed worktrees and the primary mutation-runner checkout are
preserved. Integration evidence is under `out/flatbuffers-resume-20261020/`.
The standard SDK dependency exclusions and all original parity/resource gates
remain unchanged. #100/#101 require review and merge of #130; #103 stays open.

## ObjectBox adapter delivery (2026-10-19)

The user now explicitly requests implementation and pub.dev publication of a
separate `connectanum_objectbox_adapter`. This extends the earlier documentation
boundary; it does not mark the original performance milestone complete. Work
runs on `codex/objectbox-c-adapter`, based on released master `73d840c9`.

- [x] Confirm the package was absent from pub.dev and source.
- [x] Inspect published ObjectBox 5.3.2 and Connectanum beta.8 C/native contracts.
- [x] Pass a fresh pristine `bin/test-fast` baseline.
- [x] Build an independently resolving prototype; pass analysis and 23 actual
  database, malformed-buffer and native network tests. All three envelope
  codecs demonstrate zero additional adapter body copies for received entities.
- [x] Reproduce the physical-offset gate and test the actual C reader at offsets
  0–7. Remove the unsupported eight-byte physical-alignment assumption.
- [x] Reproduce unsafe nested read tracking; retain only owned database read
  snapshots in the first release. No native transaction crosses `await`.
- [x] Integrate the separate package, public example and explicit copy metrics.
- [x] Test modified/expired receive ownership and remaining model limits.
- [x] Add native-library test setup, cross-platform CI and publication workflow.
  All 32 adapter tests pass on hosted Linux/macOS/Windows. Initial full verify
  reveals an obsolete seven-package release-order fixture; update its exact
  order to eight packages and retain all dependency assertions. Its 23 tests pass.
  Add the new helper to the canonical-flow mock, retaining one local invocation
  and coverage ownership in CI. Its 14 execution tests pass.
- [x] Complete local review, canonical `bin/verify`, strict archive inspection
  and an independent consumer using hosted dependencies.
- [x] Publish the ready archive and verify the hosted version plus fresh install.
  Published `3.0.0-beta.8` at 2026-10-19 13:19:06 UTC. A fresh-cache consumer
  passes analysis and real C ingestion with zero additional native-input body
  copies; six downloaded library files and the archive digest match.

Canonical `bin/verify` passes at exit 0 on `ce1d40b5`. Hosted adapter tests
(32 per OS), Fast Checks and archive validation pass; broader CI remains in
progress at this checkpoint. Publication/source evidence is recorded in the
[ObjectBox research](../research/2026-10-19-objectbox-c-adapter.md).

Evidence is under `out/objectbox-adapter-evidence/`. The package's initial version
is `3.0.0-beta.8`, matching the current synchronized workspace gate. It depends
on published versions; no client/core version or native ABI is changed. The
isolated native compatibility module constrains its SDK compatibility bands.
C API insertion uses caller-owned immutable memory, an independent native receive lease, schema and
complete byte checks; fallback copies are counted. ObjectBox/SDK internals are
not included in those counters. See the checked ObjectBox adapter research.

Milestone: [GitHub milestone 1](https://github.com/konsultaner/connectanum-dart/milestone/1).
Branch: `codex/flatbuffers-performance-parity` in the managed profile-cases worktree.
Baseline: `54eafc5fb675886a04d390f069714c69de2aaac0`;
released master `3bac4cf5` is integrated. Preceding checkpoint: `9b28c61c`.
Merged PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105) at `0e585405`.

Merged CI PR: [#108](https://github.com/konsultaner/connectanum-dart/pull/108), master `759d3d4c`.
Merged release: [#107](https://github.com/konsultaner/connectanum-dart/pull/107) at `73d840c9`.


Current verification follow-up (2026-10-19): `5600f1f7` passes every hosted CI
job and the full local fast suite. The complete 816-mutation router gate passes
95.2087% without exclusions. `1a20561d` repairs standard-SDK GC ring loss: the
renewed 30-row 1 MiB TLS WebSocket run completes with all 60 client/server
allocation windows measured and no timeout. Its CI stops at one unformatted test
line before coverage tests. `8f6e753a` corrects it; all 736 files pass formatting.
The first full `540ab37f` verification reproduces a synthetic VM fixture missing
`clearVMTimeline`; that superseded run is failed, not a pass. The fixture now
handles the RPC, and a new regression proves clear failure aborts measurement.
All 221 collector/worker lifecycle tests pass, with causal source restoration.
Fresh full verification and production proofs remain required. The prior 85
focused Dart cases, analysis and 139 driver tests pass. See high-GC research.

The complete b8 primary campaign finishes all 1,440 rows across 48 cases with
complete allocation observations. Independent archive/source/binary/policy/
config/lock/scenario and raw/split hashes match, and the unchanged evaluator
reproduces its report exactly. It fails 176 performance gates. Supplemental
protocol completes 900 rows with 152 performance findings; encrypted progressive
completes 240 rows with 44 performance findings and three missing measured RSS
endpoints. Payload sizes stops at 192/360 rows on the recorded 1 MiB timeout.
No complete supplemental acceptance or parity is claimed. No budget, sample
floor, workload, owned-copy requirement or dependency scope is waived. The b8
frozen full verify, 300 short rows, 120 accounting cases, 36 progressive
combinations and 190 five-platform consumers remain valid for that source.
PR #132 remains draft for unmet parity; #130 still needs independent review.

Current native envelope candidate (2026-10-17): source `b2fb8b63` passes
frozen full `bin/verify`, 300 short supplemental rows, 120 accounting cases and
36 progressive combinations with all 3,124 inputs unchanged. Its strict Linux
90-row diagnostic still fails parity (CPU 1.0099 / 1.0057 / 1.0038), with all
allocation comparisons passing and additional throughput/latency/GC/RSS failures.
A fail-first regression now motivates keeping a single borrowed application's
vector header in the native envelope, removing its separate header allocation.
All 386 core, 26 segmented-forwarding FFI and 26 FlatBuffers FFI tests pass,
including generated verification, original owners and multi-vector fallback.
Fresh production copy/volume and performance evidence is pending; no acceptance
budget, workload, measurement floor or dependency scope changes. See the checked
terminal-vector research. PR #132 remains draft for unmet parity; #130 still
requires independent review.

Current fully represented CALL candidate: a fresh audited Linux profile on
`65833214` still captures 24 inclusive native-metadata retention ticks (diagnostic
only). A limited complete-grammar match now avoids the custom loader and retained
history for two PPT strings exactly represented by fresh CALL options, with all
other fields null. Unknown/null/default/tagged/Unicode or other control shapes
keep their prior path. All 3,971 binding/metadata cases, both production consumers,
nonminimal decoder comparisons and source-restored fail-first checks pass;
analysis is clean. See the checked fully represented CALL research. Fresh
performance measurements and final full verification are pending.

The preceding `65833214` whole `bin/test-tooling` and hosted Fast Checks pass
with all 3,123 inputs unchanged. Its nonfinal remaining CI jobs were cancelled
to free the profiler runner; no full CI pass is claimed for it. The earlier
`7388e666` hosted CI now passes every job, alongside its frozen full local verify
and five-platform consumers. The `b4e2b4ea` strict 90-row diagnostic has complete
allocation/RSS observations but fails CPU ratios 1.0122 / 1.0024 / 1.0045 and
other gates. All three allocation comparisons pass. No budget is changed and no
primary/supplemental performance acceptance or milestone closure is claimed.

The complete local tooling run on `10d21c49` also reproduces a stale exact
router-test-list assertion in the mutation-runner tests. Its expected list now
includes the new router regression, while the client list remains exact. All
93 runner checks (one existing skip) and the remaining five tooling scripts pass.
The full tooling prefix had passed before that assertion. Fresh whole-tooling
and hosted checks are required on the repaired fixture; no gate is loosened.

Serializer mutation inventory repair: the hosted `b4e2b4ea` Fast Checks failure
reproduces five omissions of the new core metadata test. All four CBOR/MessagePack
VM/browser support inventories and the shared suite now include it; the router
binding target also runs its new native regression file. All 87 tooling checks
and all eight new cases through both VM and JavaScript wrappers pass. No test
exclusion, inventory equality or mutation threshold is relaxed. The preceding
source completes 300 short rows, 120 accounting cases and 36 progressive cases
with all 3,123 inputs unchanged. Its redundant full verification is intentionally
stopped for the known tooling failure; it is not a pass. Application code is
unchanged by this inventory repair. Run resulting-source tooling/CI first, use
the strict Linux diagnostic to choose the next performance step, and complete
fresh full verification before handoff/acceptance.

Deferred validation repair: a bounded 10,240-value tag diagnostic finds two
well-formed date-tag values rejected by the materializer. A fail-first native
retention test confirms rejection moved to resend. Tagged dictionaries now
retain eager semantic decoding; tag-free dictionaries keep deferred snapshots.
Tags nested in metadata are detected, while byte-string contents stay opaque.
All 312 focused VM and 160 Chrome/WASM cases pass; focused analysis is clean.
The superseded `a353ce56` proof/diagnostic attempts are stopped and preserved;
no resulting-source full verification or parity is claimed for them.

Current deferred-metadata candidate (2026-10-16): the hosted Linux profile
passes source/PID/window/report/map audits, with 46 inclusive Dart retention
ticks (not a CPU-cost or parity result). Native perf Dart addresses remain
unresolved. Three fail-first cases reproduce 16 KiB of eager metadata clones
for a 4 KiB binary extension. Native CALL/PUBLISH/YIELD now validate immediately
and defer original decode/projection/snapshots, retaining immutable native bytes
and payload-free original control fields. All 129 focused
metadata cases, five Chrome/WASM cases and 3,877 binding/fragment regressions
pass, including all 32 native flag combinations. Original eager
semantics, unknown/default/null fields, edits before resend and application
laziness are covered. Fresh full/hosted/accounting/performance proof is pending.

Eligibility source `7388e666` now passes frozen full `bin/verify` with all 3,119
inputs unchanged, all 190 production consumers on five platforms, 300 short
supplemental rows, 120 accounting cases and 36 progressive combinations. The
preceding `4738c452` hosted CI is fully green. Resulting-head hosted CI remains
in progress without a known failure. No parity or milestone closure is claimed.

CPU diagnosis follow-up: Linux native profiles now request standard Dart router
JIT maps, retain PID/hash attribution and separate router/client perf reports.
Nine tool tests cover startup/probe configuration and missing/corrupt/foreign
maps; generated Dart analysis has no errors. Profiles remain diagnostic and
cannot waive canonical parity. Hosted validation is pending. Eager native
FlatBuffers dictionary retention (decode/project/snapshot) is a concrete next
cost to profile before changing metadata semantics.

Current native eligibility repair (2026-10-16): marker-only PPT borrowing can
lose the scheme when raw null PPT fields become indistinguishable from absence
in typed Dart options. Rust and real anonymous/ticket CBOR wire reproducers fail
before the repair. Capability version 2 now requires a positive per-message
native query on the held alias at lending and forwarding; ambiguous metadata
uses the existing copying path. Older marker-only bindings reject version 2 as
well. All 69 lifetime tests (eight new native binding cases), 110 worker tests,
22 native predicate combinations plus invalid/non-CALL/released aliases and the
two production consumers pass. Five native-library variants and older Dart
bindings have live compatibility coverage. See the checked native eligibility
research. Final resulting-source full/hosted verification is still required.

The preceding `4738c452` source passes frozen full `bin/verify` with all 3,118
inputs unchanged, all 190 production consumers across five platforms, 300 short
supplemental rows, 120 accounting cases and 36 progressive combinations. The
copy-boundary comparison across nine payload-size cases removes the three large
router copies for all binary codecs; it does not establish speed improvement.
The strict Linux diagnostic validates 90 rows, 180 allocation observations and
all RSS endpoints, but fails parity: CPU ratios 1.0290 / 1.0086 / 0.9974, with
additional latency/allocation/GC/RSS failures. All gates remain unchanged. Its
hosted CI is still completing without a known failure. No milestone closure or
performance acceptance is claimed for that preceding, marker-only source.

Current internal PPT candidate (2026-10-16): a fail-first regression observes
an argument-byte array crossing the internal CALL handoff for unchanged plaintext
PPT. The candidate allows retained native handoff for exact original body identity
and immutable original PPT headers, with a cached optional native version marker.
Missing/unknown markers, changed/removed input or reply headers, replacements,
custom details, active progress, encryption and reserved `wamp` payloads fall back.
Both removed-header guards have independent fail-first/restoration proofs. All
110 worker tests, 18 new-library live cases, 18 old-library fallback cases and the
two production consumers (empty/3/65,536-byte opaque internal bodies, anonymous
and ticket) pass. Final unchanged replies after progress may reuse their loan.
Copied-but-equal reply bytes also fall back. The local companion review found
and prompted the stripped-input-header guard; a final bounded GLM judgment finds
no guard blocker. Baseline `bin/test-fast` passes. Live accounting and timing for
this candidate are still pending.

Baseline verification correction: hosted `895ff3d9` CI is now fully green, as are
its five native artifact platforms. Local `ce897f98` full verification hit native
receive-worker exits while a separate `bin/test-fast` overlapped the full suite.
That failed attempt is retained with all 3,118 inputs unchanged; no cause or pass
is claimed before a serial rerun. The three profiler-path assertions are fixed.
The `4b840309` strict Linux diagnostic completes 90 rows/180 valid allocation
observations but fails CPU parity at 1.0250 / 1.0131 / 1.0129 plus other gates.
Three lifetime-RSS observations (one warmup, two measured) remain unavailable;
reading final fields together does not remove that historical-peak contradiction.
All unavailable evidence still blocks acceptance. No gate or budget is changed.

Verified prefix checkpoint (2026-10-16): source `792cd99d` passes full frozen
`bin/verify` with all 3,115 inputs unchanged, all 38 hosted CI jobs and 180 audited
production consumers across five platforms, with zero skips and independently
matched archive/library/manifest/log hashes. Renewed 300 short supplemental rows,
120 accounting cases and 36 progressive codec combinations reconcile every owned
copy and encoded-volume component. All 36 Linux RawSocket pointer probes pass.
The strict Linux diagnostic validates all 90 rows / 180 allocation observations
and every RSS endpoint, but still fails parity: CPU ratios 1.0057 / 1.0185 /
1.0229, with additional throughput/latency/GC/RSS failures. No budget is waived.
CPU profiling succeeds on a second unchanged-source attempt; the first attempt's
CBOR `perf record` failure and partial data remain retained explicitly.

Current cancellation repair (2026-10-16): pre-change `bin/test-fast` passes on
`c15f2185`; the corrected native mutation inventory passes all 93 tool tests and
hosted Fast Checks. A real workload-sequence probe also reproduces the rejected
router send with CBOR. A temporary, restored diagnostic captures the rejected
FlatBuffers frame: `ERROR(INVOCATION, 52, {}, wamp.error.no_such_invocation)` after
callee close. WAMP requires late non-waiting cancellation responses to be ignored.
The repair discards removed-invocation responses and cancellation races during
completion/progressive update, without retaining cancelled-call state. Nine
fail-first assertions now pass, alongside two existing store-error controls;
all 109 session tests pass with default and enabled native forwarding. Analysis
passes with the same 30 existing infos. The rejected-volume gate is unchanged.
See [the checked research](../research/2026-10-16-wamp-late-cancellation-responses.md).
Renewed 300 short supplemental rows, 120 independent accounting cases and
36 progressive combinations pass on `895ff3d9`. Its full frozen `bin/verify`
passes with all 3,116 inputs unchanged. All 190 production consumers across
five platforms pass with zero skips and independently matched library/archive/
manifest/log hashes. macOS Intel first failed SDK download DNS resolution;
its unchanged-source retry passes, with the original failure retained. Hosted
CI passes all 38 jobs. The strict `c15f2185` Linux diagnostic completes all 90 rows and
validates 180 allocation observations, but CPU ratios 1.0867 / 1.0254 / 1.0216
and other throughput/latency/GC/RSS gates fail. One lifetime-RSS observation is
explicitly unavailable. No performance acceptance or milestone closure is claimed.

CPU profiling now selects each of the three canonical diagnostic construction
paths explicitly; the default remains native/native-buffer. Five mocked
orchestration tests check startup/probe/audit attribution, unsupported selections
and independent targets. The actual Dart SDK verifies the six probe argument
positions; generated-probe analysis has no errors and workflow actionlint passes.
Per-request JSON and selected-case provenance are retained. The `8cb54d20`
Linux Dart-values profile succeeds: all 3,117 source hashes, the native binary,
13 actual request files, process IDs and three real sampling windows are
independently checked. These profiles never supply primary acceptance.

Full verification of `4b840309` reproduced three profiler-test failures on
macOS: the production launcher resolves output paths but the mocked assertion
expected an unresolved `/var` path. The assertion now checks the same canonical
path; all five profiler tests pass. Full verification is being rerun.

The RSS endpoint repair reads final VmRSS and the first VmHWM from one procfs
snapshot. All 32 metrics tests, including existing strict negative controls,
pass and changed-file analysis is clean. Missing/contradictory values still
block acceptance; fresh Linux observation is pending. See the paired Linux RSS
research document. Router internal PPT handoff remains the next performance
investigation: the existing Dart guards reject PPT even though the native
result-from-call encoder can preserve opaque PPT headers and body slices.
Measured router copies are about 128 KiB in Dart plus 64 KiB at native submission
per 64 KiB RPC; no-copy forwarding requires careful ownership/metadata guards.

Active native candidate (2026-10-16): a fail-first typed-send regression observes
172 native control-string copy bytes. The private canonical Call/Publish path now
builds an aligned native prefix with the vector length at its tail and submits it
with the existing frozen payload through the existing owned-segment ABI. It avoids
native reparse/composition and extra frame wrappers. Public supplied-frame checks,
64 MiB full-frame limits, profile/connection guards and the old-ABI frame fallback
remain. No native ABI, schema, payload copy, benchmark inventory or budget changes.

All 76 focused native/ownership/transport cases pass in canonical separate
processes, plus 36 complete-wire shape cases and 14 missing-optional-ABI fixture
cases. The counter test uses an isolated child VM because native counters are
process-wide. Parallel native-file runs reproduce shared-runtime teardown
interference; their failures are retained, not used as accepted verification.
The capability fixture changes only an optional dynamic export in a test copy,
not a historical binary or production artifact. A balanced local preparation-only
probe measures 8.24 to 4.18 us; it excludes send/network/session work and is not
macro parity. Resulting-source full verification, renewed live accounting, hosted
CI and strict timing remain required. Production consumers now require 14 first
profile cases: all 190 pass on `4dab389f` across the five packaged platforms,
with zero skips and independently matched log/archive/manifest/library hashes.
Resulting-cancellation-source evidence remains pending.

RawSocket prefix candidate (2026-10-16): frozen `bin/test-fast` passes on
`2524d89b` with all 3,115 inputs unchanged. A focused fail-first regression proves
large FlatBuffers/CBOR/MessagePack frames submit their small fragments separately.
The candidate copies a bounded leading prefix (at most 4 KiB including the actual
four/five-byte header), records every performed header/coalescing copy and retains
all remaining fragments with their owner anchors. All 93 socket tests pass,
including exact wire bytes, full and bounded native bodies, cap boundaries,
independent prefix storage and failed-submission accounting. Review claims were
checked against source and these regressions. No benchmark verification, policy
or native transport changes. Resulting-source full verification, Linux pointer
probes, renewed live accounting and strict parity remain required.

Current verification (2026-10-16): source `edf3feda` passes frozen full
`bin/verify` with all 3,113 inputs unchanged, renewed 120-case accounting and
36 progressive codec combinations with independent copy/volume recomputation,
and 180 audited five-platform production consumers with zero skips. Hosted CI
passes all 38 jobs on that source. Its strict
90-row Linux diagnostic validates all 180 allocation observations and every RSS
endpoint. Allocation and GC gates pass for all three construction modes. CPU
still fails at 1.03886 / 1.03192 / 1.02334; several latency/RSS/throughput gates
also fail. Actual parity and full campaigns remain blockers; no budget is waived.

The active CI change keeps all 50 supplemental cases / 1,500 rows but distributes
complete cases over three controlled Linux jobs (30 protocol, 12 size, 8 encrypted
progressive cases). Recorded two-minute workloads make the six-hour hosted job
limit a real scheduling risk. Every case retains all codecs, three warmups,
seven measurements and existing floors/guards. A strict raw-evidence merger
requires all batches and records per-batch hardware/PIDs/attempts without pooling
absolute costs. Primary acceptance remains separate. All 78 focused cases, the complete
`bin/test-tooling` chain and actionlint workflow checks pass. Resulting-source
full verification, live batch proof and hosted publication remain pending.

Live batching proof on `8b92306c` completes all 50 cases / 300 short rows,
with stable processes in each batch and all 3,115 inputs unchanged. Independent
checks reconcile 96 E2EE, 60 active transcode, 72 native-crypto and 300 encoded
WAMP-volume observations; all 32 eligible rows retain zero avoidable payload
copies. The strict policy rejects these short runs as required. A local Dart-values
CPU profile passes source/library/window audits; native CPU and interference
observation remain unmeasured on macOS. Neither result establishes parity.

Hosted Fast Checks on `8b92306c` reproduces a synthetic merger fixture depending
on an ignored Cargo lockfile. A clean-archive regression confirms the failure;
synthetic fixture locks now replace local files, and all ten merger tests pass
in a clean archive with no generated locks. Production hash verification is
unchanged. Resulting-source CI and full local verification remain required.

Native composition candidate (2026-10-16): frozen `bin/test-fast` passes on
`7452ab61` with all 3,113 inputs unchanged. That checkpoint also passes renewed
120-case copy accounting, 36 progressive codec combinations and 180 independently
audited production consumers across five platforms, with zero skips. Its Linux
CPU diagnostic passes source/library/window audits; attribution shows native
composition rebuilding already validated metadata.

The candidate retains the full existing parser, reuses its validated field tree,
changes only application slots and validates every supplied container. Original
encoded metadata survives byte-for-byte. The regression fails first on reordered
metadata keys. All 384 core / 295 FFI library cases, 71 Dart native/frame/network
cases, 33/42 independent fixtures, all 25 public message models, generated bindings
and independent live RawSocket/WebSocket peers pass. Every public model also
rejects malformed/mixed/deep supplied containers and unsupported payload slots.
A balanced local component probe improves composition from 4.50 to 3.77 us;
this is not macro parity. Resulting-source full verification, renewed copy totals,
Linux timing and fresh native consumers remain required. No public ABI, schema,
primary inventory or performance budget changes.

Verified checkpoint (2026-10-16): full frozen `bin/verify` passes on
`87b89830` with HEAD and all 3,113 inputs unchanged, including 4,984 core and
2,865 client Wasm cases (20 existing native-only skips). Hosted CI on `84fe0f29`
passes all 38 jobs. Current hosted CI remains pending.

The production native dry run on `87b89830` builds all five artifacts and passes
all 12 first-profile consumer cases on every platform, but its verifier still
expects 10. All five actual logs reproduce the count rejection and validate with
12; the declaration now requires 12, retaining every omitted/skipped/unfinished
failure guard and reporting expected/observed counts. Focused verifier checks
pass. Replacement five-platform dry-run evidence remains required.

The packed-reply Linux diagnostic on `01300605` completes 90 rows / 180 valid
allocation observations. Allocation ratios now pass: 0.84549 / 0.89153 / 0.81924.
CPU still fails: 1.03383 / 1.03914 / 1.03297; some throughput, latency, GC and
sampled RSS gates also fail. Two lifetime RSS observations are unavailable,
both in warmup; they remain explicit. Sampled RSS gates use actual
available readings and fail. No numeric gate is waived. Fresh CPU attribution,
actual parity and full campaign acceptance remain required.

Progressive-result coverage (2026-10-16): the supplemental inventory is now
version `flatbuffers_extensions_v2`, with 50 cases (1,500 full campaign rows).
The four progressive RPC cases retain three CALL chunks and now validate two
progressive RESULTs plus a terminal result. Eight added encrypted cases exercise
both ciphers, Dart/native clients and mixed CBOR peers. A frozen-input short live
proof passes all 36 codec combinations; independent arithmetic reconciles 24 E2EE,
16 active transcode, 12 native-crypto paths and every encoded WAMP-volume total.
All 92 focused Dart and 65 comparison/campaign cases pass; analysis is clean.
The preceding packed-reply commit `01300605` separately passes all 120 renewed
copy cases with 3,113 unchanged inputs. New-source full verification, hosted CI,
full campaigns and actual primary parity remain required. No budget changes.

Current packed-reply correction (2026-10-16): full frozen `bin/verify` on
`84fe0f29` passes with all 3,113 inputs unchanged; its renewed 120 live accounting
cases independently reconcile Connectanum E2EE, transcode and encoded WAMP volume
components. Hosted CI currently has 36 passing jobs and VM coverage still running.
The `f2b577ff` 90-row Linux diagnostic still fails parity: CPU ratios
1.08631 / 1.07976 / 1.07664 and native-buffer allocation 1.03508. Every allocation
observation validates; one warmup lifetime RSS endpoint is unavailable. Measured
endpoints remain valid. No gate is relaxed.

An actual typed RPC probe finds internal replies losing their packed-payload
classification because PPT metadata was omitted from payload restoration. The
candidate passes the existing four metadata fields to that restoration helper;
a fresh probe preserves the exact 65,576-byte packed payload without materialized
arguments. Progressive internal replies now consume their reply stream through
the terminal result, retaining native loans until completion or cancellation.
All 114 focused router regressions, analysis and 154 mutation proofs pass. Local
companion suggestions were checked against source and resource-lifetime tests.
Resulting-source full verification, renewed accounting and Linux parity remain
required. Existing progressive benchmark cases measure CALL input chunks; explicit
progressive-result cost coverage remains required before supplemental acceptance.
No issue, milestone or release is closed.

Encoded-volume CI repair (2026-10-16): source `1b751b72` passes all 120
live copy/encoded-volume cases, with 3,108 unchanged inputs and independent
component recomputation. Its full local verification and hosted Fast Checks
reproduce 16 synthetic fixture failures: the older fixture producer emitted
unmeasured encoded-volume observations. The producer now supplies explicit
synthetic disjoint boundary observations through the real delta/merge code, and
an independent Python test checks and corrupts every resulting combination.
Current-source verification is pending; all performance budgets remain unchanged.
The preceding `f2dc00f0` CI run passes every hosted job.

Encoded-volume follow-up (2026-10-16): the `f2dc00f0` checkpoint passes frozen
full `bin/verify`, with HEAD and all 3,105 inputs unchanged, all 120 audited live
copy cases and 170 five-platform native consumers. Its 90-row Linux diagnostic
still fails CPU (1.094–1.118) and native-buffer allocation (1.05324), among other
gates. All 180 allocation observations validate; two warmup lifetime RSS
endpoints remain unavailable and are retained explicitly. Measured endpoints
are valid. The quiet CPU profile also retains all 3,105 inputs unchanged.

The active change repairs `wire_bytes`, which actually contained application
bytes, and adds separate actual serialized WAMP message-volume accounting at
Dart/native send acceptance. No volume counter enters a copy total; optional
native symbols preserve the existing 48-byte ABI. All budgets and inventories
stay unchanged. Focused checks pass: 825 ownership/volume cases, 37 comparison
cases, 85 VM transport cases, 122 native ABI/provider/runtime cases, both browser
compilers and the older-native-library fallback. All 154 mutation proofs validate.
Resulting-source full verification and live encoded-volume proof remain pending.
Extension diagnostics and credible primary parity remain required; no issue,
milestone or release is closed.
See [encoded-volume evidence](../research/2026-10-16-encoded-wamp-volume.md).

Current candidate (2026-10-16): a pinned, licensed SDK-derived VM builder
bulk-copies typed byte vectors through the standard Builder API. Web retains the
SDK backend after a read-only alias regression. Bool staging is eliminated and
owned UTF-8 staging is observed as framing copies. All outgoing checks remain.
Checks pass: 3,386 serializer VM / 3,391 JS / 3,381 Wasm, 30 native-owner cases,
analysis, all 154 mutation proofs, generated bindings, and independent 33/42
fixture plus 25-message interoperability. Component bulk-writer time is about
1% of the SDK byte loop; no macro parity is claimed. Final full verification,
renewed live accounting, hosted consumers and the Linux comparison are pending.
Actual encoded-size measurement and extension diagnostics remain blockers.
See [bulk writer evidence](../research/2026-10-16-flatbuffers-bulk-byte-writer.md).

Current checkpoint (2026-10-16): `5dda2ecd` passes `bin/test-fast`, focused
VM/JS/Wasm ownership checks, all 120 renewed copy cases with 3,099 unchanged
inputs, and 170 audited five-platform production consumers with zero skips.
Its 90-row Linux diagnostic improves CPU to 1.1590 / 1.1782 / 1.1633, but
native-buffer allocation is still 1.0634 and other numerical gates fail. One
baseline lifetime RSS endpoint is unavailable. Bounded rereads now retain every
actual observation; all 30 focused Dart and 32 Rust library / 139 driver tests
pass. Persistent or missing endpoints remain unavailable; no budget is changed.

Performance and reporting remain blockers: investigate repeated metadata string
allocations, measure actual encoded WAMP volume separately from logical
application bytes, and complete the declared extension diagnostics. The 48-case
primary campaign must wait for credible diagnostic parity. Full resulting-source
verification remains required; no issue or milestone is closed and no release
is made.

Concrete typed-word candidate (2026-10-16): the preceding source `25862a53`
passes frozen full `bin/verify` with all 3,098 inputs and HEAD unchanged. Its
90-row Linux diagnostic has no RSS/duration measurement failures but still
fails CPU (1.32–1.39) and native-buffer allocation (1.0838), among other gates.
A concrete `Uint32List.view` writer matches the SDK wire/allocation layout in
38,400 prototype cases and reduces 64 KiB component writer time to 0.307–0.317
of the SDK path. Integrated VM serializer (3,378) and native ownership (30)
cases pass; browser, final-source verification and end-to-end measurements are
pending. This differs from the rejected generic word adapter. Native source188
artifact retry now passes all five platforms, with 170 independently audited
consumer cases and zero skips. No parity or release is claimed.
See [concrete writer evidence](../research/2026-10-16-flatbuffers-concrete-word-writer.md).

RSS/duration repair ready (2026-10-16): fresh Linux lifetime RSS is now read
after the final sampled live boundary; missing or contradictory endpoints stay
null through Dart/Rust reports while other resource observations are retained.
The scheduler now performs real operations until actual sample coverage reaches
the unchanged minimum; the fail-first logging-delay case reproduces 2.578 ms
versus a required 30 ms. All 139 Rust driver, 31 library/artifact, 93 focused
Dart, 35 comparator and 87 inventory-script checks pass; analysis and all 154
mutation proofs pass. Resulting-source full verification is pending.

The `188d33cd` Linux diagnostic completes but still fails CPU (1.24–1.34)
and native-buffer allocation (1.0637), among other gates. A quiet CPU profile
without allocation tracing identifies SDK byte-vector writing as a major cost.
All 3,097 tracked/intended inputs stay unchanged during profiling. The next
optimization targets that measured bottleneck; no parity is claimed. Native
artifact source188 fails only Linux x64 manifest attestation due to a Sigstore
network timeout; its failed job is retried. PR #130 source63 remains fully green.
See [boundary repair evidence](../research/2026-10-16-linux-rss-duration-boundaries.md).

Verification/measurement repair (2026-10-16): `188d33cd` passes all
120 renewed HTTP copy cases with all 3,097 inputs unchanged. Its local diagnostic
still fails: throughput 0.9827 / 1.0156 / 0.9838; allocation
0.9758 / 1.0884 / 0.9853. Every observation remains retained. Frozen full
verification fails five inventory assertions because the new metadata encoding
test was absent from four serializer mutation support lists and their shared
wrapper. The test is now added everywhere, preserving every prior source/test
and floor; all 87 verification-script checks and 154 mutation proofs pass.
Resulting-source full verification remains required.

The preceding `249e0c8a` Linux 90-row/10-second diagnostic completes with full
resource observations but fails all CPU gates (1.30–1.41), several resource and
latency gates, stale child max-RSS versus later live-RSS checks, and one sample
window just below 10 seconds. No gate is loosened. Current-head Linux diagnostic
is running. Obsolete full campaigns are cancelled with artifacts retained;
a fresh primary must follow measurement repairs and credible diagnostic parity.
The next work repairs RSS/time boundary capture, then profiles actual CPU cost.

Latest performance candidate (2026-10-16): source `249e0c8a` passes the
renewed 120-case copy matrix with 3,097 inputs unchanged. The short diagnostic
improves native-buffer throughput to 1.0170 and p95/p99 to 0.9625 / 0.9927,
but allocation still fails at 1.1503; managed/pre-encoded throughput is below
parity. Component probes show native construction is already cheaper than
MessagePack. Sharing immutable membership sets in metadata projection reduces
profile allocation from about 22,000 to 8,600 bytes while retaining every check.
All 3,375 serializer VM tests, analysis and unchanged mutation preflight pass.
Browser, whole-source and end-to-end verification are pending for that candidate.

Current checkpoint (2026-10-16): `d12196ce` passes renewed 120-case owned
E2EE/transcode proof with 3,096 inputs unchanged and all 170 audited five-platform
production consumer checks. Its 90-row diagnostic still fails (throughput
0.9518 / 0.9887 / 0.9740; allocation 1.0384 / 1.1694 / 1.0535), with every raw
allocation observation valid. Full verification finds one existing FastCGI
stdout-limit fixture race; a narrow test-only reset allowance fixes all 29
focused cases while preserving HTTP status/reason/event/closure assertions.
The next candidate removes CBOR wrapper/hash/UTF-8 staging for small ASCII
scalar metadata while preserving exact wire bytes and all fallback/budget rules.
A component probe drops allocation from about 8,900 to 650 bytes per dictionary.
Whole-source verification and end-to-end performance remain pending. A separate
hosted 90-row Linux diagnostic retains the primary durations/samples/repetitions;
it never establishes primary acceptance. #103 remains open; no release is made.

Current performance work (2026-10-16): all hosted CI checks pass at
`63a802f7`, including the complete VM coverage policy with no findings and
benchmark coverage 98.74% (3,846/3,895). Frozen local `bin/verify`, package
publishing dry run and five-platform production consumers (170 cases, zero
skips, independently audited hashes) also pass. PR #130 contains this reviewed
accounting/coverage checkpoint.

Experimental `1785387e` passes `bin/test-fast`, 120 HTTP copy checks with all
3,096 inputs unchanged, and 170 audited production consumer cases. Its 90-row
diagnostic fails the unchanged budgets: throughput 0.9347 / 0.9875 / 0.9478 and
allocation 1.1348 / 1.1691 / 1.0589. All 180 allocation reports validate. Large
read-only word writes regress, so the selected candidate restores the standard
SDK byte writer while retaining the strict single-pass scalar metadata parser.

The selected candidate avoids retained Call/Publish dictionary snapshots only
in transient native outgoing profile checks, after the same wire/model/projection
validation. Public deserialization and negotiation metadata remain unchanged.
Fragmented typed FlatBuffers PPT arguments retain a canonical CBOR prefix and
the original byte body, preserving the existing args wire representation and
kwargs/crypto/metadata-authority rules. Explicit contiguous access accounts for
its coalescing copy. Regression checks pass: 3,370 VM serializer tests, 3,376
JavaScript tests, 3,366 Wasm tests and 54 serial native profile/network tests.
Independent upstream/extended readers accept 33/42 fixtures, bidirectional
Python/Dart/Rust Call conformance passes, and contiguous/segmented output for all
25 public messages agrees. The bounded local judge finds no confirmed defect;
all requested prefix boundaries are covered against an independent CBOR encoder.
Mutation preflight and analysis pass. Current-source full verification, renewed
120-case copy proof and paired timing remain pending; no parity acceptance or
release is claimed. See [vector/metadata research](../research/2026-10-16-flatbuffers-vector-metadata-allocation.md).

## Earlier checkpoints

Coverage repair in progress (2026-10-16): the first full benchmark VM run
passes all 2,657 tests but measures 93.81%, below the unchanged 98% gate.
The new external metrics observer runs outside the instrumented test process.
Direct real-VM collector tests and deterministic observer-protocol/process-failure
tests pass all 72 focused checks; the fresh full benchmark suite passes all
2,692 tests. Fresh coverage calculation and hosted CI remain pending; earlier full verification is historical evidence for `24f4276b`.
The latest scalar-metadata diagnostic still fails parity: throughput ratios are
0.9602 / 0.9973 / 0.9679 and allocation ratios 1.1364 / 1.1777 / 1.0556 for
managed values / native buffers / pre-encoded spans. No acceptance gate is waived.

Browser CI repair (2026-10-16): hosted `24f4276b` passes 4,852 browser
cases and fails two new reference-builder tests. Raw SDK builders call uint64
accessors unsupported by dart2js; production uses the portable WAMP builder.
Both failures reproduce locally. The byte-vector spy now supplies only relevant
fields and the wire comparison uses the portable builder. All 155 focused JS
cases pass without skips or threshold changes. Resulting-head CI is pending.

Verified allocation checkpoint (2026-10-16): full frozen `bin/verify` passes at
`24f4276b` with HEAD and all 3,092 tracked/intended-new inputs unchanged. This
includes Rust, VM/live, packaging, core Chrome/Wasm and 2,865 client browser cases
with twenty declared native-only skips. Prior copy-accounting source `bb549a4c`
also passes every hosted CI check and all five production consumer platforms
(170 cases, zero skips, audited hashes). New-head CI/native dry run is running.

The next measured bottleneck is repeated FlatBuffers metadata normalization.
A validated scalar-map shortcut preserves fallback semantics for complex values;
all 3,358 serializer cases pass. Fifty-five differential/reference vectors and
all truncation prefixes pass on VM and Chrome/Wasm. Two independently checked
metadata-allocation probe pairs drop from about 13,900 to 3,000 managed bytes per
decode; this is allocation-only diagnostic evidence, not primary acceptance.
A fail-first managed-fixture case also exposes an unobserved byte-vector build;
the benchmark now uses the public observed builder. All 31 fixture cases preserve
wire bytes/capacity and pass. New end-to-end timing and final verification remain
pending, and #103 stays open with unchanged budgets.

Allocation/performance follow-up (2026-10-16): stock-SDK heap/GC volume now
retains raw proof and runs its observers outside both measured PIDs. Independent
Python recomputation rejects the legacy live-heap census and forged totals;
35 comparison cases and the live 24-row/48-process allocation matrix pass.
The Rust driver now preserves the raw metadata (fail-first round-trip regression,
17 driver cases pass). GC crossing one measured snapshot is reproduced; bounded
three-attempt boundary retries retain the entire original workload and collection
window. All 100 focused allocation/GC/wire/process cases pass.

Typed input, completed CBOR encoder/decoder buffers and PPT singleton binary
views avoid extra copies. Metadata-only native PPT views now respect dictionary
authority; all 1,916 binding cases pass. All 3,270 serializer/owned-copy cases
pass before the small-frame reservation threshold refinement. Large-frame
reservation reproduces oversized backing allocation and matches standard wire
bytes. The next short diagnostic reaches 1.003 native-buffer throughput, but allocation
ratios remain 1.10–1.23 and latency still fails. All 180 allocation observations
validate after the boundary repair. The earlier diagnostic has one
allocation report correctly remains unmeasured at the ambiguous GC boundary.
No budget or inventory is relaxed. Current-source full verification, new paired
timing and hosted acceptance remain pending. See
[allocation method](../research/2026-10-15-dart-allocation-volume-research.md).

Owned pipeline accounting follow-up (2026-10-15): E2EE totals now combine eight
independently observed owned components; mixed transcode totals expose actual
router serializer/dispatch buffers separately from transport. Strict producer and
Python validation reject stale native coverage, rewound counters and forged
subtotals. The unchanged 48-byte codec layout has a separate optional coverage
scalar; the prior production library safely yields unavailable coverage. Focused
717 benchmark, 86 client and 35 router cases pass. All 120 full HTTP cases
pass copy validation. Frozen full verification passes with all 3,082 inputs and
HEAD unchanged. An extra native typed pub/sub check finds a benchmark verifier
reading the wire payload; its one-accessor correction and eight fail-first
regressions pass afterward. Final combined/hosted verification remains pending.
Missing resource values now display unmeasured/fail rather than false 1.0 parity.
No issue is closed and all performance budgets remain unchanged. See
[accounting contract](../research/2026-10-15-owned-pipeline-copy-accounting.md).


Lazy mutation startup repair (2026-10-15): hosted `b43a0a56` rejects stale
source-bound equivalence records before running `core-lazy-vm` and web. All eight
previous predicates map uniquely to unchanged text in the full current
356-mutant inventory. Their reasons and count are revalidated; only IDs and
source hashes change. Both full 356-mutant targets pass at 95.7142857143%,
with zero errors/timeouts and all 246 relevant inputs plus HEAD unchanged.
Independent benchmark/reporting changes are explicitly excluded from that
scoped proof. A preflight catches sixteen additional older stale records; their
unchanged predicates are revalidated without changing reasons, counts, ranges
or floors. All 154 proof records validate and thirteen preflight tests pass.
Canonical scripts now reject stale metadata early. Replacement hosted CI is
pending. Production dry run 38798749509 passes all five platforms and 170
consumer cases with zero skips and audited log hashes. The two paired 90-row
reply diagnostics complete cleanly but still show roughly 0.84 throughput
ratios; no parity is established. Dirty aggregate/native copy follow-up remains
unverified as a whole. See [proof refresh](../research/2026-10-15-lazy-mutation-proof-refresh.md).

Allocation measurement audit (2026-10-15): pinned Dart 3.13.1 source and a
forced-GC repro show `accumulatedSize` is live heap inventory, not allocation
volume. Prior allocation ratios cannot establish that resource gate. A standard
SDK native heap-callback prototype preserves 128 MiB of allocation history after
GC, but small-allocation weighting and observer isolation still need validation.
No numeric budget changes. See [allocation research](../research/2026-10-15-dart-allocation-volume-research.md).

Owned-copy CI checkpoint (2026-10-15): all 633 client binding mutants
complete with zero errors/timeouts, clean/restored baselines and a 95.9302325581%
assertion score against the unchanged 95% floor. Pinned client/core inputs stay
unchanged; the independent inventory guard and unrelated router correction are
recorded separately. The first full verification fails because the new serializer
test was missing from its independent inventory expectation. The second frozen
run reaches three JSON mixed-PPT failures, exposing an opaque-body conversion
gap. A router-only view wraps the same bytes in one Arguments item, retaining the
original message/owner. All fourteen fail-first control/body cases and all 107
public mixed PPT/E2EE cases now pass. The legacy JSON codec stays unchanged.
Frozen full `bin/verify` passes at `03524853` with HEAD and all 3,070
tracked/intended-new input hashes unchanged. This includes Rust, VM/live and
packaging smoke tests, core Chrome/Dart2Wasm and 2,859 client browser cases
with twenty declared native-only skips. Replacement hosted CI and production
consumers are pending; complete owned copy totals and parity stay open.

Hosted CI repair in progress (2026-10-15): `fc1881d3` finishes with 39
successful checks and one root failure: client message-binding mutation score
94.3359375% versus the unchanged 95% floor; Full Verify correctly fails as its
aggregate. A 24-case storage matrix adds event/result/invocation/error, PPT/plain
and three binary encodings. It reproduces a native ERROR metadata bug: human
message text was mistaken for a PPT scheme. The repaired predicate reads ERROR's
actual metadata. All 1,910 binding cases pass and four exact hosted survivors
are killed by assertions with source restoration checked. Complete resulting
inventory, frozen full verification and replacement hosted CI remain pending.

Owned copy foundation and reply retention (2026-10-15): cumulative Dart
observations now cover explicit clones, coalescing, byte-vector writes, allocator
moves, isolate transfers, framing, keys, PPT and portable crypto. Router worker
snapshots fence asynchronous work and reject missing/replaced workers; workload
quiescence returns an explicit success flag. The separate optional native codec
ABI observes vector/string/growth/parser/framing/key bytes without extending any
published layout. Full totals remain uncertified while the source inventory and
aggregation are completed. The new reply regression removes two full model
copies per RPC by retaining matching packed lazy payloads; other codecs retain
byte-identical wrapper output. All twelve reply cases, 371 Rust core and 294 FFI
cases, 3,383 shared serializer cases, and thirteen live copy/encryption/file cases
pass. Production verification, new timing and complete accounting remain pending.
No remaining issue is closed. See [source and limits](../research/2026-10-15-owned-copy-foundation.md).

Raw-frame verification and exact-capacity diagnostic (2026-10-15): full
`bin/verify` passes at `fc1881d3` with all 3,057 tracked inputs and HEAD unchanged.
Both 90-row paired runs complete using the same production library. Throughput
ratios remain around 0.80 of the better binary baseline; exact fixture capacity
does not establish a useful speed improvement. Allocation and latency still
regress. Required Linux CPU/RSS evidence remains unavailable; diagnostic ratio
placeholders are not measurements. A five-platform production dry run targets
`fc1881d3` (run 38773856451). The next controlled change reserves 256 bytes for
native controls and caches immutable Dart schema field-name sets. All 366 Rust
core cases, 514 Dart FlatBuffers cases, pinned Python/Dart/Rust interop and
separate client/router counter suites (83/34) pass. Local review finds no confirmed
issue. New-source timing and final full verification remain pending. See
[control construction and evidence](../research/2026-10-15-flatbuffers-control-construction.md).

Raw-frame follow-up (2026-10-15): single-span native frames now retain their
owner instead of copying, and reversed ranges return unavailable instead of
panicking. Fail-first regressions, all 366 Rust core tests, the additive 32-byte
ABI guard, 46 fixture/report cases, 117 public router/native PPT cases and three
live codec observations pass. Those unfragmented live rows report zero raw-frame
copies; no macro performance improvement is claimed. Exact pinned benchmark
buffer sizing preserves wire bytes and avoids a partial Dart backing view.
Fresh full verification, production artifacts, complete E2EE/transcode owned
totals and parity remain pending. See [source and limits](../research/2026-10-15-raw-frame-copy-observations.md).

Verification checkpoint (2026-10-15): `CARGO_INCREMENTAL=0 bin/verify`
passes at `7976a464` with Git HEAD and all 3,052 tracked input hashes unchanged.
The resulting complete 315-mutant E2EE target also passes at 95.3125%, retaining
its 95% floor and zero errors/timeouts. All 131 randomized VM/native cases,
30 randomized Chrome/Dart2Wasm cases and nine live RPC/file cases pass. Hosted
acceptance and complete outer/transcode totals remain pending. A source audit
also identifies unconditional singleton raw-frame coalescing in the native
FlatBuffers receive path; its owner/pointer regression is prepared but no
optimization or performance improvement is claimed yet.

PPT/framing observation follow-up (2026-10-15): fresh pre-change
`bin/test-fast` passes on unchanged combined head `8f1fbfb9`. Actual CBOR PPT
wrapping, binary cloning, coalescing and cold metadata setup now have separate
scoped counters for native and portable providers. An optional native plaintext
framing scalar observes file wrappers and canonical headers while preserving
the sixteen-byte v1 ABI. Fail-first observations reproduce the undercounts;
nine Rust and 131 randomized focused VM/native cases pass. Fresh-process probes verify the
new scalar and the preceding production library's null fallback. All 30 randomized
Chrome/Dart2Wasm cases and nine live RPC/file cases pass. Full frozen
`bin/verify` passes at `7976a464`. See
[PPT/framing source and limits](../research/2026-10-15-ppt-serializer-copy-observations.md).
Outer WAMP serialization, transcode totals and all performance acceptance stay
open. No milestone issue is closed by these partial observations.

Current follow-up (2026-10-15): finish remaining FlatBuffers issues.
Both unprofiled 90-row router-view diagnostics complete. Dart-value FlatBuffers
throughput improves 23.2% (best-binary ratio 0.6546 to 0.8040); native construction
and pre-encoded cases show no useful gain. All remain failed acceptance evidence.
The next native receive regression reproduces another opaque-body clone. Shared
core byte views now serve only the built-in native PPT decoder, preserving ordinary
copy semantics, custom decoders and FlatBuffers' 64 MiB encoded limit. All 1,906
focused client/core cases and twenty Chrome/Dart2Wasm cases pass. Full-source
verification and new-source measurements remain pending. PR #130's hosted
core-E2EE mutation failure at 94.921875% is repaired in `ef1fc548` without
changing its 95% floor; replacement hosted CI is pending.

Performance follow-up now uses `codex/flatbuffers-lazy-ppt-views` based on
`25e0d41f`; PR #130 retains the E2EE/counter and verified-shard review. A server
CPU diagnostic identifies eager CBOR decoding just to unwrap an opaque PPT body.
The public native test reproduces a body clone for FlatBuffers/CBOR. Bounded
singleton byte views repair that boundary without parsing the application model.
Twenty unit cases, 107 public PPT cases and nine internal regressions pass;
analysis is clean. Paired unprofiled diagnostics and complete frozen verification
remain pending; the earlier profiled attempts are failed diagnostics, not parity.
See [implementation and evidence](../research/2026-10-15-internal-ppt-byte-views.md).

The frozen full run preserves all 20 input hashes and reaches the benchmark
suite, where a stale live assertion expects zero AES assembly bytes rather than
48. The repaired test checks both RPC legs: four portable/native and cipher
combinations now pass, including exact 48-byte portable AES and 160-byte native
nonce/tag totals for two RPCs. This first full run exits 1 and is retained; a
fresh full rerun is still required. New-source production artifacts pass all five
platforms: downloaded logs verify 170 visible cases, zero skips, 22 file hashes,
ABI guards and lifecycle. The downloaded production library passes the actual
crypto copy probe. No E2EE/transcode total or parity acceptance is added.

E2EE follow-up reproduces and repairs unobserved portable AES nonce assembly,
partial failed native legacy CBOR coercion, and Rust nonce/tag framing copies.
An additive optional scalar preserves the 16-byte v1 ABI; eight Rust crypto
cases pass. The final sequential provider/report retry passes 117 cases against the rebuilt
new-scalar library; older production lookup safely returns unavailable. Frozen
full verification remains pending. The CI audit
now also requires both router shard jobs, and all 28 audit cases pass on a stable
head. The earlier 129-case run's four failures come from moving HEAD during its
fake-head assertions; its stable audit retry passes. The current fast run sees a
transient Dart ffi qualification error during edits and is not accepted; analysis
passes after qualification. See [copy boundaries](../research/2026-10-15-e2ee-copy-boundaries.md).

PR #129 now passes every hosted job and both Codecov gates. PR #130 passes
both coverage gates, but its router message-binding mutation job reaches its
90-minute deadline after 622 of 699 mutants, cancelling Full Verify. A rerun
is dispatched. The follow-up partitions the unchanged full inventory into two
shards and requires independently regenerated union scoring plus successful
shard jobs in Full Verify, using the existing MCP mechanism. No timeout,
mutation inventory or score threshold is relaxed. Focused CI checks are running;
complete new-head verification is pending. E2EE/transcode owned-boundary totals
and all performance parity budgets remain open. The shared local native resource
lease temporarily blocks timed diagnostics; no other campaign is interrupted.

Current follow-up (2026-10-14): validate FlatBuffers byte-vector views.
Branch `codex/flatbuffers-byte-vector-views` starts at scope checkpoint `fc808e92`;
[PR #129](https://github.com/konsultaner/connectanum-dart/pull/129) retains the
separate measurement/scope review. Fresh pre-change `bin/test-fast` passes.
Immutable byte views retain exact input ranges and storage, with explicit native
lifetime requirements. Both pinned generators select the same reader. Shared
payload generation fills its byte buffer directly; FlatBuffers builders reserve
the known model size. Focused VM and Chrome/Dart2Wasm binding/view cases pass.
The initial root-level browser invocation fails its hybrid loader paths; the
package-root retry passes 79 cases. A live diagnostic first rejects an outdated
driver without executing rows; the driver is being rebuilt. No parity is claimed.
Fresh pinned interop passes 33 upstream/42 extended fixtures and all 25
public message types. Both 90-row before/after diagnostics complete; native
FlatBuffers throughput improves roughly 5–6%, while the Dart-value case does
not improve usefully and allocation/GC ratios still regress. Both diagnostics
fail acceptance; Linux CPU/RSS and full duration/matrix evidence remain absent.
The first full verify rejects the new test missing from serializer mutation
inventories; all four target support lists and the shared suite now include it.
Replacement full `bin/verify` passes at exit 0 with all 12 frozen
code/test/config inputs unchanged; no mutation target or budget is reduced.
The measurement branch's child ABI probe now contributes real coverage, and
preceding head `e55d36cf` passes all main CI jobs. The subsequent borrowed-FFI
observation/router-owned-send fix is merged here from `ef9f605c`; that head passes
all five production platforms (170 cases, zero skips), audited source/log/ABI/
lifecycle evidence, a production-library ABI probe, WAMP profiles and package
dry run. Its main CI/Codecov checks remain pending. The combined branch initially
fails deployment-audit tests because the local disk is full, not because scripts
changed. Clearing only this worktree's rebuildable caches restores all 28 tests.
Fresh combined `bin/verify` passes at exit 0 with all 38 frozen code/test/config
inputs unchanged; source, native executables and prior evidence stay preserved.
Hosted byte-view acceptance remains pending. See [source and measured limits](../research/2026-10-14-flatbuffers-byte-vector-views.md).
The primary mutation checkout stays untouched.

Current follow-up (2026-10-14): complete the GitHub FlatBuffers milestone.
Branch `codex/finish-flatbuffers-milestone` reuses the managed worktree; the
primary mutation-runner checkout stays untouched. The released master remains
`73d840c9`. Its main CI now passes all 36 jobs, and all five production native
consumers pass 170 cases with zero skips. Issue #104 is closed after auditing
its public examples, generic external-owner contract, ObjectBox boundary,
seven hosted packages and linked release evidence. Issue #102 also closes on
released-source CI: the downloaded GuardMalloc report verifies 87 cases and
263 committed inputs, plus its separately recorded generated lock. The milestone description
now reflects merged and published work.

Fresh `bin/test-fast` initially fails on two absolute local paths in the
unpublished beta.8 documentation checkpoint. Normalizing those references
reproduces and repairs the policy failure; the replacement fast run passes.
The independent peer moves to cbor2 5.9.0, the first patched release for
GHSA-3c37-wwvx-h642. Fresh interop passes 33 upstream and 42 extended fixtures,
both encoding directions and all 25 public message types; the negotiated
RawSocket/WebSocket live peer also passes.

A live extraction-counter test then reproduces an existing observation gap:
Tokio-Rustls's public client/server reads bypass the instrumented internal
`Stream::poll_read`. Four source hooks now observe both public initial and
batched copies. Exact tests fail first at zero instead of three bytes and
pass after the repair, including borrowed-pointer preservation and EOF.
An additive optional scalar C API exposes this partial counter to both Dart
runtimes and client/router benchmark breakdowns. The old 48-byte Rustls ABI
is unchanged; the published beta.8 library correctly returns null for the
new optional metric. Complete dependency TLS/SDK/crypto totals remain unknown. On 2026-10-14
the user explicitly selects the standard Dart SDK scope: prove Connectanum
buffer boundaries and label unmeasured dependency internals. The follow-up
uses a new versioned scope marker, validates owned totals against their
client/router breakdowns, and permits only active, precisely labelled TLS/SDK
masking exclusions. Missing owned counters, E2EE/transcode gaps and all numeric
performance/resource budgets remain blockers. See [approved contract](../research/2026-10-14-standard-sdk-copy-scope.md).
Resulting-source `bin/verify` passes at exit 0; all six scope code/test/policy
inputs match their frozen hashes. The 32 comparison and 66 owned-counter cases
pass, including forged totals and malformed evidence. Bounded Qwen test planning
and review complete; the heavyweight GLM judge times out, so the contract is
also checked manually against the actual transport/source boundaries. PR #129
contains the measurement repairs and this approved scope update. At preceding
head `7965857f`, all five production platforms pass 170 cases with zero skips;
downloaded profile logs, ABI/lifecycle guards and source hashes are audited.
WAMP profile gates, binding, GuardMalloc, fast checks and package dry run pass.
New-head hosted acceptance remains pending; no parity is established.
The first full run reproduces the strengthened GC probe failure: actual
collections produce paired category-GC collection scopes, but the old parser
reports zero. Actual VM evidence also reproduces duplicated notifications and heap
statistics for isolates sharing one group. The final collector reads native
cumulative collection/time counters and profiles allocation once per shared
heap, while retaining every isolate for lifecycle validation. Missing, malformed
or rewound counters remain unavailable. All 35 focused forced-GC, heap/delta and
live-worker cases pass. The first timeline-reconciliation experiment fails its
stronger stream check and is retained as diagnostic evidence.
See [GC source and scope](../research/2026-10-14-dart-gc-metrics.md).
Final canonical `bin/verify` passes at exit 0, including Rust, VM/native,
consumers and Chrome/Dart2Wasm (4,751 core, 2,829 client; 20 declared native-only
skips). All 22 recorded changed code/test inputs still match their frozen hashes.
The completed local review identifies a missing-profiling-metadata fallback;
it now leaves allocation/GC unavailable, and a real VM probe verifies that
behavior. Other speculative review findings are checked against the actual SDK
snapshot and stable-isolate tests. Hosted new-source acceptance is pending.
A byte-vector construction prototype is prepared but its timed run is blocked
by an active native-mutation resource lease; that lease and primary work stay
untouched.
See [scope and evidence](../research/2026-10-14-tokio-rustls-public-copy-metrics.md).

PR #129 coverage follow-up: the `fc808e92` VM coverage job passes, but
Codecov patch coverage is 92.70% against 93.91%, with ten changed lines missed.
The existing isolated transport ABI probe now exports real client/router hits
through the canonical child-coverage directory. Its scalar/legacy ABI checks
stay isolated from shared counters; collection does not pause the current
isolate, and exclusive report creation prevents overwriting evidence. The
coverage-enabled probe passes and records seven previously missed router
lines. The normal probe plus collector regression suite passes 42 cases, and
analysis is clean. Qwen review reports no confirmed issue; its speculative
partial-write concern is covered by the existing exclusive writer tests. Full
resulting-source verification prints successful summaries for every suite,
including Chrome/Dart2Wasm. Its zsh wrapper then fails when assigning the
read-only `status` variable, so no clean canonical exit is recorded. The next
run uses a dedicated exit-code variable and an explicit Bash wrapper. Coverage
floors and milestone criteria remain unchanged; hosted acceptance is pending.
A subsequent source audit identifies another actual owned copy: the router's
borrowed send copies into Dart's native staging allocation, then
`ct_send_message` copies that input again in Rust. The existing total covers
only the first copy. Add direct Rust observation and conservative optional-ABI
fallback, then use the established owned-send API to avoid that second copy
when supported. Fresh pre-change `bin/test-fast` passes at exit 0. The Rust
regression fails first in both actual borrowed-send and file-wrapper cases,
then all five cases pass after eight source hooks. Both Dart runtimes expose
the additive nullable scalar. Missing observation prevents complete native
client/router coverage; staging and Rust bytes are retained separately. The
real ABI/ownership probe and scoped merger pass 69 cases, including three
borrowed bytes versus zero Rust copies on owned router rejection. All 32
comparison tests pass. Resulting-source `bin/verify` now passes with a clean
exit 0, including Rust, VM/native, consumers and Chrome/Dart2Wasm (4,751 core,
2,829 client; 20 declared native-only skips). All 13 changed code/test hashes
match their frozen inputs. The older production library passes the ABI probe,
leaving the absent scalar and its deltas null. GuardMalloc passes all 87 cases;
all 266 source/lock hashes, group logs and the executable are independently
verified. Bounded GLM review completes without a confirmed finding; the broader
Qwen review times out. The measurement PR remains ready for review with new-head
hosted acceptance pending. E2EE/transcode pipeline gaps, parity and milestone
closure remain open. See the FFI research note for source boundaries and the
verified disposition of the local ownership advice.

Current follow-up (2026-10-10): synchronized beta.8 publication is complete.
The user merges PR #107 through protected master at `73d840c9`; its tree exactly
matches tested release head `b382b21c`. All eight release/package tags point to
that merge. [Native release v3.0.0-beta.8](https://github.com/konsultaner/connectanum-dart/releases/tag/v3.0.0-beta.8)
is published as a prerelease with 30 assets across five platforms.
[Native workflow 38033155639](https://github.com/konsultaner/connectanum-dart/actions/runs/38033155639)
passes all five builds, production consumers, signing and publication. Downloaded
reports independently verify 170 profile cases with zero skips, exact source,
log hashes, lifecycle and 48-byte ABI guards. All five published manifests match
`73d840c9`; fresh client/router installation passes and both binary hashes match
the production proof. Intel macOS initially queues, then passes on a runner.
All seven `3.0.0-beta.8` packages are confirmed through the public pub.dev API:
[core](https://pub.dev/packages/connectanum_core/versions/3.0.0-beta.8),
[client](https://pub.dev/packages/connectanum_client/versions/3.0.0-beta.8),
[MCP](https://pub.dev/packages/connectanum_mcp/versions/3.0.0-beta.8),
[router](https://pub.dev/packages/connectanum_router/versions/3.0.0-beta.8),
[facade](https://pub.dev/packages/connectanum/versions/3.0.0-beta.8),
[auth server](https://pub.dev/packages/connectanum_auth_server/versions/3.0.0-beta.8)
and [bench](https://pub.dev/packages/connectanum_bench/versions/3.0.0-beta.8).
All seven tag-triggered publication workflows pass in dependency order; hosted
constraints remain synchronized. An isolated consumer outside the repository
uses a fresh public cache, all seven exact hosted versions and matching archive
hashes. Its default hooks download the verified production library. Dart macOS
bundling changes the install name/ad hoc signature, while all 14 code/data
sections remain identical. The public native FlatBuffers example passes with
116 frame bytes, three segments, zero application-input copies and zero
control-growth copies. The initial benchmark index is stale; refreshing after
public-index propagation resolves the clean install without changing versions.
Evidence is retained under `out/beta8-publish-evidence/`; the standalone
consumer uses an isolated scratch directory outside the repository.
Local full `bin/verify` passes on identical tree `b382b21c`; all 36 main jobs,
seven strict archives and WampApp artifacts also pass there. Post-merge
[CI 38032968401](https://github.com/konsultaner/connectanum-dart/actions/runs/38032968401)
passes all 36 jobs, including VM coverage and both mutation gates. WAMP profile gates and kTLS validation pass on `73d840c9`.
The closed release PR's separate Codecov comparison loses three hits in
unchanged router WebSocket polling and MCP timer-identity branches (patch 100%;
project 93.90% versus 93.91%). Actual LCOV differences are retained; no coverage
floor is relaxed. Local companion triage is blocked by an active native mutation
resource lease. The primary checkout and earlier local evidence stay preserved.
This documentation checkpoint remains local on `codex/publish-3.0.0-beta.8`;
published source/tags stay at `73d840c9`, avoiding another unchanged CI run.
Issues #100–#104 and performance/copy acceptance remain open; no ObjectBox
adapter or stable-release claim is included in this beta checkpoint.

Current follow-up (2026-10-09): integrate merged CI into the beta.8 release.
The user merges PR #108 at master `759d3d4c`. Release PR #107 then has one
execution-plan documentation conflict. Fresh pre-merge `bin/test-fast` passes
at exit 0 on `85b92916`; baseline evidence is retained under
`out/ci-release-resync-evidence/`. The merge preserves both the release checklist
and completed CI acceptance evidence. Package/runtime/crate changes remain the
approved beta.8 graph; no package is published yet. Canonical `bin/verify`,
strict package archives and replacement hosted acceptance are pending.
Required review and protected-master promotion remain mandatory before native
assets and dependency-ordered pub.dev tags are published. Companion summary
was initially resource-lease blocked; review then times out on Ollama and cannot
reach GLM. Manual version/tag review passes; the primary checkout is preserved.


Nonce-freshness CI repair (2026-10-15): four repeated-plaintext/key checks cover
both ciphers and both plaintext profiles. The exact skipped-initialization CI
mutant fails first; all 168 focused E2EE cases and sixteen Chrome/Dart2Wasm
cases pass. The unchanged complete 315-mutant target passes at 95.3125% with
zero errors/timeouts and the original 95% floor. An initial test-setup attempt
constructs providers during discovery and produces loader errors; its failed
run is retained. The final tests construct providers inside their test cases.
Bounded Qwen review completes without a confirmed issue. All other preceding
head hosted jobs pass; resulting-head CI and fresh full verification are pending.
No performance or complete copy-acceptance claim is added.

## Coordinated beta.8 release checkpoint (2026-10-08)

The user requests another version bump and pub.dev deployment after PR #105
is merged at master `0e585405`. This supersedes the earlier publication hold.
All seven beta.7 packages are live; beta.8 is available for the next synchronized
Dart/native graph. Preserve all unfinished milestone and performance criteria.

- [x] Start `codex/release-3.0.0-beta.8` from merged master, preserving the primary
  mutation-runner checkout and the feature branch's local evidence commit.
- [x] Run fresh baseline `bin/test-fast` at exit 0 before version edits.
- [x] Advance seven package manifests/constraints, three crate versions,
  runtime identities, hook fixtures, changelogs and current installation docs.
- [x] Pass release-planner/tag/hook checks, seven zero-warning strict package
  dry runs, manual review and full `bin/verify`.
- [x] Promote the release PR through protected master with required review and
  passing hosted checks; do not bypass branch protection.
- [x] Publish `v3.0.0-beta.8` native assets and pass production consumers on all
  five supported build platforms, then validate fresh native installation.
- [x] Publish all seven package tags in dependency order, confirm exact hosted
  versions, and validate an isolated hosted-package consumer.

No ObjectBox adapter, stable-release claim, performance parity acceptance or
milestone closure is included in this beta checkpoint.

All 37 planner/tag/note/intent tests and seven exact tag validators pass.
The initial uncommitted-tree archive attempt stops on pub's dirty-file warning;
the clean `7ca882c6` candidate passes all seven strict archives with zero warnings.
Full `bin/verify` passes at exit 0, including Rust, VM/native, consumers, router
and Chrome/Dart2Wasm (4,751 core and 2,829 client; 20 native-only skips).
Companion review is attempted but blocked by the active native mutation resource
lease; manual review is complete and the campaign remains untouched.
[PR #107](https://github.com/konsultaner/connectanum-dart/pull/107) is ready for
review. Hosted checks pass on original head `7ca882c6`; required review
and protected-master promotion remain pending. The
[five-platform native dry run](https://github.com/konsultaner/connectanum-dart/actions/runs/37799443111)
passes its builds, consumers and release preview with publication skipped.
Downloaded reports independently verify the exact `7ca882c6` commit, all 170
profile cases with zero skips, log hashes, lifecycle and 48-byte ABI guards.
These production-profile measurements belong to original head `7ca882c6`;
they do not claim verification of the new integration commit.

Current follow-up (2026-10-09): CI repair for [PR #108](https://github.com/konsultaner/connectanum-dart/pull/108).
Branch `codex/ci-execution-sharing` starts from merged master `0e585405`;
the beta.8 release branch/head remains preserved separately. The first run at
`163699a0` fails before tests because setup-dart registers its matcher from the
parent composite path. The explicit matcher opt-out at `15bbac7f` fixes shared
setup; hosted Fast Checks, package dry runs, browser coverage, shared native
build and completed mutation gates pass. Fresh local `bin/test-fast` and
canonical `bin/verify` also pass (Rust, VM, consumers, Chrome/Dart2Wasm; 4,751
core, 2,829 client, 20 unchanged native-only skips).

The replacement [run 37850365570](https://github.com/konsultaner/connectanum-dart/actions/runs/37850365570)
then exposes missing native benchmark coverage: its process intentionally
clears `CONNECTANUM_NATIVE_LIB`, while the shared library only exists under
`out/ci-native`. One ABI test fails and 230 native cases skip. Prepare now
installs and verifies the same artifact at the conventional ffi-test location,
using atomic replacement; dependency, source, toolchain, profile and digest
checks remain enforced. The real Dart discovery regression fails before the
fix and passes after it. All 14 CI execution contracts pass; the actual native
copy ABI case passes with the override unset and no skips. Local CI coverage
executes all 1,642 benchmark cases with zero skips. Its macOS benchmark gate
measures 97.203% against the 98% Linux CI floor: the exact 35-line difference
from the passing Linux report is confined to Linux-only CPU/RSS metrics.
No floor or platform guard is changed. Canonical `bin/verify` with shared
artifact reuse passes at exit 0 (Rust, VM, consumers, Chrome/Dart2Wasm;
4,751 core, 2,829 client, 20 unchanged native-only browser skips).
Replacement hosted Linux acceptance passes on source head `3efbba99`:
all 1,642 benchmark cases pass, benchmark coverage is 98.329%, handwritten
VM coverage is 93.916%, and library/packaging policies report no findings.

At source head `3efbba99`, all six hosted MCP shards and independently
regenerated aggregation complete all 1,101 mutants; the uploaded outcomes
exactly match the fresh inventory, both baselines pass, and the assertion score
is 97.37783075089392%, above the original 95% gate. The latest
[main run 37855378339](https://github.com/konsultaner/connectanum-dart/actions/runs/37855378339)
passes all 36 jobs, including Linux coverage and required Full Verify. All 47
PR checks pass on source head `3efbba99`. The user merges PR #108 into master
at `759d3d4c` on 2026-10-09. Package dry runs and every WampApp platform artifact pass on
the same source head. The separate macOS
artifact job initially cannot acquire a runner; its targeted retry passes on
unchanged artifact head `163699a0` (run 37810537255, attempt 2). Inventories,
coverage scopes/floors and deadlines stay unchanged. Local companion attempts
remain blocked by the active native mutation resource lease. Scope and proof:
[CI plan](../research/2026-10-08-ci-execution-sharing.md).

CI acceptance evidence was retained locally while PR #108 was under review;
it is now recorded here after that PR is merged. The tested source head stays
at `3efbba99`. The beta.8 release follows through PR #107.


Current follow-up (2026-10-08): PR #105 Codecov project regression.
At `7b530d58`, hosted test/mutation, package and native-artifact checks pass;
Codecov project coverage fails at 88.693% against master's 93.896%.
Its report includes two generated WAMP FlatBuffers files already measured
separately by the local coverage checker. Codecov now uses the same exact
exclusions; handwritten runtime/serializer code and thresholds remain unchanged.
The coverage runner also retains eight previously omitted complete suites,
including native owned segments, FlatBuffers frames/profiles, copy metrics and
router forwarding variants. Actual added-suite runs pass and contribute 171
handwritten VM line hits; the merged hosted-report estimate is 93.913%.
Three fail-first regression methods reproduce the omissions and scope mismatch.
Fresh baseline `bin/test-fast` and candidate `bin/verify` pass at exit 0,
including Rust/VM/consumer/router checks and both browser suites (4,751 core,
2,829 client; 20 unchanged native-only skips). All 110 coverage-policy/runner
methods pass. Codecov's public validator accepts the exact generated-file scope.
The functional fix is published as `7bf7dd4f`, followed by `ec675d59`.
All 85 PR checks pass: Codecov project is 93.90% (+0.01 percentage points
versus master), and Codecov patch, Full Verify and mutation checks pass.
The verified PR is marked ready and merged at `0e585405`.
Hosted acceptance: [PR #105 checks](https://github.com/konsultaner/connectanum-dart/pull/105/checks).
Evidence: [coverage scope/proof](../research/2026-10-08-codecov-project-coverage.md).

Current follow-up (2026-10-07): coverage runtime ownership isolation.
The normal runner isolates remote-auth integration; the coverage runner omitted
that separation. A focused combined actual run aborts at exit 134 with runtime
already started and a native callback from the wrong isolate. Four MCP and
thirteen remote-auth cases pass when separated. Coverage now retains both full
suites in sequential processes with separate raw reports; formatting continues
to merge the whole raw root. Two fail-first runner methods and failure controls
pass; all 85 script regressions pass. Bounded review identifies no concrete
finding. Candidate canonical fast/full checks pass at exit 0, including both
browser suites with the same 20 native-only skips. Hosted acceptance is pending.
The previous Linux MCP subscription assertion's specific cause remains unknown.
The `df1a9ad5` native run provides verified 34-case reports on all five platforms
(170 total, no skips), including Windows lifecycle and 48-byte ABI guards. Its
package dry run passes. The overall native run fails afterward on macOS Intel
attestation persistence; two rerun requests return HTTP 500. Sampled hosted PR
jobs fail without acquiring a runner (five attempts, no steps). These external
failures remain recorded; gates are not skipped.
Evidence: [coverage scope/proof](../research/2026-10-07-coverage-runtime-isolation.md).

Current follow-up (2026-10-07): Windows native runtime admission.
Published `4a7ac185` native run 37622772557 passes four Linux/macOS platforms;
Windows now launches tests and passes the 48-byte ABI guard, then rejects
runtime startup because its platform selector chooses the unsupported stub.
Windows now uses the existing shared supported handle. Other hosts retain
explicit rejection. The packaged verifier exercises actual start, duplicate
start, shutdown and restart before running all 34 profiles. All 20 verifier
methods and local constructor/lifecycle/unsupported controls pass. A fresh
macOS production candidate passes the runtime audit, ABI guard and all 34
public profiles. Bounded review is checked against source; GLM identifies no
definite defect. Candidate canonical fast/full checks pass at exit 0. Hosted
Windows acceptance remains pending. The preceding `4a7ac185` PR VM coverage
job 112825887695 fails one MCP last-owner cleanup assertion (expected empty,
observed `[1]`); source-level cause and repair remain pending and are the next
CI priority. Both remote masters remain at integrated `3bac4cf5`; no new merge
is needed. The five-platform gate and all benchmark budgets are unchanged.
Evidence: [runtime scope and proof](../research/2026-10-07-windows-runtime-admission.md).

Current follow-up (2026-10-07): Windows packaged consumer launcher.
Verified source checkpoint `736b6454` contains the Tokio-Rustls observer,
fast ownership-oracle selection fix and packaged 48-byte ABI guard.
Published `2bfff943` native dry run 37614965856 passes four platforms but
Windows hook compilation tries `dart.EXE.exe` before any profile tests.
Two execution regressions fail first. Windows `.EXE`/`.exe` and shell wrappers
now normalize to lowercase `.exe` and require the executable file.
All 17 verifier methods pass; POSIX paths, SDK and profile requirements remain
unchanged. Bounded local review completes without a definite error.
The corrected macOS production consumer passes the 48-byte ABI guard and all
34 public profile cases. Final `bin/test-fast` and `bin/verify` pass at exit 0,
including Rust/VM/public consumers and both browser suites (20 unchanged
native-only skips). Hosted Windows runtime acceptance remains pending. Evidence:
[Windows launcher scope and proof](../research/2026-10-07-windows-consumer-launcher.md).

Current follow-up (2026-10-07): first full hosted primary result.
Frozen `a5c6aaf9` completes all 1,440 rows (48 cases, three codecs, three warmup
and seven measured passes); driver exit0 and cleanup, policy/executable hashes
and exact local comparison replay verify. The comparator fails with 2,129
findings, including 276 parity failures: throughput, latency, CPU and allocation
gates each fail in all 48 cases; RSS fails in 36. Missing copy fields, zero GC
baselines and five windows below 10,000ms remain blockers. A forced-GC probe
emits real `GC` category B/E collection spans while the existing collector reports
zero; a positive regression fails. No collector repair is included yet.
Every original supplement, normative copy field and budget remains mandatory.
Evidence: [hosted result and GC repro](../research/2026-10-07-hosted-primary-result.md).

Current follow-up (2026-10-07): actual Tokio-Rustls plaintext extraction.
The workspace pins published Tokio-Rustls 0.26.6, both original licenses,
its unchanged published lockfile and four restored upstream test fixtures.
The source hook counts only successful `ReadBuf::put_slice()` bytes;
borrowed views and consumption preserve the storage pointer and count zero.
Two fail-first copy cases and a pending/malformed-input control pass after
instrumentation. Both macOS/Linux pass all 14 enabled and 11 disabled cases;
Linux matches all 3,017 frozen inputs and passes a real TLS connection test.
Both candidate production bundles pass 34 public profile cases and nine exact
license/notice/manifest checks each. The source gate passes all twelve controls.
Initial companion attempts are lease-blocked; later test advice completes.
The first canonical fast check loads the just-packaged production library and
fails three owner-oracle cases because test symbols are intentionally absent.
The fast client suite now explicitly prepares `ffi-test`, matching full
verification. Three execution controls pass on macOS/Linux after reproducing
both production-selection failures; a failed test build stops verification.
A larger review reaches its token limit; a bounded retry completes without an
actionable finding. Its speculative cautions are disproved by initialization,
feature selection and execution tests. Canonical fast verification passes.
Full verification terminates at exit 255 on Dart kernel-copy OS error 28:
the host disk is full. Rebuildable feature-worktree compiler/debug caches are
removed, restoring 21 GiB free while retaining source, release libraries and
proof artifacts. The production-consumer audit also exposes missing coverage
of the new 48-byte Rustls snapshot. It now requires the export and checks its
null status, writes and surrounding guards in a fresh process. All 14 verifier
methods pass, including six new failure controls; the macOS packaged library
passes the ABI guard and all 34 profile cases. A bounded GLM review completes
without a definite error. Docker's API is unresponsive after the disk event;
its original Linux direct-probe session remains live and is not restarted.
Both published cde CI runs are green. Final canonical `bin/test-fast` and
`bin/verify` pass at exit 0 after cache cleanup, including Rust/VM/consumers,
1,642 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser
cases with 20 unchanged native-only skips. Published `2bfff943` native dry
run 37614965856 passes all 34 public cases on four Linux/macOS platforms;
Windows fails before testing because hooks launch `dart.EXE.exe`. Two
execution controls reproduce uppercase suffix propagation and omitted
executable validation; a narrow launcher correction is the next CI priority.
This source-only Tokio observation does not extend the Rustls ABI or close
complete-copy/performance criteria. Evidence:
[extraction scope and proof](../research/2026-10-07-tokio-rustls-extraction.md).

Current follow-up (2026-10-07): optional Rustls source metrics bridge.
Twelve fail-first cases reproduce omitted partial-counter metadata on both
transports. A separate 48-byte C snapshot exposes all six actual Rustls source
counters; legacy 24-byte and V2 40-byte transport snapshots remain unchanged.
Client/router optional lookup and nullable deltas retain null with old libraries.
Benchmark client/router breakdowns retain the named partial observations while
complete TLS/transport gates remain unchanged. MacOS passes the native layout/
null/tail guard, 56 merge/delta cases and old/new ABI probes. Linux matches all
2,996 final frozen source/lock inputs and passes its native guard, 56 merge/delta
cases and both new/published-old ABI probes. A separate fail-first negative
counter test now preserves unmeasured metadata for invalid values. Completed companion
test advice is checked; final review is blocked by the active native-mutation
resource lease. The candidate fast check exposes a local SDK path in the published artifact
proof. Command paths are now normalized to `dart`, retaining raw report hashes;
the public-reference gate passes. Fresh canonical `bin/test-fast` and full
`bin/verify` pass at exit 0: Rust/VM/consumers, 1,642 benchmark, 4,958 router,
4,751 core browser and 2,829 client browser cases with 20 unchanged native-only
skips. Crate formatting and the final Linux native/new-ABI replay pass with
all 2,996 formatted inputs matched. Narrowed review remains lease-blocked. Both cde
hosted CI runs pass all completed jobs and retain only their MCP mutation jobs;
the frozen full primary remains independent. No complete-copy, parity or
milestone acceptance follows.

Current follow-up (2026-10-07): packaged production runtime consumers.
Source checkpoint `0ce3c364` commits the payload observer after canonical fast
and full verification passed. The new Native Artifacts gate verifies the
archive checksum, detached/embedded source manifest and production ABI/oracle
inventory, then runs all 34 public profile cases in three separate Dart
processes against the extracted library. JSON evidence rejects skips, missing
cases, errors and unfinished starts even with a success summary. Per-platform
proofs and logs upload on failure. Nine failure controls pass on macOS/Linux, and Actionlint passes. The actual
gate passes all 34 cases against each frozen published `cde9fbed` arm64 bundle;
completed companion advice is checked against source and actual timeout
behavior. Canonical candidate `bin/test-fast` and full verification pass at exit 0
together with the metrics bridge. Hosted runtime proof for all five
resulting-source platforms remains pending. No release, whole-copy or
performance acceptance follows.

Current follow-up (2026-10-07): payload copy observations.
Published source `cde9fbed` passes canonical fast/full checks. Push CI fast
checks now pass; remaining resulting-source jobs are live. Native dry run
37588514671 passes all five builds; package dry run 37588518168 passes.
All 15 pinned attestations, 25 exact notices/manifests (including Windows),
30 preview assets and rendered notes verify. Both hosted arm64 production
libraries pass 34 profile cases; other platforms have build/provenance evidence.
The independent full primary 37582544124 remains live on frozen `a5c6aaf9`.
Four new fail-first tests expose omitted 7/8/10/9-byte payload copy observations.
Hooks cover owned clones, borrowed ownership conversion, bounded U8/U16 reads
and content/certificate encodes while preserving borrowed reads and owned
moves. A targeted U24 test confirms inner clone delegation counts once.
All 243/232 macOS and 244/233 Linux enabled/disabled cases pass; both real TLS
checks pass with all 860 frozen Linux inputs matched. The source gate and five
failure controls pass. Initial companion findings are disproved by source and the targeted regression.
The follow-up is initially blocked by the native-mutation resource lease; its
post-verification retry completes and confirms the clone/borrow semantics. Canonical candidate `bin/test-fast` and full `bin/verify` pass at exit 0:
Rust/VM/consumers, 1,616 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with 20 unchanged native-only skips. No whole TLS or
parity acceptance follows; #100–#104 remain open. Evidence:
[scoped payload proof](../research/2026-10-07-rustls-payload-copies-proof.json).

Next required work after this source verification:
1. Keep resulting-source CI clean and verify public profile runtime consumers
   on the remaining Linux x64, macOS Intel and Windows x64 artifact runners.
   Their current build/provenance evidence does not exercise runtime behavior.
2. Expose named partial source observations through an optional C/Dart metrics
   path so benchmark reports can use actual source counters; preserve old ABI
   and unavailable-counter fallback. Complete TLS fields remain unknown until
   their entire declared scope is measured.
3. Observe Tokio-Rustls plaintext extraction, remaining Rustls/SDK growth,
   record/crypto and mixed-serializer boundaries without replacing the existing
   buffered TLS engine or substituting accepted byte volume for copy counts.
4. Finish the full primary and original supplemental campaigns with unchanged
   parity/resource/copy gates, then audit every original #100–#104 criterion.

Current follow-up (2026-10-07): deframer and record copy observations.
Four new fail-first tests expose omitted deframer appends/moves and record
clones/appends. All 238 enabled and 232 disabled upstream library cases pass;
the source gate and five failure controls pass. Named counters remain partial.
A live receive assertion exposes that buffered Rustls reads directly into
its deframer, bypassing `extend`; accepted input is not counted as an assumed
copy. That invalid new assertion is removed, preserving existing coverage.
The live record-append check passes on macOS and Linux. Linux passes 239 enabled
and 233 disabled cases with all 860 frozen source/lock inputs matched.
Canonical `bin/test-fast` and full `bin/verify` pass at exit 0: Rust/VM/consumers,
1,616 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases,
with 20 unchanged native-only skips.
Growth, remaining record/crypto and Tokio-Rustls/SDK extraction still prevent
whole-copy acceptance. The published `a5c6aaf9` full primary remains live;
native and package dry runs finish successfully. Both resulting-source CI fast
jobs fail a campaign unit fixture's missing generated Cargo lockfile. An
isolated temporary source root reproduces it; explicit synthetic locks and
hash/archive assertions pass all 15 campaign cases without changing policy.
All 15 a5 artifact attestations and 30 preview assets verify. Windows converts
the bundled notice and source manifest to CRLF; their new `-text` attributes
prevent that byte drift; all 843 source/fixture/notice/manifest filter controls
pass. The unchanged release-note renderer reproduces the
preview with the exact workflow reference. All 34 production profile cases
pass against both hosted macOS arm64 and Linux arm64 libraries; other three
platforms have build/provenance evidence. No release or parity claim follows.
#100–#104 remain open.

Current follow-up (2026-10-07): source-observed Rustls copies.
Rustls 0.23.45 is pinned with original licenses and an 841-file digest manifest,
including exact upstream test fixtures. Two fail-first cases expose omitted
actual chunk/queue copies; observations make all 234 library cases
pass. A feature-disabled build and real native TLS outbound observation pass.
The live receive probe exposes a separate Tokio-Rustls copy site; total TLS
coverage remains unknown. The dependency lock changes only Rustls source at the
same version. Five source-integrity failure controls and fresh `bin/test-fast` pass.
All 841 source blobs remain exact with Windows newline conversion enabled.
Native bundle packaging retains Rustls licenses and source digests. Final
`bin/verify` fails the unchanged FastCGI cumulative stdout-limit fixture
with a peer reset; its isolated unchanged repro and five unchanged repeats
pass. Fresh full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,616
benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases,
with 20 unchanged native-only skips. The narrowed GLM judgment completes
with no confirmed native defect. Real macOS arm64 packaging passes: all five
Rustls notice/manifest files match and the library excludes test oracles.
Clean source commit `3b251789` packaging then matches the verified library,
notices and source manifest. All 34 production profile cases pass in separate
processes; an initial combined probe finds an already-started shared runtime.
This scoped macOS check does not provide multi-platform release acceptance. #100–#104 and all gates remain
open. Research: [Rustls copy observer](../research/2026-10-07-rustls-copy-observer.md).

Current follow-up (2026-10-07): native prefetched input copies.
Two real TCP-pair regressions expose uncounted staging/replay copies; an
intermediate observation identifies the duplicate unread-buffer copy, now
removed. The old 24-byte snapshot remains unchanged beside a new optional
40-byte ABI. Both Dart runtimes retain null for absent counters. The 30 merge,
39 comparator/campaign and eight live worker cases pass; new test-library and
old production-library snapshot tests pass. Complete transport reports require the new input
counter evidence. Initial fast-check warnings and an omitted direct test
dependency are corrected; Linux locked-snapshot setup was repaired without
relaxing dependency locking. Final Linux arm64 native/FFI, 31 Dart and eight
live worker cases pass with all 18 source/lock hashes matched. Fresh
`bin/test-fast` passes at exit 0, including all 1,616 benchmark cases.
Full verify first exposes a test-only stale-debug library selection; the exact
repro fails before and passes after using the existing canonical test resolver.
Final full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,616 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases, with the same
20 native-only skips. Evidence: `/tmp/connectanum-native-io-copy-verify-final.{log,exit}`.
Companion debug/review/test advice is verified; no accepted source defect remains.
Preceding `0ec8df06` PR run 37565054707 completes all 41 jobs successfully.
Push run 37565051795 also completes all 41 jobs successfully. The four verified
commits through `a5c6aaf9` are now published to both remotes. Resulting-source
CI runs 37582506753 (push) and 37582511052 (PR), full primary campaign
37582544124, native dry run 37582546475 and package dry run 37582549630
are dispatched; acceptance remains pending. Resulting-head
hosted acceptance and performance parity remain pending; no issue closure follows. Research: [prefetched input copies](../research/2026-10-07-native-prefetched-input-copies.md).

Current follow-up (2026-10-07): hosted full FlatBuffers campaign.
The registered profile workflow gains an explicit manual primary choice with
all 1,440 rows and unchanged gates. Production release binaries, locks and raw
failure evidence are archived. The 38 campaign/comparator tests and verified
Actionlint pass; four synthetic summary fixtures preserve failure status.
Final companion review is blocked by the active native mutation resource lease.
Baseline `bin/test-fast` and full `bin/verify` pass at exit 0, including
1,609 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser
cases with the unchanged 20 native-only skips. Evidence:
`/tmp/connectanum-hosted-primary-verify.{log,exit}`. Hosted execution remains
pending; no performance acceptance follows. Research: [hosted full campaign](../research/2026-10-07-hosted-flatbuffers-primary-campaign.md).

Current follow-up (2026-10-07): observed native PPT submission metrics.
Thirty-six fail-first cases expose zero-copy values inferred only from settings
and permissive observation parsing. Each sample now requires its own observed
native frame submission and complete encoded-owner reuse. Missing/fallback/
repeated/mismatched observations remain unmeasured. All 121 focused, 32 native
and 20 live benchmark cases pass on macOS/Linux, with matched Linux inputs.
Tracking is opt-in; no ownership/ABI/fallback or acceptance gate changes.
Baseline fast and full `bin/verify` pass at exit zero, including 1,609 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases with 20 unchanged
native-only skips. Evidence: `/tmp/connectanum-observed-owned-copy-verify.{log,exit}`.
Resulting-head hosted verification remains pending. Final local review is blocked by
the active native mutation resource lease; direct review and focused checks
complete. Research: [observed submissions](../research/2026-10-07-observed-native-ppt-copy-boundary.md).

Current follow-up (2026-10-07): measured RawSocket input normalization.
Twenty-seven fail-first assertions reproduce partial-input retries and omitted
header accounting. Full arrays and validated native ranges retain their storage;
other inputs make one measured copy before queueing. All 81 socket/metrics cases
pass on macOS and Linux arm64, and the exact Linux diagnostic CI step passes.
Baseline fast and bounded GLM review pass. First verify fails an unchanged
FastCGI closure fixture; isolated repro and five unchanged repeats pass. Fresh
full `bin/verify` passes at exit 0: Rust/VM/consumers, 1,563 benchmark,
4,958 router, 4,751 core browser and 2,829 client browser cases, with 20
unchanged native-only skips. No assertions or timeouts changed. Evidence:
`/tmp/connectanum-socket-normalization-final-verify.{log,exit}`. SDK/TLS
and performance acceptance remain open. Research: [input normalization](../research/2026-10-07-rawsocket-input-normalization.md).

Current primary campaign (2026-10-07): the unchanged full matrix failed at
124 partial warm-up rows. An overlapping diagnostic Dart job triggered the
existing guard, which stopped the driver process group at 01:25:48 UTC. The
run provides no performance acceptance; all gates and #100–#104 remain open.
Finish builds and tests before starting a new frozen campaign. Research:
[failed primary campaign](../research/2026-10-07-primary-flatbuffers-campaign.md).

Current follow-up (2026-10-07): bounded native socket views. Twelve fail-first
transport cases reproduce the SDK partial-view copy. Validated malloc-owned
ranges now retain their original allocation through bounded read-only aliases;
a Dart finalization token retains the source through the backing root. An
interim unread metadata field passed VM tests but failed a compiled lifetime
check; the repair passes all 83 focused tests on macOS and Linux arm64. Four
real 16 MiB backpressure cases pass in both VM and compiled AOT modes, retaining
original write addresses through collection and observing final native release.
The exact CI step and its missing-interposer controls pass. Baseline fast,
focused analysis and bounded review pass. Restarted `bin/verify` passes at exit 0:
Rust/VM/consumers, 1,563 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with the unchanged 20 native-only skips. Evidence:
`/tmp/connectanum-bounded-native-alias-token-verify.{log,exit}`. Resulting-head
hosted acceptance remains pending; no total-copy or parity acceptance follows. Research: [bounded native views](../research/2026-10-07-bounded-native-socket-views.md).

Current production checkpoint `8503f31c`: [Native Artifacts 37546766311](https://github.com/konsultaner/connectanum-dart/actions/runs/37546766311)
passes five builds and its signed dry-run preview. All fifteen pinned
attestations, thirty preview assets and rendered notes verify. Fresh source-pinned
Apple Silicon and Linux arm64 production consumers pass eight steps each,
including twenty provenance, ten segment, sixteen owned-PPT and 104 mixed-PPT
cases. Both libraries exclude test oracles; source archive and log hashes match.
The other platforms have build/provenance evidence only. No release or performance
acceptance follows; required current-head CI is live. Research: [production
checkpoint](../research/2026-10-07-native-production-checkpoint.md).

Current follow-up (2026-10-07): native external-buffer allocation provenance.
Six fail-first regressions show that matching bounds allowed a foreign anchor
to redirect a native read, including an incorrect SHA-256 digest. The resolver
now verifies backing-buffer equality and retains that buffer with its anchor.
The final 20-case suite passes without skips on macOS and Linux arm64, including
equal-content foreign-allocation controls and actual GC retention/collection.
The malloc finalizer and existing copying fallback are unchanged. Fresh quiet
`bin/verify` passes at exit 0, including Rust/VM/consumers, 1,563 benchmark,
4,958 router, 4,751 browser core and 2,829 browser client tests with the unchanged
20 native-only skips. Evidence: `/tmp/connectanum-external-provenance-verify.{log,exit}`.
No total-copy or performance acceptance follows. Both preceding `a9907161`
hosted CI runs now pass all 41 jobs: [push](https://github.com/konsultaner/connectanum-dart/actions/runs/37523093121)
and [PR](https://github.com/konsultaner/connectanum-dart/actions/runs/37523101879).
The publication hold is released; resulting-head hosted checks remain pending.
Master `3bac4cf5` was fetched from both remotes and is already integrated;
`git merge github/master` reports Already up to date. Research: [allocation
provenance](../research/2026-10-07-native-external-buffer-provenance.md).

Current diagnostic follow-up (2026-10-07): real Dart SDK backpressure.
The four 16 MiB full/read-only/partial/read-only-partial cases require genuine
EAGAIN, pending flush, positive writes after receiver resumption and exact
received/accepted bytes. Full views retain allocation identity; partial views
use SDK copies. The exact updated Linux CI step passes all three probes and its
absence control; source hashes match. Root analysis and the new tool's explicit
missing-interposer rejection pass. Fresh quiet `bin/verify` passes at exit 0,
including all 1,563 benchmark, 4,958 router, 4,751 core Chrome/Dart2Wasm and
2,829 client browser cases with 20 declared native-only skips. Evidence:
`/tmp/connectanum-sdk-backpressure-verify.{log,exit}`. Final sequential
`bin/test-fast` also passes at exit 0, including all 1,563 benchmark cases and
the unchanged readiness regression. Evidence:
`/tmp/connectanum-sdk-backpressure-final-fast.{log,exit}`. The preceding local
commit `d4d91317` passed both canonical commands and independent interop. Its push is held while preceding
`a9907161` CI's MCP mutation gates remain active. No total-copy, TLS or parity
acceptance follows from this pointer diagnostic. Research: [backpressure](../research/2026-10-07-dart-sdk-backpressure.md).

Current follow-up: Dart FlatBuffers fragments and one-copy small RawSocket frames.
The ordinary fragment API preserves encoded CBOR args/kwargs and opaque body
views through valid forward-offset vector layout. Normal serialization and the
wire schema are unchanged. Two public regressions fail before the writer; all
61 focused core cases pass across seven payload-bearing message families.
Three small-frame copy regressions fail before the shared transport repair;
all 43 RawSocket tests then pass, including six codec/size copy/identity cases.
The Linux developer probe now exercises real negotiated RawSocket PPT traffic,
and CI uploads it beside the SDK boundary probe. The source audit corrects the
forced short-write/EINTR boundary to the native SocketBase::Write loop; it does
not establish Dart-level EAGAIN resumption. Partial SDK views, total SDK/TLS/
crypto copies and the full strict parity campaign remain unfinished. Research:
[segmented Dart sending](../research/2026-10-06-dart-flatbuffers-segmented-send.md).
The final 36-case real Linux PPT pointer probe passes with exact source hashes;
Rust/Python readers accept contiguous and segmented output for all 25 messages.
The first canonical fast attempt failed the new-test inventory. All four
VM/browser inventories and their shared suite now include that test; all 80
workflow regressions pass with unchanged thresholds. The next fast attempt
failed the existing HELLO/GOODBYE rejection tests because controls used the
fragment writer. Controls and absent-vector messages now return null to retain
the normal serialize path. All 22 unchanged negotiation/rejection tests and
61 core fragment cases pass. The exact Linux CI step also passes both probes
and its missing-interposer control with final source hashes. A fresh canonical
fast run passes the changed paths and then hits the unchanged two-second
worker exit-before-READY deadline in the 1,563-case benchmark suite. Five
isolated repeats pass without code/deadline changes. The failed full fast log
is retained; timing sensitivity is not accepted as proof of a clean suite.
Fresh quiet `bin/verify` now passes at exit 0, including Rust, VM,
consumer/live checks, all 1,563 benchmark and 4,958 router cases, 4,751 core
Chrome/Dart2Wasm cases and 2,829 client browser cases (20 declared native-only
skips). The unchanged worker-readiness case passes in the complete benchmark
suite without deadline or assertion changes. The final independent interop run
also passes after the control fallback repair: 33 upstream fixtures, 42 extended
fixtures and all 25 public messages in contiguous and segmented Dart output.
Fresh sequential final `bin/test-fast` also passes at exit 0, including all
1,563 benchmark cases and the unchanged readiness regression. Evidence:
`/tmp/connectanum-flatbuffers-fragments-verify.{log,exit}`,
`/tmp/connectanum-flatbuffers-fragments-final-interop.{log,exit}` and
`/tmp/connectanum-flatbuffers-fragments-final-fast.{log,exit}`. Earlier failed
logs remain failed evidence. The focused local GLM selector review completed without a concrete
defect; two Qwen attempts reached output limits and are not review evidence.
At preceding published checkpoint `a9907161`, hosted push Full Verify and VM
Coverage pass; PR Full Verify also completes with no observed failure. Both
current CI runs remain live for the MCP mutation gate. Do not push another
checkpoint while those checks are still running. Preceding `b8096fd6` CI runs
were cancelled by that newer push, so their successful individual jobs do not
constitute complete hosted acceptance. This follow-up is committed locally as
`d4d91317`; publication awaits the existing hosted mutation run. Full performance
and remaining milestone acceptance stay open.

Preceding follow-up: native PPT body reuse with empty outer CBOR/MessagePack
keyword maps. The preceding implementation rejected these valid WAMP maps.
Fresh baseline fast checks pass; four new mixed-direction regressions fail
before the repair. All 26 segmented tests now pass, including 810 additional
body/header/direction/route combinations and native input parsing of every
tested header form. They verify body identity, empty-body producer lifetime,
metadata and final fan-out release. Malformed/nonempty maps and invalid
FlatBuffers mixed vectors retain fallback. Research:
[empty PPT keywords](../research/2026-10-06-native-empty-ppt-keywords.md).
GuardMalloc passes 87 observed ownership cases with all 141 native/schema
inputs unchanged. Final `bin/test-fast` passes. Fresh `bin/verify` passes at exit 0, including Rust, VM, consumer/live
checks, 1,563 benchmark, 4,958 router, 4,690 core Chrome/Dart2Wasm and 2,829
client browser cases (20 declared native-only skips). Final native input hashes
are unchanged. Evidence: `/tmp/connectanum-empty-ppt-kwargs-verify.{log,exit}`.
Local Qwen review completed; source and regression evidence disprove its
logic-inversion, indefinite-map and wrong-kind hypotheses.

Production checkpoint `b8096fd6` [Native Artifacts 37515940631](https://github.com/konsultaner/connectanum-dart/actions/runs/37515940631)
passes all five builds and its preview. Fifteen attestations, thirty assets,
archive/library checksums and exact rendered notes verify. Fresh commit-pinned
Apple Silicon and Linux arm64 production consumers each pass all four serializers,
native construction, ten segment cases, sixteen live owned-PPT cases and 104
public mixed-PPT cases. Their source archives match. Both production libraries
exclude test oracles, with an eighteen-symbol ffi-test positive control on macOS.
The other three platforms have build/provenance evidence only. This is runtime
correctness, not performance acceptance. Evidence:
`/tmp/connectanum-b8096fd6-platform-provenance.json`,
`/tmp/connectanum-b8096fd6-preview-proof.json`,
`/tmp/connectanum-b8096fd6-production-consumers-proof.json` and
`/tmp/connectanum-b8096fd6-linux-production-consumers-proof.json`.
Hosted FlatBuffers Binding and GuardMalloc pass in PR run 37515806715. The
RawSocket/WebSocket independent-peer inputs match `b8096fd6`; the memory report
passes 87 cases/eight groups, with all 140 tracked sources matching and the
generated lock hash verified. Its synthetic PR merge has `b8096fd6` as a parent.
Uploaded group-log hashes match. Hosted PR Fast Checks also passes. Remaining
required hosted CI is still running without an observed failure. Evidence:
`/tmp/connectanum-b8096fd6-hosted-conformance-proof.json`.

Independent [SDK copy research](../research/2026-10-06-dart-sdk-copy-boundaries.md)
identifies conditional partial-view copies before socket writes and binary
masking/ring-buffer copies. A 15-case ordinary serializer diagnostic shows
all five FlatBuffers frames use partial backing views, unlike the ten
CBOR/MessagePack frames. The checked-in Linux pointer probe now confirms the full/partial-view boundary
through actual libc writes and retries. Internal buffering, TLS and total-copy
volumes remain unmeasured. This is not parity or a complete-copy claim.
Complete hosted acceptance and all unresolved milestone criteria remain pending.

Preceding follow-up: native opaque-PPT body reuse between the three binary codecs.
The nine fail-first regressions report six mixed eligibility failures and three
homogeneous echo metadata failures, exit 101. The passing `7d7fab90` canonical
checks are the baseline. Producer lifetime, empty bodies, routing metadata and
fallback rejection must be verified before publishing this change; whole-path
copy accounting and benchmark parity remain unresolved. All 22 Rust segmented
cases and 109 public live/eligibility cases now pass. The latter exposed and
reproduced 28 explicit `wamp`-scheme RPC fallbacks before removing those Dart
exclusions; custom-detail and other existing routing guards remain intact.
The predecessor's five-platform dry run, fifteen attestations and thirty preview
assets verify at `7d7fab90`; the body bridge's resulting-head artifacts and
hosted acceptance remain pending. Current `bin/test-fast` passes at
exit 0; GuardMalloc observes and passes 83 ownership cases, including all 22
segmented-forwarding tests. Final implementation/test hashes are unchanged.
The first full verification fails on an old worker-session assertion excluding
encrypted native forwarding. The repaired test preserves all ciphertext checks
in a fallback control and adds a native transfer/no-decoding control. Both and
all 204 worker/live cases pass. No product code changed for this test repair.
Fresh root analysis and corrected full `bin/verify` pass at exit 0, including
Rust, VM, consumer/live checks, 1,563 benchmark, 4,958 router, 4,690 core
Chrome/Dart2Wasm and 2,829 client browser cases (20 declared native-only skips).
Evidence: `/tmp/connectanum-native-ppt-routing-verify-fixed.{log,exit}`.
The fast run precedes the test-only worker repair; full verification covers it.
All six recorded final verification inputs and 141 GuardMalloc native/schema
inputs remain unchanged.
Hosted VM coverage on `7d7fab90` passes its library gates, then hits the explicit
45-minute job maximum during packaging formatting. Only this aggregate budget
becomes 90 minutes. All other workflow bytes, collection scripts and coverage
policy are unchanged; all 80 existing verification-tool checks pass. Hosted
completion remains pending. Evidence:
`/tmp/connectanum-native-ppt-routing-coverage-budget-proof.json`.
Research: [GitHub job timeout behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes).
Evidence:
`/tmp/connectanum-native-ppt-routing-before.{log,exit}`. Freshly fetched master
remains `3bac4cf5`, already integrated; no merge is needed.

The preceding follow-up repairs a root-analyzer regression at `8df5c9b3`.
Fresh `bin/test-fast` fails at exit 3 on four `undefined_named_parameter`
errors: the new benchmark test helper passes VM-only `runtime:` parameters
through the public conditional-export API. The helper now uses the public
`libraryPath:` parameter; its prior singleton initialization keeps the metrics
collector and provider on the same native runtime. Production code is unchanged.
Root `dart analyze` and all 28 focused counter cases pass at exit 0. The corrected
`bin/test-fast` and fresh `bin/verify` pass at exit 0, including Rust, VM,
consumer/live WAMP and browser suites (20 declared native-only client skips).
Final Dart/YAML input hashes are unchanged. Hosted acceptance remains pending.
The earlier full `bin/verify` pass did not include root analysis and therefore
did not detect this regression. Evidence:
`/tmp/connectanum-e2ee-pipeline-baseline-fast.{log,exit}` and
`/tmp/connectanum-e2ee-public-helper-{analyze,focused,fast,verify}.{log,exit}`.

The CI workflow now groups automated `codex/` branch runs by workflow, event and
ref, cancelling superseded runs within each group. Master, tags, manual dispatch
and other branches use unique run IDs, avoiding cancellation of pending runs as
well as active runs. Push and PR groups remain separate. Thirteen event/ref
boundary scenarios plus workflow separation pass with the official
`@actions/expressions` evaluator 0.3.61; all 80 verification-tool cases pass.
Every existing job body is byte-identical, including commands, gates and deadlines.
The ownership guide replaces its stale fixed case count and temporary report path
with the reproducible runner command and per-run source/count evidence.
Research: [GitHub concurrency semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)
and [official expression evaluator](https://github.com/actions/languageservices/tree/main/expressions).
Hosted cancellation behavior remains unverified. Local GLM judgment and Qwen
review completed; the evaluator/source checks resolve their inaccurate PR-ref
details. Initial bounded companion requests exhausted output limits and are not
completed reviews. Evidence: `/tmp/connectanum-ci-concurrency-evaluation.json`,
`/tmp/connectanum-ci-concurrency-job-proof.json` and
`/tmp/connectanum-ci-concurrency-tool-tests.log`.

[Native Artifacts 37480119838](https://github.com/konsultaner/connectanum-dart/actions/runs/37480119838)
passes all five builds and its dry-run preview at `8df5c9b3`. All fifteen
source/branch/workflow attestations verify; thirty preview assets match and the
notes exactly match the renderer. A fresh pinned-source standalone consumer
passes all four serializers and the public native API with the Apple Silicon
production library; ten shared-segment and sixteen live owned-PPT cases also
pass. Direct scalar input/growth copies are zero and independently owned
read-only views survive disposal. Production exports contain no `ct_test_*`
oracles; the ffi-test positive control contains eighteen. Other platforms have
build/provenance evidence only. No release is published. Evidence: `/tmp/connectanum-8df5c9b3-platform-provenance.json` and
`/tmp/connectanum-8df5c9b3-preview-proof.json` and
`/tmp/connectanum-8df5c9b3-production-consumers-proof.json`.

The preceding follow-up measures native-provider ciphertext byte-list coercion.
The fail-first matrix passes four Uint8List decrypt cases and fails all eight
ordinary-list cases because their conversions are omitted from the lower bound.
The runtime now counts that isolate-local boundary separately from FFI and native
staging, without changing the native ABI or wire representation. All 28 focused
cases pass, including both ciphers/profiles, immutable bounded subviews, exact
prefix counts on typed rejection, absent staging ABI and counter reset/deltas.
Failed legacy CBOR coercion remains explicitly excluded. The total E2EE pipeline
stays `not_measured`; no parity or complete-copy claim is added.
Baseline `bin/test-fast` passes at exit 0 before this change. All 178 native and
Session provider/profile/key-selection cases pass with the explicit ffi-test
library. Fresh canonical `bin/verify` passes at exit 0, including Rust, VM,
consumers, 1,563 benchmark, 4,935 router, 4,690 core browser and 2,829 client
browser cases (20 declared native-only client skips). The final Dart source/test
hashes are unchanged. Evidence: `/tmp/connectanum-e2ee-wrapper-verify.{log,exit}`.
Earlier focused evidence:
`/tmp/connectanum-e2ee-wrapper-{baseline-fast,regression-before-valid,focused}.{log,exit}`.
The initial regression command used a wrong package-relative path and is not the
fail-first evidence. An initial provider command also named a nonexistent test
and selected a library without the required owned-crypto/staging ABI; its failed
result is retained; the corrected run passes with the explicit ffi-test library.
Evidence: `/tmp/connectanum-e2ee-wrapper-providers-corrected.{log,exit}`.
Hosted push CI `37473576179` on `8feb80c1` now passes WampApp Consumer and
Fast Checks. Complete hosted acceptance remains pending. The superseded PR run
`37464701287`, which failed the old privacy oracle and skipped Full Verify, was
cancelled; its successful older push run and both new-head runs were preserved.


The preceding follow-up repairs WampApp's encrypted-vault privacy-test oracle.
Hosted Consumer job `112272706961` on `62f99ebb` passes 409 cases and fails one
because randomized Base64 ciphertext contains `bob`. The captured envelope has
only public metadata; the bare-string predicate is not a plaintext-leak oracle.
The test now allows only the exact public vault/backup metadata fields and checks
quoted JSON tokens. Production crypto is unchanged. The captured old oracle
fails, the repaired oracle passes, injected plaintext contacts fail, and all 22
vault cases pass. Full `bin/test-wamp-app` passes at exit 0, including VM/JS/Wasm
tests, mutation controls and the web build. Fresh canonical `bin/verify` passes
at exit 0, including Rust, VM, consumers, 1,541 benchmark, 4,935 router, 4,690 core
browser and 2,829 client browser cases (20 declared native-only client skips).
Evidence: `/tmp/connectanum-vault-oracle-verify.{log,exit}`. Current hosted CI
remains unaccepted; original issue criteria stay intact.
The repaired Fast Checks budget is confirmed by its passing hosted job; the
old WampApp privacy assertion still blocks that PR run's downstream checks.

Native Artifacts `37464710421` passes at exact `62f99ebb`, including all five
platform builds and the release preview. All fifteen attestations independently
verify; all thirty assets match and the notes exactly match the repaired renderer.
Its fresh standalone consumer, ten segment cases and sixteen live owned-PPT
cases pass with the production Apple Silicon library. No release is published;
other platforms have build/provenance evidence only. Package dry run passes.
Three superseded CI runs with cancelled Fast Checks were cancelled to free
runners; both resulting-head CI runs remain active. Evidence:
`/tmp/connectanum-62f99ebb-platform-provenance.json` and
`/tmp/connectanum-vault-oracle-control-proof.json`.

The preceding follow-up repairs the separate Fast Checks aggregate job budget
and missing release-preview evidence links. On `5f1afae9`, hosted Fast Checks
passes a live consumer smoke at 20m12.701s and is cancelled 1.937s later at
GitHub's explicit 20-minute ceiling. The aggregate budget becomes 45 minutes;
all commands, test deadlines and gates stay unchanged. All eighty verification
tool checks pass. Two release-note link regressions first fail, then all three
renderer tests pass with commit-pinned repository/server-correct conformance,
benchmark and ownership links. The ownership guide explicitly compares pinned
Dart entity reconstruction with the C producer-thread transaction/lease policy
and measured copy fallback; no ObjectBox dependency is added.
Parity and complete copy coverage stay unaccepted.
Fresh canonical `bin/verify` passes at exit 0, including Rust, VM, consumers,
1,541 benchmark, 4,935 router, 4,690 core browser and 2,829 client browser cases
(20 declared native-only client skips). Evidence:
`/tmp/connectanum-release-readiness-verify.{log,exit}`. Hosted acceptance and the
resulting head's release preview remain pending.

Native Artifacts run `37457831556` passes all five builds and the dry-run release
preview at exact source `5f1afae9`. All fifteen archive/checksum/manifest
attestations independently verify against that source/branch/workflow; checksums
and manifest source fields match. The Apple Silicon production artifact passes
a standalone public consumer, ten shared-segment cases and sixteen live owned
CBOR/MessagePack runner cases. The consumer also round-trips ordinary values
through all four public serializers. Its direct scalar payload has zero input/growth
copies and its derived read-only control view retains independent ownership.
Production exports contain no `ct_test_*` oracle; the ffi-test positive control
contains eighteen. Other platforms have build/provenance evidence only. The
preview has thirty expected assets but lacks conformance/benchmark evidence
links, motivating the renderer repair. No release is published. Fast Checks
cancellation skips Full Verify and VM coverage; binding, browser coverage,
GuardMalloc and WampApp consumers pass. Original acceptance remains open.

The preceding follow-up repairs the hosted Full Verify aggregate job budget.
Its preceding `c3dbc9cb` run reaches browser tests after 40m51s and hits GitHub's
45-minute ceiling while cases still pass. The aggregate budget becomes 90 minutes
to contain the observed preceding work and the existing bounded browser commands.
The annotation/timestamp reproducer, all 80 verification-tool checks and fresh
canonical verification pass. No command deadline or gate changes.

The preceding follow-up implements complete native construction of the benchmark
CBOR/MessagePack PPT fixture on top of pushed `425c9e62`. The baseline suites
finish before production edits; its recording wrapper fails afterward. The
`native_buffer` group previously held only a native body and subsequently
serialized a Dart map. The constructor now writes the same complete PPT bytes
directly in native storage and retains that span. Focused/live tests and all
1,541 Linux benchmark cases pass; fresh full canonical verify and sequential
fast checks both exit 0. Linux
benchmark coverage is 2,981/3,033 lines (98.286%), above the unchanged 98% gate,
and the codec is 122/122 lines. Other packages are unmeasured in this targeted
report; whole-repository coverage is not accepted by it.
The regular serializers are the byte-for-byte reference, including integer and
binary-length boundaries. The single body input copy stays counted, just as in
the FlatBuffers native fixture. No original copy/parity gate is relaxed.

The preceding follow-up adds shared encoded native submission for CBOR and
MessagePack on top of pushed campaign checkpoint `c3dbc9cb`. Frozen buffers stay
owned through queued write/flush; generic lazy owned PPT preserves the exact
allocation and counts small metadata copies. API/version/identity guards retain
compatibility and the FlatBuffers session profile. Native, Dart, live Session,
Linux coverage and GuardMalloc checks pass. Fresh canonical fast/full
verification passes after clearing disposable caches following host filesystem
exhaustion; no failed run is accepted as clean.
Dynamic CBOR/MessagePack native construction, complete copy metrics and primary
parity remain open. The preceding executor's 120-row diagnostic is correctness
evidence, not primary performance acceptance.

The preceding follow-up fixes the benchmark test runtime leak at pushed `1aafa099`.
Hosted Fast Checks failed eight cases after native E2EE factory tests left the
process-wide client runtime running. The Linux reproducer fails six accounting
cases; the factory-test runtime teardown repairs all 39 related cases with no
native skips. All 1,498 full Linux benchmark cases now pass with no native skips.
The fresh repository baseline and full `bin/verify` pass at exit 0, including
Rust, VM, consumers, 1,498 benchmark, 4,935 router, 4,690 core browser and 2,829
client browser cases (20 declared native-only client skips).
The repair is pushed to both remotes as `87688b8c`; exact-head hosted CI remains
in progress. Both package publish dry-runs, binding and GuardMalloc checks pass.

The preceding follow-up builds on pushed `dbeda203` with benchmark metric
validation, VM isolate fallback and coverage repairs. Fresh baseline verification
and 60 focused tests pass on macOS and Linux arm64. Linux benchmark coverage is
98.219% against its unchanged 98% target; full browser coverage passes both gates.
Fresh full `bin/verify` passes at exit 0, including 1,498 benchmark, 4,935 router,
4,690 core browser and 2,829 client browser cases (20 declared native-only client
skips). The unchanged native implementation retains the ordinary-routing
GuardMalloc evidence: 70 cases and all 141 native/dependency inputs matching.
Issues #95–#99 are complete. Hosted VM coverage at `dbeda203` failed at 97.404%
against the unchanged 98% benchmark gate; one browser job timed out while the
same-head PR browser job passed. Required hosted acceptance and publish dry-runs
remain pending. Copy counters and the evaluator provide partial attribution and
fail-closed gates; no paired performance campaign or parity result exists.

## Objective and scope

Complete all ten milestone issues. FlatBuffers is a regular serializer beside
JSON, MessagePack and CBOR, with interoperable Dart/Rust codecs, native-owned
construction, generic external-buffer leases, lazy routing, PPT/E2EE and measured
performance at least matching the better binary baseline on declared workloads.
ObjectBox integration itself belongs to a separate adapter package.

The primary checkout is independent and remains untouched. Feature commits,
pushes and draft PR updates are authorized. The user requested merging current
master into this working branch on 2026-10-06; both remotes are already integrated.
The earlier release/publication hold is superseded by the user's 2026-10-08
request for a synchronized beta.8 release, recorded in the checkpoint above.

## Issue acceptance status

- [x] [#95](https://github.com/konsultaner/connectanum-dart/issues/95): pinned binding, reproducible generation, metadata/schema compatibility.
- [x] [#96](https://github.com/konsultaner/connectanum-dart/issues/96): native builders, freeze/retain/transfer, native inputs throughout submission.
- [x] [#97](https://github.com/konsultaner/connectanum-dart/issues/97): generic external leases, producer-thread release, real send completion.
- [x] [#98](https://github.com/konsultaner/connectanum-dart/issues/98): complete public Dart serializer, factories and verified lazy payload behavior.
- [x] [#99](https://github.com/konsultaner/connectanum-dart/issues/99): native Rust codec, transport negotiation and supported profile guards.
- [ ] [#100](https://github.com/konsultaner/connectanum-dart/issues/100): homogeneous/mixed routing, delayed/progressive/error flows and lifetime preservation.
- [ ] [#101](https://github.com/konsultaner/connectanum-dart/issues/101): PPT and explicit typed E2EE profile; unchanged CBOR behavior and unsupported file handling.
- [ ] [#102](https://github.com/konsultaner/connectanum-dart/issues/102): external conformance, malformed-input/fuzz, memory/ownership CI.
- [ ] [#103](https://github.com/konsultaner/connectanum-dart/issues/103): representative throughput/latency/memory/copy gates and repeatable hosted evidence.
- [ ] [#104](https://github.com/konsultaner/connectanum-dart/issues/104): platform/consumer readiness and release/adapter documentation.

Implementation exists for many of these paths; unchecked items reflect remaining
acceptance and evidence, not a claim that every feature is unimplemented.

## Next work

Mixed binary PPT body reuse and empty outer-map support are implemented and
pass local canonical verification at `b8096fd6`. Its signed artifact dry run and
production consumers now pass. A developer-only socket pointer probe independently
confirms the pinned SDK boundary and retries; fresh fast/full verification passes.
Required hosted CI and complete copy instrumentation remain the next blockers.
Preserve every original milestone criterion.

1. Inspect required hosted CI for the resulting feature commit; fix any failure
   before continuing feature or benchmark work.
2. Complete #100/#101 acceptance, including crypto/serializer/transcode copies
   beyond the measured native staging sites and routing/PPT/E2EE lifetime evidence.
3. Complete #102/#104 hosted conformance, memory, artifact-consumer and release
   dry-run evidence without treating earlier commits as current-head acceptance.
4. Finish #103 measurement coverage, the paired campaign runner and all declared
   performance rows. SDK/TLS/transcode copy gaps and absent campaign results
   remain blockers; do not weaken the parity or copy gates.

## Hosted Full Verify aggregate budget (2026-10-06)

- [x] Inspect job `112200071473` in run `37437589411`, including annotations and
  the actual completed job log while the enclosing mutation run remains live.
  GitHub reports its 45-minute ceiling; core Dart2Js cases pass until 0.665s
  before cancellation. No stalled test is established by this evidence.
- [x] Calculate the observed pre-browser window (40m51s), preserving the existing
  900-second core and two 420-second client command allowances. The combined
  window is 69.861 minutes, exceeding the previous aggregate budget.
- [x] Change only Full Verify's aggregate job limit to 90 minutes. Retain all
  suites, LLVM verification, command/per-test bounds, thresholds and required jobs.
- [x] Pass all 80 verification-tool regression cases. The local debug companion's
  speculative hang/leak hypotheses are not established: timestamped passing
  cases continue immediately before GitHub's explicit deadline cancellation.
- [x] Finish fresh canonical verification before publishing this repair:
  `bin/verify` exits 0, including Rust, VM, consumers, 1,541 benchmark, 4,935
  router, 4,690 core browser and 2,829 client browser cases (20 declared
  native-only client skips). Product inputs remain unchanged from the preceding
  sequential fast check; only the CI budget and its documentation change.
- [ ] Inspect exact-head hosted verification and signed platform artifacts;
  validate the production consumer and release preview without publishing a release.

Evidence: `/tmp/connectanum-full-verify-budget-repro.json`,
`/tmp/connectanum-c3-full-verify-hosted.log`,
`/tmp/connectanum-c3-full-verify-{job,annotations}.json`,
`/tmp/connectanum-full-verify-budget-tools.{log,exit}` and
`/tmp/connectanum-c3-full-verify-timeout-debug.txt`, plus
`/tmp/connectanum-full-verify-budget-canonical.{log,exit}`.

## Complete native benchmark PPT construction (2026-10-06)

- [x] Finish the fresh baseline without changing production sources. All suite
  cases finish without test failure; the outer exit-recording command then
  fails because `status` is a reserved zsh variable. Do not claim that wrapper
  exited 0 or invent its missing exit file. The preceding pushed checkpoint's
  canonical fast/full results remain valid; final checks use `task_exit`.
- [x] Reproduce missing exact owned PPT spans for CBOR/MessagePack
  `native_buffer` construction with the existing recording Session tests.
- [x] Build complete fixture PPT directly in native storage, preserving the
  regular wire shape, uint32 identities and binary body, with one counted body
  input copy and no grow/concatenate copy.
- [x] Preserve lazy application decoding, exact owner identity and release
  on successful or rejected Session sends.
- [x] Compare byte-for-byte with the regular serializers at all relevant integer
  and binary-length boundaries and validate decoded application identity/body.
- [x] Exercise both owned construction groups over native RawSocket/WebSocket
  RPC/pub-sub, including FlatBuffers envelope/other PPT fallback semantics.
- [x] Confirm existing encryption coverage in the complete benchmark suite:
  Dart/native typed FlatBuffers with both ciphers, native mixed-serializer
  encrypted pub/sub, and native CBOR encrypted file transfer all pass on Linux.
  The new CBOR/MessagePack native constructors use the unencrypted custom typed
  benchmark scheme. Existing encrypted CBOR uses its ordinary value path;
  MessagePack is not an E2EE profile. No new encrypted constructor coverage or
  complete crypto copy attribution is claimed.
- [x] Include the codec/owner tests in the workload mutation inputs and suite.
  All 596 focused/aggregate cases and 46 live matrix cases pass. All 93 runner
  regression cases pass with one declared skip and unchanged thresholds.
  The prototype and actual-diff reviews raise source-disproved concerns:
  frozen builder disposal is a no-op, MessagePack binary headers never have
  width 1, and FlatBuffers payloads select their own decoder before the dynamic
  decoder branch. Fixed internal keys are ASCII and body() returns the validated
  requested length. No concrete companion blocker remains.
  The first canonical runs fail the stale exact mutation-inventory assertion.
  Its source, imported-test and fixture sets now include the constructor and its
  tests; exact equality and all thresholds remain enforced. Fresh canonical
  verify passes after that repair.
  The repaired fast run fails one existing close-after-READY worker case at the
  unchanged two-second readiness timeout while fast/full checks overlap. The
  unchanged case then passes five focused repeats and the full verify run's
  1,541-case benchmark suite. Do not accept the failed fast run as green or
  infer a proven root cause. Fresh sequential `bin/test-fast` now exits 0,
  with the unchanged case and all 1,541 benchmark cases passing.
  Full `bin/verify` exits 0, including Rust, VM, consumers, 1,541 benchmark,
  4,935 router, 4,690 core browser and 2,829 client browser cases (20 declared
  native-only client skips). Evidence:
  `/tmp/connectanum-native-construction-verify-final.{log,exit}`,
  `/tmp/connectanum-native-construction-startup-repeat.{log,exit}` and
  `/tmp/connectanum-native-construction-fast-sequential.{log,exit}`.
- [x] Complete focused review, fresh fast/full verification and unchanged Linux
  benchmark coverage before publishing the next checkpoint.
- [ ] Obtain exact-head hosted acceptance. Complete SDK/TLS/transcode/E2EE copy
  instrumentation, resource budgets and primary parity under the original gates.

The constructor is specific to the existing benchmark application model; it
does not replace the public CBOR/MessagePack serializers. Field names, PPT map
structure and map ordering follow the checked-in serializers. Integer and byte
string headers follow [RFC 8949 section 3](https://www.rfc-editor.org/rfc/rfc8949.html#section-3)
and the [MessagePack specification](https://github.com/msgpack/msgpack/blob/master/spec.md).
Only uint32 identities and the existing 64 MiB fixture body limit are supported.

Evidence: `/tmp/connectanum-native-construction-{owner-repro,owner-fixed,prototype,focused,live,inventory}.{log,exit}`,
`/tmp/connectanum-native-construction-{context,test-ideas-narrow,review}.txt`,
`/tmp/connectanum-native-construction-linux-coverage.{log,exit}`,
`/tmp/connectanum-native-construction-linux-{lcov.info,summary.json}`.
The coverage checker exits 1 for 204 findings in unmeasured other packages and
scopes; there are no benchmark findings. The fixture overlays these Dart/tool
changes on the existing Linux clone and retains the unchanged native binary;
it is explicitly dirty functional evidence, not a clean-head timing campaign.
The Linux daemon was unavailable; starting the existing Docker service/container
restores the retained fixture. Its native frame source matches the host's
unchanged source hash `519a466e30580aab98db61b920d0288d6e82ed6bc85b360768f6c22ef85f899d`.
Eight changed Dart/tool inputs are overlaid; it remains explicitly a dirty
functional/coverage fixture, not controlled timing or clean-head acceptance.

## Shared encoded native submission (2026-10-06)

- [x] Reproduce the missing shared ABI and two missing CBOR/MessagePack exact
  owner anchors before implementing their paths.
- [x] Add optional owned-segment ABI v1, retaining 1–64 frozen handles with no
  input consumption on success/rejection and no payload concatenation/copy.
- [x] Keep every empty producer owner alive through a nonempty segment anchor;
  verify exact allocation pointers and producer-thread final release.
- [x] Add Dart capability probes, tracked/untracked submission and a Finalizable
  input holder; preserve the FlatBuffers session-profile guard.
- [x] Add generic lazy owned PPT and eligible CBOR/MessagePack CALL/PUBLISH
  submission; count only newly serialized metadata copies at this boundary.
- [x] Reject forged/replaced owner views and retain regular serializer semantics.
- [x] Use the owned anchor for CBOR/MessagePack benchmark pre-encoded spans.
- [x] Pass 18 native ownership/network cases, 10 new Dart API/transport cases,
  existing FlatBuffers frame cases and all 131 focused benchmark/live cases.
  All 17 combined new API/existing frame cases also pass on Linux arm64.
- [x] Pass all 73 GuardMalloc ownership cases; 141 native/dependency/schema
  inputs match before/after the instrumented checks.
- [x] Complete a focused companion review. Its Finalizable-registration concern
  is disproved by the SDK marker-interface contract: the local holder keeps the
  entire list/handle graph reachable until synchronous native retention returns.
  Queued writes then own independent Frozen references. GLM judge attempts
  reach their deadlines without a substantive response, so no judge verdict is
  claimed.
- [x] Repair mutation inventories for the new part and test: all 92 runner
  regression cases pass, with their single declared skip and unchanged gates.
- [x] Pass all 281 native FFI cases after the test's runtime-rejection path uses
  the global runtime-test lock; memory instrumentation is refreshed afterward.
- [x] Add/pass eight live native Session RPC/pub-sub cases across CBOR/MessagePack
  and RawSocket/WebSocket on macOS and Linux. Use the existing worker process
  for native WebSocket handshakes so the router's Dart isolate can serve them.
- [x] Pass all 1,504 original-plus-owner-anchor Linux benchmark cases and the
  eight added Session cases, with no native skips. Targeted coverage including
  the existing child-process build probes is 2,926/2,978 lines (98.254%), above
  the unchanged 98% gate with no benchmark-specific finding. The first manual
  collection omitted the existing child-coverage environment variable and was
  rejected at 97.851%; no source fix or relaxed threshold is involved.
- [x] Pass fresh canonical fast/full verification. The first runs fail on host
  filesystem exhaustion, during browser compilation and benchmark temporary
  directory creation. Clear only this worktree's disposable Rust incremental
  caches (about 6 GiB), retaining release libraries, binaries and all evidence;
  rerun both commands successfully. Full verification includes Rust, VM,
  consumers, 1,512 benchmark, 4,935 router, 4,690 core browser and 2,829 client
  browser cases (20 declared native-only skips). Do not accept the failed runs.
- [x] Complete the final source/contract review and prepare the checkpoint for
  publication to both remotes and the existing draft PR.
- [ ] Obtain exact-head hosted acceptance after publishing the checkpoint.
- [ ] Complete dynamic CBOR/MessagePack native construction, full SDK/TLS/
  transcode copy metrics, primary timing and parity under unchanged #103 gates.

Evidence: `/tmp/connectanum-shared-codec-{rust-tests,dart-final-tests,bench-tests,linux-client-tests}.{log,exit}`,
`/tmp/connectanum-shared-codec-guardmalloc-final/report.json` and
`/tmp/connectanum-shared-codec-review-final.txt`,
`/tmp/connectanum-shared-codec-{fast,verify}-recovered.{log,exit}` and
`/tmp/connectanum-shared-codec-linux-bench-{lcov.info,summary.json}`.
The first attempted fresh baseline overlapped implementation and caught a
transient Dart switch-type compilation error introduced in this follow-up. It
was repaired before the focused suites; that attempt is not a passing baseline.
A subsequent check also detected missing mutation-inventory registrations;
those sources/tests/support files are now included and all 92 checks pass.
Fresh `bin/test-fast` and `bin/verify` pass at exit 0. No issue is closed or primary
performance claim accepted.

## Campaign executor (2026-10-06)

- [x] Implement all 48 primary cases and deterministic balanced codec schedules,
  retaining one driver/worker through warmup and measured passes.
- [x] Stream flushed JSONL without rebuilding aggregate report history.
- [x] Preserve partial/cancelled evidence and verify process-group cleanup.
- [x] Reject busy hosts, changed inputs, incomplete execution and diagnostics
  as primary acceptance; keep the checked-in numeric policy unchanged.
- [x] Retain actual WAMP configuration and reject codec/profile misattribution
  and repeated primary matrix dimensions. Fail-first regressions are preserved.
- [x] Run focused Python, Rust and benchmark-router configuration checks.
- [x] Preserve the first interrupted Linux diagnostic: 31 distinct client PIDs
  exposed that helpers recycled after every row. Add explicit successful RPC/
  pub-sub reuse and stable client/server PID checks; preserve default, failed and
  cancellation-workload recycling and test close/recovery lifetimes.
- [x] Exercise real Linux codec/transport/TLS/construction rows and inspect
  actual process metrics, raw reports and teardown.
- [x] Complete three warmup and seven measured passes for four paired cases:
  40 reports per codec, one client PID, one server PID, unchanged inputs,
  exact raw/per-pass JSONL equality and driver exit 0. The short diagnostic
  comparison fails at exit 1 with 370 findings; no primary acceptance is claimed.
- [x] Pass all 1,502 Linux benchmark cases with no native skips. Targeted library
  coverage passes the unchanged 98% gate at 2,925/2,979 lines (98.187%) with no
  benchmark-specific policy finding; the full repository report remains separate.
- [x] Pass full `bin/verify`, including all VM, consumer, benchmark, router and
  browser suites. Fresh Rust benchmark tests cover the final metadata alias fix.
- [x] Review the critical lifecycle/report guards and verify companion concerns
  against the actual sequential driver, input hashes and idempotent sampler.
- [x] Commit and push the campaign follow-up as `c3dbc9cb`; exact-head hosted
  checks remain pending.
- [ ] Complete copy coverage, shared binary-codec ownership paths, hosted
  campaign publication and all primary performance gates for #103.

See [campaign contract](../flatbuffers_performance_acceptance.md) for execution
commands and limitations. A short diagnostic cannot satisfy primary acceptance.

## Shared-runtime test teardown (2026-10-06)

- [x] Inspect the exact-head Fast Checks failure at `1aafa099`: eight benchmark
  cases fail after the new native E2EE provider factory tests.
- [x] Reproduce six accounting failures in one Linux test process with the
  factory file preceding the accounting file. Provider disposal leaves the
  shared native runtime alive, preventing a later router runtime start.
- [x] Add the runtime shutdown teardown already used by the other factory
  regression tests. All 39 related Linux cases pass with no native skips.
- [x] Pass all 1,498 full Linux benchmark cases with no native skips.
- [x] Complete the fresh `bin/test-fast` repository baseline at exit 0.
- [x] Pass fresh full `bin/verify` at exit 0 with Rust, VM, consumer, benchmark,
  router and full browser suites. Focused formatting and analysis also pass.
- [x] Push the repair to both remotes as `87688b8c`.
- [ ] Accept required hosted checks on that exact head.

Evidence: `/tmp/connectanum-flatbuffers-ci-1aafa-fast-job.log`,
`/tmp/connectanum-flatbuffers-ci-1aafa-runtime-leak-{repro,fixed}.{log,exit}`.
Full suite evidence: `/tmp/connectanum-flatbuffers-ci-1aafa-linux-bench-fixed.{log,exit}`,
`/tmp/connectanum-flatbuffers-campaign-baseline.{log,exit}` and
`/tmp/connectanum-flatbuffers-ci-runtime-teardown-verify.{log,exit}`.
The strict seven-package publish dry-run on `1aafa099` reports zero warnings;
this is that checkpoint's package evidence, not acceptance of the pending repair.

## Coverage repairs and master synchronization (2026-10-06)

- [x] Fetch both remotes and confirm `master` at `3bac4cf5` is already integrated;
  the merge command reports `Already up to date`.
- [x] Inspect both hosted coverage artifacts. Both VM jobs fail the benchmark
  98% gate at 97.404%. The same-head PR browser report passes core 96.136% and
  client 96.430%; the push job reaches its whole-suite 900-second deadline while
  still completing tests.
- [x] Complete the fresh `bin/test-fast` baseline at exit 0.
- [x] Reproduce six reporting/isolate defects before changing behavior; all six
  pass after the fixes. Incomplete boundary metadata and invalid byte counts now
  fail closed. System-only VM processes have no application fallback.
- [x] Pass all 60 focused metric, malformed-correlation, direct workload/profile
  validation and native/Dart typed E2EE factory tests with no native skips.
- [x] Pass focused analysis and all 80 verification-script tests. Check companion
  findings against source and test evidence; none establishes a remaining defect.
- [x] Pass all 1,498 macOS benchmark cases under coverage collection. Pass all
  Linux cases across the full suite and the two-case fixture repair; Linux
  benchmark coverage is 98.219% (2,923/2,976 lines) with no benchmark policy
  failures. macOS leaves Linux-only process-stat paths unexecuted at 97.043%.
  Benchmark-only input does not accept the whole-repository VM coverage job.
- [x] Pass fresh `bin/test-browser-coverage` at exit 0: core 96.136%, client
  96.430%, with 20 declared native-only client skips and unchanged thresholds.
- [x] Complete fresh `bin/verify` at exit 0: Rust, VM, consumer smokes, 1,498
  benchmark, 4,935 router, 4,690 core Chrome/Dart2Wasm and 2,829 client browser
  cases (20 declared native-only client skips).
- [ ] Push the resulting checkpoint and accept required hosted checks on it.

The bounded core browser deadline is 1,200 seconds and the whole job has 30
minutes for both suites and artifact upload. Per-test deadlines, suite selection
and coverage thresholds are unchanged. Known copy counts remain lower bounds;
these reporting repairs do not measure the outstanding SDK/TLS/transcode sites.
No additional issue is closed and no performance parity result is accepted.
Evidence is recorded in `docs/project_state.md`.

## Ordinary encoded routing and JSON ownership (2026-10-06)

The optional native forwarding-query ABI v1 checks ordinary CBOR/FlatBuffers
argument reuse without consuming the message. CBOR-to-FlatBuffers validates the
pinned container contract. Native envelope replacement resolves and rechecks the
actual destination, keeps each original payload allocation once, and rejects
incompatible output without sending bytes or consuming the source. Worker
forwarding now uses this eligibility for mixed codecs and cross-worker targets.
PPT/transparent data retains its prior path. A real regression test caught a
missing custom INVOCATION-option guard; both progressive and ordinary forwarding
now preserve custom metadata through the existing envelope-building path.

Mixed-codec tests also exposed JSON's destructive binary-container conversion.
Typed and immutable Uint8List containers now remain unchanged and reusable.
Shared TransferableTypedData aliases initially regressed when the redundant
mutation was removed; 14 fail-first cases reproduce this. One payload-local
identity cache now encodes each transfer once across arguments and keywords,
while retaining one-shot consumption and leaving caller containers unchanged.

macOS passes 87 focused native/routing/PPT tests and all 29 JSON regressions.
GuardMalloc passes 70 observed cases with all 141 native/dependency inputs
matching. Linux arm64 passes 12 forwarding tests plus a real network test with
20 transport/direction/envelope scenarios. All 116 focused Linux Dart cases pass,
including the older-library fallback with no missing-native skips.
An unnecessarily broad Linux runtime attempt was stopped during an unchanged
slow external-lease test; no complete Linux runtime-suite pass is claimed.
The initial full verification was stopped after finding the alias regression;
the next passed VM, native, router and benchmark checks but failed 14 browser
alias tests because TransferableTypedData is unsupported there. The alias cases
now explicitly select the VM, as the existing serializers' transfer tests do;
all 15 Uint8List-container cases pass in Chrome/Dart2Wasm. Fresh full verification
on that platform correction passes at exit 0: 4,682 core VM, 4,935 router, 1,456
benchmark, 4,690 core browser and 2,829 client browser cases (20 native-only client
skips). A repeated root-level parallel Linux
invocation exposed conflicting singleton native runtimes; all 116 cases pass
with the router test configuration's required concurrency 1.
Two hosted mutation jobs at
`d3546c6d` ended on runner shutdown signals, without a completed gate result.
Known copy lower bounds and SDK/TLS/transcode unknowns remain explicit. #100–#104
stay open; routing correctness is not complete copy or performance acceptance.

Completed companion reviews were advisory. Source inspection and tests confirm
that destination codecs are immutable and send-time eligibility is rechecked,
recursive JSON output allocation already existed, and cached immutable strings
are serialized independently at each alias with one shared transfer consumption.
The broad follow-up exceeded the helper's context limit; focused Qwen and GLM
follow-ups timed out. Neither incomplete review is counted as coverage. The
29 regressions and direct source checks substantiate the JSON repair.

## Portable provider copies and XSalsa limit (2026-10-05)

Portable AES now uses PointyCastle's `processBytes`/`doFinal` to write directly
after the nonce in the final buffer, returning only the bytes written. The two
portable CBOR providers avoid redundant plaintext/ciphertext wrapper clones.
Copy counters first reproduced the extra operations; the same tests pass after
removal. Windowed core counters expose the remaining mutable XSalsa output
materialization and ciphertext-list coercion, including a failed operation's
already copied prefix. Benchmark lower bounds retain their native-process and
Dart-isolate scopes, unavailable snapshots and incomplete-pipeline markers.

The pinned pinenacl 0.6.0 source exposed a separate contract defect:
`EncryptedMessage.fromList` caps input at 1 MiB. Authenticated 2 MiB typed XSalsa
decryption failed despite the advertised 64 MiB profile. Typed receive now uses
the public explicit-length `ByteList` body wrapper and nonce API with the same
authentication primitive and existing 64 MiB preflight. The legacy CBOR wrapper
is unchanged. Old-limit/next-byte/2 MiB, truncated nonce/tag, tampering, sliced
input and native/portable 2 MiB tests pass. A live reporting regression also
proved that an explicit identical peer codec was incorrectly called mixed;
matching peers are now homogeneous and a CBOR-to-JSON route stays unmeasured.

The fresh baseline `bin/test-fast` passed. macOS focused tests and all 82
native-provider cases pass. Linux arm64 passes 234 focused cases plus five live
worker scenarios. A fresh full `bin/verify` passes at exit 0, including all 1,456
benchmark and 4,923 router cases and Chrome/WebAssembly (4,675 core; 2,829 client,
20 native-only skips). Current-head hosted checks remain queued; the older run
ended cancelled. The earlier partial local run
was stopped after finding the size defect and retained as
`/tmp/connectanum-flatbuffers-portable-crypto-verify-pre-limit.log`.
Narrow Qwen review claims were checked against the pinned library code and real
tests: output capacity includes the tag; counters are isolate-local; native and
portable sites are disjoint; receive views are read synchronously by pure Dart;
short inputs are wrapped as decryption errors. No added input copy is warranted.
Crypto dependency internals, native-provider coercion, other-isolate wrappers and
serializer/framing, SDK/TLS/transcode measurements remain unfinished. #100–#104
stay open, with no accepted parity campaign or current-head hosted evidence.

## Native crypto staging and Linux CI repair (2026-10-05)

Detached XSalsa preserves the existing nonce/tag/ciphertext bytes while removing
the old payload shift and second output copy. Native ABI v1 metrics count the
actual bulk staging sites separately from transport counters; Dart records the
runtime isolate's crypto FFI copies. Existing AES wire behavior is unchanged,
including its eligible consuming decrypt with no crypto staging copy. The report
names process-wide native and isolate-local bridge scopes explicitly and keeps
total E2EE coverage unmeasured. Optional symbols plus exact ABI version guard
prevent calling an incompatible snapshot layout.

Explicit typed FlatBuffers E2EE now reaches benchmark providers, construction
groups and call/publish options instead of the former CBOR-only rules. Omitted
serializers retain the CBOR profile; typed file transfer is rejected. Live 64 KiB
native RPCs for both ciphers emit staging metrics on macOS and Linux arm64.
Four native oracle/wire/error tests and 82 native-provider cases pass on each
platform. The metric suite (4), runner suite (65) and comparator suite (15) pass.
The comparator/policy requires E2EE evidence and rejects partial totals and false
not-applicable exemptions. These correctness checks do not establish parity.

Linux CI at `b5ab660c` failed five cases across two benchmark test files because
their default library lookup omitted the CI `target/ffi-test/release` artifact.
The Linux arm64 repro fails identically before `ecaa43d4` and passes all 14 focused
cases after it, with no skips. Full local `bin/verify` passes, including 1,452
benchmark cases and Chrome/Wasm. GuardMalloc passes all 66 cases; 141 recorded
native/dependency inputs still match. Logs are
`/tmp/connectanum-flatbuffers-crypto-verify.log`,
`/tmp/connectanum-flatbuffers-crypto-guardmalloc-final/report.json`,
`/tmp/connectanum-flatbuffers-crypto-linux-{native,provider,live}.log` and
`/tmp/connectanum-flatbuffers-bench-native-path-linux-{repro,fixed}.log`.

Narrow Qwen reviews completed; claimed tag-layout, failed-call counting, ABI and
scope issues were checked against the source and direct tests. Tag insertion is
explicit, failed calls count copies already performed, unknown versions never call
the snapshot, and the mixed measurement scopes are labelled as a lower bound.
The GLM advisory request did not finish and is not review acceptance. Remaining
crypto/serializer/transcode and SDK/TLS measurement gaps, hosted CI, consumer
artifacts and the paired performance campaign keep #100–#104 open.

## External-loan terminal-path acceptance (2026-10-05)

Four native network tests now cover eleven RawSocket/WebSocket or rejection
scenarios: unobserved successful writes, actual full-queue rejection, missing
destinations, and fan-out terminated by peer reset, local close or shutdown.
Verified payload prefixes prove partial progress before termination. The sole
writer retains the foreign loan when no caller view/handle remains. A separate
rejected producer releases while the accepted send stays pending; an exported
view remains readable across shutdown. Callback count/thread, byte integrity and
byte/lease quotas are checked. Existing registration and ABI tests cover setup
rollback and safe capability fallback. GuardMalloc requires all four network
tests and passes 62 total observed cases; its runner failure-control tests pass.
Fresh canonical fast/full verification both exit 0. Local logs and the memory
report are recorded in `docs/project_state.md`; hosted acceptance for the new
commit remains pending. This completes #97 without adding database integration
or asserting end-to-end zero-copy/performance parity.

## Typed benchmark fixture checkpoint (2026-10-05)

The benchmark package now has a deterministic workload schema with worker and
iteration identity, equivalent Dart/native FlatBuffers builders, and live echo
coverage for twelve RawSocket/WebSocket, Dart/native-caller, and outer-serializer
combinations. Native WebSocket callers use a spawned isolate because a native
handshake in the same isolate as its Dart callee can fail with native I/O error
`-7`. The generator uses the compiler version already pinned in the WAMP
manifest, and CI checks that generated Dart stays current. The fixture avoids an
extra expected-body allocation during verification. These are correctness and
generation checks only. `WampWorkloadRunner` does not yet expose the three
construction groups, and no paired throughput/latency/memory campaign or parity
result exists. Issue #103 remains open.

## Earlier verification evidence

The pushed b07d7b26 checkpoint includes explicit local typed E2EE providers, optional
whole-plaintext consuming ABI, retained read-only owners, opt-in deferred runtime
exports, ordinary benchmark factories and the internal RPC serializer-metadata
repair. Existing CBOR APIs/framing remain. Actual ObjectBox bindings stay outside
core. See [current state](../project_state.md) for exact contracts and proof paths.

The verified Session repair preserves negotiated runtime-payload capability
and moves typed key selection after existing preflight through an optional provider
contract. Explicit/policy/negotiated/default precedence, CBOR/custom behavior and
context-free directional defaults are covered by 42 key/capability cases. Focused
checks pass 268 VM client/native, 120 core and 66 JS/WASM cases each (20 native
browser skips per cohort). Initial canonical fast/verify passes and all 1,453
product/native/log/history hashes are audited at snapshot
`84a26cbab9aaa8c02b86ce39b61f57818df2af64c4e25fd7433e968a26ce717e`.
After the coverage repair, the registered Session fixture passes 56 VM cases and
complete client browser coverage passes 2,791 cases plus 20 native skips. Client
96.354% and core 96.160% pass unchanged floors; raw core source/test hashes are
verified before reuse. Final canonical verify passes on 1,453-file snapshot
`c415bf87cca057178fbd8e722182c83ef63200533b758f52d9e632ff2fd8ae36`.
All product/native/log/history hashes pass completed audit under
`session-coverage-repaired-canonical-completed-audit.json`. The registered fixture
passes 56 VM cases; the full client Chrome WASM cohort passes 2,800 cases with 20
native-only skips.
Independent VM/browser campaigns select all 305 mutations, including five new
ones, at unchanged gate/deadlines/equivalents. VM completes 236 kills, ten
survivors and 59 compile errors at 95.93496%, no timeouts; regeneration, all
classifications and input/native/log hashes are independently audited. Chrome JS
also completes all 305 with identical counts/score and no timeouts or new
equivalents; its independent completed audit verifies regeneration,
classifications and all frozen source/test/support/native/log hashes under
`session-preflight-core-e2ee-web-completed-audit.json`.

The preceding 1,450-file candidate passes canonical fast/verify with Chrome WASM
on macOS. Separate focused JS/WASM Session checks pass 44 cases each. Current
production ABI passes 116 VM cases; default feature-tree GuardMalloc passes 57
observed native tests, with five failure-control checks. Those are local evidence,
not hosted/all-platform/performance acceptance.

After the loop-oracle and memory CI additions, fresh canonical fast/verify passes on
1,452-file product snapshot
`edce848870ae28ab3aee2a7e30f144e9b230ab00112c7831085e560187cd40a0`.
Prefix: `/tmp/connectanum-flatbuffers-native-memory-loop-canonical-*`.
Both exit codes and all source/native/log hashes are independently audited.
Native ffi-test artifact9884a143 remains unchanged. The new macOS memory CI job retains reports and failure-control logs,
and Full Verify depends on it. Exact b07d7b26 hosted memory execution passes
57 cases and five failure controls; source, loader/count and log hashes are audited.

Complete VM mutations pass all 300 unchanged-source mutations at 95.9184%:
235 assertion-backed kills, ten survivors and 55 compile errors, no timeouts or
new equivalents. Inputs match the feature tree and are independently audited.
The matching complete Chrome JS campaign passes the same 300-mutation gate and
235/10/55 counts with no timeouts. Its mutation process exits 0 and restored
baseline passes. The outer wrapper exits 1 after an audit helper adds a Python
cache file; independent reconciliation verifies that exact sole added artifact,
all original bytes and all classifications against matching feature inputs.
The original wrapper failure remains preserved, not relabeled as a pass. Earlier
original/logical browser failures remain failed evidence.

## Earlier verification work and outcomes

1. Complete fresh canonical fast/verify and the browser/binding mutation gates.
   Canonical snapshot `12c56f17` passes fast/full verification; all 1,454 product
   files and protected native/source/log hashes pass independent completed audit.
   Prefix: `session-deferred-tooling-repaired-canonical-*` under `/tmp`.
   After applying the new binding assertions and ordinary benchmark rows, fresh
   fast/full verification runs under `session-deferred-contracts-canonical-*`
   and full Chrome JS coverage under `session-deferred-browser-coverage-*`.
   The core VM gate
   passes all 356 mutations at 95.35714%: 267 assertion-backed kills, 21 survivors,
   68 compile errors, no timeouts or new exclusions. Regeneration, classifications,
   selected inputs/native/runner/configuration and 358 logs pass independent audit.
   Browser also passes all 356 mutations with the same counts/score; selected
   inputs and every regenerated mutation/classification pass independent audit.
   Binding completes all 603 but fails at 89.43089% assertion coverage: 440
   assertion-backed detections, 16 test-error-only detections, 36 survivors and
   111 compile errors. Preserve that independently audited failure. Isolated
   24-case contract additions pass a 1,880-case baseline/restored control and
   detect 20 of 35 observed survivors with assertions; one further detection is
   test-error-only and 14 survive. Positive metadata/construction assertions
   also have a passing corrected baseline. A fresh complete 603 campaign has completed
   under `/tmp/connectanum-flatbuffers-deferred-binding-contracts-*`; those test
   additions are now applied to the feature tree after the preceding canonical
   verification passed; the applied file matches the isolated campaign's frozen
   test hash. No new exclusions or widened deadlines are used. The sole Python
   expected-inventory test edit is explicitly recorded; preserve any whole-product
   wrapper rejection separately from the selected-input result. Initial fast
   analysis and stale-equivalence failures are
   preserved; repaired runs use the unchanged gates/deadlines and the same eight
   source-verified exclusions. Prefix: `session-deferred-loop-bound-*` under `/tmp`.
   Earlier core-lazy evidence predating this change cannot accept the candidate.
   Focused checks pass 2,227 current-library VM runtime/binding cases,
   371 older-ABI runtime cases, 115 core cases per VM/JS/WASM platform and 228
   production-library Session cases. The preceding repaired fast run fails the
   missing-part support-inventory control, now fixed in both native targets. Its
   lazy campaigns have three VM timeouts and were stopped as incomplete/failed.
   A subsequent exact expected-list assertion is also updated to include the new
   part; both scope controls pass. Six exact assertion-backed VM/JS mutant kills
   and four restored/baseline controls independently audit the bounded test-oracle repair. Production source
   and exclusions are unchanged by that repair. Check current browser coverage
   Fresh browser coverage passes all 4,595 core and 2,820 client cases plus 20
   native-only skips at unchanged floors. Independent audit verifies the frozen
   1,454 product bytes, native/log hashes and all 99 coverage artifacts, and
   regenerates the same summary. Prefix: `session-deferred-browser-coverage-*`.
   The complete binding campaign passes 603 mutations at 96.13821% assertion
   coverage: 477 detections (473 assertion-backed), 111 compile errors and 15
   survivors. Independent audit regenerates all candidates, verifies frozen
   staged inputs and matching selected feature inputs, hashes all 605 logs, and
   verifies both 1,880-case controls with no equivalents or changed deadlines.
   Prefix: `deferred-binding-contracts-client-message-binding-vm-*`.
   Canonical fast passes; full verify fails nine two-second benchmark worker
   readiness checks. The failed execution is independently audited and retained.
   All 36 focused lifecycle cases pass unchanged; exact-setting full benchmark
   reproduction passes all 1,366 cases. The original failure remains preserved
   and its cause is unestablished. No readiness budget or lifecycle implementation is
   changed, and full canonical acceptance remains open.
2. Finish exact e6fb hosted CI acceptance. Five new production bundles already
   pass checksum/manifest/source/workflow attestation checks; exact e6fb Apple
   Silicon sources execute 209 VM native/Session cases and the standalone
   construction consumer. The other four binaries are verified, not executed.
   Oracle absence has actual positive controls; typed consume and inspection are
   present. Publication is skipped. Full CI 37223117459 last had 18 successes and
   21 pending jobs. This evidence does not accept the new Dart candidate.
3. Continue the remaining implementation and issue acceptance below. Keep each
   issue open until its criteria have been checked; #95 and #96 are now closed.
   No performance parity or all-platform execution is established.

The Session fixture/registration stage has passed canonical verification, complete
local browser coverage at unchanged floors, and both complete 305-mutation gates.
Its earlier failed coverage wrappers and intermediate gate failures remain retained
in project state and the proof artifacts; they are not relabeled as passes.

## Remaining implementation and acceptance

The candidate now selects typed native decryption before payload exports in
opt-in RawSocket/WebSocket Session receives. Metadata wrappers and a generic
deferred application view preserve lazy values/errors and explicit owned copies.
Default transport forwarding stays eager. Callback mutation, provider/context
replacement, recursive wire loading and classic decoding have fail-first repairs.
The expanded older-ABI matrix also repairs CBOR byte-string shape handling while
rejecting numeric arrays before policy. Fresh local `bin/test-fast` and full
`bin/verify` both pass at exit 0; hosted and acceptance evidence remain pending.
RawSocket AES pointer reuse is observed for the binary serializers;
WebSocket exercised copied fallbacks. Existing malformed-payload and context-free
ordering regressions remain retained evidence.

An initial manual native-owned typed path now connects a frozen FlatBuffers
application payload to `packNativeTypedPayload`, opaque frame composition and
`NativeFrameTransport` submission. Optional ABI v1 borrows the input in Rust and
publishes the cipher's output allocation as a frozen owned buffer. Rust pointer
oracles verify both cipher allocations; Dart tests verify the independent input
owner and composed frame. This avoids payload copies through Dart typed data.
Ordinary Dart-value E2EE retains its existing input/output copies. Native-path
transport copy counters now expose explicit Dart-to-native copies and WebSocket
mask/coalesce copies across client and router snapshots. A separate Rustls
counter reports accepted plaintext bytes, not memory copies. Dart-managed
socket/TLS copy paths, mixed-serializer transcodes and other
end-to-end copy sources remain unmeasured. Controlled performance parity is
still unmeasured; account for crypto, builder growth and remaining copy paths,
and apply shared optimizations to the CBOR/MessagePack baselines too.

Complete external session conformance and malformed-input/fuzz/ownership CI. The
pinned Autobahn object serializer is not a functioning live peer. Existing
independently generated Python read/write fixtures verify codec messages, not full
session conformance. Execute the supported platform/consumer acceptance paths.

Declare controlled workloads, budgets, warmup/repetitions and noise policy before
measuring FlatBuffers versus both CBOR and MessagePack. Cover ordinary values,
native construction and pre-encoded spans separately; both transports, clear/TLS,
Dart/native clients, RPC/pubsub/fan-out/progressive/mixed traffic and relevant
payload sizes. Record correctness, throughput, latency, CPU, memory/GC, wire size,
retained allocations and copied bytes. Missing metrics, failed primary rows or
inconclusive intervals block acceptance. No parity result exists yet.
The proposed [performance contract](../flatbuffers_performance_acceptance.md)
records the comparison groups, primary rows, repetition/noise rules and evidence
requirements before measurement. Relative CPU/allocation/GC/RSS budgets are now
encoded in the checked-in policy (point ratio at most 1.0, confidence upper bound
at most 1.05); actual controlled results and complete copy evidence remain open.

The existing ordinary-value 16 KiB serializer diagnostic matrix now contains
FlatBuffers rows for both transports with the same settings as its binary
baselines. A native orchestrator regression proves completeness and serializer
preservation (six-row fail-first, eight-row pass). No performance measurements
are accepted from this change. The current typed-provider prototype remains
incomplete: a typed application schema and worker/iteration validation must
precede typed workloads, especially pub/sub where keyword containers are invalid.

Finish public consumer and adapter-boundary docs, then audit each issue before
closing issues and the milestone. The beta.8 release checkpoint above records
the user's subsequent publication authorization without closing those criteria.

## Pushed checkpoint and research

At d26581c3, hosted PR CI completes successfully with all 40 jobs. Five-platform
Native Artifacts dry-run succeeds with publication skipped. Bundle source/checksum/
provenance verification passes; Apple Silicon executes 34 native checks and a
standalone consumer. Other platform binaries are not executed here. PR #105 now
records these completed results. They do not clear the uncommitted stage.

Reference [binding](../flatbuffers_binding.md), [PPT/E2EE](../e2ee_ppt_research.md),
[ownership](../native_buffer_ownership.md), and [current state](../project_state.md).
The [implementation journal](../history/2026-10-04-flatbuffers-implementation-journal.md)
and [prior state](../history/2026-10-04-project-state-before-flatbuffers-consolidation.md)
remain byte-preserved historical evidence. Retained failed/superseded attempts and
freshly corrected compiler/symbol/platform attribution are recorded in current state.

## Live peer follow-up (isolated candidate)

The independent upstream-only live peer fails at HELLO as expected by the strict
metadata-v1 profile. No public upstream-subset mode exists; do not infer support
from generated upstream readers. A separate generated-schema Python peer checks
explicit CHALLENGE and WELCOME acknowledgements and rejects missing/false offers.
It catches a shared cancellation URI defect and passes both cleartext transports
with the staged correction, including the exact downloaded production library.
Keep the legacy failure-control report and the passing 48-case existing regression
control. The reviewed checker, CI integration and cancellation correction are now applied
after the unchanged-setting full benchmark reproduction passed. Actual feature
production-library peer acceptance independently audits all 1,458 source bytes,
69 regenerated bindings and all protocol/control evidence. Fresh canonical and
browser coverage runs freeze those 1,458 files under `live-peer-*` prefixes;
they must complete before commit/push. No full verify or hosted acceptance is
inferred from the peer proof. Hosted/all-platform evidence and the rest of issue #102 remain open.
See [the research record](../research/2026-10-04-flatbuffers-live-peer-conformance.md).

The first combined-candidate fast run fails two app-lab supervisor deadlines and
never reaches full verify. Its failed 1,458-file snapshot and protected/native/log
hashes independently audit. All 15 focused app-lab tests subsequently pass at the
same deadlines, so preserve both observations without inventing a root cause.
Complete and audit the current fresh browser coverage before scheduling another
full canonical run; avoid simultaneous resource-heavy suites. Do not change
budgets, exclusions or mark either failed canonical run accepted.

Fresh combined-candidate browser coverage passes both complete cohorts and the
independent 1,458-source/99-artifact audit, regenerating the same summary and
preserving unchanged floors. The next complete canonical run is now launched
sequentially under `live-peer-sequential-canonical-*`. No concurrent large suite,
new deadline, exclusion or outcome relabeling is used.
Both canonical phases now pass at exit 0 against the same frozen 1,458-file
inventory. The independent completed audit verifies all product/protected/native/
log hashes and equality with the accepted browser coverage product snapshot:
`/tmp/connectanum-flatbuffers-live-peer-sequential-canonical-completed-audit.json`.
The next crypto boundary is prepared in the
[source-backed research](../research/2026-10-04-native-owned-crypto-boundary.md),
including corrected local test/architecture advice. No new crypto API is applied
during this canonical run. [Benchmark construction preparation](../research/2026-10-04-flatbuffers-benchmark-construction.md)
also records the missing echoed application identity check. Commit/push the
accepted checkpoint and obtain its own hosted evidence before claiming hosted
acceptance. At that checkpoint all ten issue criteria remained under audit.

The initial manual native-owned FlatBuffers E2EE path is committed as `dc33fcc6`
and pushed to PR #105. Fresh `bin/test-fast` and `bin/verify` pass at exit 0 on
the code checkpoint; its exact-head hosted checks are pending. The path is
generic Connectanum ownership infrastructure that a future C-backed ObjectBox
adapter can consume under an explicit producer lifetime. Issues #96 and #101
advance but remain open at that checkpoint; all ten milestone issues were under
audit.

## Typed benchmark runner construction groups (2026-10-05)

The typed fixture now drives unique, per-iteration benchmark payloads for RPC and
pub/sub. TOML `payload_construction` is passed through the Rust orchestrator to
the Dart runner. `values`, `native_buffer`, and `pre_encoded_span` work with
FlatBuffers, CBOR and MessagePack PPT under the typed benchmark schema; invalid
scheme/mode/serializer combinations fail validation. The runner validates every
RPC result and each pub/sub delivery, retains owners until cleanup and reports
payload preparation plus native-builder input/growth counters. Eighteen live
RawSocket cases with the Dart caller and CBOR WAMP envelope pass, and a focused
RPC test confirms owner disposal follows result consumption. A separate twelve
case matrix exercises typed FlatBuffers PPT across both transports and caller
implementations, but not the new runner groups. Rust tests pass 181/181; focused
Dart tests, package analysis and formatting pass.

Instrumentation is deliberately attributed narrowly: end-to-end `latency_ms`
includes preparation and response validation, but `payload_preparation_us` for
dynamic CBOR/MessagePack groups excludes later PPT serialization. Builder copy
counters exclude codec and transport copies, including TLS, WebSocket and E2EE.
See [the updated acceptance contract](../flatbuffers_performance_acceptance.md)
and [bench usage](../../packages/connectanum_bench/README.md). `bin/verify`
passes at exit 0 on 2026-10-05. No paired campaign, memory/CPU gate or performance
parity result exists. The runner stage does not accept issue #103 or the milestone.

## Session native-owned typed FlatBuffers PPT path (2026-10-05)

`NativeOwnedBuffer.asFlatBuffersPptPayload()` can be passed to
`Session.callLazyPayload` or `Session.publishLazyPayload` with matching opaque
FlatBuffers PPT options. Once a native FlatBuffers session is established, the
CALL/PUBLISH fast path accepts only a nonempty non-`wamp` PPT scheme, the
`flatbuffers` application serializer, and no PPT cipher or key ID. It confirms
that the exact packed byte view still belongs to a frozen `NativeOwnedBuffer`,
then emits a control-only FlatBuffers envelope and composes the encoded
application bytes as a retained opaque frame span. `FlatBuffersSessionProfile`
preflight still runs before fast-path selection; `sendNativeFrame` validates and
commits the profile through the envelope. Other message shapes use normal
serialization.

Cycle-safe traversal follows nested `LazyMessagePayload` storage owners and
anchors. Queueing retains the native allocation through asynchronous native
frame submission, so tests dispose the caller's owner as soon as Session send
returns and still receive the correct response. RawSocket and WebSocket session
integration, a deep nested-anchor case, transparent CBOR fallback, and
control-only writer behavior pass. Ordinary Dart-backed payloads retain their
copying serializer path. This avoids passing the application bytes through a
Dart serialization buffer for eligible messages, but does not claim that later
WebSocket masking, TLS, encryption or platform output stages avoid copies. No
benchmark parity is inferred. `bin/test-fast` and `bin/verify` pass at exit 0
on functional checkpoint `f569e9b4`; the benchmark-runner follow-up passes
`bin/test-fast` and awaits full verification and fresh exact-head hosted CI.

## Native typed benchmark runner integration (2026-10-05)

For typed FlatBuffers PPT with `native_buffer` or `pre_encoded_span` construction,
the runner now uses `NativeOwnedBuffer.asFlatBuffersPptPayload()`. When the
caller is the native implementation and the WAMP envelope serializer is
FlatBuffers, eligible PPT calls use a control-only envelope and retained
application span. `dartValues`, Dart transports, other outer serializers,
transparent payloads, other PPT serializers and encrypted PPT keep the existing
serialization paths.

A live 12-case matrix covers native RawSocket RPC/pub-sub with FlatBuffers WAMP
envelopes, FlatBuffers/CBOR/MessagePack PPT and both owned construction groups;
each case runs two validated iterations. Runner tests verify that packed bytes
and the storage-owner record are the same view, ownership is live during a call,
and a rejected call still disposes the owner. Focused runner analysis, scenario
tests and the live matrix pass. Both `bin/test-fast` and `bin/verify` pass on the
current candidate, including Chrome WebAssembly and hosted consumer smoke tests.
Fresh exact-head hosted CI remains pending. This is correctness evidence only:
no timed comparisons or complete copy, CPU, memory or parity results exist, so
issue #103 stays open.

## External producer lease through a delayed native send (2026-10-05)

The external C producer fixture now emits a deterministic 15 MiB byte pattern
from its owner thread. A test peer runs in a separate Dart isolate because the
native RawSocket connect/handshake call blocks the caller isolate. It completes
the handshake, pauses reads until the native write receipt is observed pending,
then resumes and validates the complete RawSocket frame byte-for-byte. The test
asserts that the producer lease remains live during backpressure and is released
exactly once on its owner thread after write completion. The focused test passes;
`bin/test-fast` and full `bin/verify` also pass. Fresh hosted evidence for this
follow-up is pending. This supplies a real-send lifetime oracle for #97 without
closing that issue's remaining acceptance criteria.

## Native transport copy-counter follow-up (2026-10-05)

Optional C/Dart FFI snapshots count explicit Dart-to-native send copies and
WebSocket mask/coalescing payload copies. A separate Rustls counter reports
accepted plaintext input volume, not memory copies. The
benchmark aggregates active client and router process deltas; missing active
path counters fail closed. Dart-managed socket/TLS paths and mixed-serializer
transcodes remain unmeasured. Focused tests, `bin/test-fast` and full
`bin/verify` pass at exit 0, including Chrome WebAssembly, live WAMP integration
and consumer smoke checks. This is correctness evidence and partial native-path
attribution only; it establishes neither complete copy coverage nor FlatBuffers
performance parity, and issue #103 remains open.

## Dart transport-copy attribution follow-up (2026-10-05)

The Dart benchmark worker records synchronous Connectanum-owned RawSocket
framing, small-fragment coalescing, pre-handshake queue copies, and WebSocket
fragment coalescing around each workload. Those counters deliberately exclude
copies inside `dart:io`, SDK WebSocket masking, and TLS. The final report nests
client/router copy breakdowns, adds router deltas to the known-own lower bound,
and emits numeric `transport_copy_bytes` only for a complete measured cleartext
path. The paired evaluator requires the corresponding complete coverage marker
and an empty unknown-boundary list; it also rejects not-applicable transport
totals. Focused counter, aggregation, and 13 evaluator tests pass, and
`bin/test-fast` passes on this working tree. Full `bin/verify` and exact-head
hosted checks remain pending. This instrumentation does not measure Dart SDK
writes/masking, TLS or mixed-serializer transcodes and does not establish
FlatBuffers parity. Issue #103 remains open.

## Paired comparison evaluator and hosted CI correction (2026-10-05)

`tool/wamp_serializer_compare.py` now validates campaign metadata, non-overlap,
workload identity/order, complete sample/resource/copy evidence and the declared
paired metric gates. The machine-readable policy covers throughput, p95/p99
latency, CPU, allocation, GC pause, peak RSS and zero avoidable payload copies
at named optimized boundaries. Seven evaluator unit tests pass. It is an
analysis/gate tool only: it does not execute or schedule benchmarks, and there
is no campaign manifest or measured result. Unmeasured Dart-managed socket/TLS
and mixed-codec transcode paths remain blockers for the required rows.

The exact-head run for `a28e92c4` exposed two reproducible CI defects. Five
bench tests tried to load `libct_ffi.so` because the CI fast script did not pass
its just-built FFI test artifact into the package process. The two core-lazy
jobs stopped before mutation execution because source edits changed the AST
mutation identifiers while their justifications still named the old IDs. The
The fixes are committed and pushed as `f7387de0`. `bin/test-fast`, full
`bin/verify`, and source/ID inventory checks for both VM and browser targets
pass locally. Exact-head hosted CI for `f7387de0` is running; its complete
mutation campaigns remain acceptance evidence for this correction.

## WAMP process-resource attribution follow-up (2026-10-05)

The comparator previously evaluated CPU, allocations, GC pause and peak RSS
from the client worker only. A new working-tree change requires both client and
server process metric blocks, preserves them separately in JSONL and transformed
artifacts, and calculates resource ratios from the sum per operation. The
`server_process_metrics` block explicitly describes the Dart process hosting
RouterBinding and the HTTP benchmark controller, not an isolated router. Each
workload gets one throwaway warm-up operation before its server measurement
window so lazy router isolates exist before profiling starts. The collector
profiles all application isolates present when the window begins and rejects
isolate-set changes. Linux `/proc` provides process CPU ticks and 50 ms RSS
samples; those fields remain missing on other platforms, as do GC values when
the timeline fails to settle. The Rust orchestrator starts VM-service profiling
on that process when `--collect-wamp-vm-metrics` is requested. Eleven Python
evaluator tests, the Dart isolate-set tests, the Rust `http_stream` tests and a
live macOS one-workload smoke pass. The smoke confirms both process blocks and
server allocation/GC data; macOS lacks the Linux CPU/RSS fields required for
acceptance. The comparator names its RSS total `summed_sampled_peak_rss_bytes`
because client and server peaks can occur at different times. No campaign is
scheduled by the evaluator, and no FlatBuffers parity result exists. The exact
head after these working-tree changes still needs full local verification and
hosted CI.

`bin/test-fast` and full `bin/verify` now both exit 0 on 2026-10-05. Full
verification includes Chrome/WebAssembly serializer and client suites, live
FlatBuffers WAMP transport workloads, Rust benchmark tests, consumer-package
smokes and router integration suites. The paired-comparison evaluator has
eleven passing tests; the Dart VM process/isolate and Rust `http_stream` tests
also pass. The macOS workload smoke verifies collection wiring only because
Linux `/proc` CPU/RSS evidence is unavailable there. No paired measurements
have run, so issue #103 remains open and milestone parity acceptance is not met.
Exact-head CI and package publish dry-run workflows are queued for pushed
commit `f47438d4`.

## RSS sample-window race correction (2026-10-05)

The sampler previously dropped its final `/proc/<pid>/status` read when a 50 ms
timer read was still in flight. Server current RSS was also read after VM
profiling RPCs, outside the measured interval. `DartVmMetricsRssSampler.stop`
now waits for an active read, performs one final read, and returns current and
peak RSS together; repeated stops share the same result. Both client and server
process records use this snapshot before VM profiling finishes. A delayed-reader
test verifies ordering, end-boundary current RSS, maximum peak RSS and idempotent
stop. The server retains an end-of-workload `ProcessInfo` current-RSS value for
non-Linux diagnostics, while Linux rows remain missing if `/proc` cannot supply
the sampled boundary. `bin/test-fast` and `bin/verify` pass with exit 0 on the
RSS race correction; the final non-Linux diagnostic fallback also passes the
focused metrics suite and benchmark-package analysis. An 8-workload Linux arm64
serializer-matrix smoke emits numeric current/peak RSS
for both processes and all rows satisfy current <= sampled peak. It is a
640-sample wiring smoke, below the 1,000-sample acceptance floor. The same smoke retains
`transport_copy_bytes: not_measured` for Dart-managed callers; copy attribution,
the full campaign, hosted exact-head CI and every issue acceptance remain open.

## Client mutation CI repair (2026-10-28)

Hosted `40719790400` finishes with the client metadata mutation target at
93.58%, below its unchanged 95% threshold. Pause the uncommitted native wake
candidate. Reproduce the surviving mutations from its retained artifact. Add
ordinary native-message restore/retain anchor regressions and individually
justify only source-proven equivalents: strictly disabling the simple-PPT
optimization, an explicitly supplied private default, and null-byte decoder
closures that cannot install or run. Revalidate with clean/restored baselines
and neighboring controls before pushing. The new tests and proofs do not
change runtime source, ownership rules, performance gates or test thresholds.

The CI repair is pushed separately as `81f06e1f`. All 1,950 client binding tests
and 167 proof checks pass. The unexempted 49-mutation revalidation retains all
ten proposed equivalents, kills all four new ownership controls by assertions
and 22 neighbors; four are compile errors. Clean/restored baselines pass, and
its raw 57.78% score correctly fails 95%. Full hosted CI `40735216483` is queued.
The runtime remains unchanged from `66282e65` for that repair.

The separate readiness candidate passes three Rust notifier tests and three
FFI publication/shutdown tests. All 776 focused serial Dart router, native
runtime, bridge and live typed-PPT cases pass, with clean analysis. The three
long-poll live RPC deadlines fail against an unchanged old-library negative
control and pass with the candidate; normal old-library polling cases pass.
A GLM review's pre-registration lost-wake hypothesis is excluded by the
immediate initial arm/scan; generation/teardown synchronization is retained.
Record the independent pre-existing cross-isolate legacy callback crash in
research notes. Complete full verification before using hosted measurements as
acceptance; keep all earlier reports and unchanged budgets.

## Readiness verification and remaining memory findings (2026-10-28)

Full `bin/test-fast` and `bin/verify` pass on `7a5bdc76`. Production copy proof
`40736194337` passes 120 live cases, 300 inventory rows and 32 no-avoidable-copy
gates with unchanged inputs/binaries. CPU capture `40737157961` passes.
Diagnostic `40736188467` completes 90 rows with four numerical findings:
Dart-values p99 and peak RSS in every case. All throughput, CPU, allocation, GC
and p95 comparisons pass. Keep the eight-failure predecessor and every budget.
General CI `40736889265` supersedes the partial repair-only run `40735216483`.
Do not close #103/milestone or ready PR #132 before final acceptance.

Native exported views already pass their length to the SDK's external-memory
finalizer. Investigate fresh read-only memory/allocator capture `40740363467`
rather than changing ownership speculatively. A separate shared benchmark
optimization removes redundant sample-map staging without changing records,
copy counters, timing windows or resources measured. Its 20,000-sample AOT
component control emits identical JSON and reduces peak RSS about 3.2 MB;
that component does not establish transport/RSS acceptance.

The shared sample-staging change passes clean Dart analysis, all 118 focused
worker/sample cases, all 2,807 benchmark-package cases (including live typed,
encrypted and mixed-codec transports), and the 167-proof preflight. The two
edits preserve default JSON encoding and consume only JSON-decoder maps; every
sample remains present. A broader companion request reports no concrete finding,
but the exact-patch narrow retries hit output limits; do not claim those retries
completed. Re-measure the unchanged diagnostic policy on the committed candidate.

## Negotiated compact worker observations (2026-10-28)

`aa090feb` diagnostic `40743480042` retains four numerical findings after all
90 rows complete: Dart-values throughput/p95/RSS and pre-encoded RSS. All
native-buffer metrics and all CPU/allocation/GC/p99 comparisons pass. Keep both
its report and the distinct four-findings `7a5bdc76` report; do not loosen gates.

The next source candidate makes private worker observation IPC positional and
versioned. Parent requests `sample_encoding: positional_v1`; no request keeps
legacy named output. Parent accepts old named workers and rejects malformed or
unknown marked responses, with failed-process cleanup/recovery. Every one of
13 sample values survives; public JSON, copy counters, workloads and measurement
windows are unchanged. Optional zero/null and wide integer semantics reuse the
named decoder's validators. This reduces actual common process work in the
existing measurement window rather than excluding it.

The actual-method AOT component preserves the 20,000-record public JSON SHA-256,
reduces internal bytes 7,000,013→1,180,013, peak RSS 85.5–86.0→31.2 MB, and
encode/decode time 65.9–67.0→16.5–17.0 ms. These are isolated component observations.
All 125 initial focused cases and the complete 2,823-case benchmark suite pass;
two additional schema boundary tests follow. Local GLM test planning and exact
source review complete. Its null/copy-validator suggestions do not describe a
change from the named contract; source inspection and regressions verify that.
Run final full verification and fresh paired/copy evidence on the committed
candidate before acceptance. No native owner or SDK/allocator policy changes.

The full hosted client mutation target in `40736889265` now passes its unchanged
95% assertion gate. The compact IPC candidate passes 127 final focused cases,
including numeric spellings and unmarked positional-row rejection/recovery;
the complete benchmark suite passed 2,823 cases before those test-only additions.
Its final legacy producer branch delegates to the original standard JSON encoder.
Freeze this source and complete full verification plus fresh hosted evidence.

## Public HTTP observation staging (2026-10-28)

Full local verification and copy proof `40748144948` pass on `e72638be`; the
runtime checkpoint `7a5bdc76` is fully green in hosted `40736889265`. Current
`40748136642` is still running without a reported failure. Paired `40748141357`
completes 90 rows with eleven numeric findings. Keep it and both earlier
four-finding reports; no component optimization establishes acceptance.

The public report still eagerly creates a map per observation before internal
routing recursively clones map entries. Retain immutable sample models until
the existing HTTP JSON encoder instead. The relay's transfer/materialization
functions preserve plain Dart objects, and the final encoder uses toJson.
A 2,048-sample cross-isolate HTTP payload test preserves named JSON bytes; an
actual server smoke passes all nine codec/construction pairs with complete
sample fields. Initial readiness-control timeout was a private harness issue
(Dart hook prefix before READY), fixed without product changes. Run full
verification and paired diagnostics on the committed reporting candidate.

## Standard HTTP JSON byte encoding (2026-10-28)

`ebb7bff1` passes full local verification. Diagnostic `40754675709` completes
90 rows with seven numerical findings: Dart-values CPU/GC confidence/p95/RSS/
throughput, native-buffer p99 confidence and pre-encoded RSS. Keep this and all
prior reports; no point/confidence threshold or resource window is weakened.

Replace the shared HTTP string/UTF-8/Uint8List staging with standard SDK
JsonUtf8Encoder, preserving the declared Uint8List result through a checked
fallback. No SDK, GC or allocator tuning. A 20,000-sample AOT old/fused/fused/
old control preserves all 7,000,013 bytes and SHA-256 while reducing peak RSS
76.4–76.5→56.3 MB and encoding time 47.9–54.4→39.2–39.5 ms. Component only.
All 63 focused public/native HTTP cases, 167 proof checks and nine live HTTP
codec/construction combinations pass. GLM review catches a valid paired-
surrogate fixture gap; add actual lone-surrogate cases. Source/tests reject its
unchecked-cast suggestion and Qwen's incorrect map-key/error expectations.
Full local verification is running; freeze and remeasure the committed source.
All copy counts, complete observations, workloads and acceptance gates remain.

`2f92dcc7` full local verification passes, including Chrome/WebAssembly. Its
production copy proof `40759868387` passes 120 live/300 inventory/32 no-avoidable
copy checks with unchanged inputs/binaries. Paired `40759863991` completes
90 rows with seven numeric findings: Dart-values CPU/GC/p95/p99/throughput;
native-buffer and pre-encoded RSS (1.006378/1.011142). Native throughput ratios
are 1.039422/1.024165 and their CPU/allocation/GC/p95/p99 pass. Dart-values RSS
passes but throughput is 0.990235 and CPU 1.001236. No acceptance is claimed.
Preserve every prior failed report and all budgets. Capture the actual Dart-
values path in `40763175368` and fresh read-only native memory attribution in
`40763180032` before choosing a further runtime change. Keep source frozen.

## Measured native reply candidate (2026-10-28)

Current `2f92dcc7` remains the frozen production source. Hosted CI
`40759920152` has 35 successful jobs and no failures; VM coverage and client
mutation remain. Its preceding `40748136642` is entirely green. CPU capture
`40763175368` and fresh read-only native memory control `40763180032` complete.
The latter retains six process pairs with unchanged inputs, with FlatBuffers
summed peak medians 436/422 MB, CBOR 375/387 MB and MessagePack 411/457 MB.
These diagnostic process baselines remain distinct from primary acceptance.

Current perf call-chain export loses leaf instruction addresses when unwind
fails. A private reader of the original PERF_RECORD_SAMPLE layout recovers all
six PID/window sample sets exactly (1,730/4,198 FB, 1,781/3,982 MessagePack,
2,982/2,223 CBOR), with zero recorded lost samples. Preserve JIT-address-reuse
ambiguity. ELF/mapping attribution finds 315 FB versus 252 MessagePack router
leaf samples in ct_ffi, with VM/kernel work dominant. The temporary older perf
6.12 Linux container rejects the 7.0 record format; it is removed and its error
retained. No SDK, GC, allocator or measurement-window setting changed.

Reject speculative fixes: actual RawSocket normalization-copy counters are
zero for all codecs; bounded prefix coalescing occurs on every typed send;
Bytes cloning is shared ownership, not a payload memcpy. Args/binary duplicate
exports concern INVOCATION, not these RESULT RPC cases. The completed local
judge suggests those unsupported possibilities; source and measurements
exclude them. Private actual-code AOT payload roundtrip is FB 48–51 us,
MessagePack 56–57 us. The Dart envelope writer is only about 1.5 us. Neither
component is acceptance.

A private native prototype in `/tmp/connectanum-simple-result-prototype`
uses the pinned generated Result/Message builders for exact two-string PPT
RESULT dictionaries, retaining the original opaque payload. Its final version
uses the standard serde_cbor writer with exact bounded staging capacity; no
retained-metadata hint or new public API is needed. It preserves all dictionary
content and fallback for extended controls, typed mismatches, ordinary args or
kwargs. Bounds cover IDs, metadata, whole frame and vector alignment. Actual
old/new/new/old 200,000-iteration component observations fall from 256.8–266.6
to 47.0–48.8 ms and from 18/1,969 to 6/458 allocator requests/bytes per reply.
Both outputs have the same length and decode identically in native and Dart,
including all 65,536 bytes; output bytes differ in legal table placement.

Before adopting, complete the current pre-change `bin/test-fast`, add native
regressions for full logical equivalence against the original generic writer,
UTF-8/CBOR length transitions, ID/frame/metadata bounds, extended/invalid
controls and payload lifetime/pointer identity. Use the existing CodecAllocator
and record every metadata vector/growth copy, including failed fast attempts.
Qwen test planning completes; correct its false expectations that fallback
emits no frame, cloned Bytes changes its pointer, and the inclusive frame limit
must reject equality. Keep whitespace and unknown nonempty schemes intact.
Run focused native tests, current-library Dart interoperability and full
verification, then freeze and rerun paired/copy evidence. No acceptance gates
or workloads change, and #103/milestone stay open until full acceptance.

The pre-change `bin/test-fast` passes, as does complete hosted `40759920152`
on `2f92dcc7`. The private prototype first exposes a missing generated-module
production gate and missing private test fixtures; copy fixtures and enable the
already-pinned generated module without editing it. The first new assertions
incorrectly assumed strict serde-value identity and that the old writer accepts
an exactly 64MiB physical frame; source inspection shows normalization and an
additional conservative estimate. Preserve both behaviors. Derive that budget
from the actual pinned Result/Message table sizes, and independently discover
the generic boundary in the regression rather than mirroring the formula.
All ten focused native encoder tests then pass on the adopted source. Full
verification is running in `/tmp/connectanum-simple-result-full-verify.log`.
The completed first GLM review's allocator uncertainty is excluded by source
instrumentation and the growth regression; add an explicit checked u32 vector
length conversion as well. The final exact-patch review is running. No acceptance
claim or gate/workload changes. The generated module remains private to ct_core.

The final exact-patch GLM review completes with no concrete findings. Its
residual dead-code comment misplaces a generated-module attribute; handwritten
helper code is not exempted. Native source now has the explicit checked vector
length and schema-derived generic budget. Retain prior private failed setup/
assertion logs. Full verification and exact-source hosted measurements remain
required before acceptance; no claim follows from the component improvement.
