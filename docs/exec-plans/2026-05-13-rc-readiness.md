# Exec Plan: Release Candidate Readiness

Status: active
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-22

## Problem

The workspace is ready to move from long-lived feature-branch validation toward
a first release candidate, but the release must come from the GitHub default
branch with clean CI, visible workflows, native runtime bundles, and router
image validation. Public pub.dev publishing remains a separate release-track
decision because `connectanum_client` still depends on private
`connectanum_core`.

## Scope

- Treat MCP as RC-ready after the direct WAMP API helper smoke evidence unless
  a consumer integration uncovers a real correctness bug.
- Align `bin/audit-github-deployment-chain --require-rc-ready` with the first
  RC definition: GitHub prerelease readiness can pass when pub.dev publishing is
  intentionally deferred and the only strict Dart package blocker is the known
  private `connectanum_core` dependency.
- Accept inspected native GitHub prerelease evidence for RC readiness while
  keeping the standalone native release dry-run audit gate strictly
  non-mutating.
- Add an explicit non-mutating Router Image dry-run audit gate so container
  build validation is tracked separately from GHCR package visibility/publish
  approval.
- Promote `add-router` into the GitHub default branch used for releases.
- Configure required GitHub status checks for `Fast Checks` and `Full Verify`.
- Run local release gates, hosted CI, hosted package dry-run evidence, WAMP
  profile benchmark evidence, native artifact prerelease publishing, router
  image dry-run/publish validation, and final deployment-chain audits.

## Non-Goals

- Public pub.dev publishing for the first RC.
- Making private workspace packages publishable.
- Adding new MCP helper permutations after the RC-ready smoke unless a real
  integration bug appears.
- Mentioning private downstream application names or local downstream paths in
  checked-in docs or public artifacts.

## Milestones

- MCP direct WAMP API helper smoke is complete and hosted GitHub CI is green.
- RC audit semantics distinguish GitHub prerelease readiness from deferred
  pub.dev release-order decisions without hiding package dry-run warnings.
- GitHub `master` contains the release branch content and checked-in workflows.
- GitHub branch protection requires `Fast Checks` and `Full Verify`.
- `v0.1.0-rc.1` exists as a non-draft GitHub prerelease with native bundles,
  checksums, and Sigstore metadata.
- `ghcr.io/konsultaner/connectanum-router:0.1.0-rc.1` is published and the
  router package is visible through the public GHCR registry API or GitHub
  Packages metadata fallback.
- Final audits pass for GitHub-prerelease RC readiness, with pub.dev release
  order explicitly deferred.

## Verification

- `bin/test-fast`
- `bash -n bin/audit-github-deployment-chain`
- `bin/audit-github-deployment-chain --help`
- `bin/audit-github-deployment-chain --branch add-router --require-clean-router-image-dry-run`
- `bin/dart-package-publish-dry-run`
- `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
  is expected to fail only on the known private `connectanum_core` dependency.
- `bin/verify`
- GitHub `CI`: `Fast Checks` and `Full Verify` green on the release branch.
- GitHub `Dart Package Publish Dry Run`: green with zero warnings.
- GitHub `WAMP Profile Benchmarks`: green on the release-sensitive branch/tag.
- GitHub `Native Artifacts`: prerelease run green for `v0.1.0-rc.1`.
- GitHub `Router Image`: dry-run green, then publish green for `v0.1.0-rc.1`.
- `bin/audit-github-deployment-chain --branch master --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --show-rc-readiness`
- `bin/audit-github-deployment-chain --branch master --require-rc-ready`

## Decision Log

- 2026-05-22: Router-hosted MCP Streamable HTTP `initialize` now rejects
  requests that include a client-supplied `MCP-Session-Id` before endpoint
  lookup or creation. The router returns a `400` JSON-RPC `invalid_request`,
  omits `MCP-Session-Id` from the response, and keeps Streamable HTTP sessions
  server-assigned so consumer applications or agents cannot select predictable
  session ids. The router integration regression was added first and failed
  against the previous behavior because the same request was accepted with
  `200 OK`. The generated consumer-package smoke now sends the same request
  through a raw `HttpClient` against public `McpStreamableHttpClient.endpoint`,
  including configured bearer headers, and proves public and bearer-protected
  router-hosted MCP endpoints reject it without capturing Streamable client
  state. Pre-change `bin/test-fast` passed; after the fix, focused router
  integration coverage, `dart analyze packages/connectanum_router`, `bash -n
  bin/common.sh`, focused generated router-hosted MCP consumer smoke, repeated
  `bin/test-fast`, `git diff --check`, and full local `bin/verify` passed.
  Hosted deployment-chain evidence is pending for this checkpoint.
- 2026-05-22: Router-hosted MCP Streamable `initialize` handling now treats
  newly created endpoints as tentative until initialization succeeds. If the
  MCP server returns a JSON-RPC error for a new Streamable `initialize`
  request, the router disposes that endpoint and omits `MCP-Session-Id` so
  consumer applications cannot reuse a failed initialization as an active MCP
  session. The router integration regression was added first and failed against
  the previous session leak; the generated consumer-package smoke now proves
  the same rejected-initialize behavior through public
  `McpStreamableHttpClient.post(...)` before the normal Streamable lifecycle.
  Pre-change `bin/test-fast` passed; after the fix, focused router integration
  coverage, `dart analyze packages/connectanum_router`, `bash -n
  bin/common.sh`, focused generated router-hosted MCP consumer smoke, and
  repeated `bin/test-fast` passed. Full local `bin/verify` also passed. Commit
  `08557f7` (`fix: drop rejected mcp initialize sessions`) was pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master`
  CI run `26293468018` passed with clean logs, `add-router` CI run
  `26293451755` passed, hosted Dart Package Publish Dry Run runs `26293468008`
  and `26293451704` passed, hosted WAMP Profile Benchmarks runs `26293468009`
  and `26293451763` passed, and current-head Router Image dry-run
  `26293615506` passed for `0.1.0-rc.2-validation.08557f7`. Native Artifacts
  dry-run `26286794628` remains relevant because no native-release-sensitive
  inputs changed. The strict deployment-chain audit passed required gates on
  `master` at `08557f7`; RC readiness remains blocked only by explicit RC
  tag/prerelease/router-image tag selection and deferred pub.dev release-order
  decisions.
- 2026-05-22: Router-hosted MCP Streamable HTTP session deletion now cleans up
  endpoint-created WAMP pub/sub subscriptions. `_RouterMcpEndpoint` tracks
  subscription ids created through MCP pub/sub helpers, removes ids on explicit
  unsubscribe, and best-effort unsubscribes any remaining ids when DELETE
  removes the MCP session or the endpoint is disposed. Router integration
  coverage and the generated consumer-package smoke now prove a Streamable MCP
  subscription has one route-visible subscriber before DELETE and zero after
  DELETE through direct JSON WAMP subscription meta. Pre-change
  `bin/test-fast`, focused router integration coverage, `dart analyze
  packages/connectanum_router`, `bash -n bin/common.sh`, focused generated
  router-hosted MCP consumer smoke, `git diff --check`, and full local
  `bin/verify` passed. Commit `383e0a9`
  (`fix: clean up mcp delete subscriptions`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26289774583` passed after rerun with clean logs, `add-router` CI run
  `26289773557` passed, hosted Dart Package Publish Dry Run runs `26289774620`
  and `26289773603` passed, hosted WAMP Profile Benchmarks runs `26289774563`
  and `26289773604` passed, and current-head Router Image dry-run
  `26290485783` passed for `0.1.0-rc.2-validation.383e0a9`. The strict
  deployment-chain audit passed required gates on `master` at `383e0a9`; RC
  readiness remains blocked only by explicit RC tag/prerelease/router-image tag
  selection and deferred pub.dev release-order decisions.
- 2026-05-22: Current implementation checkpoint adds per-method HTTP route
  action overrides for the Dart router config surface. `HttpRouteSettings`
  now carries `methodActions`, `RouterConfigLoader` accepts
  `method_actions` / `methodActions`, `RouterSettingsCodec` round-trips the
  overrides, native config encoding emits method-specific targets, and Dart
  synthetic route matching includes override keys in allowed-method handling
  for deterministic `405` / `Allow` responses. `ROADMAP.md` now marks
  per-method overrides complete while keeping catch-all wildcard translation
  tables open. Pre-change `bin/test-fast`, focused config-loader/runtime
  route-method tests, `git diff --check`, and full local `bin/verify` passed.
  Hosted deployment-chain evidence remains pending for this checkpoint.
- 2026-05-22: Commit `3c5d977`
  (`test: cover http route method mismatches`) adds focused evidence for the
  HTTP route method
  whitelist half of the roadmap's 405/426 route-readiness item. Native route
  matching now has regression coverage for `MethodNotAllowed` and sorted
  `Allow` methods, the native HTTP/1 listener has a network regression proving
  a method mismatch returns `405 Method Not Allowed` without queuing a
  Dart-dispatched HTTP request, and the Dart synthetic dispatch path has
  matching coverage for `405`, the `Allow` header, `method_not_allowed`, and no
  `http_request_dispatched` event. `ROADMAP.md` now marks the method/protocol
  whitelist item complete. Pre-change `bin/test-fast`, focused native
  `cargo test -p ct_core method_mismatch -- --nocapture`, focused Dart
  route-method runtime testing, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted `master` CI run `26282723125`,
  `add-router` CI run `26282711412`, hosted Dart Package Publish Dry Run runs
  `26282723109` and `26282711355`, hosted WAMP Profile Benchmarks runs
  `26282723154` and `26282711353`, hosted kTLS Validation runs `26282723160`
  and `26282711453`, Native Artifacts dry-run `26283321576`, and Router Image
  dry-run `26283321578` all passed at `3c5d977`. The strict deployment-chain
  audit passed required gates on `master` at `3c5d977`; RC readiness remains
  blocked only by explicit RC tag/prerelease/router-image tag selection and
  deferred pub.dev release-order decisions.
- 2026-05-22: Router HTTP route protocol whitelist enforcement now returns a
  deterministic protocol mismatch response instead of falling through to route
  not found. Native route matching canonicalizes HTTP protocol aliases and
  returns `ProtocolNotAllowed` for existing route paths served over disallowed
  protocols; HTTP/1 native responses return `426 Upgrade Required` with an
  `Upgrade` header, while HTTP/2 and HTTP/3 avoid invalid connection-specific
  upgrade headers. The Dart synthetic HTTP dispatch path mirrors the same
  `426` JSON error with `protocol_not_allowed`. Pre-change `bin/test-fast`,
  focused native and Dart route-protocol tests, and full local `bin/verify`
  passed. Commit `c45aa4b`
  (`fix: return 426 for http route protocol mismatch`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26278863274`, `add-router` CI run `26278857982`, hosted Dart Package
  Publish Dry Run runs `26278863327` and `26278857984`, hosted WAMP Profile
  Benchmarks runs `26278863232` and `26278857985`, hosted kTLS Validation runs
  `26278863231` and `26278858035`, Native Artifacts dry-run `26279547806`, and
  Router Image dry-run `26279547969` all passed at `c45aa4b`. The strict
  deployment-chain audit passed required gates on `master` at `c45aa4b`; RC
  readiness remains blocked only by explicit RC tag/prerelease/router-image tag
  selection and deferred pub.dev release-order decisions.
- 2026-05-13: The first RC target is a downstream-consumable GitHub prerelease
  with native artifacts and router image validation. Pub.dev publishing is
  deferred until package ownership, public versions, and release order are
  explicit.
- 2026-05-13: GitHub `master` is the default release branch. It currently
  represents the old single-package history, so promotion must merge the
  workspace branch into GitHub `master` while keeping the workspace layout.
- 2026-05-19: Before adding more feature surface, local `bin/test-fast`
  exposed a native WAMP worker readiness timeout in the bench integration
  suite. The worker readiness budget was raised from 20s to 60s, the stale
  local `ffi-test` native artifact was rebuilt during diagnosis, and focused
  WAMP transport repros, the full WAMP transport integration suite,
  `bin/test-fast`, and `bin/verify` passed locally.
- 2026-05-19: Commit `8058104` (`test: harden native wamp worker readiness`)
  was pushed to both configured remotes. GitHub `CI` run `26087763061`
  completed successfully with `Fast Checks` and `Full Verify` green, GitHub
  `WAMP Profile Benchmarks` run `26087763027` completed successfully, and
  GitHub `Dart Package Publish Dry Run` run `26087763335` completed
  successfully. The deployment-chain audit passed the clean latest CI, clean
  latest CI logs, and clean relevant Dart package publish dry-run gates for
  `add-router`.
- 2026-05-19: GitHub `Native Artifacts` run `26088923120` completed
  successfully for `v0.1.0-rc.1`, but the GitHub tag already exists at
  `47bbf9c`, so that run is stale-tag evidence rather than current-head
  no-mutation evidence. A unique validation-tag dry-run, GitHub `Native
  Artifacts` run `26089627231` for `v0.1.0-rc.1-validation.8058104`, failed
  during Sigstore signing after Cosign could not fetch ambient OIDC
  credentials on Linux x64, Linux arm64, and macOS Apple Silicon.
- 2026-05-19: The native artifact workflow now retries Cosign `sign-blob` and
  `verify-blob` calls up to three attempts, and the deployment-chain audit now
  accepts both project and native dry-run release-intent lines. Pre-change
  `bin/test-fast`, focused local validation, and full local `bin/verify`
  passed before commit.
- 2026-05-19: Commit `f2f8720` (`ci: harden native artifact dry-run evidence`)
  was pushed to both configured remotes. GitHub `CI` run `26090478456`
  completed successfully with `Fast Checks` and `Full Verify` green. GitHub
  `Native Artifacts` run `26090497983` completed successfully for
  `v0.1.0-rc.1-validation.f2f8720`; all five platform jobs and the dry-run
  release-preview job passed, no GitHub Release mutation occurred, and the
  `native-release-preview` artifact was uploaded. The deployment-chain audit
  passed the clean latest CI, clean latest CI logs, clean relevant Dart package
  publish dry-run, and clean native release dry-run gates for `add-router`.
- 2026-05-19: GitHub `Router Image` dry-run `26091104743` for
  `0.1.0-rc.1-validation.f2f8720` failed before publishing because
  `deploy/docker/Dockerfile` copied a root `pubspec.lock` that is not checked
  in for this workspace. The Dockerfile now copies only `pubspec.yaml` before
  `dart pub get`, matching the workspace's generated-lockfile build path.
- 2026-05-19: Commit `7f54fbb` (`ci: fix router image workspace build`) was
  pushed to both configured remotes. Follow-up GitHub `Router Image` dry-run
  `26091677645` for `0.1.0-rc.1-validation.7f54fbb` progressed to
  `dart compile exe`, then failed because `/out/connectanum_router` could not
  be opened when `/out` did not exist. The Dockerfile now creates `/out`
  before compiling the router runner. Local Docker validation is blocked
  because the local Docker daemon is not running. Full local `bin/verify`
  passed on 2026-05-19 for this Dockerfile output-directory fix.
- 2026-05-19: Commit `f30aa7f` (`ci: fix router image compile output`) was
  pushed to both configured remotes, and GitHub CI run `26092286670` passed.
  Follow-up GitHub `Router Image` dry-run `26092291070` for
  `0.1.0-rc.1-validation.f30aa7f` reached the Docker Rust release build for
  `ct_ffi`, then failed because the pinned `rust:1.85-bookworm` builder does
  not implement `Default` for raw pointer fields in `ct_ffi` FFI output
  structs. A local Rust 1.85 release build for `ct_ffi` reproduced the failure
  and now passes after adding explicit zeroed defaults for the `repr(C)`
  scalar/pointer buffers. `cargo fmt --all --check` from `native/transport`,
  `git diff --check`, and full local `bin/verify` passed on 2026-05-19 for
  this Rust 1.85 compatibility fix.
- 2026-05-19: Commit `6d681ab` (`fix: support rust 1.85 ffi defaults`) was
  pushed to both configured remotes. GitHub CI run `26093400216` passed, GitHub
  `Router Image` dry-run `26093405157` passed for
  `0.1.0-rc.1-validation.6d681ab`, and GitHub `Native Artifacts` dry-run
  `26094664567` passed for `v0.1.0-rc.1-validation.6d681ab` with all five
  `ct_ffi` platform jobs and release-preview upload green. The deployment-chain
  audit passed clean latest CI, clean latest CI logs, clean relevant Dart
  package publish dry-run, and clean native release dry-run gates for
  `add-router`. RC readiness still requires router image package visibility and
  current-head RC tag/prerelease selection; pub.dev remains deferred.
- 2026-05-19: The deployment-chain audit now exposes
  `--show-router-image-dry-run` and `--require-clean-router-image-dry-run`.
  The gate verifies the latest relevant manual Router Image dry-run completed
  successfully, uploaded `router-image-preview`, skipped GHCR login, completed
  the multi-arch build step, and still covers checked-out router image inputs.
  The gate passed locally against GitHub `Router Image` dry-run `26093405157`;
  GHCR package visibility remains a separate publish/approval gate.
- 2026-05-19: Commit `d01afce` (`ci: gate router image dry-run evidence`) was
  pushed to both configured remotes. GitHub CI run `26096473969` passed, and
  the strict deployment-chain audit passed clean latest CI, clean latest CI
  logs, clean relevant Dart package publish dry-run, clean native release
  dry-run, and clean router image dry-run gates for `add-router`. RC readiness
  remains blocked by router image package visibility/publish approval and
  current-head RC tag/prerelease selection; pub.dev remains deferred.
- 2026-05-19: Native HTTP/1 keep-alive idle timeouts are now treated as quiet
  lifecycle closures in `ct_core`, keeping generated router-hosted MCP
  consumer-package smoke logs clean while preserving diagnostics for
  non-timeout protocol and I/O read errors. Pre-change `bin/test-fast` passed
  and exposed the timeout diagnostic noise. Focused native regression,
  generated consumer-package smoke output scan, `git diff --check`, and full
  local `bin/verify` passed. Commit `f0c1590`
  (`fix: silence expected http1 idle timeouts`) was pushed to both configured
  remotes. GitHub CI run `26098749788`, GitHub WAMP Profile Benchmarks run
  `26098749790`, GitHub kTLS Validation run `26098749771`, GitHub `Native
  Artifacts` dry-run `26099397722`, GitHub `Router Image` dry-run
  `26099397318`, and the strict deployment-chain audit all passed for the new
  head. RC readiness remains blocked by router image package visibility/publish
  approval and current-head RC tag/prerelease selection; pub.dev remains
  deferred.
- 2026-05-19: The Router Image workflow now uses Node 24-backed Docker setup
  actions (`docker/setup-qemu-action@v4` and `docker/setup-buildx-action@v4`)
  instead of the Node 20-backed `v3` tags, and the Router Image dry-run audit
  now fails on warning/failure check-run annotations. Pre-change
  `bin/test-fast`, primary GitHub action metadata checks for `node24`,
  `bash -n bin/audit-github-deployment-chain`, Router Image workflow YAML
  parsing, `git diff --check`, an expected failing
  `bin/audit-github-deployment-chain --branch add-router
  --require-clean-router-image-dry-run` against the old Node 20-annotated
  dry-run, and full local `bin/verify` passed. Commit `5a10bd5`
  (`ci: harden router image action audit`) was pushed to both configured
  remotes. GitHub CI run `26102726359` passed with `Fast Checks` and
  `Full Verify` green, GitHub `Router Image` dry-run `26102736224` passed for
  `0.1.0-rc.1-validation.5a10bd5`, and the strict deployment-chain audit passed
  clean latest CI, clean latest CI logs, clean relevant Dart package publish
  dry-run, clean native release dry-run, and clean router image dry-run gates.
  The Router Image dry-run audit reported check annotations clean. RC readiness
  gained public GHCR registry package-visibility evidence in the follow-up
  audit hardening; current-head RC tag/prerelease selection remains blocked on
  a release decision and pub.dev remains deferred.
- 2026-05-19: The router package visibility gate now probes public GHCR
  registry pull metadata before falling back to GitHub Packages metadata:
  `tags/list` must expose at least one tag and the first visible tag must have
  a reachable manifest digest. Pre-change `bin/test-fast`, Bash syntax/help
  checks, `git diff --check`, the focused router package audit, an
  RC-readiness audit, and full local `bin/verify` completed; all required local
  gates passed. The package visibility gate currently reports public tag
  `v0.1.0-rc.1` with manifest digest
  `sha256:45d168f29a2b4c1c187ed21ff18c0f0539703b66c2709422cc414b360966b737`.
  Commit `65caf71` (`ci: audit ghcr router package visibility`) was pushed to
  both configured remotes. GitHub CI run `26105461957` passed with
  `Fast Checks` and `Full Verify` green, and the strict deployment-chain audit
  passed clean latest CI, clean latest CI logs, clean relevant Dart package
  publish dry-run, clean native release dry-run, clean router image dry-run,
  and router package visibility gates.
- 2026-05-19: The RC-readiness audit now inventories existing local RC tags
  when no RC tag points at the checked-out head, including each tag's target
  commit and stale/current status. Pre-change `bin/test-fast`, Bash syntax,
  help output, the focused RC-readiness audit, and full local `bin/verify`
  passed. Commit `cbe1e1d` (`ci: report stale rc tag evidence`) was pushed to
  both configured remotes. GitHub CI run `26108394380` passed with
  `Fast Checks` and `Full Verify` green, and the strict deployment-chain audit
  passed clean latest CI, clean latest CI logs, clean relevant Dart package
  publish dry-run, clean native release dry-run, clean router image dry-run,
  and router package visibility gates. The audit now reports
  `v0.1.0-rc.1 -> 47bbf9c` as stale for checked-out head `cbe1e1d`, so the
  remaining RC tag action is an explicit release decision to move the stale tag
  under policy or choose a follow-up RC tag.
- 2026-05-19: The RC-readiness audit now uses both local and GitHub RC tags
  for the checked-out-head tag gate, and prints stale-tag inventories from both
  sources when no RC tag points at the candidate head. Pre-change
  `bin/test-fast`, Bash syntax, help output, the focused RC-readiness audit,
  and full local `bin/verify` passed. Commit `e25c0c7` (`ci: audit github rc
  tag evidence`) was pushed to both configured remotes. GitHub CI run
  `26111109838` passed with `Fast Checks` and `Full Verify` green, and the
  strict deployment-chain audit passed clean latest CI, clean latest CI logs,
  clean relevant Dart package publish dry-run, clean native release dry-run,
  clean router image dry-run, and router package visibility gates. The audit
  reports both local and GitHub `v0.1.0-rc.1 -> 47bbf9c` as stale for
  checked-out head `e25c0c7`.
- 2026-05-19: The generated neutral consumer package smoke now covers
  protected MCP route missing-bearer rejection for standard resource/prompt
  helpers over direct JSON and Streamable HTTP, including `resources/list`,
  `resources/read`, `resources/templates/list`, `prompts/list`, `prompts/get`,
  and resource-prompt batch calls. Pre-change `bin/test-fast` passed.
  Post-change `bash -n bin/common.sh`, `bin/test-fast`, and full local
  `bin/verify` passed.
- 2026-05-19: The deployment-chain audit now requires latest hosted CI job and
  CI-log evidence to cover the checked-out commit exactly, rejecting stale
  green branch runs before they can satisfy `--require-clean-latest-ci`,
  `--require-clean-latest-ci-logs`, or RC readiness. A fake-`gh` regression is
  wired into `bin/test-fast` and `bin/test-all`. Focused Bash syntax checks,
  the fake-`gh` audit regression, the real current-head CI/log audit, and a
  fresh `bin/test-fast` passed locally.
- 2026-05-19: The fake-`gh` exact-head audit regression now synthesizes stale
  run SHAs instead of resolving `HEAD~1`, keeping the test valid in shallow
  GitHub Actions checkouts. Focused Bash syntax checks, the fake-`gh`
  regression, `git diff --check`, and `bin/test-fast` passed locally.
- 2026-05-19: The RC-readiness audit now accepts inspected Native Artifacts
  prerelease publish evidence as native hosted evidence only in RC-readiness
  mode. The standalone native release dry-run gate remains strict: it still
  requires a non-mutating dry-run intent and release-preview artifact. The
  fake-`gh` regression now covers a non-draft native prerelease targeting the
  checked-out commit with the expected asset inventory, and `bin/test-fast`
  passed locally.
- 2026-05-19: GitHub `master` was promoted to `2eced84` with an ancestry-only
  merge commit that preserves the already-verified `add-router` tree while
  making the previous GitHub `master` history an ancestor. Pre-merge
  `bin/test-fast` and post-merge local `bin/verify` passed. The `add-router`
  branch was pushed to both configured remotes, and GitHub `master` was updated
  by fast-forward. Hosted evidence for `master` is current and green: CI run
  `26125709823`, Dart Package Publish Dry Run `26125709820`, WAMP Profile
  Benchmarks `26125709822`, kTLS Validation `26125709821`, Native Artifacts
  dry-run `26126356470`, and Router Image dry-run `26126361337`. The strict
  deployment-chain audit passed clean latest CI, clean latest CI logs, clean
  Dart package dry-run, clean native release dry-run, clean router image
  dry-run, and router package visibility gates for `master`. The first
  `add-router` CI run for `2eced84` hit a hosted browser test harness flake
  while loading the web transport test, then passed after rerunning the failed
  job. Current-head RC tag/prerelease selection remains the only GitHub RC
  readiness blocker; no RC tag or GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now derives concrete, non-mutating
  follow-up RC tag suggestions from existing numeric local and GitHub RC tags
  when no RC tag points at the checked-out head. The fake-`gh` regression covers
  stale local and GitHub `v0.1.0-rc.1` tags and asserts that the audit suggests
  `v0.1.0-rc.2` while leaving RC prerelease selection not-ready. Pre-change
  `bin/test-fast`, focused Bash syntax, the audit regression module,
  `git diff --check`, a real read-only `master` RC-readiness audit, and full
  local `bin/verify` passed. No RC tag or GitHub Release was created or moved.
- 2026-05-20: The stale-RC fake-`gh` regression now also synthesizes local,
  GitHub, and GHCR validation/dry-run RC tags. It asserts that duplicate local
  and GitHub stale numeric tags produce exactly one `v0.1.0-rc.2` suggestion
  and that validation/dry-run RC tags do not become follow-up release-tag
  suggestions. Pre-change `bin/test-fast`, focused Bash syntax, the audit
  regression module, `git diff --check`, and full local `bin/verify` passed.
  No RC tag or GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now requires numeric RC tags for the
  checked-out-head release-tag gate while still inventorying RC-looking
  validation/dry-run tags as current or stale evidence. The fake-`gh`
  regression now points a validation/dry-run tag at the checked-out head and
  proves it does not satisfy RC tag readiness; the audit still suggests only
  the next numeric follow-up tag. Pre-change `bin/test-fast`, focused Bash
  syntax, the audit regression module, `git diff --check`, a real read-only
  `master` RC-readiness audit, and full local `bin/verify` passed. No RC tag or
  GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now reports the audited branch head and
  requires it to match the checked-out head before RC readiness or follow-up
  numeric RC tag suggestions are evaluated. A fake-`gh` regression covers a
  stale audited branch head and proves follow-up RC tag suggestions are
  suppressed until the audited branch and checkout are aligned. Pre-change
  `bin/test-fast`, focused Bash syntax, the audit regression module, help
  output, `git diff --check`, an aligned `add-router` RC-readiness summary, and
  full local `bin/verify` passed. A read-only `master` RC-readiness summary
  confirmed mismatch suppression, but GitHub returned a transient 502 while
  inspecting Dart package dry-run jobs, so that summary was not used as clean
  release evidence. No RC tag or GitHub Release was created or moved.
- 2026-05-20: The RC-readiness audit now also requires the audited branch to be
  the GitHub default branch before RC readiness or follow-up numeric RC tag
  suggestions are evaluated. A fake-`gh` regression covers an aligned
  non-default branch and proves follow-up RC tag suggestions are suppressed
  until the default branch is audited. Pre-change `bin/test-fast`, focused Bash
  syntax, the audit regression module, help output, `git diff --check`, a live
  read-only `add-router` RC-readiness summary, and full local `bin/verify`
  passed. The live summary reports `add-router` as branch/head aligned but not
  the default release branch, and it does not suggest `v0.1.0-rc.2` until
  `master` is audited from an aligned checkout. Commit `ea309d6` was pushed to
  GitLab `origin` and GitHub `add-router`; GitHub `CI` run `26135920644`
  passed, and the strict deployment-chain audit passed for `add-router` with RC
  readiness still not-ready because the audited branch is not the default
  release branch and no numeric RC tag points at `ea309d6`. No RC tag or GitHub
  Release was created or moved.
- 2026-05-20: The Native Artifacts release-intent path now treats project
  SemVer prerelease tags such as `v0.1.0-rc.2` as prereleases even when the
  workflow is triggered by a tag push or a manual dispatch without the explicit
  `prerelease=true` input. This prevents an approved RC tag from accidentally
  creating a stable GitHub Release. Pre-change `bin/test-fast` passed. Focused
  release-intent unit tests, a CLI validation for `v1.2.3-rc.1`, a workflow
  guard snippet check, an isolated bench package rerun, `git diff --check`, and
  full local `bin/verify` passed locally. Commit `06dee45` was pushed to GitLab
  `origin` and GitHub `add-router`; GitHub `CI` run `26137710822` passed,
  Native Artifacts dry-run `26138108909` passed for validation tag
  `v0.1.0-rc.1-validation.06dee45`, and the strict deployment-chain audit
  passed with RC readiness still not-ready because `add-router` is not the
  default release branch and no numeric RC tag points at `06dee45`. No RC tag or
  GitHub Release was created or moved.
- 2026-05-20: GitHub `master` was fast-forward promoted from `2eced84` to
  `06dee45` so the release-safety fix is on the default release branch. GitHub
  reported the protected-branch PR rule was bypassed for the direct update.
  Hosted `master` CI run `26138507065` passed, Native Artifacts dry-run
  `26138936777` passed for validation tag
  `v0.1.0-rc.1-validation.06dee45`, and the strict deployment-chain audit
  passed on `master` with clean CI/log, Dart package dry-run, native release
  dry-run, router image dry-run, workflow visibility, and router package
  visibility gates. RC readiness remains not-ready only because no approved
  numeric RC tag or GitHub prerelease points at `06dee45`; the audit suggests
  `v0.1.0-rc.2` as the next follow-up tag after release approval. No RC tag or
  GitHub Release was created or moved. A final local `bin/verify` handoff pass
  also completed successfully after the hosted evidence was recorded.
- 2026-05-20: GitHub `master` was fast-forward promoted again from `06dee45` to
  `0c0e043` so the route rate-limit implementation is on the default release
  branch. GitHub reported the protected-branch PR rule was bypassed for the
  direct update. Local `bin/test-fast` and `bin/verify` passed before
  promotion. Hosted `master` evidence is current and green: CI run
  `26150667099` passed after rerunning a transient browser harness load
  failure, Dart Package Publish Dry Run `26150666982` passed, WAMP Profile
  Benchmarks `26150666988` passed, Native Artifacts dry-run `26151756102`
  passed for validation tag `v0.1.0-rc.1-validation.0c0e043`, and Router Image
  dry-run `26151756160` passed for validation tag
  `0.1.0-rc.1-validation.0c0e043`. The strict deployment-chain audit passed on
  `master` with clean CI/log, Dart package dry-run, native release dry-run,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility gates. RC readiness remains not-ready only because no
  approved numeric RC tag or GitHub prerelease points at `0c0e043`; the audit
  suggests `v0.1.0-rc.2` as the next follow-up tag after release approval. No
  RC tag or GitHub Release was created or moved.
- 2026-05-20: Fixed router-hosted MCP direct JSON notification semantics on
  `add-router` so recognized notification-only tool calls suppress
  handler/validation error response bodies and keep returning `202 Accepted`
  with an empty body. Pre-change `bin/test-fast` passed. The focused MCP router
  smoke regression failed before the fix because an invalid notification
  returned a JSON-RPC error body, then passed after the fix. `git diff --check`,
  post-change `bin/test-fast`, and full local `bin/verify` also passed. Commit
  `5a3d6f3` was pushed to GitLab `origin` and GitHub `add-router`. Hosted
  `add-router` evidence passed at that head: CI run `26155949934` (Fast Checks
  and Full Verify), Dart Package Publish Dry Run `26155949954`, and WAMP Profile
  Benchmarks `26155949979`. No RC tag or GitHub Release was created or moved.
- 2026-05-20: Added router-hosted MCP direct JSON batch notification regression
  coverage to the native router smoke. The test posts an invalid
  notification-only `connectanum.tool.call` inside a mixed direct JSON batch and
  proves the notification error is suppressed while a following
  `connectanum.api.list` request returns as the only batch response.
  Pre-change `bin/test-fast`, the focused MCP router smoke regression,
  `git diff --check`, post-change `bin/test-fast`, and full local `bin/verify`
  passed. Commit `7fb63b0` was pushed to GitLab `origin` and GitHub
  `add-router`. Hosted `add-router` evidence passed at that head: CI run
  `26158162335` (Fast Checks and Full Verify), Dart Package Publish Dry Run
  `26158162312`, and WAMP Profile Benchmarks `26158162311`. The non-RC strict
  deployment-chain audit also passed clean latest CI, clean CI logs, and clean
  Dart package dry-run gates for `add-router` at `7fb63b0`. No RC tag or GitHub
  Release was created or moved.
- 2026-05-20: Added router-hosted MCP direct JSON all-notification batch
  coverage to the native router smoke. The test posts a valid notification-only
  `connectanum.tool.call` and an invalid notification-only `connectanum.tool.call`
  in one direct JSON batch, then proves the router returns `202 Accepted` with
  an empty body, no JSON payload, and no `mcp-session-id` header. Pre-change
  `bin/test-fast`, the focused MCP router smoke regression, `git diff --check`,
  post-change `bin/test-fast`, and full local `bin/verify` passed. Commit
  `7ed0e08` was pushed to GitLab `origin` and GitHub `add-router`. Hosted
  `add-router` evidence passed at that head: CI run `26160395220` (Fast Checks
  and Full Verify), Dart Package Publish Dry Run `26160395223`, and WAMP Profile
  Benchmarks `26160395225`. The non-RC strict deployment-chain audit also passed
  clean latest CI, clean CI logs, and clean Dart package dry-run gates for
  `add-router` at `7ed0e08`. No RC tag or GitHub Release was created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP CORS
  smoke to cover all-notification direct JSON tool-call batches on both public
  and bearer-protected routes. The generated smoke now posts a valid
  notification-only `connectanum.tool.call` for the consumer procedure plus an
  invalid missing-name `connectanum.tool.call` notification in one direct JSON
  batch, and asserts `202 Accepted`, empty body, no JSON payload, and no
  `mcp-session-id` header. Pre-change `bin/test-fast`, `bash -n bin/common.sh`,
  the focused `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `c0d8523` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26162406329` passed at `c0d8523` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove direct JSON notification batches have WAMP-side effects, not only the
  right HTTP shape. The smoke now records consumer procedure task ids, asserts a
  mixed direct JSON batch invokes its notification-only consumer procedure call,
  and asserts public plus bearer-protected all-notification CORS batches invoke
  the valid `connectanum.tool.call` notification while the invalid missing-name
  notification stays suppressed. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `2fc71a5` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26164678308` passed at `2fc71a5` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove direct JSON notification-only pub/sub publishes have WAMP-side
  effects on both public and bearer-protected routes. The smoke now subscribes
  through direct JSON, posts a valid `connectanum.pubsub.publish` notification
  and an invalid missing-topic publish notification in one all-notification
  batch, polls the subscription, and asserts only the valid event arrives.
  Pre-change `bin/test-fast`, `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `b48d952` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26167043374` passed at `b48d952` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove Streamable HTTP session notification-only pub/sub publishes have
  WAMP-side effects. The smoke now subscribes over Streamable HTTP, posts a
  notification-only `connectanum.pubsub.publish` batch with one valid publish
  and one invalid missing-topic publish, asserts no JSON-RPC response or
  Streamable session cursor mutation, then polls the subscription and asserts
  only the valid event arrives. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Commit `922fa1f` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted GitHub CI run
  `26169647527` passed at `922fa1f` with Fast Checks and Full Verify green, and
  the non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean relevant Dart package dry-run gates. Dart Package Publish Dry Run
  `26160395223` remains clean and relevant at previous commit `7ed0e08` because
  no publish-sensitive paths changed since then; WAMP Profile Benchmarks
  `26160395225` remain clean at `7ed0e08`. No RC tag or GitHub Release was
  created or moved.
- 2026-05-20: Extended the generated consumer package router-hosted MCP smoke
  to prove Streamable HTTP session notification-only direct tool calls have
  WAMP-side effects. The smoke now posts an all-notification
  `connectanum.tool.call` batch with one valid call and one invalid missing-name
  call, asserts no JSON-RPC response or immediate Streamable session cursor
  mutation, proves the valid WAMP procedure ran, drains the session, and proves
  the invalid notification did not invoke the procedure. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, the focused
  `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. Hosted `add-router`
  evidence is clean at this follow-up: commit `5b27b19` was pushed to GitLab
  `origin` and GitHub `add-router`, GitHub CI run `26172167427` passed with
  Fast Checks and Full Verify green, and the non-RC strict deployment-chain
  audit passed clean latest CI, clean CI logs, and clean relevant Dart package
  dry-run gates. Dart Package Publish Dry Run `26160395223` remains clean and
  relevant at previous commit `7ed0e08` because no publish-sensitive paths
  changed since then; WAMP Profile Benchmarks `26160395225` remain clean at
  `7ed0e08`. No RC tag or GitHub Release was created or moved.
- 2026-05-20: Added public direct Connectanum notification helpers for
  downstream application readiness. `McpStreamableHttpClient` now exposes
  `notifyConnectanumToolDirect(...)` and `notifyConnectanumMethodDirect(...)`
  as lifecycle-free direct JSON notification APIs, and the `connectanum_mcp_io`
  entrypoint re-exports them. Client tests and MCP package tests assert the
  helpers send notification-only JSON-RPC payloads without `id`, without
  Streamable session headers, and without mutating an active session id or SSE
  cursor. The generated consumer package router-hosted MCP smoke now calls both
  helpers against a consumer WAMP procedure and verifies the procedure is
  invoked through the public package surface. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused client/MCP package tests, the focused
  generated consumer package smoke, `git diff --check`, and full local
  `bin/verify` passed. Commit `6fcd450` was pushed to GitLab `origin` and
  GitHub `add-router`. Hosted `add-router` evidence is clean at this follow-up:
  GitHub CI run `26174880668` passed with Fast Checks and Full Verify green,
  Dart Package Publish Dry Run `26174880599` passed, WAMP Profile Benchmarks
  `26174880601` passed, and the non-RC strict deployment-chain audit passed
  clean latest CI, clean CI logs, and clean Dart package dry-run gates.
- 2026-05-20: Added a public direct WAMP pub/sub notification helper for
  downstream application readiness. `McpStreamableHttpClient` now exposes
  `notifyWampEventDirect(...)`, which sends `connectanum.pubsub.publish` as a
  notification-only direct JSON request without requiring downstream callers to
  assemble JSON-RPC payloads manually. Client tests and `connectanum_mcp_io`
  re-export tests assert the helper sends no JSON-RPC `id`, does not attach
  Streamable session headers, and does not mutate active Streamable session
  state. The generated consumer package router-hosted MCP smoke now subscribes
  through direct JSON, calls the helper, polls the event queue, and verifies
  the notification reaches the WAMP subscription. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused client/MCP package tests, the focused
  generated consumer package smoke, `git diff --check`, and full local
  `bin/verify` passed. Commit `a1ef285` was pushed to GitLab `origin` and
  GitHub `add-router`. Hosted `add-router` evidence is clean at this follow-up:
  GitHub CI run `26177091687` passed with Fast Checks and Full Verify green,
  Dart Package Publish Dry Run `26177091693` passed, WAMP Profile Benchmarks
  `26177091686` passed, and the non-RC strict deployment-chain audit passed
  clean latest CI, clean CI logs, and clean Dart package dry-run gates.
- 2026-05-20: This follow-up closes a direct Connectanum tool header
  parity gap. `callConnectanumToolDirect(...)` and
  `notifyConnectanumToolDirect(...)` now reuse cached `x-mcp-header` parameter
  metadata when sending lifecycle-free direct JSON tool calls and
  notifications, matching standard `tools/call` behavior after standard or
  Connectanum direct catalog discovery. Client tests assert generated
  `Mcp-Param-*` headers for call and notification helpers, and the generated
  client-only consumer-package smoke captures `Mcp-Param-Text` from an
  external-package endpoint. Pre-change `bin/test-fast`, `bash -n
  bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, and focused
  `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'` passed; full
  local `bin/verify` passed. Commit `ed88382` was pushed to GitLab `origin`
  and GitHub `add-router`. Hosted `add-router` evidence is clean at this
  follow-up: GitHub CI run `26179778871` passed with Fast Checks and Full
  Verify green, Dart Package Publish Dry Run `26179778866` passed, WAMP Profile
  Benchmarks `26179778869` passed, and the non-RC strict deployment-chain audit
  passed clean latest CI, clean CI logs, and clean Dart package dry-run gates.
- 2026-05-20: This implementation follow-up closes the router-hosted direct
  Connectanum tool alias side of the same header contract. The client now emits
  `Mcp-Name` for `connectanum.tool.call` and `connectanum.tools.call`, the
  router validates `Mcp-Name` plus `Mcp-Param-*` for those aliases using the
  same tool schema path as standard `tools/call`, and direct dotted tool
  methods validate any present parameter headers against their schema. Native
  router coverage now accepts matching `connectanum.tool.call` headers and
  rejects mismatched `Mcp-Param-*` values; the generated consumer-package
  router-hosted MCP smoke proves public direct helpers override bad
  caller-provided `Mcp-Name`/`Mcp-Param-*` headers before reaching the real
  router endpoint. Pre-change `bin/test-fast`, formatting, `bash -n
  bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, focused
  `dart test packages/connectanum_router/test/router_integration_native_test.dart
  --chain-stack-traces`, focused generated consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `7d0bddd`
  was pushed to GitLab `origin` and GitHub `add-router`. Hosted `add-router`
  evidence is clean at this follow-up: GitHub CI run `26183740303` passed with
  Fast Checks and Full Verify green, Dart Package Publish Dry Run
  `26183740300` passed, WAMP Profile Benchmarks `26183740754` passed, and the
  non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean Dart package dry-run gates.
- 2026-05-20: This follow-up broadens direct Connectanum tool header parity to
  the generic direct JSON method helpers.
  `callConnectanumMethodDirect(...)` and
  `notifyConnectanumMethodDirect(...)` now synthesize cached
  `Mcp-Param-*` headers for `tools/call`, `connectanum.tool.call`,
  `connectanum.tools.call`, and cached dotted tool-method calls, overriding
  stale caller-provided parameter headers before the router validates them.
  Client tests prove the generic alias and dotted-method paths emit corrected
  headers; the generated client-only consumer-package smoke captures corrected
  alias/dotted parameter headers; and the generated router-hosted consumer
  package smoke sends stale task/note headers through the public generic
  helpers to prove downstream applications can call a real router endpoint
  without hand-assembling trusted MCP parameter headers. Pre-change
  `bin/test-fast`, formatting, `bash -n bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, focused
  generated client-only and router-hosted consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `fb88885`
  implemented the generic helper/header smoke coverage, and follow-up commit
  `a411ed1` removed a Dart 3.12 analyzer-dead fallback exposed by the first
  hosted CI/dry-run attempt. Hosted `add-router` evidence is clean at
  `a411ed1`: GitHub CI run `26186967933` passed with Fast Checks and Full
  Verify green, Dart Package Publish Dry Run `26186967888` passed, WAMP
  Profile Benchmarks `26186967889` passed, and the non-RC strict
  deployment-chain audit passed clean latest CI, clean CI logs, and clean Dart
  package dry-run gates.
- 2026-05-20: This follow-up closes the notification-only side of the generic
  direct tool header contract. High-level direct Connectanum tool helpers now
  strip caller-provided `Mcp-Param-*` headers before adding regenerated cached
  parameter headers, preventing stale parameters from leaking through typed,
  alias, or dotted direct notification helpers. Client tests cover uncached
  stale-header removal plus cached typed, dotted-method, and
  `connectanum.tools.call` alias notification regeneration with active
  Streamable session state preserved. The generated client-only and
  router-hosted consumer-package smokes now send stale parameter headers
  through typed, alias, and dotted direct notification helpers and prove
  corrected captured headers or real router side effects. Pre-change
  `bin/test-fast`, formatting, `bash -n bin/common.sh`, focused
  `dart test -p vm test/mcp/streamable_http_client_test.dart`, focused
  generated client-only and router-hosted consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `bafbe25`
  was pushed to GitLab `origin` and GitHub `add-router`. Hosted `add-router`
  evidence is clean at this follow-up: GitHub CI run `26189389158` passed with
  Fast Checks and Full Verify green, Dart Package Publish Dry Run
  `26189389072` passed, WAMP Profile Benchmarks `26189389097` passed, and the
  non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean Dart package dry-run gates.
- 2026-05-20: This local follow-up extends stale `Mcp-Param-*` header safety
  evidence to direct WAMP pub/sub notification helpers. The focused client test
  now sends a stale `Mcp-Param-Topic` through `notifyWampEventDirect(...)` and
  asserts the lifecycle-free direct JSON notification carries no stale
  parameter headers. The generated router-hosted consumer-package smoke sends
  the same stale topic header through the public helper and proves the event is
  still delivered by the real router endpoint. Pre-change `bin/test-fast`,
  formatting, `bash -n bin/common.sh`, focused
  `dart test -p vm packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
  focused generated client-only and router-hosted consumer-package smokes,
  `git diff --check`, and full local `bin/verify` passed. Commit `4d80537` was
  pushed to GitLab `origin` and GitHub `add-router`. Hosted `add-router`
  evidence is clean at `4d80537`: CI run `26191487398` passed with Fast Checks
  and Full Verify green, Dart Package Publish Dry Run `26191487475` passed,
  WAMP Profile Benchmarks `26191487402` passed, and the non-RC strict
  deployment-chain audit passed clean latest CI, clean CI logs, and clean Dart
  package dry-run gates.
- 2026-05-20: This implementation follow-up adds a public
  Streamable-session WAMP pub/sub notification helper for consumer
  applications. `notifyWampEvent(...)` sends `connectanum.pubsub.publish` as a
  notification-only Streamable HTTP request while preserving the active MCP
  session and stripping stale caller-provided `Mcp-Param-*` headers through the
  same Connectanum method header path as direct helpers. Client tests prove the
  helper sends no JSON-RPC `id`, carries Streamable session headers, and drops
  stale `Mcp-Param-Topic`; the MCP IO export test proves the helper is
  available through `package:connectanum_mcp/connectanum_mcp_io.dart`; and the
  generated router-hosted consumer-package smoke proves the public helper
  delivers a WAMP event through a real router endpoint without mutating the SSE
  cursor. Pre-change `bin/test-fast`, formatting, `bash -n bin/common.sh`,
  focused client/MCP package tests, and the focused generated router-hosted
  consumer-package smoke passed locally. Full local `bin/verify` passed.
  Commit `1021cb9` was pushed to GitLab `origin` and GitHub `add-router`.
  Hosted `add-router` evidence is clean at `1021cb9`: CI run `26193409876`
  passed with Fast Checks and Full Verify green, Dart Package Publish Dry Run
  `26193409938` passed, WAMP Profile Benchmarks `26193409936` passed, and the
  non-RC strict deployment-chain audit passed clean latest CI, clean CI logs,
  and clean Dart package dry-run gates.
- 2026-05-21: This implementation follow-up adds standard MCP tool
  notification helpers for consumer applications. `notifyTool(...)` and
  `notifyToolDirect(...)` send id-free `tools/call` notifications, preserve the
  active MCP session and SSE cursor for Streamable HTTP, keep direct JSON
  lifecycle-free, and strip then regenerate stale caller-provided
  `Mcp-Param-*` headers from cached tool metadata. Client tests prove the
  Streamable and direct request shapes plus parameter-header regeneration; the
  MCP IO export test proves the helpers are available through
  `package:connectanum_mcp/connectanum_mcp_io.dart`; and the generated
  router-hosted consumer-package smoke proves standard direct and Streamable
  helper calls invoke a consumer WAMP procedure through a real router endpoint
  without private assumptions. Pre-change `bin/test-fast`, formatting,
  `bash -n bin/common.sh`, focused client/MCP package tests, the focused
  generated router-hosted consumer-package smoke, `git diff --check`, and full
  local `bin/verify` passed. Commit `b45a96f` was pushed to GitLab `origin`
  and GitHub `add-router`. Hosted `add-router` evidence is clean at
  `b45a96f`: CI run `26195189401` passed with Fast Checks and Full Verify
  green, Dart Package Publish Dry Run `26195189402` passed, WAMP Profile
  Benchmarks `26195189400` passed, and the non-RC strict deployment-chain
  audit passed clean latest CI, clean CI logs, and clean Dart package dry-run
  gates.
- 2026-05-21: GitHub `master` was fast-forward promoted from `0c0e043` to
  `b45a96f`, placing the router-hosted MCP downstream-readiness helpers on the
  default release branch. GitHub reported the PR-only branch rule was bypassed
  for the direct update. Local `bin/test-fast` passed before promotion, and
  post-promotion local `bin/verify` passed. Hosted `master` evidence is clean
  at `b45a96f`: CI run `26196195552` passed with Fast Checks and Full Verify
  green, Dart Package Publish Dry Run `26196195553` passed, WAMP Profile
  Benchmarks `26196195554` passed, and Router Image dry-run `26196649190`
  passed without GHCR login while uploading the preview artifact. Native
  Artifacts dry-run `26151756102` remains relevant because no
  native-release-sensitive paths changed since `0c0e043`. The strict
  deployment-chain audit passed clean current-head CI, clean CI logs, clean
  Dart package dry-run, native release dry-run relevance, fresh router image
  dry-run relevance, workflow visibility, branch protection, and router package
  visibility gates. RC readiness remains not-ready only because no approved
  numeric RC tag or GitHub prerelease points at `b45a96f`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag, and pub.dev publishing
  remains deferred for package ownership/version/release-order decisions.
- 2026-05-21: The deployment-chain audit now prints explicit branch-protection
  handoff evidence for pull-request enforcement and administrator bypass state.
  A fake-`gh` regression covers the protected default-branch output, and the
  live `master` audit reports `Require pull requests: true` and `Admin bypass
  allowed: true`, matching the direct-promotion bypass signal from GitHub.
  Pre-change `bin/test-fast`, `bash -n bin/audit-github-deployment-chain`,
  `python3 tool/test_audit_github_deployment_chain.py`, `git diff --check`,
  `bin/audit-github-deployment-chain --branch master --show-rc-readiness`, and
  full local `bin/verify` passed. Commit `882c207` was pushed to GitLab
  `origin` and GitHub `add-router`. Hosted `add-router` evidence is clean: CI
  run `26198235075` passed with Fast Checks and Full Verify green, and the
  gated deployment-chain audit passed current-head CI/log checks, workflow
  visibility, router package visibility, and the relevant Dart package dry-run
  gate. The latest Dart Package Publish Dry Run remains `26195189402` at
  `b45a96f`, and the audit accepts it because no publish-sensitive paths
  changed in `882c207`.
- 2026-05-21: GitHub `master` was fast-forward promoted from `b45a96f` to
  `882c207`, so the default release branch now includes the explicit
  branch-protection audit handoff evidence. GitHub again reported the PR-only
  branch rule was bypassed for the direct update, and the promoted audit output
  records `Require pull requests: true` with `Admin bypass allowed: true`.
  Local `bin/test-fast` passed before the promotion, and post-promotion local
  `bin/verify` passed. Hosted `master` CI run `26199199255` passed with Fast
  Checks in 4m26s and Full Verify in 6m15s. The strict deployment-chain audit
  passed clean current-head CI, clean CI logs, relevant Dart package dry-run,
  relevant native release dry-run, relevant router image dry-run, workflow
  visibility, branch protection, and router package visibility gates. The
  latest relevant runs remain Dart Package Publish Dry Run `26196195553`, WAMP
  Profile Benchmarks `26196195554`, Router Image dry-run `26196649190`, and
  Native Artifacts dry-run `26151756102`; the audit accepts that evidence
  because `882c207` changed only audit/tooling and docs paths that are not
  sensitive to those release gates. RC readiness remains not-ready only because
  no approved numeric RC tag or GitHub prerelease points at `882c207`; the
  audit suggests `v0.1.0-rc.2` as the next release-decision tag. No RC tag or
  GitHub Release was created or moved.
- 2026-05-21: The RC-readiness audit now refuses to accept a local-only
  numeric RC tag as sufficient GitHub prerelease evidence. A fake-`gh`/fake-git
  regression covers the stale-remote-tag case where a local tag points at the
  checked-out head but the GitHub tag does not; `--require-rc-ready` must keep
  the GitHub prerelease gate not-ready until the approved RC tag exists on
  GitHub at the checked-out head. Pre-change `bin/test-fast`,
  `bash -n bin/audit-github-deployment-chain`, and
  `python3 -m unittest tool/test_audit_github_deployment_chain.py` passed;
  full local `bin/verify` passed before handoff. Commit `11a9b24` was pushed
  to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  `master` CI run `26201026642` passed with Fast Checks and Full Verify green,
  and the strict deployment-chain audit passed required release-branch gates at
  `11a9b24`. RC readiness remains not-ready only because no approved numeric
  RC tag or GitHub prerelease points at `11a9b24`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up adds
  `McpStreamableHttpClient.callConnectanumMethod(...)` as the
  Streamable-session counterpart to `callConnectanumMethodDirect(...)`, letting
  consumer applications call router-provided dotted Connectanum methods through
  an active MCP session without hand-assembling direct JSON requests. Client
  coverage proves Streamable session headers are preserved and cached
  `Mcp-Param-*` headers are regenerated over stale caller headers; the MCP IO
  export test proves the helper is available through
  `package:connectanum_mcp/connectanum_mcp_io.dart` and works for
  `connectanum.pubsub.publish`; and the generated router-hosted
  consumer-package smoke proves the public helper publishes and receives a WAMP
  event through a real router endpoint without private assumptions. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused client/MCP tests, the
  focused generated router-hosted consumer-package smoke, and full local
  `bin/verify` passed.
- 2026-05-21: Hosted GitHub `master` and `add-router` CI for commit `3674e86`
  exposed a Linux Chrome/Dart2Wasm browser harness failure after the
  non-browser Full Verify suites had passed:
  `websocket_transport_web_test.dart` failed during test loading with
  `Bad state: Cannot add stream while adding stream`, then the test runner hung
  until the Full Verify job timed out as cancelled. The browser runtime smoke
  is now explicit in `bin/test-all`: hosted Linux CI uses the stable Dart2Js
  browser compiler for this Chrome smoke, while local/non-Linux runs keep the
  Dart2Wasm default from the package test config. Pre-change `bin/test-fast`
  passed before this CI-stability patch.
- 2026-05-21: Commit `462f4e0` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub CI passed at `462f4e0` for
  both promoted branches: `master` run `26204808842` and `add-router` run
  `26204805797` each completed Fast Checks and Full Verify successfully. A
  manual Router Image dry-run on `master` at `462f4e0`, run `26205189275`,
  completed successfully, uploaded the preview artifact, and skipped GHCR
  login. The strict deployment-chain audit passes required gates at `462f4e0`:
  latest CI job/log, Dart package publish dry-run relevance, native release
  dry-run relevance, router image dry-run relevance, workflow visibility,
  branch protection, and router package visibility. RC readiness remains
  not-ready only because no approved numeric RC tag or GitHub prerelease points
  at `462f4e0`; the audit suggests `v0.1.0-rc.2` as the next
  release-decision tag.
- 2026-05-21: This implementation follow-up adds focused public-surface
  coverage for `McpStreamableHttpClient.notifyConnectanumMethod(...)`, the
  Streamable-session notification counterpart to
  `callConnectanumMethod(...)`. Client tests prove the helper sends id-free
  JSON-RPC through the active MCP session while preserving the session id and
  SSE cursor and regenerating cached `Mcp-Param-*` headers over stale caller
  headers. The MCP IO export test proves the helper is available through
  `package:connectanum_mcp/connectanum_mcp_io.dart` for
  `connectanum.pubsub.publish`, and the generated router-hosted
  consumer-package smoke proves the public helper publishes and receives a WAMP
  event through a real router endpoint without private assumptions. Pre-change
  `bin/test-fast`, formatting, `bash -n bin/common.sh`, focused client/MCP
  package tests, the focused generated router-hosted consumer-package smoke,
  `git diff --check`, and full local `bin/verify` passed.
- 2026-05-21: Commit `79570a1` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26206356283` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26206354103` passed, Dart Package
  Publish Dry Run `26206356286` passed on `master`, WAMP Profile Benchmarks
  `26206356266` passed on `master`, and Router Image dry-run `26206759399`
  passed on `master` with preview artifact upload and skipped GHCR login. The
  strict deployment-chain audit passes required gates at `79570a1`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. RC readiness remains not-ready only because no approved
  numeric RC tag or GitHub prerelease points at `79570a1`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up adds public IO-entrypoint
  Streamable WAMP meta helper coverage for consumer applications. The MCP IO
  export smoke now initializes `McpStreamableHttpClient` through
  `package:connectanum_mcp/connectanum_mcp_io.dart`, calls typed WAMP meta
  helpers over session-aware `tools/call`, and asserts Streamable session id
  plus SSE cursor propagation through the package boundary. The coverage
  includes `countWampSessions(...)`, `matchWampRegistration(...)`,
  `countWampRegistrationCallees(...)`, `matchWampSubscription(...)`, and
  `countWampSubscriptionSubscribers(...)`. Pre-change `bin/test-fast`,
  formatting, focused
  `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
  `git diff --check`, and full local `bin/verify` passed.
- 2026-05-21: Commit `022811d` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26207890975` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26207886336` passed, Dart Package
  Publish Dry Run `26207890979` passed on `master`, and Dart Package Publish
  Dry Run `26207886355` passed on `add-router`. A fresh Router Image dry-run on
  `master`, run `26208362869`, passed for `022811d`, uploaded the preview
  artifact, skipped GHCR login, and kept the router image gate non-mutating.
  The strict deployment-chain audit passes required gates at `022811d`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. The latest WAMP Profile Benchmarks run remains
  `26206356266` at `79570a1` and is still relevant because this follow-up
  changed only MCP package test coverage and state docs, not
  benchmark-sensitive WAMP profile inputs. RC readiness remains not-ready only
  because no approved numeric RC tag or GitHub prerelease points at `022811d`;
  the audit suggests `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up expands the public IO-entrypoint
  Streamable WAMP meta smoke from representative helpers to the full typed
  session/registration/subscription helper surface. The MCP IO export smoke now
  initializes `McpStreamableHttpClient` through
  `package:connectanum_mcp/connectanum_mcp_io.dart`, calls all typed WAMP meta
  helpers over session-aware `tools/call`, asserts Streamable session id and
  SSE cursor propagation through `io-session-1:post:15`, and verifies
  representative request argument envelopes for session, registration, and
  subscription lookups. Pre-change `bin/test-fast`, formatting, focused
  `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
  `git diff --check`, and full local `bin/verify` passed.
- 2026-05-21: Commit `f9b4f31` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26209778136` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26209774233` passed, Dart Package
  Publish Dry Run `26209778116` passed on `master`, and Dart Package Publish
  Dry Run `26209774291` passed on `add-router`. A fresh Router Image dry-run on
  `master`, run `26210273976`, passed for `f9b4f31`, uploaded the preview
  artifact, skipped GHCR login, and kept the router image gate non-mutating.
  The strict deployment-chain audit passes required gates at `f9b4f31`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. The latest WAMP Profile Benchmarks run remains
  `26206356266` at `79570a1` and is still relevant because this follow-up
  changed only MCP package test coverage and state docs, not
  benchmark-sensitive WAMP profile inputs. RC readiness remains not-ready only
  because no approved numeric RC tag or GitHub prerelease points at `f9b4f31`;
  the audit suggests `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up closes the remaining public
  IO-entrypoint direct JSON WAMP subscription-meta package-boundary smoke gap.
  The MCP IO export smoke now calls `listWampSubscriptionsDirect(...)`,
  `lookupWampSubscriptionDirect(...)`, `matchWampSubscriptionDirect(...)`,
  `getWampSubscriptionDirect(...)`,
  `listWampSubscriptionSubscribersDirect(...)`, and
  `countWampSubscriptionSubscribersDirect(...)` through
  `package:connectanum_mcp/connectanum_mcp_io.dart`, asserts lifecycle-free
  direct JSON `connectanum.tool.call` request shapes without session headers,
  and verifies representative lookup/subscriber argument envelopes.
  Pre-change `bin/test-fast`, formatting, focused
  `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
  `git diff --check`, and full local `bin/verify` passed before handoff.
- 2026-05-21: Commit `548d267` was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted evidence is clean for both
  promoted branches: `master` CI run `26211691986` passed with Fast Checks and
  Full Verify green, `add-router` CI run `26211687420` passed, Dart Package
  Publish Dry Run `26211691941` passed on `master`, and Dart Package Publish
  Dry Run `26211687476` passed on `add-router`. A fresh Router Image dry-run on
  `master`, run `26212270565`, passed for `548d267`, uploaded the preview
  artifact, skipped GHCR login, and kept the router image gate non-mutating.
  The strict deployment-chain audit passes required gates at `548d267`:
  current-head CI/logs, Dart package dry-run, native release dry-run relevance,
  router image dry-run, workflow visibility, branch protection, and router
  package visibility. The latest WAMP Profile Benchmarks run remains
  `26206356266` at `79570a1` and is still relevant because this follow-up
  changed only MCP package test coverage and state docs, not
  benchmark-sensitive WAMP profile inputs. RC readiness remains not-ready only
  because no approved numeric RC tag or GitHub prerelease points at `548d267`;
  the audit suggests `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up adds WAMP Profile Benchmarks as a
  first-class deployment-chain audit and RC-readiness gate.
  `bin/audit-github-deployment-chain` now exposes
  `--show-wamp-profile-benchmarks` and
  `--require-clean-wamp-profile-benchmarks`; the gate verifies the latest
  `WAMP Profile Benchmarks` run status, expected `Linux WAMP profile gates`
  job, canonical validation step, benchmark artifact upload, and stale-run
  relevance across WAMP-profile-sensitive inputs. Fake-`gh` regression coverage
  accepts stale benchmark evidence when no sensitive inputs changed and rejects
  it when checked-out package inputs changed after the benchmark head. The
  hosted WAMP benchmark workflow path filter now includes
  `packages/connectanum_core/**` and root `pubspec.yaml`, matching the audit
  sensitivity for package/runtime inputs.
  Pre-change `bin/test-fast`, `bash -n bin/audit-github-deployment-chain`,
  `python3 -m unittest tool/test_audit_github_deployment_chain.py`, live
  `bin/audit-github-deployment-chain --branch master --strict
  --require-workflows-visible --require-router-package
  --require-clean-latest-ci --require-clean-latest-ci-logs
  --require-clean-dart-package-publish-dry-run
  --require-clean-native-release-dry-run --require-clean-router-image-dry-run
  --require-clean-wamp-profile-benchmarks --show-rc-readiness`,
  `git diff --check`, and full local `bin/verify` passed. Commit `9825526`
  (`ci: gate wamp profile benchmark evidence`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `9825526`: `master` CI run `26214693146` passed, `add-router` CI run
  `26214694060` passed, `master` WAMP Profile Benchmarks run `26214693251`
  passed, and `add-router` WAMP Profile Benchmarks run `26214693816` passed.
  The strict deployment-chain audit now passes required gates at `9825526`:
  current-head CI/logs, relevant Dart package dry-run, relevant native release
  dry-run, relevant router image dry-run, current-head WAMP profile benchmark
  evidence, workflow visibility, branch protection, and router package
  visibility. RC readiness remains not-ready only because no approved numeric
  RC tag or GitHub prerelease points at `9825526`; the audit suggests
  `v0.1.0-rc.2` as the next release-decision tag.
- 2026-05-21: This implementation follow-up hardens Dart package release-plan
  diagnostics for scoped package dry-runs. `bin/dart-package-publish-dry-run
  --show-release-plan` now inventories the full workspace package set even when
  the actual `dart pub publish --dry-run` target is scoped to one package, so
  release-order output cannot hide private packages that still affect a public
  publish. The actual archive dry-run remains scoped to the selected package
  targets. A fake-`dart` regression in
  `tool/test_dart_package_publish_dry_run.py` is wired into both
  `bin/test-fast` and `bin/test-all`, proving a scoped `connectanum_client`
  release plan still lists all private workspace packages and only runs one
  archive dry-run. The RC-readiness audit deferred-pub.dev summary now keeps
  the full release-plan headings when surfacing that inventory, so package
  lists are not detached from their meaning. Pre-change `bin/test-fast`,
  `python3 tool/test_dart_package_publish_dry_run.py`,
  `bin/dart-package-publish-dry-run --show-release-plan connectanum_client`,
  `python3 tool/test_audit_github_deployment_chain.py`, `git diff --check`, and
  full local `bin/verify` passed. Commit `4dec39c` (`ci: inventory dart package
  release plan`) was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `4dec39c`: `master` CI run
  `26217438556` passed, `add-router` CI run `26217438580` passed, `master` Dart
  Package Publish Dry Run run `26217438575` passed, and `add-router` Dart
  Package Publish Dry Run run `26217438585` passed. Focused audit readability
  tests and full local `bin/verify` passed for the headed deferred-pub.dev
  summary follow-up. Commit `7d60dd8` (`ci: label dart release-plan audit
  output`) was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted CI is clean at `7d60dd8`: `master` CI run `26218795344`
  passed with Fast Checks and Full Verify green, and `add-router` CI run
  `26218790197` passed with Fast Checks and Full Verify green. The strict
  deployment-chain audit passes required gates at `7d60dd8`; it accepts Dart
  Package Publish Dry Run run `26217438575` from `4dec39c` as relevant because
  no publish-sensitive paths changed in the audit-output follow-up. RC readiness
  remains not-ready only because no approved numeric RC tag or GitHub prerelease
  points at `7d60dd8`; the audit suggests `v0.1.0-rc.2`. Commit `becaf98` (`ci:
  publish dart release plan in dry-run workflow`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`, updating hosted Dart Package Publish
  Dry Run execution to call
  `bin/dart-package-publish-dry-run --show-release-plan`, so GitHub run logs and
  step summaries include the release-order inventory on publish-sensitive
  changes. Pre-change `bin/test-fast`,
  `python3 tool/test_dart_package_publish_dry_run.py`,
  `bin/dart-package-publish-dry-run --show-release-plan connectanum_client`,
  and full local `bin/verify` passed for this follow-up. Hosted GitHub evidence
  is clean at `becaf98`: `master` CI run `26220664156` passed with Fast Checks
  and Full Verify green, `add-router` CI run `26220660767` passed with Fast
  Checks and Full Verify green, `master` Dart Package Publish Dry Run run
  `26220664109` passed with release-plan sections visible in the log, and
  `add-router` Dart Package Publish Dry Run run `26220660832` passed with the
  same log evidence. The strict deployment-chain audit passes required gates at
  `becaf98`; RC readiness remains not-ready only because no approved numeric RC
  tag or GitHub prerelease points at `becaf98`; the audit suggests
  `v0.1.0-rc.2`.
- 2026-05-21: Commit `156192c` (`ci: audit rc router image tag evidence`)
  tightens the RC-readiness audit for router image evidence.
  `bin/audit-github-deployment-chain` now derives the required Router Image tag
  from the selected numeric RC tag (`v0.1.0-rc.N` -> `0.1.0-rc.N`) and probes
  that exact public GHCR manifest during `--show-rc-readiness` /
  `--require-rc-ready`, so generic package visibility can no longer mask a
  missing RC image tag. The fake-GitHub/GHCR regression suite covers both the
  ready path and a visible-package/missing-RC-image-tag failure. Pre-change
  `bin/test-fast`, focused `bash -n bin/audit-github-deployment-chain`,
  focused `python3 -m unittest tool/test_audit_github_deployment_chain.py`, a
  live read-only `bin/audit-github-deployment-chain --branch master
  --show-rc-readiness` summary, `git diff --check`, and full local `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub evidence is clean at `156192c`: `master` CI
  run `26222937612` passed with Fast Checks and Full Verify green,
  `add-router` CI run `26222934044` passed with Fast Checks and Full Verify
  green, and the strict deployment-chain audit passed required gates on
  `master`. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `babaa9f` (`ci: normalize manual router image tags`)
  normalizes manual Router Image workflow `image_tag` inputs that use project
  version refs, so a manual `v0.1.0-rc.N` input resolves to Docker tag
  `0.1.0-rc.N`, the same tag shape used by release-tag-triggered runs and exact
  RC audit checks. Manual
  `publish_approval` still has to match the normalized primary Docker tag, so an
  approval containing the leading `v` is rejected for normalized publishes.
  Pre-change `bin/test-fast`, focused `python3 -m unittest
  tool/test_render_router_image_metadata.py
  tool/test_render_native_release_notes.py`, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `babaa9f`: `master` CI run `26225035187` and `add-router` CI run
  `26225035212` passed with Fast Checks and Full Verify green, Router Image
  dry-run `26225059344` passed on `master` for manual `image_tag=v0.1.0-rc.2`
  without GHCR login, and the strict deployment-chain audit passed required
  gates on `master`. No RC tag, GitHub Release, or router image was created or
  moved.
- 2026-05-21: Commit `f91cc8b` (`ci: audit router image preview metadata`)
  hardens Router Image dry-run artifact evidence in the deployment-chain audit.
  The audit now downloads `router-image-preview`, verifies
  `router-image-metadata.md` targets `ghcr.io/konsultaner/connectanum-router`,
  requires dry-run mode and publish=false, parses and validates the primary
  Docker tag, and rejects project-version `v` prefixes that would not match
  exact RC image tag semantics. Pre-change `bin/test-fast`, focused `bash -n
  bin/audit-github-deployment-chain`, focused `python3 -m unittest
  tool/test_audit_github_deployment_chain.py`, live read-only
  `bin/audit-github-deployment-chain --branch master
  --show-router-image-dry-run`, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `f91cc8b`: `master` CI run `26228085097` and `add-router` CI run
  `26228080838` passed with Fast Checks and Full Verify green, and the strict
  deployment-chain audit passed required gates on `master` at `f91cc8b`. The
  strict audit accepts Router Image dry-run `26225059344` as relevant because no
  router-image-sensitive inputs changed after that run, downloads the preview
  metadata, and verifies primary tag `0.1.0-rc.2` before accepting the gate. No
  RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `9ba8748` (`fix: harden MCP auth error handling`) hardens
  downstream application behavior when a router-hosted auth bridge returns a
  non-JSON error body. `ConnectanumHttpAuthClient` now throws typed
  `ConnectanumHttpAuthException`s for non-success plain-text or HTML auth
  bridge responses, preserving status code and raw body with no decoded error
  payload, while successful malformed JSON still fails as malformed JSON. The
  focused `http_auth_client_test.dart` regression covers a plain-text 503
  challenge response, and the generated client-only consumer package smoke now
  proves the same behavior through
  `package:connectanum_mcp/connectanum_mcp_io.dart` using public APIs only.
  Local evidence: pre-change `bin/test-fast`, focused
  `dart test packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`,
  `bash -n bin/common.sh`, focused `run_mcp_client_package_smoke`,
  `git diff --check`, and clean-tree full `bin/verify` passed. The commit was
  pushed to
  GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
  evidence is clean at `9ba8748`: `master` CI run `26231778548`, `add-router`
  CI run `26231777640`, Dart Package Publish Dry Run runs `26231779191` on
  `master` and `26231777632` on `add-router`, and WAMP Profile Benchmarks runs
  `26231779087` on `master` and `26231777445` on `add-router` passed. Router
  Image dry-run `26232580498` passed on `master` for manual
  `image_tag=v0.1.0-rc.2` without GHCR login, uploaded preview metadata, and
  verified primary tag `0.1.0-rc.2`. The strict deployment-chain audit passed
  required gates on `master` at `9ba8748`; RC readiness still reports not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-21: Commit `34c9889` (`fix: select streamable mcp sse responses by
  id`) fixes downstream application response selection when a Streamable HTTP
  SSE POST stream includes server notifications before JSON-RPC responses. The
  client now matches response objects by request ID for single requests and
  batches, ignores interleaved notification events, and still captures the last
  SSE event ID for session resume. Focused client regressions and the generated
  client-only consumer package smoke cover the public package path using
  `connectanum_mcp_io`. Local evidence: pre-change `bin/test-fast`, focused
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `bash -n bin/common.sh`, focused `run_mcp_client_package_smoke`,
  `git diff --check`, clean-tree `bin/test-fast`, and clean-tree `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub `master` evidence is clean at `34c9889`: CI
  run `26235994960`, Dart Package Publish Dry Run `26235995708`, WAMP Profile
  Benchmarks `26235993239`, and Router Image dry-run `26236030117` passed. The
  strict deployment-chain audit passed required gates on `master` at
  `34c9889`; RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `4daf824` (`fix: honor mcp accept quality weights`)
  hardens router-hosted MCP Streamable HTTP content negotiation for downstream
  applications. The router now honors `q=0` media ranges in `Accept` headers
  before choosing JSON or SSE response paths, so explicit JSON rejection returns
  `406 Not Acceptable` before standard MCP header validation and explicit SSE
  rejection keeps session POST responses on JSON instead of an SSE stream.
  Fail-first focused coverage reproduced the compatibility gap in
  `guards MCP Streamable HTTP ingress and sessions`; the fixed focused native
  MCP ingress regression, `dart analyze packages/connectanum_router`,
  `git diff --check`, clean-tree `bin/test-fast`, and clean-tree `bin/verify`
  passed locally. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub `master` evidence is clean
  at `4daf824`: CI run `26239725979`, Dart Package Publish Dry Run
  `26239726467`, WAMP Profile Benchmarks `26239726002`, and Router Image
  dry-run `26239757142` passed. The strict deployment-chain audit passed
  required gates on `master` at `4daf824`; RC readiness still reports not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-21: Commit `a9dc2f6` (`fix: apply mcp accept specificity`) applies
  HTTP `Accept` media-range specificity to router-hosted MCP content
  negotiation. Exact
  `application/json;q=0` and `text/event-stream;q=0` ranges now reject those
  response types even when a less-specific wildcard such as `*/*;q=1` is
  present, so direct JSON and SSE clients cannot accidentally opt back into a
  response type they explicitly reject. Fail-first focused coverage reproduced
  `application/json;q=0, */*;q=1` returning `200` instead of `406` in
  `guards MCP Streamable HTTP ingress and sessions`; the fixed focused native
  MCP ingress regression, `dart analyze packages/connectanum_router`,
  `git diff --check`, `bin/test-fast`, and `bin/verify` pass locally.
  The commit was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `a9dc2f6`: `master` CI run
  `26242592111`, Dart Package Publish Dry Run `26242591939`, WAMP Profile
  Benchmarks `26242592123`, Router Image dry-run `26242601368`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `a9dc2f6`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-21: Commit `37dfd6f` (`fix: isolate mcp direct json sessions`) fixes
  router-hosted MCP direct JSON session isolation for downstream applications.
  Direct JSON POSTs that negotiate only `application/json` now ignore caller
  `MCP-Session-Id` headers when selecting the router endpoint and response
  lifecycle headers, so stale Streamable HTTP session IDs cannot make
  lifecycle-free direct tool/meta API calls return `404`. Streamable HTTP
  requests, GET polling, and DELETE session cleanup still enforce MCP session
  IDs. Fail-first focused coverage reproduced a stale direct `tools/list` call
  returning `404` in `guards MCP Streamable HTTP ingress and sessions`; the
  fixed focused native MCP ingress regression, `dart analyze
  packages/connectanum_router`, `git diff --check`, patched `bin/test-fast`,
  and patched `bin/verify` passed locally. The commit was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
  clean at `37dfd6f`: `master` CI run `26245432181`, Dart Package Publish Dry
  Run `26245432059`, WAMP Profile Benchmarks `26245432055`, Router Image
  dry-run `26245445679`, and matching `add-router` CI/dry-run/WAMP runs
  passed. The strict deployment-chain audit passed required gates on `master`
  at `37dfd6f`; RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `dea8697` (`fix: isolate mcp direct json error sessions`)
  closes the matching direct JSON error-response session leak. Router-hosted
  direct JSON POSTs that negotiate only `application/json` now suppress caller
  `MCP-Session-Id` headers on early error responses as well as successful direct
  JSON responses, including unsupported MCP protocol versions and malformed
  JSON bodies. True Streamable HTTP POSTs, GET polling, and DELETE session
  cleanup continue to preserve and enforce session lifecycle headers.
  Fail-first focused coverage reproduced stale response headers in
  `guards MCP Streamable HTTP ingress and sessions`; after the fix, the focused
  native MCP ingress regression, `dart analyze packages/connectanum_router`,
  `bash -n bin/common.sh`, focused generated consumer-package smoke,
  `git diff --check`, patched `bin/test-fast`, and full local `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub evidence is clean at `dea8697`: `master` CI
  run `26248484287`, Dart Package Publish Dry Run `26248484324`, WAMP Profile
  Benchmarks `26248484285`, Router Image dry-run `26248512314`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `dea8697`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-21: Commit `c54f36d` (`fix: isolate mcp route auth sessions`) closes
  the matching route-level auth response session leak before the MCP handler
  runs. Pre-dispatch MCP route auth and rate-limit failures now use the same
  direct-vs-Streamable response-session decision as router-hosted MCP handling,
  so lifecycle-free direct JSON POSTs that negotiate only `application/json`
  do not echo stale caller `MCP-Session-Id` headers on missing or invalid bearer
  token failures. True Streamable HTTP auth failures still preserve the owned
  session id. Fail-first generated consumer-package smoke reproduced the secure
  direct JSON missing-bearer stale-session leak; after the fix, focused
  generated consumer-package smoke, `bash -n bin/common.sh`,
  `dart analyze packages/connectanum_router`, focused native MCP ingress
  regression, patched `bin/test-fast`, and full local `bin/verify` passed. The
  commit was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
  `master`. Hosted GitHub evidence is clean at `c54f36d`: `master` CI run
  `26251320957`, Dart Package Publish Dry Run `26251320959`, WAMP Profile
  Benchmarks `26251320944`, Router Image dry-run `26251338983`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `c54f36d`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. No RC tag, GitHub Release, or
  router image was created or moved.
- 2026-05-21: Current local implementation follow-up adds focused router
  integration regression coverage for the MCP route-level auth response session
  contract. The secure route isolation test now proves lifecycle-free direct
  JSON POSTs with stale `MCP-Session-Id` headers do not echo that session id on
  missing or invalid bearer-token failures, while true Streamable HTTP POST auth
  failures still preserve the owned session id. Pre-change `bin/test-fast`,
  focused `isolates MCP Streamable HTTP sessions by route and bearer principal`
  router integration test, `git diff --check`, and full local `bin/verify`
  passed. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
  GitHub `master`. Hosted GitHub evidence is clean at `62c0146`: `master` CI
  run `26253868994`, Dart Package Publish Dry Run `26253868990`, WAMP Profile
  Benchmarks `26253868997`, Router Image dry-run `26254530985`, and matching
  `add-router` CI/dry-run/WAMP runs passed. The strict deployment-chain audit
  passed required gates on `master` at `62c0146`; RC readiness still reports
  not-ready only because no approved numeric RC tag, GitHub prerelease, or
  matching RC router image tag has been selected. The Router Image dry-run
  uploaded preview metadata for `0.1.0-rc.2` and skipped GHCR login. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-21: Commit `6db2c26`
  (`test: cover mcp rate-limit session isolation`) extends the same
  pre-dispatch MCP response-session boundary to route-level rate-limit coverage.
  The router runtime rate-limit test now proves lifecycle-free direct JSON POSTs
  with stale `MCP-Session-Id` headers do not echo that session id when the route
  limit has already been exceeded, while true Streamable HTTP POST failures
  still preserve the owned session id. Pre-change `bin/test-fast`, focused
  `rate limited MCP routes keep Streamable HTTP CORS headers` router runtime
  test, `git diff --check`, and full local `bin/verify` passed. The commit was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `6db2c26`: `master` CI run `26256185398`, Dart
  Package Publish Dry Run `26256185362`, WAMP Profile Benchmarks `26256185401`,
  Router Image dry-run `26256205180`, and matching `add-router` CI/dry-run/WAMP
  runs passed. The first `add-router` CI attempt failed in the hosted Dart
  browser harness before the browser test body ran, then the failed-job rerun
  passed. The strict deployment-chain audit passed required gates on `master` at
  `6db2c26`; RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected. The Router Image dry-run uploaded preview metadata for
  `0.1.0-rc.2` and skipped GHCR login. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-22: Commit `fafbc56`
  (`test: cover consumer mcp rate-limit smoke`) extends route-level rate-limit MCP
  response-session evidence from the focused router runtime test into the
  generated consumer-package router-hosted MCP smoke. The neutral consumer app
  now hosts a real rate-limited MCP route, spends the first two allowed
  requests on direct JSON `tools/list` and Streamable `initialize`, then proves
  the exhausted route returns `429 rate_limited` without echoing a stale direct
  JSON caller session id while preserving the owned Streamable session id on a
  true Streamable POST failure. Pre-change `bin/test-fast`,
  `bash -n bin/common.sh`, focused generated
  `run_mcp_consumer_package_smoke`, `git diff --check`, and full local
  `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `fafbc56`: `master` CI run `26258446014` and `add-router` CI run
  `26258445002` passed. The strict deployment-chain audit passed required
  gates on `master` at `fafbc56`, using current-head CI/log evidence plus the
  latest relevant Dart package dry-run, native dry-run, WAMP profile benchmark,
  and Router Image dry-run evidence. RC readiness still reports not-ready only
  because no approved numeric RC tag, GitHub prerelease, or matching RC router
  image tag has been selected. No RC tag, GitHub Release, or router image was
  created or moved.
- 2026-05-22: Commit `7f48714`
  (`fix: allow mcp delete after route limit`) lets MCP Streamable HTTP
  `DELETE` cleanup bypass the route-level rate-limit gate while retaining route
  auth/session validation. Fail-first focused runtime coverage reproduced
  cleanup `DELETE` returning `429` after route-limit exhaustion; after the fix,
  focused rate-limited MCP runtime tests, `bash -n bin/common.sh`, the
  generated consumer-package router-hosted MCP smoke,
  `dart analyze packages/connectanum_router`, `git diff --check`, and full
  local `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
  `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `7f48714`: `master` CI run `26260457692`, Dart Package Publish Dry Run
  `26260457644`, WAMP Profile Benchmarks `26260457656`, Router Image dry-run
  `26260908932`, and matching `add-router` CI/dry-run/WAMP runs passed. The
  first strict audit found the previous Router Image dry-run stale for this
  router-sensitive change; after manual non-mutating Router Image dry-run
  `26260908932`, the strict deployment-chain audit passed required gates on
  `master` at `7f48714`. RC readiness still reports not-ready only because no
  approved numeric RC tag, GitHub prerelease, or matching RC router image tag
  has been selected, and pub.dev publishing remains deferred for
  release-order/operator decisions. No RC tag, GitHub Release, or router image
  was created or moved.
- 2026-05-22: Commit `3a066b2`
  (`test: cover mcp client rate-limit cleanup`) adds public-client regression
  coverage for rate-limited Streamable HTTP cleanup.
  `McpStreamableHttpClient` now has focused test evidence that a `429`
  Streamable POST failure preserves the active session id and SSE cursor, and
  that a following `DELETE` cleanup still sends the owned `MCP-Session-Id`
  before clearing local state. Pre-change `bin/test-fast`, the focused
  `keeps Streamable HTTP session state after rate-limit failures` client test,
  the full `streamable_http_client_test.dart` suite, `git diff --check`, and
  full local `bin/verify` passed. The first full local `bin/verify` attempt hit
  stale failed-process native-runtime lock contention; after terminating that
  process group, the two affected benchmark tests passed in isolation and the
  full `bin/verify` rerun passed. The commit was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `3a066b2`: `master` CI run `26262595795`, Dart Package Publish Dry Run
  `26262595840`, WAMP Profile Benchmarks `26262595846`, Router Image dry-run
  `26263051056`, and matching `add-router` CI/dry-run/WAMP runs passed. The
  strict deployment-chain audit passed required gates on `master` at
  `3a066b2`. RC readiness still reports not-ready only because no approved
  numeric RC tag, GitHub prerelease, or matching RC router image tag has been
  selected, and pub.dev publishing remains deferred for release-order/operator
  decisions. No RC tag, GitHub Release, or router image was created or moved.
- 2026-05-22: Commit `c30e9d1`
  (`fix: keep mcp standard headers client-owned`) hardens public MCP HTTP
  client standard-header ownership. `McpStreamableHttpClient` now filters
  caller-provided `Mcp-Method` and `Mcp-Name` from constructor and per-call
  header maps before applying the synthesized single-message standard headers
  or intentionally omitting them on GET/SSE polling and JSON-RPC batches.
  Focused regression coverage now proves stale caller standard headers cannot
  leak into initialize, direct JSON, Streamable POST, GET/SSE poll, or batch
  requests while ordinary consumer trace headers still pass through.
  Pre-change `bin/test-fast`, `dart format`, the focused
  `owns MCP protocol and session headers despite caller headers` client test,
  the full `streamable_http_client_test.dart` suite, `git diff --check`, and
  full local `bin/verify` passed. The commit was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
  `c30e9d1`: `master` CI run `26264152549`, Dart Package Publish Dry Run
  `26264152546`, WAMP Profile Benchmarks `26264152545`, Router Image dry-run
  `26264557016`, and matching `add-router` CI/dry-run/WAMP runs passed. The
  first strict audit found the previous Router Image dry-run stale for this
  router-image-sensitive client/package change; after manual non-mutating
  Router Image dry-run `26264557016`, the strict deployment-chain audit passed
  required gates on `master` at `c30e9d1`. RC readiness still reports not-ready
  only because no approved numeric RC tag, GitHub prerelease, or matching RC
  router image tag has been selected, and pub.dev publishing remains deferred
  for release-order/operator decisions. No RC tag, GitHub Release, or router
  image was created or moved.
- 2026-05-22: Commit `6cc318b`
  (`test: cover consumer mcp standard headers`) extends the generated
  client-only MCP consumer package smoke to cover public package
  standard-header ownership. The smoke now sends stale caller `Mcp-Method` and
  `Mcp-Name` headers through direct JSON, Streamable POST, and GET/SSE poll
  requests, records standard MCP headers by consumer trace, and proves
  synthesized `Mcp-Method` values are client-owned while stale caller
  `Mcp-Name` values and GET/SSE standard MCP headers are stripped. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused
  `bash -lc 'source bin/common.sh && run_mcp_client_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. The commit was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `6cc318b`: `master` CI run `26265975937` and
  `add-router` CI run `26265972592` passed with Fast Checks and Full Verify
  green. The strict deployment-chain audit passed required gates on `master`
  at `6cc318b`, using current-head CI/log evidence plus still-relevant Dart
  package dry-run, native release dry-run, Router Image dry-run, and WAMP
  profile benchmark evidence because no package, native-release, router-image,
  or WAMP profile inputs changed in this script/docs checkpoint. RC readiness
  still reports not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order/operator decisions. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-22: Commit `f08e002`
  (`test: cover router mcp standard headers`) extends the generated
  router-hosted MCP consumer package smoke to cover public package
  standard-header ownership against a real router. The smoke now sends stale
  caller `Mcp-Method` and `Mcp-Name` headers through public direct JSON tool
  helper calls, generic Streamable JSON-RPC `tools/call` POSTs, Streamable WAMP
  pub/sub notifications, and Streamable tool notifications. This proves
  consumer-package APIs sanitize or own standard MCP headers before router
  validation across direct JSON and Streamable HTTP paths. Pre-change
  `bin/test-fast`, `bash -n bin/common.sh`, focused
  `bash -lc 'source bin/common.sh && run_mcp_consumer_package_smoke'`,
  `git diff --check`, and full local `bin/verify` passed. The commit was
  pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
  GitHub evidence is clean at `f08e002`: `master` CI run `26267304417` and
  `add-router` CI run `26267301141` passed with Fast Checks and Full Verify
  green. The strict deployment-chain audit passed required gates on `master`
  at `f08e002`, using current-head CI/log evidence plus still-relevant Dart
  package dry-run, native release dry-run, Router Image dry-run, and WAMP
  profile benchmark evidence because no package, native-release, router-image,
  or WAMP profile inputs changed in this script/docs checkpoint. RC readiness
  still reports not-ready only because no approved numeric RC tag, GitHub
  prerelease, or matching RC router image tag has been selected, and pub.dev
  publishing remains deferred for release-order/operator decisions. No RC tag,
  GitHub Release, or router image was created or moved.
- 2026-05-22: Current local implementation follow-up resets the public MCP
  Streamable HTTP client's SSE cursor when a response negotiates a different
  session id. `McpStreamableHttpClient._captureSessionHeaders` now clears
  `lastEventId` before adopting a changed non-empty `MCP-Session-Id`, keeping
  `Last-Event-ID` scoped to the active session after re-initialize or session
  rotation. The existing stale-session regression now asserts re-initialize
  clears the cursor. Pre-change `bin/test-fast`, focused
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
  `git diff --check`, and full local `bin/verify` passed. Commit `742c004`
  (`fix: reset mcp sse cursor on session change`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `742c004`: `master` CI run `26268556973`, `add-router` CI run
  `26268556046`, `master` Dart Package Publish Dry Run `26268556951`,
  `master` WAMP Profile Benchmarks `26268556950`, and manual non-mutating
  `master` Router Image dry-run `26268965259` passed. The strict
  deployment-chain audit passed required gates on `master` at `742c004`; RC
  readiness remains blocked only by explicit RC tag/prerelease/router-image
  tag selection and deferred pub.dev release-order decisions.
- 2026-05-22: Current local implementation follow-up makes public MCP
  Streamable HTTP cleanup safe when no session is active.
  `McpStreamableHttpClient.deleteSession()` now returns after local cleanup
  when `sessionId` is already null, clearing any orphan SSE cursor without
  sending an invalid network `DELETE` lacking `MCP-Session-Id`. This keeps
  downstream application `finally` cleanup paths safe after failed
  initialization, prior cleanup, or local state reset. Pre-change
  `bin/test-fast`, `dart format`, and focused
  `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
  passed, followed by full local `bin/verify`. Commit `182c236`
  (`fix: skip mcp delete without active session`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence
  is clean at `182c236`: `master` CI run `26270250594`, `add-router` CI run
  `26270245743`, `master` Dart Package Publish Dry Run `26270250595`,
  `add-router` Dart Package Publish Dry Run `26270245773`, `master` WAMP
  Profile Benchmarks `26270250619`, `add-router` WAMP Profile Benchmarks
  `26270245772`, and manual non-mutating `master` Router Image dry-run
  `26270676681` passed. The strict deployment-chain audit passed required
  gates on `master` at `182c236`; RC readiness remains blocked only by explicit
  RC tag/prerelease/router-image tag selection and deferred pub.dev
  release-order decisions.
- 2026-05-22: Release-gate test follow-up adds regression coverage for the
  first-RC Dart package deferral boundary.
  `tool/test_dart_package_publish_dry_run.py` now proves strict release-ready
  mode fails on the known `connectanum_client` private `connectanum_core`
  dependency while preserving zero-warning dry-run and release-plan output.
  `tool/test_audit_github_deployment_chain.py` now proves the RC audit rejects
  unexpected strict Dart package blockers instead of treating them as the
  intentional first-RC pub.dev deferral. Pre-change `bin/test-fast`, focused
  Python suites, `git diff --check`, and full local `bin/verify` passed. Commit
  `690c3c6` (`test: cover strict dart publish deferral`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26271999722` and `add-router` CI run `26271999694` passed with Fast Checks
  and Full Verify green. The strict deployment-chain audit passed required gates
  on `master` at `690c3c6`, using current-head CI/log evidence plus
  still-relevant Dart package dry-run, native release dry-run, Router Image
  dry-run, and WAMP profile benchmark evidence because no package,
  native-release, router-image, or WAMP profile inputs changed in this
  test/docs checkpoint. RC readiness remains blocked only by explicit RC
  tag/prerelease/router-image tag selection and deferred pub.dev release-order
  decisions.
- 2026-05-22: Local RC audit deferral hardening now requires the strict Dart
  publish dry-run output to include release-order and operator-decision
  evidence before treating the known private `connectanum_core` dependency as
  an intentional first-RC pub.dev deferral.
  `tool/test_audit_github_deployment_chain.py` adds fake-hosted RC coverage for
  a strict dry-run that has the known blocker but omits the release plan, and
  `bin/audit-github-deployment-chain` rejects missing release-plan evidence or
  contradictory warning-gate output. Pre-change `bin/test-fast`, focused
  `python3 tool/test_audit_github_deployment_chain.py`,
  `bash -n bin/audit-github-deployment-chain`, `git diff --check`, and the live
  read-only strict deployment-chain audit against `master` passed locally. Full
  local `bin/verify` passed for this follow-up. Commit `209b91c`
  (`test: require dart release plan for rc deferral`) was pushed to GitLab
  `origin`, GitHub `add-router`, and GitHub `master`. Hosted `add-router` CI
  run `26274323057` passed with Fast Checks and Full Verify green. Hosted
  `master` CI run `26274326442` passed with Fast Checks and a rerun Full Verify
  on attempt 2 after a hosted browser-runner load flake. The strict
  deployment-chain audit passed required gates on `master` at `209b91c`, using
  current-head CI/log evidence plus still-relevant Dart package dry-run, native
  release dry-run, Router Image dry-run, and WAMP profile benchmark evidence
  because no package, native-release, router-image, or WAMP profile inputs
  changed in this audit/test/docs checkpoint. RC readiness remains blocked only
  by explicit RC tag/prerelease/router-image tag selection and deferred pub.dev
  release-order decisions.
- 2026-05-22: Local hosted CI reliability follow-up hardens the client browser
  WebSocket smoke after `master` CI run `26274326442` needed a Full Verify rerun
  for a retryable package:test Chrome browser-manager load flake (`Bad state:
  Cannot add stream while adding stream`). `bin/test-all` now retries the
  browser smoke, uses the expanded reporter on non-final attempts to avoid
  GitHub error annotations, and keeps the default reporter on the final attempt
  so real failures remain visible. `tool/test_verification_scripts.py` regresses
  this verification-script contract and is wired into `bin/test-fast` and
  `bin/test-all`. Pre-change `bin/test-fast`, `bash -n bin/test-fast
  bin/test-all`, and focused `python3 tool/test_verification_scripts.py` passed;
  full local `bin/verify` passed for this follow-up. Commit `d9d8a82`
  (`ci: retry browser smoke on hosted flake`) was pushed to GitLab `origin`,
  GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
  `26276704174` and hosted `add-router` CI run `26276703045` passed with Fast
  Checks and Full Verify green. The strict deployment-chain audit passed
  required gates on `master` at `d9d8a82`, using current-head CI/log evidence
  plus still-relevant Dart package dry-run, native release dry-run, Router Image
  dry-run, and WAMP profile benchmark evidence because no package,
  native-release, router-image, or WAMP profile inputs changed in this
  CI-script/docs checkpoint. RC readiness remains blocked only by explicit RC
  tag/prerelease/router-image tag selection and deferred pub.dev release-order
  decisions.

## Handoff

Active. The latest fully clean hosted implementation follow-up makes
router-hosted MCP Streamable HTTP `DELETE` dispose endpoint-owned WAMP pub/sub
subscriptions.
`_RouterMcpEndpoint` now tracks subscription ids created through MCP pub/sub
helpers, removes ids on explicit unsubscribe, and best-effort unsubscribes
remaining ids when DELETE removes the MCP session or the endpoint is disposed.
Router integration coverage and the generated consumer-package smoke prove a
Streamable MCP subscription has one route-visible subscriber before DELETE and
zero after DELETE through direct JSON WAMP subscription meta. Local focused
coverage, full `bin/verify`, hosted CI on `master` and `add-router`, hosted
Dart Package Publish Dry Run on both branches, hosted WAMP Profile Benchmarks
on both branches, current-head Router Image dry-run, and the strict
deployment-chain audit passed at `383e0a9`. RC readiness remains blocked only
by explicit RC tag/prerelease/router-image tag selection and deferred pub.dev
release-order decisions. The prior fully clean hosted implementation checkpoint
is `3c5d977`, which adds router-hosted HTTP method-mismatch coverage across
native matching, native HTTP/1 responses, and Dart synthetic dispatch; hosted
CI, hosted Dart Package Publish Dry Run, hosted WAMP Profile Benchmarks, hosted
kTLS Validation, Native Artifacts dry-run, Router Image dry-run, and the strict
deployment-chain audit passed at `3c5d977`. The prior fully clean hosted
implementation follow-up makes router-hosted HTTP route protocol mismatches
return deterministic `426 protocol_not_allowed` responses instead of ambiguous
route misses across native and Dart synthetic dispatch. The
prior fully clean hosted CI reliability follow-up adds a retrying browser
WebSocket smoke wrapper to `bin/test-all` and a focused verification-script
regression wired into fast/full local verification; local `bin/verify`, hosted
CI on `master` and `add-router`, and the strict deployment-chain audit passed
at commit `d9d8a82`. The prior fully clean hosted release-chain follow-up hardens the
first-RC pub.dev deferral boundary so the audit requires strict Dart dry-run
release-plan and operator-decision evidence before accepting the known private
workspace dependency blocker; pre-change `bin/test-fast`, focused audit tests,
`bash -n`, `git diff --check`, live read-only strict deployment-chain audit,
full local `bin/verify`, hosted CI on `master` and `add-router`, and the strict
deployment-chain audit passed at commit `209b91c`. The prior fully clean hosted
release-gate test follow-up hardens the Dart package strict publish and RC
audit unexpected-blocker boundary; local `bin/test-fast`, focused Python
regressions, `git diff --check`, full `bin/verify`, hosted CI on `master` and
`add-router`, and the strict deployment-chain audit passed at commit `690c3c6`.
The prior fully clean hosted
implementation follow-up makes
`McpStreamableHttpClient.deleteSession()` a local cleanup no-op when no
Streamable HTTP session is active, so downstream applications can call cleanup
after failed initialization or prior cleanup without generating an invalid
network DELETE; pre-change `bin/test-fast`, formatting, the focused MCP client
suite, full local `bin/verify`, hosted CI, hosted Dart package dry-run, hosted
WAMP profile benchmark, hosted Router Image dry-run, and the strict
deployment-chain audit passed at commit `182c236`. The prior fully clean hosted
implementation follow-up keeps
`McpStreamableHttpClient` SSE cursors scoped to the negotiated Streamable HTTP
session by clearing `lastEventId` whenever a response changes the active
`MCP-Session-Id`; local focused MCP client tests, full `bin/verify`, hosted
CI, hosted Dart package dry-run, hosted WAMP profile benchmark, hosted Router
Image dry-run, and the strict deployment-chain audit passed at commit
`742c004`.
The prior fully clean hosted implementation follow-up extends the generated
router-hosted MCP consumer package smoke so public consumer-package usage
proves `Mcp-Method`/`Mcp-Name` ownership against a real router across direct
JSON and Streamable HTTP tool/pubsub paths. The prior fully clean hosted
implementation follow-up extends the generated client-only MCP consumer package
smoke so consumer-style public package usage proves `Mcp-Method`/`Mcp-Name`
ownership across direct JSON, Streamable POST, and GET/SSE poll requests. The
prior fully clean hosted implementation follow-up hardens public MCP HTTP
client standard-header ownership so stale caller `Mcp-Method`/`Mcp-Name`
headers cannot leak into
initialize, direct JSON, Streamable POST, GET/SSE poll, or batch requests. The
prior fully clean hosted implementation follow-up adds public-client regression
coverage proving
`McpStreamableHttpClient`
preserves active Streamable session state after `429` rate-limit failures and
can still send session-scoped `DELETE` cleanup. The prior fully clean hosted
implementation follow-up lets router-hosted MCP Streamable HTTP `DELETE`
cleanup bypass route-level rate-limit exhaustion so a downstream application
can remove its owned session after receiving a rate-limited Streamable POST
failure. The latest fully clean hosted deployment-chain checkpoint is
`3c5d977`. The prior fully hosted implementation follow-up extends the
generated consumer-package router-hosted MCP smoke so downstream applications
prove the route-level rate-limit response-session contract against a real MCP
endpoint. The prior fully hosted
implementation follow-up adds focused router runtime regression coverage
proving pre-dispatch MCP route rate-limit response session isolation for
lifecycle-free direct JSON POST failures while preserving owned session ids for
true Streamable HTTP POST failures. The prior fully hosted
implementation follow-up adds focused router integration regression coverage
proving pre-dispatch MCP route auth response session isolation for direct JSON
missing/invalid bearer failures while preserving owned session ids for true
Streamable HTTP auth failures. The prior fully hosted implementation
fixed pre-dispatch MCP route auth response session isolation so lifecycle-free
direct JSON requests cannot echo stale `MCP-Session-Id` headers through missing
or invalid bearer-token errors. The prior fully hosted implementation fixed
router-hosted MCP direct JSON
error-response session isolation so stale `MCP-Session-Id` headers cannot leak
back through lifecycle-free malformed-body or unsupported-protocol errors. The
prior fully hosted implementation before that fixed router-hosted MCP direct
JSON endpoint lookup and success-response session isolation so stale session
headers cannot make lifecycle-free direct JSON tool/meta API calls return
`404`. Prior
implementation follow-ups apply HTTP `Accept` media-range specificity so exact
`q=0` JSON/SSE media ranges override less-specific wildcards before
router-hosted MCP JSON/SSE response-path selection, honor MCP Accept quality
weights, fix MCP Streamable HTTP SSE response selection when notifications are
interleaved before JSON-RPC responses, harden MCP HTTP auth client non-JSON
error handling for downstream applications, inspect Router Image dry-run
preview metadata, normalize manual Router Image project-version tag inputs to
the Docker tag shape required by exact RC audit evidence, and tighten
RC-readiness router image tag auditing.
The hosted Dart Package Publish Dry Run now prints the same release-order
inventory that local and audit dry-runs already expose. The default branch
contains the router-hosted MCP downstream-readiness work plus explicit
branch-protection and GitHub RC-tag audit handoff evidence; the latest hosted
implementation checkpoints harden scoped Dart package release-plan diagnostics
and add the WAMP Profile Benchmarks evidence gate. MCP coverage includes auth/session
correctness, router-provided MCP endpoints, direct JSON tool and meta APIs,
WAMP pub/sub helpers, resources/prompts, Streamable HTTP compatibility, and
generated consumer-package smokes that use public package APIs without private
project assumptions.

Hosted `master` CI is green at run `26282723125` for checkpoint `3c5d977`: Fast
Checks and Full Verify passed. Hosted `add-router` CI is green at run
`26282711412` with Fast Checks and Full Verify passed. Hosted Dart Package
Publish Dry Run is green at run `26282723109` on `master`, and matching
`add-router` Dart Package Publish Dry Run `26282711355` passed. Hosted
`master` WAMP Profile Benchmarks run `26282723154` passed with artifact upload,
and matching `add-router` WAMP Profile Benchmarks run `26282711353` passed.
Hosted kTLS Validation runs `26282723160` on `master` and `26282711453` on
`add-router` passed. Native Artifacts dry-run `26283321576` passed for
`v0.1.0-rc.2-validation.3c5d977`, and Router Image dry-run `26283321578`
passed for `0.1.0-rc.2-validation.3c5d977`. The strict deployment-chain audit
passes on `master` at `3c5d977` with clean current-head CI/log, relevant Dart
package dry-run, relevant native release dry-run, relevant router image
dry-run, relevant WAMP profile benchmark evidence, workflow visibility, branch
protection, and router package visibility gates.
The router package visibility gate verifies public GHCR registry metadata for
`ghcr.io/konsultaner/connectanum-router`. The latest Router Image dry-run is
run `26283321578` at `3c5d977`; it used manual
`image_tag=0.1.0-rc.2-validation.3c5d977`, uploaded the preview artifact,
skipped GHCR login, completed the multi-arch build, and the audit verifies
primary tag `0.1.0-rc.2-validation.3c5d977` before accepting it.

Continue with RC tag/prerelease selection from a checkout aligned with GitHub
`master`. The audit inventories stale
local and GitHub RC tags and reports that existing `v0.1.0-rc.1` points at
older commit `47bbf9c`, not the current candidate head `3c5d977`. It suggests
`v0.1.0-rc.2` exactly once as the next numeric follow-up tag while still
reporting RC prerelease and matching router image RC tag selection as not-ready.
Moving the stale tag or approving a follow-up RC tag remains a release decision.
No RC tag, GitHub Release, or router image was created or moved during this
promotion/evidence update.
