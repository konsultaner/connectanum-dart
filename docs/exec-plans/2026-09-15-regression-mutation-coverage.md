# Regression And Mutation Coverage

Status: active
Started: 2026-09-15
Baseline: `8248ad62` (PR #92 merged into master as `f3323e48`)

## Objective

The operator's next priority is near-complete regression testing and strong
mutation testing. Target at least 98% executable-line coverage per shipped
component/runtime and 95% killed viable mutations. Investigate every surviving
security-critical mutation. These targets are not current achievements.

This plan takes execution priority over the incomplete component security audit
and beta.6 publication. Preserve their evidence and resume them after this work;
PR #92 merged on 2026-09-15; publication is outside this coverage goal.

## Baseline And Scope

Hosted CI `34951191887` reports 33,515/40,031 Dart VM lines (83.72%).

| Package | Covered / measured lines | Coverage |
| --- | --- | --- |
| connectanum_core | 6,354 / 7,211 | 88.12% |
| connectanum_client | 7,638 / 9,234 | 82.72% |
| connectanum_router | 15,836 / 19,268 | 82.19% |
| connectanum_mcp | 1,480 / 1,613 | 91.75% |
| connectanum_auth_server | 421 / 455 | 92.53% |
| connectanum_bench | 1,786 / 2,250 | 79.38% |

The compatibility facade is exports only. The VM report does not measure Rust,
browser-only implementations, package hooks/executables, or standalone consumer
applications. Report these scopes separately; never treat missing data as 100%.
There is no existing mutation-testing gate.

## Work And Completion Gates

- [x] Establish reproducible per-file/package reports, explicit missing-source
  inventory, and regression floors. Keep the 98% target distinct from floors.
- [ ] Measure Rust with LLVM coverage and run cargo-mutants on native protocol,
  serializer, ownership, resource and transport paths.
- [x] Add Dart AST mutation generation and isolated execution with verified clean
  baselines, reproducible inventory, bounded children and machine-readable results.
  Compile errors, crashes and timeouts must not count as assertion kills.
- [ ] Close authorization/authentication/lifecycle gaps using independent expected
  outcomes, adversarial inputs, concurrency and cleanup assertions.
- [ ] Close protocol/serializer, session, RPC/pubsub/meta, MCP/HTTP, native FFI,
  configuration, packaging and benchmark-tool gaps.
- [ ] Add browser coverage and retain VM/browser results separately and merged.
- [ ] Measure and close standalone application regression/mutation gaps.
- [ ] Enforce measured floors in CI and publish mutation inventories/results.
- [ ] Reach the targets across the complete scope, with justified equivalent
  mutations individually recorded; no blanket exclusions or sample-wide claims.
- [ ] Run `bin/verify`, review the patch and inspect hosted evidence after push.

## Tooling Decisions

Use the Dart analyzer AST, already in the test dependency graph, for mutations.
The evaluated dart_mutant revision
`2ceb58eb1ba9e17598ffe042a07c8caa3ac7ba9e` counts all nonzero test exits as kills
and modifies shared source during parallel runs. Those behaviors cannot establish
the requested test quality. Use isolated workspace copies and classify Dart's
machine test events instead. See the upstream
[runner](https://github.com/Nimblesite/dart_mutant/blob/2ceb58eb1ba9e17598ffe042a07c8caa3ac7ba9e/src/runner/mod.rs).
Use [cargo-mutants](https://mutants.rs/) for Rust and retain its unviable, missed,
caught and timed-out outcomes separately.

## Verification Notes

### Work194 Synchronous OAuth Deadlines And Measured FFI Fixture

- Push verified Work193 as b0a9a9e0. PR93 stays draft; exact-head CI/package,
  native35590095042, router35590096360 and profile35590098675 dry-runs remain
  queued. Strict hosted audit exits1 for pending evidence. No release or merge.
- Fast194 passes with unchanged inputs before promotion. Add39 regressions for
  real synchronous deadline expiry in callback/setup/close/body, late future
  errors, generic callback exceptions and client ownership. The old source
  fails39 assertions. Preserve sanitized generic errors and specific OAuth
  exception identity, abort at most once and observe futures when deadline
  calculation throws before timeout attaches. The84-case focused baseline and
  restored baseline pass; six selected controls fail33/12/12/3/6/33 assertions
  with0 runtime errors. Full isolated MCP suite passes2430 tests. No full
  mutation-score claim follows from these selected diagnostics.
- Include metadata_projection in native FFI coverage collection exactly once.
  The selection test fails before and passes after; the tooling suite passes
  with its opt-in real-instrumentation fixture skipped. Analysis/formatting and
  Verify194 pass, including Chrome/WASM. Supervisor3485 completes real native194
  FFI collection including the metadata fixture with matching input hashes.
  Identical native193-unit/native194-FFI source scopes allow a combined report:
  ct_core8864/10064 (88.08%), ct_ffi5204/5798 (89.76%). Unmeasured sources stay
  explicit. Fast195/session86647 is the next sole native owner before promotion.
- Discovery191 finishes453 mutants; independent audit retains348/366=95.08%
  assertion-backed detections,16 survivors,2 timeouts,87 compile exclusions,
  no equivalence waivers. Strict gate remains failed on timeouts. OAuth192 is
  still live from its original snapshot. Do not duplicate its campaign.
- SDK inspection disproves companion suggestions about callback-before-await,
  Future.ignore error handling and shared retry state; source and regression
  oracles cover those contracts. Separately, SDK abort after response completion
  is a no-op. Six new isolated body-subscription cancellation assertions expose
  this further leak. Its isolated candidate passes120 focused and2466 MCP tests,
  including slow/error cleanup, oversized responses and whole-body deadlines.
  Four selected controls yield36/12/36/36 assertions,0 errors, with passing
  original/restored baselines. It is not promoted or included in Verify194.
  A second isolated discovery fixture reproduces4 unobserved late close/body
  future assertions against unchanged production; no discovery fix is claimed.

### Work193 Lossless Nullable Native Metadata

- Push verified Work192 as c40129e8. Verify192, native192 FFI collection and all
  frozen input checks pass. Matching source scopes (only trailing JSON newline
  differs) and newline-safe LCOV union yield ct_core8866/10064 (88.10%) and
  ct_ffi5078/5798 (87.58%),91 additional FFI lines over Native151 combined.
  Unmeasured sources remain listed. Exact-head hosted chains stay queued and
  the strict audit exits1 for pending evidence; no green hosted claim.
- Fast193 passes with unchanged inputs. Real FFI tests produce42 assertion
  failures:39 explicit false values become null across13 nullable fields and
  three serializers, plus3 incorrect direct-binding flags.87 controls pass.
  Preserve the earlier wrong-library run as129 infrastructure errors, not
  assertion evidence. Native parser/projection tests produce2 assertions before
  the fix. All before/after logs and input/library hashes are retained.
- Fix the13 nullable Some(false) branches to reject direct projection, keeping
  the existing lossless details fallback and payload slices. No ABI layout or
  flag change. True/absent remain fast; nonnullable YIELD progress stays false.
  All129 real-FFI tests and10 native matrix tests pass afterward, no skips.
  Tests assert tri-state values, lazy payload after release, original metadata,
  numeric/string type boundaries, routing filters, unknown/nonstring keys and
  mixed flags. Targeted analysis and formatting pass.
- Thirteen independent false-branch fault controls produce assertion failures,
  with passing original/restored baselines and the same ten-test inventory.
  These are diagnostic controls, not a complete native mutation score.
  Local companion concerns were checked against the actual fixtures, unchanged
  ABI declaration, nullable Dart fields and successful real-FFI matrix; no
  substantiated remaining finding. A bounded GLM review supports the fallback
  approach; its earlier token-limited attempt is not review evidence.
- Verify193 passes including Chrome/WASM. Supervisor3405 completes serial unit
  and FFI coverage with matching input hashes after every stage. Matching-scope
  native193 combined coverage measures ct_core8864/10064 (88.08%) and
  ct_ffi5203/5798 (89.74%),125 additional FFI lines over Native192 combined.
  Unmeasured sources remain listed. The instrumented FFI collector has not yet
  selected the new metadata fixture; its129 cases pass in full verification.
  Metadata changes are verified for commit. Discovery191 and OAuth192 continue
  from their own unchanged snapshots; do not duplicate them.
- While canonical inputs remain frozen, investigate the previous OAuth deadline
  survivor in an isolated candidate with the same production source hash. Three
  public exchange/refresh/revocation cases synchronously consume the deadline in
  onRequestOpened and reproduce missing aborts through assertions, no other
  errors. A candidate local abort-once helper handles McpOAuthTokenException
  cleanup while preserving callback exception identity. Expanded stage-boundary
  cases reproduce12 unobserved-future assertions and3 post-deadline dispatch
  assertions. The candidate guards dispatch and observes futures when synchronous
  deadline checks throw;72 focused tests and analysis pass. This is NOT canonical
  or in Verify193. Callback errors, full MCP tests and fault controls remain.
  No equivalence waiver or new full mutation score is claimed.

### Work192 Native Forwarding And OAuth Timeout Oracles

- Push the verified Work191 increment as178ca8f3; draftPR93 remains unmerged.
  Exact-head CI/package/native/router/profile checks are queued; strict audit
  exits1 for incomplete hosted evidence. Fast192/session81134 passes and its
  frozen source/test/config hashes match before promotion.
- Add eight native tests spanning three encodings, four payload shapes,
  disclosure metadata, independent progress flags, results/errors, malformed
  PPT fields, unsupported encodings and external-buffer range/null boundaries.
  Assert success and complete independently decoded WAMP frames, exact payload
  pointer/length reuse, and output ownership after dropping source messages.
  Six diagnostic fault injections detect1/1/1/1/2/1 assertion failures, no other
  failures; original/restored baselines pass. No complete mutation score inferred.
- Native192/session64804 exits0 with matching canonical inputs. The new test
  module is AST-classified test-only; production denominator remains5798 lines.
  ct_ffi unit-only coverage rises4658->4749 lines (80.34%->81.91%); ct_core is
  8800/10064 (87.44%), with two previously hit listener-loop branches unhit.
  A fresh Dart-FFI measurement is required before a new combined native score.
- Promote the previously validated OAuth nullable-header fixture correction.
  Complete OAuth192/session53855 is live with413 generated mutants; its first
  invocation rejected an incorrect target name before starting any campaign,
  and that CLI error log is retained separately. Discovery191/session66371 is
  still live from its own unchanged snapshot. Do not duplicate either campaign.
- Formatting and the targeted native suite pass. Verify192/session2955 completes
  with exit0, including Chrome/WASM, and its frozen input hashes match.
  Supervisor3330 is terminal and starts native192-ffi-current/session7464 as the
  sole native owner. Preserve /tmp/connectanum-coverage192-inputs.sha256 until
  collection finishes. No new combined coverage, mutation gate, or hosted-green
  claim yet; the implementation increment is locally verified.

### Work191 Shutdown Admission And Completed OAuth Measurement

- VM189 exits0 and frozen hashes match: overall92.30%, client93.35%, router89.22%,
  other package percentages unchanged. Keep59 unmeasured library files and12
  unmeasured packaging files visible; packaging765/787 (97.20%). OAuth token
  exchange480/483 (99.38%) is module-only evidence. Fast190 exits0 and hashes match.
- Four assertions reproduce HTTP application work admitted during delayed file
  cleanup after disposal starts. Promote a binding-wide disposed latch and early
  HTTP503 rejection with finally-based handshake release. Eight new tests cover
  existing/new connections, cancellation errors and rejection-send failures.
  The first post-fix fixture incorrectly indexed fake responses by handshake
  instead of connection ID; preserve that failure log, then correct the fixture.
  All23 focused cleanup/admission cases and285 complete router runtime cases pass.
- Four explicit fault controls detect8/8/8/4 assertions, no other errors, with
  passing original/restored baselines and frozen source/test hashes. No full
  mutation score inferred. Promote30 discovery tests with matching candidate hash
  and a passing canonical run; full453-mutant Discovery191/session66371 is live.
- OAuth188 finishes315/326 assertion-backed (96.63% raw/adjusted),9 survivors,
  2 timeouts,87 compile errors and passing baselines. Independent audit exits0.
  The strict gate fails for timeouts despite meeting the numerical threshold.
  Both timeouts expose a null dereference in a test HTTP handler when Basic
  authorization is omitted. Isolated nullable capture plus post-response assertion
  retains the credential checks. Full-MCP selected controls/session26478 finish
  with24 assertion-only failures and173 assertions/14 runtime errors respectively,
  no timeouts, and passing original/restored baselines. The correction remains
  isolated; historical timeouts stay uncredited and no equivalent waiver is made.
- Targeted analysis/formatting pass. Verify191/session69945 completes with exit0,
  including Chrome/WASM, and the final frozen input hashes match.
  Pending OAuth fixture correction is not canonical or in the live campaigns.
  Implementation is ready for a verified feature-branch commit; PR93 stays draft
  at f44fdabd and hosted jobs remain queued. No release, merge or version change.

### Work190 Verified Cleanup And Discovery Boundary Oracles

- Verify189 exits0 including Chrome/WASM and its frozen source/test/config hashes
  match. Supervisor3151 is terminal and starts VM189/session96503, the sole native
  owner. Keep canonical inputs frozen until collection and its hash check finish.
- The verified bundle contains the router ownership/disposal fixes,15 file cleanup
  regressions and203 OAuth boundary/persistence tests. OAuth188/session69980 stays
  live on its original frozen snapshot; no duplicate full campaign is started.
- A separate30-case discovery fixture targets explicit non-default resource-port
  equality, exact array diagnostics, successful fallback without abort, trailing
  separators, quoted escapes and malformed-field recovery. The2387-case full
  candidate MCP suite and targeted analysis/format pass. Initial unused fake
  constructor-parameter warning is corrected; preserve the original fixture.
- Final29-outcome focused controls detect13 assertion-only failures, with16
  survivors, original/restored baselines0 and input hashes retained. Prior full
  timeouts remain uncredited; no new complete score or equivalence waiver.
  This fixture remains isolated until VM189 releases canonical inputs.
- DraftPR93 and strict hosted deployment evidence remain pending. No merge,
  version change or publication. Recovery: coverage184-probes/WORK190.md.

### Work189 Asynchronous File Cancellation Completion

- Verify188 completes with exit 0 including Chrome/WASM; canonical source, test
  and configuration hashes match the frozen manifest.
- A controlled delayed onCancel reproduces early disposal as one assertion,
  without timeout or error-only evidence. Preserve the pre-fix fixture and log.
- Candidate follow-up retains active file readers through cancellation, shares
  one cancellation future across sender/disposal, joins cleanup during disposal,
  and propagates the first cancellation error after other resources are closed.
  Four delayed/concurrent success/error cases pass. Fast189/session29013 and its
  frozen-input check pass before promotion. All 277 tests in the candidate router
  runtime test file pass, including the final 15 file-response cleanup cases.
- Four explicit cancellation controls fail assertions only (4/4/4/2), without
  test errors or timeouts; original/restored baselines pass and hashes match the
  promoted files. No complete mutation score is inferred from these controls.
- Canonical follow-up is promoted; targeted analysis/formatting pass. Verify189,
  session1178, is the sole native owner. Keep canonical inputs frozen against
  /tmp/connectanum-coverage189-inputs.sha256 until verification and any subsequent
  measurement finish. Supervisor3151 starts VM/packaging collection in vm189-current
  only after Verify189 exits0 and its input hashes match. OAuth188/session69980 remains live on its earlier frozen
  target snapshot; do not duplicate or alter it. Implementation stays uncommitted
  pending verification; no new global coverage result or green hosted claim.

### Work188 OAuth Mutation Oracles And Router File Ownership

- Work186 verification completes and8680a025 is pushed to the coverage branch.
  Fast188/session5284 passes with matching pre-promotion input hashes.
- Add176 OAuth endpoint validation/response cases and27 persisted-state cases.
  Assert exact preflight/response errors, URI/ASCII boundaries, inclusive byte
  limits, scope restriction, zero expiry, nested JSON ownership and diagnostic
  identity. Full candidate MCP2357 tests and client analysis pass. Selected
  controls detect41 validator,10 persistence and6 response faults through
  assertions only, with passing original/restored baselines; no full score is
  inferred. OAuth188/session69980 runs all413 generated mutants on the new frozen
  target snapshot. An earlier attempt from a git-ignored candidate failed before
  dependency resolution/inventory; preserve it but do not count it as a campaign.
- Router file-response tests reproduce five premature-handshake-release assertions
  and a separate observer-related stream leak. WAMP onDone must not complete the
  pending HTTP call while the asynchronous file response still owns its handshake.
  Add per-response ownership, unconditional finalization, cancellable file reading
  and disposal guards. Dispose all pending HTTP calls before returning; continue
  cleanup after observer exceptions and then rethrow the first captured error.
- Eleven file/disposal regressions pass, including two pending streams with
  throwing cleanup observers. Full router candidate273 tests pass before the
  final additional cancellation-completion assertion/barrier; final focused and
  fault-control baselines pass. Six explicit controls are assertion-backed:
  five assertion-only, one mixed. The earlier premature-completion control
  timed out in a fixture wait and remains uncredited; an explicit event-loop
  barrier now tests the WAMP onDone ordering before waiting for the file reader.
- Canonical source/tests match the candidate and targeted analysis/format pass.
  Verify188/session68096 is live as sole native owner, with source/test/config
  hashes in /tmp/connectanum-coverage188-inputs.sha256. Keep inputs frozen until
  terminal; do not commit the new changes before full verification passes.
- Discovery184 completes and independently audits337/366 (92.08%) assertion
  detections with26 survivors,2 timeouts,1 error-only outcome and87 compile errors;
  both baselines pass and95% remains unmet. Exact8680a025 hosted checks remain
  queued. Native35573674944 and router35573677301 use dry_run=true; profile
  35573679939 is requested once. Strict audit exits1 for incomplete evidence and
  unprotected feature branch. PR93 stays draft; no releases/protection changes.
- Preserve setup failures: response fixture MIME handling initially omitted UTF-8
  encoding and two expectations used the wrong size-limit wording; final fixtures
  encode bytes explicitly and use the verified diagnostics. A new router test
  initially omitted the required response status, then compiles/passes after the
  fixture correction. Local companion suggestions are advisory: retain the
  existing scopes key for empty persisted scopes and inclusive byte-limit
  semantics. GLM judge timed out without a response; Gemma lifetime/race claims
  were checked against source and deterministic disposal controls rather than
  accepted as facts. Full recovery is in coverage184-probes/WORK188.md.

### Work186 OAuth Late-Open Ownership And Measured Floors

- VM185/session67136 completes with exit0 and matching source/test/config hashes.
  Full VM coverage is auth100%, bench99.36%, client93.32%, core94.34%, MCP96.13%,
  router89.09%, overall92.23%;59 library sources remain unmeasured. Packaging
  remains765/787 (97.20%) with12 unmeasured sources. These are the pre-fix inputs.
- Fast186/session47711 passes with unchanged pinned inputs. Promote a separate
  opening observer in _postOAuthForm: Future.timeout does not cancel postUrl,
  so late requests must be aborted without sending credentials or invoking
  owner callbacks. Keep completion state local to each operation and close only
  internally created clients.45 fakeAsync cases cover all three public OAuth
  operations, owned/borrowed clients, late success/error, on-time success,
  owner rejection, close/body deadlines and shared-client retry isolation.
  Original code fails9 assertions only. Candidate full MCP suite2154 tests and
  analysis pass. Four explicit cleanup fault controls fail assertions only,
  with clean/restored baselines; they are not a complete mutation score.
- Strengthen49 revocation regressions with exact preflight diagnostics, zero
  network/owner-hook side effects, and positive internal-space header delivery.
  Raise benchmark package and token-exchange module floors to98%. The new policy
  contract fails first, then all20 policy tests pass and actual VM185 data passes
  the raised floors. Earlier42-case candidate collection measures478/483 token
  module lines (98.96%); do not treat this as package-wide or final runtime coverage.
- OAuth184 completes and independently audits203/322 (63.04%) assertion-backed
  detections,85 survivors,2 timeouts,32 error-only outcomes and87 compile errors.
  Both baselines pass; the95% gate fails. Preserve its old snapshot.117 selected
  survivor/error-only controls using the strengthened fixture finish with46
  assertion-only,2 mixed,2 error-only and67 survivors; only48 have assertion
  evidence. These controls do not replace a full campaign. Discovery184 completes
  at337/366 (92.08%) assertion-backed,26 survivors,2 timeouts,1 error-only outcome
  and87 compile errors excluded. Original/restored baselines pass;95% is not met.
  Full Verify186/session15492 passes after promotion, including Chrome/WASM,
  with matching frozen source/test/config hashes. Canonical MCP2154 tests and
  tooling92 tests (one conditional skip) pass as well.
- PR93 body now reflects pushed07f11c91. Exact-head native35570568032 and
  router35570570370 explicitly use dry_run=true; WAMP profile35570572639 is also
  requested once. CI/package/dry-run checks are queued. Read-only strict audit
  exits1 for incomplete evidence and the unprotected feature branch, not test
  failures. Do not merge, publish, change versions or change protections.
- Retain failed setup attempts: the first isolated command omitted -p vm and
  incorrectly selected Chrome for IO-only tests; explicit VM passes. An initial
  fixture assumed access-token revocation instead of the API's refresh-token
  default. Getter/setter overrides resolve two Dart test-double lints. Qwen's
  review exceeded its output cap; completed Gemma suggestions were independently
  checked against the existing all-exit finally and typed-error behavior.
  Recovery and exact logs/hashes are in coverage184-probes/WORK186.md.

### Work185 Revocation Oracles And HTTP Decoder Verification

- Fast185/session16041 completes with exit0 and matching pinned inputs. It
  includes the full benchmark suite with the pending streaming decoder fix.
  Promote49 OAuth revocation/refresh/expiry/diagnostic regressions afterward.
  An isolated control run reproduces all14 selected completed survivors from
  the running OAuth campaign as assertion-only failures, with no other errors
  and passing original/restored baselines. The first control version had12
  assertion-only and2 mixed detections; synchronous diagnostic rendering now
  has an explicit returnsNormally assertion, and the success helper does not
  render an unexpected exception while deciding whether it was rejected.
  Deadline/socket/unrelated errors still propagate and have direct helper tests.
- Six additional form cases cover2/3/4-byte Unicode values with split/unsplit
  input and valid recovery. The initial expectation that raw non-ASCII form
  components were accepted was wrong; SDK Uri._uriDecode rejects them. Retain
  those six assertion failures and test400 for raw fields and200 for the proper
  percent-encoded equivalents, without changing production behavior.
- Verify185/session80102 was deliberately terminated (exit143) before the
  fixture correction. Supervisor2926 is terminal and never started coverage.
  Final focused verification passes2146 tests with zero errors. Final-v2 input
  hashes are pinned. Verify185-v2/session83352 completes with exit0, including
  Chrome/WASM, and final-v2 input checks pass. Supervisor2933 is terminal and
  starts VM185/session67136, the sole native owner. Preserve canonical inputs.
  Fresh canonical MCP-only collection passes2109 tests and measures token
  exchange471/477 (98.74%). No competing native run or mutation snapshot edits.
  Full98%/95% scope remains open.
- An isolated fakeAsync late-open probe reproduces four assertion failures
  among eight refresh/revocation ownership/failure cases, with no other errors.
  Unlike discovery, token exchange leaves a late-opened request unaborted after
  its deadline. A separate request observer gated by operation completion fixes
  all eight cases without closing borrowed clients, sending credentials or
  invoking late owner callbacks. This candidate is not canonical; full-suite
  validation and promotion must wait for the current measurement's frozen input
  boundary. Evidence is retained in coverage184-probes and the late-open logs.
- Completed Gemma reviews were checked against source and tests: the claim that
  a typed-only catch swallows SocketException is false, and transport-interruption
  tests protect the HTTP error path. Exact diagnostic field rendering is an
  intentional observable contract. Qwen requests exceeded their output limits;
  GLM independently refused connections. No incomplete review is claimed as done.

### Work184 HTTP Fallback, OAuth Persistence And Challenge Lists

- Fast182 finishes with exit0 and pinned inputs match. Promote the HTTP fallback
  ownership fix after reproducing four canonical assertion failures. All144 HTTP
  regressions pass, including64 new cases. The complete HTTP mutation inventory
  retains native integration and adds the new suite with a fail-first guard.
- Add114 independent versioned OAuth token-grant persistence tests, covering
  malformed state, identity/resource binding, expiry, nested ownership, valid
  JSON extensions and secret-redacted diagnostics. A nullable extension fixture
  initially failed before production because Dart inferred a non-nullable map;
  explicitly typing that map fixes the fixture. Full MCP tests then pass1919.
  Focused token-exchange coverage is431/477 (90.36%), not package-wide coverage.
  A new complete-source token-exchange mutation target retains the95% default.
- Discovery178 finishes317/360 assertion detections (88.06% raw/adjusted), with
  138 assertion-only and179 mixed detections,30 survivors,2 timeouts,11 error-only
  detections and87 compile errors. Both baselines and independent audit pass;
  the gate fails. The separate118-case boundary probe detects14 of43 selected
  prior non-assertion outcomes with assertions only;27 survive and2 time out.
  These diagnostics are not a complete score or equivalent-mutant waiver.
- Challenge-list regression research uses
  [RFC9110 section11.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-11.3)
  and [section11.6.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-11.6.1).
  The generic challenge syntax permits an auth scheme without parameters, and
  the list syntax permits empty members. A bare unknown scheme must not prevent
  discovery of a later Bearer challenge. Empty parameter-list entries must not
  discard resource metadata. The23-case fixture reproduces17 assertion failures
  before fixing cursor advancement and empty-member handling. All2060 MCP tests
  pass in a package-shaped candidate with clean analysis; canonical MCP/HTTP
  focused verification passes2204 tests after promotion. This does not claim
  complete support for every authentication scheme's credential grammar.
- Both full Verify184 attempts exit1 on an HTTP connection-close error; the
  second reproduces it in the new500-cycle streaming/recovery regression.
  Cell2865 is terminal and never started VM184. SDK inspection identifies
  Stream.join cancelOnError cancelling the HTTP parser's incoming stream before
  the malformed response completes. The pending fix uses a chunked UTF-8
  decoder and deferred format error while draining the request, without a
  second whole-body byte buffer. Its focused suites pass, including genuine
  interrupted-body error propagation. Preserve both failed logs; no retry
  suppression or broad exception swallowing is used. Fast185/session16041 is
  the sole native owner before promotion and a fresh Verify/measurement.
- The additional35-case isolated revocation/refresh probe passes2095 complete
  MCP tests with zero errors. It asserts exact forms/client authentication,
  response validation, secret redaction, preflight rejection and grant ownership.
  Token-exchange module coverage is471/477 (98.74%), not a package-wide score.
  Its helper preserves deadline/transport errors instead of claiming mutation
  assertion credit for them. Neither running campaign contains this probe.
- Discovery184/session79866 is a new complete campaign for the final snapshot.
  OAuth184/session7112 has409 generated mutants on the earlier1919-test snapshot,
  before the parser additions. Neither has a final score yet. Keep snapshots
  separate and all source/tests frozen for native verification/measurement.
  Local Qwen advice was checked against source; unsupported scope/expiry claims
  were rejected. HTTP/parser review attempts exceeded their output limits and
  are not completed reviews; the independent GLM backend refused connections.
  No merge, release, version change, threshold reduction or new waiver occurred.

### Work182 Verified Browser Gate And HTTP Transition Reproducers

- Verify181/session31694 completes with exit0, including Chrome/WASM. The
  final-v2 source/test/config hashes match. Terminal supervisor2738 starts full
  VM/packaging coverage/session54817; it is the sole native owner. Keep its
  inputs frozen. Discovery178/session81842 continues from its separate snapshot.
- WebSocket181 finishes50/54 raw assertion detections (92.59%) and50/50 adjusted
  (100%) after the four existing individual source-pinned equivalences. Nine
  compile errors are excluded;39 assertion-only and11 mixed detections have
  explicit assertions, with zero error-only/timeout credit and no remaining
  non-equivalent survivors. Original/restored baselines and independent audit
  pass, and all production/test/support hashes match canonical. This target
  passes95%; it does not establish client-wide/all-runtime completion.
- An isolated public API fixture adds64 HTTP event metadata, explicit progress,
  malformed text, zero/timing bounds, final-only fallback and late-chunk cases.
  Four assertions reproduce duplicated first-write callbacks after fallback and
  mutable-header capture in fallback responses. The five-line candidate fix
  uses the parent stream's guarded notification methods and immutable headers.
  All144 new/existing focused tests pass without loading a native library.
  Its original attempt to call a library-private copyWith extension was a
  fixture compile error, not a product failure; the final fixture uses respond.
- Retain coverage182-probes source/tests/control reports and raw logs. HTTP
  candidate changes are not yet canonical and are excluded from Verify181/VM181
  attribution. Promote only after the current native measurement releases and
  a fresh Fast gate. Full component/native/application coverage remains open.
- The verified increment is committed/pushed as08a38c01 and PR93 is updated.
  Supervisor2777 owns measurement54817 and queues Fast182 only after successful
  coverage and pinned input checks. Final21 selected HTTP controls produce19
  assertion-backed detections (18 assertion-only, one mixed), one uncredited
  timeout and one unwaived exact-timestamp survivor; all144 candidate cases pass.
  Exact-head hosted chains remain queued; strict audit exits1 for incomplete
  hosted evidence and an unprotected feature branch. No protection changes.
- VM181 library formatting completes: auth455/455, bench2318/2333,
  client8736/9411, core6837/7247, MCP3775/3927 and router17266/19391. There
  remain59 unmeasured library files. Packaging completes765/787 (97.20%) with12
  unmeasured sources; coverage and final input checks pass. Terminal2777 starts
  Fast182/session66476 as the sole native user. Router's one-line difference is
  internal session line83, not a production edit; preserve the fresh measurement.

### Work181 Browser Buffering And Snapshot Ownership

- Real WebSocket MessagePack/CBOR reproducers prove that a frame arriving during
  an earlier Blob decode is lost by the direct DOM EventStream.asyncMap path.
  Stream.multi buffers input before decoding, retains broadcast semantics and
  cancels the DOM listener when the subscription is cancelled. All56 cases pass
  on JS/WASM, including pause/relisten, pending-Blob cancellation, ordering and
  per-attempt isolation. Removing the fix fails two real-network assertions on
  each compiler. The initial WASM fixture raced a second native Blob read; the
  final independent read-completion barrier fixes the fixture, not production.
- Fresh complete selected-browser inventory reports client2703/2785 (97.06%) and
  core7424/7695 (96.48%); core3988/client2622 tests pass. WebSocket105/105 mapped
  lines does not replace package/runtime targets. All162 missing library sources
  remain visible, and WASM has no line-coverage measurement. Frozen input hashes
  pass. The full WebSocket181 run has63 mutants and four individual source-pinned
  equivalents for unused browser certificate-flag defaults; IO/native TLS is
  explicitly outside those proofs. No complete new mutation score is claimed.
- Native HTTP172 finishes at77/175 assertion detections (44%):275 generated,
  100 compile errors,62 survivors,23 timeouts,71 assertion-only/6 mixed/13
  error-only detections. Original/restored baselines and independent audit pass;
  the95% gate fails. New54 HTTP snapshot cases cover deep header immutability,
  case-insensitive repeated overrides, body-view ownership, optional metadata
  and malformed representations. All11 selected exact survivors fail assertions
  only, with clean/restored baselines. This is not a new complete HTTP score.
- Fast175 passes with frozen canonical hashes. The accumulated candidate is now
  promoted with Work174's late benchmark-session cleanup fix and17 diagnostics.
  All71 newly promoted HTTP/benchmark tests pass. Both complete mutation targets
  register/hash their new tests; the old exact HTTP inventory expectation first
  fails and is updated to retain the larger inventory. Browser integration
  contracts are wired into both Fast and Verify. All71 runner contracts pass
  (one conditional skip). A new import guard initially rejected Dart's valid
  line wrapping; its whitespace-tolerant form preserves the required import
  and registration. The first Verify was deliberately stopped before that edit
  and is not passing evidence. Verify181/session9697 then passes Rust but fails
  a second exact benchmark inventory guard missing the new suite. The expected
  set is expanded, not weakened, before a fresh full run. Implementation
  commit/push remain pending.
- All74 verification-script contracts and all4 generator contracts subsequently
  pass. Cell2738 now owns final Verify181/session31694 and queues full VM plus
  packaging coverage only after its success and final-v2 input checks. Poll the
  supervisor, not its child, and do not start another native user. Source/test
  inputs stay frozen; docs bookkeeping may be bundled with the verified code.
- Recovery: coverage181-probes contains candidate patch/archive/manifests, real
  network controls, raw logs, HTTP diagnostics/audit and the promotion patch.
  WebSocket181/session88283 and discovery178/session81842 are live in separate
  frozen clones. Cell2450/cell2596 are terminal; no duplicate native campaign.
  No version/publication/merge change or all-runtime completion is claimed.

### Work179 Independent Serializer Wire And Fragment Assertions

- A separate candidate retains all Work178 changes and adds558 inbound metadata
  and78 PPT fragment tests. JSON/MessagePack/CBOR wire fixtures are encoded
  independently; assertions cover six message types, optional metadata, malformed
  field types, recovery, isolation, retained-byte precedence and guarded buffer
  views. The first probe's nine failures were incorrect test assumptions about
  nullable empty CALL/PUBLISH/YIELD options, not production bugs; explicit
  regressions now preserve that existing contract.
- Full core VM3942 and JavaScript3988 tests pass, as do636 focused WASM tests and
  the2753-test serializer mutation wrapper. One fail-first integration assertion
  detects absent suite registration; all70 runner checks pass after registration
  and support-hash updates (one conditional skip). Analysis exits0 with one
  independently confirmed pre-existing informational lint. No production core
  behavior, exclusions or thresholds change.
- Twenty-four selected VM controls finish with assertions and zero other errors:
  eight generated AST fragment faults and sixteen explicitly labelled manual
  metadata-drop faults. Both636-test baselines pass. This is not a complete
  mutation score. Full inventory still generates1041 MessagePack and1166 CBOR
  serializer mutants; additional full campaigns require integrated final inputs.
- Core-only coverage is VM6755/7238 (93.33%), JS7357/7636 (96.35%), with12 core
  sources unmeasured per runtime. It excludes client/router consumer tests, so
  do not compare it directly with the whole-repository package scores or merge
  stale evidence into the new snapshot. Raw/policy VM reports agree. The initial
  formatter used the macOS /tmp alias and produced rejected relative source
  paths; formatting against the resolved root corrects the report without
  changing source scope. WASM success is not measured WASM coverage.
- Frozen canonical, Work178 and new-candidate input checks pass. Cell2450 still
  owns native HTTP and queued Fast175. Cell2596 audits completed WebSocket177
  (35/53 assertion score66.04%, clean baselines), starts WebSocket178 and waits
  discovery177 before its new full rerun. Do not duplicate live campaigns. The
  coverage179-probes archive/manifest and EVIDENCE.md preserve the candidate and
  exact commands; retain the Work174 pending benchmark cleanup fix. No canonical
  promotion, fresh Verify, commit, push, merge or publication is claimed.
- WebSocket178/session22654 subsequently completes and independently audits:
  62 generated,53 viable,44 assertion detections (83.02%),46 conventional kills
  (86.79%),seven survivors,nine compile errors,two error-only failures and zero
  timeouts. Both baselines0 and final candidate hashes pass; the95% gate fails.
  Allnine previous timeouts become assertion-backed detections. Preserve this
  complete report separately from both prior scores and selected controls.

### Work178 Event-Backed Completion And Discovery Setup

- Canonical172 and candidate177 input checks still pass. Their three full
  campaigns remain live; cell2450 owns native HTTP/session8963 and queued Fast175.
  No canonical implementation change, commit, push, merge or publication.
- Browser tests independently observe actual native WebSocket events, then
  assert completion after event-loop turns without an elapsed-time budget. The
  legacy fixture's concurrent initialization double-completion is reproduced in
  the first baseline and corrected by serializing notification processing.
  All36 cases pass on JS/WASM. Four selected opening timeouts become assertion-only
  failures with no other errors; original/restored/JS-WASM baselines pass.
  Four further readiness/loss controls also finish assertion-only (3/3/19/20
  assertions), with zero other errors/timeouts and passing clean/restored JS and
  WASM baselines. All eight remain selected controls, not a complete score.
- Three shared OAuth setups previously prevented test execution and one leaked
  its partially acquired server. Cleanup registration now follows acquisition;
  discovery success runs in each test. Four controls over the full MCP inventory
  now produce49-53 assertions plus35 other errors, no setup failures or deadlines,
  with both baselines passing. Do not retroactively upgrade the older campaigns.
- Eleven protected-resource bearer-method cases cover absent/null/empty/ordered
  extension values, malformed fields and immutable result lists. The empty-list
  survivor initially remained error-only because completion(...) forwards failed
  futures. An explicit success helper now yields an assertion-only detection;
  deadline exceptions remain unwrapped. Six helper regressions prove that boundary.
- Final isolated candidate passes1805 MCP tests, clean client analysis and151
  tooling tests (one conditional skip). A pre-change inventory assertion fails
  until the browser observer is explicitly included in supportHashes. Fresh
  inventory preserves all62 WebSocket mutants and all three transport suites.
  No new full-client coverage or complete mutation score is inferred.
- Recovery/evidence: coverage178-probes contains the final candidate input
  manifest, patch, untracked-test archive and selected-control reports. The
  isolated checkout is recorded in its EVIDENCE.md, not a new release branch.
  Preserve the Work174 pending benchmark cleanup fix as well. Promote only
  after Fast175 passes; then run canonical Verify and complete affected campaigns.
  Cell2596 owns the two Work177 non-native campaign handles, audits them after
  completion and starts full Work178 reruns from the frozen candidate. Preserve
  that checkout and do not duplicate its child polls or mutation runs.

### Work177 Isolated Attempt Ownership And Complete Evidence

- Older discovery172/session79902 and WebSocket175/session19457 are terminal and
  independently audited. Assertion-backed scores are221/360 (61.39%) and20/40
  (50%); conventional scores66.11% and55%. Both original/restored baselines pass,
  no waivers; gates fail. Discovery retains60 survivors,18 timeouts,87 compile
  errors,44 error outcomes and17 error-only detections. WebSocket retains13
  survivors,five timeouts,nine compile errors andtwo error-only detections.
- Isolated Work176/177 browser tests reproduce11 canonical assertions, including
  stale open/error callbacks, duplicate completion, late malformed Blob delivery,
  and old/new sent/received Goodbye classification. Candidate lifetime ownership
  guards and per-socket close state pass36 JS/WASM tests. Failed handshake behavior
  remains unchanged. The initial CLOSED-to-OPEN mock transition was corrected;
  it is not claimed as a production bug.
- Package-shaped candidate integration adds143 discovery cases, retains every
  existing MCP suite, repairsfive request-start barriers, and includes the complete
  WebSocket source/test inventory in mutation and browser verification/coverage
  selectors. All1788 MCP tests, clean package analysis and150 tooling checks pass
  (one existing conditional skip). Three inventory assertions fail before wiring.
  Five selected browser timeout controls andfour selected AS error controls now
  finish with explicit assertions plus other errors; both baselines pass. Do not
  retroactively credit them to completed full campaigns.
- Stage-one candidate JS measurement passes at client2697/2779 (97.05%) and
  core7391/7695 (96.05%), with162 unmeasured sources and WebSocket99/99 mapped
  lines. It predates the lastfive browser assertions; no WASM line score is claimed.
  Final browser session98279 is terminal, exit0:3352 core/2602 client JS tests,
  client2697/2779 (97.05%), core7392/7695 (96.06%), unchanged frozen inputs.
  New full62-mutant browser/session46295 and447-mutant discovery/session32022
  runs use that separately frozen candidate checkout; both baselines pass.
- Fresh MCP-only VM collection/session68399 passes1788 tests and measures
  authorization_discovery.dart at444/444 lines without module ignore annotations.
  Input hashes match. Evidence: discovery177-candidate-final/lcov-final.info;
  this does not replace whole-client VM or complete mutation measurements.
- Canonical code remains088323d6. Cell2450 alone owns native HTTP session8963 and
  queues Fast175 after terminal passing baselines/input hashes. Do not start a
  competing native user. After Fast175, promote the validated candidates and the
  pending Work174 benchmark cleanup fix, run canonical Verify and fresh complete
  affected measurements, then bundle these notes with implementation. Evidence,
  candidate recovery artifacts and exact handles: coverage177-probes/EVIDENCE.md.
  Keep PR93 draft, no merge/publication/version changes, full98%/95% goal active.

### Work175 Browser Measurement And Isolated Oracles

- Full Work172 VM/packaging collection is terminal with passing frozen inputs:
  client92.73%, router89.05%, other package results unchanged; packaging97.20%.
  Keep 59 library and 12 packaging sources unmeasured, not implicitly covered.
  Fresh browser175-current passes existing floors at client96.29% and core96.01%,
  with 162 unmeasured sources. WASM test success is not measured WASM coverage.
- The ignored coverage175-probes contains 90 passing ownership/direct-metadata
  tests and two readiness-fixture copies retaining all 19 existing tests. Requests
  rejected before server barriers now fail explicit assertions rather than hang.
  Fifteen exact former survivors fail assertions only; six selected former-timeout
  controls finish with assertions (two pure, four mixed). Original/restored control
  baselines pass. Preserve original and corrected control logs; do not upgrade the
  still-running complete discovery campaign with later candidate tests.
- Seventeen browser WebSocket lifecycle tests cover failed handshake, receive
  before open, normal/abnormal close, sent/received Goodbye and malformed frames
  with JSON/MessagePack/CBOR. JS and WASM pass after correcting the hybrid harness
  to accept numeric ports on both runtimes. Final JS mapped-line coverage is79/79
  for the implementation, not package coverage. A complete49-mutant isolated
  WebSocket campaign/session19457 has a passing baseline; no final score yet.
- Canonical production/tests remain frozen. Native HTTP session8963 belongs to
  supervisor cell2450, which will inspect terminal baselines/input hashes before
  starting Fast175. Discovery session79902 remains separate. After the relevant
  owners finish, promote the late-session cleanup fix and prepared discovery/web
  tests, update complete mutation inventories and browser selectors, run Verify,
  and repeat complete affected measurements. Keep bookkeeping uncommitted until
  bundled with implementation; no merge/publication/version change.

### Work172 HTTP Context And MCP Discovery Regression Matrices

- Fast172 passes before canonical edits. Promote 26 HTTP-context tests and 181
  discovery tests. All 207 focused tests and analysis pass. Cases assert exact
  bytes, copying, final/progressive wire state, callback order, completion,
  malformed descriptor recovery and concurrent response isolation; metadata and
  challenge boundaries, byte limits with multibyte text, and exact fallback URLs.
- Two failing inventory contracts reproduce missing complete targets. The new
  client-mcp-discovery-vm target includes all MCP consumer tests and all 447 AST
  mutations. Router-http-context-vm includes all 275 AST mutations plus existing
  request-body, runtime and native integration suites, with native artifact
  requirements and per-file isolation. No operator exclusions, score waivers or
  threshold reductions. Tooling passes 143 tests with one existing conditional
  skip. Pure discovery measurement is 439/444 (98.87%) lines; this does not replace
  full package/runtime coverage.
- The discovery campaign/session79902 is live with passing baseline. Preserve
  its inputs; no final score is claimed. Verify172/session66326 passes, including
  native and Chrome/WASM suites; frozen-input checks pass. Supervisor cell2363
  completed vm172-current/session60878 and launched native HTTP-context/session8963
  after releasing the coverage native window. Cell2363 is terminal; cell2450 now
  supervises the native campaign. Keep live processes, do not duplicate them. The full 98%/95% objective
  remains incomplete, including unmeasured files and browser/native/app scopes.
- Work171 workload evidence is now complete: 205/343 assertion-backed (59.77%),
  versus Work167's 154/339 (45.43%). There are 532 generated, 79 survivors, 30
  timeouts, 189 compile errors and 29 uncredited error-only detections, no waivers.
  Both baselines, independent classification audit and source/native hashes pass.
  The 95% assertion gate still fails; retain bench171-workload-mutations.
- Follow-up probes remain ignored, not canonical. Four late-discovery tests pass;
  dropping late abort or owned-client close causes two assertions each, with no
  timeout/error credit. Six workload diagnostic tests pass and two new assertions
  reproduce sessions leaked when opening succeeds after the workload deadline.
  An isolated late-session cleanup fix passes 13 tests, including bounded cleanup,
  error containment and no double-close. Promote only after review and a fresh
  baseline; current complete campaign scores do not include this candidate.
- Routine local reviews were checked against source and executions. Suggested
  changes based on missing exports, missing FFI setup in deliberately pre-FFI
  tests, or path-order races were not substantiated. The GLM judge endpoint was
  independently unreachable for the isolated cleanup candidate; its review and
  final canonical verification remain pending.

### Work171 Deterministic Buffer Assertions And Required HTTP Gate

- Fast171 passes before promotion. Eight dedicated event-buffer tests and four
  legacy cases use explicit microtask completion assertions, preserving the 11
  previous cases and adding live nonmatching-event FIFO/replay coverage. The
  direct fake_async dev dependency avoids transitive test dependencies. No real
  or fake deadline is used as an assertion substitute.
- Combined negative controls complete for 15 former timeout mutations: 11
  assertion-only, two mixed and two error-only, with zero timeouts. Error-only
  results remain uncredited. All 111 focused tests and final analysis pass.
- Two canonical pre-change contract failures prove that HTTP mutations were
  absent from CI and missing evidence could pass its audit. The complete HTTP
  target now runs with the unchanged default 95% gate and always-uploaded
  artifacts. The deployment audit requires it and rejects missing, queued,
  in-progress, failed, cancelled and skipped evidence. All 102 tooling tests pass.
- The fresh complete HTTP campaign passes at 56/58 assertion-backed detections
  (96.55%), 90 generated, two survivors, 32 compile errors, no timeouts, no
  error-only credit and no waivers. Original/restored baselines and independent
  audit pass. Its recorded target inputs match the final code. Evidence is in
  bench171-http-mutations under out/regression-coverage-2026-09-15.
- Verify171 passes, including 1307 benchmark, 3894 router, 3343 core WASM and
  2568 client WASM tests. Its final frozen-input checks pass. Session72541 and
  cell2234 are terminal; the complete 532-mutation workload campaign/session95122
  is now terminal. Its audited 59.77% assertion score and remaining failures are
  recorded above. Logs are retained in coverage171-verification. Check exact-head
  hosted evidence after pushing; keep the full goal active and PR #93 draft.

### Work170 HTTP Assertion Gate And Scenario Copy Matrix

- Fast169b passes before promoting the corrected startup/EOF fixture and 37
  scenario-copy tests. The copy matrix independently checks all 25 fields,
  nullable clearing, retention, source immutability and false/zero overrides;
  all 25 separate ignored-override controls fail assertions. Complete mutation
  wrapper/support inventories and their exact tooling contract include it.
- All 130 focused tests, package analysis and 73 tooling contracts pass. The
  complete HTTP campaign passes 95% at 56/58 (96.55%) assertion-backed detections:
  90 generated, two survivors, 32 compile errors, zero timeouts, zero error-only
  credit and no waivers. Both baselines and independent audit pass. The nine
  prior fixture timeouts now fail explicit assertions; prior lifecycle controls
  still detect the original bugs. Evidence: bench170-http-mutations.
- Verify170 passes, including 1306 benchmark, 3894 router, 3343 core WASM and
  2568 client WASM tests. Frozen source/test hashes match; cell2171/session77450
  is terminal. Logs are retained in coverage170-verification. Isolated
  coverage171-probes has eight passing microtask delivery/error tests and four
  passing legacy replacements. Its 15 selected controls yield 13 assertion-backed
  and two error-only failures, no timeouts. Error-only cases are uncredited.
  Promote both suites with a direct fake_async dev dependency, preserving all
  other tests, before remeasuring the complete workload target. Require the
  now-passing HTTP gate in CI and its exact deployment-audit contract. Keep all
  component/runtime gaps in scope; no final milestone completion is claimed.
- The two remaining HTTP survivors concern numeric-host argument representation
  and private configuration-list growability; neither is waived. The passing
  HTTP target is not completion of the benchmark component or the wider goal.

### Work169 HTTP Lifecycle And Workload Timing Assertions

- Fast169 passes before promotion of nine tests: controlled HTTP shutdown and
  rollback, transport-error classification, and independent millisecond/byte
  accounting for authentication, RPC, publish-ack and subscription/registration
  cycles. All 166 focused tests, clean package analysis and 73 tooling contracts
  pass. Both suites are included in the complete mutation inventories.
- The complete HTTP campaign and independent audit report 47/58 assertion-backed
  detections (81.03%), two survivors, nine timeouts, 32 compile errors and no
  waivers/error-only credit. Both baselines pass. Three previous survivors are
  detected, but nine configuration/early-response mutants expose fixture waits
  for callbacks that cannot occur. Preserve these outcomes instead of upgrading
  timeouts to assertions. Evidence: bench169-http-mutations.
- Verify169 passes, including browser WASM tests, and frozen inputs match.
  Cells2078/2091 are terminal. The follow-up startup/EOF candidate and its
  controls are promoted and remeasured in Work170; keep the original HTTP169
  evidence rather than retroactively attributing its timeouts to assertions.
- Work168 fed2cc82 is pushed and PR93 updated. CI35543464622, package35543464626,
  image35543523851, profile35543524908 and native dry-run35543587393 are queued.
  Strict hosted audit remains non-green with no demonstrated hosted test failure.
  Keep the full scope and 98%/95% gates intact; no merge/release/version change.

### Work168 File Registration And Cleanup Ownership

- Fast168 passed before promotion. Twenty-six tests cover file receiver deadlines,
  late success/error/cancellation ownership, all-resource cleanup, primary-error
  preservation, actual generated bytes, latency units, in-flight capacity and
  shared HTTP listener routing. Eight canonical pre-fix failures are assertions,
  not converted deadlines or crashes. The implementation bounds registration,
  cancels late resources, attempts every cleanup, and preserves the first relevant
  failure without logging exception data. Public API and wire behavior stay intact.
- All 182 focused tests, clean benchmark package analysis and 73 verification
  tooling contracts pass. The four new file suites and shared-listener test are
  included in the complete mutation inventories. The complete HTTP campaign now
  independently audits 53/58 assertion detections (91.38%), with both baselines
  passing, five survivors, 32 compile errors, no error-only detections and zero
  waivers. The 95% gate still fails; input hashes pass. Evidence is retained in
  bench168-http-mutations. Verify168 passes, including 3343 core WASM and 2568
  client WASM tests. Fresh complete repository VM/packaging coverage passes at
  vm168-current: benchmark 2307/2322 (99.35%), workload 1249/1262 (98.97%),
  client 92.09%, router 88.84%, core 94.34%, MCP 96.13%, auth server 100%.
  Measured packaging is 765/787 (97.20%), with 12 sources unmeasured. The full
  98% audit still fails; 59 library sources and external scopes lack evidence.
  Passing WASM tests are not measured coverage. Source/test/native hashes pass.
  Do not attribute Work167 workload scores to this new source/test
  snapshot; the full goal remains active.
- Cell2011, Verify168 and coverage/session59965 are terminal and release the
  native window. Fast168 and the HTTP campaign are complete. Retain their final
  logs and hashes with this implementation bundle; check the exact-head
  deployment chain after pushing.
- Nine isolated follow-up tests at coverage169-probes pass: controlled real-HTTP
  parser shutdown/rollback/disconnect tests plus independent latency and byte
  accounting for authentication, RPC, publish-ack and subscribe/register cycles.
  Three HTTP and five individual latency mutation controls fail by assertions,
  not deadlines or crashes. They are not complete campaign scores or canonical
  tests; promote after fresh test-fast, then collect complete affected campaigns.
- The complete Work167 workload campaign independently audits 154/339 assertion
  detections (45.43%), raw 183/339 (53.98%), 120 survivors, 36 timeouts, 181 compile
  errors and zero waivers. Both baselines and final hashes pass; 95% fails.
  Cell1935 and audit session61299 are terminal. Preserve their raw evidence under
  bench167-workload-mutations, rather than rerunning or narrowing the inventory.
- Isolated selected controls prove the new file assertions detect byte corruption,
  excessive active transfers and incorrect latency units. They are diagnostic
  evidence, not a complete mutation score. Results assert unordered iteration
  identities because concurrent completion order is not launch order. The GLM
  endpoint was unavailable; routine review identified the reproduced cleanup bug,
  while unsupported advice to weaken assertions was rejected against source/tests.

### Work167 Malformed Requests And Workload Failure Assertions

- Fast167 passed before promotion. Thirty real-HTTP malformed/auth-order/recovery
  tests reproduce 18 canonical assertion failures before the narrow parser fix.
  Malformed UTF-8 and form escaping now return HTTP 400 inactive JSON without
  input reflection; authorization still runs first. Thirteen workload regressions
  verify chunk-count validation, timeout failure modes, missing IDs, diagnostics
  and cleanup. All 96 focused tests, analysis and 73 tooling contracts pass.
- Complete HTTP mutation campaign: 90 generated, 58 viable, 51 assertion kills
  (87.93%), two error-only detections, five survivors, 32 compile errors, no
  waivers. Raw detection is 53/58 (91.38%). Both original/restored baselines pass
  and the independent audit passes; the 95% gate fails. New parser branches add
  four viable candidates, including a surviving non-parse-error rethrow guard.
  Do not exclude it or count bind crashes as assertion kills.
- Verify167 passes, including 1234 benchmark, 3894 router, 3343 core WASM and
  2568 client WASM tests. Fresh complete parent/child benchmark coverage is
  2292/2307 (99.35%), workload 1234/1247 (98.96%), with all measured library
  source files above 98%. Ten real child reports and frozen input/native hashes
  pass. The full scope audit still fails on absent packages/runtimes; the
  exports-only barrel is not fabricated as covered. Cell1891 is terminal.
- Cell1935 completed the full workload mutation campaign and released its native
  window; see Work168's terminal audit summary. Initial cell1932 stopped
  before creating a campaign due to missing CONNECTANUM_NATIVE_LIB; the corrected
  launch explicitly reused the verified artifact without rebuilding it. No hosted
  pass is claimed.
- Separate ignored follow-ups pass: one shared-listener/route test with two
  selected equality mutants rejected by assertions, and nine real generated-file
  integrity/cleanup tests. They do not contribute to Work167's scores. Promotion
  steps, hashes and review checks are in coverage167-probes/EVIDENCE.md. After
  the frozen window ends, integrate these with fresh verification and whole-source
  campaigns rather than applying historical mutation scores to new tests.

### Work166 Child VM Coverage And Boundary Mutation Evidence

- Fast166 passed before canonical changes. Added opt-in child VM instrumentation
  to the existing real-process native-build matrix and wired raw child reports
  into bin/test-coverage. Direct workspace collectors retain VM service auth,
  loopback ephemeral binding, the original build deadline and exact output.
  Report validation, atomic exclusive creation, process errors, malformed data,
  timeout cleanup and a real process-reaping control pass 41 helper tests.
- Promoted 18 HTTP configuration and nine transport-ranking tests with complete
  mutation support inventories. Analysis and 73 tooling contracts pass.
  Verify166 passes, including 1191 benchmark, 3894 router, 3343 core WASM and
  2568 client WASM tests. Full parent/child benchmark VM coverage is 2272/2301
  (98.74%), with runner 180/180 (100%) and workload still 1220/1247 (97.83%).
  The complete coverage audit still fails; missing packages/runtimes and the
  exports-only barrel are not claimed as covered.
- Fresh complete campaigns and independent audits: transport 33/34 strict
  assertion-backed kills (97.06%, 30 assertion-only/three mixed, one survivor,
  eight compile errors); HTTP auth 48/54 (88.89%, raw 50/54, two error-only
  detections, four survivors, 32 compile errors). Both baselines pass; no
  waivers or timeouts. Only the transport target clears 95%. Native/source/test
  hashes match. Evidence: bench166-final, bench166-boundary-mutations and
  coverage166-verification in out/regression-coverage-2026-09-15.
- Local Qwen reviews were independently checked. Atomic output ownership was
  hardened with a competing-writer test; malformed diagnostic decoding does not
  mask exit failures, and pipe failures still propagate. The separate GLM
  endpoint is unavailable. Hosted evidence remains pending, not green.
- Next, after a new baseline, promote the isolated malformed HTTP request fix:
  two pre-fix assertion failures, 55 passing candidate tests including exact
  HTTP 400 inactive JSON and successful subsequent authentication. The source
  currently leaks FormatException/ArgumentError from its async request handler.
  Also promote 13 passing workload failure probes, then recollect complete
  campaigns rather than assigning old scores to new tests. See
  coverage166-probes/EVIDENCE.md for pinned inputs and the unsuccessful
  force-close fixture that must not receive regression/mutation credit.
- Keep the full goal active and PR #93 draft. No merge, version change or
  publication. All Work166 verification/coverage/mutation processes are terminal.

### Work165 Integrated Benchmark Failure Regressions

- Fast165 passed before canonical edits. Runner163 completed, both baselines and
  final input/native hashes pass, and its independent audit reports 26/72
  assertion-backed detections (36.11%), 21 error-only detections, 25 survivors,
  17 compile errors and no timeouts/waivers. Its 95% gate fails.
- Promoted HTTP startup rollback, replay FIFO restoration, and joint pub/sub ACK
  and delivery error ownership. The canonical pre-fix run reproduces all 11
  assertion failures. The complete benchmark suite now passes 1123 tests;
  package analysis and all 72 verification-tooling contracts pass.
- Added native runner counter/latency/scheduling assertions and six worker
  handoff controls. No change to WAMP wire behavior or public APIs.
- Full-source mutation targets now include all promoted boundary suites plus
  HTTP auth and transport target modules. Their first complete audited scores
  are 40/54 (74.07%) and 28/34 (82.35%) assertion-backed kills, with raw detections
  42/54 and 30/34. Retain compile errors, test errors and survivors separately;
  no waivers, both 95% gates fail. Evidence: bench165-boundary-mutations under
  out/regression-coverage-2026-09-15.
- Verify165 passes including 3894 router, 3343 core WASM and 2568 client WASM
  tests. Full benchmark VM library coverage passes all 1123 tests and measures
  2260/2301 lines (98.22%), versus 2189/2296 (95.34%). The complete target audit
  still fails: runner 168/180 (93.33%) and workload 1220/1247 (97.83%) miss
  per-file floors, and absent other packages/runtime scopes remain unmeasured.
  The sole unmeasured benchmark library path is its exports-only barrel.
  Do not credit CLI, Rust/FFI or browser coverage from this library-only report.
- Supervisor cell1759 is terminal; frozen source/test and native hash checks
  pass. Follow-up HTTP configuration (18 cases) and transport-ranking (nine)
  tests pass as ignored probes; their assertions are not credited to the frozen
  campaigns. Promote them with inventory contracts, strengthen remaining
  runner/workload assertions, then recollect whole-target mutation evidence.
- A narrow local review was checked independently: eagerError does not cancel
  Future.wait inputs or delay the first error; success still requires ACK and
  all deliveries. Replay restores a local queue in FIFO order. No demonstrated
  HttpServer.close failure justifies speculative injectable-server APIs. GLM's
  separate endpoint is unreachable. Whole-goal completion remains unproven.

### Work164 Isolated Failure Ownership Regressions

- Preserve the live full runner163 mutation campaign and its frozen root/native
  inputs. All new source/test experiments are ignored copies under
  `out/regression-coverage-2026-09-15/coverage164-probes/`.
- Reproduce partial HTTP auth harness bind rollback failure for one and three
  earlier listeners. Both canonical cases fail rebind assertions before isolated
  cleanup-on-failure candidates; 32 candidate tests pass, including retry.
- Reproduce replay matcher data loss at the first/middle/last queued event.
  Preserve synchronous exception behavior and FIFO while restoring the scanned
  prefix. Seven candidate tests pass versus three canonical assertion failures.
- Reproduce pub/sub errors escaping while ACK is pending, or after synchronous
  and asynchronous publish failure. Candidate Future.wait owns ACK and delivery
  errors together and fails promptly without abandoning secondary errors.
  Six canonical assertion failures become 12 passing cases, including two-peer
  success, ACK/event ordering, metadata forms, error identity and payload release.
- The combined candidate/boundary matrix passes 292 tests, including 60 existing
  workload tests, 50 sample, 109 scenario and 22 transport-target cases. Scratch
  analyzer exits zero with dependency-scope informational diagnostics, not a
  clean package analyzer claim. Frozen source/test and native hashes still match.
- Qwen review leads were checked against the behavior tests; its FIFO reversal
  and Future.wait secondary-error claims are invalid. Add the useful mixed
  payload-delivery failure control. Keep candidate evidence distinct from
  package verification, and promote only after the live campaign is terminal.
- No canonical implementation/test edit, commit, publication or version change
  in Work164 yet. After promotion, run fresh package analysis, coverage, bin/verify
  and full target campaigns; older mutation scores do not describe these tests.
  Evidence.md records commands, caveats and promotion steps. The whole 98%/95%
  goal remains incomplete; GitHub's 74 exact-head checks remain queued.
- Investigate worker survivors without treating unexplored guards as equivalent.
  A six-position microtask handoff/close probe passes on canonical code; the
  copied lifecycle suite passes 36 cases. The suspected hang is not reproduced,
  so no worker fix or waiver follows. GLM is independently unavailable and Qwen
  did not supply a concrete reachable counterexample. Final scratch analysis
  has 46 dependency-scope info diagnostics; worker163 scores remain unchanged.

### Work163 Conservative Deadline Accounting

- Two classifier negative controls reproduce missed deadlines: the exact legacy
  fixture's Expected/Actual failure and throwsA wrapping an actual TimeoutException.
  Reject both as assertion kills; preserve genuine business-text assertions.
- Add opt-in historical kill-to-timeout correction with original report/log hashes,
  original summaries/statuses and conservative gate recomputation. Default audit
  rejects mismatches; opt-in still rejects crashes and inconsistent input scores.
  Never overwrite the source report or earlier audit files.
- Make the fixture throw typed TimeoutException. Its type regression fails before
  the change and passes after. All 47 focused tests and analysis pass. The complete
  tooling suite has 66 passing tests plus one Linux-only skip on macOS, including
  real Dart reporter wrappers. Fast163 and Verify163 passed, including WASM tests.
- Canonical deadline-corrected-audit.json results: historical worker 15/69 (21.74%),
  runner 21/72 (29.17%), workload 134/338 (39.64%). Thirteen worker outcomes are
  reclassified, zero runner/workload outcomes. These do not describe newer tests.
- Verify162 completed before these changes; its bench run passed 878 cases and
  measured 2189/2296 (95.34%). The following hash check stopped its supervisor
  before a stale runner campaign could start. Both old supervisors are terminal.
  Preserve raw/partial campaigns and collect fresh final evidence after review.
- Focused companion gate review is complete and independently checked; its
  contradictory opening finding is rejected by the AND-gate logic, explicit
  historical gate copy and single-read log hashing. GLM remains unavailable.
  Further canonical replays of lifecycle154, auth135, ci143 remote/MCP, remote144,
  base64-153 VM/JS, msgpack152 JS and meta-cache145 VM/JS find zero additional
  deadline corrections. The ci143 MCP campaign remains incomplete.
- Fresh worker163 coverage passes 37 tests and measures 209/209 worker lines,
  still VM/POSIX-only. Full bench163 coverage passes 879 tests and measures
  2189/2296 (95.34%). Its 98% target audit still fails; other packages/scopes are
  not measured by that report. Source/test and native hashes match. Cell1590
  completed verification/coverage and owns the full runner mutation campaign;
  cell1591 owns the independent fake-child 85-candidate worker campaign. Both
  campaigns remain active, not stalled or restartable.
  Freeze: /tmp/connectanum-coverage163-frozen-inputs.sha256; logs/manifests retained
  in coverage163-verification. Final mutation results are pending. Bundle this
  bookkeeping with the implementation commit; keep the milestone incomplete.
- Implementation 5c56a12b is pushed. Cell1591 completed worker163: 85 candidates,
  69 viable, 22 assertion kills (19 pure, three mixed), four error-only detections,
  37 timeouts, six survivors and 16 compile errors. Both baselines pass. Raw
  detection 26/69 (37.68%); strict/adjusted assertion 22/69 (31.88%), no waivers.
  Independent audit and input hashes pass; the 95% gate fails. Cell1591 is terminal.
  Cell1590 still owns the full 89-candidate runner campaign with a clean baseline.
  Exact-head CI35531155716/35531153071, package35531155711/35531153050,
  image35531168113 and profile35531169225 are queued; all 74 PR checks are queued.
  Strict audit exits1 for pending evidence and feature-branch protection, not a
  demonstrated test failure. PR #93 is updated and remains draft/unmerged; no
  publication or version change. Notes stay uncommitted for the next code bundle.

### Work162 Build Pipe Drain And Worker Assertions

- Priority correction: fixture polling deadlines and TimeoutException values
  wrapped by throwsA can be misclassified as assertion kills. Negative controls
  in coverage162-probes reproduce both. Supplementary replay changes 13 Work161
  worker outcomes to timeout (15/69 = 21.74% conservative); original 40.58% strict
  claim is withdrawn. Work160 runner/workload scores are unchanged by this replay.
  Correct the canonical classifier and fixture, regression-test them, re-audit
  old reports and rerun affected campaigns. Do not modify original raw evidence.
- Fast161/Verify161 passed on the pre-edit snapshot. Promote the isolated fake
  cargo repro into ten public BenchmarkRunner tests: six controls pass and four
  large-stderr cases hang before production changes. Drain both pipes concurrently;
  all ten now pass. Preserve byte order/non-UTF-8 data, exact exit metadata,
  arguments, cwd and disabled-build behavior. POSIX scope is explicit.
- Child probe failures remain test errors; timeouts/crashes get no mutation
  assertion credit. A missing router config prevents accidental native loading.
  Parent-only coverage does not measure the child build path; keep that gap
  visible until independently instrumented.
- Strengthen worker survivor assertions for logger identity, each close future,
  late diagnostics, file/package/direct launch cwd and relative file paths.
  All 46 focused cases and analysis pass. Seventy-one tooling contracts pass.
- Extend the full runner mutation target's test/support inventory; do not narrow
  its production scope. Cell1543 completed Verify162 and full bench coverage;
  changed classifier-test hashes stopped its planned mutation phase.
  Cell1544's worker campaign was deliberately interrupted after 30/85 outcomes
  (exit130, complete=false) due to the measurement defect. Preserve its raw logs,
  the frozen inputs and native reservation;
  do not duplicate these jobs. Work162 is uncommitted; 98%/95% is not achieved.

### Work161 Worker Lifecycle Ownership

- Preserve Work160's isolated native campaign and reserve its native test window.
  The preceding fast test and final Verify160 passed before production edits.
- Reproduce 11 failures in 21 new fake-process lifecycle cases before changing
  production code. Startup races, close during Process.start, stale cleanup,
  concurrent scenario ownership, EOF and UTF-8 decode failures are observable
  through public operations, independent child PID/request markers and reaping.
- Give each generation its own launch/readiness, response, subscriptions and
  close completion. Serialize scenarios without reusing their native runtime.
  Explicit close invalidates queued operations and pending starts. A separate
  failing close-during-cleanup test drives the additional startup epoch guard.
- Final focused matrix: 32 tests pass and 209/209 worker source lines are covered.
  Keep VM/POSIX fixture scope explicit; this is not whole-package, Windows or
  native Rust coverage. All 71 verification-tool contracts and analysis pass.
- Controlled deadlines fire only the configured readiness/shutdown timer after
  independent OS child barriers. This avoids startup timing flakiness; actual
  process creation, pipe failures, signal delivery and reaping remain real.
- Complete 85-candidate worker campaign originally recorded 28/69 (40.58%) kills, 13 survivors,
  24 timeouts, four error-only detections, 16 compile errors. Both baselines and
  independent audit passed under the old classifier, but the strict score is
  withdrawn by Work162's deadline audit. No waivers; 95% gate fails. Its fixtures do not load the
  native library. Keep its frozen tests and raw evidence distinct from follow-ups.
- Production and test reviews were attempted locally. Completed Qwen findings
  are rejected after checking synchronous ordering, caller-visible errors,
  awaited exit futures, existing timeout guards and Process.killPid behavior.
  Earlier token-limited reviews remain incomplete, and GLM is unavailable.
- Work160's native campaign and both independent audits completed; frozen hashes
  match. Fast161 and Verify161 exit 0, including browser WASM tests. Supervisor
  cell 1462 completed final benchmark collection: all 864 tests pass, covering
  2189/2295 measured lines (95.38%). Frozen input and native hashes still match.
  The benchmark-only audit fails 98%; other packages are absent, not measured.
  Implementation 994fc7e9 is pushed. PR #93 remains draft/unmerged; exact-head
  CI/package/image/profile checks are queued. The strict deployment audit fails
  pending evidence and feature-branch protection, not a proven test failure.
  The complete per-component/runtime 98%/95% milestone remains incomplete.

### Work160 Benchmark Factories And Runner Evidence

- Fast160 passes before repository edits. Add independent wire peers for all
  Dart/native transport/serializer combinations, TLS, ticket rejection, payload
  preservation and owned provider disposal. Explicit defaults and independent
  benchmark-key decoding strengthen assertion-based mutation detection.
- Expand real YAML runner coverage to exact six-sample/102-byte accounting,
  dry-run/no-load distinctions and CLI requirements/defaults. Focused suites have
  66 factory and 18 runner cases. The reversed file order fails before native
  client runtime teardown and passes afterward; keep that negative control.
- Add a complete runner mutation target and extend the workload target's hashed
  support inventory and required native artifact. Seventy tooling contract tests
  pass after updating the stale inventory expectation exposed by first verify.
- Final full benchmark-only collection: 2118/2254 (93.97%), with all 836 tests
  passing. This is not a new whole-workspace VM score. Final bin/verify exits 0,
  including browser WASM tests; frozen source/test hashes match. The complete
  89/519-candidate campaigns are running in isolated workspaces (session 51979),
  with the native test window still reserved. No completed mutation score yet.
  The pre-teardown campaign was deliberately interrupted, retained without a
  completed score, and will not be attributed to the final test snapshot.
- Work154 completed its original campaign and independent audit. Historical
  strict scores are Invocation VM 91/108, Invocation JS 92/108 and Session JS
  222/460, all below 95%. Timeouts and error-only outcomes receive no kill credit.
- A minimal public NativeWampWorker.start concurrency repro produces two child
  processes (expected one); both are cleaned up. Next implementation work should
  make startup and old-exit/pending ownership generation-safe and cover failure,
  restart and cancellation with fake child processes. Preserve this pre-fix
  evidence under coverage160-verification; it does not load the native library.
- Evidence root: out/regression-coverage-2026-09-15/coverage160-verification;
  bench160-current is initial coverage, bench160-final is reserved for the final
  snapshot, and bench160-final-mutations is the final campaign output.

Work160 is pushed as 67092fc9. All 74 PR checks are queued, and strict hosted
audit exits 1 for pending evidence/feature-branch protection. Exact-head CI
35525099435/35525096784, package 35525099454/35525096726, image 35525141697 and
profile 35525142318 are already dispatched; do not duplicate them. The complete
runner target records 21/72 (29.17%) assertion-backed kills: 29 survivors,
22 error-only detections, 17 compile errors, clean before/after baselines.
The workload target also completed: 134/338 (39.64%) strict kills, 146 survivors,
22 timeouts, 36 error-only detections, 181 compile errors. Both baselines and the
independent audit pass; the native artifact is unchanged. These are not Work161
snapshot results. All three benchmark targets still fail the 95% assertion gate.

A separate public BenchmarkRunner.run repro with controlled fake cargo confirms
a stdout/stderr pipe deadlock. Preserve coverage162-probes and its failed log;
no real native artifact is loaded or built. After Work161's frozen verification,
drain build streams concurrently and promote the six-case fake-build matrix:
three controls pass and three stderr-backpressure cases fail. The fixture waits
for PROBE_READY and the fake cargo PID before imposing operation deadlines;
zero-byte streams do not call macOS head with an invalid zero count.

### Work159 Active MCP Stream Failure Isolation

- Fast159 passes before edits. Add 23 public-router cases for active resource,
  catalog and heartbeat failures, throwing diagnostic observers, secondary close
  failures, healthy retained owners, last-owner WAMP unsubscribe, bounded
  replacement admission, canceled-but-queued heartbeats, notification opt-outs,
  and exact ACK/completion frame limits (limit-1, limit, limit+1). The focused
  41-case matrix and analyzer pass. A frozen pre-fix replay of b9378544 fails
  eight assertions with no test errors.
- Active write errors now initiate an asynchronous report-and-close operation
  whose finally guarantees cleanup. Errors remain observable after cleanup,
  without interrupting fanout or catalog refresh. Separate the low-level checked
  stream write from the synchronous admission diagnostic wrapper to avoid
  catching/reporting the observer's own exception twice.
- The first complete 38-candidate probe records 14/29 assertion-backed kills,
  9 timeouts, 6 survivors and 9 compile errors. Retain it unchanged. Strengthen
  public metadata barriers, notification selection and exact ACK-boundary tests;
  rerun the full selected inventory on the final test snapshot. No historical
  outcome is attributed to the changed tests. Whole-source inventory 2308 remains
  visible; this is not a whole-router mutation percentage.
- Three candidate equivalences are individually documented and source-hash
  pinned: two discarded private activation return values and one unmodified
  loop-copy growable flag. Do not waive the response-limit guard: public route
  options are a caller-provided Map, so a stable-limit assumption is insufficient.
- Qwen planning and production/test reviews were completed; reject suggestions
  to weaken exact error assertions or make the injected stream leak native
  resources. GLM was checked independently and unavailable. Preserve review
  triage with the evidence. The controlled clock is scoped to router startup
  and intercepts only 15-second periodic timers; real HTTP/WAMP still proves
  delivery and ownership.
- Fresh JS159 exits 0: core 7388/7695 (96.01%), client 2651/2753 (96.29%). All 162
  unmeasured sources remain visible and the 98% target audit fails. Full
  Verify159 exits 0, including 3894 router, 3343 core WASM and 2568 client WASM
  tests. Frozen inputs match. Fresh VM159 starts after verification's native
  consumers; the native-library hash matches. Serialize native consumers;
  preserve the isolated older Work154 campaign. The full 98%/95% milestone is active.

VM159 library coverage completes at 38964/42685 (91.28%), including router
17222/19391 (88.81%); other package scores are unchanged. The 98% target audit
fails and 59 unmeasured sources remain visible. Full VM159 exits 0. Packaging
remains 765/787 (97.20%), with 12 unmeasured sources and a failing 98% audit.
All native tests passed; after-test source/native hashes match and the shared
native window is released. Final measurement input hashes match.

Final 38-candidate probe completes: 22 assertion-backed kills (8 pure, 14 mixed),
3 timeouts, 4 survivors, 9 compile errors. Raw assertion score 22/29 (75.86%);
three individually hash-pinned equivalences yield 22/26 (84.62%) adjusted. No
error-only detections or timeout credit. The notification opt-out bypass and
ACK exact-limit mutations now fail assertions. The response-limit guard remains
unwaived because callers can supply mutable route options. The three remaining
timeouts suppress ACK/notification delivery; they are not assertion kills.
Both baselines, independent log audit and frozen source/test/native hashes match.
The initial and final snapshots remain separately auditable; no 95% claim.

Evidence: mcp159-live-probe (initial snapshot), mcp159-live-final-probe,
js159-current and coverage159-verification under
out/regression-coverage-2026-09-15.

Implementation `235b3faf` is pushed; PR #93 remains draft/unmerged. Exact-head
CI runs 35522595419/35522592735, package dry-runs 35522595435/35522592722,
explicit image dry-run 35522602053 and profile benchmarks 35522603252 are queued.
All 74 PR checks are queued. The strict audit exits 1 on pending/unstarted jobs
and feature-branch protection, not a proven test failure. Preserve these run IDs;
do not duplicate dispatches. VM159 and packaging formatting exited 0. Post-push
bookkeeping waits for the next code bundle. The complete coverage goal is active.

### Work158 MCP Subscription Admission Ownership

- Fast158 passes before edits. Sixteen public HTTP/WAMP cases cover unsupported
  and native stream-open errors, acknowledgment add/close errors, diagnostic
  callbacks that throw, and an existing healthy owner sharing the resource.
  A pinned replay of8698b3d0 produces eight assertion failures. After the fix,
  all sixteen pass: exact diagnostic order, failed-stream closure, public WAMP
  lookup/count, bounded listener recovery, and notification subscription IDs.
- Always release admission preparation if stream open/reporting throws. Roll
  back registered ownership if acknowledgment/activation fails. Run unused WAMP
  resource cleanup even when close-error reporting throws. Preparation release
  is explicitly idempotent; callbacks remain observable and no wire API changes.
- Complete25-candidate selected-region probe:7 assertion-backed kills (3 pure,
  4 mixed),2 error-only detections,6 timeouts,4 survivors,6 compile errors.
  Raw detection47.37%, strict assertion7/19 (36.84%), no equivalence waivers.
  Preserve every outcome. Source inventory2312 remains visible; this is not a
  whole-router campaign. Baselines, independent log audit and input/native
  hashes agree. Surviving private return values and response-limit boundaries
  need individual investigation; no passing95% mutation gate is claimed.
- Qwen planning/two reviews completed. Source inspection disproves double
  release and nondeterministic synchronous diagnostic-order claims. Later
  heartbeat/fanout observer failures remain distinct coverage work. GLM was
  independently checked and unavailable. Review triage is retained with evidence.
- Fresh JS158 exits0: core7388/7695 (96.01%), client2651/2753 (96.29%), with162
  unmeasured sources and a failing98% audit. Full Verify158 exits0, including3871
  router,3343 core WASM and2568 client WASM tests. Final frozen inputs match.
  Fresh VM158 collection started after native verification;
  the native artifact hash matches and no native
  users overlap. Full VM158 exits0:38952/42681 (91.26%), including router
  17210/19387 (88.77%); other package scores are unchanged. The98% audit fails
  and59 unmeasured library sources remain visible. Packaging is765/787 (97.20%),
  with12 unmeasured sources and a failing98% audit. Final input hashes match.
  Serialize all native consumers. Keep the older154 campaign on its immutable
  snapshot. Do not merge, publish, change versions or mark the milestone done.

Evidence: mcp158-admission-probe and coverage158-verification under
out/regression-coverage-2026-09-15.

Implementationb9378544 is pushed and PR93 remains draft/unmerged. Exact-head
CI35519470503/35519468734, package35519470645/35519468709, image35519479078
(explicit dry-run) and profile35519480115 are queued. Strict audit exits1 on
pending/unstarted jobs and feature-branch protection, not a demonstrated test
failure. VM158 tests and LCOV formatting passed. Final input and
native-library hashes match; the native window is released. Post-push docs wait for the next
implementation bundle; do not create a docs-only commit.

### Work157 HTTP Cleanup And Browser Coverage Gates

- Fast157 passes before edits. Public-router regressions reproduce skipped
  handshake release when stream finish and its diagnostic observer throw.
  The pre-fix two-method negative control fails five assertions against the
  final12-case matrix, including normal/direct/hybrid ownership and terminal
  success/error. This is an ownership bug, not a WAMP wire-format change.
- Always attempt remaining owned cleanup in finally blocks. Keep observer
  exceptions observable, remove pending ownership before callbacks, do not
  finish an already-completed direct response, and preserve independent calls.
  Tests assert exact finish attempts/diagnostics, one release before an error
  escapes, late-open rejection and a second concurrent response completing.
  The deliberately unallocated direct handle tests the real borrowed FFI error
  path, not a successful native socket close. The full runtime file passes262.
- A complete16-candidate AST probe of both methods kills all4 viable mutations
  with pure assertions;12 candidates fail compilation. No timeout/error-only
  credit, survivors or waivers. Original/restored baselines, independent log
  audit and source/test/native hashes agree. Full binding inventory2399 remains
  visible: this method-level100% is not a whole-router score. The earlier probe
  produced four timeouts and remains retained; the final barrier waits for any
  observable completion, then asserts exact values instead of timing out while
  waiting for the expected diagnostic.
- Browser policy previously omitted client package coverage and retained an
  obsolete core83.5% floor. Fail-first tests pin both packages. Raise core to96%
  and add client96.29%; the final98% target is unchanged. Additional fail-first
  tests expose binary-float rejection of exact96.29% equality. Fraction-based
  decimal comparison fixes all threshold paths without rounding or tolerances.
  Coverage-tool tests pass19; verification wiring tests pass69.
- Qwen planning/review completed; unsupported double-close claims were checked
  against descriptor/stream types, synchronous ownership removal and the hybrid
  assertions. GLM was checked independently and is unavailable. JS157 passes
  the stronger floors: core7388/7695 (96.01%), client2651/2753 (96.29%). The
  explicit98% audit fails, with162 unmeasured sources visible; frozen inputs
  match. The final replay pins pre-fix commit78c544c3 and reproduces all results.
  Full Verify157 exits0, including3855 router tests and3343 core/2568 client
  WASM tests; frozen inputs match. VM157 library coverage is38925/42680 (91.20%),
  including router17183/19386 (88.64%). Other package percentages are unchanged
  from VM156; the98% audit fails and59 unmeasured sources remain visible.
  Full VM157 collection exits0; packaging remains765/787 (97.20%), with12
  unmeasured sources and a failing98% audit. Final input hashes match.
  Native consumers were serialized and final
  source/artifact hashes checked before releasing the shared native window.
  WASM test passes are not measured WASM line coverage.
  Evidence: http157-cleanup-probe, http157-finalizer-probe and
  coverage157-verification. Keep PR93 draft; no merge/publication/version change.
- Implementation8698b3d0 is pushed. Exact-head CI35517491832/35517488279,
  package35517491702/35517488255, image35517507306 (explicit dry-run) and
  profile35517507747 are queued. Strict audit exits1 on pending jobs and
  feature-branch protection, not a proven test failure. PR93 is updated and
  remains draft/unmerged. Post-push bookkeeping waits for the next code bundle.

### Work156 Progressive Input Finalization And Pacing

- Fast156 passes before edits. Public-session prototypes produce32 assertion
  failures before the fix: eight ordinary/lazy and eight file reentry cases on
  each of VM/WASM. Bounded synchronous callbacks expose extra accepted CALLs or
  segments, not merely a transient local flag. The file E2EE cases exercise the
  portable provider/transport interface, not a real native crypto integration.
- Reserve the finished state before final dispatch and roll it back on a
  synchronous throw. Share the invariant between finishLazy and finishFileSegment
  without changing public void callbacks or WAMP messages. Keep progressive
  reentry valid, preserve exception identity and rejected-send retries, and do
  not reopen an accepted nested final when an outer progress callback throws.
- Protocol rationale: [WAMP section11.2 Progressive Call Invocations](https://wamp-proto.org/wamp_latest_ietf.html#name-progressive-call-invocations)
  requires the input sequence to end with progress absent/false, with a common
  request ID across chunks. Results remain independent of the input sequence.
  Reserving the local terminal state preserves that boundary under synchronous
  reentry; it is an implementation choice, not a spec-mandated private flag.
  Rollback preserves local dispatch rejection semantics, not delivery assurance.
- Integrate the public drain prototype with controlled completion, failure/retry,
  independent concurrent futures and no-op unsupported transports. Final input
  still allows local write pacing; it must not wait for a remote RESULT. The new
  complete19-case suite and eight additional file cases pass67 total per runtime
  on VM, explicit dart2js and dart2wasm. All69 script tests pass after a fail-first
  check of fast/full, VM/JS coverage and session mutation command selection.
- Qwen reviewed the actual diff; the proposed async callback API change is not
  compatible with the existing contract, and retained file tests already cover
  its alleged missing retry scenario. GLM is independently unreachable. Keep
  native verification serialized and retain the older Work154 isolated campaign.
  Full Verify156 exits0, including3343 core and2568 client WASM cases. Frozen
  input hashes match. Full VM156 collection exits0 and the shared native window
  is released. Packaging remains765/787 (97.20%), with12 unmeasured sources;
  the explicit98% audit fails. Final input hashes match, and the native-library
  hash matched when the native test/collection phases finished before release.
- The complete ProgressiveCall-class AST probe executes24 candidates per VM/JS:
  15/15 viable assertion-backed detections (12 pure,3 mixed),9 compile failures,
  no survivors, timeouts, error-only kills or waivers. Original/restored baselines
  pass and independent log auditing agrees; all package Dart source/test hashes
  match the snapshot. The former drain-delegation survivor now fails assertions.
  This is class-only evidence, not a whole-session score. Sharing the finalization
  guard removes two duplicated mutations: the full source inventory is648 rather
  than650, and both complete inventories remain visible. The live Work154
  campaign still describes its older650-candidate snapshot.
- Full JS156 collection exits0: core7388/7695 (96.01%) and client2651/2753
  (96.29%), with162 unmeasured sources. Both complete suites pass and frozen
  canonical inputs match. The explicit98% audit still exits1; no WASM line
  measurement is inferred. The full VM collection follows serialized
  verification. Browser package regression floors still need refreshing,
  including an explicit client package floor; this does not change the98% goal.
- VM156 library evidence is38877/42680 (91.09%), with59 unmeasured sources.
  Auth100%, bench89.17%, client92.07%, core94.34%, MCP96.13%, router88.39%.
  The explicit98% audit still fails. Do not hide the lower router measurement:
  unchanged production sources lose12 previous hits and gain one. Missing hits
  are native/runtime.dart1869/3844/3861/3863, router_binding.dart7256-7266's
  borrowed-stream cleanup/error branch and router_internal_session.dart83;
  router_mcp.dart3221 is newly covered. Add deterministic failure/lifecycle
  assertions instead of rerunning or substituting older counts for this report.
- Implementation78c544c3 is pushed; PR93 remains draft/unmerged. Exact-head CI
  35514530549/35514527810, package35514530479/35514527815, image35514537707
  (explicit dry-run) and profile35514538403 are queued. Strict audit exits1 on
  pending checks/feature-branch protection, not a proven test failure. Keep the
  post-push measurement notes uncommitted until the next implementation bundle.

### Work155 Invocation Success Oracles And Finite Reentry

- Pre-edit Fast155 exits0. Keep every prior value and rejection assertion while
  asserting normal completion for valid lazy/PPT/E2EE dispatch, authenticated
  unpacking, null/zero timeout validation and explicit non-progressive error
  replies. Capture result values without repeating the operation under test.
- Bound the rejecting callback's nested response attempt to its first dispatch,
  and require exactly one dispatch. Preserve exception identity, stack, closed
  state and later retry checks. The Work154 guard-removal VM mutant timed out
  after entering this test; it now finishes with eight assertion failures.
- Canonical invocation tests pass273 each on VM and WASM. Full VM inventory has
  130 outcomes:102/108 assertion detection (94.44%),81 pure/21 mixed kills,
  6 survivors,22 compile failures, no timeouts or error-only credit. Both original
  and restored baselines pass. No production changes or equivalence waivers.
  The complete JavaScript campaign has identical outcomes; independent log audit
  and source/test/support hashes agree. Both targets still fail the unchanged95%
  gate and the campaign exits1. Full Verify155 exits0, including core/client WASM;
  frozen input hashes match. The shared native window is released. Exact-head
  hosted CI/deployment evidence remains outstanding; PR93 stays draft/unmerged.
- Preserve the live Work154 session campaign. Its first drain-delegation survivor
  7243fe2c0f60c00646a5 has a concrete counterexample in session155-drain-probe:
  controlled pending completion, identical transport failure with retry,
  concurrent independent futures and no-op unsupported transports. The public
  Client/Session API prototype passes all four tests on VM/JS and the mutant fails
  four assertions on each; restored baselines pass. Initial prototype compile
  errors are retained separately and earn no kill credit. These new tests are
  outside the canonical campaign snapshot and cannot improve its score.
- Next integrate the pacing prototype, pin it in VM/web session support
  inventories, and verify VM/JS/WASM without duplicating the existing campaign.
  Retain all six invocation survivors unwaived pending individual proofs or
  meaningful counterexamples. Broader native/runtime/application gaps remain.

### Work154 Progressive Reply Abandonment And Lifecycle Oracles

- Pre-edit Fast154 exits0. Add a45-case public session matrix across ordinary,
  native-lazy and native-materialized delivery, distinguishing goodbye while
  the transport remains ready, closed input, lost readiness before/during send,
  active send rejection/retry, forwarded timeout reset and terminal cleanup,
  and nullable-mode native/materialized interrupts. Preserve existing assertions.
- Before production edits,16 assertions fail across VM/WASM because materialized
  callbacks ignore false dispatch results for progressive replies. Make both
  callbacks close the local response handler in that case, matching native-lazy
  behavior. Add idempotent Invocation.closeResponse; explicit abandonment releases
  the callback and cannot be undone by a later callback failure or reattachment.
  Ordinary throwing adapters retain retryability; callback API and wire format
  remain compatible. Five core regressions cover payload views and reentry.
- Focused session tests pass163 per VM/JS/WASM runtime; core lifecycle passes15
  on VM. A complete method-only probe covers all19 AST mutations in
  _sendInvocationResponse on VM and JS:18 assertion-backed kills (16 pure,
  2 mixed),1 compile failure, zero survivors/errors/timeouts and no waivers.
  Independent audit reclassifies preserved logs; original/restored baselines and
  hashes match. Keep the scope boundary explicit: this is not a650-candidate
  whole-session campaign or a new whole-package line coverage measurement.
- Pin the core Invocation dependency in both session mutation support inventories;
  the wiring regression fails first then passes. All69 verification-script tests
  pass. Full Verify154 exits0, including browser WASM, with frozen inputs
  matching; the shared native window is released. Broader refreshed mutation
  campaigns and exact-new-head hosted evidence remain required before claiming
  milestone completion. Current8a141e65 checks remain queued and the older MCP
  diagnostic jobs remain live; do not duplicate them.
- Runtime evidence correction: local bin/verify selects WASM; hosted Linux
  selects JavaScript. Work154's JavaScript evidence is the separate focused
  session run and complete method probe, not a full local JS verification run.
- Implementation02433aea is pushed; PR93 stays draft/unmerged. Fresh complete
  core-invocation-vm, core-invocation-web and client-session-web campaigns run
  serially in lifecycle154-full-mutations, unified session32167/PID9326. Do not
  restart this live campaign or treat partial scores as finished evidence.
  Exact-head CI35511282499, package35511282498, image35511337428 (dry-run) and
  profile35511338422 are queued; strict audit exits1 on outstanding checks.
  This runtime correction/delivery bookkeeping awaits the next code bundle.
- Local Qwen reviews were checked against source and tests. Their claim that
  active failures always become abandoned contradicts the guarded call sites;
  the two states deliberately differ. Timer cancellation is observed through
  the Zone-created timers as well as transport output, not inferred from elapsed
  sleeps. Cross-isolate shared-object and network-ack claims do not apply to this
  synchronous callback change. GLM independently remains unavailable.

### Work153 Base64 Contexts And Required Runtime Gates

- Complete Fast153 before edits. Retain all previous tests and add independent
  mixed-alphabet octets, all alphabet-class contexts in both quartet positions,
  malformed Latin-1/UTF-16 boundaries and padding-bit matrices. Focused VM and
  JS tests each pass20. Production codec behavior is unchanged.
- Both complete269-candidate campaigns exit0 with221 pure assertion kills,
  45 survivors and3 compile failures; no errors/timeouts or error-only credit.
  The new oracles kill a006f04adb7f935512f9,659a8e6c61608d477adc and
  ced5d0ea751b21a26f15 rather than waiving these real behavior differences.
  Raw221/266=83.08%;44 individually written immutable-string proofs pinned to
  the source hash yield adjusted221/222=99.55%. Candidate8be0ffb08e2b2f783bc2
  for mutable byte input remains unwaived. Both original/restored baselines,
  independent log audits and canonical source/test hashes agree. Preserve152.
- Separate targeted line collection measures Base64 VM130/130 andJS144/144.
  This does not replace broader package measurements or measure WASM. The
  functional SDK-delegation proofs do not claim performance equivalence.
- Make both Base64 inventories required CI gates at the unchanged95% threshold,
  configure Chrome and a45-minute full browser job budget, and require the jobs
  in the strict deployment audit. A new wiring regression fails before the
  workflow change, then passes. Initial Verify153 identifies four stale audit
  success fixtures; update them and extend the missing-job rejection loop to
  both gates. The focused audit regression and all69 verification-script tests
  pass. Final-b full bin/verify exits0, including JS/WASM, with frozen inputs
  matching. Release the shared native window. Commit/push and exact-head hosted
  deployment-chain evidence are next; no green-chain claim yet.
- Qwen's proposed hardcoded bytes and two speculative test-review concerns were
  checked against arithmetic, SDK behavior and Uint8List's input domain; no
  assertions were weakened. GLM is unavailable. Keep raw and adjusted scores,
  dependency-proof boundaries and the failed initial verification visible.

### Work152 Serializer Assertions And Wire Boundaries (Locally Verified)

- Push verified151 as0d6bec0b and update PR93. Exact-head image35506393279 and
  profile35506394230 were dispatched once; strict hosted audit exits1 while
  required CI/package/image/profile checks are queued. No green-chain claim.
- Start Fast152 before edits; it exits0. Preserve the stronger existing wire
  comparisons and malformed-input matchers, adding single-execution
  returnsNormally assertions for valid operations. Add empty MessagePack scalar
  boundaries, nested wide-key/binary-view encoding and oversized-length cases,
  plus Base64 RFC4648 section10 vectors and byte-buffer ownership/range checks.
  Focused canonical VM codec tests pass104 cases. No production changes.
- Base64 VM152 completes269 candidates with218 assertion kills,48 survivors,
  3 compile failures, no errors/timeouts or error-only kills, no waivers:
  raw/adjusted218/266=81.954887%. Both baselines pass, source/test hashes match,
  and independent log audit agrees. This improves assertion quality, not the
  conventional218 detections. Base64 JS independently completes with the same
  counts and assertion score. MessagePack JS completes234 candidates with198/225
  assertions (88.00%),26 survivors,9 compile failures and1 infrastructure error
  from a lingering renderer. No kill credit for that error; cleanup completed.
  Both browser original/restored baselines pass, source/test/support hashes
  match and independent audits agree. All three full campaigns exit1:95% gates
  remain unmet. No equivalent waivers or aggregate-completion claims.
- Initial Verify152 fails the unchanged complete-inventory regression because
  four broader serializer target support lists lack the new MessagePack helper.
  Add the helper to all four, retaining the check and source scope. The focused
  regression now passes. Frozen final-b full bin/verify exits0, including JS/WASM
  tests, and input hashes match. Release the shared native window. Passing WASM
  tests are not measured WASM line coverage.
- Inspect survivors rather than treating SDK fallback as blanket equivalence.
  An isolated two-candidate probe uses independently expected `00A0` and `00a0`
  bytes to kill two previously surviving alphabet mutations. Both original and
  restored two-test baselines pass. These assertions are not yet integrated in
  the frozen canonical152 test set, so this is only a probe and does not change
  its complete score. Integrate mixed-class contexts in the next test snapshot.
- Qwen planning/review/triage is advisory; inspect matcher source to reject the
  false suggestion that single-execution success assertions require idempotency.
  The heavyweight GLM backend is unavailable. Preserve failed/truncated review
  attempts separately rather than calling them completed reviews.

### Work151 Registry Contracts And Exact Mutation Scope (Locally Verified)

- Integrate nine isolated registry/body regression groups after Fast151-before
  exits0. Cover connection identity/protocol boundaries, FIFO response ownership,
  close cleanup, send-queue backpressure, inline ownership/overflow and streaming
  completion/errors. Canonical baseline runs all nine and passes. No production
  transport behavior changes.
- Reproduce whole-production-body rejection with actual Cargo mutations and
  same-line test-only admission with adversarial fixtures before fixing either.
  Rust AST metadata identifies exact first-to-last statement spans of production
  functions, impl methods and trait defaults. Require remaining production tokens;
  no empty/test-only-body fallback. Only exact FnValue matches may overlap test
  scopes. Half-open span intersections reject test operators on mixed lines.
  All13 analyzer and32 native mutation tooling tests pass. A real analyzer/Cargo
  integration fixture verifies column normalization and actual assertion evidence.
- Re-audit the frozen registry-b71 inventory without rerunning it. All previous
  source/test/build hashes, exclusions and classifications match; only analyzer
  identity and production-body metadata change. Score49/52 (94.23%), two error
  outcomes, one unwaived platform-guard survivor and19 compile failures. Preserve
  old rejected evidence. Explicit presence/delivery assertions repair the two
  unwrap observations without deleting value checks. The separate registry-c71
  campaign completes51/52 assertion kills (98.08%), one unwaived platform-guard
  survivor and19 compile failures, no errors/timeouts. Original/restored nine-test
  baselines, complete inventory and independent audit agree; canonical/restored
  probe source/test/build hashes match. The score is helper scope, not all native.
  Preserve its initial missing-certificate fixture build failure; no campaign
  ran on that failure, and the corrected baseline runs all nine tests.
- Fresh Cargo151 and ten-group FFI151 collection have equal parsed source scopes.
  Newline-safe union: core8865/10064 (88.09%), FFI4987/5798 (86.01%). Denominators
  and missing-source inventory remain unchanged. Evidence is under
  `out/regression-coverage-2026-09-15/native151-{current,combined}`,
  `native-ffi151-current` and `native151-registry-probe-{b,c}`. Initial Verify151
  passes, then the final-snapshot rerun including the later hosted launcher fix
  also exits0. It runs3319 core and2496 client WASM cases and all68 verification
  script tests; frozen final source/test/config hashes match. The shared native
  window is released. No whole-native98%/95% or green-hosted-chain claim.
- Individual f289d029 hosted diagnostic jobs expose missing transport Cargo.lock
  in fresh Linux/macOS checkouts despite the queued run-level status. Preserve
  artifacts under `hosted151-diagnostics`. Prepare a missing lock in the canonical
  launcher before snapshotting, never relax --locked or rewrite existing locks.
  Launcher fixtures fail before the fix and pass afterward for fresh/existing/
  generation-failure cases; a real offline Cargo fixture accepts the generated
  lock with --locked. MessagePack VM0.44% and Base64 VM67.67% assertion gates also
  fail; their outcomes/runtime applicability need investigation, not exclusions.
  MessagePack JS finishes140/225 (62.22%),57 error-only detections,28 survivors;
  Base64 VM is180/266,38 error-only detections,48 survivors. Both baselines and
  current source/test/support hashes match for these two hosted targets. Improve
  explicit positive-result assertions and investigate survivors without giving
  unhandled errors kill credit.
- Session144 JS completes644 candidates with both baselines passing. Independent
  audit agrees:205/454 assertion-backed kills (45.15%);137 pure assertions and68
  mixed diagnostics,17 error-only detections excluded,122 survivors,110 timeouts,
  190 compile failures, no waivers. Preserve its original snapshot: nine of ten
  source/test/support hashes match current files, but the later145 meta-cache
  test differs. This is not final-current Session evidence. Retain the independent
  audit in `session144-web-mutations/independent-assertion-audit151.json` and its
  explicit hash-mismatch check. No duplicate campaign is started.

### Work150 Native Transport Auth And Diagnostic Trigger (Locally Verified)

- Five pure helper regression groups pass in the canonical and isolated copies. Cover
  TLS/mTLS/bearer precedence, valid UTF-8 parity, malformed byte rejection,
  bearer presence boundaries and preflight opt-in without bypassing TLS/mTLS.
  Do not conflate presence screening with downstream credential validation.
- Initial and second42-candidate probes give38 strict assertions, two mixed/error
  outcomes and two survivors. Preserve those uncredited errors. The final order
  checks a complete wrong scheme before a truncated prefix, preserving every
  assertion while making false acceptance fail before a later indexing panic.
  Final selected-mutations-c gives40/42 assertions (95.24%), two survivors,
  no errors/timeouts/compile failures and no waivers. Both five-test baselines
  pass; independent audit verifies source-scopes-c.json. Individual source-hash
  proofs for the length-boundary equivalents are in the probe README, but neither
  is waived. Inventory review subsequently finds16 whole-function replacements
  omitted by the original `in <function>$` filter. Preserve42 as an operator-only
  probe, not complete helper coverage. A fresh58-candidate complete helper run
  includes all16 replacements:54/56 assertions (96.43%), two compile failures
  and two unwaived survivors, no errors/timeouts. Original/restored five-test
  baselines pass. Independent canonical audit verifies the exact snapshot and
  every outcome; generated full helper inventory exactly matches the campaign.
- Fast150-before exits0 before canonical integration. The shared native window
  was released after Verify149, then reserved again after confirming the other
  task is idle. Preserve the Session144 JS campaign; do not start a duplicate.
- Cargo150 and all ten FFI150 groups finish; parsed source inventories match.
  The newline-safe union measures core8835/10064 (87.79%) and FFI4987/5798
  (86.01%), macOS arm64 only, with missing sources retained. Full Verify150 exits0,
  including3319 core and2496 client WASM cases. The frozen source/test/config
  manifest still matches. The shared native reservation is released.
- GitHub returns404 for the new manual-only Mutation Diagnostics workflow before
  merge. GitHub's [workflow-dispatch rule](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatch)
  requires the file on the default branch; its [push/path filters](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushbranchestagsbranches-ignoretags-ignore)
  permit a branch-push trigger for changes to this workflow. Add that trigger,
  preserving manual dispatch and byte-identical job definitions. One new wiring
  assertion fails first, then all three focused wiring tests pass. Ruby YAML
  parsing confirms sibling events; no actionlint result is claimed. A local
  review's indentation objection is disproved by the actual YAML and parser.
  Require an actual exact-head hosted push run after publishing this change;
  configuration alone is not hosted evidence or a95% diagnostics gate.

### Work151 Isolated Registry Follow-Up (Not Integrated)

- The initial seven-test operator probe completes25 candidates:16 actual
  assertions, eight survivors and one error-only outcome, not17 assertion kills
  despite Cargo's17 catches. Original/restored seven-test baselines pass.
- A separate probe-b adds active RawSocket/WebSocket send-queue/error/close
  contracts and streaming-body delegation, and replaces one unchecked result
  unwrap with an explicit expected-result assertion. All nine tests pass after a
  fresh build. Reusing the earlier source root's Cargo cache initially gave exit0
  with zero tests; preserve and reject that result. Use a distinct target per
  isolated source root. No sockets or shared global native runtime are used.
- The fresh71-candidate helper inventory includes46 whole-function replacements.
  Cargo finishes51 caught,19 unviable and one survivor. Original/restored
  nine-test baselines pass and the full inventory matches. Strict audit rejects
  a production FnValue overlapping nested ffi-test debug blocks before scoring.
  No strict score is established. A real cargo-mutants fixture reproduces this
  failure in native151-audit-probe. Do not filter it away or count an unviable
  candidate as a kill. Next fix needs production-function scope validation while
  retaining test-only/operator rejection and strict assertion classification.
  The sole cfg-to-true survivor is equal on macOS, not proven on unsupported
  platforms, and remains unwaived. This is not canonical integration, a
  whole-native mutation score, or a line-coverage gain.
  Preserve the original Session144 campaign. Local companion suggestions that
  HTTP/3 cannot queue HTTP requests contradict the source; do not adopt them.
  Qwen review completed; GLM judgment was blocked by connection refused at its
  separate local endpoint. Fast151-before exits0 before canonical changes;
  release the shared native window while preparing the auditor fix. Canonical
  Cargo151/FFI151/Verify151 have not started.

- Work150 is pushed asf289d029; PR93 is updated. GitHub now lists Mutation
  Diagnostics active and has exact-head push run35503564490 with all12 expected
  jobs, including native RawSocket/WAMP on Linux/macOS. One Dart job starts.
  Package35503565926, image35503609163 and profile35503610161 are queued.
  Strict audit150 exits1 on incomplete CI and unprotected feature branch;
  the earlier missing-workflow finding is resolved. Preserve its log in
  coverage150-verification. No merge, release or version change.

### Work148/149 Native Target Reproduction And Helper Contracts (Locally Verified)

- Fast148-before exits0 before canonical edits. Add four collector regressions
  and one workflow regression first: the original code gives two assertion
  failures and ten missing-target/CLI errors. Integrate the isolated target
  mapping without changing the default RawSocket invocation, complete candidate
  inventories, source/tool hashes, private Cargo directories, timeout evidence or
  assertion scoring. All29 focused tooling/wiring tests pass afterward, including
  the real Rust and cargo-mutants fixtures. `bin/collect-native-mutations --help`
  lists both targets. Unknown targets fail in the Python collector before its
  filesystem/process effects; the shell wrapper still runs its preflight checks.
- The manual native diagnostic workflow runs both core-rawsocket and core-wamp
  on Linux/macOS. Each matrix entry retains uniquely named artifacts with
  `always()`, independent failures and no error suppression or candidate sampling.
  The existing diagnostic failure policy remains; this is not a claimed95% pass.
- Three native helper regression groups compare generic serializer wire bytes
  and decoded nested values on every segment boundary, reject empty/unsupported
  input and invalid JSON map keys, preserve signed numeric and Unicode conversions
  with exact error labels, and preserve all17 non-payload messages on replacement.
  Existing public wire and ownership regressions remain. All38 canonical WAMP
  tests pass. Five selected surviving numeric/character mutants now produce five
  independently audited assertions with matching38-test original/restored
  baselines and unchanged source hashes. Keep this probe separate from the full
  campaign score; no production behavior or equivalence policy changes.
- Cargo149 coverage completes: wamp.rs1750/1764 (99.21%), core8717/10064 (86.62%)
  and FFI4658/5798 (80.34%) before adding Dart-driven FFI evidence. The unchanged
  production denominator prevents credit from newly added test-only lines. FFI149
  completes all ten groups and its parsed source inventory equals Cargo149's.
  Their newline-safe union measures core8787/10064 (87.31%), FFI4987/5798 (86.01%)
  and wamp.rs1750/1764 (99.21%). Missing sources remain visible. The complete
  canonical core-wamp149 mutation campaign completes399 candidates with matching
  original/restored38-test baselines. It credits273/330 assertions (82.73%),
  with48 errors, six survivors, three timeouts and69 compile failures, no waivers.
  Independent audit agrees on every outcome. Cargo's321 catches are not assertion
  kills. Full Verify149 exits0, including3319 core and2496 client WASM tests.
  The final code/test/configuration hashes still match the frozen149 manifest.
- Companion review was checked against the actual tests/configuration. The
  nested map and expected JSON have identical shapes; unsupported codecs assert
  rejection, not round-trip success. Conditioning artifact upload on a successful
  mutation run would discard required failure evidence and was not adopted.
- Work147 is pushed as c5aeb13d and PR93 is updated. Package dry run, WAMP
  profile35499859544 and image35499858505 pass; main CI remains incomplete.
  Preserve Session144's live isolated campaign; no newer test score is inferred.
- Work148/149 is now pushed as9494ee5f and PR93 is updated. Exact-head CI/package
  checks and image35501906117/profile35501906948 remain queued. Strict audit
  exits1 and also reports Mutation Diagnostics is not discoverable by GitHub;
  do not claim hosted native diagnostic execution. No merge/publication/version
  change. Keep this post-push bookkeeping with the next implementation commit.

### Work147 Native Assertion Oracles And Completed MCP Evidence (In Progress)

- Fast147-before exits0 before canonical edits. Integrate six native groups:
  all nine CBOR payload variants retain original wire bytes and allocation,
  length words preserve nonuniform bytes across offsets/segments, exact CBOR
  headers and MessagePack payload header widths are checked, HEARTBEAT preserves
  its existing serializer-specific null contract, and CALL identifiers preserve
  positive integer widths and reject negative wraparound.
- Replace test unwraps and custom panic-only observations with explicit success,
  presence, rejection and message-variant assertions. Preserve all previous
  payload/ownership/error assertions and add two fixed helper controls proving
  value/error identity and false-expectation assertion diagnostics. The helper
  controls catch only their own fixed failures, not production parser calls.
  The production parser prefix and mutation auditor are unchanged. An old
  unsupported-serializer test now asserts its formerly discarded `matches!`.
- All35 canonical native WAMP tests pass. A selected17-candidate probe now has
  17 independently audited assertions and matching35-test original/restored
  baselines, versus13 assertions/four errors before strengthening. This is not
  a full score. Preserve compile-only probe errors separately. A fresh complete
  native147 campaign finishes all399 candidates on a private snapshot whose
  hashes exactly match canonical native sources/tests/fixtures. Original and
  restored35-test baselines pass. The strict audit credits268/330 assertions
  (81.21%),48 errors,11 survivors, three timeouts and69 compile failures; no
  waivers. Cargo's316 catches (95.76%) do not meet the assertion-backed gate.
  Preserve all individual logs and operator outcomes in native-wamp147-mutations.
  Cargo147 and all ten FFI147 groups complete with identical parsed source
  inventories. The newline-safe raw union in native147-combined measures core
  8765/10064 (87.09%), FFI4987/5798 (86.01%) and wamp.rs1726/1764 (97.85%).
  Core has one unmeasured source and FFI three; this is macOS arm64 evidence,
  not other-platform or legacy-ABI completion. Full Verify147 exits0 including
  2496 client WASM cases, with frozen147 inputs unchanged. A fresh canonical-tool
  audit independently agrees on every native outcome, count and score. Preserve
  the verification logs and input manifest in coverage147-verification.
- Final helper review was checked manually: `as_ref()` borrows the original
  error, and Rust captured-format syntax retains context; the suggested
  ownership/format defects are not present. No production panic is intercepted.
- Next integrate native148-runner-probe after a fresh fast gate. Its four new
  tests cover target/source/filter identity, default compatibility, CLI argument
  forwarding, unknown-target rejection before effects, and incomplete timeout
  evidence. Initial missing-target API errors are preserved; all27 isolated
  tooling tests then pass, including real Rust/cargo-mutants fixtures. Add
  core-wamp alongside core-rawsocket to the canonical collector and Linux/macOS
  diagnostic matrix with a fail-first workflow guard. Do not claim this probe
  as canonical verification. Qwen review did not complete; Gemma's suggested
  missing nested WAMP tests is contradicted by the actual35-test inventory.
- MCP144 completes all1098 candidates, original/restored baselines pass and
  independent audit agrees:812/836 assertions (97.13%),24 survivors,262 compile
  failures, no waivers, no timeouts or error-only kills. The report retains583
  pure assertion and229 mixed diagnostic outcomes. All36 source/test/support
  hashes still match. This measures the MCP library target, not CLI coverage or
  the complete package/runtime milestone. Inspect remaining lifecycle and
  capability survivors; no security-critical survivor is waived by assumption.
- Work146 is pushed as e1f4b785. Its package dry run and WAMP profile gate pass;
  image/main CI are incomplete. Strict audit exits1 while those checks remain
  unfinished. Preserve the original Session144 JS campaign; it is still live.

### Work146 Native Message Boundaries And Meta CI Gates (In Progress)

- Fast146-before exits0 before canonical changes. Add twelve table-driven native
  regressions for25 known variants and unknown messages, per-field missing/type
  errors, payload absence/null/empty/populated values and invalid shapes, every
  split boundary, MessagePack markers/widths/truncations, CBOR array headers,
  optional metadata/counters, invalid codes and buffer ownership/reader behavior.
- Initial run has a genuine boundary assertion failure: JSON and MessagePack
  ignore trailing values/garbage in contiguous and segmented inputs; segmented
  CBOR does too. A second failure is a test assumption: JSON non-string fields
  already yield Deserialize rather than ExpectedString. Correct that oracle,
  retaining exact rejection behavior rather than changing public errors.
- Require end-of-input after JSON and segmented CBOR deserialization and exact
  consumed length for MessagePack. All27 WAMP tests pass afterward, including
  valid JSON whitespace and unchanged lazy binary payload bytes/ownership.
- Protocol rationale: [WAMP Basic Profile](https://wamp-proto.org/wamp_bp_latest_ietf.html)
  transmits one WAMP message per unbatched WebSocket message; [RawSocket framing](https://github.com/wamp-proto/wamp-proto/blob/master/_work/rawsocket-transport.md)
  bounds one serialized WAMP message. [Batched WebSocket framing](https://wamp-proto.org/wamp_latest_ietf.html)
  is a separately negotiated format, not permission to discard extra serialized
  values. Therefore rejecting suffix bytes is a protocol-boundary correction,
  not a new application feature or change to valid message serialization.
- The meta-cache CI wiring test fails before adding both VM/JS targets to the
  matrix, Chrome setup and strict-audit job inventory. Preserve default95%
  assertion-backed threshold, complete inventories and always-uploaded evidence.
- Cargo146 and all ten Dart-driven FFI146 groups pass on frozen inputs. Parsed
  source-scope inventories match; the newline-safe raw LCOV union gives core
  8758/10064 (87.02%), FFI4987/5798 (86.01%), wamp.rs1718/1764 (97.39%).
  Investigation of the FFI denominator exposes malformed144 concatenation:
  `end_of_recordSF:` assigned the next report's first source to the previous
  source. Its union totals are invalid, not a baseline for claiming FFI gains.
  Preserve it unchanged as counterevidence. Verify146 completes exit0 including
  2496 client WASM tests, with frozen hashes unchanged. Two canonical LCOV tests
  then reproduce five missing-rejection assertions before the reader fix. All15
  native coverage tests pass afterward, including a real LLVM fixture. Valid LF,
  CRLF and no-final-newline inputs retain per-file attribution; the malformed144
  report is rejected, and re-filtered146 production LCOV is byte-identical.
  Follow-up Verify146b includes the tooling fix and exits0, including2496 client
  WASM cases; the final source/test/config manifest still matches. Hosted
  main CI remains incomplete;2155af06 package/image/profile checks pass.
  Preserve live MCP144 and
  Session144 campaigns; new native tests do not upgrade their snapshot scores.
- Narrow Gemma review completed. Its suggestions about missing full-consumption
  checks are contradicted by the complete parser paths and boundary regressions;
  no unsupported review finding is used as evidence.
- The LCOV Qwen review hit its output limit. A narrower Gemma review completed;
  its suggested CRLF defect is contradicted by `splitlines()` and the passing
  CRLF regression. Do not strip malformed suffix whitespace as suggested. GLM
  was independently unreachable. Native follow-up ideas likewise contained
  incorrect CBOR widths; use independently checked wire fixtures instead.
- Full native WAMP146 completes all399 generated candidates on the private
  snapshot; original/restored27-test baselines pass and source hashes match.
  Cargo marks295 caught, but the independent strict audit credits only12/330
  viable candidates (3.64%):283 error outcomes,32 survivors, three timeouts and
  69 compile failures. No waivers. The conventional295/330 (89.39%) is not an
  assertion score. Preserve every raw log, inventory and diagnostic classification.
  Many failures are test unwraps/custom panic diagnostics, with genuine mutated
  production panics also present; none gets assertion credit by assumption.
- Isolated follow-up147 adds five groups for all nine CBOR payload ownership/
  byte-preservation paths, nonuniform big-endian lengths, MessagePack payload
  array/map header widths and existing HEARTBEAT null-counter behavior. All32
  tests pass; preserve the initial module-path error and incorrect assumption
  that CBOR accepts null counters. Seventeen selected probes yield13 clean
  assertion kills and four mixed errors; thirteen previously surviving cases now
  assert. This is a selected probe, not a complete replacement mutation score,
  and the follow-up tests are not yet integrated into canonical sources.

### Work143/144 GOODBYE And CI Mutation Observation

- Integrate the six-case GOODBYE probe, including observer error-identity
  controls, into fast/full VM, JS/WASM, browser coverage and both Session
  mutation targets. Command-selection tests fail before wiring and pass after;
  all64 verification-script tests pass. All418 selected Session cases pass on
  VM/JS/WASM. JS143 core96.01%/client95.86% still misses98% and retains162
  unmeasured sources. Do not infer WASM line coverage from runtime passes.
- Hosted head890ae621 PR/push CI fails remote-WAMP mutation completeness and
  cancels MCP before its complete inventory finishes. Download raw artifacts
  into ci143-remote-pr/ci143-mcp-pr. Remote independent audit agrees197/202
  assertions, two survivors and three timeouts. MCP has974/1098 outcomes;
  its partial score is not a completed campaign or release result.
- Fast144-before passes before canonical edits. The credential fixture now
  caps reads and asserts non-convergence without a production limit; registry
  warmup and authenticator-factory fixtures share that same real-I/O config.
  Assert current RPC ownership before waiting for retired socket closure.
  All221 canonical remote tests pass. Final isolated full-target probes for
  the three CI timeouts produce33/33/5 real assertions and no timeouts.
- MCP pending subscribe tests race callback entry with request completion,
  assert initialization success and forbid cleanup before subscription
  completion. All25 canonical WAMP API tests pass. Across separately hashed
  iterations, eight selected former timeout mutants terminate with assertions.
  Preserve mixed errors and
  earlier failed probe variants; no scoring, threshold or production changes.
- Native Cargo143 and native FFI144 collections finish. FFI collection runs
  all10 groups with frozen inputs and an isolated instrumented library. Parsed
  source scopes match exactly, permitting raw LCOV union: ct_core8509/10052
  (84.65%), ct_ffi5103/5966 (85.53%). Keep individual reports, missing-platform
  sources, legacy-ABI limitations and native mutation gaps visible.
- Independent Session140 audit finishes:170/454 assertion-backed kills (37.44%)
  versus192/454 conventional kills (42.29%),153 survivors,108 timeouts, one
  error and190 compile failures. This predates143/144; do not attribute it to
  their tests. Latest completed VM line report remains VM142 (91.10%).
- Verify144 exits0, including2491 client WASM cases. Frozen code/test hashes
  and the standard native artifact remain unchanged. VM144 collection then
  exits0:38874/42673 library lines (91.10%),59 unmeasured sources. The one-line
  router variation is unchanged-code timing evidence. Packaging765/787 (97.20%)
  retains12 unmeasured sources; all explicit98% VM/JS/packaging audits fail.
- Remote144 completes all303 candidates and both baselines pass. Independent
  audit agrees199/202 assertion-backed kills (98.51%),200/202 conventional
  kills (99.01%), two survivors, one error-only failure,101 compile failures,
  no timeouts and no waivers. Its95% gate passes. The uncredited generation
  invalidation mutant5b5d72d1d64446c3ca1f needs a behavioral assertion rather
  than19 StateErrors. Keep the two previously investigated survivors visible.
- MCP144 remains running; start exactly one fresh Session144 JS campaign now
  that Session140 is complete. Do not attribute their partial results to a
  completed score. Work143/144 is pushed asbfd7af64; PR93 is updated. Both
  package dry runs, Router Image35494454118 and WAMP Profile35494455136 pass.
  Main CI35494381468/35494380114 is incomplete and strict audit exits1.
  No merge, publication or version change.
- Qwen planning completed; disregard its suggestions to call private session
  methods or expect a previously received HELLO to disappear. Debug/review
  attempts timed out or reached output limits; independent GLM endpoint is
  unreachable. Manual review and original/restored baseline evidence remain.

Evidence: remote144-investigation, mcp144-investigation, native143-current,
native-ffi144-current, native144-combined, browser143-current and live
remote144-vm-mutations/mcp144-vm-mutations beneath
out/regression-coverage-2026-09-15. Raw verification logs are
/tmp/connectanum-coverage144-{fast-before,verify}.log. Thresholds remain98%/95%.

### Work145 Meta Event Error Oracles

- Fast145-before exits0 after VM144 completes and before canonical edits.
- The integrated meta145-investigation test copy retains existing malformed-event
  state/recovery assertions, adds snapshot identity and observes independent
  asynchronous dispatch errors. Five controls preserve synchronous/asynchronous
  StateError/TestFailure identity and verify real dispatch-error capture.
- All102 cases pass original/restored baselines on VM/JS/WASM. Selected
  argument mutants9cd52f2a0e836509a21c,bb7662936b00da3a3da4 and
  4b04095d65f5bcae7ebe now yield8/2/7 assertions on VM/JS, zero test errors.
  This is not a complete campaign score or WASM line coverage.
- Source hashfab21ee1da2b2796ad911327e88f621623422d716790295b01f19aba83b08f96
  matches139. The investigation README records individual proofs for one
  equal-branch comparison, the unreachable fixed-topic dispatch default and two
  internal-list growability mutants. The four proofs are now individually pinned
  in both VM/JS equivalence manifests. Other survivors remain unwaived; never
  treat unchanged test results alone as proof.
- Complete157-candidate meta145 VM campaign and independent log audit agree:
  93/101 raw assertion kills (92.08%),93/97 adjusted (95.88%), four waived and
  four unwaived survivors,56 compile failures, no timeouts or error-only kills.
  Initial/restored baselines pass; the95% gate passes without changing thresholds.
- Full meta145 JS campaign and its independent audit agree with VM:93/101 raw,
  93/97 adjusted, four equivalent waivers,56 compile failures and no timeouts or
  error-only kills. Both baselines pass. Verify145 exits0, including2496 client
  WASM tests, with frozen source/test hashes matching afterward. Keep MCP144
  and Session144 campaigns alive on their existing snapshots. Local Qwen and
  broad Gemma attempts did not finish; GLM is unavailable. A narrow Gemma helper
  review completed with no concrete findings; its generic risks do not contradict
  the inspected single-completion flow or error-identity controls. Enable the meta CI
  gates next and target larger native WAMP parser gaps after serialized Fast146.

### Work142 Inbound E2EE Context And Native Error Contracts

- Fast142-before passes before canonical edits. Add 24 EVENT/INVOCATION cases
  crossing native/materialized input, actual/fallback URI and metadata presence,
  plus a prefix-registration peer-authentication case. Assert decrypted content,
  local/peer identity, event-only trust metadata and correlated invocation reply.
- Add real-native invalid-resource and wrong-protocol tests, optional-capability
  defaults, idempotent cleanup and failed TLS reload recovery. Source inspection
  corrects two initial test assumptions: optional WebSocket polling returns zero
  on non-WebSocket connections; TLS reload counts cleartext listeners too.
  Preserve failed initial probes; no production fix or mutation credit claimed.
- All412 canonical Session cases pass VM/JS/WASM; all28 native runtime cases pass.
  Analysis/formatting pass. Full VM142 and JS142 collections finish exit0 on
  frozen inputs. VM38875/42673 (91.10%), client8655/9408 (92.00%), router17147/
  19386 (88.45%),59 unmeasured sources. Native runtime gains45 covered lines to
  1239/1521 and Session gains one to993/1027; other router variation is not
  attributed to these tests. JS core7383/7690 (96.01%), client2615/2728 (95.86%),
  162 unmeasured sources. Packaging765/787 (97.20%),12 unmeasured sources. All
  explicit98% audits fail. Original serialized Verify142 exits0 after VM142,
  including3319 core/2485 client WASM cases. Final input/native hashes match;
  no native consumers remain.
- Three isolated single-mutant probes (lost materialized invocation URI, lost
  native event URI, forced native trust presence) run all117 copied client cases
  on VM/JS and produce3/4/8 assertion failures respectively, zero other errors.
  Preserve session142-context-investigation and native142-investigation evidence.
  These are individual non-equivalence proofs, not new complete mutation scores.
- Native reservation explicitly extends through143. Older Session140 JS campaign
  continues without duplication. Bundle141/142 implementation and state after
  full verification; no merge, publication or version change.
- The isolated six-case GOODBYE probe passes VM/JS/WASM. Three individual mutant
  probes yield4/2/3 actual assertions on VM and JS, zero other errors. Controls
  preserve action exception identity across zones. Preserve initial compile and
  wrong-browser-root setup failures separately. Integrate after Fast143, then
  refresh coverage, including the older Cargo/Dart-driven native measurements.
  Single-mutant probes do not upgrade complete campaign scores.

### Work141 Healthy Session And Startup Failure Oracles

- Fast141-before exits0 before canonical integration. Add connected-state checks
  after normal successful handshakes in client/meta/lazy/progressive fixtures,
  including timeout-wrapped setups. Preserve immediate-GOODBYE fixtures.
- Nine startup tests cover named authenticator selection, synchronous challenge
  errors, receive error/closure and early GOODBYE identity, verifier failure with
  throwing close, and cancellation of later methods despite one cleanup failure.
- Await the mock's existing1ms receive delivery before asserting captured
  invocation replies. No guessed longer sleep, new timeout, production change,
  classifier change, waiver or lowered threshold. Retain failed initial probe
  ordering and cascade-compile experiments as failures, never mutation credit.
- All387 canonical cases pass VM/JS/WASM; analysis and formatting pass. Three
  isolated mutants run all387 cases on VM/JS and terminate with323/1/1 actual
  assertions respectively, zero other errors. They do not upgrade full scores.
- JS141 completes exit0: core7383/7690 (96.01%), client2612/2726 (95.82%),
  retaining162 unmeasured sources. VM141 finishes exit0: library38820/42673
  (90.97%), client8654/9408 (91.99%), router17093/19386 (88.17%),59 unmeasured
  sources. Packaging765/787 (97.20%) retains12 unmeasured sources. All98% gates
  still fail. Session VM gains18 covered lines to992/1027; unchanged-code router
  variation is not attributed to these tests. Original serialized Verify141
  exits0, including2460 client WASM cases; final input/native hashes match and
  no native consumers remain. Fast142-before starts before integration.
  Reservation explicitly extended through142. Original Session140
  JS campaign continues on its older snapshot without duplicate campaigns.
- Work140 e433d615 pushed; both package dry runs pass, image/profile and main CI
  running; main CI queued. Strict audit remains non-green. Full98%/95% goal
  remains incomplete.

### Work140 Session Oracles And Native Message Dispatch

- Integrate the proven Session probe after Fast140-before exits0. Await actual
  PPT RESULT and assert its complete metadata/payload; correct fake-router YIELD
  conversion and progressive keyword setup. Observe five expected WAMP errors
  directly without swallowing StateError/TimeoutException. Four helper controls
  prove the distinction. No runtime timeout is converted into a mutation kill.
- Four new portable native-message cases cover ordinary RESULT request matching,
  unknown/retired IDs, mixed EVENT consumers and unsubscribe wire identity, and
  materialized INVOCATION response/interruption plus unregistration. These do
  not claim actual FFI ownership or Rust execution coverage. Explicitly close
  fixture controllers with listeners still attached, then cancel listeners.
- All83 canonical cases pass VM/JS/WASM; formatting and analysis pass. Retain
  initial root-launched browser failures due to fixture-relative script paths;
  package-root runs pass. Session139 isolated evidence remains hash-matched.
- Full VM140/JS140 collections finish exit0. VM38814/42673 (90.96%), client
  8636/9408 (91.79%), router17105/19386 (88.23%);59 unmeasured sources remain.
  Packaging765/787 (97.20%) retains12 unmeasured sources. JS core7383/7690
  (96.01%), client2593/2726 (95.12%);162 unmeasured sources remain. All98%
  audits fail. Session VM gains10 covered lines to974/1027; other unchanged-code
  line deltas are timing-dependent, not credited to the new tests.
- Original serialized Verify140 finishes exit0, including2451 client WASM cases.
  Final source/test/native hashes match; no native consumers remain. The one
  Session140 JS campaign remains live on its isolated snapshot; never relabel
  its eventual result as evidence for later tests. Reservation extension through
  Work141 is requested, not yet confirmed.
- Isolated five-file readiness copies pass all378 cases VM/JS/WASM; a single
  incomingClosed=true mutant produces322 actual assertions and no other errors
  on VM/JS. Six startup probes cover named auth selection and early failures.
  Preserve initial mixed-timeout and invalid browser-launch evidence. Integrate
  only after the next fast baseline; isolated probes do not upgrade full scores.
- Pushed ede8ab16 includes Work139. Package/image/profile checks pass; main CI
  remains queued and strict audit exits1. Full98%/95% scope remains incomplete.

### Work139 Fingerprint And Startup Ownership Regressions

- Integrate the previously isolated completed-replacement fingerprint probe as a
  canonical test, using a typed forwarding configuration and real secret rotation.
  Assert RPC connection indexes[0,1,1], not the mutant's[0,1,2]. Integrate both
  meta healthy-startup probes with pre-disposal ownership assertions and later
  event delivery. All221 remote tests and97 meta tests on VM/JS/WASM pass.
- Observe concurrent call settlement alongside peer receipt, preserving genuine
  errors and teardown joining. Observe retired socket closure before reusing a
  cached connection. Do not relabel deadline expiry or infinite mutated retries
  as assertions. No production, inventory, classifier, waiver or threshold change.
- Fast139-before and analysis pass. Complete157-candidate meta139 VM/JS campaigns
  and independent audits agree:90/101 assertion kills (89.11% raw/adjusted),
  eight survivors, three error-only outcomes,56 compile failures, no timeouts
  or waivers. Both baselines pass;95% gates still fail. Original Verify139
  exits0, including2443 client WASM cases; final input/native hashes match and
  no native consumers remain. Complete303-candidate remote139 and independent
  audit agree:197/202 assertion kills (97.52% raw/adjusted), two survivors,
  three timeouts,101 compile failures, no error-only kills or waivers. Both
  baselines pass; the gate still fails on timeouts. Work140 fast baseline runs
  under the explicitly extended native reservation.
  Current line measurement remains138; do not attribute it to139 tests.
- Pushed552ab403 package/image/profile checks pass and main CI
  is queued. Parent04b9aa33 consumer failure is a published beta.5 checksum HTTP500,
  not a test assertion. Same URL now returns200; one job retry request was refused
  because the parent workflow remains active. Preserve its log and current strict
  audit findings. Do not bypass published package consumption or cancel campaigns.
- An isolated Session probe restores inert PPT result assertions and correct
  fake-router RESULT framing, fixes progressive keyword setup, and replaces five
  error-completer waits while preserving unexpected error identity. All79 copied
  cases pass VM/JS/WASM. An earlier isolated incomingClosed mutant fails an
  actual readiness assertion on VM/JS, not a deadline. Integrate after fast140;
  do not attribute isolated probes to the older Session134b mutation score.

### Work138 Generation-Owned Remote Sessions

- Reproduce nine actual assertions across ten new remote-auth wire cases on
  original source before changing behavior. Own session installation, RPC results,
  failure cleanup and disconnect callbacks by generation; retry current state
  after stale fingerprint I/O. Preserve public WAMP behavior and best-effort
  warmup/abort. All220 remote tests, Fast138-before and analysis pass. Keep the
  original failing logs/source hash; a mistaken nonexistent-file test command is
  separately retained as a command error, not a production regression.
- Integrate two meta-cache disconnect-order tests. Full157-candidate VM/JS
  campaigns and independent audits agree:88/101 assertion kills (87.13% raw/
  adjusted), eight survivors, five error-only outcomes,56 compile failures;
  no timeouts/waivers. Both baselines pass;95% gates still fail. Never upgrade
  the score using separate ignored probes or by crediting generic test errors.
- Fresh VM138 exits0:38799/42673 library lines (90.92%),59 unmeasured sources;
  packaging765/787 (97.20%),12 unmeasured sources. Fresh JS138 exits0: core
  7383/7690 (96.01%), client2582/2726 (94.72%),162 unmeasured sources. All98%
  audits fail. Preserve exact per-file delta:20/22 new delegate covered/measured
  lines, plus timing-dependent socket/router changes in unmodified production.
- Original Session134b JS campaign completes with140/451 assertion kills
  (31.04%),178 survivors,23 error-only outcomes,108 timeouts, two infrastructure
  errors and190 compile failures. Both baselines and independent audit agree.
  Its recorded source/tests are older, not current138 inputs. Keep renderer
  cleanup failures uncredited even when the test process has passed or asserted.
  Triage finite procedure-registration/invocation observations and cleanup before
  refreshing the full Session campaign; do not increase deadlines to force a pass.
- Full remote138 campaign and independent audit agree:193/202 assertion kills
  (95.54% raw/adjusted), three survivors, one error-only outcome, five timeouts
  and101 compile failures. Both baselines pass; gate fails on timeouts. Original
  serialized Verify138 exits0, including3817 router,3319 core WASM and2441 client
  WASM cases. Final input/native hashes match; no native consumers remain.
  The confirmed shared native reservation continues into Work139 verification.
  Preserve coverage138-verification and full reports. New remote fingerprint
  survivor afa0f0b40a8bbada4530 is proven non-equivalent by an ignored real-wire
  probe: a delayed old fingerprint opens a third connection after its replacement
  has completed. No waiver or current-score credit. Two ignored meta probes also
  produce independent premature-UNSUBSCRIBE assertions while retaining original
  errors; full copied97-case suite passes VM/JS/WASM. Integrate these after
  frozen verification, refresh matching campaigns, then address larger
  Session/router/native coverage gaps. Complete98%/95% scope remains open.

### Work137 Remote Authentication Behavioral Assertions

- Add13 canonical regressions: an old failed warmup cannot clear replacement
  connection ownership; repaired cryptosign-file warmup must establish one real
  HELLO; public authenticators preserve safe HELLO/AUTHENTICATE denial payloads
  across six RESULT/ERROR shapes without authorizing conflicting success fields.
  Release held responses and join pending work; genuine timeouts remain errors.
- All210 focused tests and frozen Fast137-before pass. Full292-candidate campaign
  and independent saved-log audit both exit0:189/191 assertion kills (98.95288%
  raw/adjusted),100 assertion-only,89 mixed, two survivors and101 compile errors.
  Initial/restored baselines pass; no timeout, error-only or waiver credit.
  Candidate IDs and source/support/runner hashes match136b. All six old error-only
  cases and the connection-identity survivor now have behavioral assertions.
  Source-inspect both remaining survivors (absent-field early return and internal
  list growability), retaining them unwaived. No production/classifier change.
- Complete VM137 collection exits0:38784/42651 library lines (90.9334%),59
  unmeasured sources; packaging765/787 (97.2046%),12 unmeasured sources. Both98%
  audits fail. Preserve the exact per-file delta: six socket partial-frame lines
  lose observations and12 unchanged router lines gain them. Do not attribute
  those timing-dependent differences to the new authentication tests. JS136
  selected inputs are unchanged. Original serialized Verify137 exits0, including
  3807 router,3319 core WASM and2439 client WASM cases. Final source/dependency/
  native hashes match; release the native reservation after confirming no users.
- Ignored meta137-investigation proves four non-equivalent disconnect-ordering
  mutations using unwanted wire unsubscribes, without exception-to-assertion
  wrappers. The copied95-case suite passes VM/JS/WASM. Integrate its two new
  cases after frozen verification, then collect separate canonical evidence.
  Preserve source/config/probe hashes, each mutated copy, logs and companion
  adjudication; no full-campaign score is changed by these probes.
- Preserve coverage137-verification, remote137-mutations, vm137-current and
  meta137-investigation. Pushed28adca89 package/image/profile checks pass; main
  CI stays queued. The original full Session JS campaign continues on its own
  older snapshot. The complete98%/95% milestone remains open; no merge/release.
- Next correctness priority: remote137-investigation reproduces stale successful
  connection installation after reset. Complete a replacement, verify a real RPC
  uses connection1, then release connection0's late WELCOME; the next RPC uses0
  instead of1. Retain actual failing assertion/source hashes. Integrate before
  fixing attempt/session ownership, and inspect stale disconnect callbacks;
  Work137 changes no production behavior and does not fix this new finding.

### Work136 Progressive Native File Lifecycle

- Reproduce13 actual assertions among40 portable cases on original VM/JS/WASM
  source before adding a pending-call guard to the native encrypted-file branch.
  Reject after Result, canceled/timed-out/unauthorized Error, disconnect or result
  listener cancellation, without retiring another active call. Check before E2EE
  preparation/send; retain source-opening/ownership and zero-copy forwarding.
- All40 cases pass on each runtime after the fix. Positive controls independently
  assert exact request/source/range/options/context and no extra buffered packing;
  preparation/send failures preserve retryability and do not finish/close sources.
  This is portable boundary evidence, not native crypto/performance measurement.
  Canonical VM/browser verification, coverage and complete Session mutation targets
  retain the whole suite. All64 selection controls pass; no classifier/threshold/
  operator/waiver changes. The original session134b campaign keeps its old hashes.
- First Fast136 exits127 after a live script edit invalidates Bash's input offset.
  Preserve it as failed harness evidence. Frozen-input Fast136 exits0. Fresh JS136
  passes3327 core and2439 client cases without skips: core7383/7690 (96.0078%),
  client2582/2726 (94.7175%),162 unmeasured sources. The explicit98% audit fails.
  VM136 exits0: library38778/42651 (90.9193%), client8632/9408 (91.7517%),59
  unmeasured sources; packaging765/787 (97.2046%),12 unmeasured sources. Both
  explicit98% audits fail. Original frozen-input Verify136 exits0; final input and
  native hashes match. Release its native reservation only after observing the
  original terminal result; a new reservation covers the136b refresh.
- Inspect and independently audit parent CI35431908342 remote-WAMP artifact:
  292 candidates,191 viable,149 assertion kills, six uncredited error-only outcomes,
  33 timeouts, three survivors and101 compile errors. Assertion score78.0105%; no
  waivers. All33 timeouts include remote_wamp_delegate_wire_test.dart line227's
  impossible HELLO wait after an early mutated warmup failure. Current source/test
  hashes match. Work136b races HELLO against early settlement while retaining
  held-WELCOME sequencing/cleanup and propagating genuine TimeoutException.
  All197 focused tests pass. Full292 mutations and independent saved-log audit
  agree:182/191 assertion kills (95.28796% raw/adjusted), three survivors, six
  error-only outcomes and101 compile errors. Both baselines pass with no timeouts
  or waivers. Compare identical candidate IDs and production/support/runner
  hashes: all33 former timeouts now have actual assertion evidence (eight
  assertion-only,25 mixed). Historical timeout outcomes remain unchanged.
  VM136b exits0 with unchanged measured totals and failed98% target audits;
  original frozen Verify136b exits0, including2439 client WASM cases. Final
  source/dependency/native hashes match; release the native reservation only
  after verifying no remaining consumers.
- An ignored public-API probe demonstrates survivor36559fd15fde79a61e99 is
  non-equivalent. Hold an old ABORT, clear the registry, start a replacement and
  hold WELCOME; finish the old failure and start another warmup. Original source
  shares two connections; the isolated guard-removed package opens three and
  fails the explicit count assertion. Initial mistaken best-effort error and
  duplicate-type compilation attempts are retained, not counted as kills.
  Integrate the regression and rerun complete evidence separately; this probe
  does not belong to the running136b campaign's hashes.
- Parent81b3a76e package/image/profile checks pass but main CI stays queued. CI
  triggers both push and pull_request without concurrency, so duplicate runs are
  visible; do not cancel unfinished mutation evidence merely to clear the queue.
  Preserve coverage136-verification, coverage136b-verification, browser136-current,
  vm136b-current, remote136b-mutations, remote136b-investigation and
  hosted136-parent-remote-wamp. Push this implementation increment and refresh
  hosted checks/strict audit. The complete98%/95% milestone remains open.

### Work135 Complete Authentication Lifecycle Mutation Oracles

- Download and independently audit the complete hosted parent auth-server and
  HTTP-auth reports. Their19 and13 timeouts include earlier assertion failures;
  preserve timeout precedence rather than regrading those campaigns as passing.
  The timeout stack traces identify three auth lifecycle tests and one HTTP
  stalled-body test. Their pre-edit hashes match the hosted inputs.
- Observe HELLO completion over the existing finite microtask drain while the
  provider callback remains held. Retain all capacity, reentrant/duplicate
  cleanup, status and late-error assertions; release callback/cleanup holds in
  teardown even when assertions fail. The observer does not catch Future errors,
  so real exceptions/timeouts remain visible to the test runner. The HTTP test
  races response entry against authentication, observes the configured500ms
  deadline with the body still held, releases it and joins the original operation.
  It asserts an already-returned auth_timeout result, not a watchdog exception.
- Fast135-before, all367 focused auth/HTTP cases and original Verify135 exit0.
  Analysis is clean; frozen input and native hashes match. Verification includes
  3794 router,753 benchmark,3319 core WASM and2399 client WASM cases. Native users
  have finished and the shared runtime window is released. No new line-coverage
  measurement or WASM instrumentation claim; existing missing scopes remain.
- The original complete auth135 process exits0:294 auth-server candidates have
  182 assertion-backed kills (160 assertion-only,22 mixed), seven survivors and
  105 compile errors. Raw/adjusted score96.2963%, no waivers. All274 HTTP-auth
  candidates have186 assertion-backed kills (159 assertion-only,27 mixed),11
  survivors and77 compile errors. Raw94.4162%, adjusted98.9362% with exactly nine
  pre-existing source-hash-pinned equivalents; two other survivors remain.
  Both initial/restored baselines pass; no timeout/error-only/crash credit.
  Independent saved-log audit and current source/test/support hashes agree.
  Both unchanged95% gates pass. All32 formerly timed-out candidates now contain
  actual assertion evidence. Inventories, production and classifier are unchanged.
- All seven auth survivors/source hashes match the prior individual control-flow
  investigation; copy that evidence and its equality check, without adding a
  waiver or deleting defensive guards. Qwen review's alleged missing HTTP
  teardown contradicts existing setup. Retain true exception propagation and
  the finite in-memory oracle, rather than following advice to weaken thresholds.
- Preserve auth135-mutations and coverage135-verification with logs, hash checks,
  companion advice, survivor notes and per-candidate before/after comparisons.
  Parent e8118321 hosted Fast Checks now passes, confirming Work134's fixture fix.
  Package/image/profile checks pass; main CI still contains the pre-Work135 auth
  gate failure at86.24%. Collect candidate hosted evidence after this test/code
  increment. Strict branch-protection/default-workflow findings remain separate.
- Keep original session134b JS process running; its641-candidate inventory is
  isolated and not attributable to later test/source changes. Next address any
  fresh CI failure, then the confirmed progressive encrypted-file terminal-state
  bug. The complete per-component/runtime98%/95% objective remains open; no
  merge to master, publication or version change.

### Work134 Native Reply Payloads And Portable Mutation Fixtures

- Reproduce33 native reply assertion failures in the corrected86-case probe on
  VM/JS/WASM before changing production. Share outbound lazy payload packing with
  the normal path and attach Yield E2EE context first. Preserve packed-byte
  identity for matching encodings, transcode mismatches, preserve empty values,
  and use explicit fallbacks only for null payload members. The final118 portable
  regressions cover payload forms, three serializers, progressive/final replies,
  closed/error handling and real Dart E2EE. They model the native message boundary,
  not FFI execution. Six separate real-native RawSocket/WebSocket serializer cases
  verify72 RPCs with a dedicated callee isolate and bounded cleanup.
- Select full reply/profile suites in canonical VM/browser verification and
  measurement. Add complete641-candidate Session VM/JS targets without claiming
  passing gates. Move the genuine native-provider client test to the native suite,
  preserving all six assertions and awaiting the publish. Keep it in the VM
  mutation target; portable client tests no longer skip a native-only case.
  The unchanged classifier accepts the326-case clean JS campaign baseline.
- Hosted Fast Checks failed after bootstrap resolved test1.32.0 but the isolated
  reporter fixture demanded offline test1.31.2. Copy the workspace lock into the
  fixture and retain real offline resolution and the four-target classifier
  campaign. Mocked version controls verify both lock snapshots. All64 runner
  controls (one Linux-only skip) and64 verification-script controls pass. No
  classifier, inventory, timeout-credit or threshold weakening.
- Original Fast134-before and frozen-input Verify134b complete with exit0.
  Final input/native hashes match. Native integration, packaging/consumer smokes,
  router3794, bench753, core3319 WASM and client2399 WASM pass; final JS also
  passes2399 client cases with zero skips. Analyzer is clean. Native users are
  finished and the shared runtime window is released. Preserve original logs,
  hashes, companion reviews and corrected failing probes in coverage134-verification.
- VM134 measures38770/42649 (90.90%) with59 unmeasured library files, before the
  final native-test move. Packaging765/787 retains12 unmeasured sources. Final
  browser134b is core7382/7689 and client2527/2666, with162 unmeasured sources;
  the denominator changes partly because the native-only stub left JS. Explicit
  98% audits fail; WASM passing tests are not measured line coverage. Preserve
  historical snapshots instead of reattributing them to final harness inputs.
- Full157-candidate meta134 VM/JS campaigns agree:84/101 assertion kills,
  56 compile failures, six uncredited error-only outcomes and11 survivors.
  Raw/adjusted assertion score83.17%, no waivers; initial/restored baselines and
  independent saved-log audit pass. Both95% gates fail. Session134b JS remains a
  live full641-candidate campaign with isolated, hash-pinned inputs; do not restart
  or relabel it as later-source evidence.
- Parent5ece94bb hosted package/image/profile checks pass. Main CI has failed
  Fast Checks and auth-server/http-auth mutation gates (86.24%/92.02%). Retain
  hosted134-auth-server and hosted134-http-auth artifacts for timeout/oracle
  investigation. Refresh the chain after pushing this implementation increment.
  An ignored18-case progressive-file probe passes10 and fails eight actual
  assertions on VM/JS/WASM: the encrypted native branch sends after final result,
  RPC error, disconnect or subscription cancellation. Fix after CI blockers;
  preserve the probe and pre-fix hashes. No full-goal completion, merge or release.

### Work133 Profile Negotiation And Finite Meta Disposal Oracles

- Integrate40 portable session-E2EE negotiation tests covering both supported
  ciphers, required-provider rejection, exact establishment/version types,
  directional key precedence, partial/missing keys and preserved rejection
  metadata. Tests cover negotiation, not cryptographic handshake completion.
  Select the entire suite in VM/browser verification and JS coverage; the separate
  VM coverage script still needs an explicit selection.
- Replace five unbounded meta completion waits with finite exactly-once listener
  assertions, retaining teardown and event ownership checks. Add a deterministic
  concurrent-close test with held unsubscribe acknowledgements and error-visible
  cleanup. All93 meta cases and40 profile cases pass on VM; canonical final
  browser runs retain both complete suites. All60 script-selection controls pass.
- Original Fast133-before and frozen-input Verify133 exit0. Final manifests and
  native artifact hash match, with no remaining native consumers at completion.
  Keep the shared native window reserved for Work134's reproduced reply bug.
  Canonical JS coverage and WASM verification each pass2281 client cases plus one
  native-only skip. JS core7383/7691 and client2518/2701 retain161 unmeasured
  library files; explicit98% audit fails. No new whole-VM or WASM score is claimed.
- Full157-mutant inventories on VM/JS agree:101 viable,56 compile failures,
  84 assertion-backed kills (58 assertion-only,26 mixed), six error-only outcomes
  and11 survivors. Raw/adjusted assertion scores83.1683%; conventional89.1089%
  is not credited as assertion coverage. Both95% gates fail. Initial/restored
  baselines pass and the independent saved-log audit agrees. No equivalence
  waivers or crash/timeout credit. Preserve meta-cache133-mutations and
  coverage133-verification with the exact source/test/support hashes.
- Qwen test/review advice prompted additional profile parameter cases and a
  queued-callback drain. Reject suggestions that would deadlock held unsubscribe
  replies or incorrectly ban a supported cipher. Isolated18-case normal/native
  reply comparisons fail eight native PPT payload assertions on VM/JS/WASM;
  normal cases pass. The expanded62-case VM probe fails21 native cases, including
  missing E2EE packing/provider rejection and progressive reply payloads. These
  controlled metadata-boundary probes are not actual FFI measurements. Fix and
  integrate them next, retaining the pre-fix logs and fresh final verification.
- Parent5ece94bb package/image dry runs pass; CI is queued without an observed
  failure and the profile run remains pending. Refresh hosted evidence after push.
  The complete98%/95% goal remains active; no merge/publication/version change.

### Work132 Complete VM Mutation Oracles And Meta Lifecycle Assertions

- Remove pure-VM fail-fast, retaining complete browser/native-file execution,
  isolated-file sequencing, deadlines and classification. Reproduce the old
  omission using a real Dart package: an early runtime error hides a later
  assertion, timeout or process exit. The canonical four-target control verifies
  actual mixed evidence only when an assertion fails; error-only, timeout and
  process failure remain uncredited. All63 runner controls (one Linux-only skip)
  and59 script controls pass, including positive/negative complete-suite selectors.
- Integrate the92-case meta suite with finite first/duplicate event assertions,
  immutable no-op identity, failed disconnect and exact concurrent-disappearance
  success oracles. Both VM scripts explicitly select the entire suite. Focused
  VM/JS/WASM pass; final VM meta coverage259/259 is a module slice only.
- Preserve and finish the original Fast132, Verify132, browser coverage and full
  mutation processes. Fast and Verify exit0; frozen inputs and native hash still
  match. Release the native window after lsof confirms no remaining users.
  Browser coverage and WASM verification pass2240 client cases plus one genuine
  native-only skip. Canonical JS core7383/7691 and client2506/2698 retain161
  unmeasured sources; the98% audit remains red. No measured WASM score is claimed.
- Full157-candidate inventories per runtime have56 compile failures and101 viable
  mutants:82 assertion kills (58 assertion-only,24 mixed), six error-only
  detections,12 survivors and one timeout. Both raw/adjusted assertion scores are
  81.19%, with no waivers. Initial/restored baselines and independent log audit
  pass; recorded source/test hashes match. The unchanged95% gates fail honestly.
- Qwen review completed. Its alleged isolated-file argument retention and absent
  fixture teardown contradict source/controls; no-op identity is observable
  because public immutable models retain identity equality. Do not weaken these
  assertions. The unbounded disconnect wait is a real remaining mutation-oracle
  gap, not a passing-score claim; improve it in the next snapshot. Optional GLM
  judge endpoint is unavailable independently of the working Qwen backend.
- Preserve coverage132-verification, coverage132-meta, browser132-current and
  meta-cache132-mutations. The ignored32-case session-E2EE profile probe passes
  all three runtimes but remains outside canonical evidence. Integrate it next.
  Parent f6049b8e package/image/profile checks pass; CI remains queued. Refresh
  the hosted chain after push; no merge, publication or version change.

### Work131 Meta Hydration Race And Portable Binding Regressions

- Preserve the original Fast131, Verify131 and two mutation processes until
  their observed terminal exits. Fast and Verify exit0; both mutation gates exit1
  with complete inventories, not an infrastructure failure. Frozen inputs and
  ffi-test library hashes still match. Release the shared native window only
  after verify finishes and no library users remain.
- Reproduce successful cache initialization after the last hydration reply
  closes its transport before the asynchronous disconnect callback runs. The
  production fix checks Session.isConnected before accepting the snapshot.
  Add78 canonical malformed-input, cleanup, concurrency, immutable-snapshot and
  error-identity regressions. All82 meta cases plus1814 binding and9 local cases
  pass on VM, JS and WASM. Canonical browser verification and measurement retain
  those full suites, with2230 client cases and one native-only skip. No native
  binding regressions or assertions are removed.
- Verify131 and focused runtime suites pass;58 script controls,62 mutation
  controls (one Linux-specific skip) and27 audit controls pass. Analysis exits0
  with seven informational missing-brace lints, no errors/warnings. Local review's
  alleged topic-count and cleanup issues are contradicted by the ten-topic source
  inventory and independently verified cross-runtime cleanup/error assertions.
- Canonical JS measures core7383/7691 and client2506/2698, with161 unmeasured
  library sources. Meta JS301/302, binding JS643/652 and focused Meta VM258/259
  remain explicitly scoped measurements. The explicit98% audit fails; WASM
  runtime success remains distinct from measured executable-line coverage.
- Both full meta-cache mutation inventories generate157 candidates,56 compile
  failures and101 viable mutants. VM has65 assertion-backed kills,16 error-only
  detections,19 survivors and one timeout; JS has66 assertion-backed kills,
  nine error-only detections,19 survivors and seven timeouts. Raw/adjusted
  assertion scores64.36%/65.35% agree with the independent saved-log audit.
  Initial/restored baselines exit0; hashes match. No equivalence waivers or
  timeout/error-only credit. Keep the unchanged95% gate failing honestly.
- Prepared ignored92-case follow-up passes all three runtimes; eight isolated
  controls using its earlier89-case snapshot turn survivors into assertion-only
  kills. Changes separately observe first/duplicate deletes, burst snapshot
  identity, no-op member updates, failed disconnect and missing Meta objects.
  Replace unbounded changes.first in the probe with finite event collection.
  These diagnostic outcomes do not change canonical131 scores. Further controls
  using unchanged82-case tests show VM fail-fast hides later genuine assertions
  for two error-first mutants; a third remains error-only. Correct the runner
  with regression controls, integrate the follow-up and explicit VM meta suite
  selection, then collect fresh complete inventories.
- Evidence: coverage131-verification, browser131-current, coverage131-meta and
  meta-cache131-mutations. Parent ad456802 package/image/profile checks pass;
  main CI remains queued without known failures. Refresh checks after push,
  preserving pending/default-workflow/branch-protection findings. No merge,
  release, version change or whole-milestone completion claim.

### Work130 Canonical Client Browser Scope And SCRAM Request Gates

- Resume the original Fast130 process rather than starting another baseline;
  observe exit0 before edits. Reproduce the main-client suite's FFI import loading
  failure on JS/WASM, then conditionally export the unchanged native probe or a
  browser skip reason. Preserve the native-provider case: the focused VM run
  passes90 tests without skips; canonical browser selection passes329 plus one
  genuinely native-only skip on each compiler. Add main-client and meta-cache
  suites to verification; coverage now includes those and WebSocket/form suites.
- Assert positive SCRAM lower-bound acceptance by observing only the recognized
  ArgumentError rejection. Rethrow unrelated errors; no generic exception-to-
  assertion conversion. Complete12-candidate VM and12-candidate JS request
  inventories score100% raw/adjusted assertion kills. Both initial/restored
  baselines exit0, hashes match and independent saved-log audit agrees. JS has six
  assertion-only and six mixed outcomes, all with actual assertion failures;
  there are no test-error-only kills, timeouts, compile failures or waivers.
  Register both CI gates at the unchanged95% threshold and require their jobs in
  the strict deployment audit. The wider Work129 Worker50% result remains open.
- Analysis,58 script controls,27 audit controls and frozen Verify130 pass; verify
  includes3794 router,3319 core WASM and329 client browser tests. All recorded
  inputs and native artifact hash match; release the native window. Local review's
  suggestion to loosen the narrow error-message filter is rejected: a valid
  constructor must not reject, and unrelated errors must remain uncredited.
  Its untracked-file concern is addressed by committing both helper variants;
  focused CI review finds no concrete issue. No threshold or timeout change.
- Canonical JS measurement passes3327 core and329 client tests: core7364/7676
  (95.94%), client1785/2240 (79.69%),162 library files unmeasured. The broader
  client scope exposes actual gaps; it does not regress to the forms-only98.59%
  claim. Preserve raw reports and failed explicit98% target audit. These are
  measured compiler-selected sources, not complete package/WASM coverage.
- Ignored browser probes preserve every one of1814 message-binding cases and
  pass on JS/WASM with only entrypoint/relative-import changes; all9 unchanged
  local-transport auth cases pass too. Integrate their entire suites next.
  Both default and stateless MCP HTTP constructors reproduce Unsupported
  operation: Platform._version through dart:io HttpClient on both compilers.
  Portable form tests do not establish browser HTTP/session/OAuth readiness.
  No production HTTP change is made here. Retain probes and hashes separately.
- Evidence directories: coverage130-verification, browser130-current,
  scram-request130-mutations and coverage130-client-browser under the milestone
  output root. Parent a0897235 package/image/profile checks pass; main CI remains
  live with no observed failure. GitHub CI triggers both push and PR and has no
  concurrency cancellation; do not assume older runs were canceled. Inspect
  current-head hosted checks after push without duplicating manual dispatches.
  Keep the full component/runtime98%/95% goal active; no merge/release/version bump.

### Work129 Deterministic SCRAM Lifecycle And Remaining Browser Scope

- Observe the original fast129 baseline and JS/WASM prototype sessions exit0
  before integrating tracked changes; do not restart completed campaigns. Add14
  browser lifecycle cases plus10 portable request/exception cases. A controlled
  Worker records transfer arguments without pretending to perform real buffer
  detachment; real-worker cryptography, cancellation and responsiveness tests
  remain. Restore globals per test and use explicitly delivered events/manual
  timers rather than counting test-runner deadlines as assertions.
- All55 focused cases pass on each browser compiler,10 request cases pass on VM,
  and the new files analyze cleanly. Canonical JS coverage completes3327 core and
  248 client-form cases: core7319/7631 (95.91%), client forms279/283 (98.59%),171
  unmeasured library sources. Worker boundary94/94 is a measured slice, not a
  component/runtime completion claim. The explicit98% target audit fails.
- Add reproducible core-scram-worker-web, core-scram-request-vm and
  core-scram-request-web targets, retaining the full source/operator inventories
  and all existing worker tests. Run bin/test-mutations with all three targets,
  output scram-lifecycle129-mutations and process timeout60. Report complete=true;
  every initial/restored baseline exits0, and source/test hashes match.
- Worker27 candidates produce12 assertion-backed kills, four uncredited test
  errors, six timeouts, two survivors and three compile errors:50% raw/adjusted
  assertion score, not66.67% conventional detections. Late-result guard removal
  now causes six test errors; retain that diagnostic without assertion credit.
  Repeat-dispose and disposable snapshot growability survive; no equivalence
  waivers. Request VM/JS each produce11 assertion kills and one uncredited test
  error among12 candidates:91.67%, not100%. The latter always rejects valid
  keyLength values; add an explicit positive acceptance assertion, not blanket
  conversion of arbitrary crashes/deadlines to test failures. All three95% gates fail
  honestly. A separate audit of saved logs agrees with the campaign classifications.
- Frozen Verify129 exits0, including Rust/native, public installed-package/live
  router checks,3319 core WASM cases and250 client browser cases. All recorded
  inputs and native artifact SHA256 match afterward; release the native window.
- While inputs were frozen, an ignored main-client browser probe replaces only
  its FFI-only support import and adds browser metadata. All76 cases remain:
  75 pass on JS/WASM; one genuine native provider case is inapplicable. Four
  meta-cache cases pass on both compilers. Diagnostic JS1198/1588 (75.44%) retains
  223 repository library sources as unmeasured and fails policy. Preserve the
  prototype, hashes and logs in coverage129-client-browser; it is not canonical
  package coverage. Next integrate conditional test support and broader client
  browser selection without removing native cases.
- Parent b6b62f4f package, image35421916560 and WAMP35421917385 dry runs pass.
  Main CI35421877676 is still live with no observed failed job. Strict audit129
  remains non-green for pending CI, unprotected feature branch and the mutation
  diagnostics workflow not yet discoverable from the default branch. No merge or
  branch-policy change to silence these findings. Refresh hosted evidence after
  push. Evidence lives under coverage129-verification, browser129-current and
  scram-lifecycle129-mutations. Narrow local review found no concrete global
  restoration bug; suggested timer cleanup is already owned by deriver teardown,
  and the manual timer does not schedule platform work. GLM is independently
  unreachable; routine local companions ran successfully. The full goal is open.

### Work128 Full Core Browser Integration And Worker Length Validation

- Revalidate the native window rather than inferring liveness from stale logs.
  Session3580 is absent and no matching mutation/native artifact user remains.
  Its2399-candidate RouterBinding report stops at559 outcomes, complete=false:
  205 detected failures (188 assertion-backed,16 test errors,one unknown),122
  compile failures,186 survivors,46 timeouts. No accepted
  final score. Preserve it; the current runner cannot resume existing output.
- Fast128-before completes exit0 before tracked implementation edits. Integrate
  the prepared Work127 conformance/SCRAM tests without deleting original cases.
  All29 vendored fixture files preserve exact bytes, including numeric spellings,
  Unicode and line endings. Python stdlib generation plus SHA-pinned freshness
  checks requires no new Node runtime in canonical verification. Ten controls
  reject changed/added/deleted sources, modified/missing outputs, symlinks, unsafe
  names, empty inventories and input drift; empty files remain represented.
- Retain101 conformance cases and add96 literal/malformed controls for an
  independent test-only MessagePack reference. BigInt bounds precede int conversion;
  unsupported values fail closed. VM/WASM cross-check the original msgpack_dart
  oracle too. Preserve all17 legacy SCRAM cases and fixed native proof vectors;
  browser Argon2 uses real workers, with seven additional worker contract tests.
- Add18 worker boundary/lifecycle regressions. Five wrong-length cases reproduce
  an actual missing check on both JS and WASM from the canonical package path.
  Validate exact requested keyLength before copying/completing and clear malformed
  results before failing with a fixed diagnostic. Cover valid16/32/64-byte results,
  non-byte responses, concurrent request isolation, failure recovery and disposal.
  All245 focused browser tests pass per compiler;214 conformance/SCRAM VM cases pass.
  These are test-worker fault injections, not evidence of attacker control of the
  production Worker. Existing64MiB event-loop responsiveness regressions also pass.
- Canonical browser verification/coverage now runs the entire core test directory
  from its package root; source-contract tests reject reversion to a selected
  subtree or test-name filters. All56 script tests pass. Increase the bounded
  whole-suite allowance from420s to900s for the larger inventory; per-test timeout
  and coverage targets remain unchanged. Upload raw browser coverage in CI.
- Canonical browser coverage128 completes exit0 with3303 core tests and248 client
  form cases. Current hashes match: core7307/7631 (95.75%), client forms279/283
  (98.59%),171 unmeasured library sources. The explicit98% audit fails. This is
  JS measurement, not WASM or Worker-module coverage.
- The complete27-candidate worker campaign finishes with both baselines exit0,
  matching source/test hashes and an agreeing independent kill-log audit. Nine
  assertion-backed kills, six uncredited test errors, six timeouts, three survivors
  and three compile failures yield37.5% raw/adjusted assertions, not the62.5%
  conventional detection score. Removing/inverting the new length guard produces
  assertion failures; always rejecting valid lengths currently yields test errors
  and is uncredited. No waivers or policy changes. Investigate survivors at the
  repeated-dispose guard, disposable list growability and completed-result guard;
  the latter requires explicit queued-response/late-result coverage. Next use
  deterministic browser boundary fault injection rather than turning timeouts
  into assertions or attributing old scores to stronger tests.
- Frozen-input Verify128 completes with observed exit0 on original session88782,
  including Rust/native, installed-package/live-router checks,3295 core WASM tests
  and250 client browser cases. All recorded source/test/tool hashes match. No
  native artifact users remain, its SHA is unchanged, and the coordinated native
  window is released. No new native campaign. The full98%/95% milestone is not
  complete. Main PR CI35382375488
  at4bfd4c2d is now green across32 jobs; refresh hosted evidence after this increment.
- Evidence: /tmp/connectanum-coverage128-* logs and input hashes, plus ignored
  coverage128-worker-boundary, scram-worker128-mutations and browser128-current
  under out/regression-coverage-2026-09-15. Broader local review hit its output
  limit; a narrow worker-check review found no concrete issue. Fixture review
  incorrectly claimed empty-string decoding and impossible traversal filenames
  were bugs; source inspection and integrity controls refute those claims. The
  independent GLM endpoint is unavailable. Do not treat advisory output as proof.

### Work125/126 WASM Integrity And Collector Overhead

- Independently decode source-map VLQ and verify exact inventories, source/module/
  map hashes, breakpoint classifications and raw pause locations. Inventory350
  production Dart files across packages and example application; unselected or
  unmapped files stay visible. The validator's43 unit tests pass.
- Original browser session83543 completes exit0 with212 unchanged completion tests.
  Observe144 of149 mapped source lines, four not observed and one partially
  instrumented/not observed. Keep349 other files unmeasured. The smaller two-test
  compilation mapped130 lines: compiled maps alone are not an executable-source
  denominator, even with O0. No package-wide WASM percentage is claimed.
- A new ignored one-shot launcher retires each exact breakpoint only after a
  validated hit and acknowledged removal, preserves its initial inventory and
  retirement events, and atomically replaces reports. Session40513 passes the
  same212 tests, with720 debugger pauses instead of42202. Independent validation
  confirms identical line states and all25 unresolved offsets. These are boolean
  observations, not hit-frequency or production performance measurements.
- Inspect raw module hash differences rather than hiding them. They occur only
  in generated package:test bootstrap names in the debug name section and one
  source-map URI per module. A section-aware comparator verifies byte-identical
  executable/other sections and exact source-map content except that URI. Its12
  tests reject code, offset, production-URI and unrelated-debug-name corruption.
  Together with23 retirement/I/O tests, all78 Node tests pass.
- Inventory-driven session88665 passes77 MessagePack codec WASM tests. Two sources
  have212 mapped lines: nine observed,185 not observed,18 partially instrumented
  and not observed. Preserve348 unmeasured sources. The existing JS-only fallback
  suite is not applicable to this run; WASM takes its supported64-bit ByteData
  delegate path. Do not import JS hits or automatically exclude fallback lines.
- [V8 IsBreakable](https://raw.githubusercontent.com/v8/v8/14.9.155/src/wasm/wasm-opcodes-inl.h)
  and [FindNextBreakablePosition](https://raw.githubusercontent.com/v8/v8/14.9.155/src/wasm/wasm-debug.cc)
  explain the captured control-opcode relocations. Keep those unresolved without
  credit. An observed different exact offset on the same Dart line is independent
  evidence, not a waiver. The [WASM custom-section definition](https://webassembly.github.io/spec/core/appendix/custom.html)
  supports retaining debug names separately from executable-section comparison.
- Workers/startup/deferred-target completeness, executable-line inventory and
  portable canonical/CI integration are still open. Prototype files, validators,
  raw maps/modules and reproducible commands are in wasm125-validator and
  wasm126-one-shot. They are not a shipped measurement gate.
- Preserve native campaign3580 and its frozen artifact/source/test snapshot.
  All captured hashes match settled Verify123. Full-core JS session36285 completes
  exit1 with3077 passing tests and five failures. Four legacy tests incorrectly
  expect synchronous Argon2 to succeed on web; conformance setup attempts to read
  vendored fixtures through dart:io. The7237/7602 (95.20%) line result remains
  diagnostic, not accepted green coverage. Preserve raw data in browser126-core-all.
- Prepare seven real-worker SCRAM contract regressions in the ignored
  coverage126-scram-browser-contract directory. JS session3463 and WASM22985 pass
  all seven: synchronous Argon2 rejects without producing a client key, async
  derivation preserves the unchanged ASCII/UTF-8/UTF-16 proof vectors, and properly
  bound worker-derived client/server keys reproduce the cached proof. The first
  outside-package browser invocation41438 times out during suite loading; running
  from repository root resolves the test-server path. It is a retained diagnostic,
  not a passing test. Scratch-path analysis reports two dependency-layout infos;
  package integration and canonical verification remain pending.
- Next integrate platform-correct SCRAM regression expectations without deleting
  native vector assertions and make the conformance fixture harness browser-readable
  rather than dropping its tests. Do not restore synchronous web Argon2 or infer
  final runtime coverage from this failed full-core baseline.
- Main PR CI35382375488 has11 successful jobs, including Fast Checks, WampApp
  Consumer and Core Browser Coverage, with no failed jobs observed at this check.
  Remaining jobs and final strict hosted success are still pending.
- Local companion advice was checked independently. Broad requests hit output
  limits; narrow advice to mark a removal retired before acknowledgement was
  rejected. The paused target cannot execute another hit before resume, and a CDP
  error invalidates the report. GLM was separately checked and unavailable.
  No production changes, new waivers or threshold/operator changes. Bookkeeping
  remains uncommitted until it can accompany an implementation increment.

### Work124 WASM Measurement Feasibility

- Preserve the original full RouterBinding mutation process and frozen inputs.
  Browser-only probes use `CONNECTANUM_SKIP_NATIVE_BUILD=1` with the native
  library environment unset; no native build/runtime or replacement campaign.
- Confirm an instrumentation gap with identical canonical MCP completion tests:
  Chrome JS emits134 coverage source entries, including production Dart sources;
  WASM emits `coverage: []` despite both tests passing. Installed versions are
  Dart3.13.1, test1.31.2, coverage1.15.1 and Chromium149.0.7805.0.
- Investigate the [Chrome debugger protocol](https://chromedevtools.github.io/devtools-protocol/v8/Debugger/)
  and [WebAssembly source-map conventions](https://github.com/WebAssembly/tool-conventions/blob/main/Debugging.md).
  Unlike the JS profiler path, debugger breakpoints can observe actual WASM byte
  offsets. Six separate controls distinguish taken and untaken branches in a
  tiny fixture and the real MCP completion validator. Browser bytecode matches
  the compiled module, all selected fixture breakpoints resolve exactly, and
  each hit's call-frame location matches its requested offset.
- An ignored prototype Chrome launcher inserts a barrier after WASM compilation
  but before instantiation, then instruments the unchanged package:test harness.
  Final v4 session8795 exits0 with both existing tests passing, no observer
  errors,393 exact breakpoint locations and94 observed Dart source lines. The
  complete402-offset selected inventory retains nine relocated locations as
  unresolved; those are removed and receive no hit credit. Do not treat nearby
  instruction placement as execution of the requested source location.
- Preserve compiled WASM, source maps, source hashes, debugger events and browser
  version. Independent report checks pass and reject ten corrupted/incomplete
  evidence controls. Earlier v1/v2/v3 probes retain their source-map URL,
  nonexact-breakpoint and output-pipe diagnostics; they are not final evidence.
  The first local review's proposed profiler cross-check is inapplicable because
  the profiler emits no WASM entries. The later broad review was token-limited
  and is not approval.
- Evidence is under `out/regression-coverage-2026-09-15/wasm124-debugger`, with
  controls in `wasm124-probe` and `js124-control`. Reproduce the checks with
  `node out/regression-coverage-2026-09-15/wasm124-debugger/check-results.mjs`.
  This does not yet establish a production collector, executable-line inventory,
  package-wide percentage, worker/deferred-module coverage or startup coverage.
  Source maps also contain declaration/end positions; they are not an independent
  executable-line denominator. No source exclusions, threshold changes or
  package-wide WASM coverage claims are introduced.
- Package dry runs, router-image35382402068 and WAMP-profile35382403818 pass for
  exact head4bfd4c2d. Strict audit124 exits1 while main CI is queued; branch
  protection/default-workflow findings remain. Keep original CI observers and
  the full2399-candidate native mutation process. Settled Verify123 and captured
  workspace hashes still cover the untouched implementation. Leave these notes
  uncommitted until they can accompany an implementation increment.

### Work123 HTTP Authentication Lifecycle

- Add26 focused contracts for multi-round state rotation, replay, identity and
  route/profile binding, async pending/grant capacity, failure/expiry/lockout,
  late factory creation and shutdown. A controllable authenticator suspends
  callbacks without relying on timing races. Preserve normal wire semantics.
- Reproduce late HELLO/AUTHENTICATE completion after dispose: success returns200
  and issues a token, challenge returns401 and recreates state, late exceptions
  leave the synthetic request unanswered. Eight regressions fail on the old code.
  Track active transactions, mark auth disposed before cleanup, abort active and
  pending work, and guard results in the caller after awaiting. Make abort
  idempotent. Two more regressions reproduce unhandled cleanup errors; contain
  those during disposal with a sanitized event, never plugin error details.
- All26 focused tests pass. Poll helper deadlines now raise TimeoutException,
  not TestFailure; positive/negative controls ensure timeouts cannot become
  assertion mutation credit. The initial grant-capacity fixture incorrectly
  expected429 rather than the existing503 contract and was corrected; this was
  not a production bug. The late-error pre-fix timeouts are not assertion kills.
- Fast123 and original Verify123 session25534 pass. Final cleanup/test changes
  happened during that run, so settled-input Verify123 session7615 also runs and
  completes with observed exit0, including native, installed-package/live-router
  and Chrome WASM tests. All workspace input hashes match afterward. Full VM123
  refresh completes once on original session52707 with observed exit0 and matching
  hashes. Measured library lines38711/42670 (90.72%); router17073/19364 (88.17%).
  Binding3090/3666 (84.29%) still leaves576 unhit lines. Client8570/9427 (90.91%)
  is six hits below VM115 because unchanged socket-fragmentation buffering was
  not exercised in this run; retain the lower current measurement. Packaging
  remains765/787 (97.20%). Both explicit98% target audits fail, with59 library
  and12 packaging sources still unmeasured. Floors passing is not completion.
  Runtime coverage session57025
  passes245 tests but predates final inputs and remains diagnostic only.
  Preserve red/green logs and settled-input hashes under coverage123-http-auth-
  lifecycle. New full router-binding inventory has2399 candidates with matching
  source/test hashes; it is not a campaign or score. The consumer task explicitly
  yields the native window through validation and the subsequent full campaign.
- Narrow Qwen test advice informed replay/capacity cases. Its first full review
  was truncated; speculative GC, map atomicity and double-abort claims were
  independently rejected. The cleanup-error concern was reproduced and fixed.
  The separate GLM endpoint is unavailable. Keep the full milestone active;
  no merge, publication, version or threshold changes.

### Work122 Native Binding Boundary Contracts

- Add 128 regressions for direct/non-direct loader state, absent fragments,
  caller-owned overrides, conflicting INTERRUPT mode sources, full HELLO/WELCOME
  identity, minimal unknown frames, optional ABORT payloads and normalized JSON
  nested-list behavior. Existing negative tests and all helper controls remain;
  no exception catches, production changes or equivalence waivers are added.
- All 3687 focused tests pass (1814 client,1873 router), analysis and diff checks
  pass, and measured binding-file lines remain584/584 and575/575. The focused
  LCOV correctly fails whole-workspace policy because other sources are absent;
  it is not a package-wide pass. Fast122 completes before edits; frozen-input
  Verify122 also completes with observed exit0, including Rust/native, installed
  consumer smoke and Chrome WASM. Final hashes match. Release native to the
  consumer task before further native work.
- Full client492/router666 campaigns complete on original sessions72358/77614
  with observed exit0. Client381/398 viable assertions (95.73%),9 uncredited errors,
  8 survivors,94 compile failures; router496/519 assertions (95.57%),10 uncredited
  errors,13 survivors,147 compile failures. Raw/adjusted scores match; no new
  equivalents. Both baselines, current input hashes, full source/operator inventory
  comparisons and independent kill-log audits pass. Prior Work121 reports remain
  separate. These focused file gates do not establish whole-component coverage.
- JS coverage session41373 completes exit0 in browser122-current: selected core
  6628/6973 (95.05%), client forms279/283 (98.59%),172 unmeasured library sources.
  All browser input hashes match. Do not infer WASM coverage from passing tests.
  Keep VM115 as the last full VM snapshot until it is actually refreshed.
- Qwen's initial paired review was truncated; both narrowed reviews complete
  without concrete findings. Discard unsupported GC/atomicity speculation after
  source inspection. Evidence and logs are under coverage122-binding-boundaries.
  The next largest concrete line-gap lead is HTTP multi-challenge state rotation,
  route/identity/profile preservation and capacity/failure cleanup in router
  binding. Those paths are live, not candidates for coverage exclusions.

### Work121 Native Binding Assertion Oracles

- Add198 metadata dispatch contracts across JSON/MessagePack/CBOR and direct/
  non-direct binding. A valid competing UnknownMessage frame makes mistaken
  fallback observable without relying on malformed-frame errors. Assert exact
  classes, codes, distinct IDs and control fields. Keep existing negative and
  invalid-full-frame/no-decode tests intact.
- Assert known-valid synchronous full-frame parsing and nullable field presence
  before casts/dereferences. Catch only FormatException/ArgumentError in these
  success fixtures. Thirty controls preserve single evaluation, returned object
  identity, nullable values and unchanged runtime, unsupported-serializer, type,
  timeout, filesystem/socket/process, assertion and resource errors.
- All3559 focused tests pass (1732 client,1827 router;3331 previously). Focused
  analysis and diff checks pass. Fresh VM file lines584/584 client and575/575
  router are100%, not whole-package coverage. The scoped whole-workspace policy
  check correctly fails for unrelated unmeasured files; no policy was relaxed.
- Fast121 and frozen-input Verify121 complete with observed exit0, including
  Rust/native, installed-package/live-router and Chrome WASM. All final input
  hashes match; explicitly release the native window for the consumer task.
  Do not claim a new whole-VM snapshot or WASM line measurement.
- Client492 completes with369 assertions,11 uncredited errors,18 survivors and
  94 compile failures:92.71% raw/adjusted assertions versus58.04% previously.
  Both baselines, all three input hashes and independent kill-log audit pass;
  the492-candidate source/operator inventory is unchanged. Its95.48% conventional
  score does not satisfy the95% assertion gate; session29088 exits1 as expected.
  Router666 also completes:484 assertions,17 uncredited errors,18 survivors,
  147 compile failures;93.26% raw/adjusted assertions versus64.74% previously.
  Both baselines and the independent log audit pass, and input hashes matched
  before Work122 edits. Session94472 exits1 as expected. Preserve both completed
  reports as Work121 evidence. The existing client fallback mutant now has an assertion
  instead of an error-only outcome. Do not credit remaining runtime errors.
  Investigate full-frame type/length checks, conflicting INTERRUPT mode fields
  and unnecessary non-direct custom loaders; these leads are not equivalences.
- Both Qwen reviews completed; independently reject their inconsistent-helper,
  nonexistent YIELD-mode assertion and ABORT-null-safety claims. GLM's separate
  endpoint is unavailable. Keep evidence, original failures and final-input
  hashes under coverage121-binding-oracles and bindings121-vm. No production,
  threshold, equivalence or version changes. At predecessor c7710381 package,
  router-image and WAMP-profile dry runs pass; main CI is queued. Refresh hosted
  status after pushing. The complete regression/mutation milestone stays open.

### Work120 Remote Credential Isolation And Wire Contracts

- Add valid/default parser, TLS opt-in, credential file identity, authentication
  cardinality, anonymous/non-remote warmup and explicit response discriminator
  tests. Preserve all negative tests and exact wire-value checks. Runtime,
  filesystem, socket, process and timeout failures do not become parser kills.
- Reproduce a real32-bit credential fingerprint collision with three failing
  tests before changing production code: inline delegate identity, file-backed
  credential rotation and live-session reconnect. Replace the short fingerprint
  with SHA-256 over exact UTF-16BE code units, clear the temporary encoding, and
  verify five independent Unicode vectors including unpaired surrogates. This
  hash is an in-memory identity, not a password KDF or persisted verifier.
- Add a controlled wire warmup test: a later malformed configuration must not
  report aggregate completion before an earlier pending connection settles.
  Preserve transport/process failures; do not treat them as assertion kills.
- All197 focused tests pass (146 before); analysis is clean. Final focused VM
  source lines571/574 (99.48%); three unhit lines remain. Fast120 and original
  Verify120 pass. Two narrow test guards changed during that verifier, so
  frozen-input Verify120b also completes with observed exit zero, including
  Rust/native, installed-package/live-router and Chrome WASM. Final hashes match;
  release the native window. Assert the
  CA map type before containsPair and successful RangeError-free synchronous
  inline cache-key construction. Other runtime/infrastructure failures remain
  uncredited. No change to mutation operators, thresholds or equivalent waivers.
- Earlier286-candidate remote-wamp120 completes below gate at172 assertion
  kills,11 uncredited errors,four survivors,99 compile failures:91.98% raw and
  adjusted assertion score. Keep it as old-source diagnostic evidence, not
  final-snapshot evidence. The292-candidate120b campaign also predates final
  guards:172 assertions,16 errors,three survivors,101 compile failures (90.05%).
  It confirms the new controlled warmup assertion kills the eagerError survivor.
  Final120c completes with observed exit zero:292 candidates,182 assertion kills,
  six uncredited errors,three survivors,101 compile failures;95.29% raw/adjusted
  assertions,98.43% conventional detection. Both baselines and all14 source/test/
  support hashes pass; independent audit agrees and the292-candidate inventory
  matches120b exactly. No new waivers. Final snapshot is final120c-input.sha256.
- GLM's independent endpoint is unavailable. Two focused Qwen fingerprint
  reviews hit output limits and are not approval. Later completed fingerprint
  and cache-key assertion reviews have no concrete findings; independently
  inspect call sites, code-unit bounds, collision reproductions and vectors.
  Three120b survivors remain reviewed and unwaived: absent-key early return,
  connecting-future identity guard and private authmethod-list growability.
  Evidence: coverage120-remote-oracles, remote-wamp120c-vm and the named mutation
  reports under the shared root. No merge, publication or version changes.
- At predecessor f9fd4f41 package dry runs and WAMP35362469253 pass; CI is queued.
  Refresh all required hosted evidence, including router-image dry run, after
  pushing this production fix. Next client/router binding assertion gaps remain
  58.04%/64.74%. The unchanged client binding baseline passes1621 tests; inspected
  failure categories and rejected companion suggestions are in
  coverage121-binding-oracles. No new binding score or whole-component gain.

### Work119 Benchmark Configuration And Browser Evidence

- Preserve malformed-input tests and exact values while asserting that known
  valid parser calls succeed. Only FormatException/RangeError are converted to
  parser-contract assertions; controls preserve other error identities, single
  evaluation and nullable returned values. No production or policy changes.
- Add fixed-length YAML scenario/nested-list tests with element replacement,
  mutable programmatic construction and top-level options/JSON ownership checks.
  All102 focused tests pass (86 before); analysis is clean. Focused parser VM
  coverage88/89 (98.88%), not whole-package coverage.
- Full72 benchmark-config inventory passes:44 assertion kills,28 compile
  failures, no survivors/errors/timeouts/waivers;100% raw/adjusted assertions
  versus70.45% previously. Both former growability survivors now have actual
  assertions. Baseline/restored tests and source/test hashes pass; candidate IDs,
  operators and replacements match the original inventory. Independent log audit
  confirms the score. Fast119 and settled-input Verify119 complete with observed
  exit zero, including native, installed-package/live-router and Chrome WASM
  tests. Final input hashes match and the native window is explicitly released.
- Final lazy118c JS finishes on its original handle:223 assertion-backed kills
  (143 assertion-only,80 mixed),16 survivors,50 compile failures;93.31% raw,
  96.54% adjusted using eight existing equivalents. Both baselines and current
  input hashes pass; independent kill audit agrees. Survivor IDs match VM, so
  retain the individual Work118 review. No error-only/unknown/timeouts.
- Audit older complete, still input-matching remote-delegate97b/client-binding92/
  router-binding93 logs rather than inheriting conventional scores: assertion
  scores59.89%/58.04%/64.74%, with68/149/165 uncredited errors. These are the next
  gates, not fresh current-runner results or qualifying evidence. Original and
  audited reports remain separate. Do not mask socket/process/FFI failures.
- Qwen's proposals to unify constructor mutability or deep-freeze options were
  rejected after source inspection; both would change existing behavior outside
  this task. No deep-immutability claim is made. Evidence/review notes live under
  `coverage119-bench-oracles`, `bench-config119-mutations`, `bench-config119-vm`,
  and `coverage118-oracles/lazy118c-web-kill-audit.json` in the shared evidence root.
  No merge, publication, version change or whole-milestone completion.

### Work118 Payload And Remote Auth Contracts

- Add a payload contract suite without removing any legacy tests. Check nullable
  fields, decode counts, byte/alias ownership, map-form and serialized PPT,
  plaintext discrimination, and encrypted forwarding. Both wrappers retain all
  four suites and support hashes; tooling guards their imports and invocations.
  VM file sorting made JSON list order ineffective, so use an explicit entry
  point to run contract assertions before fail-fast legacy dereferences.
- Final lazy118c VM has289 candidates,221 assertion kills,two error-only,
  16 survivors,50 compile failures:92.47% raw/95.67% adjusted with eight unchanged
  pinned equivalents. Baseline/restored tests pass; source/test/support hashes
  match. The two forced-getter null errors remain uncredited. Earlier VM
  campaigns remain diagnostics, not final evidence.
- Final payload selection passes155 tests on VM and JS (113 before). Focused
  payload file VM lines are412/413 (99.76%). The earlier JS mutation snapshot
  completed below gate and predates the final boundary cases. The final
  `lazy118c-web-mutations` campaign is running without duplicating the earlier
  process. Passing JS tests are not a mutation score or WASM line measurement.
- Remote-auth tests preserve exact values while checking status/cardinality
  before dereference. New cases cover absent failure payloads, sub-threshold
  rate limits, immutable delegate lists and pending proofs after delegate
  unavailability. Helper controls preserve timeout, unknown, stack/OOM and
  preexisting assertion identity. All128 tests pass versus93 before; focused
  file coverage366/368 (99.46%).
- Final remote118c inventory:191 generated,125 assertion kills,three survivors,
  63 compile failures,97.66% raw/adjusted; no error-only kills,timeouts or waivers.
  Both baselines and input hashes pass. The pending-delegate availability bypass
  is now killed by the no-proof-forwarding assertion. Remaining list-growth and
  exact-clock-boundary survivors are reviewed and unwaived in the evidence notes.
- Fast118 passes. Initial Verify118 fails the old cross-runtime inventory
  expectation, now corrected without loosening it. Verify118b and settled-input
  Verify118c complete with observed exit zero, including Rust/native, installed
  package/live-router and Chrome WASM tests. Final input hashes match. The61-test
  mutation tooling suite (one Linux-only skip) and54-test verification tooling
  suite pass. The native window is explicitly released to both consumer tasks.
  Evidence: `coverage118-oracles`, `contracts118-vm`,
  `remote118c-vm`, `lazy118c-vm-mutations`, `remote118c-mutations` under the shared
  evidence root. No production edits, new equivalents, merge or publication.
- Next inspected gate: benchmark-config has72 candidates,31 assertion kills,
  11 error-only,2 survivors,28 compile failures in hosted114 (70.45% assertion,
  95.45% conventional). Current86 baseline tests pass. Fixed-length scenario and
  nested YAML list contracts need assertions; do not waive observable behavior.
  No benchmark input changes were made during final verification.

### Work117 Config And Native Auth Assertions

- Known-valid config parses now have explicit success assertions; negative calls
  remain raw. Preserve exact settings and add caller-mutation/collection checks.
  Error allowlist controls keep timeout, filesystem, process, socket and unknown
  failures as errors. All424 focused tests pass versus413 before. Focused loader
  VM coverage522/525 (99.43%); no whole-router improvement claim.
- Config117 full396 inventory passes with346 assertion kills,three error-only,
  ten survivors,37 compile failures:96.38% raw/adjusted versus49.86% before.
  Conventional detection97.21%, no waivers, both baselines and input checks pass.
- Native auth asserts nested credential creation and certificate discovery;
  unrelated runtime/infrastructure failures propagate. Exact TLS authorization,
  output files and listener cleanup checks remain. All42 tests pass versus33.
  Full35 inventory:19 assertions,16 compile failures,100% raw/adjusted, no
  survivors/errors/timeouts/waivers, baseline/restored zero, native artifact
  unchanged and input hashes matching.
- Keep support-file contract exact: config helper is hash-pinned by the target
  and its tooling regression. The60-test runner suite passes with one Linux-only skip.
  Fast117 passes. Initial Verify117 failed the stale support-file expectation;
  preserve its log. Settled-input Verify117b passes with observed exit zero,
  including Rust/native, installed-package/live-router and Chrome WASM tests;
  final hashes match. A consumer preview held the shared native lock; our parent
  was suspended before native tests and resumed after owner-confirmed release,
  without restarting campaigns. The native window is explicitly released.
- MCP114 finishes1098 inventory:812 assertion kills,24 survivors,262 compile
  failures,97.13% raw/adjusted, no error-only/timeouts/equivalents. Both baselines
  and current source/test/support hashes pass. Individual survivor review is in
  coverage117-oracles; capability handler combinations and pending-release
  retry/interleavings remain targeted follow-ups despite the passing gate.
- E2EE116 finishes both runtimes with269 candidates each:VM207/214 assertions
  (96.73%),three errors;JS210/214 (98.13%),including56 mixed outcomes with real
  assertions. Four survivors and55 compile failures per runtime; no waivers or
  timeouts, both baselines and final input checks pass. Retain Work116 review.
- Qwen reviews were advisory and independently checked. GLM judge connection
  was unavailable; no heavyweight approval is claimed. Separate kill-log audits
  confirm completed MCP/config/native-auth assertion scores. Continue remaining
  gates and full-scope line gaps; this does not finish the overall milestone.

### Work116 Installer And E2EE Success Assertions

- Full VM115 completes with exit zero and matching input hashes before these
  edits:38,647/42,637 measured library lines(90.64%),client8,576/9,427(90.97%).
  Other package percentages stay unchanged. Packaging765/787(97.20%);59 library
  and12 packaging sources remain unmeasured. Retain this pre-Work116 snapshot.
- Reuse the known-valid install assertion across download/extraction/retry
  success paths. Keep negative calls and exact output, requests, cleanup and
  idempotency checks. Preserve TimeoutException, ProcessException and
  SocketException identity; eight new helper controls cover sync/async
  infrastructure failures. Focused tests:102 before,110 after, all passing.
- `installers116-mutations` completes with exit zero and unchanged inventories:
  client105 generated,96 assertions,two error-only,three survivors,four compile
  failures;95.05% assertion versus97.03% conventional detection. Router103
  generated,95 assertions,four survivors,four compile failures;95.96%.
  Raw/adjusted assertion scores agree; no waivers/timeouts, both baselines pass.
  Windows sibling tar path checks explain the two client errors, not assertion
  credit. Seven filesystem/shell survivors retain Work115's unwaived review.
- E2EE tests assert known-valid construction, packing, decryption and context
  copying once before existing exact expectations. Three controls cover identity,
  nullable values, single evaluation, timeout propagation and error diagnostics.
  All73 tests pass versus70 before; analysis is clean. Both VM and JS mutation
  targets hash the support file explicitly; inventories/policy are unchanged.
  VM269 candidates completes with207 assertions,three error-only,four survivors,
  55 compile failures:96.73% raw/adjusted assertion evidence, no waivers and both
  baselines passing. Full `e2ee116-mutations` still runs its JS scope.
- Core115 finishes all six VM/JS targets with exit zero: registration24/24,
  metadata213/213,PEM87/94 raw and87/87 adjusted with seven existing equivalents
  per runtime. No error-only/timeouts; baseline and final component hashes match.
  Browser116 passes:core6628/6973,forms279/283,172 unmeasured files, WASM lines
  unmeasured. Fast116 and final Verify116 pass with observed exit zero, including
  native, installed-package/live-router and Chrome WASM tests. Input hashes match
  and the coordinated native window is released. Preserve the separate MCP114
  campaign and do not duplicate it.
- Qwen planning/review was advisory. Verified actual mutation diagnostics retain
  original errors and all post-success cleanup/count checks remain. Individual
  E2EE survivor review, logs and hash checks are in `coverage116-oracles`; none
  was waived. Remaining coverage/CI gates still prevent milestone completion.

### Work115 Core Success Assertions

- Hosted artifacts identify unchecked valid-input failures in PEM/PKCS8,
  registration handler setup and lazy metadata parsing. Assert successful
  construction/materialization before exact seed, lifecycle or feature checks.
  Assert the advertised role/features before dereference. Keep negative-input
  expectations and exact delivery/ownership assertions unchanged.
- Replace the OpenSSH line-wrapping test's self-derived expected value with the
  fixed seed shared by independent fixture encodings. Construct valid PKCS8
  under a success assertion before corrupting its envelope for rejection tests.
  No production source, mutation inventory, threshold or equivalence changes.
- All 414 focused VM tests pass before and after edits. Completed VM inventories
  have registered24/24 and metadata213/213 viable assertion kills. PEM/PKCS8 has
  87/94 raw (92.55%), 87/87 adjusted (100%) using seven unchanged pinned
  equivalents; no error-only detections/timeouts, both baselines passing.
  JavaScript inventories continue in `core115-gate-mutations`; the overall
  campaign gate is pending. No completed subset substitutes for the full goal.
- Focused VM coverage: PEM85/85, registered69/69, Details346/346,
  CustomFields46/46, PKCS8 61/63. Its whole-workspace policy intentionally fails.
  Browser115 passes at selected core6628/6973 (95.05%), form-only client279/283
  (98.59%), 172 unmeasured sources. Keep compiler denominators separate. WASM
  line instrumentation remains open. Input hashes match. Evidence is in
  `coverage115-core-oracles`, `core115-vm` and `browser115-current`.
- Client/router installer CLI fixtures now assert valid installation success
  before exact path, content and stream checks. Ten controls prove identity and
  sync/async error rejection and preserve timeout identity. Negative installer
  calls remain separate. All46 CLI tests pass. `installers115-mutations` exits
  one: client89/101 (88.12%) and router88/99 (88.89%) assertion scores, identical
  raw/adjusted, no waivers/timeouts, both baselines passing. Nine client and
  seven router error-only detections remain in valid extraction/download tests;
  do not count them as assertions. Three client/four router survivors have
  pinned investigations in review-notes.md, with no new equivalence waivers.
- The original complete MCP109 client campaign exits one: 514 pure assertion
  and two mixed detections with assertions, 452 error-only detections, 308
  survivors, 70 timeouts, 251 compile errors. Both baselines pass. Conventional
  raw/adjusted detection is 71.92%; assertion lower bound is 38.34%. This is the
  original pre-111 test snapshot, not a score for the later client regressions.
- Fast114b passes. Preserve Verify114's native-lock failure: a separate
  consumer benchmark started during remote-auth integration and held the
  global lock. Its owner confirmed completion and a free verification window;
  do not terminate unrelated work or weaken locking. Fast115 and settled-input
  Verify115 pass with observed exit zero, including Rust, installed-package
  smokes, live native router tests and Chrome WASM. Separate browser115 supplies
  JS coverage. Final input hashes match. New-head hosted evidence is required;
  existing CI is still red, including newly downloaded E2EE, lazy-VM and router
  config loader gaps in `hosted115-gate-failures`.

### Work113/114 MCP And Hosted Gate Assertions

- Add 88 MCP regressions for ten standard meta topics (publish denied before
  dispatch, subscription and release allowed), fifteen standard meta procedures
  with all raw argument forms and open keyword schemas, invalid match options,
  URI/tool-name aliases, tag deduplication and readable-template selection.
  Seven success-oracle controls preserve return identity, reject unexpected
  errors and propagate sync/async TimeoutException unchanged. The MCP suite
  passes all 851 tests. No production source or protocol changes.
- Retain exact wire/value/rejection assertions while checking valid constructor
  acceptance, response shapes and collection sizes before casts/dereferences.
  Explicit asynchronous success assertions cover cleanup and retry. An
  independent literal response replaces a self-derived expected tool result.
- Preserve the initial 202-candidate diagnostic: 127 assertion kills, 48
  error-only detections and 27 survivors, both baselines passing. It selects
  old MCP100 survivors/error-only outcomes and is not the full target score.
  Later changes do not alter that historical snapshot. Start the complete
  unchanged 1,098-candidate `mcp114-library-mutations` only after that diagnostic
  exits; final score is pending. Keep the original MCP109 client campaign.
- Downloaded hosted artifacts at `06726965` show metrics83.33%, adjusted
  authorization92.96% and JS subscription93.33% assertion detection. The fixed
  metrics114c inventory has 63 assertion kills/three survivors (95.45%).
  Authorization114b has 69 assertion kills/28 compile errors/five survivors:
  93.24% raw, 97.18% adjusted using three existing source-pinned equivalents.
  All five authorization and three metrics survivors have individual pinned
  control-flow reviews; no new waivers. Subscribed114c has 15 viable detections
  and seven compile errors on VM and JS separately, both 100%. JS includes
  eleven pure assertions and four mixed outcomes containing real assertions;
  VM has fifteen pure assertions. Final input hashes match.
- Preserve failed intermediate runs: authorization import collision in114,
  metrics four error-only outcomes in114, and VM subscription four error-only
  outcomes in114b. The last came from the earlier VM test order; assert handler
  installation in both source suites rather than reordering the campaign.
- Fresh `mcp114-vm` is a package-test-only selection: non-CLI library
  1,605/1,617 (99.26%), all MCP 2,544/3,927 (64.78%). It omits the broader
  router-hosted CLI integration suite; its whole-workspace policy correctly
  fails. Do not replace historical full-package numbers with this subset.
  WASM line coverage remains unmeasured. Coverage input hashes match.
- Qwen triage/review used. Verify its claims independently: raw keyword tests
  omit positional arguments via a conditional map entry; lookup match coverage
  already exists; synchronous helpers have only synchronous callers. Add
  explicit timeout/error controls rather than weakening assertions. Evidence
  and survivor reviews live in `coverage114-ci-mcp-oracles`.
- Fast114b passes; Verify114 stops on external native-lock contention as recorded
  above, not a clean verification pass. At the
  existing head package/image dry runs and WAMP profiles pass, but hosted CI
  also exposes PEM/PKCS8, installer, remote-authenticator and native benchmark
  auth assertion gaps. Retain `hosted114-gate-failures` for next repairs. No
  merge, publication, version bump or whole-milestone completion.

### Work112 Assertion-Based CI Gate And Oracles

- Two fail-first CLI regressions prove that test-error-only and unclassified
  detections previously returned success. Gate the default 95% threshold on
  adjustedAssertionScoreLowerBound, require complete classification and retain
  the existing rejection of infrastructure errors/timeouts. Keep conventional
  score/adjustedScore, individual outcomes and equivalence validation unchanged.
- Persist the gate metric/threshold separately from conventional scores. A list
  run has no gate result; failed baselines remain incomplete. Tests cover the
  exact threshold, mixed evidence with real assertions, unknown evidence above
  threshold, crashes/timeouts, compile-only and equivalent-only inventories,
  and preserved raw/adjusted summaries. All 60 runner tests pass on macOS with
  one explicitly Linux-only test skipped.
- Valid MCP completion constructors/parsers now assert success before exact
  field, wire, boundary and immutability checks. Assert reference type and
  non-null context before dereferencing. All 212 tests pass. Focused VM coverage
  measures 104/104 completion lines; whole-workspace policy intentionally fails
  on this selection. The identical 54-candidate inventory improves from 19
  assertion kills and 25 test-error detections to 44 assertion kills, ten compile
  errors, no survivors/errors/timeouts, on VM and JavaScript separately. No
  exclusions/waivers or production protocol changes. WASM coverage is unmeasured.
- Auth selection tests require the intended provider identity and one options
  record before using single. Repeated binding close must complete successfully
  while retaining exact unregister/owner isolation checks. All 86 tests pass;
  focused library VM coverage remains 455/455. The initial full 294-candidate
  campaign records 173 assertions, three mixed detections with assertions, six
  test-error-only detections, seven survivors and 105 compile errors. Its strict
  gate fails at 93.12%, versus 96.30% conventional. The intermediate auth112b
  result is 94.71%: matcher completes propagates Future errors instead of
  reporting assertion failures. Inspect the explicit fake-binding success/error
  outcome instead, rethrowing TimeoutException; two controls preserve the exact
  timeout for both sync/async callbacks. Final auth112c passes with 176 pure
  assertions and six mixed detections containing real assertions, seven
  survivors, 105 compile errors, no error-only detections/errors/timeouts.
  Raw/adjusted assertion score 96.30%; no equivalents. Inventory and final hashes
  match. Keep both earlier failed reports unchanged.
- Inspect all seven auth survivors without waivers: initial busy state, release
  reentrancy/identity guards, null terminal cleanup, and empty method-list
  guards. Public lifecycle tests already cover delayed/reentrant cleanup and ID
  reuse. Record individual, source-hash-pinned control-flow investigations in
  the evidence directory; no public counterexample found, no waiver applied.
  GLM's separate backend refuses connections; no heavyweight
  review was obtained. Routine Qwen review is advisory: alleged missing summary
  validation is inapplicable to internally generated summaries, and the claimed
  missing high-score/unknown test already exists. The completion review reports
  no actionable findings; retain its narrow-context limitations. The final
  helper-only review reached its token cap, not a completed review; actual
  mutant logs prove an assertion failure plus the unchanged cleanup error.
- Preserve `assertion-gate112-mutations` as pre-oracle-change evidence; never
  overwrite it with the passing `core-completion112b-mutations` or separate
  `core-completion112-web-mutations`. Final auth rerun is `auth-server112c-mutations`.
  Coverage: `core-completion112-vm`, `auth-server112c-vm`. Fresh browser112b has
  123/123 completion JS lines, selected core 6,628/6,973 (95.05%) and form-only
  client 279/283 (98.59%); 172 unmeasured sources remain. All 469 Dart hashes
  match. Preserve browser112, whose broad input hashes drifted in the unrelated
  auth binding test before the final recollection. Logs and review context:
  `coverage112-assertion-gates`. Original MCP109 keeps running unchanged.
- Fast111/Verify111 passed before Work112. Fast112 and intermediate Verify112
  pass; the latter began before the last test change. Final settled Verify112b
  passes with observed exit zero, including Rust, installed-package smokes,
  JavaScript and WASM; final component hashes match. The native owner is
  released; new-head hosted checks remain required. Work111 is
  pushed as `a3892e14`; package/image dry runs and WAMP profiles pass, CI remains
  pending. MCP100-library source/test/support hashes still match: 170 error-only
  detections leave assertion evidence at 75.84%, so the stronger gate correctly
  requires more work despite the old conventional pass. Prioritize those test
  gaps next, retaining its complete 1,098-candidate inventory and old report.
  No merge, publication, version bump or whole-milestone completion.

### Work111 MCP OAuth Boundary Assertions

- Add 12 mismatched resource URI cases and four valid exchanges through the
  public client. Require the exact rejection type/resource and zero postUrl
  calls before any token request; valid cases verify the complete token form
  and grant fields. Preserve case-insensitive schemes/hosts, default ports and
  case-sensitive paths/queries. Credentials and even empty fragments are rejected.
- Add 289 step-up cases: every ASCII code point plus non-ASCII boundaries in
  both previous scopes and server challenges, empty scopes, exact ordered union
  and duplicate removal, and HTTPS/loopback metadata URL acceptance/rejection.
  Expected scope characters use an explicit independent alphabet. Construction
  makes no HTTP calls. Deterministic persisted grants avoid wall-clock expiry.
- Valid form and step-up constructors now use returnsNormally before their
  existing exact-value assertions. Successful asynchronous grant exchanges
  capture synchronous throws with Future.sync and assert completion contents.
  Do not change mutation classification or relabel historical test errors.
- All 1,464 MCP VM tests pass; 248 form tests pass separately on JavaScript and
  WASM. `client-mcp111-vm` measures the complete HTTP client file at 1,862/1,955
  lines (95.24%); the whole-workspace policy fails on this focused selection as
  expected. Source/test/config hashes are retained. No WASM coverage claim.
- `client-oauth111-diagnostics` replays all 53 previously recorded candidates
  at lines 42..81 plus the recorded form minLength error, using the complete
  current MCP test directory. Both baselines exit zero; 50 assertion kills,
  four compile errors, no survivors/timeouts or equivalents. This is a scoped
  diagnostic, not a replacement full-target score. Original MCP109 remains
  running unchanged with all 1,597 candidates and its old test hashes.
- Local review's alleged form-recording race is refuted: the server records
  the form before writing its response. Construction checks already wrap both
  identified calls. throwsA explicitly invokes Future-returning functions;
  the mutation log proves a mismatched resource returning a grant fails that
  matcher, refuting the suggested silent pass. The final scope-fixture review
  reports no findings; retain
  the first token-limited review as incomplete. The first browser launch used
  an absent Chrome path; corrected runs use the verified repository launcher.
- Fast110/Verify110 passed before these test changes. After native110 exits,
  fresh Fast111 and settled-input Verify111 pass with observed exit zero,
  including native tests, installed-package smokes, JavaScript and WASM.
  Source/test/configuration hashes still match the diagnostic and VM evidence.
  Evidence lives under
  `coverage111-mcp-oauth`, `client-mcp111-vm` and `client-oauth111-diagnostics`.
  Work110 is pushed as `72c6b904`; package/image dry runs and WAMP profiles pass,
  while main CI is pending. The strict hosted audit remains nonzero.
  No merge, publication, version bump, waiver or whole-goal completion claim.
- Measurement follow-up: the Dart runner's exit threshold still compares the
  conventional adjustedScore, not adjustedAssertionScoreLowerBound. Its green
  CI jobs do not prove the goal's assertion threshold. Enforce assertion-based
  completion before the milestone can close, preserving historical results and
  fixing genuine test gaps rather than relabeling test-error detections.

### Work110 Native Result And Consumption Oracles

- Reproduce the native108 fixture gaps from preserved mutant logs before
  changing tests: completed WebSocket client failures become listener timeouts,
  no-op HTTP/stream/upgrade completions block peer reads, and missing metadata
  pointers reach unsafe slice construction. These are test-observation gaps,
  not new defects in unmutated production code.
- Add a test-only client helper that observes completed calls before server
  polls, retains early successful RawSocket IDs, allows server acceptance before
  client completion, and bounds waits. Preserve worker panic payloads and
  non-assertion deadline panics. Five deterministic helper regressions and all
  177 FFI library tests pass.
- Existing live fixtures now assert synchronous ownership postconditions:
  successful HTTP responses and WebSocket acceptance consume their handshake;
  finished response streams reject further writes. Keep exact wire/payload
  assertions. Validate borrowed metadata pointers before unsafe reads.
- `native-fixtures110-probe` completes all 16 generated candidates with the
  entire 177-test suite, passing baseline and unchanged 180-second deadline.
  Strict audit: 15 assertion kills, one error, zero timeouts/survivors, 93.75%
  raw/adjusted, no equivalents. The remaining error is a custom assert! message
  on a real completed-client return check, not a timeout. Preserve the report
  and `native110-current/source-scopes.json`; future checks use standard assert!
  diagnostics. Do not loosen the auditor or reclassify historical errors.
- The initial invocation rejected --jobs with --in-place before running tests;
  preserve its log separately. The corrected command uses the wrapper's single
  in-place worker in a disposable native tree. Local review found no concrete
  issue; the existing global test guard serializes native runtime access.
- Evidence: `out/regression-coverage-2026-09-15/coverage110-native-fixtures`.
  Fast109/Verify109 passed before changes. Fresh Fast110 and settled-input
  Verify110 pass with observed exit zero, including Rust, installed-package
  smokes and Chrome JavaScript/WASM tests. Final `native110b-current` input
  hashes match. After verification exits, the complete 81-candidate boundary
  rerun runs as the sole native owner; its inventory is identical to native108.
  Final strict audit: 78 assertion kills, three errors, no survivors/timeouts,
  96.30% raw/adjusted, no equivalents. All three errors are SIGSEGV after mutating
  null-pointer guards before CStr::from_ptr in the RawSocket/WebSocket client
  functions. Keep them as errors; this does not establish a defect in unmutated
  code. Strict audit exits one with evidenceClean false, whereas cargo-mutants
  reports 81 conventional detections. This remains a boundary slice, not the
  whole native component or unsafe-function coverage. The new helper
  files are test-only under the unchanged analyzer; no production exclusion,
  native behavior change, waiver, merge, publication or version change.
- Work109 is pushed at `e5410370`; both hosted package dry runs, image dry
  run and WAMP profiles pass. Main CI remains pending. The initial strict audit
  remains nonzero for pending evidence and existing branch protection/workflow
  visibility findings. Old-head CI was cancelled only after new-head runs
  appeared; cancelled runs are not passing evidence. The full goal stays open.
- During the preserved, still-running MCP campaign, individual mutation logs
  identify valid-input construction errors before eager expect() evaluation:
  OAuth step-up scope construction and form minLength boundaries are examples.
  These remain test-error detections, not assertion kills. Follow-up should
  explicitly assert successful construction/completion plus exact values for
  valid inputs, alongside the already-identified OAuth negative resource cases.
  Do not edit the current campaign snapshot or infer its final score early.

### Work109 MCP Form And Content Boundaries

- Add 248 public form regressions for malformed roots/properties, wire request
  decoding, independent required/optional fields, Unicode rune lengths, finite
  numbers, inclusive bounds, enum/cardinality constraints and exact action
  output. Thirty assertion failures reproduce calendar normalization and
  invalid RFC3339 grammar acceptance, plus rejection of lowercase `t`/`z`.
  Validate calendar fields without overflow and enforce timestamp grammar;
  retain offsets, fractions and possible month-end UTC leap-second placement.
  This is not an IERS announcement lookup. Record primary sources and the
  validation decision in `docs/mcp_integration_research.md`.
- Add 592 real loopback HTTP cases covering tool, prompt, resource and catalog
  content across both protocol eras and direct/streamable helpers. Independently
  reject malformed values, then receive exact valid data on the same client.
  Verify wire method counts and Accept negotiation; modern direct requests
  still advertise both JSON and SSE. All cases pass.
- Final focused VM collection `client-mcp109c-vm`: all 1,159 client MCP tests
  pass, complete HTTP-client file 1,860/1,955 measured lines (95.1407%), 95 missed
  lines. Source/test/config hashes match. Retain the full unmeasured inventory
  and expected whole-workspace-policy failure for this narrow selection; do
  not replace the historical whole-VM package table with this file score.
- Form-only JS and WASM behavior: 248 tests pass on each, launched from the
  package root. Add these cases to canonical browser verification and JS
  collection, with a fail-first script-inventory check. All 54 verification
  script tests and 56 mutation runner tests pass (one optional platform skip).
  `browser109-current` succeeds: selected core 6,628/6,973 (95.05%) and form-only
  client 279/283 (98.59%), with 172 unmeasured library sources. Browser tree
  shaking makes the form-only denominator narrower than the full VM HTTP file;
  it is not full client/browser completion. WASM counters remain unavailable.
- Preserve failed collection attempts separately: selecting default platforms
  also ran HTTP-server tests in WASM; workspace-root browser commands failed
  generated HTML loading. Corrected explicit VM and package-root browser runs
  pass. Early new wire-fixture failures were a missing constructor argument and
  an incorrect modern-direct Accept expectation, not production defects.
  Local companion timezone/rollover and missing-assertion suggestions were
  refuted using exact cases and source inspection, not accepted uncritically.
- Add `client-mcp-http-vm` over the complete HTTP client source and entire MCP
  test directory. `client-mcp109-mutations` retains all 1,597 candidates and
  passes its baseline. It is still running; no final score or new CI mutation
  gate is claimed. Do not change its tests and reuse this evidence as final.
  Early security-relevant survivors replace conjunctions in
  `_sameMcpOAuthResource` with disjunctions. Its only caller is
  `exchangeAuthorizationCode`; the unmutated implementation rejects mismatched
  resource URIs before opening the token exchange. Existing lifecycle tests use
  matching resources, so follow-up must vary scheme/host/port/path/query and
  reject user-info/fragments with an explicit zero-network-call assertion.
  These are uncovered negative contracts, not established production bypasses
  or equivalent-mutant waivers. Preserve the current campaign snapshot first.
- Native108 completes with 81 candidates: 66 strict assertion kills, 12 errors,
  three timeouts, no survivors or equivalents; raw/adjusted 81.4815%. Retain
  its conventional 78 detections separately. The strict audit exits one with
  `evidenceClean: false`, matching the unchanged native108 scope. Continue
  native missing-result fixture work and unsafe-function instrumentation; do
  not convert clock/timeout failures into assertion kills. Do not rerun the
  completed campaign merely because the score is incomplete.
- Evidence root: `out/regression-coverage-2026-09-15/coverage109-mcp-client`.
  Pre-change Fast108c and Verify108 were observed passing on the clean starting
  snapshot. Fresh Fast109 passes with observed exit zero after the native owner
  exited. Settled-input Verify109 also passes with observed exit zero, including
  Rust, installed-package smokes and Chrome JavaScript/WASM tests. Recorded
  source/test/config hashes still match. New-head hosted checks remain pending.
  No merge, publication, version change, exclusion or equivalence waiver. The
  whole goal remains unmet.

### Work108 Native TLS Boundaries And Lab Startup Race

- Add five native FFI regressions for null/empty/non-UTF-8 client strings, exact
  HTTP response status boundaries, both TLS client policy flags and zero-length
  WebSocket subprotocol output. TLS fixtures generate fresh self-signed
  certificates, accept any surfaced upgrade even on the expected-denial path,
  alternate zero/nonzero opt-in flags on one listener, and assert exact
  bidirectional payloads. Strengthen live invalid-status retry checks and
  assert buffer metadata before unsafe test reads without dropping payload checks.
- Reproduce the HTTP handshake test helper's negative-result deadline bypass
  with an expired deadline and injected pending-then-success poll. The real
  fail-first run is `coverage108-wait-fail-first2.log`; the earlier compile error
  is not behavioral evidence. Apply the deadline to negative and zero results,
  preserving legitimate transient retries. All 172 FFI tests pass with observed
  exit zero. Retain timeout/custom I/O wait panics as non-assertion failures;
  changing their syntax into assertions would not improve mutation detection.
- Fast108b fails in the lab-runner cleanup regression: its fake Flutter child
  writes the test marker between the first grep and the process-exit check.
  Inject that ordering deterministically into the actual Bash helper; the new
  test fails on the old implementation. Check the terminal log again, leaving
  later child wait/exit-status validation unchanged. All 15 lab-script tests
  pass with observed exit zero. This is script evidence, not emulator UI proof.
- Local companion findings were checked independently. The expired-deadline
  test does not iterate a positive pending handle; the listener exposes a
  connection only after successful TLS/protocol negotiation; the lab regression
  demonstrably fails when the final log check is absent. Do not weaken those
  assertions based on the advisory false positives.
- Evidence: `out/regression-coverage-2026-09-15/coverage108-native-tls-boundaries`.
  Settled Fast108c and Verify108 pass with observed exit zero, including Rust,
  installed-package smokes and Chrome JavaScript/WASM tests. The six changed
  implementation/test file hashes still match after verification. Fresh
  Cargo-only `native108-current` coverage completes with matching scope at core
  8,431/10,052 (83.87%) and FFI 4,655/5,798 (80.29%). Retain one core and three FFI
  unmeasured sources; do not combine this with older Dart-driven profiles.
  `native-boundaries108-mutations` runs the complete boundary inventory and
  full FFI library suite in an isolated native tree, with one local native owner,
  unchanged 180-second per-mutant limits and no skipped candidates. The final
  score is pending. Preserve the previous 81-candidate report and unsafe-function
  instrumentation gap. New-head hosted checks and strict audit remain required.
  No score waiver, merge, publication, version change or completion claim.

### Work107 Hosted Campaign Budgets And Completed Native Audit

- At `92f5c33f`, [PR CI MCP job](https://github.com/konsultaner/connectanum-dart/actions/runs/35300196245/job/105461036336)
  is cancelled by its 120-minute job limit after 1,062/1,098 mutants. The
  [push CI remote-WAMP job](https://github.com/konsultaner/connectanum-dart/actions/runs/35300192654/job/105461025721)
  processes all 286 mutants but hits its 20-minute limit before reporting final
  success. Both logs show continuing progress, not a stalled candidate. Their
  other same-head executions pass (MCP approximately 118 minutes, remote-WAMP
  approximately 15 minutes), but both overall CI runs remain cancelled.
- Replace the compound timeout expression with explicit matrix include budgets:
  MCP 180 minutes, remote-WAMP 45 minutes, all other budgets/default unchanged.
  Preserve complete inventories, 95% configured score gates, per-mutant limits,
  fail-fast=false and unconditional artifact uploads. Do not use retries or
  skipped candidates to mask incomplete campaigns. A fail-first configuration
  test verifies exact budgets, duplicate/unknown targets and default fallback;
  existing tests guard the mutation command and target inventory. Both focused
  workflow tests and all 27 deployment-audit tests pass. Local companion review
  finds no concrete defect; its fallback concern is covered by the exact default
  expression assertion. Fast107 and settled-input Verify107 both complete with
  observed exit zero, including Rust, installed-package smokes and Chrome
  JavaScript/WASM tests. Passing browser tests are not coverage measurements.
- Preserve cancelled-job logs and annotations under
  `out/regression-coverage-2026-09-15/coverage107-ci-budgets`. Full Verify, browser/VM
  coverage, consumer checks, package/image dry runs and WAMP profiles pass for
  the preceding head; require replacement hosted evidence after this fix.
- The original native106 campaign is terminal, not duplicated. Audit all 81
  candidates with `tool/native_mutations.py`, the native106b source scope and
  existing coverage-scope analyzer. `native-boundaries106-mutations/audited-results.json`
  records 48 assertion kills, 17 survivors, 13 errors and three timeouts,
  59.26% raw/adjusted, zero equivalents, with all per-mutant log hashes retained.
  The auditor exits nonzero as intended for unclean evidence. Conventional
  cargo-mutants reports 61 caught, which must not be presented as assertion kills.
  Unsafe function bodies remain outside the generator's inventory.
- Next native actions: exercise both FFI TLS verification flags through real
  connections, empty client arguments and HTTP status boundaries. Inspect
  missing-result test panics and unbounded fixture waits separately; improve
  behavioral oracles, not classification policy. Final coverage must still be
  refreshed against the final source/test snapshot. No merge/release/version
  changes; the original full milestone remains open.

### Work106 Native FFI Buffer And Handshake Boundaries

- Add 13 C-ABI regressions covering HTTP header arrays/fields, buffered bodies,
  streamed chunks, WebSocket protocol/reason strings, signed status/length
  boundaries, client port narrowing and nullable empty header values. Use live
  HTTP/WebSocket peers to verify exact response bytes, preserved handshakes and
  stream writers after invalid input, successful retries and consumed handles.
  Fixture runtime ownership is RAII-managed even if setup fails.
- Fail-first logs `/tmp/connectanum-coverage106-*-fail-first.log` retain assertion
  failures for status, optional lengths, body and client validation; invalid
  header/range/chunk cases abort with SIGABRT, and wrapped WebSocket string
  ranges segfault. Preserve those as crash reproductions, never assertion kills.
- Share pointer/length metadata checks before constructing borrowed slices or
  allocating header vectors. Keep valid null/zero-length buffers, UTF-8 decoding,
  public ABI signatures and WAMP wire behavior. The caller still owns allocation
  liveness, initialization and immutability; these checks do not make arbitrary
  foreign addresses safe. Follow Rust's
  [slice safety contract](https://doc.rust-lang.org/std/slice/fn.from_raw_parts.html)
  for alignment, maximum byte length and address wrap. Validate HTTP statuses
  within 100..599 before narrowing, as required by
  [RFC 9110 section 15](https://www.rfc-editor.org/rfc/rfc9110.html#section-15).
- Client WebSocket connect now shares header validation, rejecting a null array
  with positive length rather than silently discarding it. Both native client
  transports reject ports outside 1..65535 instead of wrapping the destination.
- All 13 focused tests pass. Full Rust workspace tests and fresh final
  `native106b-current` LLVM collection pass, including 165 FFI unit tests.
  Cargo-only totals: core 8,416/10,052 (83.72%), FFI 4,649/5,798 (80.18%).
  Existing platform/unmeasured-source gaps remain explicit. The intermediate
  `native106-current` predates the final string-range change; neither report
  can be combined with the different-input Work105 Dart/native collection.
- Native mutation inventory probing confirms cargo-mutants 27.1.0 deliberately
  skips unsafe function bodies (`visit.rs::fn_sig_excluded`), including the new
  pointer/header helpers. Retain that instrumentation gap; do not call a generated
  subset whole-FFI mutation completion or turn crash repros into assertion kills.
- VM105 completes with observed exit zero and 632 matching Dart input hashes
  before native edits: 38,515/42,612 (90.39%); router 17,003/19,331 (87.96%).
  Other package/packaging percentages match VM101; 59 library and 12 packaging
  source files remain unmeasured. Fast106 and settled-input Verify106 pass with
  observed exit zero, including Rust, installed-package smokes and Chrome WASM
  tests; the final native source/test/build scope still matches afterward.
- Start `native-boundaries106-mutations` using `bin/test-native-mutations`,
  package `ct_ffi`, feature `ffi-test`, file `ct_ffi/src/runtime/ffi.rs`, and regex
  `(checked_ffi_slice|read_http_headers|ct_http_response_|ct_connection_(accept|reject)_websocket|ct_client_connect_)`.
  Use `--cargo-test-arg=--lib --timeout 180 --build-timeout 600` and the
  full FFI library test suite, retaining the actual generated inventory rather
  than assuming the regex covers every helper. The campaign is running; no
  completed native mutation percentage is claimed for this increment.
  The wrapper's isolated `--in-place` execution is serial; cargo-mutants rejects
  an explicit `--jobs 1` alongside it before starting a campaign.
- At pushed head `ab8942b3`, package/image dry runs and WAMP profiles pass; main
  CI has pending jobs and no observed failed jobs. Require fresh hosted evidence
  after pushing this implementation. No merge/publication/version change.

### Work105 Instrumented Dart-To-FFI Coverage

- Complete fresh Cargo-only `native105-current` on macOS ARM64: core
  8,374/10,052 (83.31%); FFI 4,589/5,808 (79.01%). Keep the inactive/empty-source
  inventory explicit, including one core and three FFI unmeasured files.
- Add `bin/test-native-ffi-coverage` and its Python collector. Use the installed
  cargo-llvm-cov 0.9.1 external-test protocol (`show-env`, instrumented Cargo
  build, Dart callers, `report`), without evaluating its output as shell code.
  Fresh target/output directories prevent stale profiles or release-library
  substitution. Keep Cargo-only and Dart-driven native reports separate.
- Preserve per-group profiles, command logs and outcomes, the instrumented
  artifact hash, exact Rust scopes, and source/test/dependency hashes. Pin ignored
  Pub lock/override and package-map files as well as tracked inputs. Fail closed
  on missing/empty profiles, build/test errors, timeouts, changed inputs/artifact,
  or a surviving child that could write counters after its parent completes.
- Add nine collector tests. A real Dart executable calls a tiny Rust cdylib:
  verify the called branch has nonzero counters and the uncalled branch remains
  zero. The two fail-first probes in `/tmp/connectanum-coverage105-ffi-child-fail-first.log`
  and `/tmp/connectanum-coverage105-ffi-input-fail-first.log` expose process
  quiescence and ignored dependency-input gaps before correction. Native
  coverage-tool checks now run this suite; hosted Fast/Verify already enable
  its actual LLVM fixture. All 52 verification-script tests pass.
- `native-ffi105-current` completes with observed exit zero, 337 passing Dart
  tests across ten isolated groups and ten nonempty profile sets. Dart-driven
  native coverage alone: core 6,508/10,052 (64.74%); FFI 3,426/5,808 (58.99%).
  This selection covers buffers, E2EE, restart, transports, files, native
  runtime/lifetime, router integration, zero-copy and remote authentication;
  it does not claim legacy-ABI, other-platform or all-executable completion.
- The two Rust scope snapshots compare identically. Union their raw LCOV using
  `native_coverage.filter_lcov`, which deduplicates lines before computing
  totals: core 8,445/10,052 (84.01%), FFI 4,915/5,808 (84.62%). This establishes
  71 additional core and 326 additional FFI hits beyond Cargo tests, not new
  product behavior or a passing 98% threshold. `native-combined105-current`
  retains raw/filtered LCOV, summary and parent report/scope/collection hashes;
  calculation output is also in `/tmp/connectanum-coverage105-native-union.log`.
- Baseline Fast105 and settled-input Verify105 pass with observed exit zero.
  Verify105 includes Rust, installed-package smokes, 2,970 core Chrome WASM
  tests and two client WebSocket Chrome WASM tests. Collection precedes Verify;
  no native test/collection remains running. At pushed head `8b60e7f6`, package/image dry runs and WAMP profiles
  pass; main CI is pending with no observed failed jobs. Require new-head hosted
  evidence after pushing this implementation. No merge/publication/version change.
- Next: close the remaining genuine native/Rust and router gaps with targeted
  behavioral regressions and mutation evidence, add other native variants and
  applicable runtimes, and keep all final evidence input-matched.

### Work103/104 Exact Claims, Expiration And Result Contracts (Verified Locally)

- Separate untrusted issuer/audience comparisons from normalized configuration.
  Signed JWT/OIDC and actual HTTP introspection tests reject number/bool/object
  coercion, padded strings, case and Unicode-normalization mismatches, nested
  lists and mixed-type arrays before/after a matching audience. Valid exact
  scalar/list claims, optional restrictions, configuration normalization and
  successful recovery remain compatible. Initial 90-case run has 24 passes and
  66 assertion failures; preserve `/tmp/connectanum-coverage103-claims-fail-first.log`.
- [RFC 7519 sections 4.1.1/4.1.3](https://www.rfc-editor.org/rfc/rfc7519.html#section-4.1.3)
  require string issuer and string/array-of-string audiences;
  [section 7.3](https://www.rfc-editor.org/rfc/rfc7519.html#section-7.3)
  requires exact JSON string comparison. OAuth introspection uses the same claim
  definitions in [RFC 7662 section 2.2](https://www.rfc-editor.org/rfc/rfc7662.html#section-2.2).
  [RFC 7519 sections 4.1.4/4.1.5](https://www.rfc-editor.org/rfc/rfc7519.html#section-4.1.4)
  make expiration exclusive and not-before inclusive. Add optional factory
  clocks, preserving const zero-argument constructors and Stopwatch deadlines.
  Five deterministic expiry cases fail before the comparison fix, with zero or
  nonzero leeway and one-microsecond before/at/after assertions. Returned expiry
  remains the original timestamp, not the leeway-shifted deadline.
- HTTP103 completes with both baselines zero: 274 candidates, 186 detections,
  11 survivors, 77 compile errors, no timeouts/errors. Raw/adjusted detection is
  94.4162%; 170 assertions and 16 test errors give an 86.2944% assertion lower
  bound. HTTP104 preserves these raw outcomes and adds nine individual equivalent
  records in `tool/mutation_equivalents.json`, pinned to the provider source hash:
  zero-leeway branch equality, inaccessible null role-map lookup, null helper
  fallthrough, false/null at the sole TLS opt-in caller and a private list's
  unobservable growability. Adjusted detection is 98.9362%; adjusted assertion
  lower bound is 90.4255%. Do not waive the deadline-zero or BytesBuilder-copy
  survivors. Local review was checked against the RFC and Dart SDK: suggested
  permissive claim matching, inclusive expiry and null.toString() throwing were
  incorrect, and were not adopted.
- Add explicit result-contract assertions for valid configurations and malformed
  token/header/signature/date/introspection inputs. Catch Future errors as test
  observation values and assert HttpAuthResult, before checking success, identity
  and error reason. Invalid operator configuration retains its legitimate throws.
  Keep fail-fast mutation outcomes honest: later tests are not evidence when an
  earlier error stopped execution. HTTP104b is a fresh complete-source campaign
  with these assertions; do not relabel HTTP103/104 outcomes. All 281 provider
  tests pass, including blank scalar roles granting no empty role. The final
  focused HTTP104b coverage is 304/305 (99.67%), only the private constructor
  unexecuted, no exclusions. Its campaign completes all 274 candidates with both
  baselines zero: 186 assertions, 11 survivors including nine justified equivalent,
  77 compile errors, no test-error detections/timeouts/infrastructure errors.
  Raw assertion/detection is 94.4162%, adjusted assertion/detection 98.9362%.
  Source/test/support hashes match. Remaining unwaived candidates are the exact
  zero remaining deadline (potentially different timeout scheduling, not proven
  equivalent) and response buffer copying (ownership/performance distinction,
  not waived). Keep their outcomes and do not claim whole-router mutation coverage.
- Ten new loopback reverse-proxy regressions use the fake native boundary to
  assert exact UTF-8 byte limits, oversized and stalled header/body responses,
  actual upstream EOF after client cleanup, same-binding recovery, safe error
  events and invalid numeric/target options rejected without opening a socket.
  They and all 224 router-runtime tests pass. Final `router-runtime104b-vm`
  measures 2,469/3,636 binding lines (67.90%) with that single test-file selection;
  31 lines missed by VM101 are now exercised. It is not a whole-VM replacement
  or a merged percentage. Hashes match. These are Dart binding tests, not native
  socket implementation coverage. All focused coverage runs correctly fail the
  whole-workspace policy because other sources were not measured by that run.
- Wire router-http-auth-vm into the hosted matrix with the existing 45-minute
  auth-job budget, keeping 95% detection and per-mutant timeouts unchanged. Add it
  to the deployment audit's exact required job set and simulated job fixtures.
  A source-scope/CI test first fails for the missing job, then all 83 runner/audit
  tests pass (one Linux-only skip). Preserve `coverage104-ci-gate-fail-first.log`
  and `coverage104-ci-tool-tests.log` in `/tmp` with the connectanum prefix.
- Fast103 and Verify103 finish with observed exit zero. Verify103 predates final
  test edits. Verify104 stops at formatting before tests; fix the test indentation
  and run settled-input Verify104b, which completes with directly observed exit
  zero, including Rust, package consumer smokes and browser JS/WASM tests.
  The native runtime is released for fresh native coverage collection. Preceding
  `1f07e393` package/image/profile dry runs and hosted Full Verify pass; other
  main CI jobs are still running. New-head hosted evidence/audit remain required.
  Keep PR93 draft and preserve the complete cross-component/runtime goal.
  Next prioritize the remaining binding request/auth/continuation branches and
  native/runtime gaps; a passing HTTP-provider subcomponent is not completion.
  Refresh the historical native23 LLVM report before choosing native tests.
  `bin/test-native-coverage` currently collects Cargo workspace tests; investigate
  instrumented Dart-to-FFI execution separately rather than treating ordinary
  Dart integration passes against a release library as LLVM coverage evidence.

### Work102 HTTP Deadline Error Ownership And Bounded Date Arithmetic (In Progress)

- Work100/101 is committed/pushed as `9ae1c14e`; PR93 remains draft. Verify101
  and VM101 both complete with directly observed exit zero. The fresh whole-VM
  library report is 38,482/42,609 (90.3143%), with 59 unmeasured sources retained.
  Packaging remains 765/787 (97.20%) with 12 unmeasured sources. Preserve the
  raw/LCOV/summary/input manifest at `vm-current101`; hashes were checked before
  subsequent Work102 edits. Do not relabel it as current Work102 evidence.
- Current-head package dry runs, image dry run 35290093456 and WAMP profile run
  35290095322 pass. Main CI is still pending. Cancel only superseded runs
  35286985122 and 35286988885 to release capacity. Strict audit remains required.
- A standalone public-factory probe reproduces unhandled SocketException after
  an otherwise handled auth_timeout, plus RangeError for extreme valid JWT
  dates with leeway. Checked-in fail-first tests reproduce JWT/OIDC failures and
  assert the guarded zone contains no leaked errors. Preserve
  `/tmp/connectanum-coverage102-{probe,http-fail-first}.log`.
- Compare date differences rather than adding/subtracting leeway from bounded
  DateTime values. Observe each HTTP operation before remaining-budget evaluation
  can throw; continue awaiting its original result with the same shared deadline.
  Late errors after a terminal timeout remain redacted, not logged. GLM review
  confirms awaited pre-deadline errors remain observable; its suggestion to log
  discarded late errors is intentionally rejected. The remaining-budget helper
  already throws for nonpositive durations; no timeout-clamping workaround.
- Expand to 173 passing provider tests: late open/close errors, literal complete
  vs partial Basic/bearer credentials, exact chunked/content-length UTF-8 bounds,
  rejection before reading an oversized declared body, invalid UTF-8 followed by
  recovery, a valid JWT plus an extra segment, empty-identity fallback and negative
  skew. Correct an initial test fixture to use the supported username fallback,
  not an invented authid alias; no production change for that fixture failure.
- Replace the forever-pending setup-deadline fixture with a valid eventual result:
  ignoring the timeout can now fail the authentication assertion rather than hit
  the runner deadline. Retain real HTTP/TLS coverage alongside synthetic phase
  fixtures. Targeted analysis passes. `http-auth102-vm` preserves raw/LCOV/input
  hashes and measures 305/306 (99.67%); only the private constructor is uncovered.
  Its isolated test run is not a passing whole-workspace coverage gate.
- HTTP102 completes all 272 generated candidates: 176 kills, 19 survivors,
  77 compile errors, no timeouts or infrastructure errors. Both baselines pass,
  and source/test/support hashes match. Conventional raw/adjusted detection is
  90.2564%; its 158 assertion and 18 test-error detections give an 81.0256%
  assertion lower bound. No waivers or passing 95% HTTP gate. MCP100 completes
  all 1,098 candidates: 804 kills, 32 survivors, 262 compile errors, no timeouts
  or infrastructure errors, both baselines zero. Raw/adjusted detection is
  96.1722%; its 634 assertion and 170 test-error detections give a 75.8373%
  assertion lower bound. Source/test/support hashes match. Keep all survivors
  explicit; this is non-CLI library coverage, not whole-package completion.
  Fast102 and Verify102 both pass with directly observed exit zero, including
  Rust, package/consumer smokes and browser JS/WASM tests. All local campaigns
  are complete and the native runtime is free. Pushed-head
  Fast Checks now passes; hosted Full Verify is running and the strict audit
  remains non-green for pending CI. Keep all mutation outcomes and the full milestone
  open, with no equivalence waivers, merge, publication or version change.
- Survivor follow-up probe `/tmp/connectanum-coverage102-claim-probe.dart` signs
  independent fixture tokens and reproduces audience coercion/normalization:
  numeric 42 authenticates for string "42", an empty array for literal "[]",
  and padded scalar/list strings for an unpadded audience. Preserve its failing
  exit and log. This is a real next security defect, not an equivalence waiver.
  [RFC 7519 section 4.1.3](https://www.rfc-editor.org/rfc/rfc7519.html#section-4.1.3)
  defines scalar string or array-of-string audiences, with section 7.3's exact
  string comparisons. Next add checked-in JWT/OIDC/OAuth fail-first cases and
  separate strict token audience/issuer comparison from configuration parsing.
  Do not alter the live verification or mutation snapshots to imply this is fixed.

### Work101 HTTP Bearer Validation And Hosted Analyzer Failure (In Progress)

- Hosted push run 35283872576 now has a failed Fast Checks job 105411747954.
  It exits during analysis, before running regressions: receive().listen() in
  the native paused-listener regression dereferences a nullable stream. The
  local analyzer reproduces it; an explicit non-null assertion fixes analysis
  without skipping the test or changing its behavioral assertions. Preserve
  `/tmp/connectanum-coverage101-{ci-fast,native-analysis-before,native-analysis-after}.log`.
- Push the one-line CI correction separately as `1a187bc2`. Both package dry
  runs pass; current main CI is pending. Cancel only six older active CI runs on
  this branch to release hosted capacity, retaining logs and all local campaigns.
  The strict audit still fails pending CI and stale profile evidence.
- The replacement hosted Fast Checks job 105421393404 in run 35286985122 gets
  past analysis and fails the WebSocket JSON EOF/reconnect case while rebinding
  the old port. The helper force-kills the peer before its asynchronous finally
  block has completed server.close(). Waiting for natural exit fails Verify100
  in all three WebSocket EOF cases, so use an explicit listener-closed message
  sent only after awaited server.close(), then dispose/rebind. Keep forced
  teardown for remaining isolate resources; do not enable shared binding, add
  sleeps or weaken the reconnect test. All six EOF and all 50 native transport
  cases pass, as do focused analysis and formatting. Preserve
  `/tmp/connectanum-coverage101b-ci-fast.log` and the failed Verify100 log.
  Fresh Verify101 completes with directly observed exit zero on settled inputs,
  including Rust, package smokes and browser JS/WASM suites. Hosted CI remains red
  until the correction is pushed and replacement checks pass.
- Native99 completes 368 candidates with 157 kills, 94 survivors, 32 timeouts,
  one error and 84 compile errors; both baselines pass. Raw/adjusted conventional
  score is 55.2817%. Its 93 assertion, 35 mixed and 29 test-error detections give
  an assertion lower bound of 45.0704%. No waivers. Its native-test hash predates
  the analyzer correction; do not claim it as final-snapshot evidence. The queued
  Fast100 passes; after the recorded Verify100 failure, Verify101 passes and
  releases the native runtime for fresh whole-workspace VM coverage. MCP100 stays
  live.
- Public-factory JWT/OIDC and real-loopback OAuth tests reproduce four defects:
  malformed signature decoding throws; malformed present exp/nbf can authenticate;
  fractional JWT expiry is truncated; OAuth ignores future nbf despite active=true.
  The first targeted run records two passes and 63 failures, including explicit
  fail-closed assertions. Preserve `/tmp/connectanum-coverage101-http-auth-fail-first.log`.
- Parse all JWT segments inside the format-error boundary and return a generic
  failure without reflecting encoded token data. Time validation distinguishes
  absent optional claims from present invalid claims, checks finite/range bounds
  before scaling, preserves JWT fractions and requires integral OAuth timestamps.
  Check OAuth nbf. Never reuse the permissive configuration integer parser for
  security-sensitive token claims.
- Standards: [RFC 7519 sections 2 and 4.1.4-4.1.5](https://www.rfc-editor.org/rfc/rfc7519.html#section-2)
  define optional numeric dates, including fractions for JWT. Present null or
  strings are not NumericDates. [RFC 7662 section 2.2](https://www.rfc-editor.org/rfc/rfc7662.html#section-2.2)
  specifies integral exp/nbf introspection timestamps. This deliberately rejects
  previously accepted malformed claim types; valid public factory APIs and
  omitted optional dates remain compatible.
- Expand to 153 passing provider tests: independent HMAC fixtures, recovery,
  fractional/integral/non-finite/bounded dates, issuer/audience rejection,
  identity/role mapping, immutable registry snapshots, encoded HTTP requests,
  configuration errors, endpoint failures and client disposal after synchronous
  setup exhausts the deadline. Final `http-auth101d-vm` measures 301/302 (99.67%)
  with only the private registry constructor uncovered. Retain raw/LCOV/summary
  and exact input hashes; earlier 101/101b/101c reports remain separate. The focused
  report does not pass whole-workspace gates. Add a 98% file floor.
- The first complete-source router-http-auth-vm mutation campaign finishes all
  268 candidates: 141 kills, 49 survivors, one timeout and 77 compile errors,
  with both baselines zero. Raw/adjusted score 73.8220%, assertion lower bound
  63.8743% (118 assertion, four mixed, 19 test-error detections); no waivers.
  Preserve this report unchanged. Its surviving active-token check exposes an
  otherwise-invalid inactive-token fixture. Add usable-identity inactive cases,
  real TLS handshake default denial/explicit opt-in, canonical claim precedence,
  iterable scope mapping and truncated signatures. Pin the existing certificate
  fixtures as mutation supportFiles. The full `http-auth101b-mutations` rerun
  completes with 158 kills, 32 survivors, one timeout and 77 compile errors;
  both baselines zero. Raw/adjusted detection improves to 82.7225%, assertion
  lower bound 73.2984% (136 assertion, four mixed, 18 test-error detections).
  Source/test/support hashes match. The timeout_ms fallback mutant still times
  out and is not an assertion kill. Remaining TLS-parser-equivalence candidates,
  credential precedence, byte-limit equality, deadline-budget and helper cases
  stay explicit; no waivers or 95% gate. Targeted analysis,
  coverage-tool tests and 55 runner tests pass (one optional skip). Local GLM
  review misstates Dart's DateTime bounds; verify the SDK's documented
  100,000,000-day limits and add passing endpoint tests rather than widening to
  overflow-prone values. No underlying token exceptions are added to logs.
- HTTP and MCP implementation changes pass final Verify101 and are ready for
  the feature-branch implementation commit; replacement hosted checks remain
  required. Keep the complete cross-runtime milestone open, with no
  merge, publication or version change.

### Work100 MCP Survivor Oracles And Listener Cleanup (In Progress)

- Preserve completed MCP97 evidence: 1,098 candidates, 798 kills, 38 survivors,
  262 compile errors, both baselines zero and 95.4545% conventional detection.
  Its read-only `kill-evidence100.json` audit reports 627 assertion detections
  and 171 test errors, giving a 75% assertion-detected lower bound. This report
  predates the tests below; do not relabel it current or waive its survivors.
- Add real LocalTransport assertions for recipient selection and option-alias
  precedence, removing consumed aliases without mutating caller inputs. Mixed
  recipient lists must return actionable errors before any Publish, and a later
  valid Publish must succeed. Preserve raw meta argument compatibility with an
  explicit match override, precise completion errors and subsequent recovery.
  A serialization observer distinguishes discarding revoked pending events from
  merely suppressing their eventual response; prove its positive control first.
- Extend the HTTP peer with request-scoped SSE notifications. Successful updates
  acknowledge only the requested resource, publish, reread and remain sessionless.
  Reject empty acknowledgements, unrequested resources/list-change subscriptions,
  malformed notification URIs and publication failures without subsequent reads.
  Correct initial fixture assumptions: WAMP publish uses the generic tool-call
  envelope; unrequested acknowledgements are rejected by the client parser.
- `/tmp/connectanum-coverage100c-resource-fail-first.log` isolates a real defect
  after those fixture corrections: the publication error is handled, but listener
  cleanup leaks `StateError: No element` into the zone. Observe the pending
  notification future before publishing; retain its later await and fail-closed
  notification behavior. The regression asserts the separate unhandled-error
  collection is empty, rather than treating a runtime error as an assertion kill.
- All 756 MCP cases and targeted analysis pass. `mcp100b-vm` preserves matching
  source/test hashes, raw coverage and LCOV: non-CLI library 1,605/1,617 (99.26%),
  CLI 939/2,310 (40.65%), combined 2,544/3,927 (64.78%). The isolated MCP test run
  omits cross-package CLI integration coverage; it is not comparable to VM96's
  complete-workspace percentage and does not pass whole-workspace policy gates.
  Preserve preliminary `mcp100-vm` separately; it predates the listener tests/fix.
- Fresh full `mcp100-library-mutations` runs 1,098 candidates after its clean
  baseline, with no new equivalence waivers. Native99 is still live and is the
  sole native-runtime owner. One queued validation process waits for its exact
  PID/command to finish, then runs `bin/test-fast` and `bin/verify` sequentially
  into `/tmp/connectanum-coverage100-{fast,verify}.log`. These gates are pending;
  the previous Fast98/Verify99 results are not Work100 completion evidence.
- Changes remain uncommitted until verification. Work99 `94c04567` package dry
  runs, router-image dry run and profile benchmark pass; main CI jobs remain
  running/queued, so hosted handoff is not green. Keep PR #93 draft and the full
  milestone active. No merge, version change or publication.

### Work99 Native EOF And Receive-Worker Lifecycle

- A real loopback RawSocket test fails first with the assertion "peer EOF must
  notify connection loss" after a peer sends WELCOME and closes. The old
  receive worker silently leaves its handle stream open: its exit port is only
  consumed by explicit `close()`. Preserve
  `/tmp/connectanum-coverage99-eof-fail-first.log` as the behavioral repro.
- Use a single ordered port for data, errors and exit, with a buffered
  single-subscription handle stream. Capture the controller and completion
  futures for each attempt; old pumps cannot replace/clear a newer connection.
  Notify loss without awaiting a paused subscriber's close. Normal EOF after
  GOODBYE closes the stream and completes disconnect without a connection-loss
  error. Yield between synchronous 50 ms native waits to handle stop messages.
  Shutdown remains bounded; SDK error-listener payloads support a nullable
  stack string and preserve RemoteError stack traces.
- Add 19 regressions across both transports and all serializers: abrupt EOF,
  reconnect with fresh completion state, received GOODBYE, explicit close while
  the worker is spawning, and paused-listener notification. All 107 combined
  transport/file cases pass, as does focused analysis. Correct test fixture
  port reuse: the HTTP peer still listens when its first upgraded connection
  closes without Hello; reuse it rather than killing and immediately rebinding.
  This fixture failure is distinct from the reproduced production EOF defect.
- `native-transports99-vm` measures 418/466 lines (89.70%), with 48 uncovered
  lines retained, versus Work98's 388/440. Its six input hashes match the tests,
  source, runtime, support helper and ffi-test artifact. The focused checker fails
  whole-workspace gates; this is not Rust coverage or a 98% achievement.
  Verify99 passes with directly observed exit zero on settled inputs, including
  Rust, package/consumer smokes, browser JS, 2,970 core WASM and two WebSocket
  WASM tests. Its native runtime is released for the next complete campaign,
  `native-transports99-mutations`. Fast98 passed before this increment. No final
  mutation score yet; passing WASM tests are not measured WASM line coverage.
- Local Qwen/GLM reviews are advisory: completing both disconnect and connection
  loss contradicts the existing transport/client contract; the SDK specifies
  two-element error lists, not bare strings. Do not infer native double-release
  from isolate exit because the receive isolate does not release sent handles.
  Keep immediate-EOF trailing-handle and materialization-failure cleanup tests
  as explicit follow-ups rather than claiming the timed peers prove them.
- Work98 `e94f5462` is committed and pushed to the coverage branch and PR #93
  updated. Its router-image dry run `35282024554`, profile benchmark run
  `35282026997` and package dry run `35282002153` pass. Strict audit remains
  non-green while main CI is queued; retain
  `/tmp/connectanum-coverage98-hosted-audit.log`. No merge or publication.

### Work98 Mutation Evidence And Native Boundaries

- Add per-kill cause evidence (assertion, caught test error, mixed or unknown)
  and assertion-detected lower bounds while retaining all existing raw/adjusted
  scores and denominators. Reset reporter IDs across isolated commands. The
  separate `tool/audit_mutation_kill_evidence.py` reclassifies saved kill logs,
  checks their existing counts/scores, hashes input/report/log/tool evidence,
  rejects escaping paths and derived re-audits, and exclusively creates output.
  It never rewrites originals or makes historical source/test hashes current.
  All 55 tooling tests pass, one optional skip. Real Dart reporter probes
  protect assertion versus caught exception and mixed teardown attribution.
- Preserve and finish native97: all 348 candidates complete, with 107 kills,
  126 survivors, 23 timeouts and 92 compile errors; 41.796875% raw/adjusted,
  clean initial/restored baselines and unchanged native artifact. No waivers.
  Its read-only audit reports 58 assertion, 36 test-error and 13 mixed kills;
  71/256 gives a 27.734375% assertion-detected lower bound. Other historical
  audits preserve remote-auth96b (96.875%), remote-delegate97b (96.2567%) and
  router-config96 (97.2145%) conventional scores without claiming assertion-only
  detection. Derived reports are `kill-evidence98.json` beside each original.
- Add 12 native regressions: literal MessagePack/CBOR length headers at uint32
  and int64 boundaries without huge allocations; corrupted suffix bytes and
  truncated tails for every serializer; batch sentinels and exact one/default
  caps; refused connection, fresh readiness/lost futures, idempotent open/close
  and successful same-port reconnect for RawSocket/WebSocket and all serializers.
  Peer helpers run in separate isolates and close only after Hello/Welcome.
  An initial expected batch size of 64 was a test-authoring mistake, corrected
  to the source's 32; it is not reported as a production bug fix.
- Focused 31 transport plus 57 file/runtime tests pass. With explicit ffi-test
  artifact and matching input hashes, `native-transports98-vm` measures 388/440
  lines (88.18%), up from 377/440 (85.68%). Keep all 52 uncovered lines visible.
  Native97 predates these test changes and must not be relabeled current evidence.
  Whole-workspace VM96 remains 89.82%; do not add focused gains to that snapshot.
- Fast98 passes. Verify98 runs through the final successful 2,970 core WASM
  and two WebSocket WASM cases and its PIDs are terminal. The app restart lost
  its original command handle, preventing direct recovery of the exit status;
  retain `/tmp/connectanum-coverage98-verify.log` and this evidence limitation.
  Qwen and GLM reviews were checked against source: no verified reporter defect;
  the proposed int64 header correction and pre-Hello peer timer race were false
  leads. Formatting, focused analysis and diff checks pass. MCP97 remains live.
  No merge, publication, version change, lowered threshold or equivalence waiver.

### Work97 Trust Roots And Native File Transport Wrappers

- Resume clean `c769e76f`, preserving live VM96/MCP95 runs. VM96 finishes zero
  at 38,236/42,569 measured library lines (89.82%) with 59 unmeasured sources;
  keep it separate from this turn's focused additions. MCP95 finishes 1,098
  candidates at 798 kills, 38 survivors and 262 compile errors, 95.4545%, both
  baselines zero. Its CLI-options test hash differs from the current file, so
  start MCP97 only after confirming MCP95 terminal. No final-snapshot claim.
- Add a subprocess-local trust fixture using Dart `--root-certs-file` and the
  independent HTTP3 and remote-auth CA fixtures. Eight real TLS handshakes
  prove default and client-only contexts accept the default root, while custom
  CA contexts accept only their configured root, with/without client identity.
  No public network or machine trust-store changes. The previous security
  survivor `ae7cfcc5b9c3e81af8cd` now fails the explicit trust-result assertion.
  Add the test, probe and all certificates/keys to mutation input hashing.
  The initial partial campaign is interrupted to remove an unused import;
  preserve it as incomplete, superseded evidence. `remote-delegate97b-mutations`
  completes all 286 candidates on the settled snapshot: 180 kills, seven
  survivors, 99 compile errors, 96.2567% raw/adjusted, both baselines zero and
  all 14 source/test/support hashes matching. Keep the other seven survivors
  visible; no equivalence waivers or source changes.
- Add 18 file-wrapper cases: two transports, three serializers and three
  encryption modes. Reuse the RawSocket peer and add a WebSocket peer in a
  separate isolate; validate negotiated subprotocol and text/binary frames.
  Decode received WAMP independently, decrypt with portable providers, check
  exact ranges/header boundaries through 65,536 bytes, reject foreign runtime
  contexts/invalid sources, close sources twice and send ordinary messages on
  the same connection afterward. All 57 runtime/file tests and existing
  transport tests pass. The first focused report is 376/440 (85.45%). Repeat with
  an explicit current `ffi-test` library and record its artifact hash:
  `native-files97b-vm` measures 377/440 (85.68%) for the complete wrapper versus
  271/440 (61.59%). Keep 63 uncovered lines and missing workspace
  scopes visible; the focused report intentionally does not pass workspace gates.
- Add whole-source target `client-native-transports-vm` with both test files,
  native-runtime support hashes and serialized native execution. Its 348-mutant
  inventory is generated. After verification releases the native runtime,
  `native-transports97-mutations` starts with a clean baseline and the recorded
  `ffi-test` artifact hash. It is the sole native owner; retain its initial
  timeout outcomes separately from kills and do not overlap new native runs.
  The manifest guard fails first; all 48 runner tests then pass (one optional
  skip). Do not add a passing mutation CI gate before measuring its score.
- Qwen's suggested WebSocket file-capability rejection contradicts the source
  and real native wire results. Its proposed uniform foreign-source exception
  also contradicts the distinct clear/E2EE API contracts. Keep the verified
  assertions. The TLS process has an exit deadline and teardown kill; stderr
  collection does not replace that deadline. SDK WebSocket/server closes are
  idempotent; the fixture's cleanup remains defensive.
- Fast97 passes as the starting regression check. Focused tests, formatting and
  analysis pass. Verify97 passes on settled test/manifest inputs, including Rust,
  native/package/consumer smokes, 2,970 core WASM and two WebSocket WASM tests.
  Passing WASM tests are not measured WASM line coverage. Work96's
  package/image/profile dry runs pass and its main CI is in progress. No merge,
  package publication, version change, coverage exclusion or equivalence waiver.
- A scoring audit distinguishes caught test exceptions from process crashes.
  `classify` currently counts a completed real test's failure or error as a kill;
  process/suite/infrastructure failures and deadlines are separate outcomes.
  The remote-authenticator96b kill logs contain 85 expectation-failure and 39
  runtime-error events across 124 killed mutants. Earlier "assertion kill"
  wording is inaccurate for these conventional mutation rates. GLM review
  confirms the distinction, independently verified in the JSON test events.
  Expose separate kill causes/scores in follow-up measurement tooling; retain
  original reports and do not claim that the current rates are assertion-only.

### Work96 Configuration Survivors And Remote Authentication

- Preserve VM95 and MCP95 processes on resume. VM95 completes successfully at
  38,176/42,569 measured library lines (89.68%) with 59 unmeasured sources.
  This predates the following tests; retain that snapshot boundary and the
  separate packaging report. MCP95 remains live on its earlier test snapshot.
- Configuration regressions now assert secure disclosure/auto-create defaults,
  primary auth identity precedence, absent sections, retained authenticator
  options, fixed-length lists, zero-valued supported limits and legacy
  protocol/type selection. The full five-file suite passes 413 cases.
  `router-config96-vm` retains 522/525 lines (99.43%). Its report deliberately
  fails whole-workspace scope checks rather than concealing missing files.
- `router-config96-mutations` completes 396/396: 349 kills, 10 survivors,
  37 compile errors, 97.2145% raw/adjusted, both baselines zero, verified input
  hashes. This improves 85.5153% without waivers. Remaining mutations affect
  intermediate collection growth, empty collection construction, the temporary
  OpenMetrics object's unused enabled flag, numeric fast paths and private
  nullable-map defaults. Keep each outcome visible. Add the complete-source
  target to CI at 95%, with a 45-minute job budget.
- Direct remote-authenticator tests complement the existing worker suite.
  Cover malformed success/challenge/failure responses, provider allowlists,
  deep immutable copies, correlated single-use proofs, abort failures,
  expiry/disabled expiry, static realm/identity throttling and delegate failover.
  `remote-auth96c-vm` measures 365/368 lines (99.18%) from 297/368 (80.71%).
  The private registry constructor and two defensive pending-delegate branches
  stay in the denominator. The final 93-case suite, formatting and analysis pass.
  Add a 98% file floor and full-source target `router-remote-authenticator-vm`;
  the manifest guard fails first, then all 47 runner tests pass (one optional skip).
- The first authenticator campaign completes 191 candidates: 102 assertion
  kills, 26 survivors, 63 compile errors, 79.6875% raw/adjusted, both baselines
  zero. Provider acceptance, fake-challenge identity, disabled expiry/throttling,
  bounded numeric options and overlapping failure backoff gain independent
  assertions. `remote-auth96b-mutations` completes the full rerun on final tests:
  124 kills, 4 survivors, 63 compile errors, 96.875% raw/adjusted, both baselines
  zero and source/test hashes verified. Add its complete-source 95% CI gate
  with a 45-minute job budget. No equivalence waivers. Remaining outcomes are
  private handle-list growth, pending-delegate cooldown and the two exact-time
  window comparisons; retain them for further lifecycle/clock-boundary work.
- Qwen/GLM advice was checked against source: the limiter intentionally shares
  state by realm/authId; no per-instance isolation change is justified. The
  pending proof is held by a Completer, not awaited before testing duplication.
  Tests inspect backoff without sleeping through it. Further investigate the
  static failure-map lifetime/capacity against worker-level security guards;
  high line coverage does not establish resistance to unique-identity floods.
- `dart --verbose --help` confirms `--root-certs-file` as a possible deterministic
  subprocess fixture for the earlier custom-CA/system-root policy survivor.
  This is a next-test lead, not evidence that trust-root isolation is verified.
- Correct the deployment auditor's stale inventory for five existing gates
  plus both new gates. A fail-first matrix consistency test also rejects
  duplicate targets. All 27 audit tests and Bash syntax checks pass. Unknown and
  missing jobs still fail strict auditing. The prior head's package/image/profile
  checks pass; hosted CI remains pending.
- Fast96 passes. Verify95b captured three corrected fixture-development errors;
  Verify96 captured stale audit fixtures while the CI gate was being updated.
  Verify96b passes on settled Dart/Rust inputs, including final regression
  cases, native/package smokes and 2,970 core plus two WebSocket WASM cases.
  The final authenticator gate is added only after the audit phase terminates;
  a separate full 27-case audit run also passes for the final workflow/fixture
  snapshot. Bash syntax, workflow YAML parsing, targeted Dart analysis and
  formatting checks pass. WASM tests remain distinct from unmeasured WASM lines.

### Work95 Configuration Validation Coverage

- Implementation is pushed as `64dfc805`; draft PR #93 is updated. Both package
  dry runs pass; CI/image/profile evidence remains pending. Strict audit finds
  five newer mutation gates absent from its hard-coded required-job inventory.
  A workflow-matrix regression fails first. Update that inventory and all audit
  fixtures, retaining strict unknown/missing-job rejection; all 27 audit tests
  and Bash syntax checks pass. This follow-up awaits Verify95b and a bundled
  implementation commit. Verify95b is the only native-runtime test user; VM95
  is now formatting after all runtime tests finished. Do not restart either.
  Feature-branch protection and default-branch workflow visibility findings
  remain explicit, and queued hosted checks do not satisfy the strict audit.
- The complete configuration campaign finishes 396/396 with 307 assertion kills,
  52 survivors and 37 compile errors: 85.5153% raw/adjusted. Both baselines exit
  zero; all source/test/support hashes match. Keep every outcome, no waivers.
  Next cover legacy transport selection, absent/default sections, disclosure
  defaults and retained authenticator options with independent assertions.
  High line coverage has not met the mutation target; do not gate this target as
  passing or reduce the threshold. MCP95 remains live on its earlier test snapshot.
- Add malformed-configuration tests through map, JSON and YAML entry points.
  Exact FormatException messages distinguish schema validation from decoding or
  fixture failures. Permission/authentication/provider/listener/header/metrics
  and rate-limit inputs cannot silently become defaults. Positive cases assert
  alias precedence, explicit disabling, immutable results, input preservation,
  legacy WebSocket/HTTP normalization and default RawSocket selection.
- All 385 focused configuration tests pass; the complete loader improves from
  429/525 (81.71%) to 522/525 (99.43%) in `router-config95b-vm`, with seven input
  hashes. The remaining private constructor and two unreachable private helper
  branches stay measured and unexcluded. Add a 98% file floor, not a claim that
  the complete router package meets the goal.
- A fail-first manifest guard protects `router-config-loader-vm`: the entire
  loader, five configuration test files and external quickstart YAML fixture.
  All 46 runner tests pass with one optional skip. The separate 396-candidate
  `router-config95-mutations` campaign starts with a clean baseline; no final
  mutation score or new CI gate for this target is claimed yet.
- Qwen review's possible YAML false-positive is contradicted by assertions on
  the exact configuration error, not just any FormatException. Header-key
  coercion would fail the explicit throw assertion, not falsely pass it.
  Assertions cover the named immutable maps, not unproven deep immutability.
- Fast95 and full Verify95 pass, including the final configuration tests, router
  CLI integration, native/package smokes, Rust and browser WASM checks. WASM
  line coverage remains unmeasured. Separate final formatting/analysis and the
  updated 46-case runner test suite pass. Start `vm-current95` with recorded
  inputs as the only native-runtime owner. The mutation campaigns are Dart-only.
  Prior head CI `35263839205` and package/image/profile dry runs pass. New package
  percentages remain pending collection, not extrapolated from focused reports.
- Early configuration survivors identify missing legacy transport selection and
  absent/default-section assertions. Inspect the complete inventory after the
  live campaign ends before batching survivor-directed tests and a final rerun;
  high line coverage is not evidence that mutation coverage meets the goal.

### Work94 Remote Delegate Wire Coverage

- Preserve the live VM93b/MCP92 processes; do not restart them. VM93b completes
  at 37,903/42,555 measured lines (89.07%), with 59 unmeasured library sources.
  This is pre-Work94 evidence. The previous head's package/image/profile checks
  pass; CI is pending. Fast94 finishes zero.
- Fifteen fail-first wire cases demonstrate explicit invalid status maps falling
  into legacy challenge/success parsing. Guard legacy fallback with absence of
  the `status` key; valid modern and status-less legacy replies remain supported.
  Extend the negative cases across challenge/camel/snake result shapes.
- All 145 focused tests pass: six transport/serializer combinations, concurrent
  request correlation, timeout/rejection recovery, proof/abort payloads, detailed
  WAMP errors, credential/key parsing and rotation, registry warmup, TLS options
  and malformed configuration. `remote-delegate94d-vm` measures the complete
  source at 568/571 (99.47%) with input hashes. No exclusions; missing whole-
  workspace scope still fails the focused canonical check. Add a 98% file floor.
- A fail-first manifest regression protects the entire source, both test files,
  three TLS fixtures and core cryptosign fixture input. The 45 tooling cases
  pass with one optional fixture skip. The initial 286-candidate campaign scores
  87.70% (164 kills / 23 survivors / 99 compile errors). TLS flag, cache identity,
  alias precedence and failed-warmup recovery assertions lift the separate final
  `remote-delegate94b-mutations` to 179 / 8 / 99, or 95.7219% raw/adjusted.
  Original/restored baselines exit zero and all input hashes match. Add its
  complete-source 95% CI gate. No waivers or outcomes counted as assertion kills
  other than actual test assertion failures.
- Investigate surviving security-sensitive guards: custom-CA contexts must not
  gain system trust roots, but local certificate fixtures alone do not observe
  that root-store distinction. Retain this explicit test gap. The file-path
  cache mutant changes absent/null metadata rather than resolved credentials;
  connection-future identity, anonymous/factory collection guards and resource
  lifetime survivors remain visible for further tests, not equivalent waivers.
- Full Verify94 fails a real router CLI login: generated base64url tokens can
  start with `--`, which the parser rejects as a missing value. Four deterministic
  credential cases fail before the fix. Preserve known-option missing-value
  errors, accept opaque credentials, add `--option=value` with embedded equals,
  and reject duplicate/valued flags. The 69 real-router CLI cases pass after
  that parser fix. Work95's GLM review identifies a genuine assignment-form
  lookahead ambiguity; 16 fail-first cases reproduce it before checking the
  next token's option prefix. All 393 final CLI tests pass. Credential values
  followed by realm/auth-id/tool options and assignment syntax in CLI help
  protect the public consumer path.
  Fast95 and Verify95 pass; final workspace coverage owns the native runtime.
- MCP92 completes at 798 kills / 38 survivors / 262 compile errors: 95.4545%
  raw/adjusted, original/restored baselines zero and matching input hashes.
  Retain individual outcomes with no waivers. Inspect the pending-revocation
  survivors: revoked subscriptions are rejected before handle publication,
  reconciliation drains pending buffers and release futures deduplicate cleanup.
  These guards merit further resource/lifecycle assertions; do not call them
  equivalent or claim whole-package coverage. Add the complete library 95% CI
  gate; CLI and other runtime/component obligations remain open.
- MCP92's test inventory predates the CLI regression additions. Keep its score
  historical, not final evidence for the new snapshot. Start the separate
  `mcp95-library-mutations` only after the earlier campaign is terminal; its
  baseline passes and it remains in progress. The subsequent assignment-form
  lookahead regressions also postdate this campaign's test snapshot. Retain
  it as historical evidence and rerun final inputs only after it is terminal;
  do not duplicate the live run or attribute its score to later tests.
- Qwen review's status-null compatibility suggestion contradicts the documented
  explicit-status contract. Its abort-session concern contradicts `_ensureSession`
  and the passing two-connection regression. WebSocket cleanup is awaited; the
  mutation runner does not use line-coverage policy to exclude candidates.
  No production behavior is changed for those hypothetical findings.

### Work93 Remote Auth Benchmark And Binding Gates

- Revalidate the pending work and live processes after the status-only table.
  Fast93 and VM92 finish zero. The VM92 main report is 37,779/42,555 (88.78%),
  with 59 unmeasured library sources; packaging is 765/787 (97.20%), with 12
  unmeasured sources. These are pre-Work93 measurements.
- Five fail-first cases in `/tmp/connectanum-coverage93-remote-red.log` show
  malformed RPC/transport keys and transport types throwing casts. Validate
  string keys and compare the transport type without a cast. Preserve the
  parser's skip-invalid-candidate semantics and prove a later valid service
  remains discoverable. All 32 configuration tests pass.
- Add real native TLS ticket RPC coverage for both configured realms,
  authentication failure, invalid shared token, service permission boundaries,
  nested fixture credential files, listener release and restart. The 33-test
  focused run passes and `remote-auth93-vm` measures 137/138 lines (99.28%)
  in the harness versus the prior 36/138 (26.09%). Add a 98% file floor. The
  focused canonical check correctly fails missing workspace scope; this is not
  a whole-package score. The only uncovered harness line throws on missing
  certificate fixtures. Strengthen restart with explicit stale-transaction
  rejection and collect new final-snapshot evidence after verification.
- Inventory the entire harness in `bench-remote-auth-native`, including its
  unit/integration tests and all five certificate inputs. Guard the manifest
  with a fail-first tooling test; all 44 mutation tooling tests pass (one
  optional fixture skipped). Serialize its future native campaign with the
  repository verification and coverage jobs.
- Client binding92 finishes 492/492: 380 assertion kills, 18 survivors and 94
  compile errors, both baselines zero, no timeouts/errors/equivalents; raw and
  adjusted scores are 95.4774%. Source/test/support hashes still match. Protect
  this complete source target in CI, keeping the default 95% threshold and
  allowing sufficient job time. It does not represent the whole client.
- Router binding91 finishes 666/666: 483 kills, 36 survivors, 147 compile
  errors, both baselines zero; 93.06% raw/adjusted. Add 39 JSON/MessagePack/CBOR
  cases for absent trailing fields, heartbeat field boundaries, empty unknown
  messages, authoritative ABORT metadata and absent versus empty AUTHENTICATE
  extra. All 1,710 binding tests pass; analysis is clean. Start the distinct
  `router-binding93-mutations` campaign against the final tests, preserving
  MCP92. Full `bin/verify` remains the sole native-runtime user.
- Qwen's stale-state concern leads to the explicit restart-transaction check.
  Its ABORT precedence proposal contradicts the inspected implementation;
  retain the independent metadata override assertions. Do not weaken tests or
  count hypothetical future refactors/fixture paths as defects.
- Full `bin/verify` finishes zero, exercising the final tests, native/Rust,
  installed-package/router/MCP smokes, 2,970 core WASM tests and two browser
  WebSocket tests. WASM line coverage is still unmeasured. The final 33-test
  focused run passes wrong service-ticket rejection, stale transaction rejection
  and fresh authentication after restart. `remote-auth93b-vm` measures 137/138
  (99.28%), with matching source/test/certificate hashes; its canonical checker
  deliberately reports missing whole-workspace scope rather than a false pass.
  Fresh `vm-current93` collects with a complete input hash inventory as the only
  native-runtime owner. Keep the new benchmark native mutation campaign deferred
  until this collection releases the slot; do not duplicate either live campaign.
- Push `add1cda2` and update PR #93. Both package dry runs and the image dry run
  pass; profile/CI remain pending. The strict audit selects the correct head,
  fails pending logs/jobs and retains the known unprotected feature branch and
  default-branch mutation-workflow visibility findings.
- VM93's native collection completes before starting the new native campaign.
  Its main report is 37,886/42,555 (89.03%): bench 89.17%, client 88.46%, with
  59 unmeasured library sources. Packaging formatting continues. This report
  predates the survivor assertions below; preserve that historical boundary.
- `remote-auth93-mutations` completes all 35 candidates with both baselines
  zero: 16 kills, three survivors and 16 compile errors (84.21% raw/adjusted).
  Investigate every survivor: the missing cases are supplied logger routing,
  fake challenge on identity denial and recursive creation with multiple absent
  parent directories. Add behavioral assertions for those contracts, including
  failure without an auth role after the fake challenge; do not change production.
- All 33 focused tests pass. `remote-auth93c-vm` remains 137/138 (99.28%) with
  final input hashes. `remote-auth93b-mutations` completes 35/35: 19 assertion
  kills, 16 compile-invalid outcomes, zero survivors/errors/timeouts/equivalents,
  100% raw/adjusted, original/restored baselines zero and unchanged native artifact.
  All source/test/certificate hashes match. Add this complete source target to
  the CI mutation matrix with conditional Rust setup and native-library build,
  preserving the default 95% gate. No full-bench mutation claim is implied.
- Qwen's follow-up review finds no concrete defect. Run full `bin/verify` again
  for the final assertions/config before committing; it is the only native user.
  Keep router93/MCP92 live without restarting them.
- Router binding93 completes 666/666: 501 kills, 18 survivors, 147 compile
  errors; 96.5318% raw/adjusted, both baselines zero, no timeouts/errors or
  equivalence waivers, and matching source/test/support hashes. Add its full
  source target to the 95% CI matrix with the same 90-minute job allowance as
  client binding. The YAML parses with all three new targets present. Remaining
  survivors are retained, not suppressed. VM93 also finishes packaging and exits
  zero: 765/787 (97.20%) and 12 unmeasured packaging sources. This is still the
  pre-survivor-assertion test snapshot; retain MCP92 as the only live mutation run.
- The second full `bin/verify` finishes zero on the final assertions/config:
  722 benchmark cases, native/Rust and installed-package smokes, 2,970 core WASM
  cases and two browser WebSocket cases pass. No WASM line-coverage claim is
  implied. Start `vm-current93b` with the final input inventory as the only native
  runtime user, leaving MCP92 untouched. Commit the test/CI follow-up together
  with these material evidence updates, without publishing or changing versions.

### Work92 MCP Handshake And Pending Cleanup

- The preceding short table was status only. Revalidate current processes:
  preserve binding91, let VM91 finish and use the already-running fast gate.
  VM91 completes at 37,776/42,553 (88.77%) with 59 unmeasured library sources;
  client is 88.40%, router 85.68%, core 94.22%, MCP 95.91%, auth-server 100%,
  bench 84.69%. Packaging remains 97.26% client / 97.14% router, with 12
  unmeasured sources. Do not attribute this snapshot to Work92's newer code.
- Twelve fail-first tests show tool handlers execute when an initialized
  notification follows no initialize request, an initialize notification or a
  failed initialize request, both individually and inside batches. The
  [MCP session lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
  requires an initialize request/response before the client's initialized
  notification. Record successful response construction in a private boolean;
  keep the public enum unchanged and require created state as well. Early
  acknowledgements must not carry over to a later successful initialization.
  Router stateless/direct JSON routing is separate and remains unchanged.
  This finding establishes a protocol gate bypass, not an auth bypass.
- Correct one test fixture that previously sent only initialized before testing
  operation parameter validation. Add unrelated-notification, closed-state,
  notification-only batch, duplicate-invalid-ID isolation and explicit malformed
  message error assertions. Pending pub/sub tests use controlled Completers to
  prove concurrent revocations share one release, failed release remains retryable,
  successful cleanup removes pending work even after callbacks are withdrawn,
  and failed subscribe leaves no acquired subscription or stale cleanup entry.
- All 689 MCP tests pass (28 new cases). Package analysis reports only four
  pre-existing informational suggestions. `mcp92-vm` measures all 13 library
  component sources at 1,601/1,617 (99.01%) with source/test input hashes. Its
  canonical policy correctly fails incomplete workspace/native CLI scope;
  do not use its package percentage as an integration coverage result.
  `mcp92-library-mutations` starts 1,098 candidates with a passing baseline,
  retaining complete source/test/support inventories. MCP89's 94.36% becomes
  historical after this source/test change. Binding91 stays live and unchanged.
- `bin/test-fast` and full `bin/verify` finish zero. The verify log includes the
  final client closing-boundary cases, all 689 MCP tests, Rust, installed-package/
  native router/MCP smoke, 2,970 core WASM tests and two browser WebSocket tests.
  WASM line coverage remains unmeasured. Fresh `vm-current92` now collects as
  the sole native-runtime owner. Focused MCP coverage and both fresh mutation
  inventories have matching source/test/support hashes. Hosted package/image/
  profile checks on pushed `3192d18d` pass;
  current-head CI remains pending, with no known new red job. No merge,
  publication, version change, lowered floor or equivalence waiver.

- The client binding91 target completes at 378 assertion kills / 20 survivors /
  94 compile errors, with both baselines zero and no errors/timeouts/waivers.
  Its raw/adjusted 94.9749% is still below 95%. Three new per-serializer closing
  frame regressions cover details present but reason absent, preserving text,
  ABORT extensions and the existing empty default. All 1,621 client binding
  tests pass and analysis is clean. Start `client-binding92-mutations` only
  after confirming the earlier client target is terminal; leave the router
  half of binding91 running. The old client result is now historical.
- Local test advice was checked against public APIs. Qwen's lifecycle review
  suggested cross-thread locks and throwing for ignored duplicate/closed
  notifications; neither follows from this isolate-local synchronous transition
  or the JSON-RPC notification contract. GLM's cleanup review found no concrete
  defect: both failure expectations attach before completing the shared error,
  and the held release future makes concurrent cleanup deterministic. Some
  narrower Qwen review attempts reached their output limits and are incomplete;
  do not count them as completed reviews. Final client tests were also inspected
  directly against the existing two length guards and closing-message models.
- Push `7c64f901` and update PR #93. New-head push package dry-run
  `35258344706` passes. PR package check `35258355527`, CI
  `35258344621`/`35258355550`, image dry-run `35258371694` and profile run
  `35258373290` remain pending; the CI watcher is live. Strict audit exits one
  for pending evidence and the known unprotected feature branch/default-branch
  mutation-workflow visibility findings. All selected run heads match. No
  assertion of a clean hosted chain; leave post-push bookkeeping uncommitted
  for the next implementation increment and preserve current evidence collectors.

### Work91 Native Metadata And Fragment Boundaries

- Resume pending tests after the status-only table response. Inspect current
  processes and reports rather than restarting the fast gate, VM90 or either
  mutation campaign. VM90 is terminal with 37,704/42,553 measured VM lines
  (88.60%); client is 88.00%, router 85.50%, core 94.22%, MCP 95.91%, auth-server
  100% and bench 84.69%. Keep 59 missing library sources and 12 missing packaging
  sources visible. Do not attribute these scores to Work91's newer tests.
- Add 645 contract cases, with 3,289 focused tests passing. Cover all 14 lazy
  session message types, independent IDs, payloads and ownership anchors;
  unsupported codes and absent metadata flags must fall back, while explicit
  invalid wrappers fail materialization. Direct-only flags cannot authorize
  metadata binding. HELLO/WELCOME auth slots, including empty strings, override
  decoded fields only under the direct flag; missing slots use the lazy map.
  Separate numeric presence and boolean bits, including zero values, and test
  non-direct options and custom-field separation rather than only direct paths.
  Single non-null PPT/policy slots must preserve an options object, while wholly
  absent options without detail bytes stay null; this targets short-circuit
  mutation survivors hidden by tests that populate every field together.
- Cover nullable closing messages, missing/null detail maps, malformed fragments,
  ABORT fragment overlays preserving the unselected frame field, recursive JSON
  binary markers and unsupported payload serializers. Assert the empty-frame
  error message so a downstream RangeError cannot masquerade as the intended
  shape rejection. Shared handshake contracts now assert authmethods, topic,
  procedure, authextra and extension separation. No production behavior edits.
  Initial property-name/type-inference errors and the mistaken null expectation
  for YieldOptions.progress are test-authoring errors, not production bugs.
- Final focused `binding91g-vm` records 584/584 client binding and 575/575 router
  binding lines, both 100%. Source/test/support/policy hashes accompany it. Add
  98% floors for these complete files without altering other targets or scope.
  Its canonical checker intentionally exits one for incomplete workspace scope;
  never present its two-file totals as package or native-runtime coverage.
- The old mutation campaign finishes: client 304 assertion kills, 94 survivors
  and 94 compile errors, 76.38% raw/adjusted; router 334 kills, 183 survivors and
  147 compile errors, 64.60% raw/adjusted. Both original/restored baselines pass,
  with no errors/timeouts or equivalents. These snapshots predate Work91 tests/
  support; router also predates the final Work90 shorthand correction. After
  confirming termination, start fresh `binding91-mutations` for both targets.
  Keep MCP89 running with its unchanged snapshot. No new equivalence waivers.
- Local companion test advice was checked against source. Reject the earlier
  suggestion that non-direct identity fields should stay null: lazy Details uses
  map fallback. Review's default-value and nullable-map concerns are not defects;
  YieldOptions.progress is deliberately non-null false, and explicit closing/map
  tests already cover absence. The focused auth/flag review found no concrete
  defects. Slot-review speculation is resolved by the explicit production
  mapping of Register stringC to invoke. Full `bin/verify` finishes zero and its
  log includes the final auth/feature/PPT assertions. Rust, installed-package/
  native smoke checks, 2,970 core WASM tests and two browser WebSocket tests pass.
  WASM line instrumentation remains missing. Workspace analysis has five
  informational suggestions, no errors/warnings; final changed-test analysis
  retains only the existing fixture suggestion. `vm-current91` now collects as
  the sole native-runtime owner. Commit/push and new-head hosted checks remain
  pending. No merge, publication, version change or weakened threshold.
- Post-push evidence: `3192d18d` is on the coverage branch and PR #93 is updated.
  New-head package dry runs pass; CI, image and WAMP profile checks are queued/
  running. The strict audit retains pending evidence plus known feature-branch
  protection/default-branch workflow visibility findings, not a green chain.
  MCP89 now finishes at 94.36% raw/adjusted: 786 assertion kills, 47 survivors,
  262 compile errors, both baselines zero, no errors/timeouts or equivalents.
  All source/test/support hashes still match. This is the complete library
  target, not the CLI. Investigate JSON-RPC request validation/lifecycle and
  pub/sub cancellation/release/revocation survivors first. Do not restart the
  live fresh binding91 campaign or native VM91 collector. Keep these post-push
  notes uncommitted until the next implementation increment.

### Work90 Native Feature And Abort Contracts

- Classify the previous short coverage-table turn as status only. Revalidate the
  clean worktree, native VM89 collector and MCP89 campaign; preserve both.
  VM89 completes with auth-server 455/455, core 6,823/7,243, client 8,126/9,355,
  MCP 3,752/3,912, router 16,318/19,287 and bench 1,909/2,254. Keep its 59 missing
  library sources visible. Packaging is unchanged at client 391/402 and router
  374/385, with 12 unmeasured sources. This is pre-Work90 evidence, not a score
  for subsequently changed code/tests.
- Start `bin/test-fast` before substantive edits, after VM89 has released native
  use and is formatting reports only; it finishes zero. Use shared independent
  wire/property oracles for every public role feature, omitted/null/false/true
  values, role isolation, dealer reflection, broker trust-level alias precedence
  and independent message state. Run both full-frame and metadata HELLO/WELCOME
  decoders across JSON, MessagePack and CBOR; unsupported inbound serializer IDs
  must fail explicitly. Initial enum spelling/exhaustiveness errors are test
  authoring errors, not production reproductions.
- Eighteen valid full-frame cases fail with false instead of the announced true
  progressive invocation capability; the 18 corresponding metadata cases pass.
  Add the missing assignments in both native caller/callee/dealer mappers.
- Expanded request-frame tests expose ABORT with an empty details dictionary
  throwing. A separate 201-case abort run has 135 failures before the fix,
  including lost full-frame/custom/fragment payload fields. The
  [WAMP ABORT contract](https://wamp-proto.org/wamp_latest_ietf.html#section-4.1.3)
  permits optional closing information and optional positional/keyword payloads.
  Preserve details and payloads without changing the wire schema. Abort is not
  an AbstractMessageWithPayload and its fields are final, so fragment overlays
  construct an immutable Abort rather than relying on generic lazy payload setup.
  Missing message text is valid; non-text message values still reject.
- Additional regressions assert request/entity IDs, ACK versus revocation,
  cancellation modes, registration policy/disclosure/timeout options, progressive
  results, passthrough metadata, custom-field separation and lazy ERROR payloads.
  Review reproduces a patch regression in three cases: preserving full-frame
  router details must not reject its existing text shorthand. Keep the shorthand
  while preserving dictionary details. All 2,644 focused tests pass.
  `binding90e-vm` measures client message binding
  545/584 (93.32%) and router message binding 515/575 (89.57%). Keep its failing
  canonical partial-scope report and input hashes; these are not package totals.
- Add full-source client/router message-binding mutation targets, explicitly
  inventorying the shared test oracle. A fail-first manifest check guards both
  targets. All 43 mutation tooling checks pass, with one optional native fixture
  skipped. `binding90-mutations` has a passing client baseline and 492 generated
  candidates; router follows serially. The router snapshot predates the final
  shorthand fix and must be rerun after this campaign terminates; it is not
  final-source evidence. The client source/test/support hashes still match.
  Keep the existing MCP89 campaign running.
  Neither partial campaign is a final mutation score. Early fragment-fallback
  survivors remain to investigate after the complete inventory finishes, notably
  kwargs-only fragments and preserving the other full-frame payload field when
  one fragment overrides it. Also distinguish the intended empty-frame
  ArgumentError from a downstream RangeError, which the broad matcher accepts;
  do not waive that survivor without examining the public error contract.
- Qwen advice is advisory: reject its proposed expectation that an explicitly
  announced progressive feature should remain false. Missing feature dictionaries
  yield null, not default feature objects. Review's alleged null-cast and omitted
  metadata-details regressions are disproved by source and tests: String? accepts
  null, malformed scalars already rejected, details are explicitly passed, and
  the client optional decoder delegates to the same non-null fragment semantics.
- Full `bin/verify` finishes zero, including Rust, installed-package/native
  router/MCP smoke checks, 2,970 core WASM tests and two browser WebSocket tests.
  Its router suite includes the final shorthand compatibility regression, and
  final changed-file formatting is clean. Workspace analysis exits zero with
  five informational null-aware-element suggestions, four pre-existing; no
  errors or warnings. WASM line coverage remains unmeasured. Fresh `vm-current90`
  coverage is running as the sole native-runtime owner. New-head push and hosted
  checks remain pending. Work89 package/image/
  profile checks pass while both CI runs continue. No master merge, publication,
  version change or equivalent waiver. The overall coverage goal is not complete.

### Work89 Public MCP Contracts And Mutation Follow-Up

- Revalidated the unfinished catalog test file and the live Work88 mutation
  process rather than restarting it. The short user-requested coverage table
  was a status-only turn. The existing Work89 `bin/test-fast` finishes zero.
  Correct test construction against the actual public record/FutureOr APIs;
  initial compile errors and mistaken ordering/default expectations were test
  authoring errors, not production bugs. No production behavior changes.
- Add 156 regressions across four new contract suites and the existing session
  bridge suite. Exact schemas and safety hints are observed through initialized
  MCP `tools/list`; individual metadata fields, including false/empty values,
  remain distinct from omission. Session selection is independent and discovery
  issues no WAMP call, subscribe or publish. Per-procedure mapping/deadlines
  override shared defaults; pending providers are released in finally so a
  missing deadline fails an assertion rather than a runner timeout.
- All four registry types test closed cursor boundaries, malformed namespace,
  shape and offset, immutable page snapshots and terminal next-cursor absence.
  Resource checks cover zero size, isolated annotations and unrelated template
  rejection without handler invocation. Capability and continuation tests retain
  explicit server configuration, individual annotation hints, absent versus empty
  result fields, recursive JSON normalization, and fail-closed form capability,
  result-type and continuation-state validation. Pub/sub covers exact byte/count
  capacity, overflow, cleanup and independent publish/subscribe permissions.
- All 661 MCP tests and package analysis pass. `mcp89-vm` measures all 13 MCP
  library component sources at 1,598/1,615 (98.95%). Native CLI integration is
  absent from this focused collection; retain its failing canonical report and
  do not substitute its partial package percentage for the full VM result.
- Work88's `mcp88-library-mutations` finishes all 1,095 candidates: 664 kills,
  169 survivors, 262 compile errors, 79.71% raw/adjusted, both baselines zero,
  no errors/timeouts/equivalents. It is historical after the new tests. The
  fresh complete-source `mcp89-library-mutations` campaign includes all 20
  current test files and has a passing baseline; do not report its partial
  counts as a completed score or start a duplicate campaign.
- Qwen review prompted explicit next-cursor assertions. Reject unsupported
  claims that an exception skips finally or that `toTools().single` constructs
  a server: the timeout fixture invokes a tool directly and releases its
  pending provider. Keep exact scalar conversion expectations rather than
  weakening them to type-only checks. Cursor fixture encoding was checked
  against the actual generated format before constructing malformed inputs.
- Full `bin/verify` passes, including Rust, installed-package/native router
  smoke tests, 2,970 core WASM tests and two browser WebSocket tests. WASM line
  coverage remains unmeasured. Fresh `vm-current89` workspace collection is
  running as the sole native-runtime user; do not start another native suite
  until it terminates. VM88 remains the last complete workspace measurement.
  Pushed Work88
  package, image and profile checks pass, with both CI runs still running.
  Commit/push, fresh whole-workspace coverage and new-head hosted evidence remain
  pending. The whole multi-runtime/package/application goal remains active.

### Work88 MCP Lifecycle Oracles And Key-File Boundaries

- Resume with the existing native87 process confirmed live, not merely a lock.
  Preserve it as the sole native-runtime owner and do not restart it. All eight
  recorded source/test/support hashes still match. The previous work made
  implementation and verification progress; the short user-requested coverage
  table was status only. Work88 adds new executable tests and fail-first fixes.
- Twenty HTTP CLI cases cover refresh credential rotation, exact authorization
  and trace headers, token-type-specific revocation, absent/blank refresh grants,
  exact 401 rejection semantics, intermediate endpoint failures, no subsequent
  side effects, and no success/credential output on failure. Two WAMP API tests
  retain registered tool objects while withdrawing/rebinding callbacks: failed
  reconciliation must preserve ownership for retry, and later cleanup releases
  once via either the rebound callback or explicit override. All 505 MCP tests
  and package analysis pass. No production MCP behavior was changed.
- `out/regression-coverage-2026-09-15/mcp88-final-vm` measures the complete MCP
  library at 1,592/1,615 (98.58%), WAMP API 620/630 (98.41%). Enforce a 98% WAMP
  API file floor. Its CLI measurement is only 890/2,297: this focused run does
  not include native integration and is deliberately not substituted for full
  workspace coverage or merged with older CLI evidence. The canonical policy
  correctly exits nonzero for missing scopes in this partial report.
- Add the complete `mcp-library` mutation target, retaining the existing `mcp`,
  `mcp-cli` and `mcp-cli-native` scopes. A fail-first inventory test proves all
  library implementation files agree with the measured component and that the
  whole-package/native CLI scopes remain intact. Its 1,095-candidate campaign
  is active in `mcp88-library-mutations`, with a passing clean baseline.
- A fresh pure core baseline passes 3,072 tests without using the occupied
  native FFI runtime. Five new failing cases prove that a repeated header check
  accepts three incorrect OpenSSH footers and that an unchecked inner ASN.1
  parse rejects existing legacy raw 32/64-byte PKCS8 representations. Validate
  the footer after CR/LF normalization. Catch inner parse failures only for
  already-supported raw lengths; retain outer structure/version/OID checks and
  successfully parsed nested-seed precedence. These are key-file fixes, not
  changes to WAMP wire behavior, algorithms or SCRAM derivation.
- Fifty-one new key tests cover invalid writer lengths, missing PEM markers,
  short outer sequences, versions/OIDs, missing algorithms, nested/raw sizes,
  raw byte prefixes, ownership isolation, encrypted-password requirements and
  valid newline variants. All 59 focused existing/new cases pass independently
  on VM, JavaScript and WASM. Full core VM passes 3,123 tests. The focused
  `keys88-final-vm` / `keys88-final-js` reports measure PKCS8 at 61/63 VM and
  56/56 JS, PEM at 77/85 VM and 67/73 JS. They are not whole-core reports;
  their canonical policy failures retain missing scopes. WASM is test evidence
  only, not line instrumentation. No coverage exclusions were added.
- A fail-first launcher test adds key boundary and existing cryptosign vectors
  to both canonical browser commands. `browser88` passes 2,970 JavaScript tests
  and measures core 6,623/6,973 (94.98%), with 173 unmeasured library sources
  still visible. Fifty launcher checks, 41 mutation-runner checks (one optional
  native fixture skipped), 16 coverage-checker checks, workspace analysis,
  formatting, shell syntax and public-artifact-reference validation pass.
- `core-pem-pkcs8-vm` and `core-pem-pkcs8-web` retain complete source inventories,
  the same behavioral suites, and `keys.dart` fixture hashes. The VM half of
  `keys88-mutations` completes all 100 candidates: 77 kills, 17 survivors and
  six compile errors, 81.91% raw/adjusted, both baselines zero. No crashes,
  timeouts or equivalence waivers. Browser work is still running. This is not
  a passing 95% gate or whole-core mutation score.
- Initial survivor triage, not waivers: PEM source SHA-256
  `bedf8eeb2232a5fd71ebd75faa229c5ba0d20f3470f25cce2c9b2c45c48013cf`
  retains unchecked test gaps for magic (`a5e934ebeb80937ea8a5`), key count
  (`a27071569effbb67e9cc`), KDF selection (`ecfa469f9236571a6a84`), key type
  (`08b134214c19ca9fba9a`), and CBC selection/decryption
  (`e8f7e664af2b2957d7d1`, `dba002ad3529615892c1`, `9880fcd4981ccf506019`,
  `864fa50c714d2c69e6f3`, `df6ec1b2f18bfa90fc09`). CTR direction mutant
  `e16f0ec1d91b3fb31ca6` needs separate cipher-semantics review, not a blanket
  waiver. PKCS8 SHA-256
  `b6e4af02f6b9397dfe9c65ed40cca765320cb3859093435a26b3975b6a7871b3`
  has six fixed-size PEM line-wrap survivors (`03e7cb535020ebe724ef`,
  `755837de2fcc0c9f37a8`, `a76f9526176f467f61dc`, `cbd93bcb29a9f0a1084c`,
  `aa84cab9ebb7581c989b`, `21708c630192b37e0270`) and inner-parse guard survivor
  `5f333271cf0dcfbb657d`; the latter still fails closed at the later length
  check, so existing broad throws matchers do not distinguish error provenance.
  Investigate individually after the shared VM/JS snapshot finishes.
- Local Qwen/GLM reviews were checked against source and tests. Rebinding is
  intentional, idempotent release is directly asserted, and exact diagnostics
  must not be weakened on speculative advice. PKCS8 outer OCTET STRING remains
  required; do not broaden that boundary. A truncated test-ideas response is
  not accepted review evidence. Gemma's native-survivor grouping is advisory
  only, not an equivalence or completed-score claim.
- Published `417b2ca1` push CI `35233785010` and PR CI `35233789407` both pass.
  Both package dry runs, image dry run and profile benchmarks pass. The fresh
  completed-head strict audit retains only the known unprotected feature branch
  and mutation workflow absent from default-branch discovery findings. Neither
  is bypassed. The preceding audit's pending-PR findings are superseded.
  These hosted results cover Work87, not the uncommitted Work88 changes.
  Final fast/full verification, full VM coverage, implementation commit/push,
  PR update and new-head hosted checks remain queued behind native87. Do not
  edit an executing Bash launcher. No merge, publication or version change.

Work88 follow-up after the initial key campaign completed:

- Both VM and JS finish the original 100-candidate snapshot with 77 kills,
  17 survivors and six compile errors, 81.91% raw/adjusted, both baselines zero.
  No errors/timeouts or waivers. Preserve that report as the earlier snapshot.
- Add eight cases using the existing public Ed25519 fixture independently
  re-encrypted by OpenSSH with AES-256-CBC and the literal `test-only` password.
  Assert the known seed, then reject altered binary magic/key count/key type
  and unsupported cipher/KDF labels without accepting the still-decryptable
  ciphertext. Preserve truncated/unsupported inner DER error provenance outside
  the legacy raw lengths. An initial test expectation incorrectly called all
  malformed lengths unsupported tags; the all-0xff DER length prefix instead
  throws RangeError. Correct the fixture oracle, not production behavior, and
  add a distinct unsupported-tag case with a valid zero length byte.
- All 67 focused cases pass on VM and JS. The new `keys88c-vm` / `keys88c-js`
  reports measure PEM 85/85 VM and 72/73 JS, PKCS8 61/63 VM and 56/56 JS. Add
  98% floors for PEM on both runtimes and PKCS8 on JS. The full rerun at
  `keys88c-mutations` is active, with no copied outcomes or equivalence waivers.
  The earlier 59-case WASM/browser-wide evidence is historical until rerun.
- Native87 completes all 613 candidates: 214 kills, 259 survivors, 107 compile
  errors, 14 errors and 19 timeouts, 42.29% raw/adjusted. Original/restored
  baselines are both zero, the native artifact is unchanged, and all eight
  recorded input hashes match. Crashes/timeouts remain non-kills. Native
  ownership is released; fresh `bin/test-fast` passes. Full VM88 collection is
  now the sole native owner; `bin/verify` follows serially.
- `keys88c-mutations` finishes both runtimes at 87 kills, seven survivors and
  six compile errors (92.55% raw/adjusted), both baselines zero, no errors or
  timeouts. The eight follow-up cases kill all ten actionable old survivors.
  Add seven individual source-hash-pinned equivalence records per runtime.
  The fixed 32-byte seed writer produces 46 ASN.1 content bytes plus its two-byte
  outer SEQUENCE header: 48 DER bytes, exactly 64 base64 characters, one loop
  iteration. Six line-wrap mutants therefore select identical bounds or change
  an unreachable branch. Independently decoding the existing fixture confirms
  48 bytes; GLM's contrary 46-byte arithmetic omitted the outer header and is
  rejected. PointyCastle 4.0.0 SIC initialization ignores the CTR direction flag
  and always initializes AES for encryption; the CBC direction is not waived.
  Fresh `keys88d-mutations` validates the equivalence configuration; older raw
  and adjusted reports remain unchanged.
- Canonical `browser88c` passes 2,978 JavaScript tests and measures core
  6,628/6,973 (95.05%); 173 unmeasured sources remain visible. This is measured
  JS evidence, not WASM line coverage.
- A fail-first manifest test catches omission of the existing native library
  loader tests from the full-runtime mutation target. Include that suite and
  require every direct runtime-importing regression while preserving isolated
  test processes and native-library requirements. All 42 mutation tooling tests
  pass, with one optional native fixture skipped. This expands the next native
  campaign's oracles; it does not revise the completed native87 score.
- Add both key-file mutation targets to CI with Chrome setup and the unchanged
  95% gate. The browser target shares the existing 90-minute long-browser job
  budget because its local campaign already approaches 20 minutes; individual
  mutation deadlines/classification remain unchanged. Extend deployment-audit
  required jobs and fake hosted fixtures. A
  fail-first launcher check protects target selection/artifacts; 51 launcher
  tests pass. Local companion reviews are advisory: target manifests and browser
  launchers already include the new tests, artifact names are matrix-specific,
  and speculative findings about unseen symlink code are not adopted.
- Full VM88 collection passes: core 6,823/7,243 (94.20%), MCP 3,746/3,912
  (95.76%), including CLI 2,154/2,297 (93.77%). Auth-server 100%, client
  86.80%, router 84.67% and bench 84.69% are unchanged. All 59 unmeasured
  library files remain visible. Separate packaging remains client 97.26% and
  router 97.14%, with 12 unmeasured files. This is not whole-goal completion.
  All 26 deployment-audit regression tests pass. Serial final `bin/verify` is
  running after coverage has exited, with no overlapping native runtime users.
- Fresh `keys88d-mutations` completes both full 100-candidate inventories with
  exit zero: 87 kills, seven individually justified equivalents, six compile
  errors, 92.55% raw / 100% adjusted. Both original/restored baselines pass,
  no errors/timeouts occur, and all source/test/support hashes match. This is
  the new equivalence-configured snapshot, not a rewritten older report or a
  whole-core mutation score.
- Final serial `bin/verify` passes, including Rust, installed-package MCP/router
  smoke checks, all 3,131 core VM tests, 2,970 core WASM tests and two browser
  WebSocket cases. WASM remains uninstrumented for line coverage. Native runtime
  ownership is released. All key-campaign input hashes match the final tests;
  the MCP campaign continues with matching source/test hashes and must not be
  duplicated. The implementation bundle is ready for coverage-branch commit/push
  and new-head hosted evidence; no merge, publication or version changes.
  Full VM collection and `bin/verify` follow serially before commit/push.

### Work87 Native Client Boundaries And Auth Gate Repair

- Pushed work86 as `a7562b23`, updated PR #93, and dispatched exact-head image
  and profile dry runs. Package checks `35228604211`/`35228608689`, image
  `35228708346` and profile benchmarks `35228710567` pass. Push CI
  `35228603988` exposes an auth-server mutation gate failure; the PR CI and
  remaining jobs are still running. This red gate is not waived.
- Native UTF-8 key tests reproduce 16 failures before changing production:
  multibyte IDs are rejected or truncated, same-prefix IDs alias a different
  key, and encrypted file sends fail key lookup. Correct four byte-length
  arguments in the native client runtime. The wire format, ciphers and public
  signatures are unchanged. A pure Dart provider is the independent crypto
  oracle rather than relying on a native self-roundtrip that could hide aliasing.
- The 39-case real RawSocket suite covers exact WAMP framing for JSON,
  MessagePack and CBOR, binary/base64 length boundaries, offset slices, native
  owned segments, rejected file/range/key/cipher inputs, both file-encryption
  ciphers, and received direct/wrapped E2EE payloads. Cached plaintext has
  independent ownership from its consumed message; altered cache parameters
  and reads after external ownership release fail closed. Tests assert exact
  content and recovery, not only successful calls.
- Initial fixture expectations incorrectly used wire nibble 15 rather than
  negotiated bit exponent 24, and omitted the CBOR envelope from encrypted
  file length. These fixture errors are corrected, not production bugs. Final
  fail-first log `native-red-final` retains only the 16 genuine key failures.
  Focused reports `native87-regression` and `native87b-regression` do not claim
  whole-client coverage. A full-source `client-native-runtime-vm` mutation
  target retains native artifact provenance and file-isolated test execution.
- A fail-first launcher check found the new suite absent from all three
  verification/coverage commands; it is now included. All 49 launcher tests
  pass. Fast87's first run was invalidated by editing its active Bash script;
  retain the exit-127 log, do not classify it as a product regression or a pass.
  The clean fast rerun, full VM87 coverage and serial `bin/verify` pass.
  The native runtime inventory has 613 candidates, not a sampled
  subset; no completed native-runtime mutation score is claimed yet.
- Auth-server hosted inventory remains all 294 candidates: 180 kills, seven
  survivors, 105 compile errors and two timeouts (95.24%, but not clean). The
  two timeouts are `9e33a2db89a2a9823589` (duplicate AUTHENTICATE admission) and
  `532a04779244e577ebf8` (terminal cancellation notification). Strengthen three
  existing tests to assert callback/response state before releasing their
  pending provider, with finally cleanup. All 84 auth tests pass. Auth87 reruns
  the entire unchanged production inventory and completes at 96.30%
  raw/adjusted: 182 kills, seven survivors and 105 compile errors, no errors,
  timeouts or waivers, both baselines zero. All ten source/test/support hashes
  match. The two prior deadlines now fail explicit callback-count and response
  presence assertions while the provider remains pending.
- Reinspect all seven Auth87 survivors through symbol references; none is
  waived or counted as a kill. At `pending_transaction.dart` SHA-256
  `8d587073290ecd510597b14242277df9bd26bf870e902338db4c8b8eb60827c6`:
  `0cc1ead8b574c8cf203d` changes the initial busy value, overwritten by `_run`
  before provider work; `f0f7947b4129955b0d95` removes the releasing guard and
  `b427e0e5e565adf26797` removes its assignment, while the two release callers
  remain separated by busy/finished state; `06d5f692caa982dc1a65` forces the
  abort branch, but a null terminal failure throws inside the existing cleanup
  catch before invoking a non-null authenticator; `61dd92199791b8c1fad0`
  removes the identity guard, while `_onHello` rejects occupied IDs and release
  is the sole map remover. Existing reentrant cleanup/ID-reuse tests pass under
  these mutants. No distinguishing public behavior is established, not proof
  that these defensive guards should be removed. At `selection.dart` SHA-256
  `555bcc0d43cd62d282117cd205f11b471697814272612f878379b2a068a187dc`,
  `33646fef253d12eefb8d` and `b4d522ace2dd2d9e1360` add empty lists to the
  candidate ordering; the nested loop makes no selection from either empty
  list. Keep all seven individual outcomes and the unchanged raw denominator.
- Local Qwen/GLM advice was checked against real implementations. Reject the
  proposed JSON string oracle: the serializer encodes Uint8List as WAMP binary.
  Reject the alleged independent FFI UTF-8 encoder: ffi's `toNativeUtf8` calls
  the same `utf8.encode`. Native error constants are negative and decrypted
  buffer ownership is deliberately separate from the consumed message. Do not
  weaken ownership tests or change protocol behavior on those speculative claims.
- Full `vm-current87/summary.json` measures client 8,120/9,355 (86.80%),
  native runtime 608/755 (80.53%), and router 16,330/19,287 (84.67%). Core
  remains 93.90%, MCP 95.40%, auth-server 100%, bench 84.69%. The 59 unmeasured
  library sources remain visible. Packaging retains separate denominators:
  client 391/402 (97.26%), router 374/385 (97.14%), 12 unmeasured sources.
  These VM measurements are not browser/WASM/native Rust coverage claims.
- Final verification includes Rust, installed-package MCP smoke checks,
  2,903 core WASM tests and two browser WebSocket tests. Logs use
  `/tmp/connectanum-coverage87-*`. Work87 is pushed as `417b2ca1` and PR #93
  updated. Native87-mutations starts all 613 candidates with a clean baseline
  and the unchanged native artifact hash; it is the sole native-runtime owner.
  No completed native mutation score is claimed. Hosted CI
  `35233785010`/`35233789407`, packages `35233785025`/`35233789398`, image
  `35233804665` and profile `35233807361` are exact-head runs. Both package
  checks pass; remaining hosted evidence is pending. Strict audit fails closed
  on pending jobs and the known feature-branch protection/workflow discovery
  findings. Leave this post-push bookkeeping uncommitted for the next code
  increment rather than creating a docs-only commit. Whole-goal
  targets remain unmet; no version, publication or merge action.

### Work86 Security Oracles And Evidence Integrity

- Revalidated existing processes before starting tests. Full VM85 completed
  successfully at the pushed `9e9579bf` snapshot. Package dry runs
  `35222915512`/`35222919508`, router-image dry run `35222988471` and canonical
  WAMP benchmarks `35223059950` pass. CI `35222915528`/`35222919475` subsequently
  completed successfully. No release/merge was performed.
- A pending GitHub run has an empty conclusion. Bash whitespace IFS collapses
  that column, shifting SHA/event fields. Six real reader snippets and pending
  CI end-to-end cases reproduce 24 failures. A non-whitespace separator now
  preserves empty columns; all 26 audit tests pass. Real strict audit correctly
  recognizes the head and manual dry-run event, but still fails closed for
  pending CI. Feature-branch protection and default-branch workflow visibility
  findings remain visible; neither is bypassed.
- Five runtime regressions exercise protected RPC/publish with the optional
  transport bearer check disabled, disallowed profile and realm methods before
  challenge creation, and changed profile policy after access/refresh issuance
  and cached-session use. Assert no unauthorized invocation/publication, then
  prove valid grants work. Rejected methods do not consume challenge capacity;
  rejected refreshes do not rotate grants. Mutable caller-owned profile method
  lists model the public configuration object's behavior, not a new reload API.
- Full runtime coverage passes 214 tests. The partial report at
  `binding86-regression/summary.json` measures 28 lines previously uncovered in
  VM85. It is not whole-router coverage; its policy failure for unmeasured
  unrelated sources is retained rather than narrowing the inventory.
- Initial replay `binding86-security-replay` exposed a polling deadline counted
  as an assertion kill. It is historical, not accepted final evidence. The
  stronger RPC oracle observes explicit unauthorized dispatch/session errors
  rather than merely waiting for a response. Final diagnostic replay
  `binding86b-security-replay/report.json` kills all six previously listed
  security mutants with explicit assertion failures, both baselines zero and
  unchanged native artifact. All production/test hashes match the current
  files. The full 2,379-candidate inventory is retained; six selected outcomes
  are not a whole-component score or equivalence waiver.
- Seven fail-first reporter cases prove helper deadlines and uncaught
  `Future.timeout` were classified as kills. Classify these as timeouts before
  considering assertion failures; matcher failures merely containing timeout
  text remain kills. Another fail-first test proves VM/browser mutant logs
  overwrite one another. Each target now has independent outcome logs, recorded
  paths and a runner hash. All 39 tooling tests pass (one optional native skip).
  Stored-log check `historical-timeout-reclassification86.json` removes 165
  false kills from incomplete binding66 and 10 from workload84. Binding66's
  partial counts are now 438 kills / 487 survivors / 394 compile errors /
  176 timeouts, still incomplete. Workload84 corrects to 47.93% raw/adjusted
  with 19 timeouts. Serializer82 and HTTP84 stored kills do not change. These
  corrections do not replace current-source campaigns or modify original files.
  Invocation85's per-runtime logs collided; its VM outcomes cannot be independently
  reclassified from those overwritten files. Fresh `invocation86-mutations` is
  complete in both runtimes with distinct recorded logs and the fixed runner:
  100 assertion kills, six survivors and 22 compile errors each, 94.34%
  raw/adjusted, no errors/timeouts/waivers, both baselines zero. All eight
  source/test/support hashes match. Exit one correctly retains the unmet 95%.
- Local companion advice was independently checked. GLM's proposed requirement
  that a timeout have test result `error` is rejected: polling helpers use
  `fail()` and produce `failure`, which must still not inflate mutation scores.
  Its concern that matcher text starts with TimeoutException is contradicted
  by real Dart reporter fixtures. Audit tests execute the actual six reader
  lines, including four-field events, not a reimplementation of their parser.
- Fresh `bin/test-fast` and full `bin/verify` pass with native use serialized,
  including 2,903 core WASM and two browser WebSocket tests. The completed
  prior-head strict audit finds only feature-branch protection and the mutation
  workflow not yet discoverable from master; CI/log/package/image/benchmark
  checks are clean. Commit/push and new-head hosted checks remain pending. Logs use
  `/tmp/connectanum-coverage86-*`; no goal-completion claim.

### Work85 Integration Verification And Completed Campaigns

- Revalidated process handles and the process table before starting a new native
  runtime user. No mutation process remains. Binding66 stopped at 1,495/2,379
  candidates (603 kills, 487 survivors, 394 compile errors, 11 timeouts), with
  `complete:false` and no restored-baseline result. Preserve it as interrupted
  evidence; do not attribute its partial percentage to a completed campaign.
- Serializer82 completes with clean original/restored baselines. CBOR VM has
  768 kills / 158 survivors / 239 compile errors / one timeout (82.85%);
  JavaScript has 762 / 160 / 239 / five (82.20%). MessagePack VM has 670 kills /
  162 survivors / 209 compile errors (80.53%); JavaScript has 867 / 190 / 218
  (82.02%). Raw and adjusted scores match, with no equivalence waivers. Timeouts
  remain failures, not kills. These full-source target scores remain below 95%.
- Workload84 completes all 519 candidates: 172 kills, 157 survivors, 181 compile
  errors and nine timeouts (50.89% raw/adjusted), both baselines zero. This is not
  whole-benchmark-package mutation evidence or a clean CI mutation gate.
- Fresh `bin/test-fast` exposes an integration regression in work78: the existing
  client test requires an invocation to remain open after synchronous transport
  rejection. Two focused core tests reproduce the same incompatibility for final
  results and errors. Preserve local rejection/retry semantics while reserving
  terminal closure during dispatch to reject reentry. Roll back only a rejected
  terminal attempt; progressive callbacks must not undo an accepted nested final
  reply, even when the outer callback subsequently throws. Preserve exception
  identity and stack. No WAMP wire change or new acknowledgement mechanism.
- Correct the uncommitted work78 test that assumed throwing after acceptance
  must permanently close the invocation. A void adapter does not expose whether
  it performed an irreversible side effect before throwing; that assumption
  contradicted established client behavior. Existing client assertions are not
  relaxed and now additionally prove one successful retry and rejection after
  completion. The focused invocation/client suites pass 344 tests. Initial test
  authoring failures (import placement and Yield's invocationRequestId field)
  are separate from the three reproduced behavioral failures.
- GLM review independently identified the invocation compatibility regression.
  Its CBOR-null concern is ruled out by the preceding `is CborMap` guard and the
  map conversion branch always returning a map. Its repeated lazy-loader concern
  is ruled out by `_ensureLoaded` clearing and checking `_loader`; the old fast
  path applied to present, not absent, keys. Qwen proposed retry and nested
  progressive cases; its suggestion to leave a successfully finalized nested
  invocation open is rejected. Final Qwen review completed; its suggested nested
  progressive/final test is already present, and Dart isolates do not share this
  mutable invocation instance. Full gates remain pending.
- Logs use `/tmp/connectanum-coverage85-*`. Existing serializer82/workload84
  report directories retain individual outcomes and hashes. Invocation78 source
  and test hashes no longer match this follow-up, so its 94.29% is historical,
  not the new implementation's mutation score. No final whole-goal claim.
- Next security-focused follow-up after the current implementation clears full
  verification and hosted checks: binding66 survivors `cd43388098f3fafab99e`
  and `850937720626a4942dd9` remove the protected ordinary HTTP call/publish
  bearer requirement; `61f23e93d08141f1bdb4`, `f05d4a1315925a5b4d23`,
  `17cd3ddb730e24c68134` and `0b65936ab4b5a0515784` bypass auth-method policy.
  Reproduce these with independent denial and no-side-effect assertions using
  the existing HTTP bridge/profile/realm fixtures before rerunning full binding
  evidence. This identifies missing mutation protection, not a confirmed bug in
  unmutated production. The colon-joined `_externalSessionCacheKey` is another
  lead, but current external/grant/anonymous-MCP callers all supply explicit
  cache keys; do not assert an exploitable collision or waive the fallback
  survivors without a public-path repro and pinned equivalence analysis.
- Fresh `bin/test-fast` and full `bin/verify` pass after the integration
  correction, with native runtime users serialized. Full verification includes
  Rust/Dart suites, package/CLI/MCP consumers, 2,903 core Chrome/WASM tests and two
  browser WebSocket tests. Logs are `connectanum-coverage85-test-fast-final.log`
  and `connectanum-coverage85-verify.log` under `/tmp`. No WASM line-coverage
  claim follows from these runtime tests. Invocation85 VM and
  JavaScript finish all 128 candidates each: 100 kills, six survivors, 22 compile
  errors, no crashes/timeouts, both original/restored baselines zero. Raw and
  adjusted scores are 94.34%; no waivers. The strict command exits one for the
  unmet 95% floor. All eight source/test/support hashes match current files;
  source SHA-256 is
  `847f7a3b7f7ba7eb8295da80d68a1291a1e51e9f8e5f7cde5afc3b739653497a`.
  Retain `invocation85-mutations/mutation-report.json` separately from work78.
- Qwen CI review flags the absent invocation/serializer mutation gates. They
  remain deliberately non-required while their measured scores are below 95%;
  adding failing gates or lowering their thresholds is not a valid fix. Existing
  selected test inventories and new passing-target gates remain enforced.

### Benchmark HTTP And WAMP Facade Regression

- Work83/84 selects benchmark paths that do not load native FFI while binding66
  owns the native runtime. The pre-change HTTP baseline passes four tests; the
  earlier fast66 workspace baseline remains the last bin/test-fast run. Fresh
  bin/test-fast and bin/verify are queued, not waived or replaced by focused tests.
- HTTP now has 439 tests across the existing suite and two regression files.
  Exact diagnostic snapshots cover optional counters, zero-valued timings,
  ordered/equal/reversed timestamps, aggregation and snapshot independence.
  Streaming tests cover pattern/chunk boundaries, copied versus borrowed bodies,
  empty chunks, drain ordering, first/second-chunk accounting, read/write/close
  failures, cancellation of the source subscription and interleaved requests.
  Synthetic/test body adapters do not access native handles. No production HTTP
  change or coverage exclusion was needed; 222/222 VM lines are covered.
- Initial full HTTP83 mutation evidence has 138 candidates: 51 assertion kills,
  two survivors, 84 compile errors and one timeout (94.44%), both baselines zero.
  A new second-chunk timing oracle catches the survivor that overwrites its
  timestamp with the last chunk. HTTP84 completes with 52 kills, one survivor,
  84 compile errors and one timeout (96.30% raw/adjusted), both baselines zero.
  The command exits nonzero because the timeout remains; do not label it a clean
  CI pass or count that timeout as an assertion kill. No equivalences are waived.
- Remaining HTTP outcomes are retained individually: `a1910c148cc4aee254d9`
  disables the private emit helper's empty-chunk guard; current callers already
  filter empty chunks. `5d76cc3f66fa8a66b730` changes the synthetic loop's `>` to
  `>=`, creating a zero-length infinite loop. An output-byte-budget assertion
  cannot observe this loop because the helper suppresses zero-length writes.
  Keep the timeout visible; do not convert a watchdog deadline to an assertion
  kill. The 98% HTTP line floor is enforced; a required mutation CI gate is not
  added while the strict mutation command is unclean.
- Work84 reproduces 15 incorrect-success cancellation cases with a real Dart
  loopback WebSocket peer, independent JSON wire frames, and all three cancel
  modes. Previously any error completed the benchmark successfully. The facade
  now recognizes only `wamp.error.canceled` and the router's existing
  `wamp.error.invocation_canceled`, propagating all other errors and stack traces.
  It leaves router/client wire behavior unchanged. The
  [WAMP cancellation specification](https://wamp-proto.org/wamp_ap_latest_ietf.html)
  uses the standard cancellation URI and allows a RESULT to win a kill-mode race.
  Such a result remains valid WAMP but does not prove a successful cancellation
  workload, so the benchmark continues rejecting it rather than counting it.
- The final 47-case wire suite additionally asserts all five call variants,
  acknowledged materialized/lazy publishing, event streams/callbacks/lazy payload
  subscriptions and revocation, registration/invocation/unregister, progressive
  input/results, disconnect failure, idempotent close, concurrent outcomes and
  ignoring a late cancelled response before a fresh call succeeds.
- Both mutation wrappers retain complete selected test inventories and hashes;
  the workload wrapper also hashes public TLS test fixtures. The HTTP target
  mutates the entire handler source; the workload target mutates the entire
  workload source and selects unit plus Dart WebSocket wire/TLS suites. Native
  integration is not claimed by this non-native target. Forty-eight launcher
  checks protect these selections; no source ranges or operators are excluded.
- Final focused verification: 558 tests pass in the two wrappers, full repository
  analysis passes, 37 runner checks pass with one optional native fixture skip,
  16 coverage-checker checks pass, and formatting/diff/public-reference checks
  pass. `bench84b-final-vm` measures HTTP 222/222 and workload 1,054/1,243 lines.
  It intentionally does not include native integration or the rest of the bench
  package; its partial package subtotal is not a replacement for whole-workspace
  bench coverage. The policy returns nonzero for missing package/source evidence.
- Local Qwen test planning/review and GLM review completed. A valid coarse-clock
  concern was addressed with inclusive monotonic bounds. Suggestions to return
  a successful RESULT from the cancellation benchmark were rejected: that would
  restore false-success accounting and change its Future<void> contract.
  The legacy URI was verified against the Error constant and router send path;
  the workload runner already applies an event-timeout bound to cancellation.
  Wire tests independently prove unrelated errors and disconnects propagate.
- Evidence under `out/regression-coverage-2026-09-15/`:
  `bench-http83-mutations`, `bench-http84-mutations`, `bench84b-final-vm`, and
  `bench-wamp84-mutations`. The workload campaign is live, with 519 candidates and
  baseline zero; partial results are not a completed score. Logs use the
  `/tmp/connectanum-coverage83-*` and `/tmp/connectanum-coverage84-*` prefixes.
  HTTP source hash is
  `10192da5a56f145772d2e469f04ade76f1eba1a04fd43375217a6f64e3146dca`;
  workload source hash is
  `b7455933e825bb47181564976f66b28de9d9a14eb3b00c86330142dc33a0e1e1`.
  Final report hashes match the current HTTP tests. No older score is attributed
  to newer workload tests. Binding66 and serializer82 owners remain live and
  untouched. Fresh full gates and implementation commit/push remain pending.

### PPT Value Contracts And Serializer Campaigns

- Work79 adds 126 CBOR public-API tests for exact binary headers, borrowed views
  including input offsets, non-minimal lengths, fragment precedence, empty/null
  fields, fallback envelopes, all small-frame truncations, trailing data and
  bounded large declared lengths. VM/WASM pass. A diagnostic replay against the
  old CBOR73 source catches 69 of 87 selected survivors, leaving 18, with clean
  and restored baselines, no errors/timeouts/waivers. This is not a full score.
- Expanded work80/82 tests include byte-for-byte preservation of non-minimal
  fragments, materialized binary plus kwargs, ignored binary-valued fields,
  uint64 declared lengths, and malformed UTF-8 keys. The final CBOR suite has
  158 cases. Two fail-first tests show PPT lookup ignores invalid UTF-8 in
  unknown top-level map keys. Validate text keys in the fallback and redact the
  resulting FormatException. Known-key single-binary decoding stays zero-copy.
  Valid unknown text and non-text extension keys retain their old behavior.
- [RFC 8949 sections 3.1 and 3.2.3](https://www.rfc-editor.org/rfc/rfc8949.html)
  classify invalid UTF-8 as invalid CBOR, including invalid individual text
  chunks. Generic decoder validation policy is application-dependent; strict
  PPT text-key rejection is our fail-closed application policy, not a claim
  that every generic CBOR decoder must perform validation. cbor 6.5.1 stores
  UTF-8 key bytes lazily and lookup does not force text decoding. Its CborString
  interface and both concrete string classes use strict toString() by default.
- Eleven fail-first cases show MessagePack PPT keyword maps cast values to
  non-nullable Object: direct lookup works but values/entries/forEach/map/copy,
  mutation and cross-codec forwarding fail for null values. Preserve the
  declared Map<String, dynamic> contract. Ten additional fail-first cases show
  CBOR and MessagePack return maps with non-string keyword keys that fail only
  on later application access. Both now check keys before returning the payload,
  with redacted FormatException and recovery tests. String keys, including empty
  and Unicode strings, remain unchanged. The shared suite has 43 cases.
- The [WAMP call payload contract](https://wamp-proto.org/wamp_latest_ietf.html)
  permits arbitrary application values in keyword arguments. These fixes retain
  null values and the existing string-keyed dictionary contract; they add no
  wire feature, coercion or new serialization format. Nested application data
  is not reinterpreted as top-level keyword arguments.
- Core82 VM passes 3,071 tests and measures 6,721/7,231 lines (92.95%); CBOR is
  1,281/1,300 (98.54%). Canonical JavaScript passes 2,910 and measures
  6,253/6,591 (94.87%); CBOR is 1,329/1,370 (97.01%). All 181 unmeasured browser
  sources remain visible. WASM passes 2,902 tests without a line-coverage claim.
  Full analysis passes. The core-only VM checker still fails missing-package
  scopes, rather than treating this as whole-workspace evidence.
- Work81 adds shared serializer mutation entrypoints without removing original
  tests. VM retains all applicable suites; the browser wrapper also registers
  the JS-only fallback suite. All original tests and helper files are hashed as
  support inputs, including the common wrapper for browser runs. The inventory
  guard compares filesystem discovery to imports, main calls and support lists;
  it fails before wiring and passes afterward. A formatter-induced multiline
  import parsing failure was corrected without changing the expected inventory.
  All 46 launcher, 37 mutation-runner, four mutation-generator, 16 coverage-checker
  and 24 deployment-audit tests pass, with one optional native fixture skipped.
  Original and wrapped VM runs both pass 2,098 tests;
  measured test-run durations are 6.428s and 4.104s respectively. The browser
  wrapper passes 2,103 tests in 10.734s; no unmatched browser speedup is claimed.
- Fresh full-source snapshot82 VM and JavaScript mutation campaigns run CBOR
  then MessagePack under serializers82-vm-mutations and serializers82-web-mutations.
  Both CBOR baselines pass and each inventory has 1,166 candidates. These runs
  are live, not final scores; no new serializer gate is asserted to pass 95%.
  CBOR hash: bb33063775f7004ecf9b325313ecd0727b6d7fbee202cd2ed67d50b8ed82d500.
  MessagePack hash: 2d18d06a5e8557b11ef77dadc87367255ce3bab1c55d526e667abad6ae87f79d.
  Binary test hash: f99bb12cba3b29316ffe0cd239c6dabf853f3b1f21aaaa2b1ff9dd3a915f2e48.
  Shared PPT test hash: 0c12510ed3d2fd120f439bbb87b60cba940822cca96dc889f94c8dc00389e66c.
- Earlier CBOR73 completes with 684 kills, 238 survivors, 239 compile errors and
  one timeout among 1,162 generated (74.1062% raw/adjusted), passing baselines and
  no waivers. Timeout 4508dcf119881179a1e7 changes the indefinite chunk break
  offset from +1 to -1; it remains a timeout, not an assertion kill. That source
  hash and the diagnostic PPT79 replay predate these fixes; preserve both as
  older evidence rather than attributing their counts to snapshot82.
- Local Qwen planning/review improved fragment-byte and boundary assertions.
  Suggestions to sample truncations or remove view-offset assertions were not
  adopted: the fixed small frame is bounded and borrowed views have observable
  offsets. GLM's deferred-key finding was reproduced and fixed. Its speculative
  claims about CborString strictness/subclasses were disproved by dependency
  source inspection and concrete tests; generic decoder APIs were not invented.
  Final narrow GLM and Qwen reviews reached their output-token limits and are not
  completed clean reviews; retain those diagnostics separately from the completed
  prior reviews and independent source/test verification.
- Binding66 still owns the native runtime. The continuing increment retains its
  pre-change fast66 baseline; fresh bin/test-fast and bin/verify must run after
  that owner finishes, before commit/push and hosted verification. No merge,
  publication, version change or equivalence waiver. Evidence is under
  out/regression-coverage-2026-09-15/core82-vm, browser-current82 and serializers82-*
  with logs /tmp/connectanum-coverage79* through /tmp/connectanum-coverage82*.

### Terminal Invocation Response Dispatch

- Historical work78 snapshot: its post-throw closure behavior is corrected by
  work85 above after full integration validation exposed the incompatible retry
  contract. The measurements below apply only to the original work78 hashes.
- Seven of nine fail-first cases show terminal dispatch is not committed before
  the transport callback runs: a callback can synchronously emit a second terminal
  response, throw after delivery and permit retry, or change options.progress to
  alter completion after emission. Nested progressive delivery and missing-adapter
  recovery are separate controls. Close terminal state before dispatch; never
  reset it after a callback. Keep actual progressive replies open.
- The [WAMP Advanced Profile](https://wamp-proto.org/wamp_ap_latest_ietf.html)
  requires calls to end with a final result or error and permits progressive
  messages only while the invocation is ongoing. Pre-dispatch closure is our local
  enforcement of that lifecycle, not a new wire feature or protocol requirement
  about callback implementation. Post-terminal adapter failure stays closed
  because delivery may already have occurred; failures before dispatch can retry.
- All 267 tests in the expanded Invocation wrapper pass. Core78 VM passes 2,870
  tests and measures 6,715/7,226 (92.93%); Invocation is 190/191 (99.48%). JS78
  passes 2,709, measuring 6,228/6,581 (94.64%) with Invocation 223/225 (99.11%).
  WASM78 passes 2,701. Both complete full-source mutation78 campaigns record
  99 assertion kills, six survivors and 22 compile errors (94.29% raw/adjusted),
  both baselines passing and no errors/timeouts/equivalence waivers.
  Source hash: `f3a143bb7b18c5ac3594850b09141f8405ac6b6139157c6c009ae77beb937c6c`.
- Preserve Invocation77 as older evidence: 75 new regressions, 256 wrapper tests,
  2,859 full-core VM / 2,698 JS / 2,690 WASM passes; 6,717/7,228 VM and
  6,231/6,584 JS lines. Invocation itself is 192/193 VM and 226/228 JS.
  Both full-source mutation77 campaigns record 101 assertion kills, seven
  survivors and 22 compile errors / 130 generated, 93.52% raw/adjusted, passing
  baselines and no errors/timeouts/equivalences. Subsequent orphan-decoder
  assertions and the terminal dispatch change are not covered by those snapshots.
- Reviewed survivors involve repeated PPT checks, redundant assignment, absent
  byte/decoder pairing and terminal error closure. No waiver has been applied.
  The local GLM judge accepted two orphan-decoder equivalences and requested
  re-entrancy evidence for the terminal branch. We added real contract tests and
  investigated the lifecycle instead of using the suggested waivers to pass 95%.
- Both runtimes now enforce a 98% Invocation file floor. Launcher checks reject
  omission of transcoding, regression and response-lifecycle suites. After four
  fail-first metadata audit job-list mismatches, all 24 audit tests pass, including
  missing-job checks. All 45 launcher and 57 measurement-tool tests pass on their
  recorded snapshots, with one optional native fixture skipped.
- Fresh `bin/verify` and commit/push remain gated on the sole live binding66 native
  owner. No merge, publication or version changes. Evidence roots are core78-vm,
  browser-current78, invocation78-mutations and invocation78-web-mutations under
  `out/regression-coverage-2026-09-15`; logs use `/tmp/connectanum-coverage78*`.

### Lazy Invocation Response Transcoding

- Fourteen of 17 initial tests reproduce data loss when non-WAMP PPT re-encodes
  lazy payloads across JSON, MessagePack, CBOR or the unencoded PPT fallback.
  Matching packed encodings already pass and retain byte identity. The fix uses
  lazy positional/keyword fields before explicit arguments when re-encoding,
  matching the existing E2EE fallback precedence without changing the wire format.
- The expanded 25-case matrix verifies partial lazy fields with explicit fallback,
  single decoding, failure before emission and recovery. Together with existing
  Invocation tests, all 45 pass. Two launcher assertions fail before adding the
  new file to both canonical browser commands; all 45 launcher tests then pass.
- Core76 VM passes 2,784 tests and measures 6,683/7,228 (92.46%). JavaScript76
  passes 2,623 and measures 6,194/6,566 (94.33%). WASM76 passes 2,615 without
  a coverage claim. Workspace analysis passes. Core-only reports retain missing
  packages and unmeasured-source inventories; no whole-workspace claim is made.
- Invocation76 inventories the complete invocation.dart source and runs one
  wrapper with hashed Invocation, transcoding, lazy-payload and registration
  suites. All 130 candidates complete: 52 assertion kills, 56 survivors and
  22 compile errors, 48.15% raw/adjusted, both baselines passing, no other outcomes
  or equivalences. Source hash:
  `127abbd818a8b2ea88ef162420493b014dcf068b130c30d722e66b852e3c31ab`.
- Further Invocation regression tests target surviving plain-lazy forwarding,
  fragment assembly, metadata, timeout and lifecycle branches. These tests
  postdate the above snapshots and need fresh mutation/coverage evidence.
- The local Qwen review completed after earlier response-limit failures; GLM
  timed out. Its suggested fallback-to-explicit-only change is rejected: public
  lazy getters already return decoded lists/maps, and cross-serializer fixtures
  independently prove that ignoring them loses data. A serializer mismatch is
  not a validation failure; it requires decoding and re-encoding.
- Evidence: `out/regression-coverage-2026-09-15/core76-vm`,
  `browser-current76`, and `invocation76-mutations`; focused logs use
  `/tmp/connectanum-coverage76*` and the new regressions `/tmp/connectanum-coverage77*`.
  The live binding66 native campaign still prevents fresh full verification,
  commit and push. No merge, publication or version change.

### Lazy Metadata And Subscription Lifecycle

- Eight fail-first metadata cases expose eager-key resurrection after removal
  and explicit value/null overwrites in ordinary-map and Details custom merges.
  Resolve pending entries before removal and use putIfAbsent consistently when
  materializing wire metadata. No authentication or WAMP wire format changes.
- The 21 custom-map and 259 Details regressions cover loader composition,
  independent instances/maps, single evaluation, nulls, clearing, explicit
  replacement after failure, all structured fields and capability isolation.
  Existing feature/handshake/custom tests bring the mutation suite to 295 cases.
  The first Details fixture had 36 generic function-variance errors; correcting
  its typed write helper is test authoring, not a production fix.
- Metadata74 VM completes with 137 assertion kills, 76 survivors and 44 compile
  errors / 257 candidates (64.32% raw/adjusted), with both baselines passing.
  The survivors identify unasserted remote capability defaults and feature keys.
  Independent absent/null/false/true per-role assertions raise metadata74b to
  213 assertion kills, 44 compile errors and no survivors/errors/timeouts/waivers
  (100% viable), both baselines passing. Do not relabel that snapshot after the
  final null-aware-map style fix. Final Metadata74c VM confirms 213 assertion
  kills / 213 viable, 44 compile errors, both baselines passing and no other
  outcomes. Its Details test hash is
  d71d58999cab8b27f0bc7b50b20c4e93e76a499994b6fbfcb4188a700ddda7f5.
  Original browser74 completes at 137/213 (64.32%), matching the older VM scope;
  final browser74b completes at 213/213 (100%), with 44 compile errors, passing
  baselines and no other outcomes. Its expanded tests and hashes match final VM74c.
- Thirty-one new subscription tests expose two override-stream callback
  replacement failures. Delivery now reads the current callback, like Registered,
  rather than retaining the old callback. The other cases cover delivery masks,
  lazy/materialized/payload routing, independent synchronous broadcast consumers,
  revocation reason and cancellation waiting. Two initial stream-object identity
  assertions were corrected to test shared delivery or the saved override;
  retain those fixture errors separately from the two reproduced product failures.
- The 37 subscription cases pass on VM, JS and WASM. Full subscription75 VM and
  JS mutation campaigns each record 15 kills and seven compile errors / 22,
  100% raw/adjusted, passing clean/restored baselines and no other outcomes.
  Source hash: 976bbebabbd12193adf8f5e86bd3fd3522bfa6a4e6b6cfba009dbbfbdb1857c9.
  Regression test hash: 9a5a8dde4b04dc9a9e7978d691051684a15efe9fd65fecf98ecafc71e500ebb8.
- Canonical JS/WASM verification and browser coverage now include metadata and
  subscription suites. Their launcher regressions fail before selection changes.
  Subscription mutation jobs and Chrome setup are wired into CI; audit fixtures
  reproduce the mismatched job set, then all 24 audit tests pass, including
  missing-job checks. All 44 launcher tests and 53 coverage/mutation-tool tests
  pass (one optional native fixture skipped). New 98% VM file floors cover all
  three models; browser floors cover only Details and Subscribed.
- Core75b VM passes 2,759 tests: 6,679/7,226 (92.43%); Details 346/346, custom
  fields 46/46 and Subscribed 51/51. The partial workspace policy retains missing
  other-package findings and 172 unmeasured library sources. Complete JS75 passes
  2,598 tests: 6,180/6,562 (94.18%), Details 379/379, Subscribed 46/46, custom
  fields 54/56. The custom-map remove method boundaries remain uncovered in JS
  despite exercised removal behavior; do not waive them or claim 98%. Separate
  focused subscription JS instrumentation is 48/48, not a replacement denominator
  for the broader 46/46 report. WASM75 passes 2,590 tests without coverage claims.
- Final style-adjusted JS75b repeats 2,598 passes and 6,180/6,562 (94.18%);
  WASM75b repeats 2,590 passes. Workspace analysis passes without issues.
  Focused final analysis and 332 combined model tests pass. GLM reviews completed;
  proposed automatic loader retry and skipped removal loads would change or break
  the map contract. Its missing onEvent attachment claim is contradicted by the
  existing attachment call and both installation-order tests. No such changes.
- Complete MessagePack71 records 668 kills, 162 survivors and 209 compile errors
  / 1,039, 80.48% raw/adjusted, both baselines passing and no errors/timeouts/waivers.
  Preserve MessagePack67's 73.34% separately. This older isolated snapshot does
  not cover later metadata or CBOR changes. Native binding66 and CBOR73 remain
  live; do not duplicate their campaigns or overlap native-runtime users.

Evidence: metadata74-mutations, metadata74b-mutations, metadata74c-mutations,
metadata74-web-mutations, metadata74b-web-mutations, subscribed75-mutations,
subscribed75-web-mutations, subscribed75-vm, subscribed75-js, core74-vm,
browser-current74, core75-vm, core75b-vm, browser-current75, browser-current75b
and msgpack71-mutations
under out/regression-coverage-2026-09-15, plus /tmp/connectanum-coverage74* and
/tmp/connectanum-coverage75* logs. Some named final campaigns are still running
or queued, not completed evidence. Fresh bin/verify, commit and push wait for
native binding66 to release the shared runtime; no merge or publication.

### Registration Lifecycle And CBOR Frame Parity

- Work72 adds 51 registration regressions covering all direct/materialized/lazy
  callback routes, sync/async errors, progressive and already-final responses,
  out-of-order request-ID isolation, fan-out, lazy bytes and stream disposal.
  Full VM72 passes 2,022 tests, JavaScript 1,840 and WASM 1,832. Core-only VM
  measures 6,508/7,229 (90.03%); Registered is 69/69 VM and 84/84 JavaScript.
  Browser core is 5,798/6,424 (90.26%), with 182 unmeasured sources visible.
- Initial registered72 VM mutations record 23 kills, one survivor and 22 compile
  errors / 46 candidates (95.83%). Browser records 20 kills, one survivor,
  three timeouts and 22 compile errors (83.33%, unclean). Mutants preventing
  stream attachment left a test awaiting a cancellation callback that could not
  occur. Work73 asserts attachment and cancellation start explicitly, releases
  held futures in teardown, and listens/cancels a never-listened controller
  before awaiting close. A 52nd regression ensures cancelling one stream listener
  immediately after dispatch does not erase its delivered invocation or stop peers.
- Final registered73 VM and JavaScript campaigns each record 24 assertion kills
  plus 22 compile errors / 46; 100% raw/adjusted viable score, both baselines zero,
  no survivors/errors/timeouts/equivalences. Source remains
  909d34cd280be80ae6c689f8c975bc2d3f15e23c7def21daf616261edd9e1515;
  test hash is f55360da20d7c5d0f6e3a8638327749988ff695c1a12857613dad27be96b0bc1.
  Canonical JS/WASM verification and JS coverage include this suite; VM/JS file
  floors are 98%. Both mutation targets are required by CI/deployment audit.
  A missing-job regression fails before wiring; final audit passes 24 tests.
- CBOR research: RFC 8949 sections [3.2](https://www.rfc-editor.org/rfc/rfc8949.html#section-3.2)
  and [3.4.6](https://www.rfc-editor.org/rfc/rfc8949.html#section-3.4.6) define
  indefinite containers and self-described CBOR (tag 55799). Ordinary definite
  and indefinite WAMP arrays already share the fast scanner; the self-described
  tag exercises the existing fallback without changing represented content.
  Independent fixtures expose 60 cases where fallback silently discarded invalid
  RESULT/INVOCATION progress or INVOCATION receive_progress values. Three bool?
  casts now match fast-path validation; null/true/false behavior remains tested.
- The first CBOR frame suite contains 408 cases: tagged/untagged, definite/
  indefinite outer and nested containers, handshake/acknowledgement metadata,
  custom values, PPT, all seven payload message types and malformed booleans.
  Fail-first result is 348 pass/60 fail; all 408 pass after the production fix.
  Full core73 VM passes 2,431 tests and measures 6,575/7,226 (90.99%); CBOR is
  1,259/1,296 (97.15%). JavaScript passes 2,249 and measures 5,899/6,430 (91.74%);
  WASM passes 2,241 without a coverage claim. A transient partial VM LCOV was
  regenerated after the process completed; only the terminal report is evidence.
- Seventeen further chunked UTF-8/binary, truncation, scalar-type, unsupported-
  message and recovery tests bring the final focused CBOR suite to 425, passing.
  Final core73b VM passes 2,448 tests with 6,592/7,226 (91.23%) core lines and
  1,276/1,296 (98.46%) CBOR lines. The new CBOR VM floor is 98%; unmeasured other
  packages make the workspace policy correctly fail on this core-only report.
  JavaScript73b passes 2,266 tests with 5,923/6,430 (92.12%) core lines; WASM73b
  passes 2,258 without a coverage claim. CBOR production hash is
  09edca3f06b6e9fc097ab588ce474df09013476901906ef3566f183b574cf0e8;
  test hash is 5c879ef8eba2075459adfcbe21944d561071b548aa0f4619eb668a8451650110.
  Local GLM reviews completed; suggestions to preserve malformed booleans were
  rejected because they contradict the established fast path. Suggested stream
  cleanup hazards were checked against final mutation outcomes, not accepted
  as findings without a repro. Preserve initial test-authoring compilation/null-
  wrapper mistakes separately from the actual 60-case production repro.
- Existing serializer challenge/welcome and feature-announcement tests were
  omitted from canonical browser selection. A fail-first launcher test captures
  the omission; both test-all compilers and browser coverage now include them.
  Final JavaScript73c passes 2,275 tests with 6,027/6,430 (93.73%) core lines;
  CBOR remains 1,307/1,363 (95.89%). Do not claim the VM's 98% threshold for JS.
  WASM73c passes 2,267 tests, without measured coverage. Workspace analysis,
  formatting/public-artifact checks, 42 launcher tests, 16 coverage checker tests
  and 37 mutation-runner tests (one optional native fixture skipped) pass.
- New whole-file core-cbor-serializer-vm/web targets include every serializer
  test plus challenge/welcome and lazy-payload regressions. The VM cbor73 campaign
  inventories 1,162 candidates, with a passing clean baseline and matching final
  CBOR source/test hashes. It has completed: 684 assertion kills, 238 survivors,
  239 compile errors and one timeout (74.11%), with the restored baseline also
  passing. This older snapshot is not evidence for the later PPT decoder fixes.
  The web target is configured but not yet run. Existing MsgPack71 and binding66
  campaigns continue on their older snapshots; do not restart or relabel them.
- Evidence: registered72-mutations, registered72-web-mutations,
  registered73-mutations, registered73-web-mutations, core72-vm,
  browser-current72, core73-vm, browser-current73, core73b-vm,
  browser-current73b, browser-current73c and cbor73-mutations under
  out/regression-coverage-2026-09-15. Fast66 is the pre-change baseline of this
  continuing increment. Fresh bin/verify and commit/push remain pending while
  binding66 owns the shared native runtime. No merge/publication/version change.

### MCP Completion Boundaries And Payload Containers

- Work71 adds 210 regression cases alongside the two existing completion tests.
  Public request/result models are asserted against independent expected fields,
  not only round trips. Cases cover prompt/resource references, optional title
  and context, string-only map keys/values, empty and Unicode partial values,
  constructor name validation, immutable input snapshots, candidate order and
  duplicates, 0/1/99/100/101/102 candidate boundaries, total bounds, nullable
  booleans, and field-specific parser diagnostics. No production behavior changes.
- Final core71b-vm passes 1,971 tests and measures 6,462/7,229 (89.39%) core-only
  lines. Completion is 104/104 VM lines. The workspace checker correctly exits
  nonzero for packages not collected in this core-only run. Final canonical
  browser-current71b passes 1,789 JavaScript tests and its policy; completion is
  123/123 lines and core is 5,722/6,358 (90.00%), with 182 unmeasured library
  sources visible. Adding completion/dependencies expands the browser denominator.
  WASM passes 1,781 tests; no WASM line-coverage measurement is claimed.
- Full-source completion71-mutations has 41 kills, three survivors and ten
  compile errors / 54 candidates, 93.18% raw/adjusted, both baselines passing.
  All three survivors concern error diagnostic normalization or string constraints.
  Additional assertions give completion71b-mutations 44 kills and ten compile
  errors / 54, 100% viable kills, both baselines passing, no errors/timeouts or
  waived equivalents. This proves this model file, not all core/MCP components.
  Completion source SHA-256 remains
  e5af50d61cbc1d756c55223af7400556f3459577cc850bac83dbefde2cb588b1.
- The first completion71-web-mutations snapshot records a Chromium renderer
  descendant alive after command exit. Preserve the infrastructure error; it is
  not an assertion kill. The next browser target uses one compilation wrapper
  importing both complete test suites, following the established lazy-payload
  mutation convention. Complete completion71b-web-mutations records 44 assertion
  kills, ten compile errors / 54, no errors/timeouts/survivors/equivalences, with
  passing clean/restored baselines. Its 100% viable score matches VM. Support-file
  hashes are retained by the runner. The final regression test hash is
  5674c6caa42227bdd4e20261e65bf455c0a3c45c20e10ae2765a4f7a0111819b;
  wrapper hash is
  8df0b0507255c7e9a05d9a2580f29ca0ff5990298168c8d9fdb43f6fb4fbb241.
- Canonical browser verification and coverage now include both completion suites.
  A fail-first launcher-selection regression covers both scripts; all 40 launcher
  tests pass after wiring. Completion has a 98% file floor on VM and JavaScript.
  Coverage checker tests pass (16); mutation runner tests pass (37, with the
  optional real-native fixture skipped). Generator tests pass (four). Workspace
  Dart analysis, changed-file formatting and public-artifact checks pass.
  CI now requires both complete completion mutation targets, with Chrome setup
  for the browser target; the deployment audit requires both matching job names.
  The initial missing-VM-job audit regression fails before wiring, then all 24
  audit tests pass with the VM job required. The final dual-job audit run is
  retained separately. GLM verification-diff advice was checked: the unchanged
  job name template matches the audit, and a coverage floor rejecting future
  uncovered code is intended, not a reason to weaken the floor.
- Preserve initial test-authoring failures separately: inferred String-only maps
  rejected malformed fixtures before production parsing, and two assertions
  wrongly rejected valid String candidates. The corrected 204-test snapshot and
  final 212-test snapshot both pass. Qwen test planning/review timed out or hit
  token limits; narrower GLM calls completed. Advisory suggestions were checked:
  total == count with hasMore true and null list entries were already tested;
  singleton/nested-list cases were added without inventing new protocol rules.
- Work70 adds 469 independent-encoder payload-container tests for CALL, PUBLISH,
  YIELD, RESULT, EVENT, INVOCATION and ERROR across all three encodings. Assertions
  preserve absent/empty fields, nested null/binary application values and direct
  binary payloads while rejecting invalid containers and non-string keyword keys.
  Negative closures encompass both decode and public getters, accepting eager or
  lazy validation. Source behavior is unchanged. VM70 passes 1,761 tests and
  stays at 6,427/7,229 core-only lines; JS70 passes 1,577 and measures 5,548/6,164
  (90.01%); WASM70 passes 1,569 without line instrumentation.
- payload70-replay inventories all 31 AST mutations in the selected eager/lazy
  payload guard ranges: 21 kills, five survivors and five compile errors, no
  errors/timeouts/equivalences, passing clean/restored baselines and matching
  restored source hash. All eager guards are killed. The five surviving lazy
  single-binary optimizations remain recorded, not waived or presented as a full
  component score. The test hash is
  2928f684a22aabf957ca0bfbcbf6e7b3c778540db635854cf34dd3410dbe3ed8;
  replay.py and complete logs/inventory are retained in the evidence directory.
- The full older MessagePack67 VM campaign is now terminal: 608 kills, 221
  survivors, 209 compile errors / 1,038 candidates, 73.34% raw/adjusted with both
  baselines passing and no errors/timeouts/equivalences. This is the work67 source
  snapshot, before subsequent auth-extra and payload/outbound changes. Never
  relabel its result as a current-snapshot score.
- A fresh full msgpack71-mutations campaign now inventories 1,039 candidates on
  the current work68 production source with work69/70 test additions. Its clean
  baseline passes; it remains running. Source/test hashes in its report bind
  this measurement to that snapshot. Do not convert partial counts into a score.
- Fast66 remains the pre-change baseline of this continuing increment. The live
  binding66 campaign owns the shared native runtime; full bin/verify and the
  implementation commit/push remain pending. No merge, publication or version
  change. Evidence: core70-vm, browser-current70, payload70-replay, core71-vm,
  browser-current71, core71b-vm, browser-current71b, completion71-mutations,
  completion71b-mutations, completion71-web-mutations,
  completion71b-web-mutations, msgpack67-mutations and msgpack71-mutations
  under out/regression-coverage-2026-09-15.

### Independent Outbound Metadata And Segments

- Work69 adds 279 cases in serializer_outbound_metadata_test.dart. Independent
  JSON/MessagePack/CBOR decoders compare serialized messages against literal WAMP
  IDs, distinct request/resource IDs and explicit expected fields, not a WAMP
  round trip. The cases cover each PPT field individually and together, escaped
  and empty strings, Result progress absent/false/true, Yield constructor
  defaults, null options, revocation request ID zero, and absent/partial/complete
  UNSUBSCRIBED details. CALL/PUBLISH fragments must retain same-encoding payload
  buffers, preserve mixed materialized/encoded fields, insert required empty
  positional placeholders, and transcode foreign encodings instead of splicing
  incompatible bytes. No production behavior was changed in this slice.
- Final core69b-vm passes 1,292 tests and measures 6,427/7,229 (88.91%), compared
  with core-only VM68's 6,360/7,229. JSON serializer is 935/968 (96.59%),
  MessagePack 1,184/1,261 (93.89%), and CBOR 1,192/1,299 (91.76%). The workspace
  checker still fails for other uncollected scopes; this is not workspace-wide
  completion. Final browser-current69b passes 1,108 tests and its policy, with
  core 5,541/6,164 (89.89%), JSON 933/1,049 (88.94%), MessagePack 1,210/1,352
  (89.50%) and CBOR 1,183/1,363 (86.79%). The 185 unmeasured library sources remain
  visible. WASM passes 1,100 tests with no line-coverage measurement. Formatting
  and focused analysis pass. Keep the earlier 216-test core69/browser69 evidence
  separate from the final 279-test snapshot, even where line totals match.
- outbound69b-replay reruns all 25 previously recorded survivors in the selected
  outbound/segmentation range. Eighteen are now assertion-killed, including all
  selected dropped-revocation/PPT-field cases, mismatched encoding and lost mixed
  fields. Seven survive: four buffer-copy flags, two empty-operation guards and
  the no-encoded-buffer guard. No equivalences were waived and no compile errors,
  crashes or timeouts occurred; both clean/restored baselines pass. This selected
  diagnostic is not a full source/component mutation score. Original and current
  mutation IDs, full current AST inventory, old/new hashes, exact UTF-16 offset
  remapping, tests, commands, replay script and logs are retained. The first
  outbound69-replay stopped before baseline execution because a line contained
  two identical operators; the corrected mapping uses the verified offset delta
  as well as line/text/replacement checks. Preserve that authoring failure.
- Source remains work68 MessagePack hash
  54f0fe7363904b4400adbddbe6aac67c1d641ac55e06d3cee8a2fcf823675594;
  final outbound test SHA-256 is
  541437933da11e6f01e07b4b69c74527100af8b9de52f9a6bd0f6deb7b38fcc6.
  Test-authoring failures included incorrect constructor names, treating JSON
  serialize output as bytes, omitting Yield's default false flag, and a misplaced
  test scope. They are not product bugs. Qwen review was independently checked:
  the suite already uses external format decoders and literal expected frames;
  its typed-default suggestion led to additional cases. A wider GLM review
  exhausted its output budget and is not counted as completed review evidence.
  A subsequent narrow GLM oracle review completed and confirmed that dropping
  the cipher field fails the independently constructed expected-frame assertion;
  the isolated replay demonstrates that assertion kill directly.
- binding66 and MessagePack67 remain live on earlier snapshots. Do not restart
  them or attribute their results to later tests. The shared native hash remains
  unchanged. Fast66 is the pre-change baseline for the continuing implementation
  increment; fresh bin/verify, commit/push and exact-head hosted verification are
  still pending until binding66 releases the native runtime. The overall target
  remains incomplete; no gates, scope exclusions, versions or releases changed.

### Authentication Extra Dictionary Guards

- Work68 follows security-relevant MessagePack67 survivors. WAMP defines
  [AUTHENTICATE](https://wamp-proto.org/wamp_latest_ietf.html#section-9.2.2)
  with an Extra dictionary, and its
  [serializer types](https://wamp-proto.org/wamp_latest_ietf.html#section-2.2)
  require string dictionary keys. Non-map Extra values were silently replaced
  with empty maps in all three serializers; MessagePack/CBOR also coerced
  non-string keys, including collisions, to strings. New fail-first tests
  reproduce 37 failures before the fix, with 32 other focused cases passing.
  All 69 pass afterward. Malformed input now throws a constant FormatException
  without source/offset or authentication data. Valid empty, nested, nullable,
  SCRAM and binary metadata remains unchanged; constructors/signature handling
  are unchanged. MessagePack type guards now have direct negative assertions.
- Full core VM68 passes 1,013 tests. Core-only coverage measures 6,360/7,229
  (87.98%); the workspace policy correctly fails for missing package scopes and
  the core floor, as it did for core-only VM67. MessagePack measures 1,150/1,261
  (91.20%). Canonical browser68 passes 829 tests and its coverage policy at
  5,464/6,162 (88.67%), with MessagePack 1,174/1,352 (86.83%) and 185 unmeasured
  library sources visible. WASM passes 821 tests without measured line coverage.
  Evidence lives under core68-vm and browser-current68. Focused analysis and
  formatting pass. Do not merge old source-position LCOV into these reports.
- auth-extra68-replay selects all 13 generated mutations on the three new
  dictionary guards and two MessagePack type guards. Ten are assertion-killed;
  three fail compilation. There are no survivors, crashes, timeouts or waivers,
  and both clean/restored baselines pass with restored source hashes matching.
  The report retains the whole-source inventory, explicit line selection,
  commands, logs and source/test hashes. This is a guard diagnostic, not a
  whole-file or component mutation score. The earlier full MessagePack67
  campaign remains active and does not include these tests or source changes.
- MessagePack source SHA-256 is
  54f0fe7363904b4400adbddbe6aac67c1d641ac55e06d3cee8a2fcf823675594;
  JSON is 8ac0588cf2cb6a0b826604631574d7d851a2faabcfc6ab3fa07185f512b5ed70;
  CBOR is 27a982318cca7f75ccf7b4458c504e5ca1036c0e5e628b0895bb2ed68484e66f.
  Qwen test ideas and GLM review were checked against the implementation and
  runtime evidence. The removed MessagePack normalization only stringified
  top-level keys, not values; valid nested binary tests pass on all runtimes.
  Qwen's first review exhausted its output budget; GLM completed the fallback.
- The binding66 native-runtime owner and MessagePack67 controllers were both
  confirmed live. Their partial reports are not final scores. The shared native
  library hash remains cda2b53349bc6718cc3fd278daf8fd251936fca7a5ed55ed51347f6b54d86363.
  Preserve their snapshots and do not start another native user or rebuild the
  artifact. Fast66 is the pre-change baseline for this continuing increment;
  fresh bin/verify, commit and push remain pending behind that owner. Hosted
  d44d3ea7 verification does not cover work67/work68. The full goal is incomplete.

### MessagePack Framing And Inventory Integrity

- Work67 is uncommitted on top of d44d3ea7. The binding66 campaign continues in
  its isolated snapshot; do not rebuild or replace its native artifact. Fast66
  provided the pre-change baseline. Fresh full verification of work67 remains
  pending until the native-runtime owner finishes; do not attribute verify66
  or d44d3ea7 hosted evidence to these later changes.
- Independent [MessagePack format vectors](https://github.com/msgpack/msgpack/blob/master/spec.md)
  cover scalar widths, legal wider encodings, binary values, collections,
  truncated extensions and trailing bytes in small/depth-checked frames. Of the
  first 179 cases, 54 fail before the fix: the bounds scanner returns null and
  falls through to the generic decoder, exposing RangeError/IndexError or
  FormatError instead of the serializer's FormatException contract. Both scanner
  loops now reject invalid values directly, with no extra work on valid frames.
- Expanded tests assert redaction, nullable metadata, distinct request/resource
  IDs, progressive options, timeout, recipient filters and both payload fields.
  All 210 focused cases, 670 broader VM serializer/lazy-payload cases, 959 full
  core VM cases, 775 canonical JavaScript coverage cases and 667 WASM cases pass.
  Preserve initial fixture getter errors and incorrect error-label assertions as
  test-authoring failures, separate from the reproduced framing bug.
- Core-only VM67 measures 6,361/7,233 (87.94%); its MessagePack serializer is
  1,152/1,264 (91.14%). It excludes cross-package test contributions, and its
  workspace-policy check correctly fails for missing scopes and the core floor.
  It is not directly comparable to full-workspace VM66. Browser67 measures
  5,458/6,164 (88.55%); serializer is 1,170/1,354 (86.41%) and codec 180/185
  (97.30%). Browser policy passes, with 185 unmeasured library sources retained.
  WASM remains passing tests without measured line coverage. Raw evidence is in
  core67-vm and browser-current67; do not merge older source-position reports.
- The first inventory reused existing codec target names, and JSON parsing
  silently shadowed the new definitions. Retain msgpack67-inventory as an
  authoring mistake, not full serializer evidence. Renamed serializer targets
  preserve the existing codec targets. Six fail-first configuration/equivalence
  cases prove that duplicate top-level/nested keys previously started execution.
  The loader now rejects duplicates before creating campaign output. Eight
  final cases also cover escaped duplicate keys; all 37 runner tests pass with
  the optional real-native fixture explicitly skipped, and four generator tests
  pass. The checked-in manifest has a separate unique-key regression.
- Corrected msgpack67b-inventory contains all 1,038 VM serializer candidates and
  all 1,272 browser serializer/codec candidates. The full VM campaign is running
  under msgpack67-mutations; the browser campaign has not started. Source/test
  hashes, not the base commit alone, identify this uncommitted snapshot. Serializer
  SHA-256 is bcbcdf9d1aa4bbe87e4b1193744216c4c98be8a89f931a3c4bed70938d3f1f0d;
  wire tests are f67ff759080dbc7e22706fa8110df306bcb9598966627a4f276ae3f1a71bcdba;
  ingress tests are 904288fae4526c03e66509a44cc31ee8d755a9a03e6a9d1227c5c9f00adba53e.
  Inventory is not a score; no candidate window, source exclusions, equivalence
  waivers or lower gates were introduced.
- Gemma/GLM/Qwen advice was independently checked. The top-level scanner loop
  cannot silently stop after fewer elements, and Python JSONDecodeError is a
  ValueError subclass. Existing missing-file errors already fail closed; they
  are not a new security regression. Additional runtime checks and final
  verification remain required before committing and pushing this increment.

### Configured File Conditional Requests

- VM65 identified router_binding.dart as the largest measured library gap:
  699 uncovered lines. New synthetic-runtime file-response regressions cover
  conditional requests, exact byte ranges, empty files, unsafe/decoded paths,
  content types, directory errors and symlink containment. Windows symlink
  creation is explicitly skipped; do not claim platform coverage from macOS.
- The initial 51 tests record 16 failures: HEAD honored Range, If-Range was
  ignored, If-None-Match did not use weak comparison, and malformed percent
  escapes left requests unanswered. Those fixes pass all 51. The expanded
  matrix then reproduces invalid HTTP-date requests hanging because the parser
  throws HttpException. Corrected imports and error handling pass all 81 cases;
  the full runtime/metrics pair passes 214. Preserve initial fixture compilation
  errors and the missing HttpException import as authoring failures, not kills.
- Protocol basis: [RFC 9110 sections 13.1.2, 13.1.5 and 14.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-13.1.5)
  require weak If-None-Match comparison, strong If-Range validation and GET-only
  Range handling. Existing size/mtime ETags are weak, and file mtime alone cannot
  establish Last-Modified strongness under section 8.8.2.2. Thus If-Range selects
  the complete representation, even for a matching date. No validator format or
  WAMP behavior changes. Full-file replies remain NativeHttpResponseFile.
- Slice66c covers 429/3,636 binding lines, not the whole router; its full-scope
  checker correctly fails for missing other components. Fresh package-wide
  coverage66 and serial verify66 pass, including native and JavaScript/WASM
  suites. VM66 measures 36,799/42,501 lines (86.58%); router is 16,290/19,287
  (84.46%), and binding is 2,965/3,636 (81.55%). The explicit 98% target check
  fails; 59 unmeasured library sources remain visible. Separate packaging
  coverage remains client 391/402 and router 374/385, with 12 unmeasured sources.
  Do not merge old LCOV
  line numbers across this source change. Reports remain under router-files66,
  router-files66b and router-files66c, with the failed runs retained separately.
- router-binding-vm inventories the whole binding file (2,379 candidates), with
  the runtime/metrics suites, explicit native artifact provenance, complete test
  file cleanup and 30-second per-test deadlines. Campaign66 has started against
  d44d3ea7 after verification, with baseline exit zero. Inventory66 and partial
  outcomes are not a completed mutation score. No candidate range or denominator
  is excluded to manufacture a pass.
- Exact-head package publishing dry runs 35084904972/35084901145 and router-image
  dry run 35084941801 pass; image MCP smoke and multi-platform builds pass with
  publication disabled. PR CI 35084904963 passes all 14 jobs and push CI
  35084901062 passes. Strict audit66 confirms clean jobs/logs and relevant
  publishing/image evidence, but still fails the unprotected feature-branch and
  mutation workflow absent from master findings. All seven latest beta.5 package
  publications and native artifacts were rechecked as successful. No merge,
  version bump or publication was performed; heavy diagnostics remain red.
- Gemma and GLM reviews were checked against source and executable assertions.
  Their suggested openRead length argument and HEAD range behavior contradict
  the Dart exclusive-end API and the protocol/GET-only guard, respectively.
  Existing GET range buffering remains a separate large-file memory/performance
  risk; this change does not claim to fix it or the hosted WAMP throughput gates.

### Router Metrics Contracts And Hosted Confirmation

- 748ddf21 PR CI 35079233511 passes all 14 expected jobs; push CI 35079229883
  and publishing dry runs 35079233562/35079229726 also pass. Strict audit65
  confirms exact-head clean jobs/logs and publishing evidence but still fails
  the same two structural findings below. No merge, release or protection change
  was performed. The last native-artifact and all seven pub.dev publication
  workflows separately confirm successful beta.5 releases; these do not publish
  or validate a new release of the coverage branch.
- 0ca81adf PR CI 35068960263 and publishing dry-run 35068960262 pass. Strict
  audit63 confirms clean exact-head jobs/logs and publishing evidence; its two
  structural findings remain the unprotected feature branch and mutation workflow
  absent from master. Do not merge or weaken protection to remove them.
- Diagnostics 35068969747 reduces fragmentation findings from 24 to two: only
  TLS/CBOR lifecycle rates at 1.874/1.946 Gbit/s remain below 2 Gbit/s. All data
  floors pass. The independent JSON WebSocket 64 MiB buffered file gate remains
  red at 1.194/1.147 Gbit/s data/lifecycle. All eight scenarios complete, six pass;
  evidence is retained under deployment63. The diagnostic chain is not green.
  A five-round local AOT probe found ascii.encode(substring) slower than the
  existing validated copy loop; no speculative serializer change was applied.
- Ten new metrics-model tests assert exact JSON keys and distinct counter values,
  copy preservation/replacements, optional omission versus zero, large process
  byte counts, all HTTP telemetry fields, per-listener counts, active-throttle
  filtering/order and default inactivity. No native runtime is needed for these
  model tests; service/native integration coverage remains separate.
- Metrics65 VM collection measures 249/249 lines; retry65b Chrome JS measures
  173/174 (constructor instrumentation differs). Both and Chrome WASM pass ten
  tests. WASM test success is not measured WASM coverage. Full-scope checkers
  correctly reject these isolated reports for missing other components; no
  component inventory or denominator was narrowed to manufacture a full pass.
- Complete Metrics64 has 62 kills/four survivors (93.94%). The final default-flag
  assertion raises Metrics65 to 63 kills/three survivors (95.45% raw/adjusted).
  Both inventory all 66 candidates and have passing clean/restored baselines,
  with no compile failures, errors, timeouts or equivalence waivers. The remaining
  boolean mutations change fixed-length result lists to growable lists; retain
  those outcomes rather than overfitting a behavioral oracle to allocation details.
- The new router-metrics-vm target runs at the existing 95% floor in CI, with
  always-retained reports/logs; the VM coverage policy now enforces a 98% file
  floor without removing the model from router/package totals. Deployment
  auditing requires the job, and fixture
  tests explicitly reject its omission. Fast64 passes. Full VM coverage65 then
  verify65 pass serially against the final production/test snapshot, including
  native checks, the real LLVM fixture and JavaScript/WASM suites. Focused
  analysis and formatting pass. Hosted metrics CI also reports 63 kills/three
  survivors from all 66 candidates (95.45%), clean/restored baseline exits zero;
  source/test hashes match locally. Retain its synthetic PR merge c06dfe24
  provenance under deployment65/router-metrics-ci rather than substituting the
  feature-branch SHA in the raw artifact.
- Fresh library VM65 reports 36,772/42,496 lines (86.53%). Auth is 100%, core
  90.22%, client 85.10%, router 84.34%, MCP 95.40% and bench 81.20%. Existing
  floors pass; --require-target correctly fails the 98% objective. All 59
  unmeasured library sources remain explicit. This refresh supersedes VM28 for
  the library snapshot, not standalone applications or native/browser coverage.
- Separate VM65 packaging coverage reports client 391/402 (97.26%) and router
  374/385 (97.14%), with 12 unmeasured packaging sources. The collection exits
  zero against existing floors, not against the whole-milestone 98% objective.
- Preserve browser65's pre-output exit 137 as infrastructure/invocation failure,
  not a product regression or mutation kill. Retry65b passes. Local companion
  suggestions were checked against source and tests; the suggestion to include
  backpressure in transportAlerts contradicted the contract and was rejected.

### Lazy Event Throughput Regression

- Hosted diagnostics 35065981089 on 6a8a2bf7 now completes all eight scenarios,
  uploads evidence and publishes the status table even when gates fail. Six
  scenarios pass; WebSocket fragmentation and file transfer fail. The separate
  JSON WebSocket 64 MiB Dart-buffered transfer fails at 1.235/1.181 Gbit/s
  data/lifecycle against 2 Gbit/s. Evidence remains under deployment59; do not
  call the diagnostic chain green or relax its policy.
- fe562ea1 routed plain LazyEventPayload getters through a combined decoded
  view. Keyword-only worker/iteration checks consequently decoded each 4 MiB
  positional body. Eight fail-first assertions establish the regression across
  JSON/MessagePack/CBOR read orders and independently invalid fields. Plain
  getters now use the underlying independent lazy fields. Wrapped/custom PPT,
  runtime/fallback E2EE and already-decoded payloads retain cached shared decode;
  full materialization still validates both fields.
- Complete matched local matrices use isolated ports, one router worker and one
  native runtime thread, identical native/scenario hashes, and fresh AOT workers.
  Before: 16 gate findings. After: all 24 workload gates pass. CBOR pub/sub data
  improves from 0.577-0.618 to 2.372-4.065 Gbit/s, JSON from 1.485-1.519 to
  3.604-7.011, MessagePack from 3.075-3.327 to 4.123-10.604. Evidence and provenance
  are under deployment60/websocket-isolated and deployment61/websocket-after.
  This single local comparison is not hosted proof or a variance study; peak RSS
  remains substantial. The initial default-port run was deliberately interrupted
  and is not comparison evidence. No workload or throughput gate changed.
- Final focused VM/Chrome JS/Chrome WASM suites each pass 90 tests. Tests cover
  independent decode counts, encoded byte identity, shared packed decoding,
  deferred invalid-field errors, one-time E2EE/custom PPT unwrap, metadata/anchor
  preservation and absent/empty/populated payload conversion with copy isolation.
- Complete Event61: seven kills, twelve survivors and three compile errors,
  36.84% raw/adjusted. Complete Event63 after metadata/conversion tests: 18 kills,
  one survivor and three compile errors, 94.74% raw/adjusted. Each inventories all
  22 source mutations, has passing clean/restored baselines, and no errors,
  timeouts or equivalence waivers. The remaining decoded-flag mutation delegates
  to a helper with the same check; retain it visibly until individually reviewed.
  This library target is not whole-core mutation evidence.
- Fast61 and full verification62 pass. Eleven final tests were added during
  verification62 and pass separately on all three runtimes; full verification63
  rechecks the final source/test snapshot. Focused analysis/formatting pass. Preserve wrong-root browser
  asset timeouts and initial invalid test-constructor compilation separately from
  the corrected fail-first assertions and successful runtime tests.
- Publishing dry-run 35065965825 and app artifacts 35065961167 pass on 6a8a2bf7;
  PR CI 35065965580 is pending. Re-run diagnostics and the strict deployment audit
  after pushing the lazy-getter fix. No master merge, publication or version bump.

### Deployment Diagnostics And Message Persistence

- A5e6515b exact-head PR CI 35062393342, publishing dry-run 35062393273 and
  application artifacts 35062390211 pass. Strict audit56 confirms clean CI jobs
  and logs but retains the unprotected feature branch and checked-in mutation
  workflow absent from master findings. Master itself is protected and its latest
  CI/publishing/profile-benchmark runs pass. No merge/publication is authorized.
- Fresh diagnostic run 35063947294 reproduces a current performance blocker:
  24 checks fail across twelve 4 MiB native WebSocket pub/sub variants. Data-window
  rates span 0.34-1.63 Gbit/s, below the unchanged 2 Gbit/s floor. Retain both this
  artifact and historical failed run 32707969763 under
  out/regression-coverage-2026-09-15/deployment57. Different runner hosts and Dart
  3.13.1/3.13.4 plus Rust 1.98.0/1.98.1 versions make causality unresolved.
- The failing fragmentation gate stopped four later diagnostic scenarios from
  executing. The launcher's new fail-first harness proves premature termination
  after workload/gate failures. It now completes remaining scenarios, records
  per-scenario workload/gate exit codes, skips a failed workload's gate and keeps
  a nonzero aggregate result. CPU information is optional evidence, never a gate;
  GitHub always publishes the status table and uploads artifacts. Seven isolated
  failure/success cases and all 39 launcher tests pass. No throughput policy or
  required gate is relaxed. Re-run the hosted diagnostics after pushing this fix
  to expose the remaining transfer scenarios; performance is still unresolved.
- Historical CI 35041876161 failed before mutation execution because Ubuntu
  Chrome had no usable sandbox; dd8cb16d's canonical launcher fix and later green
  CI cover that issue. CI 35037800535 instead failed fetching the hosted beta.5
  router release asset with a connection reset. Keep the published-consumer
  path intact; do not conceal this download-resilience gap with local overrides.
- Server58's final snapshot passes 205 tests at 3,298/3,531 VM lines (93.40%).
  Server RPC code is 773/868 (89.06%); mailbox storage is 248/252 (98.41%). Six
  loopback-router tests cover authenticated sending, private cursor notifications,
  receipt/device/account boundaries, one-time consume/retry, malformed calls and
  durable attachment/storage failures. A later eligible notification provides a
  causal barrier for the unauthorized-notification assertion, rather than sleep.
- Two direct and one real RPC regression fail before the mailbox fix: directories
  and dangling links are not missing stores despite File.exists() returning false.
  The new no-follow type check rejects them, preserves genuine missing-file
  compatibility and retains messages/cursors through failure recovery. Public
  RPC errors redact paths. The link regression explicitly skips Windows.
- Message57 completes: 236 candidates, 140 kills, 68 survivors, 28 compile errors,
  no errors/timeouts/equivalences, 67.31% raw/adjusted and passing clean/restored
  baselines. Sources are mailbox_store.dart and message_service.dart; only their
  unit suites are mutation oracles. Do not attribute RPC coverage to that run.
  Push56 completes with 229 kills, 24 survivors, 44 compile errors, no errors/
  timeouts/equivalences, 90.51% raw/adjusted across 297 candidates and both
  baselines passing. Both targets remain below 95%; inventory scope is explicit.
- Fast56 and full verification58 pass, including the real LLVM fixture and core
  JS/WASM suites. Server58 coverage, focused analysis and formatting pass. Preserve
  the initial wrong-library-path test invocation as infrastructure failure, not
  product evidence. Verification59 follows the launcher/workflow changes.

### Application Push Lifecycle Follow-Up

- Server56 passes 196 tests at 3,225/3,528 VM lines (91.41%), compared with
  server44's 89.70%. FCM gateway is 96/96, push service 90/90, and subscription
  storage 182/184 (98.91%). The server-wide 98% gate remains unmet; 81 unmeasured
  application files, including executable coverage gaps, remain explicit.
- Three fail-first initialization tests reproduce leaked caller-owned HTTP
  clients on successful shutdown and failed gateway construction. The
  googleapis_auth nonClosingClient ownership contract requires closing the
  underlying client separately. Late authentication wrappers are also closed
  after initialization timeout. Fixtures use an offline-only BaseClient,
  synthetic RSA credentials and temporary files, with no external account access.
- Stalled and slow-drip response-body tests both time out before the fix.
  Delivery now shares one elapsed deadline across headers and body, and cancels
  the StreamIterator on expiry, oversize response, failure and completion.
  Additional regressions cover exact credential/response limits, malformed
  persisted fields, account/device-bound unregister and revocation, dispatcher
  lifecycle, transient store failures and status/name response validation.
- Fast54 and full verification54 pass. The final body fix follows verification54;
  full verification55 then passes serially after server55 collection, including
  native HTTP/3, the real LLVM fixture and JavaScript/WASM browser suites. Later
  server56 tests, analysis and formatting pass. Preserve the earlier test compilation failure, bad runner
  module invocation and premature LCOV check as tooling/test-development failures.
  Correct direct runner invocation passes all 35 tests (one platform skip).
- New app-server-push-vm inventory covers all three push production files and
  four test files. Complete push54 records 176 kills, 61 survivors, 44 compile
  errors and seven timeouts across 288 candidates (72.13% raw/adjusted), with
  passing clean/restored baselines and no equivalences. Its original snapshot
  precedes the later body deadline and endpoint/status/lifecycle regressions.
  Complete push55 uses the newer body/lifecycle snapshot: 200 kills, 53 survivors,
  44 compile errors and zero errors/timeouts/equivalences across 297 candidates,
  79.05% raw/adjusted, both baselines passing. Preserve earlier unclean evidence.
  Its operator inventory is 116 binary, 142 condition, 25 boolean, ten negation
  and four null-fallback candidates. It predates the additional server56 tests.
  Timeouts are not kills; no exclusions or weakened thresholds are introduced.
- Server56 adds independently invalid persisted schemas/entries, duplicate keys
  versus duplicate provider tokens, account-isolated deletion, atomic failed
  token transfer, compare-and-delete results, and same-length mute-policy changes.
  Typed FCM errors cannot be confused with generic errors; malformed details do
  not hide a later valid typed error. Dispatcher tests exercise exact presentation
  ID/queue bounds, blank account inputs and older queued cursors. A child process
  with an isolated fake chmod validates permission failure without modifying the
  parent PATH. Child execution is not counted in parent LCOV, and Windows remains
  an explicitly separate gap. These later tests await fresh mutation evidence.
- Full shared51 is complete: 1,314 candidates, 986 kills, 83 survivors, 245
  compile errors, zero errors/timeouts/equivalences, 92.24% raw/adjusted, with both
  baselines passing. It improves on shared41's 83.63% but remains below 95%.
  Operators: 697 binary, 538 condition, 30 boolean, 46 negation, three null-fallback.
  It uses 135 tests and predates the 136th Base64url regression. Do not relabel its
  snapshot or use passing individual slices as whole-application evidence.
- The 3742159b full PR CI is green. Latest pushed 2f089b70 publishing dry-run
  35059122690 and application artifacts 35059120216 pass; PR CI 35059122706 is
  still running. Audit47 observed that newer incomplete head, not a regression
  in the completed 3742159b run. Latest-head audit53 remains pending.

### Latest Consumer And Browser Checkpoint

- App-shared52 passes all 136 tests on VM and Chrome JavaScript; WASM53 passes
  the same suite. VM measures 1,537/1,540 (99.81%), JavaScript 1,768/1,792
  (98.66%); WASM line coverage remains unclaimed and the 94 unmeasured application
  sources remain explicit. Tests independently invalidate MCP capabilities/types,
  distinguish unsafe routes, exercise exact attachment/message/push limits,
  preserve legacy receipts and aggregate latest receipt time in both recipient
  orders. Persisted call ciphertext distinguishes URL-safe from standard Base64.
  WASM51 failed due to an incorrect manually supplied Chrome path, not product
  behavior; retain its log. WASM53 passes with the repository browser launcher.
  Fast49 and serial full verification51 pass, including the real LLVM fixture,
  native HTTP/3, 528 core WASM tests and two WebSocket WASM tests. Shared analysis,
  formatting and git diff whitespace checks pass. Local companion suggestions
  were checked against source: the tests already exercise exact 64-chunk bounds,
  successful non-voice descriptors without duration and both padding variants;
  no exclusions or exception-message-only assertions were added.
- Complete app-shared41: 1,314 candidates, 894 kills, 175 survivors, 245 compile
  errors, zero errors/timeouts/equivalences, 83.63% raw/adjusted. Both baselines
  pass. Operator inventory: 697 binary, 538 condition, 30 boolean, 46 negation,
  three null-fallback candidates. This is the 112-test snapshot, not the latest
  oracle. Full app-shared51 uses 135 tests and is now complete as recorded above;
  it predates the final Base64url regression.
- Complete app-call48: all 214 candidates, 174 kills, nine survivors, 31 compile
  errors, zero errors/timeouts/equivalences, 95.08% raw/adjusted, with both
  baselines passing. Operators: 105 binary, 90 condition, eight boolean, eight
  negation, three null-fallback. Removing alphabet validation can admit standard
  Base64 through Dart's normalizer: a new distinguishing persisted-ciphertext
  test now rejects '+' and '/'. Complete app-call52 validates the 136-test oracle:
  175 kills, eight survivors, 31 compile errors, zero errors/timeouts/equivalences,
  both baselines passing, 95.63% raw/adjusted. Alphabet-validation mutant
  016877bb31d79bafabca produces the expected assertion failure, not a crash.
  This passing call slice is not a passing whole-application mutation score.
- Pushed 3742159b publishing dry-run 35057163119 and application artifacts
  35057159987 pass. Its PR CI 35057163344 remains in progress; the new shared
  JavaScript gate passes. Strict audit47 awaits completion of that chain.

### Prior Consumer Checkpoint

- Canonical app-shared47 passes all 115 tests on VM/Chrome JavaScript/WASM.
  VM remains 1,536/1,540 (99.74%); JavaScript is 1,760/1,788 (98.43%). No WASM
  line-coverage claim is made. Additional tests distinguish direct ICE credential
  and URL limits, exactly sixteen offers, and independently inconsistent offers.
  The collector explicitly selects vm/chrome, keeps Bash 3 option arrays nonempty,
  rejects missing Chrome/unsupported runtimes, and omits VM ignore processing for
  JavaScript. Both use the same 98% floor/source inventory. Behavioral launcher
  tests pass; the new separate CI browser gate/artifact awaits hosted execution.
- Complete app-shared35: 1,314 candidates, 798 kills, 272 survivors, 244 compile
  errors, zero errors/timeouts/equivalences, 74.58% raw/adjusted. Clean/restored
  baselines pass. Full app-shared41 runs the 112-test snapshot; later 115-test
  boundary improvements must be validated separately, not relabeled into it.
  The full 214-candidate app-call46 slice runs the newer boundary oracle but
  predates the final independent version/algorithm rejection assertions.
- Application server44 passes all 148 tests at 3,154/3,516 VM lines (89.70%),
  up 77 covered lines; server.dart rises to 706/868. Public signed call RPC and
  pub/sub tests cover lifecycle, duplicates, pagination, account/device isolation,
  rejection/error mapping and redacted filesystem failure/recovery. The 98% gate
  remains unmet and the executable unmeasured. Preserve the focused native-lock
  collision from overlapping fast42; the complete server collection passes only
  after fast42 exits successfully. Full verification45 passes serially afterward,
  including the real LLVM fixture and both core/browser compiler paths.
- f4ae80b0 PR CI 35053842965, publishing dry-run and application artifacts pass.
  Strict audit35 confirms clean/relevant jobs and logs, but still fails feature
  branch protection and mutation-diagnostics.yml absent from master. No merge,
  publication, branch-policy weakening or blanket exclusion is performed.

### Earlier Checkpoints

- Follow-up app-shared40 passes 112 tests at 1,536/1,540 VM lines (99.74%).
  Separate JavaScript collection initially measured only 1,671/1,762 (94.83%).
  Additional cross-runtime endpoint, backup, envelope, receipt, device, call,
  attachment and consent rejection tests raise app-shared40-browser to
  1,757/1,787 (98.32%), without exclusions. Both full collections pass; keep
  their denominators distinct. Canonical shared browser collection/CI enforcement
  remain pending; JavaScript results are not WASM line-coverage evidence.
- Server baseline app-server38 passes 145 tests at 3,077/3,516 VM lines (87.51%).
  server.dart accounts for 233 uncovered lines. Its executable and export facade
  remain unmeasured, as do the unrelated application components listed separately.
  An initial summary ran before the formatter completed; preserve it as
  summary-before-format-complete.json, not as valid coverage. The final summary
  follows the formatter's successful exit and remains below the 98% target.
- Full bin/test-fast35 and bin/verify35 pass, including the real LLVM fixture and
  both core browser compilers. f4ae80b0 is pushed; its publishing dry-run and
  shared VM gate pass, with the hosted artifact confirming 99.74%. Remaining CI
  and the strict audit are watched. The prior runtime image dry-run passes.
- Complete profile37 verifies both baselines and all 150 candidates: 125 kills,
  six survivors, 19 compile errors, no errors/timeouts/equivalences, 95.42% raw
  and adjusted. This verifies the constructor and typed-avatar boundary oracles,
  not the entire shared protocol. Full app-shared35 still uses the earlier
  97-test snapshot and must not be relabeled as the newer 112-test oracle.

- Pushed 8872ad3e carries the HTTP-body lost-wakeup fix and configuration/tooling
  regressions after bin/test-fast and bin/verify pass. Its package dry-run passes;
  candidate CI remains pending. Complete native30 retains 93 assertion kills,
  19 survivors, five compile errors, ten errors and two timeouts: 75.00%
  raw/adjusted, unclean evidence. Keep all 129 candidates and logs.
- Shared consumer protocol app-shared37 passes 100 tests at 1,536/1,540 executable
  VM lines (99.74%). New regressions first fail for out-of-range avatar integer
  lists silently narrowed to bytes and non-string receipt timestamps throwing
  TypeError. Strict range/type checks fix those cases without changing valid
  wire values. Independent receipt fields, image signatures/copy isolation,
  call configuration/state, message expiry and malformed backup/push data are
  exercised. This is shared-protocol VM evidence, not Flutter/server coverage.
- Application-aware LCOV parsing separates shared/server/client production
  lib/bin paths, rejects test/path-traversal inflation, and retains all unmeasured
  application sources. Sixteen report tests pass. The new canonical shared
  collector passes its 98% policy with all eleven measured sources required;
  94 other application source files remain listed. Behavioral launcher tests
  cover resolution/test/format/floor failures, output paths with spaces and
  refusal to overwrite evidence. CI retains raw, LCOV and JSON artifacts.
- Hosted core-lazy-web job 104634266890 reaches its 90-minute budget, retaining
  an incomplete 272/289 inventory: 208 kills, 15 survivors, 49 compile errors,
  no recorded errors/timeouts. Routine ~23-second browser test commands, not a
  proven per-mutant hang, dominate runtime. Preserve the downloaded artifact.
  A grouped entrypoint imports all three unchanged suites and hashes those
  dependencies. Exact named-test comparison is identical (84 tests), and both
  baselines pass: local 12.76 seconds becomes 5.60 seconds. The full lazy33
  campaign completes all 289 candidates with clean/restored baselines passing:
  223 kills, 16 survivors, 50 compile errors, zero errors/timeouts. Raw score is
  93.31%, adjusted 96.54% with eight existing source-hash-pinned equivalences.
  Source/operator inventory, thresholds and timeout policies are unchanged.
  No replacement hosted pass is claimed yet.
- Local review's proposed missing-lib/path-resolution findings are disproved
  by the actual scope tuple, Windows/Unix parser fixtures, exact test-name
  comparison and canonical 99.74% collection. Retaining failed coverage artifacts
  is intentional; do not delete them based on the companion's cleanup suggestion.
  No broad exclusions are added. Verification33 and standalone consumer33 pass,
  including Flutter/browser tests and release web compilation. Fast35 passes;
  full35 runs serially for the new mutation tooling. Hosted CI/audit remain required.
- The runner now supports standalone application Dart roots: scoped snapshots,
  ignored lockfile copying with symlink rejection, offline resolution in the
  package directory and dependency hashes/logs. All 35 runner tests pass, with
  one Linux-only skip on macOS. app-shared-vm inventories all thirteen production
  sources, including declaration-only facades. Its complete 1,314-candidate
  app-shared35 campaign passes the clean baseline and remains running.
  It does not establish a mutation score yet. Later constructor/typed-avatar
  and signal-ciphertext boundary tests address observed survivors; profile36
  confirms the constructor size-limit mutant is killed. Its complete 150-candidate
  result has 124 kills, seven survivors and 19 compile errors: 94.66% raw/adjusted,
  no errors/timeouts, both baselines passing. Profile37 checks the newer typed
  boundary oracle; neither slice replaces the full inventory. Keep the original
  campaign because it predates these newer test oracles. Flutter client and
  application server mutation execution/coverage remain separate pending work.

Evidence: app-shared31/32/33/34/36/37, app-shared35-mutations,
app-profile36-mutations, native30-rawsocket, coverage33-browser-timeout,
lazy33-combined-browser and coverage31/32/33/35/36/37 logs. The original goal stays active.

Initial pre-change `bin/test-fast` failed an existing launcher timing assertion
(15.05 seconds against a 10-second bound). The unchanged isolated test passes in
5.51 seconds and full confirmation passed. A later VM coverage run encountered
an intermittent native-ticket benchmark failure; its isolated recheck and the
next complete coverage/verification runs pass. An initial full verification
also failed the existing benchmark CLI smoke without diagnostic output; its
traced recheck and next complete verification pass. Causes remain unproven.

A final verification overlapped VM coverage collection and exhausted the native
test runtime's shared-lock admission wait; keep those full commands serialized.
A subsequent serialized verification hit a 30-second protected MCP HTTP/3
handshake timeout. The isolated test and all five HTTP/3 tests pass with the
test-enabled native library. Twenty further diagnostic group repetitions pass
(100 test executions); the intermittent handshake failure's cause remains
unproven. Do not treat rechecks as a fix or increase the timeout to hide it.
The ordinary release native library lacks these test-client helpers and skips
the HTTP/3 cases; reproductions must use `target/ffi-test/release`.

The final full `bin/verify` confirmation passes, including native integration,
297 core tests on each Chrome JavaScript/WASM compiler and browser WebSocket
checks. A final mutation-runner regression separately reproduced an empty target
configuration incorrectly passing without tests; the guard now rejects empty or
non-mapping configurations before creating evidence. All 11 runner tests pass.
Retained local evidence is under `out/regression-coverage-2026-09-15/`, including
complete mutation inventories, VM/browser LCOV and summaries, raw native data,
the earlier HTTP/3 failure, diagnostic repetitions and final verification log.
This confirms the first slice, not completion of the repository-wide target.

### Completed First Slice

- VM coverage now measures 33,767/40,031 (84.35%) after adding five omitted client
  suites and new regressions. The source inventory and accurate, unrounded
  package floors are enforced locally and configured in CI. Router results vary
  by 11 lines across complete runs because HTTP stream-close error handling and
  pending-call shutdown branches are timing-dependent. Retain the pre-change
  hosted router floor (82.18%) rather than treating the best observed run as a
  deterministic ratchet; enforce the new authorization-file floor separately.
  Deterministic stream-close failure injection remains required router work.
- Authentication-server measures 455/455 lines (100%). Transaction handling,
  authenticator selection, the WAMP RPC adapter and `auth_server.dart` each
  measure 100%. The defensive missing-challenge branch is exercised through a
  malformed third-party implementation of the public `AuthResult` interface.
  Added tests cover owner isolation, all response envelopes, service admission,
  late callbacks, malformed RPC payloads, cancellation and deadline behavior.
  Mutation-guided cases independently check duplicate admission when capacity
  remains, closed-server admission, explicit/disabled deadline overrides,
  retained masked failures, invalid auth-method entries and inconsistent plugin
  outcomes. Three initially plausible equivalent status/payload mutants were
  distinguished through malformed public plugin implementations, not waived.
- Expanding core serializer tests to Chrome reproduced a dart2js Base64 invalid
  sentinel bug. Portable bit checks fix it without changing VM wire output.
  Browser Base64 measures 144/144 (100%); the complete measured browser slice
  is 4,291/5,201 (82.50%), separately reported from the VM badge.
- Authorization mutation inventory: 102 generated, 69 killed, 28 compile errors,
  five survivors, three individually justified source-hash-pinned equivalents.
  Raw score 93.24%, adjusted 97.18%. Forced provider-decision conditions remain
  unwaived because skipping an overridable getter need not be equivalent.
  Clean and restored baselines pass. This is only the
  authorization file and the declared AST operator set, not all router behavior.
- Full authentication-server mutation inventory: 294 generated, 181 killed,
  105 compile errors, eight survivors, no timeouts/errors and passing clean and
  restored baselines. Raw score 95.77%, no equivalent exclusions. CI runs this
  whole-package inventory as a gate. Remaining survivors cover cleanup guards,
  empty method-list guards and reserved RPC options; retain them for review.
- Base64 VM inventory: 269 generated, 218 killed, three compile errors and 48
  survivors (81.95%). Chrome inventory before the final short-input test:
  216 killed, three compile errors and 50 survivors (81.20%). The final short-input
  test also passes Chrome. SDK-fallback/performance-path equivalents need proof,
  not blanket waivers. Both inventories remain below the mutation target.
- RawSocket regression additions cover all serializer/size negotiation pairs,
  malformed and truncated handshakes, file offsets and backpressure. The complete
  macOS mutation pass reports 82 caught, 26 missed, five unviable and ten timed out
  of 123 mutants. Linux-only branches remain visible; no exclusions or passing
  native mutation claim are made. LLVM transport-workspace tests pass, but the
  raw report includes inline unit-test bodies and is not a production percentage.
- Coverage-tool regression tests reject missing measured files, non-library
  coverage inflation, empty reports and rounded-up floors. Mutation-runner tests
  cover baseline failures, restoration, process-group cleanup, compiler/runtime
  error classification, empty target configuration, UTF-16 offsets and
  equivalent-mutation validation.

The next independent source slices are MCP/Streamable HTTP, client session and
native-runtime boundaries, router state/FFI/configuration, and benchmark tools.
More than 6,200 measured VM lines remain uncovered, besides unmeasured scopes.
Keep this plan active; reaching the complete target requires substantially more
regression and mutation work. No new release or hosted evidence is claimed.

### MCP And MessagePack Follow-Up

- Hosted master `f3323e48` has green CI `34962388214`, publish dry-run
  `34962388215`, and WAMP benchmarks `34962388212`. These verify the merged
  baseline, not the current uncommitted coverage changes.
- A silent UDP peer regression proves the native HTTP/3 test client previously
  outlived an eight-second observation window. Its ffi-test-only handshake now
  has a five-second deadline, before the outer Dart timeout destroys the
  listener. The regression fails before and passes after the change; all five
  native HTTP/3 integration cases pass. Diagnostics identify method, path
  without query, and port. This fixes the unbounded test-client diagnostic gap,
  not the still-unproven original intermittent handshake cause.
- MessagePack regression coverage now exercises scalar wire types, every
  truncated prefix, bounded subviews, collection header transitions, exact
  integer limits, nonminimal encodings and JavaScript fallback diagnostics.
  Core browser coverage is 4,345/5,201 (83.54%) with 381 passing tests; the
  MessagePack codec is 180/185 (97.30%). Native/WASM versus JavaScript error
  behavior is explicitly tested rather than hidden behind broad assertions.
- The first complete MessagePack Chrome inventory has 234 mutations: 173
  killed, nine compile errors and 52 survivors (76.89% viable kill rate).
  Clean and restored baselines pass; no equivalences are waived. A fresh full
  inventory with distinguishing boundary tests completed with 193 kills,
  nine compile errors and 32 survivors (85.78%), zero timeouts/errors and
  passing clean/restored baselines. Twenty additional kills are verified;
  no passing 95% claim is made.
- Real-Session MCP tests cover RPC options/results, acknowledged and
  unacknowledged publishing, retained event metadata, final-owner cleanup and
  shared subscription ownership. A queued RPC reply provides deterministic
  event-delivery synchronization without sleeps. They exposed WAMP errors
  rendered as `Instance of 'Error'`: the delegate now returns the error URI
  only, never private error payloads. Immediate/asynchronous failures, null
  URIs, timeouts and non-WAMP failures have distinguishing tests.
- All 154 MCP package tests pass. Their measured VM library slice is now
  1,586/1,615 (98.20%), with registry replacement/cursor invalidation, malformed
  public requests, handler non-dispatch, metadata and capability consistency
  assertions. The large `src/cli/router_hosted_client.dart` executable is still
  unmeasured; this percentage is not whole-component completion. The full MCP
  mutation target includes that file and has 2,274 mutations. Its initial
  inventory is running; CLI survivors already confirm this scope needs tests.
- Fresh `bin/test-fast`, MCP analysis and full `bin/verify` pass, including
  native HTTP/3, 374 WASM core tests and two WASM WebSocket tests. The separate
  browser coverage command passes 381 JavaScript core tests. Local full
  verification selects WASM; hosted Linux selects JavaScript. A new full VM
  coverage collection started only after verification completed and passed:
  33,891/40,033 (84.66%), with 6,142 uncovered measured lines and 61 unmeasured
  library files. Package counts: core 6,359/7,211; client 7,843/9,234;
  router 15,862/19,268; MCP 1,586/1,615; authentication-server 455/455;
  benchmark tools 1,786/2,250. The MCP measured floor is now enforced at 98%.
- The strict deployment audit's exact job contract now includes browser
  coverage and both mutation gates. A regression fails before the contract
  update and passes after it; all 24 deployment-audit tests pass.
- A local review identified signal-terminated mutation processes incorrectly
  counted as kills when they emitted failure JSON before crashing. A regression
  reproduces the flaw; the runner now classifies negative process exit codes
  as infrastructure errors and retains baseline/mutant/restored exit codes.
  All 12 runner regressions pass. Live inventories started before this guard;
  preserve them as diagnostic evidence rather than final gate certification.

Evidence is retained in `out/regression-coverage-2026-09-15/vm-follow-up/`,
`mcp-slice/`, `browser-msgpack-slice/`, and both MessagePack mutation directories.
Next: complete the live MCP inventory, test the CLI and surviving MCP paths,
investigate MessagePack survivors, and obtain hosted evidence for this candidate.
The near-complete repository-wide goal remains active and unmet.

### Hosted Mutation Gate Repair

- Coverage commit `d5ecb305` is pushed in draft PR #93. CI `34982430544`
  exposes a platform-dependent authentication mutation failure: 163 kills,
  105 compile errors, 18 timeouts and eight survivors (86.24%). Its clean and
  restored baselines pass. Linux discovers the lifecycle suite first, while
  macOS discovers a different first suite; fail-fast exposed callback-entry
  waits after mutations had already returned a failed authentication result.
- Callback-entry waits now race the operation and explicitly fail on premature
  completion or error. Four helper regressions cover early result/error and
  late losing-future settlement. An isolated replay of hosted timeout mutant
  `91fe47c65d6b4db125ff` now reports an assertion kill, not a timeout.
- Mutation commands expand directory targets into sorted `*_test.dart` paths
  and retain `resolvedTests`/`testCommand`. Supporting Dart helpers remain
  hashed. A reproduced-before runner regression checks stable execution order;
  another preserves timeout classification even alongside an assertion failure.
  No timeout increase, retry, scope reduction or timeout-to-kill conversion is
  involved. All 14 runner tests pass.
- Reentrant abort/close cleanup and transaction-ID reuse regressions assert
  single cleanup and capacity ownership. Custom service-admission validation
  receives options only, never HELLO/AUTHENTICATE/abort envelope fields. This
  distinguishes reserved-key filter mutant `c6b2da97818fe62e5d41`. All 84
  authentication tests pass; the complete fresh 294-mutant inventory records
  182 kills, seven survivors and 105 compile errors, with clean/restored
  baselines, zero timeouts/errors and 96.30% raw/adjusted score. No new
  equivalences were added. Remaining cleanup/selection guards stay unwaived;
  the added reentrancy tests do not distinguish those redundant-looking guards.
- MessagePack JavaScript tests now assert precise errors at minimal incomplete
  collection and 64-bit integer boundaries. All eight JS fallback tests pass;
  the complete 234-mutant browser inventory has 197 kills, 28 survivors and nine
  compile errors (87.56% raw/adjusted), with clean/restored baselines and zero
  timeouts/errors. Four new kills are verified, but the target remains unmet.
  This inventory started before deterministic test ordering; retain it as
  diagnostic evidence. The larger MCP inventory remains live and diagnostic.
- `bin/test-fast` passes after correcting an initially wrong expected abort
  URI in a new test; full `bin/verify` also passes, including native HTTP/3,
  all 84 auth tests, 374 Chrome WASM core tests and two WASM WebSocket tests.
  Repair `e2f488f7` is pushed to PR #93. New CI `34985212120` is running with
  green browser coverage, both mutation gates and package dry-run
  `34985212069`. The hosted authentication artifact confirms 182 kills, seven
  survivors, 105 compile errors, zero timeouts/errors and 96.30% raw/adjusted,
  with passing baselines. Full hosted verification and strict candidate audit
  remain pending. The HTTP/3 reliability
  issue is not claimed fixed by successful repetitions or this CI repair.

Evidence: `out/regression-coverage-2026-09-15/auth-gate-repair/` retains the
hosted failing inventory, local inventories, exact-mutant replay and runner
before/after logs. `msgpack-web-boundary-mutations/` retains the new complete
browser inventory. The full coverage goal remains active.

### Public MCP CLI Measurement

- Added 199 no-network option regressions and 26 real HTTP CLI tests. They use
  the public entrypoint, never private parser calls. Exact transcripts cover
  optional payload defaults, auth combinations, Unicode/control boundaries,
  secret non-disclosure, discovery, two-page tool/resource/template/prompt
  catalogs, exhausted/repeated cursors, malformed raw method catalogs, tool
  errors, explicit/discovered ticket grants and mismatched grant identities.
  Only the option suite owns process-wide `exitCode`, avoiding interference
  between independently scheduled test files. All 379 package tests pass.
- The previously unmeasured CLI has 2,291 executable lines. These tests cover
  463 (20.21%); whole measured MCP is 2,049/3,906 (52.46%). The existing
  1,586/1,615 library slice still measures 98.20%. Preserve its 98% floor as an
  explicit exact-source cohort instead of claiming that the old percentage
  covers the CLI. The CLI now has a 20.2% floor and required-source entry.
  All lines remain in package/overall totals; no library or CLI lines are
  excluded. Every measured MCP source must belong to exactly one component;
  omitted new files and duplicate ownership fail closed. Cohort regressions
  reproduce missing-source/invalid-policy/unassigned-source false passes
  before the checker updates; all eleven checker tests pass afterward.
- The union of the last completed full VM report and this new MCP slice is
  34,354/42,324 (81.17%), with 7,970 uncovered measured lines and 60 unmeasured
  library files. The lower percentage exposes new scope rather than lost
  coverage. The subsequent fresh, serialized full VM run passes at
  34,337/42,324 (81.13%), with 7,987 uncovered measured lines. That fresh
  single-run result supersedes the union. Client session/socket error paths
  and router native HTTP stream cleanup differ between passing collections;
  add deterministic regressions rather than treating merged hits as stable
  execution. Fresh package counts: core 6,359/7,211; client 7,835/9,234;
  router 15,853/19,268; MCP 2,049/3,906; auth 455/455; bench 1,786/2,250.
- Replayed twelve individually selected CLI survivors in an isolated current
  workspace. Eleven now fail tests; one is a compile error after the CLI is
  actually imported. Clean/restored baselines pass; no timeouts/errors or
  equivalences. Retain the full definitions, source/test hashes and logs.
  This is diagnostic survivor investigation, not a full-scope mutation score.
  Do not restart the older live 2,274-mutant inventory merely because it is slow.
  After it finished its CLI portion, started the separate complete `mcp-cli`
  target (1,179 mutants) against the new tests. Its clean baseline passes;
  the complete CLI score remains pending, with no sampled-score substitution.
- CI `34985212120` and package dry-run `34985212069` pass for prior candidate
  `e2f488f7`. Its required CI/log/publish-dry-run audit passes. The non-release
  branch remains unprotected, and the new manual diagnostic workflow is not
  yet discoverable on the default branch; no strict release readiness claim.
  These hosted results do not cover the new CLI tests.
- Fresh `bin/test-fast` and `bin/verify` pass, including native HTTP/3 and
  Chrome WASM. The final five auth tests and test-helper isolation adjustment
  also pass in the focused 379-test package run. Native HTTP/3's original
  handshake cause remains unproven; package test configuration already uses
  concurrency one, so overlapping package test files do not explain it.
- CLI checkpoint `5fa96e89` is pushed to PR #93. Final-state `bin/verify`
  started only after full VM collection finished. It and hosted CI
  `34990192211` plus package dry-run `34990192207` are running. Required
  candidate audit for this commit remains pending; no merge/publication.

Evidence is retained under `out/regression-coverage-2026-09-15/mcp-cli-entrypoints/`.
Next: finish the diagnostic MCP inventories, verify this candidate in hosted
CI, and extend CLI coverage to compatibility sessions,
metadata, pub/sub and auth lifecycle operations. Continue the remaining native,
browser, client/router and consumer scopes; neither target is complete.

### HTTP/3 Cleanup And Early Closure Regressions

- Final-state verification for `5fa96e89` reproduced the intermittent native
  handshake failure on POST `/mcp/secure` in the protected direct JSON test.
  This happened without an overlapping full native verification/coverage run.
  Do not attribute it to shared-runtime contention or call passing retries a fix.
- A new FFI regression first failed waiting for a peer close event after a
  successful response. The per-request Tokio runtime was dropped before QUIC
  could notify its server. The helper now sends H3_NO_ERROR and awaits endpoint
  draining, bounded at two seconds, before runtime destruction, on success and
  error paths. It preserves the original request error and never reports success
  when successful-request draining exceeds its bound. The existing five-second
  handshake deadline and silent-peer eight-second observation bound are unchanged.
- Cleanup exposed a production classification bug: a normal peer close during
  HTTP/3 builder setup was always recorded as ProtocolError. The early return
  now uses the typed H3_NO_ERROR predicate. Deterministic native tests close the
  QUIC peer before invoking HTTP/3 setup, then assert Graceful for H3_NO_ERROR
  and ProtocolError for H3_INTERNAL_ERROR, zero requests/timeouts, exactly one
  close event, and released registry ownership. Disabling the new predicate
  reproduces the assertion failure; the error control still passes.
- These choices follow [RFC 9114 section 8.1](https://www.rfc-editor.org/rfc/rfc9114.html#section-8.1)
  and [Quinn's endpoint drain contract](https://docs.rs/quinn/0.11.11/quinn/struct.Endpoint.html#method.wait_idle).
  This is a lifecycle/observability fix, not proof of the original intermittent
  handshake cause. Conditional ffi-test traces now correlate local/remote
  endpoint addresses, handshake timing, and pending admission counts, without
  headers or payloads in the new diagnostics.
- Both deterministic setup tests and both FFI deadline/cleanup tests pass.
  All 77 native router integration tests pass with debug traces. Fresh
  `bin/test-fast` and final `bin/verify` pass, including 671 router tests,
  isolated remote-auth integration and Chrome WASM checks. The previous
  candidate's CI `34990192211` and package dry-run both pass. Its Linux VM
  artifact measures 34,345/42,324 (81.15%), with 60 unmeasured library files;
  retain it separately from the local 34,337/42,324 measurement.
- The separate full 1,179-mutant CLI inventory has now completed with 221 kills,
  631 survivors, 327 compile errors, zero timeouts/errors, and passing clean and
  restored baselines. Raw/adjusted score is 25.94% over 852 viable mutants, with
  no equivalences. The five operator families are binary, nullFallback, boolean,
  negation and condition. Source and both test hashes match the worktree; the
  report retains its actual pre-commit provenance rather than rewriting it.
  The complete report and per-mutant logs are retained under the preceding
  MCP CLI evidence directory. This does not replace the still-running older
  full MCP diagnostic snapshot or establish a passing CLI mutation gate.
- Native fixes are pushed as `d097afaf` to draft PR #93. Package dry-run
  `34992820507` passes; current CI `34992820252` is running, so the required
  candidate CI/log/publish-dry-run audit remains pending. No merge/publication.

Evidence: `out/regression-coverage-2026-09-15/http3-cleanup/` retains the failing
verification, reproduced assertions, focused passing tests, and router traces.
The complete coverage goal remains active; no new whole-component score is
claimed from these focused regressions.

### Public CLI Integration And Signal Cleanup

- Nine new Dart integration tests run the public CLI in the coverage process
  against the real public router example in a child. They cover 2025-03-26 and
  2025-06-18 compatibility, protected SSE and JSON-response routes, authenticated
  session deletion, WAMP metadata, pub/sub and resource notifications. Modern
  ticket/WAMP-CRA/SCRAM flows verify refresh, request-scoped resource updates,
  revocation and sessionlessness; wrong-realm/unprotected auth discovery fails
  closed. The standalone MCP package tests remain native-independent.
- Initial teardown required SIGKILL after a successful SIGTERM request. An
  independent stuck example exited immediately when subsequently sent SIGINT:
  Future.any did not cancel the untriggered signal stream. The example now
  registers both listeners before readiness and explicitly cancels them on
  shutdown. Both normal SIGTERM and SIGINT exit-zero tests pass. The fixture
  registers idempotent cleanup before awaiting readiness, bounds termination,
  and serializes children because NativeTransportRuntime uses an OS-wide lock.
- The integration-only coverage run measures 1,932/2,291 CLI lines (84.33%).
  The subsequent fresh combined 234-test CLI run passes at 2,060/2,291 lines
  (89.92%), leaving 231 uncovered lines and raising its regression floor to
  89.9%. This is not a fresh whole-workspace score; full collection remains
  required to validate the candidate before push.
- `mcp-cli-native` declares all 1,179 CLI mutants, both CLI unit-test files and
  the router integration test. It records support-file and native-artifact
  hashes; missing native inputs fail instead of skipping. Native bytes must
  remain unchanged through the restored baseline. Run it with
  `CONNECTANUM_MUTATIONS_NATIVE=1 bin/test-mutations --target mcp-cli-native --output <fresh-directory>`.
  The manual diagnostic workflow includes this target. Its complete execution
  is pending; the inventory alone establishes no score. Keep it serialized
  with full native verification and coverage collection.
  The example-only SIGINT regression lives in a separate lifecycle test file:
  full verification includes it, but CLI mutation scoring does not credit
  failures in unrelated example code. The shared child fixture is hash-recorded
  as a support file. Repeat combined collection after this helper extraction.
- Mutation-runner tests reproduced suite setup/teardown failures classified as
  kills. Such failures now remain infrastructure errors. Eighteen runner tests
  pass, including support hashes, native input validation, configured test
  deadlines and changed-artifact rejection with incomplete evidence.
- The older complete MCP diagnostic run finished at 659 killed, 1,349 survived,
  262 compile errors and four timeouts (2,012 viable; 32.75% raw/adjusted; no
  equivalences). Its clean/restored baselines pass. This snapshot predates the
  latest CLI tests and runner guards. The four timeout mutants force the null
  validation guards at wamp_api.dart lines 1766, 1777, 1790 and 1813 false;
  the publish test awaited a message even after an error result. Assert success
  before a same-stream WAMP barrier and inspect the recorded publish instead.
  All six session bridge tests pass; isolated replay of those four exact
  mutants produces four assertion kills, no timeouts/errors, and passing
  clean/restored baselines. The replay records its four-mutant diagnostic scope
  explicitly; it is not a new complete MCP score.
- Prior candidate d097afaf passes all seven hosted CI jobs (34992820252),
  package dry-run 34992820507, and the required candidate audit. The new code is
  not yet covered by that hosted result. Fresh `bin/test-fast` passes and final
  `bin/verify` is running. Full VM collection and the native CLI mutation target
  must follow serially, not overlap the native runtime lock.

Evidence is retained under `out/regression-coverage-2026-09-15/mcp-cli-live/`.
Continue toward the full original coverage and mutation targets; no completion
or release readiness claim is made from this checkpoint.

### HTTP/3 Address-Family Collision

- The previous full verification failed again at the protected MCP HTTP/3 GET.
  A 50-attempt diagnostic group stopped at its first failure, attempt 16;
  the server received the client's Initial with zero pending admissions. A
  second instrumented group also stopped at attempt 16: server replies were
  successfully sent but the dual-stack client received no datagrams. Another
  IPv4 socket owned the same local port. Neither increased timeouts nor passing
  retries establish a fix for this failure.
- An independent, test-owned socket probe reproduces the macOS collision:
  an IPv4 wildcard bind and a dual-stack IPv6 bind can share a port, but IPv4
  replies reach the original IPv4 owner. Binding the client in the destination's
  address family rejects that occupied port with AddrInUse instead.
- `http3_test_client_bind_addr` now selects IPv4/IPv6 unspecified addresses from
  the peer address. The FFI test request client and all eight Rust HTTP/3 test
  clients use it. The deterministic family-selection and occupied-port tests
  both fail before and pass after the change. All four focused FFI tests pass,
  including the unchanged silent-peer deadline and endpoint-draining regressions.
  This helper matrix does not claim complete FFI IPv6 host-parser coverage.
- Temporary UDP instrumentation is removed and the optimized ffi-test artifact
  rebuilt from the fixed source. Fresh `bin/test-fast` and `bin/verify` pass.
  Full verification includes 152 ffi-test cases, 680 router tests, isolated
  remote auth, zero-copy, 374 core WASM tests and two WebSocket WASM tests.
- Fresh full VM collection, serialized after verification, passes at
  35,930/42,324 lines (84.89%), leaving 6,394 uncovered measured lines and 60
  unmeasured library files. MCP is 3,646/3,906 (93.34%); CLI coverage remains
  2,060/2,291 (89.92%) after fixture extraction and validates the 89.9% floor.
  Authentication is 455/455; core 6,359/7,211; client 7,843/9,234; router
  15,841/19,268; bench 1,786/2,250. No favorable union with older runs is used.
  The original per-component/runtime and mutation targets remain unmet.
- A new runner regression launches actual Dart reporter fixtures rather than
  relying solely on synthetic events. Healthy tests survive, assertion failures
  kill, suite setup/teardown failures and abrupt exits remain infrastructure
  errors, and test timeouts remain timeouts. A teardown failure overrides an
  earlier assertion kill. All 19 runner regressions pass; the local companion's
  speculative fixture-misattribution concern did not reproduce on this reporter.

Evidence: `out/regression-coverage-2026-09-15/http3-address-family/`, including
both stopped diagnostic groups, temporary instrumentation source, the standalone
socket repro and before/after regression logs. Never stop another application
or alter its sockets to work around this failure.

Next: push this verified checkpoint, run the complete `mcp-cli-native` target
into `out/regression-coverage-2026-09-15/mcp-cli-native/`, and inspect hosted
CI/audit evidence. Do not rebuild or replace its hash-pinned native library
while mutations run. Client `test/hook` is another concrete coverage gap:
existing installer/build-hook tests are omitted from the root test and VM
coverage commands. Measure and integrate them next, retaining hook/tool entry
points separately from the current library-only collector scope.

### Mutation Cleanup And Packaging Coverage

- The native CLI inventory at 129c2eda was stopped at 24/1,179 outcomes (16
  kills, eight infrastructure errors). Dart fail-fast skipped fixture teardown
  and orphaned a router holding the shared native runtime lock. Only that
  verified, test-owned orphan was terminated. Keep the incomplete inventory as
  diagnostics, not a score. A real subprocess regression fails before the runner
  cleanup fix: apparent success/failure leaves a live listening child. The runner
  now reaps owned process groups on ordinary exit and flags descendants as
  infrastructure errors. Native suites run per file without internal fail-fast,
  with independent reporter IDs and one unchanged whole-mutant deadline.
- Four formerly problematic mutants replay with three kills and one survivor,
  clean/restored baselines, unchanged native artifact and no timeouts/errors.
  All 23 runner regressions pass, including explicit packaging source validation
  without admitting test paths or traversal. The full native CLI rerun remains
  pending until full verification/VM coverage finish; no native rebuild may
  overlap its pinned-artifact campaign.
- Full verification exposed an unguarded JSON binary-buffer test accessing the
  global message store while neighboring tests shut it down. The observed -14
  invalid-handle failure is not accepted as fixed by the script's automatic
  retry. Add the shared test_guard, and use CONNECTANUM_CARGO_RETRY_ATTEMPTS=1
  for the next full confirmation. An intermediate verification was also
  invalidated by editing its shell script while it was executing; rerun on a
  stable tree, never report that interrupted command as passing.
- Existing test/hook was absent from test-fast/test-all/test-coverage. A script
  regression fails before and passes after integrating those suites. Coverage
  now has separate library and packaging source scopes; tests, traversal and
  nested test/lib paths cannot enter either metric. The packaging inventory
  retains absent bin/hook/tool files. Policy-scope mismatch and omitted measured
  entry points fail closed. All 14 coverage-checker tests pass.
- Eighteen new tests exercise both release installers. A real loopback HTTP
  truncation reproduces partially downloaded archives left at the final cache
  path. Stage each transfer in a unique sibling directory, close the complete
  stream, then rename. Both archive and checksum interruption now preserve the
  prior installed library, clean temporary state, close clients, and allow retry.
  Checksum rejection, corrupt tar, missing library and interrupted extraction
  also have independent expected errors and output-preservation assertions.
- All 52 hook/installer tests pass. Focused library installer coverage is
  116/122 (95.08%), versus 84/117 (71.79%) before new tests. Packaging coverage
  is separately 297/400 (74.25%): build hook 245/348 (70.40%) and install CLI
  52/52 (100%), with 14 missing packaging entry points. Fifteen CLI regressions
  distinguish help/usage output, exact exit codes, environment/argument
  precedence, output paths and cached success without network access. Floors
  are 95%, 70.4% and 98% respectively, not whole-goal completion. The collector and
  hosted artifact upload retain separate packaging LCOV and JSON summaries.
- The complete 105-mutant client-installer target includes the library installer
  and install CLI, not the duplicated build-hook implementation. Its first run
  reports 58 kills, 43 survivors and four compile errors, 57.43% raw/adjusted,
  no equivalences/timeouts/errors and passing clean/restored baselines. CLI
  survivors guided the fifteen additional tests. The complete rerun has 97
  kills, four survivors and four compile errors: 96.04% raw/adjusted, no
  equivalence exclusions, no timeouts/errors and passing clean/restored baselines.
  Operator scope remains binary, nullFallback, boolean, negation and condition;
  this is not a claim about ungenerated statement-deletion mutations. All four
  survivors are in the library, not the CLI: recursive create flags at lines
  117/128/201 and the arm64 host condition at 162. Parent creation earlier in the
  flow explains the directory flags' ordinary-path survival, but unusual
  filesystem/provider interleavings have not been proved equivalent. The host
  condition requires other-platform evidence. Keep all four unwaived. Checksum,
  HTTP-status and CLI-input guard mutants are killed in this declared inventory.
  CI and the candidate audit now require the client-installer mutation gate.
- Both router installers contain the same duplicated HTTP downloader. Mirrored
  regressions fail before their fix and all 30 router hook/installer tests pass
  after it. Library coverage is 105/111 (94.59%); packaging-only hook coverage is
  228/331 (68.88%) and router install CLI 22/52 (42.31%). Preserve these independent
  counts; router installer mutation evidence is still missing. Focused analysis
  of both packages' changed code/tests passes. The collector protects each
  measured installer/hook/CLI with a separate floor, and the final full report
  must retain the newly measured sources rather than union favorable checkpoints.
- CI 35003806341 and publish dry-run 35003806383 pass for 129c2eda. They do not
  cover this follow-up. Fresh bin/test-fast passes with Cargo retries disabled.
  Final bin/verify also passes with the same no-retry setting: 698 router tests,
  isolated remote auth, zero-copy, 374 core WASM tests and two WebSocket WASM
  tests. All 24 updated deployment-audit regressions pass separately. The fresh
  full VM/packaging collector passes after verification completed: 36,084/42,451
  VM lines (85.00%), 6,367 uncovered measured lines and 59 unmeasured library
  files. Separate packaging coverage is 547/783 (69.86%), with 12 unmeasured
  entry points; client is 297/400 and router is 250/383. Reports are retained in
  out/regression-coverage-2026-09-15/vm-current9. Branch push and candidate hosted
  audit remain required; the complete-scope coverage goal remains unmet.

### Linux Mutation Process-State Regression

- CI 35010146390 for 3f87906e fails all three mutation gates at clean baseline.
  Their retained JSON logs end with success=true followed by the runner's orphan
  marker. Linux killpg succeeds even when only unreaped zombies remain. A
  Linux-only child-subreaper test retains a confirmed Z-state descendant and
  reproduces the false error without sleeps or Dart-specific assumptions.
- The runner now records live process-group members before signaling; Z/X states
  are already terminated, while sleeping, running, blocked and stopped fixtures
  still invalidate the result. Census failures remain infrastructure errors.
  Four deterministic Linux regressions pass, including killing a real listening
  orphan and preserving failed-test versus successful-test classification for
  zombie-only groups. CI must validate the repaired runner before starting new
  native mutation evidence. No timeout or coverage threshold was relaxed.

### Build-Hook Execution And Router Installer

- Extract each hook's native operation into buildNativeAssets without changing
  its body. runBuildHook still uses the SDK build wrapper for error reporting and
  process exit; tests can now assert operational BuildError behavior directly.
- Thirty-one new tests per package check supported artifact names, unsupported
  targets, no-code-asset builds, numeric/string/bool skip settings and precedence,
  dependency inventory, optional source directories, cache timestamps including
  equal-mtime rebuilds, missing native input/workspace/output, Cargo errors and
  preservation of installed bytes. An owned shell fixture verifies the default
  POSIX Cargo invocation and environment, not a real Rust build. Windows execution
  is not established by that smoke. Existing SDK-wrapper tests still pass.
- Fifteen router install CLI tests cover 52/52 executable lines. Focused packaging
  collection passes the raised floors: client 381/402 (94.78%) and router 364/385
  (94.55%); hooks are 329/350 and 312/333, each CLI 52/52. Twelve other packaging
  sources remain unmeasured. Keep these per-package results separate from full VM
  coverage. A combined concurrent diagnostic fails due to existing process-wide
  cwd and exitCode tests; canonical per-package collection succeeds.
- Add a complete router-installer mutation target. First inventory: 93 killed,
  six survivors, four compile errors out of 103. A real-tar success test with
  spaced paths kills the unconditional extraction-error mutation. Complete rerun:
  94 killed, five survivors, four compile errors, 94.95% raw/adjusted, passing
  clean/restored baselines and no timeouts/errors. No equivalences are waived.
  Remaining IDs: f4b38e0eaca32083e0c9, d96fb05dfb182a9081db, 667cec0ca8602056d235
  (recursive directory creation), d506118233042e426142 (arm64 host condition),
  3a8c9e037148ff700121 (shell invocation). Linux x64 evidence is still pending.
  Do not round 94.95% into a passing result or require this gate without evidence.
- bin/test-fast and final bin/verify pass with Cargo retries disabled, including
  745 router tests, isolated remote authentication, zero-copy, 374 core WASM and
  two WebSocket WASM tests, before any native campaign. Focused analysis, formatting, 14 coverage
  checker tests and 26 mutation-runner tests pass (Linux-specific case tested in
  an owned container). Reports/logs are retained under packaging10 and complete
  router-installer10 / router-installer10b directories.
- For repair 0c1170ea, CI 35010985044 has passing Fast Checks, browser coverage,
  consumer app and all three mutation gates; Full Verify / VM Coverage are still
  running. Package dry-run 35010994084 passes. Final follow-up hosted evidence and
  a fresh native CLI inventory remain required. The overall goal is still unmet.

### Packaging Isolation And Linux Evidence

- Reproduce concurrent hook fixtures sharing a real package root, and concurrent
  CLI tests swapping exit codes (observed [64, 0] instead of [0, 64]). Use owned
  temporary package roots and zone-local cwd; remove deletion of real checkout
  caches. Separate command status from main's process-global exitCode. Keep real
  subprocess checks for exit codes 0/64/1 and stdout/stderr, with an on-disk
  verified archive/extraction cache and no external download dependency.
- Add failed-rename staging cleanup, default installation location, unsupported
  target and source-deletion-before-Cargo-launch regressions. The latter checks
  InfraError, its ProcessException cause/trace, no emitted assets and preservation
  of installed bytes. Mark the POSIX Cargo fixture explicitly non-Windows instead
  of silently passing there. An initial entrypoint test incorrectly assumed skip
  overrides a configured native library; reproduce with canonical native env and
  correct the test to use a no-code-assets input, without changing precedence.
- The earlier Linux x64 router inventory completes below target: 93 killed,
  six survivors, four compile errors / 103, 93.94%, passing baselines. Merely
  changing hosts swaps architecture survivors. Extract the unchanged version
  string decision into a pure helper and test x64, arm64 and aarch64 independently
  in both installers and hooks. No survivor is waived or rounded into a pass.
- Fresh complete macOS inventories: client 98 killed, three survivors, four
  compile errors / 105 (97.03%); router 95 killed, four survivors, four compile
  errors / 103 (95.96%). Fresh Linux router independently matches 95/4/4. Raw and
  adjusted scores are identical, no equivalences, timeouts or infrastructure
  errors, clean/restored baselines pass. Add router-installer to the CI matrix
  and exact deployment-audit job contract. Retain complete per-mutant/operator
  records in installers11-macos and router-installer11b-linux.
- The new nine-job audit contract fails before the audit recognizes the router
  installer job, then all 24 deployment-audit regressions pass after the change.
  All 14 coverage-checker regressions, focused static analysis and formatting pass.
- 184 focused tests pass on both macOS arm64 and Linux x64; macOS also passes
  with the canonical native-library environment. Focused packaging reports:
  macOS client 391/402 and router 374/385; Linux client 388/402 and router 371/385.
  Each CLI covers 53/53 lines. Hook floors increase to Linux-proven 95.9% / 95.7%,
  below the unchanged 98% goal. Twelve other packaging sources are unmeasured.
  Do not combine per-platform coverage to conceal platform gaps or replace the
  full VM report with these focused measurements. Reports/logs are retained in
  packaging11-macos and packaging11c-linux.
- CI 35010985044 for 0c1170ea passes Full Verify but fails its packaging floors:
  Linux executes different OS/architecture branches from the original macOS
  measurement. The new Linux reports pass stronger floors; do not lower them.
  For e8a697bc, CI 35012835384 passes Full Verify and existing mutation gates;
  VM Coverage is still running, package dry-run 35012835188 passes.
- The native CLI inventory mcp-cli-native10 remains live with its original
  hash-pinned native library. Latest full bin/test-fast/bin/verify passed before
  these edits; fresh full local verification, candidate hosted CI and deployment
  audit remain pending. Serialize them after that inventory; never rebuild the
  library or start a duplicate campaign just because observation times out.
  The complete regression/mutation goal remains unmet.

### Native Production Coverage Accounting

- Add a standalone, locked syn/proc-macro2 analyzer in tool/rust_coverage_scope,
  with its own Cargo target outside the native transport build. Parse Rust AST
  scopes rather than matching braces or test filenames. Treat test and ffi-test
  as disabled for the release scope; unknown platform/feature predicates remain
  candidates, not exclusions. Keep each exclusion's source range and reason.
- Resolve external modules through the parsed graph, including inline modules,
  explicit paths and files reachable from both test and production contexts.
  Refuse orphaned/ambiguous modules, opaque source generation, unsupported inner
  scope attributes and measured lines shared between test and production tokens.
  Parse tokio::select futures/guards/handlers as Rust expressions instead of
  excluding its entire production macro body. Production macro definitions need
  a local production invocation; test-only invocation cannot establish scope.
- Snapshot source/build-input hashes before collection, check them afterwards,
  and require the same analyzer and reconstructed scopes. Preserve raw LCOV;
  filtered output recalculates executable-line totals and does not carry stale
  function/branch percentages. Report per-crate totals, exclusion lines and every
  unmeasured candidate source separately. Current graph: 35 Rust sources,
  22 production candidates / 13 test-only, 39 hashed source/build inputs.
- Adversarial tests found and fixed three accounting errors during development:
  statement semicolons outside expression spans, blank/comment LLVM regions
  inside excluded bodies, and #[path] modules resolving children relative to the
  containing directory rather than an inferred file-stem directory. A rustc
  regression proves the path rule. Real cargo-llvm-cov on an owned fixture leaves
  only its three production lines, excluding inline/external test bodies and its
  ffi-test-only helper. This fixture does not touch the transport runtime.
- Eleven Rust tests, 13 Python tests including the real LLVM fixture, and 28 script
  contract tests pass. Clippy with warnings denied, rustfmt, shell syntax and
  Python compilation pass. The tool regression gate is in bin/test-fast and
  bin/test-all; bin/test-native-coverage runs the real LLVM fixture before its
  source snapshot, transport collection and production filtering.
- No fresh native component percentage or completed mutation score is claimed.
  The earlier raw native report lacks matching source hashes and is not reused.
  mcp-cli-native10 is still live with its unchanged hash-pinned ct_ffi artifact.
  Full local test-fast, verify and fresh native collection are queued in that
  order after it; evidence will be retained under native-scope12. New tooling
  changes stay uncommitted until verification is available. For pushed 9954fc32,
  CI 35016060507 is now fully green, including VM Coverage and all four mutation
  gates; publish dry-run 35016060485 and the relevant clean-CI/logs/package audit
  pass. These do not verify the uncommitted candidate. The complete coverage and
  mutation goal remains open.

### E2EE Payload And Benchmark Configuration

- Pure-Dart E2EE regressions reproduce out-of-range key/ciphertext integers
  silently narrowed by Uint8List conversion, key-array retention in invalid-length
  errors, and raw parser exceptions escaping authenticated malformed CBOR.
  Validate and copy each list byte once, retain only key length in diagnostics,
  and normalize invalid plaintext envelopes without retaining parser exceptions.
  Valid formats remain covered by both ciphers' roundtrips and independent
  OpenSSL-backed AES-GCM fixtures, including authenticated empty plaintext at
  exactly the nonce-plus-tag boundary. Narrowing is invalid-input acceptance,
  not evidence of a cryptographic authentication bypass.
- Add field-by-field context copy/clear tests, policy precedence/short-circuit
  checks, trust/URI/auth-identity constraints, malformed input, nonce/tag/data
  tampering, wrong-key failures, ownership and helper forwarding. Defer context
  factories to test bodies so mutations do not abort suite registration.
- Fresh focused line reports: VM 292/295 (98.98%), JavaScript 341/344 (99.13%).
  Seventy tests pass independently on VM, JavaScript and WASM; WASM runtime test
  success is not a measured WASM line-coverage claim. The complete core VM suite
  passes 665 tests. No production lines are removed from the denominator.
- The first 269-mutant VM inventory passes at 209 kills / 214 viable (97.66%),
  five survivors and 55 compile errors. Investigate the missing-identity guard:
  a public List can override contains(null), so its removal is distinguishable,
  not equivalent. Add the adversarial role-list test. The fresh full inventory
  e2ee14c-vm-mutations has 210 kills, four survivors, 55 compile errors, no
  timeouts/errors, clean/restored baselines and raw/adjusted 98.13% scores.
  Remaining survivors are the empty-context fast path, two private-list
  growability flags and the Uint8List fast path; none is waived as equivalent.
  Per-operator outcomes and input hashes are retained in the complete reports.
- The separate full e2ee14-js-mutations campaign is still live on the 69-test
  snapshot. Preserve it, retain its test/source hashes and inspect the completed
  report before claiming a browser mutation score. The added missing-role test
  independently passes on both browser compilers. Browser mutation remains a
  diagnostics target rather than an unproven required CI gate.
- Benchmark configuration regressions cover invalid document shapes and map
  keys at every tested depth, required-field types, numeric coercion, duration
  parsing/formatting boundaries, optional-field omission, shallow extra-map
  ownership, declaration order and JSON/YAML roundtrips. No parser policy change
  is made. All 86 tests pass at 88/89 lines (98.88%); the remaining private
  missing-integer/default branch stays measured, not excluded. Complete inventory
  bench-config14b-mutations: 72 generated, 42 kills, two survivors, 28 compile
  errors, no timeouts/errors, passing baselines; raw/adjusted 95.45%. The two
  list-growability survivors stay unwaived.
- Add 98% VM file floors for E2EE/configuration, the E2EE browser floor, and
  required VM mutation jobs for both targets. Expand the exact deployment-audit
  contract to eleven jobs; its regression fails before the contract update, then
  all 24 audit tests pass. All 29 verification-script tests and 14 coverage-checker
  tests pass. Browser collectors and full verification now include both E2EE
  files; a full collector run passes 451 tests and measures 4,693/5,526 core
  browser lines (84.93%). This is not the 98% core-wide goal.
- Focused analysis, formatting, shell syntax, diff checks and local advisory
  reviews complete. Reproductions, coverage, test logs and complete VM inventories
  are retained under e2ee14*, bench-config14b* and native-scope12. Native CLI
  campaign mcp-cli-native10 remains live with its unchanged pinned artifact;
  the existing verification queue remains live and will run bin/test-fast,
  bin/verify and fresh native production coverage in order after it. Do not
  rebuild ct_ffi or start duplicate campaigns. Commit/push/PR updates and the
  current candidate's hosted CI/audit remain pending those checks; keep the
  complete goal active.

### Lazy Payload Ownership And Mutation Follow-Up

- Regressions independently reproduce empty packed envelopes being decoded
  repeatedly, generic byte-list narrowing ahead of E2EE validation, and nested
  mutable payload values remaining aliased after toOwned/copyPayloadTo. Clear
  the packed callback only after success, retain wire bytes, validate each byte
  before narrowing, and copy WAMP container/binary graphs with an iterative
  identity memo. Preserve internal aliases/cycles, lazy decoding and shared
  providers/contexts/callbacks; no native use-after-free or cryptographic forgery
  is claimed by these Dart-level reproductions.
- Eighty-four focused tests pass on VM, JavaScript and WASM. The file measures
  412/413 VM lines (99.76%) and 482/488 JS lines (98.77%), with 98% file floors.
  Test owned subviews, partially cached state, packed failure/retry, both cipher
  byte bounds, provider/context precedence, runtime capability gating, wire-first
  decoding, in-place PPT serializer detection and repeated access. Browser
  collection/full verification now include the lazy, invocation and result
  suites. Fresh full browser collection passes 536 tests at 5,291/6,089 measured
  core lines (86.89%), with 185 other library files explicitly unmeasured by this
  browser slice; it is not component completion.
- The first full lazy VM inventory has 289 generated, 189 killed, 50 survivors,
  50 compile errors (79.08%); distinguishing tests produce 216 kills and 23
  survivors (90.38%) in the next full inventory. Both have passing baselines,
  no timeouts/errors and no equivalence exclusions. More tests distinguish valid
  byte boundaries, explicit provider/context overrides, required runtime data,
  decoded-state resets, retained metadata, serializer paths and empty shapes.
- Record eight individual source-hash-pinned equivalences only after inspecting
  all state writes: two packed-cache guards are redundant after clearing the
  successful decoder, and six predicates compare private message byte/decoder
  fields whose nullness is always paired. Public factory mismatches cannot break
  the message's guarded setter invariant. The owned copier preserves nullness;
  packed factories accept no pre-materialized fields. Forced whole branches and
  public provider/context guards are not waived. The local judge's hypothetical
  counterexamples were checked against these actual constructors/writes.
- A JS baseline failed before mutation because Dart 3.13.1 dart2js emitted
  expect(0, 1) for a scalar spy-field read after an indirect provider call that
  really incremented it. Keep the minimal repro and generated JS diagnostic;
  replacing scalar spy storage with a complete event log preserves the exact
  assertions and passes VM/JS/WASM, rather than skipping a platform or weakening
  expectations. The failed baseline has no mutation-score claim. New full
  lazy17-vm-mutations and lazy17-js-mutations use the event-log tests. The complete
  VM report has 223 killed, 16 survivors and 50 compile errors (289 generated),
  passing baselines and no timeouts/errors. Raw score 93.31%, adjusted 96.54%
  after the eight individual equivalences. Eight further survivors remain
  unwaived, including public provider/factory/restore predicates. Add the VM CI
  gate and twelve-job deployment-audit contract; a failing-before regression
  verifies the new contract and all 24 audit tests pass afterwards. Browser
  mutation remains live and diagnostics-only, not a passing score.
- Browser E2EE inventory e2ee14-js-mutations has now completed: 269 generated,
  209 killed, five survived, 55 compile errors, passing clean/restored baselines,
  raw/adjusted 97.66%, no waivers/timeouts/errors. It uses the original 69 tests;
  the later identity test passes both browser compilers separately.
- The original mcp-cli-native10 inventory also completed without replacing its
  pinned library: 1,179 generated, 560 killed, 292 survivors, 327 compile errors,
  raw/adjusted 65.73%, passing baselines and no equivalences/timeouts/errors.
  Security/error-validation survivors and CLI line gaps still require work.
  The existing queue then passed bin/test-fast, bin/verify and fresh native
  production collection, in that order. Never overlap those native commands.
  Native macOS arm64 production report: ct_core 8,348/10,045 (83.11%), ct_ffi
  4,589/5,808 (79.01%); exclude 4,084 and 3,396 test/helper lines with explicit
  AST ranges/reasons, preserve raw LCOV and hashes, and retain four unmeasured
  candidate files. This is not a Linux or native benchmark-crate measurement.
  The source-scope tool now has real-workspace evidence, not just fixture tests.
  Candidate commit/push, PR update and hosted CI/audit remain pending. Preserve
  raw evidence under lazy15*, lazy16*, lazy17*,
  mcp-cli-native10 and native-scope12. The overall goal remains incomplete.

### MCP CLI Adversarial Responses And Cleanup

- Add public HTTP regressions for malformed session counts/lists/details,
  registration and subscription lookup/match/list inconsistencies, wrong entity
  URIs, unexpected live members and malformed member counts. Assert the exact
  diagnostic category and that no later network action occurs. Keep positive
  integral-double and both session-detail ID field cases; do not invoke private
  validators just to increase coverage.
- Exercise acknowledged publication, method calls, notifications and event
  polling with nested payloads. Reject incorrect handles/topics, missing
  acknowledgements/IDs, dropped or remaining events and absent/wrong payloads.
  The rejected response may be followed only by cleanup.
- Three HTTP regressions fail before the production change: returned subscription
  topic/queue-limit validation was outside try/finally and leaked the valid
  returned handle. Move validation inside the existing unsubscribe boundary for
  direct, active-direct and Streamable subscriptions. Six real-router tests
  corrupt one otherwise valid response and require a successful unsubscribe
  acknowledgement plus active-session DELETE. Requests that fail before a usable
  handle is parsed are not covered by this cleanup claim.
- The router fault proxy preserves Content-Length instead of inadvertently using
  unsupported chunked request framing, passes empty SSE priming data, and waits
  for its handlers before checking teardown failures. These are fixture repairs,
  not claims of new transport support. All 329 CLI tests and 14 router CLI tests
  pass. Fresh combined CLI line coverage is 2,111/2,291 (92.14%); raise the floor
  from 89.9% to 92.1%, leaving the 98% target explicit.
- bin/test-fast exposed a separate intermittent workflow regression: piping
  dart pub token list into grep -q under pipefail can give the producer SIGPIPE,
  making the conditional silently skip removal. A deterministic fake producer
  exceeds pipe capacity after the matching line and also exercises exit 17;
  both cases fail before the fix. Capture the output first, preserving producer
  failure, then match the complete line. All 31 verification-script tests pass,
  including real-Dart isolated token cleanup preserving unrelated registries.
- The completed full vm-current17 report at aff93292 is 36,296/42,478 (85.45%),
  with 59 unmeasured library sources. Its per-package values are auth 100%, bench
  81.20%, client 85.10%, core 90.15%, MCP 93.34% and router 82.40%. Keep this
  earlier whole-workspace snapshot distinct from the newer focused CLI report.
- The serialized bin/test-fast, final-snapshot CLI collection and bin/verify
  queue passed. Hosted aff93292 CI passed all twelve jobs and publishing dry run
  passed, but strict log audit rejected the skipped real LLVM fixture. Configure
  Fast Checks and Full Verify with llvm-tools-preview, pinned cargo-llvm-cov
  0.9.1 and CONNECTANUM_TEST_LLVM_COVERAGE=1. The new workflow regression fails
  before that configuration; all 31 script tests and the real 13-test native
  coverage integration suite pass after it. These late workflow changes have
  focused validation; new candidate hosted CI/audit evidence remains required.
- The complete lazy17-js-mutations inventory has 289 generated mutants: 222
  kills, 16 survivors, 50 compile errors and one infrastructure error. Both
  baselines pass. Raw score is 92.89%, adjusted 96.10%, but the campaign fails
  closed because a live descendant remained after test exit. The assertion
  failure for 3c9eef1f979b85a272f7 must not be relabeled as a kill. Investigate
  browser fail-fast/queued-compilation lifecycle before another complete run.
- A fresh complete native CLI mutation inventory must follow successful full
  verification; never replace its pinned library while it runs. No new CLI
  mutation score or complete-goal claim is established by these regression tests.

Evidence: cli18*, vm-current17 and the preserved earlier inventories under
out/regression-coverage-2026-09-15. The full component/runtime and mutation target
remains open; no merge or publication is authorized by this checkpoint.

### Batch Metadata And Browser Runner Cleanup

- Extend the real-router fault proxy to one response within a batch, preserving
  siblings and JSON/SSE framing. Rejections cover malformed/inconsistent session
  counts/details, registration/subscription discovery and member statistics,
  omitted catalog entries and tool errors. Require no HTTP request after the
  rejected direct batch. Keep existing subscription cleanup evidence intact.
- Three regressions reproduce acceptance of a mismatched procedure identity on
  session count/list/get batch results. Apply the existing optional identity
  guard used by registration/subscription metadata. Positive cases retain wrapped
  responses with/without procedure and named flat response compatibility.
- All 69 real-router CLI tests and 329 focused CLI tests pass. Fresh cli19d
  coverage is 2,146/2,297 executable CLI lines (93.43%); enforce a 93.4% floor,
  keeping the 98% target and whole-workspace denominator separate.
- A real Chrome fixture demonstrates that fail-fast skips tearDownAll and later
  tests after an assertion failure. Chrome mutation commands now finish suites
  before shutdown; no grace period, retry or relaxed leak classification is
  introduced. The process census adds executable identity (ps comm, not argv).
  All 27 runner tests pass locally except the explicitly Linux-only zombie case.
  The lazy17-js error remains an error; the identity/cause of that historical
  descendant is still unproven. The independent complete lazy19-js inventory is
  running with the revised command, not yet passing evidence.
- The live browser inventory correctly classifies the cycle-detection mutant
  308d9f46d9ca2de88fcf as an error: the ordinary cyclic fixture hangs until the
  browser disconnects. Add a bounded cyclic-map input before the original
  ordinary-container case so repeated traversal fails an assertion rather than
  blocking the event loop. All 55 focused regressions pass on VM, JavaScript and
  WASM. An isolated exact-mutant replay has passing clean/restored baselines and
  a bounded assertion kill. Preserve the old inventory unchanged; diagnostic
  replay is not a replacement score or a complete new campaign.
- bin/test-fast passed before the new batch/runner changes. Focused collection
  and bin/verify with CONNECTANUM_TEST_LLVM_COVERAGE=1 passed.
  e051650b is pushed with its hosted CI still in progress; current uncommitted
  changes require new candidate hosted evidence. No native mutation campaign
  pins ct_ffi at this checkpoint.

Evidence: cli19*, browser19*, lazy19-js-mutations and the earlier preserved
inventories under out/regression-coverage-2026-09-15. The full goal remains open.

### RawSocket Probe Cancellation

- A paused-time regression fails before the fix: a standard frame's first byte
  is consumed by read_exact and discarded when the optional upgrade probe times
  out. Retain the lookahead buffer/count outside the timed future, use read's
  cancellation-safe partial operation and restore the consumed prefix on timeout.
- All 20 RawSocket tests pass after the fix. Additional cases preserve immediate
  EOF rejection with zero/one probe byte and successful upgrade with a buffered
  magic byte plus socket suffix. Existing file-range/backpressure tests still
  pass. Add Tokio test-util only as a dev dependency for deterministic time.
- bin/test-fast finished successfully. Full bin/verify with the real LLVM
  fixture is running before the serialized native20-rawsocket campaign. Preserve
  all cargo-mutants outcomes; its caught count is not sufficient to prove an
  assertion kill. cfg-inactive mutants require separate platform accounting.
- Discovery lists 3,356 transport and 1,289 benchmark candidates. These include
  inactive platform code and do not establish a viable production denominator or
  meet the complete native mutation target. No broad equivalence is justified.

Evidence: native20-before/after logs, native20-rawsocket snapshot and campaign
output, and coverage20 verification logs. The full goal remains active.

### Native Mutation Evidence And Wire Assertions

- Full coverage20 verification passed at ab4511a6. Native20 failed its clean
  baseline because cargo-mutants omitted sibling public TLS fixtures; native21
  failed setup because --in-place cannot be combined with --jobs. Preserve both
  failures rather than labeling either a mutation campaign pass.
- The complete isolated native22 RawSocket campaign contains 129 candidates.
  Strict audit confirms 17 assertion kills, 72 errors, 22 survivors, five compile
  errors and 13 timeouts, despite Cargo reporting 89 caught. Both baselines pass.
  Raw/adjusted candidate score is 13.71%, no equivalences. Runtime panics,
  unwrap/expect failures and hangs are not explicit assertion kills. Inactive
  platform bodies remain visible; no active-platform denominator is claimed.
- Add the canonical collector and auditor with input/tool/log hashes, complete
  inventory correspondence, test-only panic locations, multiline replacement
  offsets and identical clean/restored test inventories. Materialize symlinks;
  the new isolation regression fails against preserved links. Include sibling
  public TLS fixtures and isolate build output. Never mutate the live checkout.
- All 21 tooling tests and 33 verification-script tests pass, including real
  rustc/libtest, cargo-mutants and sibling-include fixtures. Fast/Verify install
  pinned cargo-mutants 27.1.0. Linux/macOS diagnostics collect audited evidence,
  retain artifacts on failure and continue to fail on survivors or dirty evidence.
- Strengthen RawSocket response-byte assertions and half-close cases for peers
  ineligible for an upgrade. Check negotiation results before awaiting response
  bytes; half-close completed inputs so truncated data cannot leave peers waiting
  forever. Do not relabel the old timeouts. A proposed below-minimum endpoint
  test was rejected by configuration validation before negotiation; remove that
  invalid fixture rather than bypass validation to increase coverage.
- bin/test-fast and bin/verify pass, including the real LLVM fixture and both
  browser compilers. The subsequent native23 production collection passes at
  macOS arm64 ct_core 8,357/10,051 (83.15%), ct_ffi 4,589/5,808 (79.01%) and
  RawSocket 254/267 (95.13%), with four unmeasured candidate sources retained.
  Native23's complete mutation inventory is now running after those serialized
  checks; do not substitute new assertions for its pending measured result.
- Hosted ab4511a6 CI passed all twelve jobs and publishing dry-run passed.
  Strict audit retains the known feature-branch/default-workflow constraints.
  The complete lazy19 inventory retained one cycle-related error; lazy20 is a
  separate running inventory, not a replacement classification for lazy19.

Evidence: native20/21/22-rawsocket, native23-current/native23-rawsocket when
completed, and native23 verification/tooling logs. The full goal remains active.

### FastCGI Response Regressions And Browser Mutation Gate

- The complete lazy20 JavaScript inventory contains 289 candidates: 223 kills,
  16 survivors and 50 compile errors. Clean/restored baselines pass, with no
  timeouts/errors. Raw score is 93.31%; the eight existing individually justified,
  source-hash-pinned equivalences yield 96.54% adjusted. Preserve the earlier
  errored inventories rather than replacing their results. Require a separate
  core-lazy-web CI job, with complete logs/inventory artifacts and a 90-minute
  campaign budget; individual test timeouts and error classification are unchanged.
  All 24 deployment-audit tests pass with thirteen required jobs.
- FastCGI's public route plus a real TCP upstream reproduces comma-folded cookies.
  The parser now retains independent fields, and NativeHttpResponse has an
  immutable additionalHeaders list appended to its scalar header map at FFI
  marshaling. The existing CtHttpHeader array ABI already supports this; no
  native ABI change is needed. A native HTTP wire test checks three separate
  Set-Cookie lines, including an Expires comma and mixed-case input names.
  This follows [RFC 6265 section 3](https://www.rfc-editor.org/rfc/rfc6265#section-3),
  which warns that folding Set-Cookie fields changes their semantics.
- Inspection beyond HTTP/1 exposed native HTTP/2 and HTTP/3 header-map overwrites.
  Six real-protocol tests fail independently at the cookie assertion for plain,
  buffered and streaming replies. All six pass after appending caller fields,
  without folding, in each response builder. The tests also assert complete body
  bytes and repeated non-cookie fields. Conflicting Content-Length fixtures are
  replaced by one computed value for plain/buffered replies and removed for
  streaming replies. The new HTTP/2 plain fixture independently failed with
  three lengths; inserting the computed length last fixes that framing defect.
  Tests run in an independent Cargo target directory, not the shared FFI build.
  The initial verify ran its native phase before these changes and was not
  final-snapshot evidence; the subsequent coverage25 full verify includes all
  six native header tests and passes.
- Case-insensitive repeated Connection fields contribute all hop-by-hop tokens,
  and upstream Content-Length is removed before native framing. Separate
  regressions reproduce acceptance of 600/999 statuses; the parser now rejects
  them before dispatch, matching native validation and the 100..599 range in
  [RFC 9110 section 15](https://www.rfc-editor.org/rfc/rfc9110.html#section-15).
- Thirty focused regressions pass. Cases cover CRLF/LF, valid status boundaries,
  padded/fragmented records, binary bodies, stderr isolation, invalid version/ID,
  truncated headers/content/padding, failed END_REQUEST, malformed CGI headers,
  cumulative stdout limits, incomplete-response timeout and invalid UTF-8.
  The fixture waits for upstream EOF on success/error/timeout rather than merely
  destroying the socket in teardown. Header snapshots are immutable.
- Local companion review's casing concern is disproved by the existing
  _nativeHttpResponseHeaderEntries lowercasing; its Connection concern is
  disproved by source inspection and exact header-set assertions. The RFC-backed
  status tightening is intentional. Pre-change bin/test-fast and analysis pass;
  initial bin/verify with the real LLVM fixture and both browser compilers passes.
  Full VM collection vm-current24 subsequently failed the legacy ABI fixture,
  without a valid new total. Cargo succeeded but the test helper's broad mtime
  check rejected its artifact after a cfg(test)-only source change. A fake-Cargo
  regression reproduces both normal and legacy failures. Trust Cargo freshness
  after success, but still reject failed builds and absent outputs; all six
  fixture cases pass. Local review proposed requiring a relink after no-op Cargo
  success, which would reinstate the reproduced bug; reject that recommendation.
  Fresh bin/test-fast and final-snapshot bin/verify pass, including the real
  legacy ABI regression, 34 verification-script tests, the real LLVM fixture
  and both browser compilers. Full VM collection vm-current25 is running;
  native25-current is queued serially afterward.
  Candidate hosted evidence remains required;
  no whole-router percentage or
  new FastCGI mutation score is claimed from these focused tests.
- Native23 completed all 129 RawSocket candidates, but strict auditing reports
  12 kills, 91 errors, 19 survivors, five compile errors and two timeouts.
  Preserve the failed evidence. Several logs combine genuine assertion failures
  with test unwrap/expect panics, which cannot be reported as assertion-only kills.
  Remaining native test quality, platform-specific survivors and complete native
  scope remain open; do not weaken the auditor to manufacture a passing score.
- Hosted 7984160 CI (35037801775) and publishing dry-run (35037801711) passed.
  The locally updated thirteen-job audit reports the browser gate missing from
  the older twelve-job run, not a failed browser campaign. Unprotected feature
  branch and diagnostic workflow absent from master remain strict findings.
  Do not weaken those checks or merge/publish to remove them without authorization.

Evidence: lazy20-js-mutations and native23-rawsocket under
out/regression-coverage-2026-09-15, plus coverage24/25 regression/verification logs.
The original per-component/runtime coverage and mutation goal remains active.

### Hosted Browser Launcher And Full Coverage Checkpoint

- Commit 4b551b78 is pushed to PR #93 after final-snapshot bin/test-fast and
  bin/verify pass. Hosted core-lazy-web fails its unmutated baseline with Chrome's
  No usable sandbox error, before executing any mutant. Preserve its incomplete
  inventory and failure artifact; this is not a failed mutation score.
- bin/test-mutations bypassed the canonical browser launcher used by other
  browser checks. A behavioral entrypoint fixture reproduces the missing hosted
  Linux flag, then passes after optional browser preparation. Seven cases verify
  Linux/Darwin, CI/local operation, arguments containing spaces, and VM operation
  without Chrome, native-build opt-in, and failure before the runner when browser
  setup fails. Only the existing CI=true Linux policy is reused; local browser
  launches and strict mutation classifications/thresholds are unchanged.
  All 36 verification-script tests, fresh bin/test-fast and final bin/verify
  pass, including the real LLVM fixture and both browser compilers. Replacement
  hosted evidence remains required.
- Complete vm-current25 and native25-current collections pass, serialized after
  final-snapshot verification. VM libraries: 36,428/42,494 (85.73%), with 59
  unmeasured sources. Auth server is 100%, core 90.15%, client 85.10%, router
  82.60%, bench 81.20%, MCP package 95.40%; MCP library 98.20% and CLI 93.43%
  retain separate denominators. Packaging is client 391/402 (97.26%) and router
  374/385 (97.14%), with twelve unmeasured sources.
- macOS arm64 native production coverage: ct_core 8,373/10,051 (83.31%), ct_ffi
  4,585/5,808 (78.94%). Four unmeasured candidate sources remain explicit.
  These results do not establish Linux/native benchmark workspace coverage or
  a passing native mutation score. Native23's errors/survivors remain open.

Evidence: vm-current25, native25-current, coverage25-browser-ci-failure, and
coverage25/26 regression logs under out/regression-coverage-2026-09-15.

### RawSocket Behavioral Oracle Checkpoint

- Native23's complete inventory exposed mixed assertion/unwrap failures, not a
  passing mutation score. Retain that failed evidence and the strict auditor.
- Handshake regressions assert explicit success/error variants and full wire
  responses. Success matrices independently check serializer, exponent, upgrade,
  file-sender availability and both payload directions. Interleaved handshake
  fixtures remain alongside deterministic prequeued wire cases.
- Seven file-range cases cover zero lengths, off_t overflow, exact/end/past EOF
  and partial prefixes. The socket write half is shut down only after the send
  returns, including the duplicated sender descriptor. Bounded reads through
  EOF distinguish missing/extra bytes without indefinite read_exact waits.
  The slow-reader test retains exact payload assertions. Repeated file segments
  interleaved with ordinary writes share one socket and preserve the file cursor.
- Genuine infrastructure errors, production panics and timeouts remain errors
  or timeouts, never mutation kills. No production logic or mutation policy
  changes. Local companion concerns about extra bytes escaping the read bound
  and shutdown racing an awaited send are disproved by source inspection;
  global metric counters retain conservative lower bounds for parallel tests.
- bin/test-fast and all 21 focused RawSocket tests pass. Final bin/verify passes,
  including the real LLVM fixture and both browser compilers. The complete
  isolated native27-rawsocket inventory is running serially after verification;
  retain all outcomes and audit it before claiming a new score. The complete
  cross-runtime goal remains open. Production RawSocket bytes before cfg(test)
  are unchanged (SHA-256 f7a9dfe10ab6272cb44aab39796bfd19194bafd8ae4ae6b643bcfd7dfad4b0c1).

Evidence: coverage27-checkpoint under out/regression-coverage-2026-09-15.

### Configuration Contracts And Isolated Fixture Coverage

- Full vm-current28 passes serially after bin/verify: 36,650/42,494 executable
  library lines (86.25%), up 222. Router is 16,148/19,282 (83.75%);
  router_settings.dart is 480/480 (100%) and now has a 98% file floor.
  Other package totals and the 59 unmeasured library sources are unchanged.
  Packaging remains client 391/402 and router 374/385, with twelve unmeasured
  sources. Keep these VM measurements separate from browser/native/app scope.
- New settings regressions exercise field-by-field equality and copy behavior,
  independent map keys without assuming collision-free hashes, nested options,
  collection snapshots, route enrichment/idempotence, exact versus prefix route
  precedence, listener-field preservation and legacy/explicit protocols.
- The first settings28 mutation baseline failed because its isolated workspace
  omitted examples/quickstart/router.yaml, required by the retained config-loader
  suite. Reproduce with a snapshot regression, then copy explicitly declared
  git-listed supportFiles and record their hashes. Reject missing/unlisted files,
  absolute/parent escapes and symlink files/ancestors. Thirty runner tests pass,
  with one Linux-only process regression skipped locally. Do not remove the
  integration suite or count the failed baseline as a mutation score.
- Complete settings29: 337 candidates, 182 kills, 37 survivors, 118 compile
  errors, no timeouts/errors; clean/restored baselines pass. Raw/adjusted score
  is 83.11%, with no exclusions. Mutation survivors exposed absent tests for
  default realm creation/disclosure, HTTP3 opt-in and positive capacity limits.
  Add those tests plus nonnegative threshold boundaries and explicit protocol
  precedence; all 157 settings/loader tests and analysis pass.
- Seven private-helper equivalences are individually pinned to source hash
  2e9661f379ae78c06a70f83c225c431eda518d79e5bced4e81de448ec13a20ad:
  unexposed list growability, set-deduplicated appended protocol values, guards
  unreachable for owned normalized route paths, and redundant normalization
  branches. Do not blanket-exclude public identical fast paths: settings classes
  are subclassable and getters may be overridden. The complete settings30
  campaign is running; no passing score or required mutation gate is claimed.
- Native27 retains eight audited kills, 95 errors, 19 survivors, five compile
  errors and two timeouts across all 129 candidates. Custom assert messages lack
  the standard marker; keep the strict auditor and preserve predicates while
  using normal diagnostics. A real rustc fixture verifies custom versus standard
  assertions and production panics remain distinct. All 21 tooling and 21
  RawSocket tests pass. Production Rust bytes remain unchanged. Native28 runs
  serially after VM collection; audit the complete result before claiming a score.
- Separate app-shared29 VM baseline passes 56 tests at 1,396/1,537 (90.83%).
  Its export facade and protocol constants have no executable records. The
  Flutter client and application server remain separate, unmeasured scopes;
  application-aware reporting/gates and full mutation inventories remain open.
- bin/test-fast and bin/verify passed before the latest snapshot-tool/boundary
  edits. Final-snapshot verification and candidate hosted evidence remain pending.
  Local companions supplied test ideas/review and confirmed that public getter
  overrides defeat an unconditional identity-fast-path equivalence proof.

Evidence: vm-current28, settings28-mutations (failed baseline), settings29-mutations,
settings30-mutations, app-shared29 and native28-rawsocket under
out/regression-coverage-2026-09-15. The original full goal remains active.

### Hosted HTTP Body Hang And Native Audit Parser

- PR Full Verify job 104636405479 in run 35045484401 reached its 45-minute limit
  while http1_stream_reader_reclaims_after_completion waited indefinitely. The
  same-commit push job passed; that is not a fix or a reason to ignore this run.
  Source inspection identifies an actual lost-wakeup window: mark_finished
  writes the predicate and notifies without the chunks mutex held by take_slice
  between its predicate check and Condvar.wait.
- A coordinated test holds that condition-check mutex while a started finisher
  calls normal/error completion. It fails before the fix because completion
  overtakes the protected interval. mark_finished now holds the same mutex for
  the predicate update and notification. All six HTTP-body tests pass afterward,
  including reclamation and stalled-client errors. No network or CI timeout is
  increased. Local review confirms mark_error releases its error lock before
  entering mark_finished, so the fix introduces no reverse nested-lock order.
- Native28's first audit records 21 kills, 82 errors, 19 survivors, five compile
  errors and two timeouts. Valid multi-assertion logs reveal a second evidence
  problem: FAILURE used a greedy DOTALL .+ for header names and swallowed whole
  intervening blocks. A regression fails with two valid failure blocks merged
  into one name. Restrict header names/lookaheads to a single line; real rustc
  now verifies two-test assertion failures too. All 23 tooling tests pass;
  extra/duplicate printed headers and actual panics/crashes/timeouts still fail
  closed. This corrects parsing, not the rules for what counts as a kill.
- Preserve native28's original report. Separate parser-recheck-audited-results
  plus parser-recheck-tools.sha256 record the corrected grader's 92 kills,
  eleven errors, 19 survivors, five compile errors and two timeouts. Score is
  74.19% raw/adjusted and evidence remains unclean. The remaining errors are not
  relabeled. A fresh native30 campaign is queued after final verification.
- Complete settings30 passes both baselines: 193 kills, 26 survivors and 118
  compile errors, no timeouts/errors. Raw score 88.13%, adjusted 91.04% using
  exactly seven pinned private-helper equivalences. Nineteen other survivors
  remain unresolved; do not add a passing required gate or claim 95%.
- Fresh bin/test-fast and final bin/verify pass, including the real LLVM fixture
  and both browser compilers. Native30 is running serially afterward; candidate
  hosted CI and strict audit evidence remain required.

Evidence: coverage30 HTTP-body before/after logs, native parser before/after
fixtures, hosted timeout log and triage, plus the retained native28 re-audit and
settings30 full inventory. The whole coverage goal remains active.
