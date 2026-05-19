# Exec Plan: Release Candidate Readiness

Status: active
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-19

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

## Handoff

Active. Router image dry-run build blockers found on `f2f8720`, `7f54fbb`, and
`f30aa7f` are fixed, native HTTP/1 idle-timeout diagnostics no longer pollute
router-hosted MCP consumer smoke logs, the Router Image workflow/audit path is
hardened against Node 20 deprecation annotations, and the router-hosted MCP
consumer smoke now rejects missing credentials across protected direct JSON and
Streamable resource/prompt helper paths. The deployment-chain audit now rejects
stale hosted CI/log runs whose `headSha` does not match the checked-out commit,
so RC readiness cannot accidentally rely on older green branch evidence.
Hosted CI evidence is clean for the previous implementation head, and the
current local audit confirmed CI/log evidence still covers the checked-out head
before this audit-hardening commit. Relevant Dart package, native release, and
router image dry-run evidence is still clean; and the strict deployment-chain
audit passes the Dart package dry-run, native release dry-run, router image
dry-run, and router package visibility gates when CI/log evidence is current.
The audit verifies public GHCR registry metadata before falling back to GitHub
Packages metadata, and the router package visibility gate passes because
`ghcr.io/konsultaner/connectanum-router` is publicly reachable with tag
`v0.1.0-rc.1` and a manifest digest. Continue with RC tag/prerelease selection
for the current head. The audit inventories stale local and GitHub RC tags and
reports that the existing `v0.1.0-rc.1` tag points at the older `47bbf9c`
commit in both sources, not the current candidate head; retagging or choosing
a follow-up RC tag remains a release decision.
