# Meta Discovery Authorization

Status: source and coverage fixes merged and verified; package release pending
Started: 2026-09-09
Completed: 2026-09-10

## Contract

The user requires registration Meta discovery to disclose only callable
procedures and subscription Meta discovery to disclose only subscribable
topics. Permission to invoke a Meta procedure is not a grant to discover all
realm entities. Publishing alone must not expose subscription metadata.

The [WAMP Meta API specification](https://wamp-proto.org/wamp_latest_ietf.html)
defines list/lookup/match/get and participant/count procedures. It describes
publisher use cases for subscription introspection; subscribe-only visibility
is this router's explicitly requested stricter policy, not a universal
WAMP protocol requirement. Preserve existing response shapes and make hidden
IDs indistinguishable from missing IDs through the related Meta endpoints.

## Work

1. Reproduce publish-only subscription visibility on real WebSocket,
   RawSocket, router-hosted MCP direct JSON, and Streamable HTTP connections.
2. Require subscribe permission for live and configured subscription Meta
   snapshots, including the correct match policy for dynamic authorization.
3. Remove the configured documentation-only registration authorization bypass
   in MCP Meta snapshots. Leave explicitly configured general API documentation
   catalogs outside this change; those are not WAMP registration Meta results.
4. Exercise static grants/denies, dynamic denials, pattern subscriptions,
   related Meta lookup/detail/count methods, and authorized positive controls.
5. Run focused tests and analysis, local review, and `bin/verify` sequentially
   after the baseline `bin/test-fast`. Do not overlap native runtime test gates.

## Progress

- Initial inspection: live registration snapshots already check `call`.
  WAMP and MCP subscription snapshots use `publish OR subscribe`. Configured
  MCP registration snapshots skip authorization when `allow_call` is false.
  Subscription visibility also omits match-policy context for dynamic checks.
- Baseline `bin/test-fast` passed before implementation. All eight live-router
  regressions then failed on unauthorized subscription IDs across WebSocket,
  RawSocket, MCP direct JSON, and MCP Streamable HTTP, under both static and
  dynamic policies. The initial standalone run skipped without a resolved
  native library; the red and green runs explicitly loaded the ffi-test library.
- Implemented subscribe-only visibility and dynamic match-policy context on
  both paths, plus call authorization for configured MCP registration entries.
  All eight regressions now pass, including authorized positive controls,
  publish-only and register-only callers, explicit and dynamic denials,
  exact/prefix/wildcard subscriptions, configured entries, and hidden-ID parity.
- Router analysis and the combined 122-test Meta/session/auth suite pass.
  Local semantic review completed; source checks confirmed catalog separation,
  exhaustive match-policy conversion, and existing static/dynamic precedence
  coverage. No actionable production-code finding remained.
- The first full `bin/verify` run exposed a legacy MCP smoke expectation that
  anonymously disclosed a configured registration without call permission.
  That smoke now requires the ID to stay hidden publicly, while an authorized
  member retains synthetic ID/list/get/callee coverage. An ID learned by the
  member must also remain hidden when used on the public endpoint. The separate
  explicitly configured documentation catalog remains visible as before.
  The updated smoke passes independently and in the complete verification gate.
- Final `bin/verify` passes: 482 router tests (including all eight new discovery
  cases), six isolated remote-auth tests, 13 zero-copy tests, 124 benchmark tests,
  isolated package/live MCP consumer smokes, and Chrome/Dart2Wasm SCRAM and
  WebSocket coverage. Router analysis and `git diff --check` are clean. The
  test-only follow-up review was checked against the intentional nondisclosure
  contract and existing helper behavior; no actionable issue remained.
- The user requested a commit and push of the verified security branch.
  Published beta.5 consumers still require master integration and a synchronized
  release to receive this fix; pushing this branch does not publish packages.
  Resume the broader WampApp plan without treating this source verification as
  evidence of a package publication or deployment.
- Commit `16d0efa5` is pushed to both GitLab and GitHub on
  `codex/meta-discovery-authorization`. Fresh clean-tree `bin/verify` passes.
  CI `34331583523` passes all four jobs and package publish dry run `34331583640`
  passes, both at the exact commit. The strict master deployment baseline and
  branch exact-head clean-CI/log, relevant package dry-run, visible-workflow,
  and router-package audits pass. No merge, release tag, or package publication
  was performed. Post-push evidence notes are held for the next implementation
  commit rather than creating a docs-only bookkeeping commit.
- The user requested master integration. Opened
  [PR #89](https://github.com/konsultaner/connectanum-dart/pull/89) from the
  verified security branch. GitHub reports no merge conflicts but requires one
  approving review; the normal merge command was rejected by branch policy.
  PR-triggered CI is running. Neither master remote has moved from `a5613d17`,
  and no branch-protection bypass or release publication was performed.
- On 2026-09-10, the user merged PR #89 at `04123953`. Its source tree matches
  the verified `16d0efa5` tree exactly. Fast-forwarded local and GitLab master
  to the GitHub merge commit while preserving uncommitted evidence notes.
  Post-merge package publish dry run `34472422572` passes; CI `34472422608`,
  WAMP Profile Benchmarks `34472422573`, and fresh local `bin/verify` are running.
  This source integration does not publish a new package version.

## Post-Merge CI Repair

- Master `04123953` passes fresh local `bin/verify`, hosted package publish
  dry run `34472422572`, WAMP Profile Benchmarks `34472422573`, and strict
  baseline/package/benchmark audits. CI `34472422608` passes Fast Checks,
  WampApp Consumer, and Full Verify. Coverage fails before collection with
  pub.dev authorization errors on both the initial job and a targeted rerun.
- Coverage grants `id-token: write` for Codecov. Its setup-dart step registers
  a pub.dev token automatically; other test jobs resolve public dependencies
  without that token. Keep Codecov OIDC, artifact strictness, and publishing
  workflows unchanged. Remove only the coverage runner's pub.dev token before
  bootstrap, guarded by token-list presence because absent removal exits 65.
- Regression tests execute the exact workflow shell block against dummy
  env-var tokens, preserving another registry and proving repeated cleanup.
  Both tests failed before the fix and pass afterward. All 22 verification
  script tests, baseline `bin/test-fast`, and fresh `bin/verify` pass.
- Dart's [token store](https://github.com/dart-lang/pub/blob/master/lib/src/authentication/token_store.dart)
  uses the [platform configuration directory](https://github.com/dart-lang/pub/blob/master/lib/src/io.dart),
  not `PUB_CACHE`. The fixture now isolates HOME, APPDATA, XDG_CONFIG_HOME,
  and PUB_CACHE, clears inherited test config overrides, and refuses writes
  unless CLI help confirms its temporary token location. The initial fixture
  mistakenly created a local dummy-token file; test entries were removed and
  the generated file deleted. The pre-existing OAuth login file was unchanged.
- Follow-up commit `87f1a60b` is pushed to both maintained remotes. Hosted CI
  `34475872067` and PR CI `34475902747` pass all four jobs, including coverage
  collection, Codecov upload, and strict artifact upload. The exact-head CI/log
  audit passes, as do strict master protection and relevant package/benchmark
  audits: the follow-up changes no release or WAMP benchmark inputs.
- The user merged [PR #90](https://github.com/konsultaner/connectanum-dart/pull/90)
  at `733c6d91`. Local master and GitLab master are fast-forwarded to that GitHub
  merge commit; its tree is identical to verified `87f1a60b`. Final master CI
  `34478086614` passes all four jobs. The final strict master audit passes
  exact-head CI/log cleanliness, required checks, workflow/router-package
  visibility, and relevant package dry-run and WAMP benchmark evidence.
  No additional implementation or package publication is included in this
  handoff. Post-merge notes stay uncommitted per policy.
