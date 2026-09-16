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
  coverage66 and verify66 run serially before handoff. Do not merge old LCOV
  line numbers across this source change. Reports remain under router-files66,
  router-files66b and router-files66c, with the failed runs retained separately.
- router-binding-vm inventories the whole binding file (2,379 candidates), with
  the runtime/metrics suites, explicit native artifact provenance, complete test
  file cleanup and 30-second per-test deadlines. Inventory66 is not a mutation
  score. No candidate range or denominator is excluded to manufacture a pass.
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
