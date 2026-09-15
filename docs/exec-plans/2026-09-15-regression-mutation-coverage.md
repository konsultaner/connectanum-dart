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
