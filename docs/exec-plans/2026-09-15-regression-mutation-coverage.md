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
  the complete 234-mutant browser inventory is running. The larger MCP
  inventory remains live and diagnostic.
- `bin/test-fast` passes after correcting an initially wrong expected abort
  URI in a new test; full `bin/verify` is running. Hosted confirmation of the
  repair and strict candidate audit remain pending. The HTTP/3 reliability
  issue is not claimed fixed by successful repetitions or this CI repair.

Evidence: `out/regression-coverage-2026-09-15/auth-gate-repair/` retains the
hosted failing inventory, local inventories, exact-mutant replay and runner
before/after logs. The full coverage goal remains active.
