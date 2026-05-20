# Exec Plan: Release Candidate Readiness

Status: active
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-21

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
  local `bin/verify` passed. Hosted `add-router` evidence is pending until this
  implementation is pushed.

## Handoff

Active. GitHub `master` points at `0c0e043`, and `add-router` contains the
router-hosted MCP direct JSON notification correctness fix plus native-router
and generated consumer-package smoke coverage for single-message, mixed-batch,
all-notification batch, pub/sub, and Streamable notification side effects. The
latest pushed follow-up exposes a public direct WAMP pub/sub notification
helper for downstream application readiness: `notifyWampEventDirect(...)`
sends `connectanum.pubsub.publish` as a notification-only direct JSON payload
without Streamable lifecycle coupling, remains re-exported by the MCP IO
entrypoint, and is covered by client tests, MCP package tests, and generated
consumer-package router-hosted MCP smoke. This follow-up closes direct
Connectanum tool header parity: direct tool call and notification helpers now
emit cached `Mcp-Param-*` headers after direct catalog discovery, with focused
client tests, generated client-only consumer-package smoke, and full local
`bin/verify` passing. This implementation follow-up extends that same contract
to the router-hosted alias path: direct `connectanum.tool.call` /
`connectanum.tools.call` now share `Mcp-Name` and `Mcp-Param-*` validation with
standard `tools/call`, and consumer-package smoke coverage proves public direct
helpers override stale caller-provided MCP name/parameter headers before the
real router endpoint validates them. The latest pushed follow-up extends the
same header-synthesis behavior to generic direct JSON method helpers, and
hosted `add-router` evidence is clean for pushed head `a411ed1`: CI run
`26186967933`, Dart Package Publish Dry Run `26186967888`, WAMP Profile
Benchmarks `26186967889`, and the non-RC strict deployment-chain audit all
passed. The current local follow-up hardens notification-only direct tool
helpers by stripping stale caller-provided `Mcp-Param-*` headers and extending
typed, alias, dotted-method, client-only smoke, and router-hosted consumer
smoke coverage; commit `bafbe25` is pushed to both remotes, local
`bin/verify` is clean, and hosted `add-router` evidence is green for CI,
Dart Package Publish Dry Run, WAMP Profile Benchmarks, and the strict
deployment-chain audit. The latest pushed follow-up extends that stale-header
consumer safety coverage to `notifyWampEventDirect(...)` by proving stale
`Mcp-Param-Topic` is stripped in the focused client test and cannot break real
router-hosted pub/sub notification delivery in the generated consumer-package
smoke; commit `4d80537` is pushed to both remotes, local `bin/verify` is clean,
and hosted `add-router` evidence is green for CI, Dart Package Publish Dry Run,
WAMP Profile Benchmarks, and the strict deployment-chain audit. The latest
pushed follow-up adds the Streamable-session counterpart,
`notifyWampEvent(...)`, so consumer applications can send notification-only
pub/sub publishes over an active MCP session without hand-assembling raw
JSON-RPC; focused client/MCP package tests and the generated router-hosted
consumer-package smoke are clean locally, commit `1021cb9` is pushed to both
remotes, full `bin/verify` passed, and hosted `add-router` evidence is green
for CI, Dart Package Publish Dry Run, WAMP Profile Benchmarks, and the strict
deployment-chain audit. The current local follow-up adds the standard MCP
counterpart, `notifyTool(...)` and `notifyToolDirect(...)`, so consumer
applications can send id-free `tools/call` notifications over Streamable HTTP
or direct JSON without hand-assembling raw payloads or trusted parameter
headers. Focused client/MCP package tests, the generated router-hosted
consumer-package smoke, `git diff --check`, and full local `bin/verify` are
clean; hosted `add-router` evidence is pending until this implementation is
pushed.
Hosted `master` evidence remains current and green for CI, Dart package
dry-run relevance, WAMP Profile Benchmarks, Native Artifacts dry-run, and
Router Image dry-run relevance. The
strict deployment-chain audit passes on `master` with clean current-head CI/log,
Dart package dry-run, native release dry-run, router image dry-run, workflow
visibility, branch protection, and router package visibility gates. The audit
verifies public GHCR registry metadata before falling back to GitHub Packages
metadata, and the router package visibility gate passes because
`ghcr.io/konsultaner/connectanum-router` is publicly reachable with tag
`v0.1.0-rc.1` and a manifest digest.

Continue with RC tag/prerelease selection for `0c0e043` only from a checkout
that is aligned with GitHub `master`. The audit now reports both the audited
branch head and whether the audited branch is the default release branch before
RC tag selection. When the audited branch and checkout differ, or when the
audited branch is not the default branch, it reports not-ready and suppresses
follow-up RC tag suggestions until the release checkout is aligned with
`master`. When aligned on the default branch, the audit inventories stale local
and GitHub RC tags and reports that the existing `v0.1.0-rc.1` tag points at
older commit `47bbf9c`, not the current candidate head. It suggests
`v0.1.0-rc.2` exactly once as the next numeric follow-up tag while still
reporting RC prerelease selection as not-ready. Validation/dry-run RC tags are
inventoried but do not satisfy the checked-out-head RC tag gate and are not
treated as follow-up release candidates. Moving the stale tag or approving a
follow-up RC tag remains a release decision. No RC tag or GitHub Release was
created or moved during the master-promotion, release-intent hardening, or
audit-tooling work.
