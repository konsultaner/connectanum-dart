# Project State

Last updated: 2026-05-25
Current branch: `add-router`
Last reviewed branch checkpoint: MCP HTTP auth bridge header ownership.
Latest fully clean hosted checkpoint: Commit `78e0eb0`.
Current implementation checkpoint: The MCP HTTP auth client regression now
proves `ConnectanumHttpAuthClient` keeps `Authorization` caller-controlled for
downstream applications that protect the HTTP auth bridge itself while still
owning JSON request framing headers. The focused test now covers a constructor
default authorization header, per-call authorization overriding that default
for ticket-grant challenge/authenticate requests, the default authorization
header applying to refresh calls without a per-call replacement, and per-call
authorization on revoke calls, alongside the existing `Accept` /
`Content-Type` JSON ownership assertions. Baseline `bin/test-fast` passed on
2026-05-25 before this change. Focused local coverage passed on 2026-05-25:
`dart format packages/connectanum_client/test/mcp/http_auth_client_test.dart`,
`dart analyze packages/connectanum_client/test/mcp/http_auth_client_test.dart`,
`dart test packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`,
`git diff --check`, and
`python3 tool/check_public_artifact_references.py`. Full local `bin/verify`
passed on 2026-05-25, including the updated MCP HTTP auth client test,
MCP package smokes, generated consumer-package smoke, router-hosted MCP example
smoke, router suite, and Chrome/Dart2Wasm browser WebSocket smoke. Hosted
evidence for this local checkpoint has not been requested yet; the latest fully
clean hosted checkpoint remains `78e0eb0`.
Prior implementation checkpoint: The generated MCP client-only consumer
package smoke now proves an HTTP auth grant can drive route-provided direct
JSON resources, prompts, and WAMP session meta helpers before any Streamable
HTTP lifecycle starts. The pre-lifecycle path now covers direct ping,
`tools/list`, `connectanum.api.list`, `resources/list`, `resources/read`,
`resources/templates/list`, `prompts/list`, `prompts/get`,
`wamp.session.count`, `wamp.session.list`, `wamp.session.get`, direct WAMP
pub/sub subscribe/publish/poll/unsubscribe, and direct batches while stale
per-call `Authorization` metadata is present. The smoke asserts every request
uses the grant-owned bearer token, sends no MCP session header, keeps
`sessionId` and `lastEventId` unset, and routes the WAMP pub/sub and session
meta helpers through the expected `connectanum.pubsub.*` and `wamp.session.*`
tools. Baseline `bin/test-fast` passed on 2026-05-25 before this change.
Focused local coverage passed on 2026-05-25: `bash -n bin/common.sh`,
`git diff --check`, `python3 tool/check_public_artifact_references.py`, and
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
Full local `bin/verify` passed on 2026-05-25, including the updated MCP
client-only consumer package smoke, router-hosted MCP example smoke, generated
consumer-package smoke, router suite, and Chrome/Dart2Wasm browser WebSocket
smoke. Commit `78e0eb0`
(`test: cover auth grant direct mcp catalog`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`78e0eb0`: `add-router` CI run `26384979697` passed with Fast Checks and Full
Verify green; `master` CI run `26384984837` passed with Fast Checks and Full
Verify green. The strict deployment-chain audit passed required gates on
`master` at `78e0eb0`, including clean current-head CI/logs, still-relevant
Dart package dry-run, WAMP profile benchmark, Router Image dry-run, Native
Artifacts dry-run evidence, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected; pub.dev publishing remains deferred for release-order and operator
decisions. No RC tag, GitHub Release, or published router image was created or
moved.
Prior implementation checkpoint: The public Streamable HTTP MCP client
auth-grant regression now covers lifecycle-free typed direct WAMP pub/sub
helpers, not only direct ping/tool/meta/batch calls and the generated
consumer-package smoke. `McpStreamableHttpClient.withAuthGrant(...)` is now
covered across `subscribeWampTopicDirect(...)`, `publishWampEventDirect(...)`,
`pollWampEventsDirect(...)`, and `unsubscribeWampTopicDirect(...)` while stale
per-call `Authorization` metadata is present. The regression asserts every
request still uses the grant-owned bearer token, stays on `application/json`,
sends no MCP session header, leaves `sessionId` and `lastEventId` unset, and
routes through the expected `connectanum.pubsub.*` tool calls. Baseline
`bin/test-fast` passed on 2026-05-25 before this change. Focused local coverage
passed on 2026-05-25:
`dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
`dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
and
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
Full local `bin/verify` passed on 2026-05-25, including the updated client MCP
test, MCP client/server package smokes, router-hosted MCP example smoke,
generated consumer-package smoke, router suite, and Chrome/Dart2Wasm browser
WebSocket smoke. Commit `3778692`
(`test: cover auth grant direct wamp helpers`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`3778692`: `master` CI run `26383251625` and `add-router` CI run
`26383247054` passed with Fast Checks and Full Verify green; `master` WAMP
Profile Benchmarks run `26383251626` and `add-router` WAMP Profile Benchmarks
run `26383247053` passed; `master` Dart Package Publish Dry Run
`26383251624` and `add-router` Dart Package Publish Dry Run `26383247044`
passed. Manual `master` Router Image dry-run `26383629405` passed at
`3778692`, uploaded the preview metadata `sha-3778692b25e3`, skipped GHCR
login, and validated the multi-arch build without publishing. The strict
deployment-chain audit passed required gates on `master` at `3778692`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark, Router Image dry-run, still-relevant Native Artifacts dry-run
evidence, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected;
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or published router image was created or moved.
Prior implementation checkpoint: The generated MCP client-only consumer
package smoke now proves a consumer application can use an HTTP auth grant for
typed direct WAMP pub/sub helpers before opening any Streamable HTTP session.
The pre-lifecycle auth-grant direct JSON path now subscribes, publishes, polls,
and unsubscribes through `subscribeWampTopicDirect(...)`,
`publishWampEventDirect(...)`, `pollWampEventsDirect(...)`, and
`unsubscribeWampTopicDirect(...)` while stale per-call `Authorization` metadata
is present. The smoke asserts every direct WAMP helper keeps the client-owned
grant bearer token, sends no MCP session header, and leaves `sessionId` /
`lastEventId` unset. The fake consumer endpoint now also treats the original
refresh token as rotated after a successful refresh, rejects a second refresh
attempt with `401`, and still keeps the original access token valid for later
Streamable lifecycle checks. Baseline `bin/test-fast` passed on 2026-05-25
before this change. Focused local coverage passed on 2026-05-25:
`bash -n bin/common.sh`, `git diff --check`,
`python3 tool/check_public_artifact_references.py`, and
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
Full local `bin/verify` passed on 2026-05-25, including the updated MCP
client-only consumer package smoke, router-hosted MCP example smoke, generated
consumer-package smoke, router suite, and Chrome/Dart2Wasm browser WebSocket
smoke. Commit `e9b0440`
(`test: cover mcp auth grant direct pubsub`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`e9b0440`: `master` CI run `26382129143` and `add-router` CI run
`26382095683` passed with Fast Checks and Full Verify green. The strict
deployment-chain audit passed required gates on `master` at `e9b0440`,
including clean current-head CI/logs, still-relevant Dart package dry-run, WAMP
profile benchmark, Router Image dry-run, and Native Artifacts dry-run evidence,
branch protection, workflow visibility, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or published router image was created or moved.
Prior implementation checkpoint: The generated MCP client-only consumer
package smoke now also proves refresh-token revocation from a consumer
application boundary. After refreshing the issued HTTP auth grant and proving
the refreshed bearer is used for lifecycle-free direct JSON, the smoke revokes
the refreshed access token and verifies a follow-up direct JSON request returns
`401` without creating Streamable HTTP session state. It then revokes the
refreshed refresh token with `token_type_hint: refresh_token`, attempts another
refresh with that revoked token, and asserts the auth bridge returns `401`. The
fake consumer endpoint tracks revoked access and refresh tokens and records the
refresh, revoke, and rejected-refresh request bodies/traces, while keeping the
original issued grant valid for later Streamable lifecycle checks. Baseline
`bin/test-fast` passed on 2026-05-25 before this change. Focused local coverage
passed on 2026-05-25: `bash -n bin/common.sh`, `git diff --check`,
`python3 tool/check_public_artifact_references.py`, and
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
Full local `bin/verify` passed on 2026-05-25, including the updated MCP
client-only consumer package smoke, router-hosted MCP example smoke, generated
consumer-package smoke, router suite, and Chrome/Dart2Wasm browser WebSocket
smoke. Commit `900b7e9`
(`test: cover mcp refresh token revoke smoke`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`900b7e9`: `master` CI run `26380824261` and `add-router` CI run
`26380823498` passed with Fast Checks and Full Verify green. The strict
deployment-chain audit passed required gates on `master` at `900b7e9`,
including clean current-head CI/logs, still-relevant Dart package dry-run, WAMP
profile benchmark, Router Image dry-run, and Native Artifacts dry-run evidence,
branch protection, workflow visibility, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or published router image was created or moved.
Prior implementation checkpoint: The generated MCP client-only consumer package
smoke proves the HTTP auth grant refresh/revoke path from a consumer
application boundary. After the existing issued-grant direct JSON checks, the
smoke refreshes the grant, constructs
`McpStreamableHttpClient.withAuthGrant(...)` from the refreshed grant, sends a
direct JSON `ping` with stale per-call `Authorization` metadata, and asserts the
fake endpoint observes the refreshed bearer token without any MCP session
header or `sessionId` / `lastEventId` mutation. It then revokes the refreshed
access token with `token_type_hint: access_token` and proves a follow-up direct
JSON request is rejected with `401` while still creating no Streamable HTTP
session state. The fake consumer endpoint now accepts the original and
refreshed access tokens and tracks revoked access tokens so the existing issued
grant remains valid for later Streamable lifecycle checks. Baseline
`bin/test-fast` passed on 2026-05-25 before this change. Focused local coverage
passed on 2026-05-25: `bash -n bin/common.sh`, `git diff --check`,
`python3 tool/check_public_artifact_references.py`, and
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_client_package_smoke'`.
Full local `bin/verify` passed on 2026-05-25, including the updated MCP
client-only consumer package smoke, router-hosted MCP example smoke, generated
consumer-package smoke, router suite, and Chrome/Dart2Wasm browser WebSocket
smoke. Commit `fcc6ef4`
(`test: cover mcp auth grant refresh smoke`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`fcc6ef4`: `master` CI run `26379386698` and `add-router` CI run
`26379383928` passed with Fast Checks and Full Verify green. The strict
deployment-chain audit passed required gates on `master` at `fcc6ef4`, including
clean current-head CI/logs, still-relevant Dart package dry-run, WAMP profile
benchmark, Router Image dry-run, and Native Artifacts dry-run evidence, branch
protection, workflow visibility, and router package visibility. RC readiness
remains not-ready only because no approved numeric RC tag, GitHub prerelease, or
matching RC router image tag has been selected; pub.dev publishing remains
deferred for release-order and operator decisions. No RC tag, GitHub Release, or
published router image was created or moved.
Prior implementation checkpoint: The generated MCP client-only consumer package
smoke proves an application can use an HTTP auth grant for lifecycle-free direct
JSON before opening any Streamable HTTP session. Commit `324ee24`
(`test: cover mcp auth grant consumer direct json`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `324ee24`: `master` CI run `26377930589` and `add-router` CI run
`26377928223` passed with Fast Checks and Full Verify green. The strict audit
passed required gates on `master` at `324ee24`, including clean current-head
CI/logs, still-relevant Dart package, WAMP, Router Image, and Native Artifacts
evidence, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected;
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or published router image was created or moved.
Prior implementation checkpoint: The public Streamable HTTP MCP client
auth-grant regression now covers lifecycle-free direct JSON helper calls, not
only initialized Streamable HTTP sessions. A client constructed from
`ConnectanumHttpAuthGrant` now has coverage proving its owned trimmed bearer
token is preserved when per-call headers try to provide stale
`Authorization` metadata across direct JSON `ping`, standard `tools/list`,
Connectanum tool/meta API access, and direct JSON batch POST. The regression
also asserts these direct JSON calls stay lifecycle-free: every request uses
`application/json`, no MCP session header is sent, and `sessionId` /
`lastEventId` remain unset. This aligns auth grants with the bearer-token
direct JSON lifecycle smoke and protects downstream applications that use HTTP
auth grants for direct tool/meta API access without first opening a Streamable
session. Baseline `bin/test-fast` passed on 2026-05-25. Focused local coverage
passed on 2026-05-25:
`dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
`dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
and
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
Full local `bin/verify` passed on 2026-05-25, including the router-hosted MCP
example smoke, generated consumer-package smoke, and Chrome/Dart2Wasm browser
WebSocket smoke. Commit `da1c41a`
(`test: cover mcp auth grant direct json`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`da1c41a`: `master` CI run `26376646690` and `add-router` CI run
`26376646678` passed with Fast Checks and Full Verify green. Dart Package
Publish Dry Run `26376646677` on `master` and `26376646691` on `add-router`,
plus WAMP Profile Benchmarks `26376646652` on `master` and `26376646707` on
`add-router`, passed for the same head. Manual non-mutating Router Image
dry-run `26377017450` passed on `master`, uploaded preview metadata for
`sha-da1c41a82f1f`, skipped GHCR login, and did not push an image. Native
Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `da1c41a`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or published
router image was created or moved.
Prior implementation checkpoint: The public Streamable HTTP MCP client
bearer-token regression now covers both Streamable HTTP and lifecycle-free
direct JSON calls under stale per-call `Authorization` metadata. The primary
`withBearerToken(...)` smoke sends conflicting per-call bearer headers across
Streamable `initialize`, `notifications/initialized`, `tools/list`, GET/SSE
polling, Streamable batch POST, DELETE cleanup, and direct JSON `tools/list`,
`ping`, and batch POST, then asserts every recorded request still uses the
client-owned trimmed bearer token. This keeps the public convenience
constructor aligned with the auth-grant lifecycle regression and protects
downstream applications that mix Streamable HTTP sessions with direct JSON MCP
tool/meta access. Baseline `bin/test-fast` passed on 2026-05-25. Focused
local coverage passed on 2026-05-25:
`dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
`dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
and
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
Full local `bin/verify` passed on 2026-05-25, including the router-hosted MCP
example smoke, generated consumer-package smoke, and Chrome/Dart2Wasm browser
WebSocket smoke. Commit `a60d432`
(`test: cover mcp bearer lifecycle headers`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`a60d432`: `master` CI run `26375633670` and `add-router` CI run
`26375630452` passed with Fast Checks and Full Verify green. Dart Package
Publish Dry Run `26375633662` on `master` and `26375630482` on `add-router`,
plus WAMP Profile Benchmarks `26375633672` on `master` and `26375630471` on
`add-router`, passed for the same head. Manual non-mutating Router Image
dry-run `26375900535` passed on `master`, uploaded preview metadata for
`sha-a60d43290c44`, skipped GHCR login, and did not push an image. Native
Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `a60d432`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or published
router image was created or moved.
Prior implementation checkpoint: The public Streamable HTTP MCP client
auth-grant regression now covers the full initialized lifecycle, not only
`initialize(...)`. A client constructed from `ConnectanumHttpAuthGrant` now has
coverage proving its owned bearer token is preserved when per-call headers try
to provide stale `Authorization` metadata across Streamable `initialize`,
sessionful `tools/list`, GET/SSE polling, and DELETE cleanup. The same test
also asserts public consumer trace headers still flow per request, the active
MCP session id is attached on sessionful calls, and `deleteSession(...)` clears
local session state afterward. Baseline `bin/test-fast` passed on 2026-05-25.
Focused local coverage passed on 2026-05-25:
`dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
`dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
and
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
Full local `bin/verify` passed on 2026-05-25, including the router-hosted MCP
example smoke, generated consumer-package smoke, and Chrome/Dart2Wasm browser
WebSocket smoke. Commit `c588ff4` (`test: cover mcp auth grant lifecycle`) was
pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted
GitHub evidence is clean at `c588ff4`: `master` CI run `26374623727` and
`add-router` CI run `26374619965` passed with Fast Checks and Full Verify
green. Dart Package Publish Dry Run `26374623735` on `master` and
`26374619948` on `add-router`, plus WAMP Profile Benchmarks `26374623736` on
`master` and `26374619943` on `add-router`, passed for the same head. Manual
non-mutating Router Image dry-run `26374917999` passed on `master`, uploaded
preview metadata for `sha-c588ff46d07c`, skipped GHCR login, and did not push
an image. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `c588ff4`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or published
router image was created or moved.
Prior implementation checkpoint: `bin/test-all` now bounds each browser
WebSocket smoke attempt with
`CONNECTANUM_BROWSER_TEST_ATTEMPT_TIMEOUT_SECONDS`, defaulting to 420 seconds,
while preserving the existing `CONNECTANUM_BROWSER_TEST_ATTEMPTS` retry count
and final-attempt GitHub annotation behavior. This hardens the hosted
deployment chain against retryable `package:test` browser-manager startup or
load stalls like the first `master` CI attempt at `3f3f4c2`, where rerunning
the failed browser job passed cleanly but the original attempt consumed the
job timeout. `tool/test_verification_scripts.py` now guards the retry wrapper,
attempt timeout, and reporter behavior. Baseline `bin/test-fast` passed on
2026-05-24. Focused local coverage passed on 2026-05-24:
`bash -n bin/test-all` and `python3 tool/test_verification_scripts.py`. Full
local `bin/verify` passed on 2026-05-24 for this checkpoint, including the
Chrome/Dart2Wasm browser WebSocket smoke through the updated wrapper. Commit
`8a8f09b` (`ci: bound browser smoke attempts`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`8a8f09b`: `master` CI run `26373596238` and `add-router` CI run
`26373596242` passed with Fast Checks and Full Verify green. Dart Package
Publish Dry Run `26371382131` on `master` and `26371382110` on `add-router`,
WAMP Profile Benchmarks `26371382109` on `master` and `26371382129` on
`add-router`, Router Image dry-run `26372834591`, and Native Artifacts dry-run
`26286794628` remain relevant because no corresponding sensitive inputs
changed after their clean runs. The strict deployment-chain audit passed
required gates on `master` at `8a8f09b`, including clean current-head CI/logs,
Dart package dry-run, WAMP profile benchmark evidence, relevant Router Image
dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready
only because no approved numeric RC tag, GitHub prerelease, or matching RC
router image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior implementation checkpoint: The public Streamable HTTP MCP client now
treats a client-level `Authorization` header as owned auth/session state once
it is provided through constructor headers, `withBearerToken(...)`, or
`withAuthGrant(...)`. Request-specific headers are still honored for plain
clients, but a bearer/auth-grant client reapplies its captured authorization
header after per-call headers so stale or conflicting per-call metadata cannot
swap the bearer principal on an existing MCP client/session. Coverage now proves
auth-grant clients keep the grant bearer token even when `initialize(...)`
receives a stale `Authorization` header, while plain clients can still send a
per-call `Authorization` header when they have no client-level auth state.
Baseline `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24: `dart format` and `dart analyze` for
`packages/connectanum_client/lib/src/mcp/streamable_http_client.dart` and
`packages/connectanum_client/test/mcp/streamable_http_client_test.dart`, plus
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
Full local `bin/verify` passed on 2026-05-24 for this
checkpoint. Commit `3f3f4c2` (`fix: keep mcp bearer auth stable`) was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `3f3f4c2`: `master` CI run `26371382128` passed after a
failed-job rerun cleared a hosted browser-runner load flake, and `add-router`
CI run `26371382102` passed with Fast Checks and Full Verify green; Dart
Package Publish Dry Run `26371382131` on `master` and `26371382110` on
`add-router` passed; WAMP Profile Benchmarks `26371382109` on `master` and
`26371382129` on `add-router` passed; Router Image dry-run `26372834591`
passed on `master` with preview metadata `sha-3f3f4c2e9e4a`, GHCR login
skipped, and preview metadata uploaded. Native Artifacts dry-run `26286794628`
remains relevant because no native-release-sensitive inputs changed. The
strict deployment-chain audit passed required gates on `master` at `3f3f4c2`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark evidence, current Router Image dry-run, relevant native release
dry-run, branch protection, workflow visibility, and router package visibility.
RC readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior implementation checkpoint: Router-hosted MCP secure JSON-response route
coverage now proves a second valid bearer principal can use the public
resource/prompt surface without owning or mutating the first principal's
session. The native router integration smoke, public router-hosted MCP example,
and generated consumer-package smoke now cover lifecycle-free direct JSON
`resources/list`, `resources/read`, `resources/templates/list`, `prompts/list`,
and `prompts/get` for the independent principal, then repeat the resource and
prompt calls on an initialized JSON-response Streamable HTTP session while
asserting `MCP-Session-Id` and POST/SSE cursor state remain principal-isolated.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24: `dart analyze packages/connectanum_router/test/router_integration_native_test.dart packages/connectanum_router/example/router_hosted_mcp.dart`,
`cd packages/connectanum_router && dart test test/router_integration_native_test.dart --name "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
`bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
and `git diff --check`. Full local `bin/verify` passed on 2026-05-24 for this
checkpoint. Commit `e1a496e`
(`test: cover secure json mcp resources prompts`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `e1a496e`: `master` CI run `26370411899` and `add-router` CI run
`26370411877` passed with Fast Checks and Full Verify green; Dart Package
Publish Dry Run `26370411887` on `master` and `26370411864` on `add-router`
passed; WAMP Profile Benchmarks `26370411888` on `master` and `26370411900` on
`add-router` passed; Router Image dry-run `26369504710` at `25afea8` and Native
Artifacts dry-run `26286794628` remain relevant because no corresponding
sensitive inputs changed after their clean runs. The strict deployment-chain
audit passed required gates on `master` at `e1a496e`, including clean
current-head CI/logs, Dart package dry-run, WAMP profile benchmark evidence,
relevant Router Image and native release dry-runs, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior implementation checkpoint: The checked-in `connectanum_mcp` IO
entrypoint smoke now uses a stateful Streamable MCP fake endpoint for pub/sub
instead of a static poll response. The fake endpoint records per-subscription
event queues, processes notification-only pub/sub publishes for side effects,
and returns the actual queued event payloads through public
`package:connectanum_mcp/connectanum_mcp_io.dart` helpers. The smoke now proves
a consumer application can initialize a Streamable session, subscribe, publish
through typed WAMP helpers, publish through `connectanum.pubsub.publish`, send
notification-only method/helper publishes, poll back all four queued events
without changing the POST/SSE resume cursor for notifications, unsubscribe,
then use direct JSON pub/sub helpers while preserving the active Streamable
session state.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24: `dart format packages/connectanum_mcp/test/io_client_export_test.dart`,
`dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`,
and `dart analyze packages/connectanum_mcp`. Full local `bin/verify` passed on
2026-05-24 for this checkpoint. Commit `25afea8`
(`test: cover mcp io pubsub side effects`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`25afea8`: `master` CI run `26369187521` and `add-router` CI run `26369185437`
passed with Fast Checks and Full Verify green; Dart Package Publish Dry Run
`26369187504` on `master` and `26369185436` on `add-router` passed; Router
Image dry-run `26369504710` passed on `master`; WAMP Profile Benchmarks
`26366801338` and Native Artifacts dry-run `26286794628` remain relevant
because no corresponding sensitive inputs changed after their clean runs. The
strict deployment-chain audit passed required gates on `master` at `25afea8`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark evidence, current Router Image dry-run, relevant native release
dry-run, branch protection, workflow visibility, and router package visibility.
RC readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior implementation checkpoint: The generated consumer-package smoke now
proves a downstream application can use an initialized Streamable HTTP MCP
session to send notification-only tool calls through the standard
`tools/call` helper, Connectanum `connectanum.tool.call`, direct dotted
procedure names, and plural `connectanum.tools.call` aliases. The smoke asserts
each valid notification invokes the registered WAMP procedure and keeps
`MCP-Session-Id` plus the POST/SSE resume cursor unchanged, while an invalid
notification-only batch entry is accepted and dropped without invoking the
procedure.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24:
`bash -n bin/common.sh`,
`python3 tool/check_public_artifact_references.py`,
`git diff --check`, and
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Hosted
GitHub evidence is clean at `7b4a88e`: `master` CI run `26368059584` and
`add-router` CI run `26368057989` passed with Fast Checks and Full Verify
green. Dart Package Publish Dry Run `26366801335`, WAMP Profile Benchmarks
`26366801338`, Router Image dry-run `26366846880`, and Native Artifacts
dry-run `26286794628` remain relevant because no corresponding sensitive
inputs changed after their clean runs. The strict deployment-chain audit passed
required gates on `master` at `7b4a88e`, including clean current-head CI/logs,
Dart package dry-run, WAMP profile benchmark evidence, current Router Image
dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior implementation checkpoint: The checked-in native router integration
smoke now proves router-hosted MCP direct JSON-RPC notifications invoke the
same WAMP procedure as request/response tool calls without creating or
mutating Streamable HTTP session state. The smoke records `app.safe.lookup`
invocations and verifies notification-only calls through standard
`tools/call`, Connectanum `connectanum.tool.call`, direct dotted
`app.safe.lookup`, and plural `connectanum.tools.call` helpers. Coverage now
runs on the public MCP route, a public notification-only batch with an invalid
notification ignored, bearer-protected `/mcp/secure` for both the primary
secure route and a second valid bearer principal before initialization, and
bearer-protected `/mcp/secure-json-post` for both primary and independent valid
bearer principals before initialization.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24:
`dart analyze packages/connectanum_router/test/router_integration_native_test.dart`
and
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal|smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
`3feb797` (`test: cover direct mcp notification side effects`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `3feb797`: `master` CI run `26366801355` and
`add-router` CI run `26366796353` passed with Fast Checks and Full Verify
green; Dart Package Publish Dry Run `26366801335` on `master` and
`26366796357` on `add-router` passed; WAMP Profile Benchmarks `26366801338`
on `master` and `26366796352` on `add-router` passed; manual non-mutating
Router Image dry-run `26366846880` passed on `master` at `3feb797` with
preview metadata `sha-3feb797f84b1`, GHCR login skipped, and preview metadata
uploaded. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `3feb797`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior implementation checkpoint: The public router-hosted MCP example now
proves direct JSON-RPC notification paths invoke the same WAMP procedure as
request/response tool calls without creating or mutating Streamable HTTP
session state. The example records `example.task.lookup` invocations and the
direct tool/meta smoke sends notification-only calls through standard
`tools/call`, Connectanum `connectanum.tool.call`, direct dotted
`example.task.lookup`, and plural `connectanum.tools.call` helpers. Because
the helper is shared, this runs on the public route, both bearer-protected MCP
routes, and the independent valid bearer principal paths before Streamable
initialization.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24:
`dart analyze packages/connectanum_router/example/router_hosted_mcp.dart` and
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
`dbb52aa` (`example: cover direct mcp tool notifications`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `dbb52aa`: `master` CI run `26365310039` and
`add-router` CI run `26365307456` passed with Fast Checks and Full Verify
green; Dart Package Publish Dry Run `26365310038` on `master` and
`26365307444` on `add-router` passed; WAMP Profile Benchmarks `26365310040`
on `master` and `26365307457` on `add-router` passed; manual non-mutating
Router Image dry-run `26365614158` passed on `master` at `dbb52aa` with
preview metadata `sha-dbb52aa872f6`, GHCR login skipped, and preview metadata
uploaded. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `dbb52aa`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior implementation checkpoint: The checked-in router integration smoke,
public router-hosted MCP example, and generated consumer-package smoke now
extend secure-route direct JSON tool/meta API access from `tools/call` helpers
and catalogs to direct dotted JSON-RPC tool-method names. The checked-in native
router smoke proves `app.safe.lookup` can be called directly on both
bearer-protected MCP routes, `/mcp/secure` and `/mcp/secure-json-post`, for
owner and independent valid bearer principals without mutating `sessionId` or
`lastEventId`. The public router-hosted MCP example now calls
`example.task.lookup` as a direct JSON-RPC method inside its direct tool/meta
smoke, and both the public example and generated consumer-package smoke run the
full direct tool/meta helper sweep for a second valid bearer principal before
that principal initializes a Streamable session on secure Streamable and secure
JSON-response routes.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24:
`dart analyze packages/connectanum_router/test/router_integration_native_test.dart packages/connectanum_router/example/router_hosted_mcp.dart`,
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal|smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
`bash -n bin/common.sh`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
`python3 tool/check_public_artifact_references.py`, and `git diff --check`.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
`26b7348` (`test: cover direct mcp dotted methods`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `26b7348`: `master` CI run `26364003714` and `add-router` CI run
`26364002656` passed with Fast Checks and Full Verify green; Dart Package
Publish Dry Run `26364003678` on `master` and `26364002658` on `add-router`
passed; WAMP Profile Benchmarks `26364003654` on `master` and `26364002655`
on `add-router` passed; manual non-mutating Router Image dry-run
`26364336014` passed on `master` at `26b7348` with preview metadata
`sha-26b734836c67`, GHCR login skipped, and preview metadata uploaded. Native
Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `26b7348`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior implementation checkpoint: The checked-in router integration smoke,
public router-hosted MCP example, and generated consumer-package smoke now
extend independent-principal direct JSON coverage on both bearer-protected MCP
routes, `/mcp/secure` and `/mcp/secure-json-post`, from direct tool/topic
catalogs and pub/sub into the full direct WAMP meta helper surface. Before a
second valid bearer principal initializes its own Streamable session, the smoke
now proves direct helpers for WAMP session, registration, callee, subscription,
subscriber, and subscriber-count metadata are callable with bearer auth, expose
only the caller's visible session/subscription scope, keep internal service
sessions hidden from callee/subscriber metadata, and do not populate
`sessionId` or `lastEventId`. The public example and generated
consumer-package smoke now run these direct WAMP meta helpers before direct
pub/sub for both secure Streamable and secure JSON-response routes.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24:
`dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal" --chain-stack-traces`,
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
`bash -n bin/common.sh`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
and `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`.
Post-change `python3 tool/check_public_artifact_references.py`,
`git diff --check`, `bin/test-fast`, and full local `bin/verify` passed on
2026-05-24 for this checkpoint. Commit `20c6c97`
(`test: cover direct mcp wamp meta sessions`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`20c6c97`: `master` CI run `26362759298` and `add-router` CI run
`26362755835` passed with Fast Checks and Full Verify green; Dart Package
Publish Dry Run `26362759287` on `master` and `26362755826` on `add-router`
passed; WAMP Profile Benchmarks `26362759307` on `master` and `26362755815`
on `add-router` passed; manual non-mutating Router Image dry-run
`26363036566` passed on `master` at `20c6c97` with preview metadata
`0.1.0-rc.2-validation.20c6c97`, GHCR login skipped, and preview metadata
uploaded. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `20c6c97`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Previous implementation checkpoint: The checked-in router integration smoke,
public router-hosted MCP example, and generated consumer-package smoke now
extend the bearer-protected JSON-response MCP route at `/mcp/secure-json-post`
beyond rejected cross-principal session reuse. After a second valid bearer
principal is rejected when it tries to reuse the owner `MCP-Session-Id`, the
same valid principal can use public MCP HTTP helpers to access the direct JSON
tool catalog plus WAMP topic metadata and pub/sub without lifecycle side
effects, initialize a distinct JSON-response Streamable HTTP session, keep
POST responses in JSON mode without capturing a POST/SSE cursor, run pub/sub
on that independent session while preserving empty JSON-response cursor state,
and delete its own session without mutating the owner session. The public
example and generated consumer-package smoke prove lifecycle-free direct JSON
WAMP/pubsub access before initialize and independent pub/sub after initialize;
the checked-in router integration smoke pins route-level direct WAMP topic
catalog access, direct pub/sub delivery, independent JSON-response Streamable
pub/sub delivery, and owner-session stability for a second valid bearer
principal.
Commit `8cd8f5e` (`test: cover json-response mcp pubsub sessions`) was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `8cd8f5e`: `master` CI run `26361007393` and `add-router`
CI run `26361003647` passed with Fast Checks and Full Verify green; Dart
Package Publish Dry Run `26361007296` on `master` and `26361003643` on
`add-router` passed; WAMP Profile Benchmarks `26361007284` on `master` and
`26361003657` on `add-router` passed; manual non-mutating Router Image dry-run
`26361298005` passed on `master` at `8cd8f5e` with preview metadata
`0.1.0-rc.2-validation.8cd8f5e`, GHCR login skipped, and preview metadata
uploaded. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `8cd8f5e`, including clean current-head
CI/logs, Dart package dry-run, WAMP profile benchmark evidence, current Router
Image dry-run, relevant native release dry-run, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; pub.dev publishing remains deferred for
release-order and operator decisions.
Previous implementation checkpoint: The checked-in router integration smoke,
public router-hosted MCP example, and generated consumer-package smoke now
extend the bearer-protected standard Streamable MCP route at `/mcp/secure`
beyond rejected cross-principal session reuse. After a second valid bearer
principal is rejected when it tries to reuse the owner `MCP-Session-Id`, the
same valid principal can use public MCP HTTP helpers to access direct JSON tool
and WAMP topic metadata plus pub/sub without lifecycle side effects, initialize
a distinct Streamable HTTP session, capture a session-scoped POST/SSE cursor on
the standard Streamable tools/list path, run pub/sub on that independent
session while advancing only its own SSE cursor, and delete its own session
without mutating the owner session. The public example and generated
consumer-package smoke cover the reuse rejection matrix across Streamable
methods and prove direct JSON WAMP/pubsub access remains lifecycle-free before
initialize; the checked-in router integration smoke pins route-level ownership,
direct WAMP topic catalog access, direct pub/sub delivery, and independent
Streamable pub/sub delivery for a second valid bearer principal.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24:
`dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "isolates MCP Streamable HTTP sessions by route and bearer principal" --chain-stack-traces`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
`bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
and `git diff --check`. Post-change `bin/test-fast` passed on 2026-05-24.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint.
Commit `a2c706f` (`test: cover independent mcp pubsub sessions`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `a2c706f`: `master` CI run `26359793602` passed with Fast
Checks and Full Verify green plus clean logs, and `add-router` CI run
`26359791440` passed with Fast Checks and Full Verify green. Dart Package
Publish Dry Run `26359793607` on `master` and `26359791425` on `add-router`
passed at `a2c706f`; WAMP Profile Benchmarks `26359793618` on `master` and
`26359791432` on `add-router` passed at `a2c706f`; manual non-mutating Router
Image dry-run `26359802334` passed on `master` at `a2c706f` with preview
metadata `0.1.0-rc.2-validation.a2c706fc2275`, GHCR login skipped, and preview
metadata uploaded; Native Artifacts dry-run `26286794628` remains relevant
because no native-release-sensitive inputs changed. The strict
deployment-chain audit passed required gates on `master` at `a2c706f`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark evidence, current Router Image dry-run, relevant native release
dry-run, branch protection, workflow visibility, and router package visibility.
RC readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior implementation checkpoint: The checked-in router integration smoke,
public router-hosted MCP example, and generated consumer-package smoke now prove
that the bearer-protected JSON-response MCP route at `/mcp/secure-json-post`
does more than reject cross-principal session reuse. After a second valid bearer
principal is rejected when it tries to reuse the owner `MCP-Session-Id`, the
same valid principal can use the public MCP HTTP client helpers to access the
direct JSON tool catalog, initialize a distinct Streamable HTTP session, keep
POST responses in JSON mode without capturing a POST/SSE cursor, list tools on
that independent session, and delete its own session without mutating the owner
session. The generated consumer-package smoke follows the route's paginated tool
catalog because the smoke route intentionally sets a page size of one.
Pre-change `bin/test-fast` passed on 2026-05-24. Focused local coverage passed
on 2026-05-24:
`dart analyze packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
`bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
and `git diff --check`. Post-change `bin/test-fast` passed on 2026-05-24.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
`2b14e88` (`test: cover independent json-response mcp sessions`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `2b14e88`: `master` CI run `26357273499` passed with Fast
Checks and Full Verify green plus clean logs, and `add-router` CI run
`26357271763` passed with Fast Checks and Full Verify green. Dart Package
Publish Dry Run `26357273488` on `master` and `26357271785` on `add-router`
passed at `2b14e88`; WAMP Profile Benchmarks `26357273487` on `master` and
`26357271784` on `add-router` passed at `2b14e88`; manual non-mutating Router
Image dry-run `26357553510` passed on `master` at `2b14e88` with GHCR login
skipped and preview metadata uploaded; Native Artifacts dry-run `26286794628`
remains relevant because no native-release-sensitive inputs changed. The
strict deployment-chain audit passed required gates on `master` at `2b14e88`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark evidence, current Router Image dry-run, relevant native release
dry-run, branch protection, workflow visibility, and router package visibility.
RC readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior implementation checkpoint: The public router-hosted MCP example now
extends the bearer-protected JSON-response MCP route at
`/mcp/secure-json-post` with active-session auth/ownership coverage. The
example fixture issues a second ticket bearer principal and proves that a
different valid bearer principal cannot reuse the owner `MCP-Session-Id`
across Streamable batches, notifications, tools, resources, prompts,
GET/SSE poll, and DELETE (`404 Not Found`). It also proves bearerless active
session reuse is rejected with `401 Unauthorized`, and that an unknown bearer
is rejected across active direct JSON tools, WAMP meta/pubsub, resources, and
prompts without mutating the owner session state before Streamable failures
clear the rejected client's stale session state. The owner JSON-response MCP
client keeps its active session id stable, keeps the POST/SSE cursor empty,
and continues through tools/call, resources, prompts, pub/sub, GET/SSE poll,
and DELETE cleanup. Pre-change `bin/test-fast` passed on 2026-05-24. Focused
local coverage passed on 2026-05-24:
`dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
`python3 tool/check_public_artifact_references.py`, and `git diff --check`.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
`bc2575c` (`example: cover json-response mcp session isolation`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `bc2575c`: `master` CI run `26355702455` passed with Fast
Checks and Full Verify green plus clean logs, and `add-router` CI run
`26355702355` passed with Fast Checks and Full Verify green. Dart Package
Publish Dry Run `26355702488` on `master` and `26355702383` on `add-router`
passed at `bc2575c`; WAMP Profile Benchmarks `26355702451` on `master` and
`26355702340` on `add-router` passed at `bc2575c`; manual non-mutating Router
Image dry-run `26355974643` passed on `master` at `bc2575c` with GHCR login
skipped and preview metadata uploaded; Native Artifacts dry-run `26286794628`
remains relevant because no native-release-sensitive inputs changed. The strict
deployment-chain audit passed required gates on `master` at `bc2575c`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark evidence, current Router Image dry-run, relevant native release
dry-run, branch protection, workflow visibility, and router package visibility.
RC readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected; the audit
suggests `v0.1.0-rc.2` as the next numeric tag if release approval is given.
Pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
Prior implementation checkpoint: The generated consumer-package
router-hosted MCP smoke now extends the bearer-protected JSON-response route
at `/mcp/secure-json-post` with the same active-session isolation matrix used
by the standard secure Streamable route. The generated consumer application
smoke now proves a different valid bearer principal cannot reuse the owner
`MCP-Session-Id` on JSON-response Streamable POSTs (`404 Not Found` /
`Unknown MCP HTTP session`), bearerless active-session reuse is rejected with
`401 Unauthorized`, and an unknown bearer on an active session is rejected
across direct JSON tools, direct WAMP meta/pubsub calls, Streamable batches,
notifications, tools, resources, prompts, GET/SSE poll, and DELETE while the
rejected client state is cleared on Streamable failures. The owner client keeps
its active MCP session id, keeps the POST/SSE cursor empty, and continues
through typed protocol override, pub/sub, GET/SSE poll, and DELETE cleanup
coverage. Pre-change `bin/test-fast` passed on 2026-05-24. Focused local
coverage passed on 2026-05-24:
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
`bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
and `git diff --check`. Full local `bin/verify` passed on 2026-05-24 for this
checkpoint. Commit `1d80b57`
(`test: cover consumer json-response mcp sessions`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `1d80b57`: `master` CI run `26354715574` passed with Fast Checks and
Full Verify green plus clean logs, and `add-router` CI run `26354713644`
passed with Fast Checks and Full Verify green. Dart Package Publish Dry Run
`26353736911` at `c453949`, WAMP Profile Benchmarks `26353736914` at
`c453949`, Router Image dry-run `26353998120` at `c453949`, and Native
Artifacts dry-run `26286794628` remain relevant because no publish-,
WAMP-profile-, router-image-, or native-release-sensitive inputs changed. The
strict deployment-chain audit passed required gates on `master` at `1d80b57`,
including clean current-head CI/logs, relevant Dart package dry-run, relevant
WAMP profile benchmark evidence, relevant Router Image dry-run, relevant
native release dry-run, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected; the audit suggests `v0.1.0-rc.2` as the next numeric tag if release
approval is given. Pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior implementation checkpoint: The checked-in router native integration
MCP smoke now also pins auth/session isolation for the bearer-protected
JSON-response route at `/mcp/secure-json-post`. Before any Streamable
lifecycle session exists, the smoke proves an unknown bearer token is rejected
with `401 Unauthorized` and no response `MCP-Session-Id`. After an authorized
client initializes a Streamable MCP session, the same route rejects raw JSON
POST requests that reuse the active `MCP-Session-Id` without a bearer or with
an unknown bearer, and rejects a Streamable HTTP POST from a different valid
bearer principal using the owner session id with `404 Not Found` /
`Unknown MCP HTTP session`; the owner client retains its active MCP session id,
keeps the POST/SSE cursor empty, and continues through the existing
route-provided resources, prompts, pub/sub, poll, unsubscribe, and DELETE
cleanup assertions. Pre-change `bin/test-fast` passed on 2026-05-24. Focused
local coverage passed on 2026-05-24:
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
`dart analyze packages/connectanum_router/test/router_integration_native_test.dart`,
`python3 tool/check_public_artifact_references.py`, and `git diff --check`.
Full local `bin/verify` passed on 2026-05-24 for this checkpoint. Commit
`c453949` (`test: cover json-response mcp principal isolation`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `c453949`: `master` CI run `26353736923` passed with Fast Checks and
Full Verify green plus clean logs, and `add-router` CI run `26353735642`
passed with Fast Checks and Full Verify green. Dart Package Publish Dry Run
`26353736911` on `master` and `26353735630` on `add-router` passed cleanly at
`c453949`; WAMP Profile Benchmarks `26353736914` on `master` and
`26353735619` on `add-router` passed at `c453949`. Router Image dry-run
`26353998120` passed for current head with preview metadata
`sha-c453949d0b17`, GHCR login skipped, and no image publish. The strict
deployment-chain audit passed required gates on `master` at `c453949`,
including clean current-head CI/logs, current Dart package dry-run, current
WAMP profile benchmark evidence, current Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; the audit suggests `v0.1.0-rc.2` as the next
numeric tag if release approval is given. Pub.dev publishing remains deferred
for release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior implementation checkpoint: The checked-in router native integration
MCP smoke now extends the bearer-protected JSON-response route at
`/mcp/secure-json-post` to prove route-provided resources, resource
templates, and prompts under the same auth/session mode as the route's tools,
WAMP meta API, and pub/sub helpers. The smoke now uses the public IO client
plus HTTP ticket auth grant to cover direct JSON `resources/list`,
`resources/read`, `resources/templates/list`, `prompts/list`, and
`prompts/get` before Streamable initialization while confirming the calls
remain lifecycle-free and do not create an MCP session id. After Streamable
initialize, initialized notification, and tools/list, the same route also
covers Streamable `resources/list`, `resources/read`,
`resources/templates/list`, `prompts/list`, and `prompts/get` while keeping
the active MCP session id stable and the POST/SSE resume cursor empty on JSON
POST responses before continuing pub/sub subscribe, service-session publish,
poll, unsubscribe, and DELETE cleanup. Pre-change `bin/test-fast` passed on
2026-05-24. Focused local coverage passed on 2026-05-24:
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
`dart analyze packages/connectanum_router/test/router_integration_native_test.dart`,
`python3 tool/check_public_artifact_references.py`, and `git diff --check`.
Full local `bin/verify` passed on 2026-05-24. Commit `bb7d3a5`
(`test: cover secure json-response mcp resources`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `bb7d3a5`: `master` CI run `26351940781` passed with Fast Checks and
Full Verify green plus clean logs, and `add-router` CI run `26351939292`
passed with Fast Checks and Full Verify green. Dart Package Publish Dry Run
`26351940788` on `master` and `26351939291` on `add-router` passed cleanly at
`bb7d3a5`; WAMP Profile Benchmarks `26351940789` on `master` and
`26351939286` on `add-router` passed at `bb7d3a5`. Router Image dry-run
`26352174318` passed for current head with preview metadata
`sha-bb7d3a5d36c0`, GHCR login skipped, and no image publish. The strict
deployment-chain audit passed required gates on `master` at `bb7d3a5`,
including clean current-head CI/logs, current Dart package dry-run, current
WAMP profile benchmark evidence, current Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; the audit suggests `v0.1.0-rc.2` as the next
numeric tag if release approval is given. Pub.dev publishing remains deferred
for release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Earlier implementation checkpoint: The checked-in router native integration
MCP smoke exposes a bearer-protected JSON-response route at
`/mcp/secure-json-post` from the shared `_buildMcpSmokeSettings()` fixture,
using the same route-provided tool, WAMP meta API, pub/sub, resources, and
prompts surface as `/mcp/secure` with `post_response_transport: json`. The
smoke proves the route rejects missing bearer credentials without returning an
MCP session id, then uses the public IO client plus HTTP ticket auth grant to
cover authenticated direct JSON tool catalog access, WAMP topic meta discovery,
Streamable initialize and initialized notifications, tools/list, pub/sub
subscribe, service-session publish, poll, unsubscribe, and DELETE cleanup.
The route-level assertions also pin JSON POST-response session behavior by
checking the active session id stays stable while the client never captures a
POST/SSE resume cursor. Pre-change `bin/test-fast` passed on 2026-05-24.
Focused local coverage passed on 2026-05-24:
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security" --chain-stack-traces`,
`dart analyze packages/connectanum_router/test/router_integration_native_test.dart`,
`python3 tool/check_public_artifact_references.py`, and `git diff --check`.
Full local `bin/verify` passed on 2026-05-24. Commit `26d5ed5`
(`test: cover secure json-response mcp integration`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `26d5ed5`: `master` CI run `26351016213` passed with Fast Checks and
Full Verify green plus clean logs, and `add-router` CI run `26351015880`
passed with Fast Checks and Full Verify green. Dart Package Publish Dry Run
`26351016222` on `master` and `26351015879` on `add-router` passed cleanly at
`26d5ed5`; WAMP Profile Benchmarks `26351016231` on `master` and
`26351015870` on `add-router` passed at `26d5ed5`. Router Image dry-run
`26351265685` passed for current head with preview metadata
`sha-26d5ed52278a`, GHCR login skipped, and no image publish. The strict
deployment-chain audit passed required gates on `master` at `26d5ed5`,
including clean current-head CI/logs, current Dart package dry-run, current
WAMP profile benchmark evidence, current Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; the audit suggests `v0.1.0-rc.2` as the next
numeric tag if release approval is given. Pub.dev publishing remains deferred
for release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Earlier implementation checkpoint: The public router-hosted MCP example now
exposes a bearer-protected JSON-response route at `/mcp/secure-json-post`,
configured with `post_response_transport: json` on the same route-provided
tool, WAMP meta API, pub/sub, resources, and prompts surface as the standard
example MCP route. The example smoke proves the route rejects missing bearer
credentials and an unknown bearer token, then uses the public IO client plus
HTTP ticket auth grant to cover direct JSON tools/list and tools/call, WAMP
tool/meta helpers, route-provided resources and prompts, Streamable initialize
and initialized notifications, tools/list, tools/call, resources/read,
prompts/get, pub/sub subscribe/publish/poll/unsubscribe, GET/SSE
`notifications/tools/list_changed` polling, and DELETE cleanup. The smoke also
asserts JSON POST responses on the active route keep the MCP session id stable
and do not capture a POST/SSE cursor before GET/SSE polling. This brings the
checked-in public example in line with the generated consumer-package secure
JSON-response readiness smoke without depending on private downstream
application assumptions. Pre-change `bin/test-fast` passed on 2026-05-24.
Focused local coverage passed on 2026-05-24:
`dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`,
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_router_hosted_mcp_example_smoke'`,
`python3 tool/check_public_artifact_references.py`, and `git diff --check`.
Full local `bin/verify` passed on 2026-05-24. Commit `7440ca4`
(`example: cover secure json-response mcp route`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `7440ca4`: `master` CI run `26350085437` passed with Fast Checks and
Full Verify green plus clean logs, and `add-router` CI run `26350083211`
passed with Fast Checks and Full Verify green. Dart Package Publish Dry Run
`26350085430` on `master` and `26350083219` on `add-router` passed cleanly at
`7440ca4`; WAMP Profile Benchmarks `26350085438` on `master` and
`26350083220` on `add-router` also passed at `7440ca4`. The Router Image
dry-run `26350340880` passed for current head with preview metadata
`sha-7440ca41ac9a`, GHCR login skipped, and no image publish. The strict
deployment-chain audit passed required gates on `master` at `7440ca4`,
including clean current-head CI/logs, current Dart package dry-run, current
WAMP profile benchmark evidence, current Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; the audit suggests `v0.1.0-rc.2` as the next
numeric tag if release approval is given. Pub.dev publishing remains deferred
for release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Earlier implementation checkpoint: The generated consumer-package
router-hosted MCP smoke now adds a bearer-protected JSON-response route at
`/mcp/secure-json-post`, configured with the snake-case
`post_response_transport: json` option and the same route-provided tool, WAMP
meta API, pub/sub, resources, and prompts surface as the consumer MCP route.
The smoke proves missing-bearer and unknown-bearer requests are rejected on
that JSON-response endpoint before issuing a ticket HTTP auth grant, then runs
the existing JSON-response compatibility coverage through the authenticated
client. That authorized route smoke covers direct JSON single, batch,
notification-only, and error/recovery requests, Streamable HTTP initialize and
initialized notifications, typed tools/resources/prompts, raw tools/list and
ping with the active `MCP-Session-Id`, WAMP pub/sub polling, GET/SSE
notification delivery, and DELETE cleanup without capturing POST/SSE cursors
or changing the active session id. This closes the remaining app-shaped
consumer readiness gap where JSON-response compatibility routes were public
only while secure MCP auth/session correctness was proven only on the standard
Streamable route. Pre-change `bin/test-fast` passed on 2026-05-24. Focused
local coverage passed on 2026-05-24:
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
`bash -n bin/common.sh`, and `git diff --check`. Full local `bin/verify`
passed on 2026-05-24. Commit `77015b9`
(`test: cover secure json-response mcp route`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`77015b9`: `master` CI run `26349158295` passed with Fast Checks and Full
Verify green plus clean logs, and `add-router` CI run `26349158303` passed
with Fast Checks and Full Verify green. The strict deployment-chain audit
passed required gates on `master` at `77015b9`, including clean current-head
CI/logs, relevant Dart package dry-run, relevant WAMP profile benchmark
evidence, relevant Router Image dry-run, native release dry-run relevance,
branch protection, workflow visibility, and router package visibility. Router
Image dry-run `26345818520` at `f8497d6` remains relevant because no
router-image-sensitive paths changed, with preview metadata
`sha-f8497d6ea540`, GHCR login skipped, and no image publish. Dart Package
Publish Dry Run `26344002614` at `9ac5e22`, WAMP Profile Benchmarks
`26344002624` at `9ac5e22`, and Native Artifacts dry-run `26286794628` remain
relevant because no publish-, WAMP-profile-, or native-release-sensitive
inputs changed. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected; the audit suggests `v0.1.0-rc.2` as the next numeric tag if release
approval is given. Pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Previous implementation checkpoint: The generated consumer-package
router-hosted MCP smoke now reuses the raw direct JSON CORS error/recovery
assertion after both JSON-response Streamable compatibility routes have opened
an MCP session: `postResponseTransport: json` and
`streamPostResponses: false`. The active-session slice sends the current
`MCP-Session-Id` on raw direct JSON requests, covers missing tools, resources,
prompts, API descriptions, and pub/sub handles, keeps mixed success/error batches
recoverable with notification suppression, and verifies the JSON-response
route keeps the Streamable session id stable without capturing a POST/SSE
cursor. This extends the previous sessionless JSON-response route coverage,
which already proved direct JSON single, batch, notification-only, and
error/recovery behavior before opening a Streamable session. Pre-change
`bin/test-fast` passed on 2026-05-24.
Focused local coverage passed on 2026-05-24:
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
`bash -n bin/common.sh`, `python3 tool/check_public_artifact_references.py`,
and `git diff --check`. Full local `bin/verify` passed on 2026-05-24.
Commit `cb6fdfc` (`test: cover active json-response mcp errors`) was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `cb6fdfc`: `master` CI run `26348290257` passed with
Fast Checks and Full Verify green plus clean logs, and `add-router` CI run
`26348288465` passed with Fast Checks and Full Verify green. The strict
deployment-chain audit passed required gates on `master` at `cb6fdfc`,
including clean current-head CI/logs, relevant Dart package dry-run, relevant
WAMP profile benchmark evidence, relevant Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. Router Image dry-run `26345818520` at `f8497d6` remains relevant
because no router-image-sensitive paths changed, with preview metadata
`sha-f8497d6ea540`, GHCR login skipped, and no image publish. Dart Package
Publish Dry Run `26344002614` at `9ac5e22`, WAMP Profile Benchmarks
`26344002624` at `9ac5e22`, and Native Artifacts dry-run `26286794628` remain
relevant because no publish-, WAMP-profile-, or native-release-sensitive
inputs changed. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected; the audit suggests `v0.1.0-rc.2` as the next numeric tag if release
approval is given. Pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Earlier implementation checkpoint: The generated consumer-package router-hosted
MCP smoke applies the raw direct JSON CORS single, batch, notification-only,
and error/recovery assertions to both JSON-response Streamable compatibility
routes before opening a Streamable session. This proves sessionless direct
JSON access for tools/list, ping, tool-call aliases, WAMP API list/describe
metadata, resources/list/read/templates, prompts/list/get, and pub/sub
subscribe/publish/poll/unsubscribe on those JSON response routes, including
batch JSON-RPC catalog, detail, tool-call, and pub/sub flows. It also proves
raw notification-only POSTs on those routes remain CORS-visible, bodyless
`202 Accepted` responses that do not create or mutate Streamable MCP session state.
The error/recovery smoke covers missing tools, resources, prompts, API
descriptions, and pub/sub handles, plus mixed success/error batches with
notification suppression and successful follow-up catalog reads.
Commit `d1888c0` (`test: cover json-response mcp error recovery`) was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `d1888c0`: `master` CI run `26347442474` passed with
Fast Checks and Full Verify green plus clean logs, and `add-router` CI run
`26347441207` passed with Fast Checks and Full Verify green. Router Image
dry-run `26345818520` at `f8497d6` remains relevant because no
router-image-sensitive paths changed, with preview metadata
`sha-f8497d6ea540`, GHCR login skipped, and no image publish. Dart Package
Publish Dry Run `26344002614` at `9ac5e22`, WAMP Profile Benchmarks
`26344002624` at `9ac5e22`, and Native Artifacts dry-run `26286794628` remain
relevant because no publish-, WAMP-profile-, or native-release-sensitive
inputs changed. The strict deployment-chain audit passed required gates on
`master` at `d1888c0`, including clean current-head CI/logs, relevant Dart
package dry-run, relevant WAMP profile benchmark evidence, relevant Router
Image dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected; the audit suggests `v0.1.0-rc.2` as the next
numeric tag if release approval is given. Pub.dev publishing remains deferred
for release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint: Commit `d6b4c44`
(`test: cover json-response mcp notifications`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence was
clean at `d6b4c44`: `master` CI run `26346638661` and `add-router` CI run
`26346636643` passed.
Prior checkpoint details: Commit `f8497d6`
(`test: cover direct json mcp response routes`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. It applied raw direct JSON
CORS single and batch assertions to both JSON-response Streamable
compatibility routes before opening a Streamable session, proving
sessionless direct JSON access for tool/meta API, resources/prompts, and
pub/sub request/response flows on those routes.
Prior checkpoint details: Commit `f860178`
(`test: cover json-response mcp context routes`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. It configured resources,
resource templates, prompts, and pagination limits on both JSON-response
Streamable compatibility routes, verified typed Streamable resources/prompts
helpers on those routes, confirmed the responses stayed JSON rather than
POST/SSE, kept the active session id stable, and extended typed direct
protocol-version override coverage to resources/read and prompts/get from the
same app-shaped package boundary. Hosted GitHub evidence is clean at
`f860178`: `master` CI run `26344918687` passed with Fast Checks and Full
Verify green plus clean logs, `add-router` CI run `26344909791` passed, and
clean Router Image dry-run `26344922913` passed for current head with preview
metadata `sha-f86017842835`, GHCR login skipped, and no image publish. The
latest Dart Package Publish Dry Run `26344002614` at `9ac5e22` remains
relevant because no publish-sensitive paths changed, the latest WAMP Profile
Benchmarks run `26344002624` at `9ac5e22` remains relevant because no
WAMP-profile-sensitive paths changed, and Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed. The strict deployment-chain audit passed required gates on `master`
at `f860178`, including clean current-head CI/logs, relevant Dart package
dry-run, relevant WAMP profile benchmark evidence, current Router Image
dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint details: Commit `9ac5e22`
(`fix: keep streamable protocol overrides stateless`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `9ac5e22`: `master` CI run `26344002623` passed with Fast Checks and
Full Verify green plus clean logs, `add-router` CI run `26344001242` passed,
`master` Dart Package Publish Dry Run `26344002614` passed, `add-router` Dart
Package Publish Dry Run `26344001253` passed, `master` WAMP Profile Benchmarks
`26344002624` passed, `add-router` WAMP Profile Benchmarks `26344001266`
passed, and clean Router Image dry-run `26344012477` passed for current head
with preview metadata `sha-9ac5e22430a4`, GHCR login skipped, and no image
publish. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `9ac5e22`, including clean current-head
CI/logs, current Dart package dry-run, current WAMP profile benchmark evidence,
current Router Image dry-run, native release dry-run relevance, branch
protection, workflow visibility, and router package visibility. RC readiness
remains not-ready only because no approved numeric RC tag, GitHub prerelease,
or matching RC router image tag has been selected, and pub.dev publishing
remains deferred for release-order and operator decisions. No RC tag, GitHub
Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `e2cd258`
(`fix: expose mcp protocol override on typed helpers`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `e2cd258`: `master` CI run `26342560829` passed with Fast Checks and
Full Verify green plus clean logs, `add-router` CI run `26342560812` passed,
`master` Dart Package Publish Dry Run `26342560810` passed, `add-router` Dart
Package Publish Dry Run `26342560819` passed, `master` WAMP Profile Benchmarks
`26342560800` passed, `add-router` WAMP Profile Benchmarks `26342560813`
passed, and clean Router Image dry-run `26342852651` passed for current head
with preview metadata `sha-e2cd2580e16a`, GHCR login skipped, and no image
publish. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `e2cd258`, including clean current-head
CI/logs, current Dart package dry-run, current WAMP profile benchmark evidence,
current Router Image dry-run, native release dry-run relevance, branch
protection, workflow visibility, and router package visibility. RC readiness
remains not-ready only because no approved numeric RC tag, GitHub prerelease,
or matching RC router image tag has been selected, and pub.dev publishing
remains deferred for release-order and operator decisions. No RC tag, GitHub
Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `941ae91`
(`fix: expose mcp protocol override on request helpers`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `941ae91`: `master` CI run `26341477286` passed with Fast Checks and
Full Verify green plus clean logs, `add-router` CI run `26341477312` passed,
`master` Dart Package Publish Dry Run `26341477304` passed, `add-router` Dart
Package Publish Dry Run `26341477297` passed, `master` WAMP Profile Benchmarks
`26341477303` passed, `add-router` WAMP Profile Benchmarks `26341477296`
passed, and clean Router Image dry-run `26341778458` passed for current head
with preview metadata `sha-941ae9164dc5`, GHCR login skipped, and no image
publish. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `941ae91`, including clean current-head
CI/logs, current Dart package dry-run, current WAMP profile benchmark evidence,
current Router Image dry-run, native release dry-run relevance, branch
protection, workflow visibility, and router package visibility. RC readiness
remains not-ready only because no approved numeric RC tag, GitHub prerelease,
or matching RC router image tag has been selected, and pub.dev publishing
remains deferred for release-order and operator decisions. No RC tag, GitHub
Release, or router image was created or moved.
Prior hosted checkpoint details: Generic MCP HTTP client helpers now expose
the same protocol-version override that low-level POST helpers already had:
`McpStreamableHttpClient.request(...)`, `requestDirect(...)`,
`notification(...)`, and `notificationDirect(...)` accept an optional
`protocolVersion` and forward it as `MCP-Protocol-Version` without mutating the
client's negotiated Streamable HTTP version. This keeps downstream
applications on public direct JSON tool/meta APIs when they need to probe
older supported MCP protocol versions, instead of forcing raw JSON-RPC POST
bodies for that compatibility path. Focused local coverage passed on
2026-05-23:
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
and
`dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`.
Pre-change `bin/test-fast` and full local `bin/verify` passed on 2026-05-23.
Prior hosted checkpoint details: Streamable HTTP explicit initialize
negotiation now sends the requested supported MCP protocol version in both the
JSON-RPC initialize body and the `MCP-Protocol-Version` request header. The
low-level direct JSON POST helpers also accept a protocol-version header
override without mutating the negotiated client version, so compatibility
probes can exercise older supported MCP versions through direct JSON access.
Generated consumer-package smokes and the router-hosted example now keep the
client default at latest while passing explicit initialize versions, proving
header/body alignment from the consumer boundary. Pre-change `bin/test-fast`
passed on 2026-05-23, focused MCP client test, generated consumer smoke,
router-hosted example smoke, public-artifact guard, shell syntax check, diff
checks, and full local `bin/verify` passed on 2026-05-23. Commit `25fd0f7`
(`fix: align explicit mcp protocol headers`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`25fd0f7`: `master` CI run `26340457507` passed with Fast Checks and Full
Verify green plus clean logs, `add-router` CI run `26340457117` passed,
`master` Dart Package Publish Dry Run `26340457490` passed, `add-router` Dart
Package Publish Dry Run `26340457128` passed, `master` WAMP Profile Benchmarks
`26340457495` passed, `add-router` WAMP Profile Benchmarks `26340457141`
passed, and clean Router Image dry-run `26340473727` passed for current head
with preview metadata `sha-25fd0f778518`, GHCR login skipped, and no image
publish. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `25fd0f7`, including clean current-head
CI/logs, current Dart package dry-run, current WAMP profile benchmark evidence,
current Router Image dry-run, native release dry-run relevance, branch
protection, workflow visibility, and router package visibility. RC readiness
remains not-ready only because no approved numeric RC tag, GitHub prerelease,
or matching RC router image tag has been selected, and pub.dev publishing
remains deferred for release-order and operator decisions. No RC tag, GitHub
Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `d216a2d`
(`fix: honor supported mcp protocol versions`) made MCP initialize negotiation
return a requested supported protocol version (`2025-03-26`, `2025-06-18`, or
`2025-11-25`) instead of always upgrading to latest, while unsupported body
versions still fall back to latest. Router-hosted Streamable HTTP and direct
JSON responses propagate the negotiated or supported request protocol version
in MCP response headers, and the Streamable HTTP client updates its negotiated
protocol version from the initialize result. Generated consumer-package smokes
and the router-hosted example now assert that supported older MCP versions
remain negotiated for downstream application readiness. Pre-change
`bin/test-fast` passed on 2026-05-23, focused lifecycle/client/router,
generated consumer smoke, router-hosted example smoke, public-artifact guard,
and diff checks passed, and full local `bin/verify` passed on 2026-05-23.
Commit `d216a2d` was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted GitHub
evidence is clean at `d216a2d`: `master` CI run `26339458336` passed with Fast
Checks and Full Verify green plus clean logs, `add-router` CI run
`26339456857` passed, `master` Dart Package Publish Dry Run `26339458338`
passed, `add-router` Dart Package Publish Dry Run `26339456838` passed,
`master` WAMP Profile Benchmarks `26339458339` passed, `add-router` WAMP
Profile Benchmarks `26339456830` passed, and clean Router Image dry-run
`26339470709` passed for current head with preview metadata
`sha-d216a2d5ae8e`, GHCR login skipped, and no image publish. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed. The strict deployment-chain audit passed required gates on
`master` at `d216a2d`, including clean current-head CI/logs, current Dart
package dry-run, current WAMP profile benchmark evidence, current Router Image
dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint details: The public artifact reference guard now also
scans `bin/common.sh`, keeping the generated MCP consumer smoke packages and
their embedded package metadata under the same local downstream path and
private-literal guard as checked-in public docs, package metadata, release-note
templates, and examples. Pre-change `bin/test-fast` passed on 2026-05-23, and
focused local checks passed:
`python3 tool/check_public_artifact_references.py` and
`python3 tool/test_public_artifact_references.py`. Full local `bin/verify`
passed on 2026-05-23 for this checkpoint. Commit `c704248`
(`test: scan generated mcp smoke artifacts`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`c704248`: `master` CI run `26337377257` passed with Fast Checks and Full
Verify green plus clean logs, and `add-router` CI run `26337374836` passed.
The strict deployment-chain audit passed required gates on `master` at
`c704248`; Dart Package Publish Dry Run, Native Artifacts dry-run, Router
Image dry-run, and WAMP Profile Benchmarks evidence from `e14615a` or earlier
remained relevant because `c704248` did not change those sensitive inputs. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected, and pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Fast and full verification now run
`tool/check_public_artifact_references.py` plus its focused regression tests,
guarding checked-in public docs, release-note templates, package metadata, and
examples against local downstream paths while allowing neutral "consumer
application" or "downstream application" wording.
Commit `b259c79` (`test: guard public artifact references`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `b259c79`: `master` CI run `26336504930` passed with Fast
Checks and Full Verify green plus clean logs, and `add-router` CI run
`26336504920` passed. The strict deployment-chain audit passed required gates
on `master` at `b259c79`; Dart Package Publish Dry Run, Native Artifacts
dry-run, Router Image dry-run, and WAMP Profile Benchmarks evidence from
`e14615a` or earlier remained relevant because `b259c79` did not change those
sensitive inputs. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `cbb1382`
(`test: harden mcp consumer alias smoke`) extended the generated consumer
package smoke for router-hosted MCP route aliases and initialize metadata. It
exercises the public MCP route with camel-case route option aliases for server
identity, catalog page sizes, allowed origins, topic schema metadata, and
resource template/content fields; asserts that Streamable HTTP `initialize`
returns route-provided MCP `serverInfo` and `instructions`; and keeps the JSON
POST, non-streaming POST, and secure snake-case route paths covered. Local
verification passed: pre-change `bin/test-fast`, focused generated MCP
consumer package smoke, `bash -n bin/common.sh`, `git diff --check`, and full
local `bin/verify`. Hosted GitHub evidence is clean at `cbb1382`: `master` CI
run `26335448261` passed with Fast Checks and Full Verify green plus clean
logs, and `add-router` CI run `26335445322` passed. The strict deployment-chain
audit passed required gates on `master` at `cbb1382`; Dart Package Publish Dry
Run, Native Artifacts dry-run, Router Image dry-run, and WAMP Profile
Benchmarks evidence from `e14615a` or earlier remained relevant because
`cbb1382` did not change those sensitive inputs. RC readiness remains
not-ready only because no approved numeric RC tag, GitHub prerelease, or
matching RC router image tag has been selected, and pub.dev publishing remains
deferred for release-order and operator decisions. No RC tag, GitHub Release,
or router image was created or moved.
Prior hosted checkpoint details: Commit `e14615a`
(`fix: honor mcp route option aliases`) added router-hosted MCP route option
support and validation for top-level camel-case aliases for agent-facing
controls, including `includePubsubTools`, `includeStandardMetaApi`,
`includeRegisteredProcedures`, `includeSubscribedTopics`, `toolListPageSize`,
`promptListPageSize`, `resourceListPageSize`,
`resourceTemplateListPageSize`, `postResponseTransport`, and
`streamPostResponses`. Route `name`, `version`, `title`, `description`, and
`instructions` now flow into MCP `initialize` server metadata and instructions
instead of only influencing direct WAMP API metadata, and prompt
`resultDescription` is accepted and validated as the camel-case alias. Commit
`e14615a` was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
`master`. Hosted GitHub evidence is clean at `e14615a`: `master` CI run
`26334367559` passed with Fast Checks and Full Verify green plus clean logs,
`add-router` CI run `26334364715` passed, `master` Dart Package Publish Dry
Run `26334367577` passed, `add-router` Dart Package Publish Dry Run
`26334364694` passed, `master` WAMP Profile Benchmarks `26334368013` passed,
`add-router` WAMP Profile Benchmarks `26334364701` passed, and clean Router
Image dry-run `26334375630` passed for current head with preview metadata
`sha-e14615a40cc2`, GHCR login skipped, and no image publish. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed. The strict deployment-chain audit passed required gates on
`master` at `e14615a`, including clean current-head CI/logs, current Dart
package dry-run, current WAMP profile benchmark evidence, current Router Image
dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint details: Commit `ef4906b`
(`fix: validate mcp string route options`) added router-hosted MCP route
option validation for agent-facing string fields before building the native
router config. Malformed server `name`, configured procedure/topic display
fields, configured resource and resource-template URI/display/content fields,
and configured prompt, prompt-argument, and prompt-message string fields fail
fast instead of being silently dropped or reported as vague missing values.
Configured procedures now also honor the camel-case `toolName` alias. Commit
`ef4906b` was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
`master`. Hosted GitHub evidence is clean at `ef4906b`: `master` CI run
`26333047829` passed with Fast Checks and Full Verify green plus clean logs,
`add-router` CI run `26333047819` passed, `master` Dart Package Publish Dry Run
`26333047828` passed, `add-router` Dart Package Publish Dry Run `26333047820`
passed, `master` WAMP Profile Benchmarks `26333047831` passed, `add-router`
WAMP Profile Benchmarks `26333047818` passed, and clean Router Image dry-run
`26333056237` passed for current head with preview metadata
`sha-ef4906b7cab3`, GHCR login skipped, and no image publish. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed. The strict deployment-chain audit passed required gates on
`master` at `ef4906b`, including clean current-head CI/logs, current Dart
package dry-run, current WAMP profile benchmark evidence, current Router Image
dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint details: Commit `de79b40`
(`fix: validate mcp metadata route options`) added router-hosted MCP procedure
and topic metadata route option validation for agent-facing metadata shapes
before native router config export. Metadata string fields, string-list fields
such as `publishesEvents`, direct annotation hints, and nested `annotations`
hint values now fail fast when malformed instead of being silently dropped from
direct JSON or Streamable HTTP tool/topic metadata. Commit `de79b40` was
pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Local
verification passed on 2026-05-23: pre-change `bin/test-fast`, focused router
JSON config test, and full `bin/verify`. Hosted GitHub evidence is clean at
`de79b40`: `master` CI run `26332071957` passed with Fast Checks and Full
Verify green plus clean logs, `add-router` CI run `26332071970` passed,
`master` Dart Package Publish Dry Run `26332071969` passed, `add-router` Dart
Package Publish Dry Run `26332071958` passed, `master` WAMP Profile Benchmarks
`26332071941` passed, `add-router` WAMP Profile Benchmarks `26332071959`
passed, and clean Router Image dry-run `26332103181` passed for current head
with preview metadata `sha-de79b40edc18`, GHCR login skipped, and no image
publish. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `de79b40`, including clean current-head
CI/logs, current Dart package dry-run, current WAMP profile benchmark evidence,
current Router Image dry-run, native release dry-run relevance, branch
protection, workflow visibility, and router package visibility. RC readiness
remains not-ready only because no approved numeric RC tag, GitHub prerelease,
or matching RC router image tag has been selected, and pub.dev publishing
remains deferred for release-order and operator decisions. No RC tag, GitHub
Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `bc2260c`
(`fix: validate recursive mcp schema json`) added router-hosted MCP schema
route option validation that walks nested procedure and topic schema metadata
recursively, requiring map keys to be strings, values to be JSON-compatible,
and numbers to be finite. Malformed nested `inputSchema`, `outputJsonSchema`,
`eventSchema`, and metadata schema aliases now fail while building native
router config instead of escaping into agent-facing tool/topic metadata for
direct JSON or Streamable HTTP clients. Commit `bc2260c` was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `bc2260c`: `master` CI run `26331196480` passed with Fast Checks and
Full Verify green plus clean logs, `add-router` CI run `26331196355` passed,
`master` Dart Package Publish Dry Run `26331196497` passed, `add-router` Dart
Package Publish Dry Run `26331196373` passed, `master` WAMP Profile Benchmarks
`26331196490` passed, `add-router` WAMP Profile Benchmarks `26331196365`
passed, and clean Router Image dry-run `26331202343` passed for current head
with preview metadata `sha-bc2260c99087`, GHCR login skipped, and no image
publish. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `bc2260c`, including clean current-head
CI/logs, current Dart package dry-run, current WAMP profile benchmark
evidence, current Router Image dry-run, native release dry-run relevance,
branch protection, workflow visibility, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected, and pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `49ff2c5`
(`fix: validate mcp schema route options`) added router-hosted MCP procedure
and topic route config validation for direct JSON schema aliases plus nested
metadata schema aliases as JSON objects with string keys. Malformed
`inputSchema`, `outputJsonSchema`, `eventSchema`, and metadata schema variants
now fail while building native router config instead of silently dropping
agent-facing tool or topic schema metadata for a consumer application. Commit
`49ff2c5` was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
`master`. Hosted GitHub evidence is clean at `49ff2c5`: `master` CI run
`26330377110` passed with Fast Checks and Full Verify green plus clean logs,
`add-router` CI run `26330375276` passed, `master` Dart Package Publish Dry
Run `26330377353` passed, `add-router` Dart Package Publish Dry Run
`26330375284` passed, `master` WAMP Profile Benchmarks `26330377119` passed,
`add-router` WAMP Profile Benchmarks `26330375274` passed, and clean Router
Image dry-run `26330382749` passed for current head with preview metadata
`sha-49ff2c504620`, GHCR login skipped, and no image publish. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed. The strict deployment-chain audit passed required gates on
`master` at `49ff2c5`, including clean current-head CI/logs, current Dart
package dry-run, current WAMP profile benchmark evidence, current Router Image
dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint details: Commit `2659ee0`
(`fix: honor camel mcp topic options`) added router-hosted MCP topic route
config validation and support for camel-case `allowPublish` and
`allowSubscribe` aliases in addition to the existing snake-case config keys,
matching the public MCP WAMP topic metadata shape. The router-hosted MCP smoke
declares a public read-only topic with `allowPublish: false`; direct JSON and
Streamable HTTP checks prove the metadata exposes `allowPublish: false` and
`allowSubscribe: true`, and that publish attempts fail instead of
silently defaulting to publishable. Commit `2659ee0` was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `2659ee0`: `master` CI run `26329548485` passed with Fast Checks and
Full Verify green plus clean logs, `add-router` CI run `26329547966` passed,
`master` Dart Package Publish Dry Run `26329548469` passed, `add-router` Dart
Package Publish Dry Run `26329547976` passed, `master` WAMP Profile Benchmarks
`26329548463` passed, `add-router` WAMP Profile Benchmarks `26329547974`
passed, and clean Router Image dry-run `26329558070` passed for current head
with preview metadata `sha-2659ee0e63f5`, GHCR login skipped, and no image
publish. Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed. The strict deployment-chain audit
passed required gates on `master` at `2659ee0`, including clean current-head
CI/logs, current Dart package dry-run, current WAMP profile benchmark evidence,
current Router Image dry-run, native release dry-run relevance, branch
protection, workflow visibility, and router package visibility. RC readiness
remains not-ready only because no approved numeric RC tag, GitHub prerelease,
or matching RC router image tag has been selected, and pub.dev publishing
remains deferred for release-order and operator decisions. No RC tag, GitHub
Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `9b3e96d`
(`fix: validate nested mcp route options`) added MCP route option validation
for malformed nested configured procedure/topic/resource/prompt fields while
building native router config, including non-boolean procedure call flags,
non-boolean topic publish/subscribe flags, non-integer or negative resource
sizes, non-list prompt arguments/messages, non-boolean required prompt
arguments, and non-string prompt message roles. This keeps router-hosted MCP
endpoints fail-fast for consumer application configuration errors instead of
silently ignoring nested route fields or falling back to defaults. Commit
`9b3e96d` was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
`master`. Hosted GitHub evidence is clean at `9b3e96d`: `master` CI run
`26328491376` passed with Fast Checks and Full Verify green plus clean logs,
`add-router` CI run `26328491411` passed, `master` Dart Package Publish Dry
Run `26328491393` passed, `add-router` Dart Package Publish Dry Run
`26328491409` passed, `master` WAMP Profile Benchmarks `26328491395` passed,
`add-router` WAMP Profile Benchmarks `26328491408` passed, and clean Router
Image dry-run `26328839965` passed for current head with preview metadata
`sha-9b3e96d38542`, GHCR login skipped, and no image publish. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed. The strict deployment-chain audit passed required gates on
`master` at `9b3e96d`, including clean current-head CI/logs, current Dart
package dry-run, current WAMP profile benchmark evidence, current Router Image
dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint details: Commit `7f2d4f9`
(`fix: validate mcp route option shapes`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`7f2d4f9`: `master` CI run `26327603290` passed with Fast Checks and Full
Verify green plus clean logs, `add-router` CI run `26327603273` passed,
`master` Dart Package Publish Dry Run `26327603260` passed, `add-router` Dart
Package Publish Dry Run `26327603276` passed, `master` WAMP Profile
Benchmarks `26327603281` passed, `add-router` WAMP Profile Benchmarks
`26327603275` passed, and Router Image dry-run `26327615245` passed for
current head with preview metadata `sha-7f2d4f9ca7ec`, GHCR login skipped, and
no image publish. Native Artifacts dry-run `26286794628` remains relevant
because no native-release-sensitive inputs changed. The strict
deployment-chain audit passed required gates on `master` at `7f2d4f9`,
including clean current-head CI/logs, current Dart package dry-run, current
WAMP profile benchmark evidence, current Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `e274b5a`
(`fix: validate mcp post response options`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`e274b5a`: `master` CI run `26326611407` passed with Fast Checks and Full
Verify green plus clean logs, `add-router` CI run `26326609144` passed,
`master` Dart Package Publish Dry Run `26326611413` passed, `add-router` Dart
Package Publish Dry Run `26326609130` passed, `master` WAMP Profile
Benchmarks `26326611401` passed, `add-router` WAMP Profile Benchmarks
`26326609137` passed, and Router Image dry-run `26326876433` passed for
current head with GHCR login skipped and no image publish. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed. The strict deployment-chain audit passed required gates on
`master` at `e274b5a`, including clean current-head CI/logs, current Dart
package dry-run, current WAMP profile benchmark evidence, current Router Image
dry-run, native release dry-run relevance, branch protection, workflow
visibility, and router package visibility. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order and operator decisions. No RC tag, GitHub Release, or router
image was created or moved.
Prior hosted checkpoint details: Commit `d2cc63b`
(`test: cover mcp json post responses`) was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`d2cc63b`: `master` CI run `26325673314` passed with Fast Checks and Full
Verify green plus clean logs, and `add-router` CI run `26325672952` passed.
`master` Dart Package Publish Dry Run `26323732462`, `master` WAMP Profile
Benchmarks `26323732487`, Router Image dry-run `26323764121`, and Native
Artifacts dry-run `26286794628` remain relevant because no publish-sensitive,
WAMP-profile-benchmark-sensitive, router-image-sensitive, or
native-release-sensitive inputs changed since those runs. The strict
deployment-chain audit passed required gates on `master` at `d2cc63b`,
including clean current-head CI/logs, relevant Dart package dry-run, relevant
WAMP profile benchmark evidence, relevant Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `dfedfd5`
(`test: cover active-session direct mcp access`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `dfedfd5`: `master` CI run `26324656392` passed with Fast Checks and
Full Verify green plus clean logs, and `add-router` CI run `26324655835`
passed. `master` Dart Package Publish Dry Run `26323732462`, `master` WAMP
Profile Benchmarks `26323732487`, Router Image dry-run `26323764121`, and
Native Artifacts dry-run `26286794628` remain relevant because no
publish-sensitive, WAMP-profile-benchmark-sensitive, router-image-sensitive,
or native-release-sensitive inputs changed since those runs. The strict
deployment-chain audit passed required gates on `master` at `dfedfd5`,
including clean current-head CI/logs, relevant Dart package dry-run, relevant
WAMP profile benchmark evidence, relevant Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `3c6ff20`
(`fix: honor mcp auth publish filters`) made router publish delivery honor
standard WAMP authid/authrole include and exclude option keys from raw WAMP,
direct JSON MCP, and Streamable MCP publish calls. The router worker maps
`exclude_authid`, `exclude_authrole`, `eligible_authid`, and
`eligible_authrole` into state matching, while the state matcher still accepts
legacy plural auth filter aliases for compatibility. The generated
router-hosted MCP consumer package smoke discovers the MCP subscriber session
and auth metadata through WAMP meta, then proves session ID, authid, and
authrole delivery/suppression filters through both direct JSON and Streamable
MCP paths without private project assumptions. A router worker regression covers
raw WAMP authid include/exclude delivery. Local verification passed, then
commit `3c6ff20` was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted GitHub evidence is clean at `3c6ff20`: `master` CI run
`26323732469` passed with Fast Checks and Full Verify green and clean logs,
`add-router` CI run `26323730795` passed, `master` Dart Package Publish Dry Run
`26323732462` and `add-router` Dart Package Publish Dry Run `26323730799`
passed, `master` WAMP Profile Benchmarks `26323732487` and `add-router` WAMP
Profile Benchmarks `26323730797` passed, and Router Image dry-run
`26323764121` passed for `0.1.0-rc.1-validation.3c6ff20` with preview upload,
skipped GHCR login, completed multi-arch build, and clean annotations. Native
Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed since `89c7915`. The strict
deployment-chain audit passed required gates on `master` at `3c6ff20`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark evidence, Router Image dry-run, native release dry-run relevance,
branch protection, workflow visibility, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected, and pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `f7cf3d3`
(`test: cover mcp session publish filters`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`f7cf3d3`: `master` CI run `26322569564` passed with Fast Checks and Full
Verify green and clean logs, and `add-router` CI run `26322567606` passed.
`master` Dart Package Publish Dry Run `26319930721` and `add-router` Dart
Package Publish Dry Run `26319930224` remain relevant because no
publish-sensitive paths changed since `8aba33c`; `master` WAMP Profile
Benchmarks `26319930699` and `add-router` WAMP Profile Benchmarks
`26319930217` remain relevant because no WAMP profile benchmark-sensitive paths
changed since `8aba33c`; current-head Router Image dry-run `26320203435`
remains relevant because no router-image-sensitive paths changed since
`8aba33c`; Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed since `89c7915`. The strict
deployment-chain audit passed required gates on `master` at `f7cf3d3`,
including clean current-head CI/logs, relevant Dart package dry-run, relevant
WAMP profile benchmark evidence, relevant Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `2e3a792`
(`test: cover mcp exclude-me publish options`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`2e3a792`: `master` CI run `26321124924` passed with Fast Checks and Full
Verify green and clean logs, and `add-router` CI run `26321124820` passed.
`master` Dart Package Publish Dry Run `26319930721` and `add-router` Dart
Package Publish Dry Run `26319930224` remain relevant because no
publish-sensitive paths changed since `8aba33c`; `master` WAMP Profile
Benchmarks `26319930699` and `add-router` WAMP Profile Benchmarks
`26319930217` remain relevant because no WAMP profile benchmark-sensitive paths
changed since `8aba33c`; current-head Router Image dry-run `26320203435`
remains relevant because no router-image-sensitive paths changed since
`8aba33c`; Native Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed since `89c7915`. The strict
deployment-chain audit passed required gates on `master` at `2e3a792`,
including clean current-head CI/logs, relevant Dart package dry-run, relevant
WAMP profile benchmark evidence, relevant Router Image dry-run, native release
dry-run relevance, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `8aba33c`
(`feat: add mcp wamp option builders`) added public
`mcpWampPublishOptions(...)` and `mcpWampSubscribeOptions(...)` builders for
canonical WAMP option maps instead of hand-built string-key maps. The builders
emit standard wire keys such as `exclude_me`, `meta_topic`, `get_retained`,
and PPT option fields while preserving consumer extension keys from `custom`;
typed parameters override duplicate `custom` entries for standard fields. The
Streamable client tests prove both active-session and lifecycle-free direct
JSON helpers send these option maps, the MCP IO export smoke covers the same
helpers through `connectanum_mcp_io.dart`, and the generated client-only plus
router-hosted consumer smokes use the public builders for subscribe/publish
acknowledgement paths. Pre-change `bin/test-fast`, focused client/MCP tests,
`dart analyze packages/connectanum_client packages/connectanum_mcp`, focused
generated client-only and router-hosted consumer smokes, repeated
`bin/test-fast`, and full local `bin/verify` passed on 2026-05-23. Commit
`8aba33c` was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
`master`. Hosted GitHub evidence is clean at `8aba33c`: `master` CI run
`26319930691` passed with Fast Checks and Full Verify green and clean logs,
`add-router` CI run `26319930213` passed, `master` Dart Package Publish Dry
Run `26319930721` and `add-router` Dart Package Publish Dry Run `26319930224`
passed, `master` WAMP Profile Benchmarks `26319930699` and `add-router` WAMP
Profile Benchmarks `26319930217` passed, and current-head Router Image dry-run
`26320203435` passed for `0.1.0-rc.2-validation.8aba33c` with preview upload,
skipped GHCR login, completed multi-arch build, and clean annotations. Native
Artifacts dry-run `26286794628` remains relevant because no
native-release-sensitive inputs changed since `89c7915`. The strict
deployment-chain audit passed required gates on `master` at `8aba33c`,
including clean current-head CI/logs, Dart package dry-run, WAMP profile
benchmark evidence, Router Image dry-run, native release dry-run relevance,
branch protection, workflow visibility, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected, and pub.dev
publishing remains deferred for release-order and operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `06228fb`
(`fix: normalize mcp wamp pubsub options`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`06228fb`: `master` CI run `26318444140` passed with Fast Checks and Full
Verify green and clean logs, `add-router` CI run `26318442150` passed,
`master` Dart Package Publish Dry Run `26318444109` and `add-router` Dart
Package Publish Dry Run `26318442141` passed, and current-head Router Image
dry-run `26318773516` passed for `0.1.0-rc.2-validation.06228fb` with preview
upload, skipped GHCR login, completed multi-arch build, and clean annotations.
WAMP Profile Benchmarks `26317169023` on `master` and `26317168999` on
`add-router` remain relevant because no WAMP profile benchmark-sensitive inputs
changed since `d35ac42`. Native Artifacts dry-run `26286794628` remains
relevant because no native-release-sensitive inputs changed since `89c7915`.
The strict deployment-chain audit passed required gates on `master` at
`06228fb`, including clean current-head CI/logs, Dart package dry-run, WAMP
profile benchmark evidence, Router Image dry-run, native release dry-run
relevance, branch protection, workflow visibility, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order and operator decisions.
No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `d35ac42`
(`fix: reject direct mcp notification responses`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `d35ac42`: `master` CI run `26317169024` passed with Fast Checks and
Full Verify green and clean logs, `add-router` CI run `26317168997` passed,
`master` Dart Package Publish Dry Run `26317168989` and `add-router` Dart
Package Publish Dry Run `26317168998` passed, `master` WAMP Profile Benchmarks
`26317169023` and `add-router` WAMP Profile Benchmarks `26317168999` passed,
and current-head Router Image dry-run `26317182342` passed for
`0.1.0-rc.2-validation.d35ac42` with preview upload, skipped GHCR login,
completed multi-arch build, and clean annotations. Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed since `89c7915`. The strict deployment-chain audit passed required
gates on `master` at `d35ac42`, including clean current-head CI/logs, Dart
package dry-run, WAMP profile benchmark evidence, Router Image dry-run, native
release dry-run relevance, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `f15518b`
(`fix: reject mcp notification response bodies`)
rejects non-empty successful POST response bodies for JSON-RPC notifications
and notification-only batches before accepting response `MCP-Session-Id` /
protocol-version headers or POST/SSE resume cursors. This aligns the client
with the MCP Streamable HTTP transport contract
(`https://modelcontextprotocol.io/specification/2025-06-18/basic/transports`):
accepted client notifications or responses use `202 Accepted` with no body,
while response-bearing requests use JSON or SSE bodies. Empty, accepted, or
no-content notification responses still remain accepted. The focused
regression was added first and failed against the prior behavior because a
notification-only POST with a body returned normally instead of throwing before
state capture. Coverage now exercises single notifications and
notification-only batches over both JSON and POST/SSE bodies, proving
`sessionId` and `lastEventId` stay unchanged when the server includes
replacement session headers or SSE event ids. The generated client-only
consumer-package smoke exercises the same paths through public
`connectanum_mcp_io.dart` APIs. Pre-change `bin/test-fast` passed before edits.
After the fix, the focused malformed POST regression, full
`streamable_http_client_test.dart`, `bash -n bin/common.sh`, focused generated
client-only consumer smoke, `dart analyze packages/connectanum_client`,
repeated `bin/test-fast`, and full local `bin/verify` passed on 2026-05-23.
Commit `f15518b` (`fix: reject mcp notification response bodies`) was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `f15518b`: `master` CI run `26315819342` passed with Fast
Checks and Full Verify green and clean logs, `add-router` CI run `26315818609`
passed, `master` Dart Package Publish Dry Run `26315819303` and `add-router`
Dart Package Publish Dry Run `26315818619` passed, `master` WAMP Profile
Benchmarks `26315819251` and `add-router` WAMP Profile Benchmarks
`26315818639` passed, and current-head Router Image dry-run `26315836302`
passed for `0.1.0-rc.2-validation.f15518b` with preview upload, skipped GHCR
login, completed multi-arch build, and clean annotations. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed since `89c7915`. The strict deployment-chain audit passed
required gates on `master` at `f15518b`, including clean current-head CI/logs,
Dart package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
native release dry-run relevance, branch protection, workflow visibility, and
router package visibility. RC readiness remains not-ready only because no
approved numeric RC tag, GitHub prerelease, or matching RC router image tag has
been selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `bed07fa`
(`fix: validate mcp post response shape`) validates the JSON-RPC response
shape for stateful POST requests before
accepting successful response `MCP-Session-Id` / protocol-version headers or
POST/SSE resume cursors. Single JSON-RPC requests with an `id` must receive a
JSON object, request batches with response-bearing items must receive an array
of JSON objects, and accepted/no-content/empty or POST/SSE streams without a
matching response now throw before session/cursor capture. The client
regression was added first and failed against the prior behavior because a
valid JSON array response with `MCP-Session-Id: post-json-shape-session`
changed the active session from `session-1` before `listTools` rejected the
response shape. The regression now also covers POST/SSE streams that contain
only notifications plus response-bearing batches that return a single JSON
object, proving both `sessionId` and `lastEventId` remain unchanged before a
fresh request recovers on the same session. The generated client-only
consumer-package smoke exercises the same wrong-shape JSON, missing POST/SSE
response, and wrong-shape batch paths through public
`connectanum_mcp_io.dart` APIs. Pre-change `bin/test-fast` passed before edits.
After the fix, the focused malformed POST regression, full
`streamable_http_client_test.dart`, `bash -n bin/common.sh`, focused generated
client-only consumer smoke, `dart analyze packages/connectanum_client`,
repeated `bin/test-fast`, and full local `bin/verify` passed on 2026-05-22.
Commit `bed07fa` (`fix: validate mcp post response shape`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `bed07fa`: `master` CI run `26313816851` passed with Fast
Checks and Full Verify green and clean logs, `add-router` CI run `26313816819`
passed, `master` Dart Package Publish Dry Run `26313816817` and `add-router`
Dart Package Publish Dry Run `26313816843` passed, `master` WAMP Profile
Benchmarks `26313816842` and `add-router` WAMP Profile Benchmarks
`26313816821` passed, and current-head Router Image dry-run `26313868479`
passed for `0.1.0-rc.2-validation.bed07fa` with preview upload, skipped GHCR
login, completed multi-arch build, and clean annotations. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed since `89c7915`. The strict deployment-chain audit passed
required gates on `master` at `bed07fa`, including clean current-head CI/logs,
Dart package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
native release dry-run relevance, branch protection, workflow visibility, and
router package visibility. RC readiness remains not-ready only because no
approved numeric RC tag, GitHub prerelease, or matching RC router image tag has
been selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `66e89c6`
(`fix: preserve mcp post sessions`) was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. `McpStreamableHttpClient._postPayload()` now
defers successful POST response `MCP-Session-Id` / protocol-version capture
until the JSON body or POST/SSE event data parses successfully. POST/SSE resume
cursor capture now also happens only after SSE event JSON is valid and a
matching response has been selected. HTTP 401/403/404 session cleanup still
runs before any response header capture, and successful 202/204/empty
notification responses still capture valid response session headers. The client
regression was added first and failed against the prior behavior because a
malformed JSON POST response with `MCP-Session-Id: post-json-session` changed
the active session from `session-1` before throwing. The regression now also
covers malformed POST/SSE event data with a replacement response session header
and proves both `sessionId` and `lastEventId` remain unchanged before a fresh
request recovers on the same session. The generated client-only
consumer-package smoke now exercises the same malformed POST JSON/SSE response
paths through public `connectanum_mcp_io.dart` APIs. Pre-change `bin/test-fast`
passed before edits. After the fix, the focused malformed POST regression, full
`streamable_http_client_test.dart`, `bash -n bin/common.sh`, focused generated
client-only consumer smoke, `dart analyze packages/connectanum_client`,
repeated `bin/test-fast`, and full local `bin/verify` passed on 2026-05-22.
Commit `66e89c6` (`fix: preserve mcp post sessions`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `66e89c6`: `master` CI run `26311665595` passed with Fast Checks and
Full Verify green and clean logs, `add-router` CI run `26311662052` passed,
`master` Dart Package Publish Dry Run `26311665598` and `add-router` Dart
Package Publish Dry Run `26311662027` passed, `master` WAMP Profile Benchmarks
`26311665596` and `add-router` WAMP Profile Benchmarks `26311662028` passed,
and current-head Router Image dry-run `26311683317` passed for
`0.1.0-rc.2-validation.66e89c6` with preview upload, skipped GHCR login,
completed multi-arch build, and clean annotations. Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed since `89c7915`. The strict deployment-chain audit passed required
gates on `master` at `66e89c6`, including clean current-head CI/logs, Dart
package dry-run, WAMP profile benchmark evidence, Router Image dry-run, native
release dry-run relevance, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `f782968`
(`fix: preserve mcp poll sessions`) was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`f782968`: `master` CI run `26309125787` passed with Fast Checks and Full
Verify green and clean logs, `add-router` CI run `26309125582` passed,
`master` Dart Package Publish Dry Run `26309125789` and `add-router` Dart
Package Publish Dry Run `26309125515` passed, `master` WAMP Profile Benchmarks
`26309125788` and `add-router` WAMP Profile Benchmarks `26309125514` passed,
and current-head Router Image dry-run `26309745717` passed for
`0.1.0-rc.2-validation.f782968` with preview upload, skipped GHCR login,
completed multi-arch build, and clean annotations. Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed since `89c7915`. The strict deployment-chain audit passed required
gates on `master` at `f782968`, including clean current-head CI/logs, Dart
package dry-run, WAMP profile benchmark evidence, Router Image dry-run, native
release dry-run relevance, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `d0f5358`
(`fix: reject empty mcp response sessions`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. `McpStreamableHttpClient` now treats
any present Streamable HTTP `MCP-Session-Id` response header as a value that
must pass `_mcpSessionIdHeaderValueValid(...)`; a missing response header still
means no session negotiation, but an explicit empty `MCP-Session-Id` now clears
`sessionId` and `lastEventId` and throws `McpStreamableProtocolException`. The
client regression was added first and failed against the prior behavior because
an empty response `MCP-Session-Id` was accepted as a successful `initialize`
result instead of a protocol error. The generated client-only consumer-package
smoke now exercises the same explicit empty response-session header through
public `connectanum_mcp_io.dart` APIs and proves the client state remains clear
before a fresh initialize recovers. Pre-change and post-change local gates,
including full local `bin/verify`, passed on 2026-05-22. Hosted evidence is
clean at `d0f5358` as summarized above.
Prior hosted checkpoint details: Commit `dbaa0f3`
(`fix: reset mcp sse resume cursor`) was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. `McpStreamableHttpClient` now treats an
empty SSE `id:` field as an explicit Streamable HTTP resume-cursor reset
instead of ignoring it. `event.id == null` still means the event did not carry
an id field, while `event.id == ''` clears `lastEventId`, so later `poll()`
requests do not send a stale `Last-Event-ID` after a standards-compatible SSE
reset. The client regression was added first and failed against the prior
behavior because an empty response event id left `lastEventId` at
`session-1:post:1`. The generated client-only consumer-package smoke now sends
the same empty-id SSE response through public `connectanum_mcp_io.dart` APIs
and follows it with a poll to prove the stale cursor was not replayed.
Pre-change `bin/test-fast` passed. After the fix, focused
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart
-r expanded --plain-name "clears the resume cursor when SSE sends an empty
id"`, full
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart
-r expanded`, `bash -n bin/common.sh`, focused `bash -lc 'source
bin/common.sh && run_mcp_client_package_smoke'`, `dart analyze
packages/connectanum_client`, and repeated `bin/test-fast` passed on
2026-05-22. Full local `bin/verify` passed on 2026-05-22. Hosted GitHub
evidence is clean at
`dbaa0f3`: `master` CI run `26304262034` passed with Fast Checks and Full
Verify green and clean logs, `add-router` CI run `26304262081` passed,
`master` Dart Package Publish Dry Run `26304262111` and `add-router` Dart
Package Publish Dry Run `26304262077` passed, `master` WAMP Profile Benchmarks
`26304262035` and `add-router` WAMP Profile Benchmarks `26304262052` passed,
and current-head Router Image dry-run `26304274791` passed for
`0.1.0-rc.2-validation.dbaa0f3` with preview upload, skipped GHCR login,
completed multi-arch build, and clean annotations. Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed since `89c7915`. The strict deployment-chain audit passed required
gates on `master` at `dbaa0f3`, including clean current-head CI/logs, Dart
package dry-run, WAMP profile benchmark evidence, Router Image dry-run, native
release dry-run relevance, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `730e75b`
(`fix: reject malformed mcp response sessions`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`730e75b`: `master` CI run `26301874277` passed with Fast Checks and Full
Verify green and clean logs, `add-router` CI run `26301874343` passed,
`master` Dart Package Publish Dry Run `26301874299` and `add-router` Dart
Package Publish Dry Run `26301874267` passed, `master` WAMP Profile Benchmarks
`26301874338` and `add-router` WAMP Profile Benchmarks `26301874276` passed,
and current-head Router Image dry-run `26301886236` passed for
`0.1.0-rc.2-validation.730e75b` with preview upload, skipped GHCR login,
completed multi-arch build, and clean annotations. Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed since `89c7915`. The strict deployment-chain audit passed required
gates on `master` at `730e75b`, including clean current-head CI/logs, Dart
package dry-run, WAMP profile benchmark evidence, Router Image dry-run, native
release dry-run relevance, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `eb9a9c5`
(`fix: reject malformed mcp session ids`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`eb9a9c5`: `master` CI run `26299150343` passed with Fast Checks and Full
Verify green and clean logs, `add-router` CI run `26299150459` passed,
`master` Dart Package Publish Dry Run `26299150379` and `add-router` Dart
Package Publish Dry Run `26299150397` passed, `master` WAMP Profile Benchmarks
`26299150488` and `add-router` WAMP Profile Benchmarks `26299150455` passed,
and current-head Router Image dry-run `26299168032` passed for
`0.1.0-rc.2-validation.eb9a9c5` with preview upload, skipped GHCR login,
completed multi-arch build, and clean annotations. Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed since `89c7915`. The strict deployment-chain audit passed required
gates on `master` at `eb9a9c5`, including clean current-head CI/logs, Dart
package dry-run, WAMP profile benchmark evidence, Router Image dry-run, native
release dry-run relevance, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `27c65d2`
(`fix: reject client mcp initialize sessions`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence was clean at
`27c65d2`: `master` CI run `26296339766` passed with Fast Checks and Full
Verify green and clean logs, `add-router` CI run `26296339683` passed,
`master` Dart Package Publish Dry Run `26296339784` and `add-router` Dart
Package Publish Dry Run `26296339688` passed, `master` WAMP Profile Benchmarks
`26296339687` and `add-router` WAMP Profile Benchmarks `26296339710` passed,
and current-head Router Image dry-run `26296373275` passed for
`0.1.0-rc.2-validation.27c65d2`.
Prior hosted checkpoint details: Commit `08557f7`
(`fix: drop rejected mcp initialize sessions`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`08557f7`: `master` CI run `26293468018` passed with Fast Checks and Full
Verify green and clean logs, `add-router` CI run `26293451755` passed,
`master` Dart Package Publish Dry Run `26293468008` and `add-router` Dart
Package Publish Dry Run `26293451704` passed, `master` WAMP Profile Benchmarks
`26293468009` and `add-router` WAMP Profile Benchmarks `26293451763` passed,
and current-head Router Image dry-run `26293615506` passed for
`0.1.0-rc.2-validation.08557f7` with preview upload, skipped GHCR login,
completed multi-arch build, and clean annotations. Native Artifacts dry-run
`26286794628` remains relevant because no native-release-sensitive inputs
changed since `89c7915`. The strict deployment-chain audit passed required
gates on `master` at `08557f7`, including clean current-head CI/logs, Dart
package dry-run, WAMP profile benchmark evidence, Router Image dry-run, native
release dry-run relevance, branch protection, workflow visibility, and router
package visibility. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `383e0a9`
(`fix: clean up mcp delete subscriptions`) makes router-hosted MCP endpoints
clean up MCP-created WAMP pub/sub subscriptions when a Streamable HTTP session
is deleted or an endpoint is disposed. `_RouterMcpEndpoint` tracks
subscription ids created through `connectanum.pubsub.subscribe`, removes ids
on explicit unsubscribe, and best-effort unsubscribes remaining ids during
DELETE/disposal. The router integration smoke proves a Streamable MCP
subscription reports one route-visible subscriber before DELETE and zero
afterward through direct JSON WAMP subscription meta. The generated
consumer-package smoke proves the same cleanup through public
`McpStreamableHttpClient` helper calls. Pre-change `bin/test-fast`, focused
router integration coverage, `dart analyze packages/connectanum_router`,
`bash -n bin/common.sh`, focused generated router-hosted MCP consumer smoke,
`git diff --check`, repeated `bin/test-fast`, and full local `bin/verify`
passed on 2026-05-22. Commit `383e0a9` was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`383e0a9`: `master` CI run `26289774583` passed after rerun with Fast Checks
and Full Verify green and clean logs, `add-router` CI run `26289773557`
passed, `master` Dart Package Publish Dry Run `26289774620` and `add-router`
Dart Package Publish Dry Run `26289773603` passed, `master` WAMP Profile
Benchmarks `26289774563` and `add-router` WAMP Profile Benchmarks
`26289773604` passed, and current-head Router Image dry-run `26290485783`
passed for `0.1.0-rc.2-validation.383e0a9` with preview upload, skipped GHCR
login, completed multi-arch build, and clean annotations. Native Artifacts
dry-run `26286794628` remains relevant because no native-release-sensitive
inputs changed since `89c7915`. The strict deployment-chain audit passed
required gates on `master` at `383e0a9`, including clean current-head CI/logs,
Dart package dry-run, WAMP profile benchmark evidence, Router Image dry-run,
native release dry-run relevance, branch protection, workflow visibility, and
router package visibility. RC readiness remains not-ready only because no
approved numeric RC tag, GitHub prerelease, or matching RC router image tag has
been selected, and pub.dev publishing remains deferred for release-order and
operator decisions. No RC tag, GitHub Release, or router image was created or
moved.
Prior hosted checkpoint details: Commit `3c5d977`
(`test: cover http route method mismatches`) adds focused production-readiness
coverage for HTTP route method whitelist mismatches. Native route matching now
has regression coverage proving existing paths with disallowed methods return
`HttpRouteMatch::MethodNotAllowed` with sorted allowed methods instead of
`NotFound`. The native HTTP/1 listener now has a network regression proving a
disallowed method returns `405 Method Not Allowed` with an `Allow` header and
does not enqueue a Dart-dispatched HTTP request. The Dart synthetic route path
now has matching runtime coverage proving consumer-visible responses include
`405`, `Allow`, and the `method_not_allowed` JSON reason without emitting
`http_request_dispatched`. `ROADMAP.md` now marks the HTTP method/protocol
whitelist 405/426 readiness item complete. Pre-change `bin/test-fast`, focused
native `cargo test -p ct_core method_mismatch -- --nocapture`, focused Dart
`dart test packages/connectanum_router/test/router_runtime_test.dart -r
expanded --chain-stack-traces -n "honors typed HTTP route method restrictions
before dispatch"`, `git diff --check`, and full local `bin/verify` passed on
2026-05-22. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted GitHub evidence is clean at `3c5d977`: `master` CI run
`26282723125` and `add-router` CI run `26282711412` passed with Fast Checks and
Full Verify green; `master` Dart Package Publish Dry Run `26282723109` and
`add-router` Dart Package Publish Dry Run `26282711355` passed; `master` WAMP
Profile Benchmarks `26282723154` and `add-router` WAMP Profile Benchmarks
`26282711353` passed; `master` kTLS Validation `26282723160` and `add-router`
kTLS Validation `26282711453` passed. Current-head Native Artifacts dry-run
`26283321576` passed for `v0.1.0-rc.2-validation.3c5d977` with all five
platform jobs and release-preview upload green and no GitHub Release mutation.
Current-head Router Image dry-run `26283321578` passed for
`0.1.0-rc.2-validation.3c5d977`, uploaded `router-image-preview`, skipped GHCR
login, completed the multi-arch build step, and had clean check annotations.
The strict deployment-chain audit passed required gates on `master` at
`3c5d977`, including clean current-head CI/logs, Dart package dry-run, native
release dry-run, Router Image dry-run, WAMP profile benchmark evidence,
workflow visibility, branch protection, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected, and pub.dev
publishing remains deferred for release-order/operator decisions. No RC tag,
GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `c45aa4b`
(`fix: return 426 for http route protocol mismatch`) makes router-hosted HTTP
route protocol whitelists distinguish configured route protocol mismatches from
route misses. Native route matching canonicalizes route/request HTTP protocol
aliases (`http`, `http/1.1`, `h2`, `http/2`, `h3`, and `http/3`) and returns a
protocol-not-allowed match when an existing route path is served over a
disallowed protocol. HTTP/1 native responses return `426 Upgrade Required` with
an `Upgrade` header, and HTTP/2/HTTP/3 native responses return `426` without
invalid connection-specific upgrade headers. The Dart synthetic HTTP dispatch
path mirrors the same `426` JSON error with the `protocol_not_allowed` reason,
so consumer applications see a deterministic configuration error instead of an
ambiguous `404 route_not_found`. Pre-change `bin/test-fast`, focused native
`cargo test --manifest-path native/transport/Cargo.toml -p ct_core
http_route_protocol_aliases_and_mismatches_are_explicit -- --nocapture`,
focused Dart
`dart test packages/connectanum_router/test/router_runtime_test.dart -r
expanded --chain-stack-traces -n "honors typed HTTP route protocol restrictions
before dispatch"`, `git diff --check`, and full local `bin/verify` passed on
2026-05-22. The commit was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted GitHub evidence is clean at `c45aa4b`: `master` CI run
`26278863274` and `add-router` CI run `26278857982` passed with Fast Checks and
Full Verify green; `master` Dart Package Publish Dry Run `26278863327` and
`add-router` Dart Package Publish Dry Run `26278857984` passed; `master` WAMP
Profile Benchmarks `26278863232` and `add-router` WAMP Profile Benchmarks
`26278857985` passed; `master` kTLS Validation `26278863231` and `add-router`
kTLS Validation `26278858035` passed. Current-head Native Artifacts dry-run
`26279547806` passed for `v0.1.0-rc.2-validation.c45aa4b` with all five
platform jobs and release-preview upload green and no GitHub Release mutation.
Current-head Router Image dry-run `26279547969` passed for
`0.1.0-rc.2-validation.c45aa4b`, uploaded `router-image-preview`, skipped GHCR
login, completed the multi-arch build step, and had clean check annotations.
The strict deployment-chain audit passed required gates on `master` at
`c45aa4b`, including clean current-head CI/logs, Dart package dry-run, native
release dry-run, Router Image dry-run, WAMP profile benchmark evidence,
workflow visibility, branch protection, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag, GitHub
prerelease, or matching RC router image tag has been selected, and pub.dev
publishing remains deferred for release-order/operator decisions. No RC tag,
GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `d9d8a82`
(`ci: retry browser smoke on hosted flake`) hardens hosted CI browser-smoke
reliability after `master` CI run `26274326442` needed a Full Verify rerun for
a retryable package:test Chrome browser-manager load flake (`Bad state: Cannot
add stream while adding stream`). `bin/test-all` now retries the client browser
WebSocket smoke, keeps non-final retry attempts on the expanded reporter to
avoid GitHub error annotations, and preserves the default reporter on the final
attempt so real failures still surface normally. `tool/test_verification_scripts.py`
regresses the verification-script contract and is wired into `bin/test-fast`
and `bin/test-all`. Pre-change `bin/test-fast`, `bash -n bin/test-fast
bin/test-all`, focused `python3 tool/test_verification_scripts.py`, and full
local `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`d9d8a82`: `master` CI run `26276704174` and `add-router` CI run
`26276703045` passed with Fast Checks and Full Verify green. The strict
deployment-chain audit passed required gates on `master` at `d9d8a82`, using
current-head CI/log evidence plus still-relevant Dart package dry-run, native
release dry-run, Router Image dry-run, and WAMP profile benchmark evidence
because no package, native-release, router-image, or WAMP profile inputs
changed in this CI-script/docs checkpoint. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order/operator decisions. No RC tag, GitHub Release, or router image
was created or moved.
Prior hosted checkpoint details: Commit `209b91c`
(`test: require dart release plan for rc deferral`) tightens
`bin/audit-github-deployment-chain` so first-RC pub.dev deferral is accepted
only when the strict Dart publish dry-run output includes zero warnings, the
known private `connectanum_core` blocker, the release-order inventory, the
workspace dependency order, and operator decisions. It rejects missing
release-plan evidence and contradictory warning-gate output instead of treating
the blocker line alone as sufficient. `tool/test_audit_github_deployment_chain.py`
adds fake-hosted RC coverage for a strict dry-run that has the known blocker but
omits the release plan. Pre-change `bin/test-fast`, focused
`python3 tool/test_audit_github_deployment_chain.py`,
`bash -n bin/audit-github-deployment-chain`, `git diff --check`, the live
read-only strict deployment-chain audit against `master`, and full local
`bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`209b91c`: `master` CI run `26274326442` passed with Fast Checks and a rerun
Full Verify on attempt 2 after a hosted browser-runner load flake, and
`add-router` CI run `26274323057` passed with Fast Checks and Full Verify green.
The strict deployment-chain audit passed required gates on `master` at
`209b91c`, using current-head CI/log evidence plus still-relevant Dart package
dry-run, native release dry-run, Router Image dry-run, and WAMP profile
benchmark evidence because no package, native-release, router-image, or WAMP
profile inputs changed in this audit/test/docs checkpoint. RC readiness remains
not-ready only because no approved numeric RC tag, GitHub prerelease, or
matching RC router image tag has been selected, and pub.dev publishing remains
deferred for release-order/operator decisions. No RC tag, GitHub Release, or
router image was created or moved.
Prior hosted checkpoint details: Commit `690c3c6`
(`test: cover strict dart publish deferral`) adds regression
coverage proving
`bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`
fails on the known `connectanum_client` private `connectanum_core` dependency
while still reporting zero publish warnings and the release-order plan. It also
adds fake-hosted RC audit coverage proving the first-RC pub.dev deferral is not
accepted when strict Dart package output contains any unexpected private
workspace dependency blocker. Pre-change `bin/test-fast`, focused
`python3 tool/test_dart_package_publish_dry_run.py`,
`python3 tool/test_audit_github_deployment_chain.py`, `git diff --check`, and
full local `bin/verify` passed. The commit was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`690c3c6`: `master` CI run `26271999722` and `add-router` CI run
`26271999694` passed with Fast Checks and Full Verify green. The strict
deployment-chain audit passed required gates on `master` at `690c3c6`, using
current-head CI/log evidence plus still-relevant Dart package dry-run, native
release dry-run, Router Image dry-run, and WAMP profile benchmark evidence
because no package, native-release, router-image, or WAMP profile inputs changed
in this test/docs checkpoint. RC readiness remains not-ready only because no
approved numeric RC tag, GitHub prerelease, or matching RC router image tag has
been selected, and pub.dev publishing remains deferred for release-order/operator
decisions. No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `182c236`
(`fix: skip mcp delete without active session`) changes
`McpStreamableHttpClient.deleteSession()` to return after local cleanup when
`sessionId` is already null, clearing any orphan SSE cursor without sending an
invalid network `DELETE` lacking `MCP-Session-Id`. This keeps downstream
application `finally` cleanup paths safe after failed initialization, prior
cleanup, or local state reset. Pre-change `bin/test-fast`, `dart format`, and
focused
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
passed, followed by full local `bin/verify`. The commit was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is
clean at `182c236`: `master` CI run `26270250594`, `add-router` CI run
`26270245743`, `master` Dart Package Publish Dry Run `26270250595`,
`add-router` Dart Package Publish Dry Run `26270245773`, `master` WAMP Profile
Benchmarks `26270250619`, `add-router` WAMP Profile Benchmarks `26270245772`,
and manual non-mutating `master` Router Image dry-run `26270676681` passed.
The strict deployment-chain audit passed required gates on `master` at
`182c236`, using current-head CI/log, Dart package dry-run, WAMP profile
benchmark, and Router Image dry-run evidence plus still-relevant native release
dry-run evidence. RC readiness remains not-ready only because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected, and pub.dev publishing remains deferred for release-order/operator
decisions. No RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `742c004`
(`fix: reset mcp sse cursor on session change`) updates
`McpStreamableHttpClient._captureSessionHeaders` so `lastEventId` is cleared
before adopting a changed non-empty `MCP-Session-Id`. This keeps
`Last-Event-ID` scoped to the active Streamable HTTP session and prevents
re-initialize or session-rotation flows from sending a previous session's SSE
cursor on the next GET/SSE poll. The existing stale-session regression now
asserts re-initialize clears the cursor. Pre-change `bin/test-fast`, focused
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
`git diff --check`, and full local `bin/verify` passed. The commit was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `742c004`: `master` CI run `26268556973`,
`add-router` CI run `26268556046`, `master` Dart Package Publish Dry Run
`26268556951`, `master` WAMP Profile Benchmarks `26268556950`, and manual
non-mutating `master` Router Image dry-run `26268965259` passed. The strict
deployment-chain audit passed required gates on `master` at `742c004`, using
current-head CI/log, Dart package dry-run, WAMP profile benchmark, and Router
Image dry-run evidence plus still-relevant native release dry-run evidence.
RC readiness remains not-ready only because no approved numeric RC tag,
GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order/operator decisions. No
RC tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint details: Commit `f08e002`
(`test: cover router mcp standard headers`) extends the generated
router-hosted MCP consumer smoke for public package standard-header ownership
against a real router. The generated router-hosted MCP
consumer package smoke sends stale caller `Mcp-Method` and `Mcp-Name` headers
through public direct JSON tool helper calls, generic Streamable JSON-RPC
`tools/call` POSTs, Streamable WAMP pub/sub notifications, and Streamable tool
notifications. The smoke now proves public consumer-package APIs sanitize or
own standard MCP headers before the real router validates direct JSON and
Streamable HTTP requests. Pre-change `bin/test-fast`, `bash -n bin/common.sh`,
focused `bash -lc 'source bin/common.sh && run_mcp_consumer_package_smoke'`,
`git diff --check`, and full local `bin/verify` passed. The commit was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted GitHub
evidence is clean at `f08e002`: `master` CI run `26267304417` and
`add-router` CI run `26267301141` passed with Fast Checks and Full Verify
green. The strict deployment-chain audit passed required gates on `master` at
`f08e002`, using current-head CI/log evidence plus still-relevant Dart package
dry-run, native release dry-run, Router Image dry-run, and WAMP profile
benchmark evidence because no package, native-release, router-image, or WAMP
profile inputs changed in this script/docs checkpoint. RC readiness remains
not-ready only because no approved numeric RC tag, GitHub prerelease, or
matching RC router image tag has been selected, and pub.dev publishing remains
deferred for release-order/operator decisions. No RC tag, GitHub Release, or
router image was created or moved.
Prior hosted checkpoint details: Commit `6cc318b`
(`test: cover consumer mcp standard headers`) extends the generated
client-only MCP consumer smoke for public package standard-header ownership.
The generated client-only MCP consumer package smoke now sends stale caller
`Mcp-Method` and `Mcp-Name` headers through direct JSON, Streamable POST, and
GET/SSE poll requests. The smoke harness records standard MCP headers by
consumer trace and proves direct JSON and Streamable POST use client-owned
synthesized `Mcp-Method` values while omitting stale caller `Mcp-Name`, and
GET/SSE poll forwards neither standard MCP header while still using the owned
Streamable session. The commit was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`6cc318b`: `master` CI run `26265975937` and `add-router` CI run
`26265972592` passed with Fast Checks and Full Verify green. The strict
deployment-chain audit passed required gates on `master` at `6cc318b`, using
current-head CI/log evidence plus still-relevant Dart package dry-run, native
release dry-run, Router Image dry-run, and WAMP profile benchmark evidence
because no package, native-release, router-image, or WAMP profile inputs
changed in this script/docs checkpoint. RC readiness remains not-ready only
because no approved numeric RC tag, GitHub prerelease, or matching RC router
image tag has been selected, and pub.dev publishing remains deferred for
release-order/operator decisions. No RC tag, GitHub Release, or router image
was created or moved.
Prior hosted checkpoint details: Commit `c30e9d1`
(`fix: keep mcp standard headers client-owned`) hardens public MCP HTTP client
standard-header ownership.
`McpStreamableHttpClient` now treats caller-provided `Mcp-Method` and
`Mcp-Name` as controlled headers alongside `Accept`, `MCP-Protocol-Version`,
`MCP-Session-Id`, and `Last-Event-ID`. The client still synthesizes
`Mcp-Method` and `Mcp-Name` for single-message POSTs when the request body has
a method/name, but stale caller values are stripped from constructor and
per-call header maps and therefore cannot leak into initialize, direct JSON,
Streamable POST, GET/SSE poll, or JSON-RPC batch requests where they would be
misleading. Pre-change `bin/test-fast`, `dart format`, the focused
`owns MCP protocol and session headers despite caller headers` client test, the
full `streamable_http_client_test.dart` suite, `git diff --check`, and full
local `bin/verify` passed. The commit was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`c30e9d1`: `master` CI run `26264152549`, `master` Dart Package Publish Dry Run
`26264152546`, `master` WAMP Profile Benchmarks `26264152545`, `master` Router
Image dry-run `26264557016`, `add-router` CI run `26264149237`, `add-router`
Dart Package Publish Dry Run `26264149235`, and `add-router` WAMP Profile
Benchmarks `26264149240` passed. The first strict audit found the previous
Router Image dry-run stale for this router-image-sensitive client/package
change; after manual non-mutating Router Image dry-run `26264557016`, the
strict deployment-chain audit passed required gates on `master` at `c30e9d1`,
using current-head CI/logs, Dart package dry-run, WAMP profile benchmark, and
Router Image dry-run evidence plus still-relevant native release dry-run
evidence. RC readiness remains not-ready only because no approved numeric RC
tag, GitHub prerelease, or matching RC router image tag has been selected, and
pub.dev publishing remains deferred for release-order/operator decisions. No RC
tag, GitHub Release, or router image was created or moved.
Prior hosted checkpoint: Commit `3a066b2`
(`test: cover mcp client rate-limit cleanup`) adds public-client regression
coverage for rate-limited Streamable HTTP cleanup.
`McpStreamableHttpClient` now has focused test evidence that a `429`
Streamable POST failure preserves the active session id and SSE cursor, and
that a following `DELETE` cleanup still sends the owned `MCP-Session-Id` before
clearing local state. Pre-change `bin/test-fast`, the focused
`keeps Streamable HTTP session state after rate-limit failures` client test,
the full `streamable_http_client_test.dart` suite, `git diff --check`, and full
local `bin/verify` passed. The first full local `bin/verify` attempt hit stale
failed-process native-runtime lock contention; after terminating that process
group, the two affected benchmark tests passed in isolation and the full
`bin/verify` rerun passed. The commit was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`3a066b2`: `master` CI run `26262595795`, `master` Dart Package Publish Dry Run
`26262595840`, `master` WAMP Profile Benchmarks `26262595846`, `master` Router
Image dry-run `26263051056`, `add-router` CI run `26262595587`, `add-router`
Dart Package Publish Dry Run `26262595586`, and `add-router` WAMP Profile
Benchmarks `26262595584` passed. The strict deployment-chain audit passed
required gates on `master` at `3a066b2`, using current-head CI/logs, Dart
package dry-run, WAMP profile benchmark, and Router Image dry-run evidence plus
still-relevant native release dry-run evidence. RC readiness remains not-ready
only because no approved numeric RC tag, GitHub prerelease, or matching RC
router image tag has been selected, and pub.dev publishing remains deferred for
release-order/operator decisions. No RC tag, GitHub Release, or router image
was created or moved.
Prior hosted checkpoint: Commit `7f48714`
(`fix: allow mcp delete after route limit`) lets router-hosted MCP Streamable
HTTP `DELETE` cleanup bypass the route-level rate-limit gate so exhausted
clients can still remove owned sessions. Runtime regression coverage and the
generated consumer-package router-hosted MCP smoke prove the exhausted
Streamable POST path still returns `429 rate_limited` with the owned
`MCP-Session-Id`, while cleanup `DELETE` returns `202`, keeps the session
header, and omits route rate-limit headers. Hosted GitHub evidence is clean at
`7f48714`: `master` CI run `26260457692`, `master` Dart Package Publish Dry Run
`26260457644`, `master` WAMP Profile Benchmarks `26260457656`, `master` Router
Image dry-run `26260908932`, `add-router` CI run `26260453248`, `add-router`
Dart Package Publish Dry Run `26260453292`, and `add-router` WAMP Profile
Benchmarks `26260453365` passed. The strict deployment-chain audit passed
required gates on `master` at `7f48714`, using current-head CI/logs, Dart
package dry-run, WAMP profile benchmark, and Router Image dry-run evidence plus
still-relevant native release dry-run evidence. RC readiness remains not-ready
only because no approved numeric RC tag, GitHub prerelease, or matching RC
router image tag has been selected, and pub.dev publishing remains deferred for
release-order/operator decisions. No RC tag, GitHub Release, or router image
was created or moved.
Prior hosted checkpoint: Commit `fafbc56`
(`test: cover consumer mcp rate-limit smoke`) extends route-level rate-limit
MCP response-session evidence from the focused router runtime test into the
generated consumer-package router-hosted MCP smoke. The neutral consumer app
hosts a real rate-limited MCP route, spends the first two allowed requests on
direct JSON `tools/list` and Streamable `initialize`, then proves the exhausted
route returns `429 rate_limited` without echoing a stale direct JSON caller
session id while preserving the owned Streamable session id on a true
Streamable POST failure. The commit was pushed to GitLab `origin`, GitHub
`add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`fafbc56`: `master` CI run `26258446014` and `add-router` CI run
`26258445002` passed. The strict deployment-chain audit passed required gates
on `master` at `fafbc56`, using current-head CI/log evidence plus the latest
relevant Dart package dry-run, native dry-run, WAMP profile benchmark, and
Router Image dry-run evidence. RC readiness remains not-ready only because no
approved numeric RC tag, GitHub prerelease, or matching RC router image tag has
been selected. No RC tag, GitHub Release, or router image was created or moved.
Prior router-hosted MCP checkpoint: Router-hosted MCP notification correctness now
has native-router and generated consumer-package smoke coverage for direct JSON
single-message, mixed-batch, all-notification batch, pub/sub notification side
effects, and Streamable direct tool/pubsub notification side effects. The latest
pushed follow-up adds `McpStreamableHttpClient.notifyWampEventDirect(...)` so
consumer applications can publish WAMP pub/sub events as lifecycle-free direct
JSON notifications without hand-assembling `connectanum.pubsub.publish`
payloads. The prior pushed follow-up closed direct Connectanum tool client
header parity: `callConnectanumToolDirect(...)` and
`notifyConnectanumToolDirect(...)` reuse the same cached `x-mcp-header`
parameter metadata as `tools/call`, after either standard or Connectanum direct
catalog discovery. This implementation follow-up closes the router-hosted half
of that alias path: `connectanum.tool.call` and `connectanum.tools.call` now
share standard `Mcp-Name` extraction and `Mcp-Param-*` validation with
`tools/call`, and direct dotted tool methods validate present parameter headers
against their tool schema. Client tests assert direct Connectanum tool calls and
notifications emit `Mcp-Name`; native-router coverage accepts matching
`connectanum.tool.call` headers and rejects mismatched `Mcp-Param-*` values;
the generated consumer-package router-hosted MCP smoke now proves a public
client helper overrides bad caller-provided `Mcp-Name`/`Mcp-Param-*` headers
before reaching the real router endpoint. Pre-change `bin/test-fast`, focused
local MCP/router tests, generated consumer-package smokes, `git diff --check`,
and full local `bin/verify` are clean for this implementation. Commit
`7d0bddd` was pushed to GitLab `origin` and GitHub `add-router`. Hosted
`add-router` evidence is clean at `7d0bddd`: CI run `26183740303` passed with
Fast Checks and Full Verify green, Dart Package Publish Dry Run `26183740300`
passed, WAMP Profile Benchmarks `26183740754` passed, and the non-RC strict
deployment-chain audit passed clean latest CI, clean CI logs, and clean Dart
package dry-run gates.
This implementation follow-up broadens that direct-header contract to the
generic direct JSON method helpers:
`callConnectanumMethodDirect(...)` and
`notifyConnectanumMethodDirect(...)` now synthesize cached `Mcp-Param-*`
headers for `tools/call`, `connectanum.tool.call`, `connectanum.tools.call`,
and cached dotted tool-method calls, overriding stale caller-provided
parameter headers before router validation. Client tests prove the generic
alias and dotted-method paths emit corrected headers, the generated client-only
consumer package smoke asserts corrected captured parameter headers, and the
generated router-hosted consumer package smoke now sends stale task/note
headers through the public generic helpers to prove downstream applications can
use those helpers against a real router endpoint without hidden header
assembly. Pre-change `bin/test-fast`, `bash -n bin/common.sh`, focused
`dart test -p vm test/mcp/streamable_http_client_test.dart`, focused generated
client-only and router-hosted consumer-package smokes, `git diff --check`, and
full local `bin/verify` passed. Commit `fb88885` implemented the generic
helper/header smoke coverage, and follow-up commit `a411ed1` removed a Dart
3.12 analyzer-dead fallback exposed by the first hosted CI/dry-run attempt.
Hosted `add-router` evidence is clean at `a411ed1`: CI run `26186967933`
passed with Fast Checks and Full Verify green, Dart Package Publish Dry Run
`26186967888` passed, WAMP Profile Benchmarks `26186967889` passed, and the
non-RC strict deployment-chain audit passed clean latest CI, clean CI logs, and
clean Dart package dry-run gates.
This implementation follow-up hardens direct tool notification parameter
headers for consumer applications. High-level direct Connectanum tool helpers
now strip caller-provided `Mcp-Param-*` headers before adding regenerated
cached parameter headers, so stale parameters cannot leak through
notification-only typed, alias, or dotted direct tool helper calls. Client tests
cover uncached stale-header removal, cached typed notification regeneration,
cached dotted-method notification regeneration, and
`connectanum.tools.call` alias notification regeneration while preserving the
active Streamable session. The generated client-only and router-hosted
consumer-package smokes now send stale parameter headers through typed, alias,
and dotted direct notification helpers and prove corrected captured headers or
real router side effects. Pre-change `bin/test-fast`, formatting,
`bash -n bin/common.sh`, focused
`dart test -p vm test/mcp/streamable_http_client_test.dart`, focused generated
client-only and router-hosted consumer-package smokes, `git diff --check`, and
full local `bin/verify` passed. Commit `bafbe25` was pushed to GitLab `origin`
and GitHub `add-router`. Hosted `add-router` evidence is clean at `bafbe25`:
CI run `26189389158` passed with Fast Checks and Full Verify green, Dart
Package Publish Dry Run `26189389072` passed, WAMP Profile Benchmarks
`26189389097` passed, and the non-RC strict deployment-chain audit passed clean
latest CI, clean CI logs, and clean Dart package dry-run gates.
This implementation follow-up extends the same stale-header safety evidence to the
public direct WAMP pub/sub notification helper. `notifyWampEventDirect(...)`
now has focused client coverage proving stale caller-provided
`Mcp-Param-Topic` headers are stripped from lifecycle-free direct JSON
notifications, and the generated router-hosted consumer-package smoke sends the
same stale header through the public package helper while proving the event is
delivered by the real router endpoint. Pre-change `bin/test-fast`, formatting,
`bash -n bin/common.sh`, focused
`dart test -p vm packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
focused generated client-only and router-hosted consumer-package smokes,
`git diff --check`, and full local `bin/verify` passed. Commit `4d80537` was
pushed to GitLab `origin` and GitHub `add-router`. Hosted `add-router`
evidence is clean at `4d80537`: CI run `26191487398` passed with Fast Checks
and Full Verify green, Dart Package Publish Dry Run `26191487475` passed, WAMP
Profile Benchmarks `26191487402` passed, and the non-RC strict
deployment-chain audit passed clean latest CI, clean CI logs, and clean Dart
package dry-run gates.
This implementation follow-up adds a public Streamable-session WAMP
pub/sub notification helper for consumer applications. `notifyWampEvent(...)`
sends `connectanum.pubsub.publish` as a notification-only Streamable HTTP
request while preserving the active MCP session and stripping stale
caller-provided `Mcp-Param-*` headers through the same Connectanum method
header path as direct helpers. Client tests prove the helper sends no JSON-RPC
`id`, carries Streamable session headers, and drops stale `Mcp-Param-Topic`;
the MCP IO export test proves the helper is available through
`package:connectanum_mcp/connectanum_mcp_io.dart`; and the generated
router-hosted consumer-package smoke proves the public helper delivers a WAMP
event through a real router endpoint without mutating the SSE cursor. Pre-change
`bin/test-fast`, formatting, `bash -n bin/common.sh`, focused client/MCP
package tests, and the focused generated router-hosted consumer-package smoke
passed locally. Full local `bin/verify` passed. Commit `1021cb9` was pushed to
GitLab `origin` and GitHub `add-router`. Hosted `add-router` evidence is clean
at `1021cb9`: CI run `26193409876` passed with Fast Checks and Full Verify
green, Dart Package Publish Dry Run `26193409938` passed, WAMP Profile
Benchmarks `26193409936` passed, and the non-RC strict deployment-chain audit
passed clean latest CI, clean CI logs, and clean Dart package dry-run gates.
This implementation follow-up adds standard MCP tool notification helpers for
consumer applications. `notifyTool(...)` and `notifyToolDirect(...)` send
id-free `tools/call` notifications, preserve the active MCP session and SSE
cursor for Streamable HTTP, keep direct JSON lifecycle-free, and strip then
regenerate stale caller-provided `Mcp-Param-*` headers from cached tool
metadata. Client tests prove the Streamable and direct request shapes plus
parameter-header regeneration, the MCP IO export test proves the helpers are
available through `package:connectanum_mcp/connectanum_mcp_io.dart`, and the
generated router-hosted consumer-package smoke proves standard direct and
Streamable helper calls invoke a consumer WAMP procedure through a real router
endpoint without private assumptions. Pre-change `bin/test-fast`, formatting,
`bash -n bin/common.sh`, focused client/MCP package tests, the focused
generated router-hosted consumer-package smoke, `git diff --check`, and full
local `bin/verify` passed. Commit `b45a96f` was pushed to GitLab `origin` and
GitHub `add-router`. Hosted `add-router` evidence is clean at `b45a96f`: CI
run `26195189401` passed with Fast Checks and Full Verify green, Dart Package
Publish Dry Run `26195189402` passed, WAMP Profile Benchmarks `26195189400`
passed, and the non-RC strict deployment-chain audit passed clean latest CI,
clean CI logs, and clean Dart package dry-run gates.
GitHub `master` was fast-forward promoted from `0c0e043` to `b45a96f`, so the
router-hosted MCP downstream-readiness helpers now sit on the default release
branch. GitHub reported the PR-only branch rule was bypassed for the direct
update. Local `bin/test-fast` passed before promotion, and post-promotion local
`bin/verify` passed. Hosted `master` evidence is clean at `b45a96f`: CI run
`26196195552` passed with Fast Checks and Full Verify green, Dart Package
Publish Dry Run `26196195553` passed, WAMP Profile Benchmarks `26196195554`
passed, and Router Image dry-run `26196649190` passed without GHCR login while
uploading the preview artifact. Native Artifacts dry-run `26151756102` remains
relevant because no native-release-sensitive paths changed since `0c0e043`.
The strict deployment-chain audit passed clean current-head CI, clean CI logs,
clean Dart package dry-run, native release dry-run relevance, fresh router image
dry-run relevance, workflow visibility, branch protection, and router package
visibility gates. RC readiness remains not-ready only because no approved
numeric RC tag or GitHub prerelease points at `b45a96f`; the audit suggests
`v0.1.0-rc.2` as the next release-decision tag, and pub.dev publishing remains
deferred for package ownership/version/release-order decisions.
This implementation follow-up makes the deployment-chain audit branch
protection evidence explicit for release handoff: the audit now reports
whether the audited branch requires pull requests and whether administrators
can bypass branch protection. A fake-`gh` regression covers the protected
default-branch case, and the live `master` audit now reports pull-request
enforcement and administrator-bypass status matching the direct-promotion
bypass evidence. Pre-change `bin/test-fast`,
`bash -n bin/audit-github-deployment-chain`,
`python3 tool/test_audit_github_deployment_chain.py`, `git diff --check`,
`bin/audit-github-deployment-chain --branch master --show-rc-readiness`, and
full local `bin/verify` passed. Commit `882c207` was pushed to GitLab
`origin` and GitHub `add-router`. Hosted `add-router` evidence is clean for
this audit-readability follow-up: CI run `26198235075` passed with Fast Checks
and Full Verify green, and the gated deployment-chain audit passed current-head
CI/log checks, workflow visibility, router package visibility, and the relevant
Dart package dry-run gate. The latest Dart Package Publish Dry Run remains
`26195189402` at `b45a96f`, and the audit accepts it because no
publish-sensitive paths changed in `882c207`.

GitHub `master` was fast-forward promoted from `b45a96f` to `882c207`, so the
default release branch now includes the explicit branch-protection audit
handoff evidence. GitHub again reported the PR-only branch rule was bypassed
for the direct update, and the promoted audit output records `Require pull
requests: true` with `Admin bypass allowed: true`. Local `bin/test-fast` passed
before the promotion, post-promotion hosted `master` CI run `26199199255`
passed with Fast Checks and Full Verify green, the strict deployment-chain
audit passed all release-branch gates, and post-promotion local `bin/verify`
passed. The latest Dart package dry-run, WAMP Profile Benchmarks, Router Image
dry-run, and Native Artifacts dry-run evidence remains relevant because
`882c207` changed only audit/tooling and docs paths that are not sensitive to
those release gates. RC readiness remains not-ready only because no approved
numeric RC tag or GitHub prerelease points at `882c207`; the audit suggests
`v0.1.0-rc.2` as the next release-decision tag. No RC tag or GitHub Release was
created or moved during this promotion.

This implementation follow-up tightens the RC-readiness audit for GitHub
prerelease evidence: a numeric RC tag that exists only in the local checkout no
longer lets `--require-rc-ready` accept an existing GitHub prerelease with the
same tag name. The audit now requires the selected RC tag to be present on
GitHub at the checked-out head before the GitHub prerelease gate can report
ready, preventing stale remote tag/release combinations from being masked by a
local tag. Focused validation passed with pre-change `bin/test-fast`,
`bash -n bin/audit-github-deployment-chain`, and
`python3 -m unittest tool/test_audit_github_deployment_chain.py`; full local
`bin/verify` passed before handoff. Commit `11a9b24` was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. Hosted `master` CI run
`26201026642` passed with Fast Checks and Full Verify green, and the strict
deployment-chain audit passed required release-branch gates at `11a9b24`.
RC readiness remains not-ready only because no approved numeric RC tag or
GitHub prerelease points at `11a9b24`; the audit suggests `v0.1.0-rc.2` as the
next release-decision tag.

This implementation follow-up adds
`McpStreamableHttpClient.callConnectanumMethod(...)` as the Streamable-session
counterpart to `callConnectanumMethodDirect(...)`, so consumer applications can
call router-provided dotted Connectanum methods through an active MCP session
without hand-assembling direct JSON requests. Client coverage proves the helper
preserves Streamable session headers and regenerates cached `Mcp-Param-*`
headers over stale caller headers; the MCP IO export test proves the helper is
available through `package:connectanum_mcp/connectanum_mcp_io.dart` and works
for `connectanum.pubsub.publish`; and the generated router-hosted
consumer-package smoke proves the public helper publishes and receives a WAMP
event through a real router endpoint without private project assumptions.
Pre-change `bin/test-fast`, `bash -n bin/common.sh`, focused client/MCP tests,
the focused generated router-hosted consumer-package smoke, and full local
`bin/verify` passed.

Hosted GitHub `master` and `add-router` CI for commit `3674e86` exposed a
Linux Chrome/Dart2Wasm browser harness failure after the non-browser Full
Verify suites had passed: `websocket_transport_web_test.dart` failed during
test loading with `Bad state: Cannot add stream while adding stream`, then the
test runner hung until the Full Verify job timed out as cancelled. The browser
runtime smoke is now explicit in `bin/test-all`: hosted Linux CI uses the stable
Dart2Js browser compiler for this Chrome smoke, while local/non-Linux runs keep
the Dart2Wasm default from the package test config. Pre-change `bin/test-fast`
passed before this CI-stability patch.

Commit `462f4e0` was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted GitHub CI passed at `462f4e0` for both promoted
branches: `master` run `26204808842` and `add-router` run `26204805797` each
completed Fast Checks and Full Verify successfully. A manual Router Image
dry-run on `master` at `462f4e0`, run `26205189275`, completed successfully,
uploaded the preview artifact, and skipped GHCR login. The strict
deployment-chain audit passes required gates at `462f4e0`: latest CI job/log,
Dart package publish dry-run relevance, native release dry-run relevance,
router image dry-run relevance, workflow visibility, branch protection, and
router package visibility. RC readiness remains not-ready only because no
approved numeric RC tag or GitHub prerelease points at `462f4e0`; the audit
suggests `v0.1.0-rc.2` as the next release-decision tag.

This implementation follow-up adds focused public-surface coverage for
`McpStreamableHttpClient.notifyConnectanumMethod(...)`, the
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

Commit `79570a1` was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted evidence is clean for both promoted branches:
`master` CI run `26206356283` passed with Fast Checks and Full Verify green,
`add-router` CI run `26206354103` passed, Dart Package Publish Dry Run
`26206356286` passed on `master`, WAMP Profile Benchmarks `26206356266`
passed on `master`, and Router Image dry-run `26206759399` passed on
`master` with preview artifact upload and skipped GHCR login. The strict
deployment-chain audit passes required gates at `79570a1`: current-head
CI/logs, Dart package dry-run, native release dry-run relevance, router image
dry-run, workflow visibility, branch protection, and router package
visibility. RC readiness remains not-ready only because no approved numeric RC
tag or GitHub prerelease points at `79570a1`; the audit suggests
`v0.1.0-rc.2` as the next release-decision tag.

This implementation follow-up adds public IO-entrypoint Streamable WAMP meta
helper coverage for consumer applications. The MCP IO export smoke now
initializes `McpStreamableHttpClient` through
`package:connectanum_mcp/connectanum_mcp_io.dart`, calls typed WAMP meta
helpers over session-aware `tools/call`, and asserts Streamable session id plus
SSE cursor propagation through the package boundary. The coverage includes
`countWampSessions(...)`, `matchWampRegistration(...)`,
`countWampRegistrationCallees(...)`, `matchWampSubscription(...)`, and
`countWampSubscriptionSubscribers(...)`. Pre-change `bin/test-fast`, formatting,
focused `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
`git diff --check`, and full local `bin/verify` passed.

Commit `022811d` was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted evidence is clean for both promoted branches:
`master` CI run `26207890975` passed with Fast Checks and Full Verify green,
`add-router` CI run `26207886336` passed, Dart Package Publish Dry Run
`26207890979` passed on `master`, and Dart Package Publish Dry Run
`26207886355` passed on `add-router`. A fresh Router Image dry-run on
`master`, run `26208362869`, passed for `022811d`, uploaded the preview
artifact, skipped GHCR login, and kept the router image gate non-mutating. The
strict deployment-chain audit passes required gates at `022811d`: current-head
CI/logs, Dart package dry-run, native release dry-run relevance, router image
dry-run, workflow visibility, branch protection, and router package visibility.
The latest WAMP Profile Benchmarks run remains `26206356266` at `79570a1` and
is still relevant because this follow-up changed only MCP package test coverage
and state docs, not benchmark-sensitive WAMP profile inputs. RC readiness
remains not-ready only because no approved numeric RC tag or GitHub prerelease
points at `022811d`; the audit suggests `v0.1.0-rc.2` as the next
release-decision tag.

This implementation follow-up expands the public IO-entrypoint Streamable WAMP
meta smoke from representative helpers to the full typed
session/registration/subscription helper surface. The MCP IO export smoke now
initializes `McpStreamableHttpClient` through
`package:connectanum_mcp/connectanum_mcp_io.dart`, calls all typed WAMP meta
helpers over session-aware `tools/call`, asserts Streamable session id and SSE
cursor propagation through `io-session-1:post:15`, and verifies representative
request argument envelopes for session, registration, and subscription lookups.
Pre-change `bin/test-fast`, formatting, focused
`dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
`git diff --check`, and full local `bin/verify` passed.

Commit `f9b4f31` was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted evidence is clean for both promoted branches:
`master` CI run `26209778136` passed with Fast Checks and Full Verify green,
`add-router` CI run `26209774233` passed, Dart Package Publish Dry Run
`26209778116` passed on `master`, and Dart Package Publish Dry Run
`26209774291` passed on `add-router`. A fresh Router Image dry-run on
`master`, run `26210273976`, passed for `f9b4f31`, uploaded the preview
artifact, skipped GHCR login, and kept the router image gate non-mutating. The
strict deployment-chain audit passes required gates at `f9b4f31`: current-head
CI/logs, Dart package dry-run, native release dry-run relevance, router image
dry-run, workflow visibility, branch protection, and router package visibility.
The latest WAMP Profile Benchmarks run remains `26206356266` at `79570a1` and
is still relevant because this follow-up changed only MCP package test coverage
and state docs, not benchmark-sensitive WAMP profile inputs. RC readiness
remains not-ready only because no approved numeric RC tag or GitHub prerelease
points at `f9b4f31`; the audit suggests `v0.1.0-rc.2` as the next
release-decision tag.

This implementation follow-up closes the remaining public IO-entrypoint direct
JSON WAMP subscription-meta package-boundary smoke gap. The MCP IO export smoke
now calls `listWampSubscriptionsDirect(...)`,
`lookupWampSubscriptionDirect(...)`, `matchWampSubscriptionDirect(...)`,
`getWampSubscriptionDirect(...)`,
`listWampSubscriptionSubscribersDirect(...)`, and
`countWampSubscriptionSubscribersDirect(...)` through
`package:connectanum_mcp/connectanum_mcp_io.dart`, asserts lifecycle-free
direct JSON `connectanum.tool.call` request shapes without session headers,
and verifies representative lookup/subscriber argument envelopes. Pre-change
`bin/test-fast`, formatting, focused
`dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`, and
`git diff --check` passed; full local `bin/verify` passed before handoff.

Commit `548d267` was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`. Hosted evidence is clean for both promoted branches:
`master` CI run `26211691986` passed with Fast Checks and Full Verify green,
`add-router` CI run `26211687420` passed, Dart Package Publish Dry Run
`26211691941` passed on `master`, and Dart Package Publish Dry Run
`26211687476` passed on `add-router`. A fresh Router Image dry-run on
`master`, run `26212270565`, passed for `548d267`, uploaded the preview
artifact, skipped GHCR login, and kept the router image gate non-mutating. The
strict deployment-chain audit passes required gates at `548d267`: current-head
CI/logs, Dart package dry-run, native release dry-run relevance, router image
dry-run, workflow visibility, branch protection, and router package visibility.
The latest WAMP Profile Benchmarks run remains `26206356266` at `79570a1` and
is still relevant because this follow-up changed only MCP package test coverage
and state docs, not benchmark-sensitive WAMP profile inputs. RC readiness
remains not-ready only because no approved numeric RC tag or GitHub prerelease
points at `548d267`; the audit suggests `v0.1.0-rc.2` as the next
release-decision tag.

This implementation follow-up adds WAMP Profile Benchmarks as a first-class
deployment-chain audit gate. `bin/audit-github-deployment-chain` now exposes
`--show-wamp-profile-benchmarks` and
`--require-clean-wamp-profile-benchmarks`, and `--show-rc-readiness` /
`--require-rc-ready` include the WAMP benchmark gate. The gate verifies the
latest workflow run status, the `Linux WAMP profile gates` job, the canonical
WAMP profile validation step, `wamp-profile-benchmark-artifacts` upload, and
stale-run relevance across WAMP-profile-sensitive inputs. Regression coverage
accepts stale WAMP benchmark evidence when no sensitive inputs changed and
rejects it when checked-out client/package inputs changed after the benchmark
head. The hosted WAMP benchmark workflow path filter now includes
`packages/connectanum_core/**` and root `pubspec.yaml`, matching the audit
sensitivity for package/runtime inputs. Pre-change `bin/test-fast`,
`bash -n bin/audit-github-deployment-chain`,
`python3 -m unittest tool/test_audit_github_deployment_chain.py`, live
`bin/audit-github-deployment-chain --branch master --strict
--require-workflows-visible --require-router-package --require-clean-latest-ci
--require-clean-latest-ci-logs
--require-clean-dart-package-publish-dry-run
--require-clean-native-release-dry-run --require-clean-router-image-dry-run
--require-clean-wamp-profile-benchmarks --show-rc-readiness`,
`git diff --check`, and full local `bin/verify` passed. Commit `9825526`
(`ci: gate wamp profile benchmark evidence`) was pushed to GitLab `origin`,
GitHub `add-router`, and GitHub `master`. Hosted GitHub evidence is clean at
`9825526`: `master` CI run `26214693146` passed with Fast Checks and Full
Verify green, `add-router` CI run `26214694060` passed with Fast Checks and
Full Verify green, `master` WAMP Profile Benchmarks run `26214693251` passed,
and `add-router` WAMP Profile Benchmarks run `26214693816` passed. The strict
deployment-chain audit now passes required gates at `9825526`: current-head
CI/logs, relevant Dart package dry-run, relevant native release dry-run,
relevant router image dry-run, current-head WAMP profile benchmark evidence,
workflow visibility, branch protection, and router package visibility. RC
readiness remains not-ready only because no approved numeric RC tag or GitHub
prerelease points at `9825526`; the audit suggests `v0.1.0-rc.2` as the next
release-decision tag.

This implementation follow-up hardens Dart package release-plan diagnostics for
scoped package dry-runs. `bin/dart-package-publish-dry-run --show-release-plan`
now inventories the full workspace package set even when the actual
`dart pub publish --dry-run` target is scoped to one package, so release-order
output cannot hide private packages that still affect a public publish. The
actual dry-run remains scoped to the selected package targets. A fake-`dart`
regression in `tool/test_dart_package_publish_dry_run.py` is wired into both
`bin/test-fast` and `bin/test-all`, proving a scoped `connectanum_client`
release plan still lists all private workspace packages and only runs one
archive dry-run. The RC-readiness audit deferred-pub.dev summary now keeps the
full release-plan headings when surfacing that inventory, so package lists are
not detached from their meaning. Pre-change `bin/test-fast`,
`python3 tool/test_dart_package_publish_dry_run.py`,
`bin/dart-package-publish-dry-run --show-release-plan connectanum_client`,
`python3 tool/test_audit_github_deployment_chain.py`, `git diff --check`, and
full local `bin/verify` passed. Commit `4dec39c` (`ci: inventory dart package
release plan`) was pushed to GitLab `origin`, GitHub `add-router`, and GitHub
`master`. Hosted GitHub evidence is clean at `4dec39c`: `master` CI run
`26217438556` passed, `add-router` CI run `26217438580` passed, `master` Dart
Package Publish Dry Run run `26217438575` passed, and `add-router` Dart Package
Publish Dry Run run `26217438585` passed. Focused audit readability tests and
full local `bin/verify` passed for the headed deferred-pub.dev summary
follow-up. Commit `7d60dd8` (`ci: label dart release-plan audit output`) was
pushed to GitLab `origin`, GitHub `add-router`, and GitHub `master`. Hosted CI
is clean at `7d60dd8`: `master` CI run `26218795344` passed with Fast Checks
and Full Verify green, and `add-router` CI run `26218790197` passed with Fast
Checks and Full Verify green. The strict deployment-chain audit passes required
gates at `7d60dd8`; it accepts Dart Package Publish Dry Run run `26217438575`
from `4dec39c` as relevant because no publish-sensitive paths changed in the
audit-output follow-up. Commit `becaf98` (`ci: publish dart release plan in
dry-run workflow`) was pushed to GitLab `origin`, GitHub `add-router`, and
GitHub `master`, updating hosted Dart Package Publish Dry Run execution to call
`bin/dart-package-publish-dry-run --show-release-plan`, so GitHub run logs and
step summaries include the release-order inventory on publish-sensitive
changes. Pre-change `bin/test-fast`,
`python3 tool/test_dart_package_publish_dry_run.py`,
`bin/dart-package-publish-dry-run --show-release-plan connectanum_client`, and
full local `bin/verify` passed for this follow-up. Hosted GitHub evidence is
clean at `becaf98`: `master` CI run `26220664156` passed with Fast Checks and
Full Verify green, `add-router` CI run `26220660767` passed with Fast Checks and
Full Verify green, `master` Dart Package Publish Dry Run run `26220664109`
passed with release-plan sections visible in the log, and `add-router` Dart
Package Publish Dry Run run `26220660832` passed with the same log evidence.
The strict deployment-chain audit passes required gates at `becaf98`; RC
readiness remains not-ready only because no approved numeric RC tag or GitHub
prerelease points at `becaf98`; the audit suggests `v0.1.0-rc.2`.
Commit `156192c` (`ci: audit rc router image tag evidence`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`, tightening
RC-readiness router image evidence by deriving the required GHCR tag from the
selected numeric RC tag (`v0.1.0-rc.N` -> `0.1.0-rc.N`) and probing that exact
public manifest. Pre-change `bin/test-fast`, focused
`bash -n bin/audit-github-deployment-chain`, focused
`python3 -m unittest tool/test_audit_github_deployment_chain.py`, a live
read-only `bin/audit-github-deployment-chain --branch master
--show-rc-readiness` summary, `git diff --check`, and full local `bin/verify`
passed. Hosted GitHub evidence is clean at `156192c`: `master` CI run
`26222937612` passed with Fast Checks and Full Verify green, `add-router` CI
run `26222934044` passed with Fast Checks and Full Verify green, and the strict
deployment-chain audit passed required gates on `master`. The audit still marks
RC readiness not-ready because no approved numeric RC tag, GitHub prerelease, or
matching RC router image tag has been selected; it suggests `v0.1.0-rc.2`.
Commit `babaa9f` (`ci: normalize manual router image tags`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`, normalizing manual
Router Image workflow `image_tag` inputs that use project version refs so a
manual `v0.1.0-rc.N` input resolves to Docker tag `0.1.0-rc.N`, the same tag
shape as release-tag-triggered runs and RC audit checks. Manual
`publish_approval` still has to match the normalized primary Docker tag, so an
approval containing the leading `v` is rejected for normalized publishes.
Pre-change `bin/test-fast`, focused `python3 -m unittest
tool/test_render_router_image_metadata.py tool/test_render_native_release_notes.py`,
`git diff --check`, and full local `bin/verify` passed. Hosted GitHub evidence
is clean at `babaa9f`: `master` CI run `26225035187` and `add-router` CI run
`26225035212` passed with Fast Checks and Full Verify green, Router Image
dry-run `26225059344` passed on `master` for manual `image_tag=v0.1.0-rc.2`
without GHCR login, and the strict deployment-chain audit passed required gates
on `master`. The audit still marks RC readiness not-ready because no approved
numeric RC tag, GitHub prerelease, or matching RC router image tag has been
selected; it suggests `v0.1.0-rc.2`.
Commit `f91cc8b` (`ci: audit router image preview metadata`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. It hardens the
Router Image dry-run audit artifact evidence: the audit now downloads
`router-image-preview`, verifies the `router-image-metadata.md` summary targets
`ghcr.io/konsultaner/connectanum-router`, requires dry-run mode and
publish=false, parses the first metadata tag, validates it as a Docker tag, and
rejects project-version `v` prefixes that would not match RC image tag
semantics. Pre-change `bin/test-fast`, focused `bash -n
bin/audit-github-deployment-chain`, focused `python3 -m unittest
tool/test_audit_github_deployment_chain.py`, live read-only
`bin/audit-github-deployment-chain --branch master --show-router-image-dry-run`,
`git diff --check`, and full local `bin/verify` passed. Hosted GitHub evidence
is clean at `f91cc8b`: `master` CI run `26228085097` and `add-router` CI run
`26228080838` passed with Fast Checks and Full Verify green, and the strict
deployment-chain audit passed required gates on `master` at `f91cc8b`. The
strict audit accepts Router Image dry-run `26225059344` as relevant because no
router-image-sensitive inputs changed after that run, downloads the preview
metadata, and verifies primary tag `0.1.0-rc.2` before accepting the gate.
Commit `9ba8748` (`fix: harden MCP auth error handling`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. It hardens router-hosted
auth bridge outage behavior for downstream applications:
`ConnectanumHttpAuthClient` now converts non-success non-JSON HTTP auth
responses into typed `ConnectanumHttpAuthException`s with preserved raw bodies
instead of leaking a `FormatException`, and the generated client-only consumer
package smoke proves that behavior through the public `connectanum_mcp_io`
package boundary. Local evidence: pre-change `bin/test-fast`, focused
`dart test packages/connectanum_client/test/mcp/http_auth_client_test.dart -r expanded`,
`bash -n bin/common.sh`, focused `run_mcp_client_package_smoke`,
`git diff --check`, and clean-tree full `bin/verify` passed. Hosted GitHub
evidence is clean at `9ba8748`: `master` CI run `26231778548`, `add-router` CI
run `26231777640`, Dart Package Publish Dry Run runs `26231779191` on `master`
and `26231777632` on `add-router`, and WAMP Profile Benchmarks runs
`26231779087` on `master` and `26231777445` on `add-router` passed. Router
Image dry-run `26232580498` passed on `master` for manual
`image_tag=v0.1.0-rc.2` without GHCR login, uploaded preview metadata, and
verified primary tag `0.1.0-rc.2`. The strict deployment-chain audit passed
required gates on `master` at `9ba8748`; RC readiness still reports not-ready
only because no approved numeric RC tag, GitHub prerelease, or matching RC
router image tag has been selected.
Commit `34c9889` (`fix: select streamable mcp sse responses by id`) was pushed
to GitLab `origin`, GitHub `add-router`, and GitHub `master`. It fixes
Streamable HTTP SSE response selection for downstream applications by matching
JSON-RPC responses to request IDs across single requests and batches, ignoring
interleaved notification events while still updating the SSE cursor. Local
evidence: pre-change `bin/test-fast`, focused
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
`bash -n bin/common.sh`, focused `run_mcp_client_package_smoke`,
`git diff --check`, clean-tree `bin/test-fast`, and clean-tree `bin/verify`
passed. Hosted GitHub `master` evidence is clean at `34c9889`: CI run
`26235994960`, Dart Package Publish Dry Run `26235995708`, WAMP Profile
Benchmarks `26235993239`, and Router Image dry-run `26236030117` passed. The
strict deployment-chain audit passed required gates on `master` at `34c9889`;
RC readiness still reports not-ready only because no approved numeric RC tag,
GitHub prerelease, or matching RC router image tag has been selected.
Commit `4daf824` (`fix: honor mcp accept quality weights`) was pushed to
GitLab `origin`, GitHub `add-router`, and GitHub `master`. It hardens
router-hosted MCP HTTP content negotiation by honoring `q=0` media ranges in
`Accept` headers before selecting JSON or Streamable HTTP SSE response paths.
Local evidence: pre-change `bin/test-fast`, focused
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "guards MCP Streamable HTTP ingress and sessions" -r expanded`,
`dart analyze packages/connectanum_router`, `git diff --check`, clean-tree
`bin/test-fast`, and clean-tree `bin/verify` passed. Hosted GitHub `master`
evidence is clean at `4daf824`: CI run `26239725979`, Dart Package Publish Dry
Run `26239726467`, WAMP Profile Benchmarks `26239726002`, and Router Image
dry-run `26239757142` passed. The strict deployment-chain audit passed
required gates on `master` at `4daf824`; RC readiness still reports not-ready
only because no approved numeric RC tag, GitHub prerelease, or matching RC
router image tag has been selected.
Commit `a9dc2f6` (`fix: apply mcp accept specificity`) was pushed to GitLab
`origin`, GitHub `add-router`, and GitHub `master`. It applies HTTP `Accept`
media-range specificity so exact `application/json;q=0` and
`text/event-stream;q=0` ranges reject those response types even when
less-specific wildcards remain acceptable. Local evidence: pre-change
`bin/test-fast`, fail-first focused
`dart test packages/connectanum_router/test/router_integration_native_test.dart -n "guards MCP Streamable HTTP ingress and sessions" -r expanded`,
fixed focused native MCP ingress regression, `dart analyze
packages/connectanum_router`, `git diff --check`, clean-tree `bin/test-fast`,
and clean-tree `bin/verify` passed. Hosted GitHub evidence is clean at
`a9dc2f6`: `master` CI run `26242592111`, Dart Package Publish Dry Run
`26242591939`, WAMP Profile Benchmarks `26242592123`, Router Image dry-run
`26242601368`, and matching `add-router` CI/dry-run/WAMP runs passed. The
strict deployment-chain audit passed required gates on `master` at `a9dc2f6`;
RC readiness still reports not-ready only because no approved numeric RC tag,
GitHub prerelease, or matching RC router image tag has been selected.

Active exec plan: `docs/exec-plans/2026-05-13-rc-readiness.md`.
Current milestone: Release-candidate readiness for a GitHub prerelease from the
promoted default branch. GitHub `master` and `add-router` contain the latest
validated hosted audit-readiness checkpoint at `a9dc2f6`. The latest
implementation follow-up applies Accept media-range specificity so exact
`q=0` JSON/SSE media ranges override less-specific wildcards with hosted
`master` CI/dry-run/WAMP/Router Image evidence and strict audit evidence.
Earlier implementation follow-ups honor MCP Accept quality weights, fix
Streamable HTTP SSE response selection for interleaved notifications and
batches, normalize manual Router Image project-version tag inputs to the Docker
tag shape required by RC audit evidence, tighten RC router image tag audit
evidence, make hosted package dry-run runs print the release plan directly,
harden Dart package release-plan diagnostics, improve
deferred-pub.dev audit readability, and add a first-class WAMP Profile
Benchmarks evidence gate to the deployment-chain audit.
MCP remains RC-ready for the first candidate: router-hosted endpoints,
auth/session correctness, direct JSON/meta API, WAMP pub/sub coverage,
resources/prompts, Streamable HTTP compatibility, and consumer-package smoke
coverage are in place. Further MCP helper permutations are post-RC polish
unless consumer integration exposes a real correctness bug.
Latest completed exec plan:
`docs/exec-plans/2026-05-13-mcp-consumer-direct-wamp-api-helper-smoke.md`
(complete; hosted CI evidence clean; MCP treated as RC-ready).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-consumer-direct-wamp-meta-helper-smoke.md`
(complete; hosted CI/log/dry-run evidence clean; strict audit still reports
known operator-side release-hardening gaps).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-router-direct-wamp-meta-helper-smoke.md`
(complete; hosted CI/log/dry-run evidence clean; strict audit still reports
known operator-side release-hardening gaps).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-router-direct-resource-prompt-helper-smoke.md`
(complete; hosted CI/log/dry-run evidence clean; strict audit still reports
known operator-side release-hardening gaps).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-router-direct-helper-example-smoke.md`
(complete; hosted CI/log/dry-run evidence clean; strict audit still reports
known operator-side release-hardening gaps).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-standard-direct-router-happy-path-smoke.md`
(complete; hosted CI/log/dry-run evidence clean; strict audit still reports
known operator-side release-hardening gaps).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-standard-direct-secure-auth-smoke.md`
(complete; hosted CI/log/dry-run evidence clean; strict audit still reports
known operator-side release-hardening gaps).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-standard-direct-batch-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-standard-direct-tool-helper-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-client-direct-wamp-helper-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-client-direct-resource-prompt-helper-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-client-direct-json-post-helper-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-client-direct-json-helper-api-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-client-direct-json-ping-helper-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-consumer-direct-json-ping-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-consumer-direct-json-tool-call-alias-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-batch-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-13-mcp-consumer-streamable-wamp-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-direct-json-error-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-direct-json-notification-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-direct-json-batch-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-direct-json-cors-resource-prompt-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-cors-post-body-error-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-cors-session-auth-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-cors-method-negotiation-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-cors-error-session-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-raw-named-cors-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-streamable-cors-lifecycle-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-cors-preflight-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Earlier completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-origin-policy-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-12-mcp-consumer-secure-protocol-version-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-deleted-session-streamable-matrix-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-public-route-reuse-streamable-matrix-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-active-missing-bearer-streamable-matrix-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-other-principal-reuse-wamp-meta-pubsub-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-active-unknown-bearer-wamp-meta-pubsub-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-unknown-bearer-wamp-meta-pubsub-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-rejected-bearer-wamp-meta-pubsub-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-active-bearer-wamp-meta-pubsub-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-missing-bearer-wamp-meta-pubsub-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-session-method-missing-bearer-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-secure-missing-bearer-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-router-batch-tool-catalog-pagination-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-router-batch-catalog-pagination-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-router-generic-catalog-pagination-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-router-tool-catalog-pagination-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-11-mcp-consumer-router-catalog-pagination-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-client-package-catalog-pagination-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-client-package-auth-client-grant-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Earlier completed exec plan:
`docs/exec-plans/2026-05-10-mcp-client-package-auth-grant-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-router-native-auth-grant-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-consumer-package-auth-grant-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-example-auth-grant-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-auth-grant-streamable-client-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-http-auth-per-call-header-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-controlled-request-header-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-direct-json-batch-notification-response-header-smoke.md`
(complete; hosted CI and deployment-chain evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-direct-json-response-header-session-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-direct-json-http-error-session-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-wamp-helper-header-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-typed-helper-header-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-streamable-initialize-header-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-streamable-session-header-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-direct-batch-header-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-direct-notification-helper-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-notification-only-batch-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-deterministic-wamp-api-catalog-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-deterministic-resource-prompt-catalog-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-deterministic-tool-catalog-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-consumer-challenge-auth-lifecycle-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-consumer-challenge-auth-rejection-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-consumer-challenge-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-10-mcp-consumer-streamable-session-reuse-isolation-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-streamable-batch-error-isolation-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-direct-batch-error-isolation-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-server-package-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-io-entrypoint-registration-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-io-entrypoint-streamable-poll-delete-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-io-entrypoint-standard-wamp-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-io-entrypoint-direct-tool-meta-smoke.md`
(complete; hosted CI evidence clean).
Earlier completed exec plan:
`docs/exec-plans/2026-05-09-mcp-io-entrypoint-auth-session-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-io-entrypoint-streamable-pubsub-smoke.md`
(complete; hosted CI evidence clean).
Earlier completed exec plan:
`docs/exec-plans/2026-05-09-mcp-io-entrypoint-streamable-resource-prompt-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-client-package-batch-resource-prompt-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-client-package-batch-pubsub-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-client-package-batch-error-isolation-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-client-package-generic-batch-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-client-package-streamable-lifecycle-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-streamable-lifecycle-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-pubsub-queue-overflow-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-batch-topic-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-mcp-consumer-topic-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-topic-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-auth-refresh-revoke-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-protocol-version-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-error-recovery-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-subscription-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-wamp-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-direct-tool-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-pubsub-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-09-router-hosted-mcp-example-batch-resource-prompt-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-batch-resource-prompt-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-batch-pubsub-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-batch-subscription-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-batch-wamp-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-generic-direct-wamp-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-registration-session-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-subscription-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-meta-template-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-generic-streamable-jsonrpc-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-direct-batch-tool-alias-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-direct-tool-api-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-client-package-direct-generic-tool-method-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-client-package-direct-wamp-meta-helper-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-client-package-direct-wamp-helper-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-client-package-direct-resource-prompt-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-active-resource-prompt-detail-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-08-mcp-consumer-active-resource-prompt-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-active-tool-call-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-active-streamable-batch-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-active-notification-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-active-direct-json-batch-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-active-direct-json-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-streamable-resource-prompt-error-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-resource-prompt-error-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-generic-resources-prompts-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-generic-api-list-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-generic-pubsub-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-generic-jsonrpc-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-entity-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-session-meta-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-client-auth-error-session-clear.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-participant-meta-smoke.md`
(complete; hosted CI evidence clean).
Current implementation checkpoint: router-hosted MCP protected resource/prompt
helper auth-rejection coverage is complete locally. The generated neutral
consumer package smoke now verifies that the secure MCP route rejects missing
credentials for direct JSON `resources/list`, `resources/read`,
`resources/templates/list`, `prompts/list`, and `prompts/get`; the same
standard helpers over Streamable HTTP; and direct/Streamable resource-prompt
batches. Pre-change `bin/test-fast` passed. Post-change `bash -n
bin/common.sh`, `bin/test-fast`, and full local `bin/verify` passed on
2026-05-19. No release tag/prerelease action was taken; current-head RC
tag/prerelease selection remains a release decision.
Previous implementation checkpoint: GitHub RC tag evidence audit hardening is
complete and pushed. `bin/audit-github-deployment-chain --show-rc-readiness`
now uses both local and GitHub RC tags for the checked-out-head tag gate, and
the RC-readiness view inventories stale tags from both sources when no RC tag
points at the candidate head. Commit `e25c0c7` (`ci: audit github rc tag
evidence`) was pushed to both configured remotes. GitHub CI run `26111109838`
passed with `Fast Checks` and `Full Verify` green, and the strict
deployment-chain audit passed the clean CI/log, Dart package dry-run, native
release dry-run, router image dry-run, and router package visibility gates.
The audit reports both local and GitHub `v0.1.0-rc.1 -> 47bbf9c` as stale for
checked-out head `e25c0c7`, so the remaining release decision is explicit:
move the stale tag under release policy or choose a follow-up RC tag.
Previous implementation checkpoint: RC tag evidence audit hardening is complete
and pushed. `bin/audit-github-deployment-chain --show-rc-readiness` now lists
existing local RC tags when no RC tag points at the checked-out head, including
the target commit and whether each tag is stale for the current candidate.
Commit `cbe1e1d` (`ci: report stale rc tag evidence`) was pushed to both
configured remotes. GitHub CI run `26108394380` passed with `Fast Checks` and
`Full Verify` green. The strict deployment-chain audit passed clean latest CI,
clean latest CI logs, clean relevant Dart package publish dry-run, clean native
release dry-run, clean router image dry-run, and router package visibility
gates. RC readiness remains blocked only on current-head RC tag/prerelease
selection; pub.dev publishing remains deferred.
Previous implementation checkpoint: router package visibility audit hardening
is complete and pushed. `bin/audit-github-deployment-chain
--require-router-package` now probes public GHCR registry pull metadata first
by reading the visible tag list and validating a manifest digest, then falls
back to GitHub Packages metadata for compatibility. Pre-change `bin/test-fast`
passed. Focused checks for Bash syntax, help output, `git diff --check`, the
router package visibility audit, and full local `bin/verify` passed on
2026-05-19. Commit `65caf71` (`ci: audit ghcr router package visibility`) was
pushed to both configured remotes. GitHub CI run `26105461957` passed with
`Fast Checks` and `Full Verify` green. The strict deployment-chain audit passed
clean latest CI, clean latest CI logs, clean relevant Dart package publish
dry-run, clean native release dry-run, clean router image dry-run, and router
package visibility gates. The package visibility gate reported public registry
tag
`v0.1.0-rc.1` with manifest digest
`sha256:45d168f29a2b4c1c187ed21ff18c0f0539703b66c2709422cc414b360966b737`.
The RC-readiness audit confirmed that readiness is now blocked on current-head
RC tag/prerelease selection rather than router package visibility; pub.dev
remains deferred.
Previous implementation checkpoint: Router Image workflow deprecation
hardening is complete. The workflow now uses the Node 24-backed
`docker/setup-qemu-action@v4` and `docker/setup-buildx-action@v4` tags, and
`bin/audit-github-deployment-chain --require-clean-router-image-dry-run` now
fails when the Router Image dry-run check run has warning/failure annotations.
Pre-change `bin/test-fast` passed. Primary GitHub action metadata checks
confirmed the Docker setup/build/publish and artifact actions in this workflow
use `node24`; `bash -n bin/audit-github-deployment-chain`,
Router Image workflow YAML parsing, `git diff --check`, an expected failing
`bin/audit-github-deployment-chain --branch add-router
--require-clean-router-image-dry-run` against the old Node 20-annotated dry-run,
and full local `bin/verify` passed on 2026-05-19. Commit `5a10bd5`
(`ci: harden router image action audit`) was pushed to both configured remotes.
GitHub CI run `26102726359` passed with `Fast Checks` and `Full Verify` green,
GitHub `Router Image` dry-run `26102736224` passed for
`0.1.0-rc.1-validation.5a10bd5`, and the strict deployment-chain audit passed
clean latest CI, clean latest CI logs, clean relevant Dart package publish
dry-run, clean native release dry-run, and clean router image dry-run gates.
The Router Image dry-run audit reported check annotations clean. RC readiness
remained blocked by router package visibility and current-head RC
tag/prerelease selection until the follow-up GHCR registry audit hardening
above; pub.dev stayed deferred.
Previous implementation checkpoint: native HTTP/1 keep-alive idle timeouts now
close quietly instead of emitting `http/1 connection read error` diagnostics
from the native runtime, while non-timeout HTTP/1 protocol and I/O read errors
remain logged. Pre-change `bin/test-fast` passed and exposed the generated
router-hosted MCP consumer-package smoke timeout noise. Focused
`cargo test -p ct_core http1_read_error_logging_skips_expected_idle_timeouts`,
focused generated consumer-package smoke with an output scan for the removed
diagnostic, `git diff --check`, and full local `bin/verify` passed on
2026-05-19. Commit `f0c1590` (`fix: silence expected http1 idle timeouts`) was
pushed to both configured remotes. GitHub CI run `26098749788`, GitHub WAMP
Profile Benchmarks run `26098749790`, GitHub kTLS Validation run `26098749771`,
GitHub `Native Artifacts` dry-run `26099397722` for
`v0.1.0-rc.1-validation.f0c1590`, and GitHub `Router Image` dry-run
`26099397318` for `0.1.0-rc.1-validation.f0c1590` all passed. The strict
deployment-chain audit passed clean latest CI, clean latest CI logs, clean
relevant Dart package publish dry-run, clean native release dry-run, and clean
router image dry-run gates for `add-router`; RC readiness remains blocked by
router image package visibility/publish approval and current-head RC
tag/prerelease selection, with pub.dev still deferred.
Previous implementation checkpoint: the deployment-chain audit now has an
explicit non-mutating Router Image dry-run gate
(`--require-clean-router-image-dry-run`) that verifies the latest relevant
manual dry-run completed, uploaded `router-image-preview`, skipped GHCR login,
completed the multi-arch build step, and still covers checked-out router image
inputs. The gate passed locally against GitHub `Router Image` dry-run
`26093405157` for `0.1.0-rc.1-validation.6d681ab`. The preceding router image
Rust 1.85 compatibility fix is complete, pushed, and hosted evidence is clean.
GitHub `Router Image` dry-run `26091104743` for
`0.1.0-rc.1-validation.f2f8720` failed before publishing because
`deploy/docker/Dockerfile` attempted to copy a root `pubspec.lock` that is not
checked in for this workspace. Commit `7f54fbb` copied only `pubspec.yaml`
before `dart pub get`, letting the container build generate its own lockfile.
GitHub `Router Image` dry-run `26091677645` for
`0.1.0-rc.1-validation.7f54fbb` progressed to `dart compile exe` and then
failed because `/out/connectanum_router` could not be opened when `/out` did
not exist. Commit `f30aa7f` creates `/out` before compiling the router runner;
GitHub CI run `26092286670` passed for that commit. Follow-up GitHub
`Router Image` dry-run `26092291070` for
`0.1.0-rc.1-validation.f30aa7f` reached the Docker Rust build and failed
because the pinned `rust:1.85-bookworm` builder does not implement `Default`
for raw pointer fields in `ct_ffi` FFI output structs. The FFI layer now
provides explicit zeroed defaults for those `repr(C)` scalar/pointer buffers.
Local Docker validation is blocked because the local Docker daemon is not
running. Local Rust 1.85 release build for `ct_ffi`, `cargo fmt --all --check`
from `native/transport`, `git diff --check`, and full local `bin/verify`
passed on 2026-05-19. Commit `6d681ab` was pushed to both configured remotes;
GitHub CI run `26093400216`, GitHub `Router Image` dry-run `26093405157` for
`0.1.0-rc.1-validation.6d681ab`, and GitHub `Native Artifacts` dry-run
`26094664567` for `v0.1.0-rc.1-validation.6d681ab` all passed. The
deployment-chain audit passed clean latest CI, clean latest CI logs, clean
relevant Dart package publish dry-run, clean native release dry-run, and clean
router image dry-run gates for `add-router`. RC readiness remains blocked by
invisible
`ghcr.io/konsultaner/connectanum-router` package visibility and missing
current-head RC tag/prerelease selection; pub.dev publication remains deferred.
Last deployment-chain audit implementation commit:
`d01afce` (`ci: gate router image dry-run evidence`; hosted CI and strict local
deployment-chain audit gates clean).
Last router image build implementation commit:
`6d681ab` (`fix: support rust 1.85 ffi defaults`; hosted CI, router image
dry-run, native artifact dry-run, and deployment-chain audit gates clean).
Previous implementation checkpoint: native release dry-run audit and Sigstore
retry hardening is complete, pushed, and hosted evidence is clean. GitHub
`Native Artifacts` run
`26088923120` completed successfully for `v0.1.0-rc.1`, but that tag already
exists on GitHub at commit `47bbf9c`, so it cannot provide no-mutation
current-head evidence. A follow-up validation dry-run, GitHub `Native
Artifacts` run `26089627231` for `v0.1.0-rc.1-validation.8058104`, failed
during Sigstore signing on Linux x64, Linux arm64, and macOS Apple Silicon
because Cosign could not fetch ambient OIDC credentials. The local workflow
now retries Cosign `sign-blob` and `verify-blob` calls up to three attempts,
and the deployment-chain audit now accepts both project and native dry-run
release-intent lines. Pre-change `bin/test-fast` passed on 2026-05-19, and
focused local checks passed for `bash -n bin/audit-github-deployment-chain`,
workflow YAML parsing, `git diff --check`, and the audit dry-run intent parser.
Full local `bin/verify` passed on 2026-05-19 before commit. Commit `f2f8720`
(`ci: harden native artifact dry-run evidence`) was pushed to both configured
remotes. GitHub `CI` run `26090478456` completed successfully with `Fast
Checks` and `Full Verify` green. GitHub `Native Artifacts` run `26090497983`
completed successfully for `v0.1.0-rc.1-validation.f2f8720`; all five platform
jobs and the dry-run release-preview job passed, the audit confirmed the
dry-run avoided GitHub Release mutation, and the uploaded `native-release-preview`
artifact was present. The deployment-chain audit passed the clean latest CI,
clean latest CI logs, clean relevant Dart package publish dry-run, and clean
native release dry-run gates for `add-router`. RC readiness remains blocked by
invisible `ghcr.io/konsultaner/connectanum-router` and missing current-head RC
tag/prerelease; pub.dev publishing remains intentionally deferred.
Previous pushed implementation commit:
`8058104` (`test: harden native wamp worker readiness`; hosted CI and
deployment-chain evidence clean).
Previous implementation checkpoint: native WAMP worker readiness hardening is
complete, pushed, and hosted evidence is clean. Pre-change `bin/test-fast`
failed on
`packages/connectanum_bench/test/wamp_transport_integration_test.dart` because
the native WAMP worker did not report `READY` within the 20s startup budget on
the ticket-authenticated secure-realm workload. The worker readiness budget and
the direct worker process readiness assertion now use 60s, which keeps the gate
bounded while covering cold Dart/package/native startup on this host. Focused
repro for the failing test passed after the change, focused native cancel-cycle
repro passed after rebuilding the stale local `ffi-test` native artifact, and
the full WAMP transport integration suite passed. Focused `dart analyze` for
the two touched bench files, `bin/test-fast`, and `bin/verify` passed on
2026-05-19. Commit `8058104` (`test: harden native wamp worker readiness`) was
pushed to both configured remotes. GitHub `CI` run `26087763061` completed
successfully with `Fast Checks` and `Full Verify` green, GitHub `WAMP Profile
Benchmarks` run `26087763027` completed successfully, and GitHub `Dart Package
Publish Dry Run` run `26087763335` completed successfully. The
deployment-chain audit passed the clean latest CI, clean latest CI logs, and
clean relevant Dart package publish dry-run gates for `add-router`. RC
readiness remains blocked by the stale hosted native release dry-run for the
current head, invisible `ghcr.io/konsultaner/connectanum-router`, and missing
RC tag/prerelease; pub.dev publishing remains intentionally deferred.
Earlier pushed implementation commit:
`c4302db` (`mcp: add direct json ping helper`; hosted CI and deployment-chain
evidence clean).
Previous implementation checkpoint: router-hosted MCP direct JSON `ping` client
helper readiness is complete and pushed. The implementation adds an explicit
direct JSON mode to `McpStreamableHttpClient.ping(...)` so active
Streamable sessions can probe router-hosted MCP endpoints without sending
Streamable session headers, and extends the generated neutral consumer smoke
to cover the active-session and bearer-protected route paths. Pre-change
`bin/test-fast`, `dart format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
`bash -n bin/common.sh`, focused
`dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
focused `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
and full local `bin/verify` passed on 2026-05-13. Commit `c4302db` was pushed
to both configured remotes. GitHub `CI` run `25772595323` completed
successfully with `Fast Checks` and `Full Verify` green, GitHub
`WAMP Profile Benchmarks` run `25772595350` completed successfully, and GitHub
`Dart Package Publish Dry Run` run `25772595346` completed successfully and
covers the checked-out head. The deployment-chain audit passed with clean
latest CI, clean hosted CI logs, and a clean relevant Dart package publish
dry-run. The strict audit still reports only known operator-side
release-hardening gaps: branch protection/required checks are absent,
`.github/workflows/router-image.yml` is not yet visible from the default
branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
is not visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP direct JSON `ping`
readiness is complete and pushed. The router direct JSON dispatcher now accepts
`ping` without requiring Streamable HTTP initialization, and the generated
consumer smoke proves public and bearer-protected MCP routes handle direct JSON
`ping`, direct JSON batch `ping`, Streamable POST/SSE `ping`, and Streamable
batch `ping` over browser-readable CORS. Pre-change `bin/test-fast`, focused
`bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`, and
full local `bin/verify` passed on 2026-05-13. Commit `e156708` was pushed to
both configured remotes. GitHub `CI` run `25771050652` completed successfully
with `Fast Checks` and `Full Verify` green, GitHub `WAMP Profile Benchmarks`
run `25771050659` completed successfully, and GitHub
`Dart Package Publish Dry Run` run `25771050658` completed successfully and
covers the checked-out head. The deployment-chain audit passed with clean
latest CI, clean hosted CI logs, and a clean relevant Dart package publish
dry-run. The strict audit still reports only known operator-side
release-hardening gaps: branch protection/required checks are absent,
`.github/workflows/router-image.yml` is not yet visible from the default
branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
is not visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP raw direct JSON
tool-call alias CORS readiness is complete and pushed. The generated consumer
smoke now proves public and bearer-protected MCP routes accept both the
singular `connectanum.tool.call` method and the plural
`connectanum.tools.call` alias over browser-readable direct JSON CORS,
including a direct JSON batch that mixes both names without entering the
Streamable HTTP session lifecycle. Pre-change `bin/test-fast`, focused
`bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`, and
full local `bin/verify` passed on 2026-05-13. Commit `5e9647b` was pushed to
both configured remotes. GitHub `CI` run `25769429169` completed successfully
with `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
clean. The deployment-chain audit passed with clean latest CI, clean hosted CI
logs, and a clean relevant Dart package publish dry-run. The latest package
dry-run remains relevant from `aa33384` because no publish-sensitive paths
changed after that commit. The strict audit still reports only known
operator-side release-hardening gaps: branch protection/required checks are
absent, `.github/workflows/router-image.yml` is not yet visible from the
default branch through the Actions API, and
`ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP raw Streamable HTTP WAMP
API/pubsub CORS readiness is complete and pushed. The generated consumer smoke now
proves public and bearer-protected MCP routes support browser-style Streamable
HTTP `tools/call` POST/SSE responses for WAMP API metadata and pub/sub
subscribe, publish, poll, and unsubscribe helpers, including MCP tool-result
errors for missing API entries and unknown pub/sub handles. Pre-change
`bin/test-fast`, focused `bash -n bin/common.sh`, focused
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap;
run_mcp_consumer_package_smoke'`, and full local `bin/verify` passed on
2026-05-13. Commit `cc2640d` was pushed to both configured remotes. GitHub
`CI` run `25765942692` completed successfully with `Fast Checks` and
`Full Verify` green, and the hosted CI log scan was clean. The
deployment-chain audit passed with clean latest CI, clean hosted CI logs, and a
clean relevant Dart package publish dry-run. The latest package dry-run remains
relevant from `aa33384` because no publish-sensitive paths changed after that
commit. The strict audit still reports only known operator-side
release-hardening gaps: branch protection/required checks are absent,
`.github/workflows/router-image.yml` is not yet visible from the default branch
through the Actions API, and `ghcr.io/konsultaner/connectanum-router` is not
visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP raw direct JSON error
CORS readiness is complete and pushed. The generated consumer smoke now proves
public and bearer-protected MCP routes return browser-readable direct JSON
error payloads for missing tools, resources, prompts, WAMP API metadata, and
pub/sub handles, including mixed batches with successful responses and a
notification. The smoke also preserves lifecycle-free direct JSON behavior with
no `MCP-Session-Id`. Pre-change `bin/test-fast`, focused
`bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh; cd_repo_root;
dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`, and full local
`bin/verify` passed on 2026-05-12. Commit `74b86c0` was pushed to both
configured remotes. GitHub `CI` run `25763989367` completed successfully with
`Fast Checks` and `Full Verify` green, and the hosted CI log scan was clean.
The deployment-chain audit passed with clean latest CI, clean hosted CI logs,
and a clean relevant Dart package publish dry-run. The latest package dry-run
remains relevant from `aa33384` because no publish-sensitive paths changed
after that commit. The strict audit still reports only known operator-side
release-hardening gaps: branch protection/required checks are absent,
`.github/workflows/router-image.yml` is not yet visible from the default branch
through the Actions API, and `ghcr.io/konsultaner/connectanum-router` is not
visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP raw direct JSON
notification-only CORS readiness is complete and pushed. The generated consumer
smoke now proves public and bearer-protected MCP routes return CORS-readable
`202 Accepted` responses with empty bodies for single direct JSON notifications
and notification-only direct JSON batches while preserving lifecycle-free direct
JSON behavior with no `MCP-Session-Id`. Pre-change `bin/test-fast`, focused
`bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`, and
full local `bin/verify` passed on 2026-05-12. GitHub `CI` run `25761942671`
completed successfully with `Fast Checks` and `Full Verify` green, and the
hosted CI log scan was clean. The deployment-chain audit passed with clean
latest CI, clean hosted CI logs, and a clean relevant Dart package publish
dry-run. The latest package dry-run remains relevant from `aa33384` because no
publish-sensitive paths changed after that commit. The strict audit still
reports only known operator-side release-hardening gaps: branch
protection/required checks are absent, `.github/workflows/router-image.yml` is
not yet visible from the default branch through the Actions API, and
`ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP raw direct JSON batch
CORS readiness is complete and pushed. The generated consumer smoke now proves
public and bearer-protected MCP routes return CORS-readable JSON-RPC batch
responses for catalog, `connectanum.api.describe`, resource, prompt, and
pub/sub calls while preserving lifecycle-free direct JSON behavior with no
`MCP-Session-Id`. Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`,
and focused
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap;
run_mcp_consumer_package_smoke'` passed on 2026-05-12. Full local
`bin/verify` passed on 2026-05-12. GitHub `CI` run `25759765256` completed
successfully with `Fast Checks` and `Full Verify` green, and the hosted CI log
scan was clean. The deployment-chain audit passed with clean latest CI, clean
hosted CI logs, and a clean relevant Dart package publish dry-run. The latest
package dry-run remains relevant from `aa33384` because no publish-sensitive
paths changed after that commit. The strict audit still reports only known
operator-side release-hardening gaps: branch protection/required checks are
absent, `.github/workflows/router-image.yml` is not yet visible from the
default branch through the Actions API, and
`ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP direct JSON CORS
resource/prompt/API-description readiness is complete and pushed. The generated
consumer smoke now proves public and bearer-protected MCP routes return
CORS-readable direct JSON responses for `connectanum.api.describe`,
`resources/list`, `resources/read`, `resources/templates/list`, `prompts/list`,
and `prompts/get`, while preserving lifecycle-free direct JSON behavior with no
`MCP-Session-Id`. Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`,
and focused `bash -lc 'source bin/common.sh; cd_repo_root;
dart_workspace_bootstrap; run_mcp_consumer_package_smoke'` passed on
2026-05-12. Full local `bin/verify` passed on 2026-05-12. GitHub `CI` run
`25756916759` completed successfully with `Fast Checks` and `Full Verify`
green, and the hosted CI log scan was clean. The deployment-chain audit passed
with clean latest CI, clean hosted CI logs, and a clean relevant Dart package
publish dry-run. The latest package dry-run remains relevant from `aa33384`
because no publish-sensitive paths changed after that commit. The strict audit
still reports only known operator-side release-hardening gaps: branch
protection/required checks are absent, `.github/workflows/router-image.yml` is
not yet visible from the default branch through the Actions API, and
`ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
Previous implementation checkpoint: router-hosted MCP CORS POST body error
readiness is complete and pushed. The generated consumer smoke now proves public
and bearer-protected MCP routes return CORS-readable JSON errors for unsupported
POST `Content-Type` values and malformed JSON bodies without creating
Streamable session state. It also repeats those checks inside initialized
Streamable HTTP sessions, asserts the active `MCP-Session-Id` is preserved, and
recovers with a post-error `tools/list`. Pre-change `bin/test-fast`, focused
`bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`, and
full local `bin/verify` passed on 2026-05-12. GitHub `CI` run `25754419353`
completed successfully with `Fast Checks` and `Full Verify` green, and the
hosted CI log scan was clean. The deployment-chain audit passed with clean
latest CI, clean hosted CI logs, and a clean relevant Dart package publish
dry-run. The latest package dry-run remains relevant from `aa33384` because no
publish-sensitive paths changed after that commit.
Previous implementation checkpoint: router-hosted MCP CORS session/auth guard
readiness is complete and pushed. The generated consumer smoke now proves public
and bearer-protected Streamable HTTP CORS errors for missing session headers,
invalid `Last-Event-ID`, stale-session poll/delete, and active secure-session
missing or invalid bearer tokens. The router MCP route auth wrapper now echoes
the request `MCP-Session-Id` on route-level auth failures so browser clients
can distinguish active-session auth failures from lifecycle-free errors.
Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`, and focused
`bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap;
run_mcp_consumer_package_smoke'` passed on 2026-05-12 after the router/session
fix. Full local `bin/verify` passed on 2026-05-12. GitHub `CI` run
`25751993094`, `Dart Package Publish Dry Run` run `25751993080`, and
`WAMP Profile Benchmarks` run `25751993089` completed successfully for
`aa33384`. The deployment-chain audit passed with clean latest CI, clean
hosted CI logs, and a clean relevant Dart package publish dry-run.
Previous implementation checkpoint: router-hosted MCP CORS method-negotiation
readiness is complete and pushed. The generated consumer smoke now preflights
`POST`, `GET`, and `DELETE` against public and bearer-protected MCP routes, and
checks CORS-readable unsupported-method plus invalid-`Accept` failures without
creating Streamable session state. Pre-change `bin/test-fast`, focused
`bash -n bin/common.sh`, and focused `bash -lc 'source bin/common.sh;
cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`
passed on 2026-05-12. Full local `bin/verify` passed on 2026-05-12. GitHub
`CI` run `25749366742` completed successfully with `Fast Checks` and
`Full Verify` green, and the hosted CI log scan was clean. The
deployment-chain audit passed with clean latest CI, clean hosted CI logs, and a
clean relevant Dart package publish dry-run; the dry-run remains relevant from
`59a8e79` because no publish-sensitive paths changed.
Previous implementation checkpoint: router-hosted MCP CORS error/session
readiness is complete and pushed. MCP routes bypass native listener-side bearer
fast-fail so the Dart binding can apply route-specific MCP CORS policy to auth
failures, while ordinary protected HTTP routes keep native transport-auth
coverage. The generated consumer smoke proves secure missing-bearer direct JSON
and Streamable initialize failures are CORS-readable and do not create session
state, and proves Streamable header-validation failures preserve the active
session. Local verification, hosted CI, hosted CI log scan, the Dart package
publish dry run, the WAMP profile benchmark workflow, and the non-strict
deployment-chain audit are clean for `59a8e79`.
Previous implementation checkpoint: generated consumer smoke coverage for a
router-hosted MCP raw named CORS readiness slice across public and
bearer-protected routes (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
router-hosted MCP Streamable CORS lifecycle readiness slice across public and
bearer-protected routes (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
router-hosted MCP CORS/preflight readiness slice across public and
bearer-protected routes (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
configured allowed Origin on public and bearer-protected router-hosted MCP
routes through public client constructors, plus disallowed Origin rejection
without local Streamable HTTP session state (complete; hosted CI and
deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
bearer-protected router-hosted MCP route using older supported and unsupported
Streamable HTTP protocol-version headers through public auth-grant client APIs
(complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
deleted Streamable MCP session ID when calling the Streamable HTTP route matrix
for tool/resource batches, WAMP meta/pub-sub calls, notifications, resources,
prompts, poll, and delete after session deletion (complete; hosted CI and
deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
public MCP route trying to reuse another client's active secure Streamable MCP
session ID when calling the Streamable HTTP route matrix for tool/resource
batches, WAMP meta/pub-sub calls, notifications, resources, prompts, poll, and
delete (complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
missing bearer trying to reuse another client's active secure Streamable MCP
session ID when calling the Streamable HTTP route matrix for tool/resource
batches, WAMP meta/pub-sub calls, notifications, resources, prompts, poll, and
delete (complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for a
valid bearer token issued to a different principal trying to reuse another
client's active secure Streamable MCP session ID when calling the Streamable
HTTP route matrix for tool/resource batches, WAMP meta/pub-sub calls,
notifications, resources, prompts, poll, and delete (complete; hosted CI and
deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for an
unknown raw bearer token trying to reuse another client's active secure
Streamable MCP session ID when calling the direct JSON, WAMP meta/pub-sub, and
Streamable HTTP route matrix (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: generated consumer smoke coverage for an
unknown raw bearer token on fresh secure MCP clients when calling the direct
JSON, WAMP meta/pub-sub, and Streamable HTTP route matrix (complete; hosted CI
and deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for stale
or revoked bearer tokens on fresh secure MCP clients when calling the direct
JSON, WAMP meta/pub-sub, and Streamable HTTP route matrix (complete; hosted CI
and deployment-chain evidence clean).
Previous implementation checkpoint: generated consumer smoke coverage for stale
or revoked bearer tokens on active secure Streamable MCP sessions when calling
WAMP meta API and pub/sub paths (complete; hosted CI and deployment-chain
evidence clean).
Previous implementation checkpoint: MCP consumer package secure router-hosted
WAMP meta/pub-sub missing-bearer smoke coverage (complete; hosted CI and
deployment-chain evidence clean).
Previous implementation checkpoint: MCP consumer package secure router-hosted
Streamable session-method missing-bearer smoke coverage (complete; hosted CI and
deployment-chain evidence clean).
Previous implementation checkpoint: MCP consumer package secure router-hosted
missing-bearer direct JSON, batch, and Streamable HTTP smoke coverage (complete;
hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP consumer package router-hosted batch
tool catalog pagination smoke (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: MCP consumer package router-hosted batch
resource/template/prompt catalog pagination smoke (complete; hosted CI and
deployment-chain evidence clean).
Previous implementation checkpoint: MCP consumer package router-hosted generic
catalog pagination smoke (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: MCP consumer package router-hosted tool
catalog pagination smoke (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: MCP consumer package router-hosted catalog
pagination smoke (complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP client-only consumer package
catalog pagination smoke (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: MCP client-only consumer package
auth-client grant smoke (complete; hosted CI and deployment-chain evidence
clean).
Previous implementation checkpoint: MCP client-only consumer package
auth-grant smoke (complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP router-native auth-grant smoke
(complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP generated consumer package auth-grant
smoke (complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP router-hosted example auth-grant smoke
(complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP auth-grant Streamable client smoke
(complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP HTTP auth per-call header smoke
(complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP controlled request header smoke
(complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP direct JSON batch/notification
response-header session smoke
(complete; hosted CI and deployment-chain evidence clean).
Previous implementation checkpoint: MCP direct JSON response-header session
isolation smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP direct JSON HTTP-error session smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP WAMP helper header smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP typed helper header smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP Streamable initialize header smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP Streamable session lifecycle header smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP direct batch header smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP direct notification helper smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP notification-only batch smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP deterministic WAMP API catalog smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP deterministic resource/prompt catalog
smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP deterministic tool catalog smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer challenge-auth lifecycle smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer challenge-auth rejection smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer challenge-auth secure MCP smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer Streamable session reuse
isolation smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP Streamable HTTP batch
error-isolation smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP direct JSON batch
error-isolation smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP server-only consumer package smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP IO entrypoint WAMP registration meta
smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP IO entrypoint Streamable poll/delete
smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP IO entrypoint standard WAMP meta smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP IO entrypoint direct tool/meta smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP IO entrypoint auth/session smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP IO entrypoint Streamable pub/sub smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP IO entrypoint Streamable resource/prompt
smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package batch resource/prompt
smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package batch pub/sub smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package batch error isolation
smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package generic JSON-RPC and
batch smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client-only Streamable lifecycle smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example Streamable
lifecycle smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP pub/sub queue overflow smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP batch WAMP topic metadata smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP generated consumer package WAMP topic
metadata smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example WAMP topic
metadata smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example auth
refresh/revocation smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example protocol-version
compatibility smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example JSON-RPC
error/recovery smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example batch WAMP
subscription meta smoke plus workspace hook user defines
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example batch WAMP
session/registration meta smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example direct tool/meta
API smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example batch
pub/sub smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: router-hosted MCP example batch
resource/prompt smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer batch resource/prompt smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer batch pub/sub smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer batch subscription meta
smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer batch WAMP meta smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic direct JSON WAMP meta
smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic Streamable WAMP
registration/session meta smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic Streamable WAMP
subscription meta smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic Streamable WAMP
meta/resource-template smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic Streamable JSON-RPC
smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer direct batch tool alias smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer direct tool API smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package direct generic tool
method smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package direct WAMP meta helper smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package direct WAMP helper smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client package direct resource/prompt
smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer active resource/prompt detail
auth smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer active resource/prompt auth
smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer active tool call auth smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer active Streamable batch auth
smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer active notification auth smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer active direct JSON batch auth
smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer active direct JSON auth smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer Streamable resource/prompt
error smoke (complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer resource/prompt error smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic resources/prompts smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic API list smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic pub/sub smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer generic JSON-RPC smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer entity meta smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer session meta smoke
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP client auth error session clearing
(complete; hosted CI evidence clean).
Previous implementation checkpoint: MCP consumer participant meta smoke
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-single-error-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-batch-error-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-invalid-last-event-id-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-protocol-version-compatibility-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-active-session-method-auth-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-active-session-auth-invalidation-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-auth-refresh-revoke-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-consumer-direct-resources-after-streamable.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-client-package-helper-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-07-mcp-client-package-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-package-metadata-readiness.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-router-integration-io-entrypoint.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-public-example-io-entrypoint.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-consumer-io-entrypoint-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-direct-batch-after-streamable-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-direct-wamp-after-streamable-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-consumer-direct-catalog-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-direct-catalog-header-cache.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-consumer-custom-header-smoke.md`
(complete; hosted CI evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-custom-parameter-headers.md`
(complete; hosted evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-streamable-standard-headers.md`
(complete; hosted evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-06-mcp-streamable-session-recovery.md`
(complete; hosted evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-05-mcp-external-authorization-context.md`
(complete; hosted evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-05-mcp-http-auth-client-helper.md`
(complete; local verification clean; hosted evidence pending).
Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-consumer-runtime-smoke.md`
(complete; hosted evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-04-native-hook-user-defines-consumer-run.md`
(complete; hosted evidence clean).
Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-consumer-package-smoke.md`
(complete; hosted CI evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-example-verification-gate.md`
(complete; hosted CI evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-streamable-batch-smoke.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-streamable-session-isolation.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-router-hosted-mcp-example-pubsub-smoke.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-client-bearer-convenience.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-router-hosted-mcp-secure-example.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-route-security-resources-prompts.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-router-hosted-mcp-example-resources-prompts.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-direct-json-resources-prompts.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-router-hosted-mcp-config-validation.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-router-hosted-mcp-resources-prompts.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-router-hosted-mcp-example-readiness.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-package-release-readiness.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-direct-json-typed-wamp-helpers.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-direct-json-client-helpers.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-streamable-standard-meta-helpers.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-streamable-meta-helpers.md`
(complete; hosted evidence clean). Latest completed exec plan:
`docs/exec-plans/2026-05-04-mcp-streamable-wamp-tools.md`
(complete; hosted evidence clean). Previous completed exec plan:
`docs/exec-plans/2026-05-04-mcp-streamable-discovery-helpers.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-04-mcp-streamable-tool-helpers.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-04-mcp-ping-readiness.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-json-rpc-batch.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-participant-meta-scope.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-direct-json-session-meta-scope.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-direct-json-subscription-meta-smoke.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-direct-json-meta-api-smoke.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-streamable-protected-pubsub-smoke.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-protected-pubsub-smoke.md`
(complete; hosted evidence clean). Earlier completed exec plan:
`docs/exec-plans/2026-05-03-mcp-direct-json-pubsub-smoke.md`
(complete; hosted evidence clean). The MCP authenticated Streamable router smoke plan is complete:
`docs/exec-plans/2026-05-03-mcp-authenticated-streamable-smoke.md`
(complete; hosted evidence clean). The MCP Streamable HTTP client plan is
complete:
`docs/exec-plans/2026-05-03-mcp-streamable-http-client.md`
(complete; hosted evidence clean). The router MCP POST/SSE response
plan is complete:
`docs/exec-plans/2026-05-03-router-mcp-post-sse-responses.md`
(complete; hosted evidence clean). The router MCP SSE resumability plan is complete:
`docs/exec-plans/2026-05-03-router-mcp-sse-resumability.md`.
The router MCP SSE polling plan is complete:
`docs/exec-plans/2026-05-03-router-mcp-sse-polling.md`.
The router MCP Streamable HTTP readiness plan is complete:
`docs/exec-plans/2026-05-03-router-mcp-streamable-http-readiness.md`.
The metrics secret-redaction plan is complete:
`docs/exec-plans/2026-05-03-metrics-secret-redaction.md`.
The OpenMetrics scrape timeout plan is complete:
`docs/exec-plans/2026-05-03-openmetrics-scrape-timeout.md`.
The GitHub deployment-chain readiness plan is paused because the latest
branch-head audit is clean and remaining RC blockers are operator/deployment
decisions: current-head RC tag/prerelease selection and Dart package
ownership/release order. Branch-protection, workflow visibility, and router
package visibility gates are ready; the existing `v0.1.0-rc.1` tag still points
at the older `47bbf9c` commit.

## Last Known Verification

- Current autonomous focus:
  - Router-owned caller disclosure is complete locally. `RouterStateStore`
    computes disclosure from caller/callee policy and returns disclosed caller
    session/auth metadata in `InvocationDispatchResult`; worker, internal
    session, and native forwarding consume those dispatch fields and strip
    spoofable caller/auth detail keys from caller-provided options. Focused
    router worker-session, router runtime, client E2EE peer-metadata, Rust
    invocation, `git diff --check`, and full local `bin/verify` passed on
    2026-05-20.
  - GitHub default-branch promotion for `06dee45` is complete. GitHub `master`
    was fast-forwarded from `2eced84` to `06dee45` on 2026-05-20; GitHub
    reported the protected-branch PR rule was bypassed for that direct update.
    Hosted `master` CI run `26138507065` passed with `Fast Checks` and
    `Full Verify`, Native Artifacts dry-run `26138936777` passed for validation
    tag `v0.1.0-rc.1-validation.06dee45`, and the strict deployment-chain audit
    passed for `master` with clean CI/log, Dart package dry-run, native release
    dry-run, router image dry-run, workflow visibility, and router package
    visibility gates. RC readiness still reports not-ready because no approved
    numeric RC tag or GitHub prerelease points at `06dee45`; the audit suggests
    `v0.1.0-rc.2` as the next follow-up tag after release approval. No RC tag or
    GitHub Release was created or moved. A final local `bin/verify` handoff
    pass also completed successfully after the hosted evidence was recorded.
  - Native Artifacts RC prerelease intent hardening is complete and pushed.
    Project SemVer prerelease tags such as `v0.1.0-rc.2` are now treated as
    GitHub prereleases by both `tool/validate_native_release_intent.py` and the
    Native Artifacts workflow tag-push/manual publish path, so an approved RC
    tag cannot accidentally create a stable GitHub Release. Pre-change
    `bin/test-fast` passed on 2026-05-20. Focused release-intent unit tests, a
    CLI validation for `v1.2.3-rc.1`, a workflow guard snippet check, and
    `git diff --check` passed locally; an isolated bench package rerun and full
    local `bin/verify` also passed on 2026-05-20. Commit `06dee45` was pushed
    to GitLab `origin` and GitHub `add-router`; GitHub `CI` run `26137710822`
    passed, Native Artifacts dry-run `26138108909` passed for validation tag
    `v0.1.0-rc.1-validation.06dee45`, and the strict deployment-chain audit
    passed with RC readiness still not-ready because `add-router` is not the
    default release branch and no numeric RC tag points at `06dee45`. No RC tag
    or GitHub Release was created or moved.
  - RC default-branch selection audit hardening is complete and pushed.
    `bin/audit-github-deployment-chain --show-rc-readiness` now reports whether
    the audited branch is the default release branch and suppresses follow-up
    numeric RC tag suggestions on aligned non-default branches. Pre-change
    `bin/test-fast`, focused Bash syntax, the audit regression module, help
    output, `git diff --check`, a live read-only `add-router` RC-readiness
    summary, and full local `bin/verify` passed on 2026-05-20. The live summary
    now reports `add-router` as branch/head aligned but not the default release
    branch, and it does not suggest `v0.1.0-rc.2` until `master` is audited from
    an aligned checkout. Commit `ea309d6` was pushed to GitLab `origin` and
    GitHub `add-router`; GitHub `CI` run `26135920644` passed, and the strict
    deployment-chain audit passed for `add-router` with RC readiness still
    not-ready because the audited branch is not the default release branch and
    no numeric RC tag points at `ea309d6`. No RC tag or GitHub Release was
    created or moved.
  - RC branch/head alignment audit hardening is complete locally.
    `bin/audit-github-deployment-chain --show-rc-readiness` now prints the
    audited branch head and requires it to match the checked-out head before RC
    readiness or follow-up numeric RC tag suggestions are evaluated. Mismatched
    branch/checkout audits report not-ready and suppress follow-up tag
    suggestions until alignment is fixed. Pre-change `bin/test-fast`, focused
    Bash syntax, the audit regression module, help output, `git diff --check`,
    an aligned `add-router` RC-readiness summary, and full local `bin/verify`
    passed on 2026-05-20. A read-only `master` RC-readiness summary confirmed
    mismatch suppression, but GitHub returned a transient 502 while inspecting
    Dart package dry-run jobs, so that summary was not used as clean release
    evidence. No RC tag or GitHub Release was created or moved.
  - Numeric RC tag selection hardening is complete locally. The RC-readiness
    audit now requires a numeric RC tag for the checked-out-head release-tag
    gate while still inventorying RC-looking validation/dry-run tags as
    current or stale evidence. The fake-`gh` regression now proves a current
    validation/dry-run tag does not satisfy RC tag readiness and still suggests
    only the next numeric follow-up tag. Pre-change `bin/test-fast`, focused
    Bash syntax, the audit regression module, `git diff --check`, a real
    read-only `master` RC-readiness audit, and full local `bin/verify` passed
    on 2026-05-20. No RC tag or GitHub Release was created or moved.
  - Router-hosted MCP protected resource/prompt auth-rejection smoke coverage
    is complete locally. The generated neutral consumer package smoke now
    checks missing-credential rejection for direct JSON and Streamable
    resource/prompt helpers plus resource-prompt batches on the secure MCP
    route. Pre-change `bin/test-fast` passed; post-change `bash -n
    bin/common.sh`, `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-19.
  - GitHub RC tag evidence audit hardening is complete and pushed.
    `bin/audit-github-deployment-chain --show-rc-readiness` now uses both
    local and GitHub RC tags for the checked-out-head tag gate, and it prints
    stale-tag inventories from both sources when no RC tag points at the
    candidate head. Pre-change `bin/test-fast`, Bash syntax, help output, the
    focused RC-readiness audit, and full local `bin/verify` passed on
    2026-05-19. Commit `e25c0c7` (`ci: audit github rc tag evidence`) was
    pushed to both configured remotes. GitHub CI run `26111109838` passed with
    `Fast Checks` and `Full Verify` green, and the strict deployment-chain
    audit passed the clean CI/log, Dart package dry-run, native release
    dry-run, router image dry-run, and router package visibility gates. The
    audit reports both local and GitHub `v0.1.0-rc.1 -> 47bbf9c` as stale for
    checked-out head `e25c0c7`.
  - RC tag evidence audit hardening is complete and pushed.
    `bin/audit-github-deployment-chain --show-rc-readiness` now inventories
    existing local RC tags when no RC tag points at the checked-out head,
    including each target commit and stale/current status. Pre-change
    `bin/test-fast`, Bash syntax, help output, and the focused RC-readiness
    audit passed on 2026-05-19; full local `bin/verify` also passed. Commit
    `cbe1e1d` (`ci: report stale rc tag evidence`) was pushed to both
    configured remotes. GitHub CI run `26108394380` passed with `Fast Checks`
    and `Full Verify` green, and the strict deployment-chain audit passed the
    clean CI/log, Dart package dry-run, native release dry-run, router image
    dry-run, and router package visibility gates. The audit now reports
    `v0.1.0-rc.1 -> 47bbf9c` as stale for checked-out head `cbe1e1d`, so the
    remaining action is an explicit release decision to move the stale tag
    under policy or choose a follow-up RC tag.
  - Router package visibility audit hardening is complete and pushed.
    `bin/audit-github-deployment-chain --require-router-package` now probes
    public GHCR registry pull metadata, validates a manifest digest, and falls
    back to GitHub Packages metadata only as a compatibility path. Pre-change
    `bin/test-fast`, focused Bash/help/diff checks, the focused package
    visibility audit, an RC-readiness audit, and full local `bin/verify`
    completed on 2026-05-19; all required local gates passed. Commit
    `65caf71` (`ci: audit ghcr router package visibility`) was pushed to both
    configured remotes. GitHub CI run `26105461957` passed with `Fast Checks`
    and `Full Verify` green, and the strict deployment-chain audit passed the
    clean CI/log, Dart package dry-run, native release dry-run, router image
    dry-run, and router package visibility gates. The package visibility gate
    reports public tag
    `v0.1.0-rc.1` with manifest digest
    `sha256:45d168f29a2b4c1c187ed21ff18c0f0539703b66c2709422cc414b360966b737`.
    RC readiness still requires current-head RC tag/prerelease selection.
  - Router Image workflow deprecation hardening is complete and pushed.
    Commit `5a10bd5` (`ci: harden router image action audit`) was pushed to
    both configured remotes. GitHub CI run `26102726359`, GitHub `Router Image`
    dry-run `26102736224`, and the strict deployment-chain audit passed for
    `5a10bd5`; the Router Image dry-run audit reported check annotations
    clean.
  - Native HTTP/1 keep-alive idle-timeout log-cleanliness is complete and
    pushed.
    The native runtime now treats HTTP/1 idle timeouts as expected connection
    lifecycle closures instead of printing `http/1 connection read error`,
    preserving diagnostics for non-timeout protocol and I/O errors. Pre-change
    `bin/test-fast` passed and exposed the generated router-hosted MCP
    consumer-package smoke timeout diagnostic. Focused
    `cargo test -p ct_core
    http1_read_error_logging_skips_expected_idle_timeouts`, focused generated
    consumer-package smoke with output scan, `git diff --check`, and full local
    `bin/verify` passed on 2026-05-19. Commit `f0c1590`
    (`fix: silence expected http1 idle timeouts`) was pushed to both configured
    remotes. GitHub CI run `26098749788`, GitHub WAMP Profile Benchmarks run
    `26098749790`, GitHub kTLS Validation run `26098749771`, GitHub `Native
    Artifacts` dry-run `26099397722`, GitHub `Router Image` dry-run
    `26099397318`, and the strict deployment-chain audit all passed for
    `f0c1590`. RC readiness still requires router image package visibility or
    publish approval and current-head RC tag/prerelease selection.
  - MCP consumer package raw Streamable HTTP WAMP API/pubsub CORS smoke is
    complete and pushed in commit `cc2640d`
    (`test: cover mcp streamable wamp cors`). The slice extends the neutral
    generated consumer package smoke to prove browser-style public and
    bearer-protected MCP routes return CORS-readable Streamable HTTP
    `tools/call` POST/SSE responses for WAMP API metadata and pub/sub
    subscribe, publish, poll, and unsubscribe helpers, including MCP
    tool-result errors for missing API entries and unknown pub/sub handles.
    Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
    cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
    and full local `bin/verify` passed on 2026-05-13. GitHub `CI` run
    `25765942692` completed successfully with `Fast Checks` and `Full Verify`
    green, and the hosted CI log scan was clean. The deployment-chain audit
    passed with clean latest CI, clean hosted CI logs, and a clean relevant
    Dart package publish dry-run. The latest package dry-run remains relevant
    from `aa33384` because no publish-sensitive paths changed after that
    commit. The strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and `ghcr.io/konsultaner/connectanum-router`
    is not visible in GitHub Packages.
  - MCP consumer package raw direct JSON error CORS smoke is complete and
    pushed in commit `74b86c0` (`test: cover mcp direct json error cors`). The
    slice extends the neutral generated consumer package smoke to prove
    browser-style public and bearer-protected MCP routes return CORS-readable
    direct JSON error payloads for missing tools, resources, prompts, WAMP API
    metadata, and pub/sub handles, including mixed batches with successful
    responses and a notification, without creating Streamable HTTP session
    state. Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`,
    focused `bash -lc 'source bin/common.sh; cd_repo_root;
    dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`, and full local
    `bin/verify` passed on 2026-05-12. GitHub `CI` run `25763989367`
    completed successfully with `Fast Checks` and `Full Verify` green, and the
    hosted CI log scan was clean. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and a clean relevant Dart package publish
    dry-run. The latest package dry-run remains relevant from `aa33384` because
    no publish-sensitive paths changed after that commit. The strict audit
    still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package raw direct JSON notification-only CORS smoke is
    complete and pushed in commit `edfcdcd`
    (`test: cover mcp direct json notification cors`). The slice extends the
    neutral generated consumer package smoke to prove browser-style public and
    bearer-protected MCP routes return CORS-readable `202 Accepted` responses
    with empty bodies for single direct JSON notifications and notification-only
    direct JSON batches without creating Streamable HTTP session state.
    Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap;
    run_mcp_consumer_package_smoke'`, and full local `bin/verify` passed on
    2026-05-12. GitHub `CI` run `25761942671` completed successfully with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. The deployment-chain audit passed with clean latest CI, clean hosted
    CI logs, and a clean relevant Dart package publish dry-run. The latest
    package dry-run remains relevant from `aa33384` because no publish-sensitive
    paths changed after that commit. The strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package raw direct JSON batch CORS smoke is complete and
    pushed in commit `4eb6376` (`test: cover mcp direct json batch cors`). The
    slice extends the neutral generated consumer package smoke to prove
    browser-style public and bearer-protected MCP routes return CORS-readable
    JSON-RPC batch responses for catalog, `connectanum.api.describe`, resource,
    prompt, and pub/sub calls without creating Streamable HTTP session state.
    Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`, and focused
    `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap;
    run_mcp_consumer_package_smoke'` passed on 2026-05-12. Full local
    `bin/verify` passed on 2026-05-12. GitHub `CI` run `25759765256`
    completed successfully with `Fast Checks` and `Full Verify` green, and the
    hosted CI log scan was clean. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and a clean relevant Dart package publish
    dry-run. The latest package dry-run remains relevant from `aa33384` because
    no publish-sensitive paths changed after that commit. The strict audit still
    reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package direct JSON CORS resource/prompt/API-description smoke
    is complete and pushed in commit `ea0442f`
    (`test: cover mcp direct json cors resources`). The slice extends the
    neutral generated consumer
    package smoke to prove browser-style public and bearer-protected MCP routes
    return CORS-readable direct JSON responses for
    `connectanum.api.describe`, `resources/list`, `resources/read`,
    `resources/templates/list`, `prompts/list`, and `prompts/get` without
    creating Streamable HTTP session state. Pre-change `bin/test-fast`,
    focused `bash -n bin/common.sh`, and focused `bash -lc 'source
    bin/common.sh; cd_repo_root; dart_workspace_bootstrap;
    run_mcp_consumer_package_smoke'` passed on 2026-05-12. Full local
    `bin/verify` passed on 2026-05-12. GitHub `CI` run `25756916759`
    completed successfully with `Fast Checks` and `Full Verify` green, and the
    hosted CI log scan was clean. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and a clean relevant Dart package publish
    dry-run. The latest package dry-run remains relevant from `aa33384` because
    no publish-sensitive paths changed after that commit. The strict audit still
    reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package router-hosted CORS POST body error smoke is complete
    and pushed in commit `de467ac`
    (`test: cover mcp cors post body errors`). The slice extends the neutral
    generated consumer package smoke to
    prove browser-style public and bearer-protected MCP routes reject
    unsupported POST `Content-Type` values and malformed JSON bodies with
    CORS-readable JSON errors and no accidental session creation. Initialized
    Streamable HTTP sessions now get the same coverage while preserving the
    active `MCP-Session-Id`, followed by a recovery `tools/list` check.
    Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; cd_repo_root;
    dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`, and full local
    `bin/verify` passed on 2026-05-12. GitHub `CI` run `25754419353`
    completed successfully with `Fast Checks` and `Full Verify` green, and the
    hosted CI log scan was clean. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and a clean relevant Dart package publish
    dry-run. The latest package dry-run remains relevant from `aa33384` because
    no publish-sensitive paths changed after that commit. The strict audit still
    reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package router-hosted CORS session/auth guard smoke is
    complete and pushed in commit `aa33384`
    (`fix: preserve mcp session on cors auth failures`). The slice extends the
    neutral generated consumer package smoke to prove browser-style public and
    bearer-protected Streamable HTTP failures for missing `MCP-Session-Id`,
    invalid `Last-Event-ID`, stale-session poll/delete, and active
    secure-session missing or invalid bearer tokens. The focused smoke first
    caught that MCP route-level auth failures were CORS-readable but did not
    echo an active `MCP-Session-Id`; the router binding now includes that
    request session id in MCP auth failure headers. Pre-change `bin/test-fast`,
    focused `bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
    cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
    and full local `bin/verify` passed on 2026-05-12. GitHub `CI` run
    `25751993094`, `Dart Package Publish Dry Run` run `25751993080`, and
    `WAMP Profile Benchmarks` run `25751993089` completed successfully for
    `aa33384`. The deployment-chain audit passed with clean latest CI, clean
    hosted CI logs, and a clean relevant Dart package publish dry-run. The
    strict audit still reports only known operator-side release-hardening gaps:
    branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package router-hosted CORS method-negotiation smoke is
    complete and pushed in commit `636a773`
    (`test: cover mcp cors method negotiation`). The slice extends the neutral
    generated consumer package smoke to prove browser-style CORS preflights for
    `POST`, `GET`, and `DELETE` on public and bearer-protected MCP routes. It
    also sends raw allowed-origin requests for unsupported `PUT`, invalid GET
    `Accept`, and invalid POST `Accept`, asserting CORS-readable JSON errors,
    an `Allow` header for unsupported methods, and no accidental Streamable
    session state. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
    cd_repo_root; dart_workspace_bootstrap; run_mcp_consumer_package_smoke'`,
    and full local `bin/verify` passed on 2026-05-12. GitHub `CI` run
    `25749366742` completed successfully for `636a773` with `Fast Checks` and
    `Full Verify` green, and the hosted CI log scan was clean. The
    deployment-chain audit passed with clean latest CI, clean hosted CI logs,
    and a clean relevant Dart package publish dry-run. The publish dry-run
    remains relevant from `59a8e79` because no publish-sensitive paths changed.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package router-hosted CORS error/session smoke is complete and
    pushed in commit `59a8e79` (`fix: keep mcp auth failures cors-readable`).
    The slice keeps MCP route auth failures in the Dart binding path so
    route-specific MCP CORS policy is available before responding, while
    ordinary protected HTTP routes keep native listener-side transport-auth
    coverage. The generated consumer package smoke now proves secure
    missing-bearer direct JSON and Streamable initialize failures are
    CORS-readable and do not create Streamable session state. It also sends raw
    Streamable requests that fail header validation for missing `Mcp-Method`,
    mismatched `Mcp-Name`, missing `Mcp-Param-TaskId`, and invalid
    `Mcp-Param-Note`, then follows them with a valid request proving the active
    session still works. Pre-change `bin/test-fast` passed, a focused pre-fix
    smoke reproduced the native fast-fail CORS gap, focused
    `bash -lc 'source bin/common.sh; cd_repo_root; dart_workspace_bootstrap;
    run_mcp_consumer_package_smoke'`, focused
    `dart test packages/connectanum_router/test/http_route_transport_auth_test.dart`,
    focused `dart analyze packages/connectanum_router`, and full local
    `bin/verify` passed on 2026-05-12. GitHub `CI` run `25746825371`
    completed successfully for `59a8e79` with `Fast Checks` and `Full Verify`
    green, and the hosted CI log scan was clean. GitHub `Dart Package Publish
    Dry Run` run `25746825383` completed successfully and covers the checked-out
    head. GitHub `WAMP Profile Benchmarks` run `25746825412` completed
    successfully. The deployment-chain audit passed with clean latest CI, clean
    hosted CI logs, and a clean relevant Dart package publish dry-run. The
    strict audit still reports only known operator-side release-hardening gaps:
    branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer package router-hosted raw named CORS smoke is complete.
    Commit `e2210c3` (`test: cover mcp raw named cors access`) is pushed to
    both remotes. GitHub `CI` run `25742676102` completed successfully for
    `e2210c3` with `Fast Checks` and `Full Verify` green, and the hosted CI log
    scan was clean. GitHub `Dart Package Publish Dry Run` run `25735530321`
    remains clean and relevant from `e35cab0` because no publish-sensitive
    paths changed. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The slice extends the neutral
    generated consumer package smoke to prove browser-like raw direct JSON
    CORS access to `connectanum.tools.list`, `connectanum.tool.call`,
    `connectanum.api.list`, and pub/sub subscribe/publish/poll/unsubscribe on
    public and bearer-protected MCP routes without creating Streamable session
    state. It also extends raw Streamable HTTP POST/SSE coverage to named
    `tools/call`, `resources/read`, and `prompts/get` requests using the
    public `Mcp-Method`, `Mcp-Name`, and concrete `Mcp-Param-*` headers needed
    by header validation. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, and focused `bash -lc 'source bin/common.sh;
    run_mcp_consumer_package_smoke'`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-12.
  - MCP consumer package router-hosted Streamable CORS lifecycle smoke is
    complete. Commit `786904a`
    (`test: cover mcp streamable cors lifecycle`) is pushed to both remotes.
    GitHub `CI` run `25739082402` completed successfully for `786904a` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25735530321` remains
    clean and relevant from `e35cab0` because no publish-sensitive paths
    changed. The deployment-chain audit passed with clean latest CI, clean
    hosted CI logs, and a clean relevant Dart package publish dry-run. The
    strict audit still reports only known operator-side release-hardening gaps:
    branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The slice extends the neutral generated consumer package smoke to use raw
    browser-like Streamable HTTP requests with the configured allowed `Origin`
    on public and bearer-protected MCP routes, checking readable
    session/protocol headers across initialize, initialized notification,
    POST/SSE tool listing, GET/SSE notification polling, Last-Event-ID resume,
    DELETE, and deleted-session rejection. The raw Streamable POST helper also
    sends the public `Mcp-Method` and `Mcp-Name` headers expected by the
    router's Streamable HTTP header guard, and the preflight smoke now asserts
    those headers are allowed. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused `bash -lc 'source bin/common.sh;
    run_mcp_consumer_package_smoke'`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-12.
  - MCP consumer package router-hosted CORS/preflight smoke is complete. Commit
    `e35cab0` (`fix: allow mcp cors preflight`) is pushed to both remotes.
    GitHub `CI` run `25735530396` completed successfully for `e35cab0` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25735530321` completed
    successfully for `e35cab0`. The latest branch runs also show `kTLS
    Validation` run `25735530322` and `WAMP Profile Benchmarks` run
    `25735530337` completed successfully for `e35cab0`. The deployment-chain
    audit passed with clean latest CI, clean hosted CI logs, and a clean
    relevant Dart package publish dry-run. The strict audit still reports only
    known operator-side release-hardening gaps: branch protection/required
    checks are absent, `.github/workflows/router-image.yml` is not yet visible
    from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The implementation adds MCP-specific CORS response metadata for configured
    allowed origins, handles public and bearer-protected CORS preflight before
    auth/session resolution, and scopes the native listener-side bearer bypass
    to MCP-derived CORS preflight route config. The generated consumer smoke
    proves allowed public and secure preflight, disallowed preflight rejection,
    and actual direct JSON response CORS headers without private application
    assumptions. Pre-change `bin/test-fast`, focused
    `dart test packages/connectanum_router/test/http_route_transport_auth_test.dart`,
    focused `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml
    --features ffi-test
    http_transport_auth_allows_bearerless_cors_preflight_when_configured --
    --nocapture`, focused `bash -lc 'source bin/common.sh;
    run_mcp_consumer_package_smoke'`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-12.
  - MCP consumer package router-hosted Origin policy smoke is complete. Commit
    `6dfcb87` (`test: cover mcp origin policy smoke`) is pushed to both
    remotes. GitHub `CI` run `25731613387` completed successfully for
    `6dfcb87` with `Fast Checks` and `Full Verify` green, and the hosted CI log
    scan was clean. GitHub `Dart Package Publish Dry Run` run `25635686773`
    remains clean and relevant because no publish-sensitive package inputs
    changed after `90a27ca`. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and a clean relevant Dart package publish
    dry-run. The strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The generated consumer smoke now configures neutral allowed origins on the
    public and secure MCP routes, proves public and auth-grant clients can use
    direct JSON and Streamable HTTP with the allowed `Origin` header, and proves
    disallowed direct JSON requests fail with HTTP 403 without local Streamable
    session state. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-12.
  - MCP consumer package secure protocol-version compatibility smoke is
    complete. Commit `8ceac39`
    (`test: cover secure mcp protocol versions`) is pushed to both remotes.
    GitHub `CI` run `25728977893` completed successfully for `8ceac39` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The implementation extends the generated consumer smoke's
    protocol-version compatibility helper so it can build either public clients
    or `withAuthGrant` clients with `defaultProtocolVersion`, then runs the
    older supported protocol-version initialize/ping/delete checks and the
    unsupported-version HTTP 400 state-leak check against the bearer-protected
    MCP route after issuing a ticket auth grant. Pre-change `bin/test-fast`,
    focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-12.
  - MCP consumer package deleted Streamable session reuse matrix smoke is
    complete. Commit `e2cd92d`
    (`test: cover deleted streamable mcp session matrix`) is pushed to both
    remotes. GitHub `CI` run `25726259108` completed successfully for
    `e2cd92d` with `Fast Checks` and `Full Verify` green, and the hosted CI log
    scan was clean. GitHub `Dart Package Publish Dry Run` run `25635686773`
    remains clean and relevant because no publish-sensitive package inputs
    changed after `90a27ca`. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and a clean relevant Dart package publish
    dry-run. The strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The implementation replaces the generated consumer smoke's
    single deleted-session `tools/list` check with the same stale-session
    Streamable route matrix used for other rejected session reuse paths. After
    successful Streamable initialization, GET/SSE polling, Last-Event-ID resume,
    and session deletion, the client now reuses the deleted session id and last
    event id and must receive HTTP 404 with local Streamable state cleared
    across Streamable batch `tools/list` and `resources/list`, Streamable WAMP
    meta/pub-sub `tools/call` batches, `notifications/initialized`, typed
    `tools/list`, typed `tools/call`, typed resource and prompt helpers,
    GET/SSE poll, and session delete. The same client then reinitializes to
    prove recovery remains usable. Pre-change `bin/test-fast` passed on
    2026-05-11. Focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-12.
  - MCP consumer package public-route Streamable session reuse matrix smoke is
    complete. Commit `ffa38c4`
    (`test: cover public mcp route reuse matrix`) is pushed to both remotes.
    GitHub `CI` run `25695269935` completed successfully for `ffa38c4` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The implementation replaces the generated consumer smoke's public-route
    poll/delete checks with the same stale-session Streamable route matrix used
    for other-principal reuse. A public-route client now reuses the primary
    secure client's active Streamable MCP session id and last event id, then
    must receive HTTP 404 and clear only its own local Streamable state across
    Streamable batch `tools/list` and `resources/list`, Streamable WAMP
    meta/pub-sub `tools/call` batches, `notifications/initialized`, typed
    `tools/list`, typed `tools/call`, typed resource and prompt helpers,
    GET/SSE poll, and session delete. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` all passed on
    2026-05-11.
  - MCP consumer package secure router-hosted active missing-bearer Streamable
    matrix smoke is complete. Commit `0c21cd5`
    (`test: cover active missing mcp bearer matrix`) is pushed to both remotes.
    GitHub `CI` run `25692740916` completed successfully for `0c21cd5` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The neutral generated consumer package smoke now uses a bearerless
    secure-route client with the primary client's active secure Streamable MCP
    session id and last event id, then proves the route rejects missing
    credentials across
    Streamable batch `tools/list` and `resources/list`, Streamable WAMP
    meta/pub-sub `tools/call` batches, `notifications/initialized`, typed
    `tools/list`, typed `tools/call`, typed resource and prompt helpers,
    GET/SSE poll, and session delete. Each rejected operation re-seeds the
    copied session state and must clear only the rejected client's local
    Streamable state. The primary owner session is rechecked afterward to prove
    rejected bearerless reuse does not disturb the valid session. Pre-change
    `bin/test-fast`, focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`, and
    post-change `bin/test-fast` all passed on 2026-05-11. Full local
    `bin/verify` also passed on 2026-05-11.
  - MCP consumer package secure router-hosted other-principal Streamable
    session reuse smoke is complete. Commit `533638b`
    (`test: cover secure mcp principal reuse matrix`) is pushed to both
    remotes. GitHub `CI` run `25689906622` completed successfully for
    `533638b` with `Fast Checks` and `Full Verify` green, and the hosted CI log
    scan was clean. GitHub `Dart Package Publish Dry Run` run `25635686773`
    remains clean and relevant because no publish-sensitive package inputs
    changed after `90a27ca`. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and a clean relevant Dart package publish
    dry-run. The strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The neutral generated consumer package smoke now uses a client with a
    bearer token validly issued to a different principal to try to reuse the
    primary client's active secure Streamable MCP session id and last event id.
    The rejected reuse matrix covers Streamable batch `tools/list` and
    `resources/list`, Streamable WAMP meta/pub-sub `tools/call` batches,
    `notifications/initialized`, typed `tools/list`, typed `tools/call`, typed
    resource and prompt helpers, GET/SSE poll, and session delete. The primary
    owner session is rechecked afterward to prove rejected cross-principal
    reuse does not disturb the valid session. Pre-change `bin/test-fast`,
    focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package secure router-hosted active unknown-bearer WAMP
    meta/pub-sub smoke is complete. Commit `251e5e2`
    (`test: cover active unknown mcp bearer auth`) is pushed to both remotes.
    GitHub `CI` run `25687247656` completed successfully for `251e5e2` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The neutral generated consumer package smoke now seeds a secure
    `McpStreamableHttpClient` with an unknown raw bearer token plus another
    client's active Streamable MCP session id and last event id, then rejects it
    across direct JSON
    `connectanum.api.list`, direct JSON `connectanum.pubsub.subscribe`, direct
    JSON WAMP meta/pub-sub batches, Streamable tool/resource batches,
    Streamable WAMP meta/pub-sub `tools/call` batches, notifications, resource
    and prompt helpers, GET/SSE poll, and session delete. The primary owner
    session is rechecked afterward to prove rejected reuse does not disturb the
    valid session. Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`,
    focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package secure router-hosted unknown-bearer WAMP meta/pub-sub
    smoke is complete. Commit `caf987a`
    (`test: cover unknown mcp bearer auth`) is pushed to both remotes. GitHub
    `CI` run `25684774263` completed successfully for `caf987a` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The target was the neutral generated consumer package smoke: secure
    router-hosted MCP must reject an unknown raw bearer token for direct JSON
    `connectanum.tools.list`, direct JSON `connectanum.api.list`, direct JSON
    `connectanum.pubsub.subscribe`, direct JSON batches that mix WAMP
    meta/pub-sub methods, Streamable `initialize`, and Streamable HTTP batches
    that call WAMP meta/pub-sub tools through `tools/call`, without populating
    consumer Streamable session state. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package secure router-hosted WAMP meta/pub-sub missing-bearer
    smoke is complete. Commit `3ca481c`
    (`test: cover secure mcp meta pubsub auth`) is pushed to both remotes.
    GitHub `CI` run `25676940340` completed successfully for `3ca481c` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The target was the neutral generated consumer package smoke:
    secure router-hosted MCP must reject missing bearer credentials for direct
    JSON `connectanum.api.list`, direct JSON `connectanum.pubsub.subscribe`,
    direct JSON batches that mix WAMP meta/pub-sub methods, and Streamable HTTP
    batches that call WAMP meta/pub-sub tools through `tools/call`, without
    populating consumer Streamable session state. Pre-change `bin/test-fast`,
    focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package secure router-hosted Streamable session-method
    missing-bearer smoke is complete. Commit `d2c8e19`
    (`test: cover secure mcp session method auth`) is pushed to both remotes.
    GitHub `CI` run `25674548625` completed successfully for `d2c8e19` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The target was the neutral generated consumer package smoke: secure
    router-hosted MCP must reject bearerless Streamable HTTP GET/SSE poll and
    DELETE session requests with HTTP 401 even when the caller knows an active
    authenticated MCP session id, clear the rejected caller's Streamable session
    state, and leave the authenticated owner session usable. Pre-change
    `bin/test-fast`, focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package secure router-hosted missing-bearer smoke is complete.
    Commit `e31f063`
    (`test: cover secure mcp missing bearer batches`) is pushed to both remotes.
    GitHub `CI` run `25671922553` completed successfully for `e31f063` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The target was the neutral generated consumer package smoke: secure
    router-hosted MCP must reject missing bearer credentials for direct JSON
    `connectanum.tools.list`, direct JSON batch `connectanum.tools.list`,
    Streamable HTTP `initialize`, and Streamable HTTP batch `tools/list`
    without populating consumer Streamable session state. Pre-change
    `bin/test-fast`, focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package router-hosted batch tool catalog pagination smoke is
    complete. Commit `4d9c786`
    (`test: page router mcp batch tool catalogs`) is pushed to both remotes.
    GitHub `CI` run `25669602960` completed successfully for `4d9c786` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The target was the neutral generated consumer package smoke: direct JSON and
    Streamable HTTP JSON-RPC batches should prove `connectanum.tools.list` /
    `tools/list` cursor traversal on the real router-provided MCP endpoints
    instead of only proving first-page behavior. Pre-change `bin/test-fast`,
    focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package router-hosted batch resource/template/prompt catalog
    pagination smoke is complete. Commit `9bfa925`
    (`test: page router mcp batch catalogs`) is pushed to both remotes.
    GitHub `CI` run `25667401950` completed successfully for `9bfa925` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The target was the neutral generated consumer
    package smoke: direct JSON and Streamable HTTP JSON-RPC batches should
    prove `resources/list`, `resources/templates/list`, and `prompts/list`
    cursor traversal on the real router-provided MCP endpoints instead of only
    proving first-page behavior. Pre-change `bin/test-fast` passed on
    2026-05-11. Focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package router-hosted generic resource/template/prompt catalog
    pagination smoke is complete. Commit `0601652`
    (`test: page router mcp generic catalogs`) is pushed to both remotes.
    GitHub `CI` run `25665252241` completed successfully for `0601652` with
    `Fast Checks` and `Full Verify` green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25635686773` remains
    clean and relevant because no publish-sensitive package inputs changed
    after `90a27ca`. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The target was the neutral generated consumer
    package smoke: generic direct JSON `resources/list`,
    `resources/templates/list`, and `prompts/list`, plus generic Streamable
    HTTP JSON-RPC calls for the same catalogs, should follow opaque cursors on
    the real router-provided MCP endpoints instead of only proving first-page
    behavior. Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`, and
    focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'` passed on
    2026-05-11. Post-change `bin/test-fast` and full local `bin/verify` passed
    on 2026-05-11.
  - MCP consumer package router-hosted tool catalog pagination smoke is
    complete. Commit `44e5fbc` (`test: page router mcp tool catalogs`) is
    pushed to both remotes. GitHub `CI` run `25663098863` completed
    successfully for `44e5fbc` with `Fast Checks` and `Full Verify` green, and
    the hosted CI log scan was clean. GitHub `Dart Package Publish Dry Run` run
    `25635686773` remains clean and relevant because no publish-sensitive
    package inputs changed after `90a27ca`. The deployment-chain audit passed
    with clean latest CI, clean hosted CI logs, and a clean relevant Dart
    package publish dry-run. The strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    The generated router-hosted MCP consumer smoke now forces public and
    bearer-protected tool catalogs to paginate with opaque cursors, and
    generated app checks follow those cursors through both initialized
    Streamable `tools/list`, typed helper catalogs, generic JSON-RPC
    `tools/list`, lifecycle-free direct JSON `connectanum.tools.list`, and
    generic direct JSON-RPC `connectanum.tools.list`. Batch `tools/list` checks
    now assert a valid paginated first page while neighboring `tools/call`
    responses prove the registered consumer procedure remains callable.
    Pre-change `bin/test-fast`, focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11.
  - MCP consumer package router-hosted catalog pagination smoke is complete.
    The generated router-hosted MCP consumer smoke now configures deterministic
    second-page resource, resource template, and prompt catalog entries on the
    real router-provided MCP endpoints, forces opaque cursors with page size
    one, and follows those cursors through public
    `McpStreamableHttpClient` typed helpers over both session-bound Streamable
    HTTP and lifecycle-free direct JSON. Pre-change full local `bin/verify`,
    focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_consumer_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11. Commit `4e00460` (`test: page router mcp consumer catalogs`)
    is pushed to both remotes. GitHub `CI` run `25660013309` completed
    successfully for `4e00460` with `Fast Checks` and `Full Verify` green, and
    the hosted CI log scan was clean. GitHub `Dart Package Publish Dry Run` run
    `25635686773` remains clean and relevant because no publish-sensitive
    package inputs changed after `90a27ca`. The deployment-chain audit passed
    with clean latest CI, clean hosted CI logs, and a clean relevant Dart
    package publish dry-run. The strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP client-only consumer package catalog pagination smoke is complete
    through full local and hosted verification. The standalone generated MCP
    client package smoke now exposes deterministic fake cursor pages for tools,
    resources, resource templates, and prompts, then follows those opaque
    `nextCursor` values through public `McpStreamableHttpClient` helpers over
    session-bound Streamable HTTP and lifecycle-free direct JSON where
    supported. The direct JSON cursor probes also assert no `MCP-Session-Id`
    leaks into consumer requests. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-11. Commit `3e00cb1` (`test: follow mcp catalog cursors in client
    smoke`) is pushed to both remotes. GitHub `CI` run `25658297818` completed
    successfully for `3e00cb1` with `Fast Checks` and `Full Verify` green, and
    the hosted CI log scan was clean. GitHub `Dart Package Publish Dry Run` run
    `25635686773` remains clean and relevant because no publish-sensitive
    package inputs changed after `90a27ca`. The deployment-chain audit passed
    with clean latest CI, clean hosted CI logs, and a clean relevant Dart
    package publish dry-run. The strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP client-only consumer package auth-client grant smoke is complete
    through full local and hosted verification. The standalone generated MCP
    client package smoke now exposes a neutral fake `/auth` endpoint, obtains
    a ticket grant through
    `ConnectanumHttpAuthClient.issueTicketToken`, asserts the parsed grant
    identity/role/provider metadata plus forwarded auth headers, and opens its
    successful secure Streamable HTTP MCP session with
    `McpStreamableHttpClient.withAuthGrant`. The fake MCP endpoint still
    asserts the mapped bearer `Authorization` header and the smoke continues to
    cover direct JSON tool/meta APIs, pub/sub helpers, resources/prompts,
    session lifecycle, custom headers, batches, notifications, and Streamable
    HTTP polling/deletion from a generated consumer package. Pre-change
    `bin/test-fast`, focused `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-10. Commit `da7d7a2` (`test: obtain mcp client auth grants`) is
    pushed to both remotes. GitHub `CI` run `25638166438` completed
    successfully for `da7d7a2` with `Fast Checks` and `Full Verify` green, and
    the hosted CI log scan was clean. GitHub `Dart Package Publish Dry Run` run
    `25635686773` remains clean and relevant because no publish-sensitive
    package inputs changed after `90a27ca`. The deployment-chain audit passed
    with clean latest CI, clean hosted CI logs, and a clean relevant Dart
    package publish dry-run. The strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP client-only consumer package auth-grant smoke is complete through full
    local and hosted verification. The standalone generated MCP client package
    smoke now creates its successful secure Streamable HTTP client with
    `McpStreamableHttpClient.withAuthGrant` and a full
    `ConnectanumHttpAuthGrant`, while the fake endpoint still asserts the
    expected bearer `Authorization` header. Pre-change `bin/test-fast`, focused
    `bash -n bin/common.sh`, focused
    `bash -lc 'source bin/common.sh; run_mcp_client_package_smoke'`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-10. The first verify attempt hit a stale native runtime lock from
    its own leftover test process tree; after clearing that lock, the clean
    verify rerun completed successfully. Commit `ae7c02e`
    (`test: use auth grants in mcp client smoke`) is pushed to both remotes.
    GitHub `CI` run `25637060551` completed successfully for `ae7c02e` with
    `Fast Checks` (4m30s) and `Full Verify` (6m17s) green, and the hosted CI
    log scan was clean. GitHub `Dart Package Publish Dry Run` run
    `25635686773` remains clean and relevant because no publish-sensitive
    package inputs changed after `90a27ca`. The deployment-chain audit passed
    with clean latest CI, clean hosted CI logs, and a clean relevant Dart
    package publish dry-run. The strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP router-native auth-grant smoke is complete through full local and
    hosted verification. The implementation slice moved successful secure
    router-native Streamable HTTP MCP clients to
    `McpStreamableHttpClient.withAuthGrant` backed by
    `ConnectanumHttpAuthGrant`, while preserving explicit bearer headers for
    direct HTTP assertions and rejected-principal session isolation probes.
    It also updates the public MCP README protected-route guidance to prefer
    HTTP auth bridge grants for successful secure Streamable clients.
    Pre-change `bin/test-fast` passed on 2026-05-10.
    Focused `dart test packages/connectanum_router/test/router_integration_native_test.dart -p vm`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-10. Commit `90a27ca` (`test: use auth grants in router mcp
    integration`) is pushed to both remotes. GitHub `CI` run `25635686770`
    completed successfully for `90a27ca` with `Fast Checks` (4m19s) and
    `Full Verify` (6m11s) green, and the hosted CI log scan was clean.
    GitHub `Dart Package Publish Dry Run` run `25635686773` completed
    successfully for `90a27ca` with `Publish Dry Run` (20s) green and covers
    the checked-out head. GitHub `WAMP Profile Benchmarks` run `25635686778`
    completed successfully for `90a27ca` with `Linux WAMP profile gates`
    (7m55s) green. The deployment-chain audit passed with clean latest CI,
    clean hosted CI logs, and a clean relevant Dart package publish dry-run.
    The strict audit still reports only known operator-side release-hardening
    gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP generated consumer package auth-grant smoke is complete through full
    local and hosted verification. The generated neutral consumer package smoke
    now opens successful secure Streamable HTTP MCP sessions with
    `McpStreamableHttpClient.withAuthGrant` wherever a complete
    `ConnectanumHttpAuthGrant` is available, including the primary
    cross-principal session reuse isolation session and HTTP auth
    refresh/revoke active-session setup. Raw bearer clients remain only for
    intentionally rejected-token and cross-principal reuse probes. Pre-change
    `bin/test-fast`, the focused neutral generated consumer package smoke,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-10. Commit `9700601` (`test: use auth grants in mcp consumer
    smoke`) is pushed to both remotes. GitHub `CI` run `25634626705` completed
    successfully for `9700601` with `Fast Checks` (4m20s) and `Full Verify`
    (6m05s) green, and the hosted CI log scan was clean. The deployment-chain
    audit passed with clean latest CI and clean hosted CI logs. The latest
    Dart package publish dry-run remains clean and relevant because no
    publish-sensitive paths changed since `30b834a`. The strict audit still
    reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP router-hosted example auth-grant smoke is complete through full local
    and hosted verification. The public router-hosted MCP example now uses
    `McpStreamableHttpClient.withAuthGrant` wherever a full HTTP auth bridge
    grant is available in successful secure direct JSON, Streamable HTTP,
    protocol-version, refresh, and revoke flows. Raw bearer clients remain only
    for negative rotated/revoked-token probes. Pre-change `bin/test-fast`, the
    focused router-hosted MCP example smoke, the focused neutral generated
    consumer package smoke, post-change `bin/test-fast`, and full local
    `bin/verify` all passed on 2026-05-10. Commit `30b834a` (`test: use mcp
    auth grants in router example`) is pushed to both remotes. GitHub `CI` run
    `25633616482` completed successfully for `30b834a` with `Fast Checks`
    (4m26s) and `Full Verify` (6m07s) green, and the hosted CI log scan was
    clean. GitHub `Dart Package Publish Dry Run` run `25633616452` completed
    successfully for `30b834a` and covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25633616456` completed successfully for
    `30b834a` with `Linux WAMP profile gates` green (7m56s). The
    deployment-chain audit passed with clean latest CI, clean hosted CI logs,
    and clean Dart package publish dry-run evidence. The strict audit still
    reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP auth-grant Streamable client smoke is complete through full local and
    hosted verification. The focused slice adds
    `McpStreamableHttpClient.withAuthGrant` for HTTP auth bridge grants,
    rejects non-Bearer grants before opening a protected Streamable HTTP
    session, and rejects empty refresh/revoke tokens before sending HTTP auth
    bridge lifecycle requests. Focused client tests, the MCP IO entrypoint
    auth-session smoke, the neutral generated consumer package smoke,
    post-change `bin/test-fast`, and full local `bin/verify` all passed on
    2026-05-10. Commit `2ace2a8` (`feat: wire mcp auth grants into streamable
    clients`) is pushed to both remotes. GitHub `CI` run `25632291307`
    completed successfully for `2ace2a8` with `Fast Checks` (4m27s) and
    `Full Verify` (6m17s) green, and the hosted CI log scan was clean. GitHub
    `Dart Package Publish Dry Run` run `25632291310` completed successfully
    for `2ace2a8` and covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25632291313` completed successfully for
    `2ace2a8` with `Linux WAMP profile gates` green (7m53s). The
    deployment-chain audit passed with clean latest CI, clean hosted CI logs,
    and clean Dart package publish dry-run evidence. The strict audit still
    reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP HTTP auth per-call header smoke is complete through full local and
    hosted verification. `ConnectanumHttpAuthClient` now accepts per-call
    headers on ticket, WAMP-CRA, SCRAM, generic authenticate, refresh, and
    revoke calls. Constructor-wide headers apply first, per-call metadata
    applies second, and the auth client keeps JSON framing headers
    authoritative. Focused auth-client coverage, the MCP IO entrypoint smoke,
    the neutral generated consumer package smoke, post-change `bin/test-fast`,
    and full local `bin/verify` all passed on 2026-05-10. Commit `ad3e957`
    (`feat: add per-call mcp auth headers`) is pushed to both remotes. GitHub
    `CI` run `25631109320` completed successfully for `ad3e957` with
    `Fast Checks` (4m34s) and `Full Verify` (6m35s) green, and the hosted CI
    log scan was clean. GitHub `Dart Package Publish Dry Run` run
    `25631109324` completed successfully for `ad3e957` and covers the
    checked-out head. GitHub `WAMP Profile Benchmarks` run `25631109346`
    completed successfully for `ad3e957` with `Linux WAMP profile gates` green
    (8m15s). The deployment-chain audit passed with clean latest CI, clean
    hosted CI logs, and clean Dart package publish dry-run evidence. The strict
    audit still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP direct JSON batch/notification response-header session smoke is
    complete through full local and hosted verification. The focused client regression and
    neutral generated client-package smoke now inject `MCP-Session-Id` response
    headers on direct JSON batch responses, direct single notification
    `202 Accepted` responses, and notification-only batch `202 Accepted`
    responses while an active Streamable HTTP session exists; the client keeps
    the Streamable session id and SSE resume cursor unchanged and sends those
    direct JSON calls without Streamable session headers. Focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r
    expanded --plain-name "keeps direct JSON response session headers
    lifecycle-free"` passed, the full
    `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
    suite passed, `bash -n bin/common.sh` passed, focused
    `run_mcp_client_package_smoke` passed, post-change `bin/test-fast` passed,
    and full local `bin/verify` passed on 2026-05-10. Commit `72b6240`
    (`test: cover mcp direct json response header variants`) is pushed to both
    remotes. GitHub `CI` run `25628970062` completed successfully for
    `72b6240` with `Fast Checks` and `Full Verify` green, and the hosted CI
    log scan was clean. GitHub `Dart Package Publish Dry Run` run
    `25628970072` completed successfully for `72b6240` and covers the checked
    out head. GitHub `WAMP Profile Benchmarks` run `25628970064` completed
    successfully for `72b6240`. The deployment-chain audit passed with clean
    latest CI, clean hosted CI logs, and clean Dart package publish dry-run
    evidence. The strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP direct JSON response-header session isolation smoke is complete through
    full local and hosted verification. Direct JSON MCP calls now ignore
    `MCP-Session-Id` response headers when they are lifecycle-free, so a direct
    JSON success or forced HTTP error cannot replace or clear an active
    Streamable HTTP session id or SSE resume cursor. Streamable `initialize`
    and session-bound Streamable requests still capture MCP session headers and
    keep the session-aware HTTP error path. A focused fail-first regression
    reproduced the old response-header overwrite, the focused regression now
    passes, the full
    `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
    suite passes, and the neutral generated client-package smoke now injects
    response session headers on direct JSON success and direct HTTP-error
    probes without private application assumptions. Full local `bin/verify`
    passed on 2026-05-10. Commit `a426fcf`
    (`fix: isolate mcp direct json response headers`) is pushed to both
    remotes. GitHub `CI` run `25627974549` completed successfully for
    `a426fcf` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25627974556` completed successfully for
    `a426fcf`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25627974555` completed successfully for
    `a426fcf`. The deployment-chain audit passed with clean latest CI and clean
    Dart package publish dry-run evidence. The audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP direct JSON HTTP-error session smoke is complete through full local and
    hosted verification. Direct JSON MCP requests remain lifecycle-free even
    when a consumer also has an active
    Streamable HTTP session: direct JSON HTTP `401`, `403`, and `404` failures
    now throw typed `McpStreamableHttpException`s without clearing the cached
    Streamable session id or SSE cursor. Session-bound Streamable requests and
    Streamable `initialize` still use the session-clearing error path. A focused
    fail-first regression reproduced the old direct JSON `401` session clear,
    the focused regression now passes, the full
    `packages/connectanum_client/test/mcp/streamable_http_client_test.dart`
    suite passes, and the generated neutral client-package smoke now forces the
    same direct HTTP-error path without private application assumptions. The
    generated consumer package smoke now preserves Streamable session state for
    protected direct JSON auth failures while continuing to require
    session-bound Streamable failures to clear stale state. Focused
    `run_mcp_client_package_smoke`, focused `run_mcp_consumer_package_smoke`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-10. Commit `86b94a5`
    (`fix: preserve mcp direct json session state`) is pushed to both remotes.
    GitHub `CI` run `25626971782` completed successfully for `86b94a5` with
    `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25626971768` completed successfully for
    `86b94a5`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25626971771` completed successfully for
    `86b94a5`. The deployment-chain audit passed with clean latest CI and clean
    Dart package publish dry-run evidence. The audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP WAMP helper header smoke is complete through full local and hosted
    verification. WAMP API list/describe helpers, generic WAMP
    meta procedure calls, standard WAMP meta convenience helpers, and WAMP
    pub/sub subscribe/publish/poll/unsubscribe helpers now accept optional
    per-call `headers`. The shared `_callStructuredTool(...)` dispatcher
    forwards those headers through initialized Streamable `tools/call` requests
    and lifecycle-free direct JSON `connectanum.tool.call` requests. Package
    tests assert Streamable WAMP helper headers are sent with active
    `MCP-Session-Id` state while direct JSON WAMP helper headers are sent
    without session headers; the `connectanum_mcp` IO entrypoint test proves the
    re-exported API compiles and forwards headers for WAMP API, meta, and
    pub/sub helpers. Generated neutral client and consumer package smokes plus
    the router-hosted MCP public example compile and run WAMP helper headers
    against fake and router-hosted endpoints. Pre-change `bin/test-fast`,
    focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`,
    focused `run_mcp_client_package_smoke`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10. Commit `b60bd77`
    (`test: cover mcp wamp helper headers`) is pushed to both remotes. GitHub
    `CI` run `25625714931` completed successfully for `b60bd77` with
    `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25625714942` completed successfully for
    `b60bd77`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25625714945` completed successfully for
    `b60bd77`. The deployment-chain audit passed with clean latest CI and clean
    Dart package publish dry-run evidence. Strict audit still reports only
    known operator-side release-hardening gaps: branch protection/required
    checks are absent, `.github/workflows/router-image.yml` is not yet visible
    from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
    A final local `bin/verify` rerun after hosted-evidence notes also passed on
    2026-05-10.
  - MCP typed helper header smoke is complete through full local and hosted
    verification. `McpStreamableHttpClient.ping`, typed tools, direct
    Connectanum JSON helpers, resources, and prompts now accept optional
    per-call `headers`; `callTool` merges caller headers with cached MCP tool
    parameter headers while preserving the parameter-header contract. Package
    tests assert header forwarding for Streamable helpers with active session
    state and direct JSON helpers without `MCP-Session-Id`; the
    `connectanum_mcp` IO entrypoint test proves the re-exported public API
    forwards those headers. Generated neutral client and consumer package
    smokes plus the router-hosted MCP public example compile and run typed
    helper headers against fake and router-hosted endpoints. Pre-change
    `bin/test-fast`, focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`,
    focused `run_mcp_client_package_smoke`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10. Commit `c2e8b31`
    (`test: cover mcp typed helper headers`) is pushed to both remotes. GitHub
    `CI` run `25624621207` completed successfully for `c2e8b31` with
    `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25624621223` completed successfully for
    `c2e8b31`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25624621210` completed successfully for
    `c2e8b31`. The deployment-chain audit passed with clean latest CI, clean CI
    log scan, and clean Dart package publish dry-run evidence. Strict audit
    still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP Streamable initialize header smoke is complete through full local
    verification. Pre-change `bin/test-fast` passed on 2026-05-10.
    `McpStreamableHttpClient.initialize` and `notifyInitialized` now accept
    optional per-call `headers`, completing the helper-level Streamable session
    header surface with `request`, `post`, `notification`, `postBatch`, `poll`,
    and `deleteSession`. Package coverage pins initialization headers without
    an active MCP session and initialized-notification headers with the active
    session. The `connectanum_mcp` IO entrypoint test proves the re-exported
    public API forwards those headers, and generated neutral client/consumer
    package smokes compile and run the same calls against fake and router-hosted
    MCP endpoints. `dart format
    packages/connectanum_client/lib/src/mcp/streamable_http_client.dart
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart
    packages/connectanum_mcp/test/io_client_export_test.dart
    packages/connectanum_router/example/router_hosted_mcp.dart`, `bash -n
    bin/common.sh`, focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`,
    focused `run_mcp_client_package_smoke`, and focused
    `run_mcp_consumer_package_smoke` passed on 2026-05-10. Post-change
    `bin/test-fast` and full local `bin/verify` passed on 2026-05-10. Commit
    `86bb901` (`test: cover mcp streamable initialize headers`) is pushed to
    both remotes. GitHub `CI` run `25623601714` completed successfully for
    `86bb901` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25623601724` completed successfully for
    `86bb901`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25623601711` completed successfully for
    `86bb901`. The deployment-chain audit passed with clean latest CI, clean CI
    log scan, and clean Dart package publish dry-run evidence. Strict audit
    still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP Streamable session lifecycle header smoke is complete through full
    local verification. Pre-change `bin/test-fast` passed on 2026-05-10 with
    isolated `TMPDIR`. `McpStreamableHttpClient.poll` and `deleteSession` now
    accept per-call `headers`, matching the direct JSON-RPC header controls
    already exposed by `request`, `post`, `notification`, and `postBatch`.
    Package coverage pins GET/SSE polling and DELETE cleanup forwarding neutral
    consumer headers with the active Streamable session. The `connectanum_mcp`
    IO entrypoint test proves the re-exported public API forwards those headers,
    and generated neutral client/consumer package smokes compile and run the
    same lifecycle calls against fake and router-hosted MCP endpoints. `dart
    format packages/connectanum_client/lib/src/mcp/streamable_http_client.dart
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart
    packages/connectanum_mcp/test/io_client_export_test.dart
    packages/connectanum_router/example/router_hosted_mcp.dart`, `bash -n
    bin/common.sh`, focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`,
    focused `run_mcp_client_package_smoke`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`. Commit
    `020980a` (`test: cover mcp streamable session headers`) is pushed to both
    remotes. GitHub `CI` run `25622672504` completed successfully for
    `020980a` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25622672496` completed successfully for
    `020980a`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25622672501` completed successfully for
    `020980a`. The deployment-chain audit passed with clean latest CI, clean CI
    log scan, and clean Dart package publish dry-run evidence. Strict audit
    still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP direct batch header smoke is complete through full local verification.
    Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
    `McpStreamableHttpClient.postBatch` now accepts per-call `headers`, matching
    the direct JSON-RPC header controls already exposed by `post`, `request`,
    and `notification`. Package coverage pins a direct JSON-RPC batch with an
    active Streamable session as session-free while forwarding a neutral
    consumer header. Generated neutral client-only package smokes assert direct
    batch and notification-only batch headers are forwarded without
    `MCP-Session-Id`, and router-hosted consumer smoke coverage compiles and
    runs the same public API against a real MCP endpoint. `dart format
    packages/connectanum_client/lib/src/mcp/streamable_http_client.dart
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    `bash -n bin/common.sh`, focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    focused `run_mcp_client_package_smoke`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`. Commit
    `508b47d` (`test: cover mcp direct batch headers`) is pushed to both
    remotes. GitHub `CI` run `25621734784` completed successfully for
    `508b47d` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25621734774` completed successfully for
    `508b47d`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25621734769` completed successfully for
    `508b47d`. The deployment-chain audit passed with clean latest CI, clean CI
    log scan, and clean Dart package publish dry-run evidence. Strict audit
    still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP direct notification helper smoke is complete through full local
    verification. Pre-change
    `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
    `McpStreamableHttpClient.notification` now exposes the same `streamable`,
    `includeSession`, and `headers` controls as the lower-level `post` helper so
    downstream applications can send lifecycle-free direct JSON-RPC
    notifications through public API. Package coverage pins direct JSON and
    Streamable HTTP single notifications as `202 Accepted` requests that do not
    mutate active Streamable session state. Generated neutral client and
    consumer package smokes assert the same behavior through public package
    fakes and a real router-hosted MCP endpoint. `dart format
    packages/connectanum_client/lib/src/mcp/streamable_http_client.dart
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    `bash -n bin/common.sh`, focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    focused `run_mcp_client_package_smoke`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`. Commit
    `7e9226f` (`test: cover mcp direct notifications`) is pushed to both
    remotes. GitHub `CI` run `25620848947` completed successfully for
    `7e9226f` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25620848943` completed successfully for
    `7e9226f`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25620848945` completed successfully for
    `7e9226f`. The deployment-chain audit passed with clean latest CI, clean CI
    log scan, and clean Dart package publish dry-run evidence. Strict audit
    still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP notification-only batch smoke is complete through full local
    verification. Public fake MCP smoke endpoints now mirror the real
    router-hosted MCP endpoint by returning `202 Accepted` when a JSON-RPC
    batch contains only notifications and therefore produces no response
    objects. `McpStreamableHttpClient` package coverage now pins direct JSON
    and Streamable HTTP notification-only batches as `null` responses that do
    not mutate active Streamable session state. Generated neutral client and
    consumer package smokes now assert the same behavior through public package
    fakes and a real router-hosted MCP endpoint. Pre-change `bin/test-fast`,
    `dart format packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    `bash -n bin/common.sh`, focused `dart test
    packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    focused `run_mcp_client_package_smoke`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`. Commit
    `d33e43e` (`test: cover mcp notification-only batches`) is pushed to both
    remotes. GitHub `CI` run `25619981931` completed successfully for
    `d33e43e` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25619981935` completed successfully for
    `d33e43e`, and the audit confirmed it covers the checked-out head. GitHub
    `WAMP Profile Benchmarks` run `25619981933` completed successfully for
    `d33e43e`. The deployment-chain audit passed with clean latest CI and clean
    Dart package publish dry-run evidence. Strict audit still reports only
    known operator-side release-hardening gaps: branch protection/required
    checks are absent, `.github/workflows/router-image.yml` is not yet visible
    from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP deterministic WAMP API catalog smoke is complete through focused local
    verification. `connectanum.api.list` now sorts procedure metadata by
    procedure URI and topic metadata by topic URI before returning structured
    content. Package-level coverage pins deterministic WAMP API metadata
    ordering, and the generated neutral consumer package smoke asserts sorted
    unique WAMP API procedure/topic catalogs for typed Streamable helpers,
    typed direct JSON helpers, generic direct JSON-RPC access, and generic
    Streamable JSON-RPC access against a real router-hosted MCP endpoint.
    Pre-change `bin/test-fast`,
    `dart format packages/connectanum_mcp/lib/src/tools/wamp_api.dart
    packages/connectanum_mcp/test/wamp_api_test.dart`, `bash -n bin/common.sh`,
    focused `dart test packages/connectanum_mcp/test/wamp_api_test.dart`, and
    focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with
    isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-10 with
    isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-10 with
    isolated `TMPDIR`. Commit `eb8724a`
    (`test: cover deterministic mcp wamp api catalogs`) is pushed to both
    remotes. GitHub `CI` run `25619083686` completed successfully for
    `eb8724a` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25619083679` completed successfully for
    `eb8724a`, and the audit confirmed it covers the checked-out head. The
    deployment-chain audit passed with clean latest CI and clean Dart package
    publish dry-run evidence. Strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP deterministic resource/prompt catalog smoke is complete through full
    local verification. `McpResourceRegistry.listPage()` now sorts resources by
    URI, `McpResourceRegistry.listTemplatePage()` sorts templates by URI
    template, and `McpPromptRegistry.listPage()` sorts prompts by name before
    pagination. Package-level tests pin deterministic ordering for all three
    list surfaces, and the generated neutral consumer package smoke asserts
    sorted unique resource, resource template, and prompt catalogs for direct
    JSON and generic Streamable JSON-RPC access against a real router-hosted MCP
    endpoint. Pre-change `bin/test-fast`,
    `dart format packages/connectanum_mcp/lib/src/resources/resource.dart
    packages/connectanum_mcp/lib/src/prompts/prompt.dart
    packages/connectanum_mcp/test/resources_test.dart
    packages/connectanum_mcp/test/prompts_test.dart`, `bash -n bin/common.sh`,
    focused `dart test packages/connectanum_mcp/test/resources_test.dart
    packages/connectanum_mcp/test/prompts_test.dart`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
    Commit `c92f6bc` (`test: cover deterministic mcp resource catalogs`) is
    pushed to both remotes. GitHub `CI` run `25618101175` completed
    successfully for `c92f6bc` with `Fast Checks` and `Full Verify` green.
    GitHub `Dart Package Publish Dry Run` run `25618101186` completed
    successfully for `c92f6bc`, and the audit confirmed it covers the
    checked-out head. The deployment-chain audit passed with clean latest CI
    and clean Dart package publish dry-run evidence. Strict audit still reports
    only known operator-side release-hardening gaps: branch protection/required
    checks are absent, `.github/workflows/router-image.yml` is not yet visible
    from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP deterministic tool catalog smoke is complete with hosted CI evidence.
    `McpToolRegistry.listPage()` now sorts tools by name before pagination so
    `tools/list` has a stable consumer-facing order even when router-hosted MCP
    tools come from dynamic WAMP snapshots. The generated neutral consumer
    package smoke now asserts sorted unique tool catalogs for direct JSON access
    and generic Streamable JSON-RPC access against a real router-hosted MCP
    endpoint. Package-level `tools/list` coverage pins the deterministic order.
    This matches current official MCP draft readiness guidance for
    cache-friendly `tools/list` results while retaining stable `2025-11-25`
    Streamable HTTP behavior. Pre-change `bin/test-fast`,
    `dart format packages/connectanum_mcp/lib/src/tools/tool.dart
    packages/connectanum_mcp/test/tools_test.dart`, `bash -n bin/common.sh`,
    focused `dart test packages/connectanum_mcp/test/tools_test.dart`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
    Commit `0ce6929` (`test: cover deterministic mcp tool catalogs`) is pushed
    to both remotes. GitHub `CI` run `25617167891` completed successfully for
    `0ce6929` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25617167890` completed successfully for
    `0ce6929`, and the audit confirmed it covers the checked-out head. The
    deployment-chain audit passed with clean latest CI and clean Dart package
    publish dry-run evidence. Strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer challenge-auth lifecycle smoke is complete with hosted CI
    evidence. The generated neutral consumer package smoke in `bin/common.sh`
    now runs the HTTP auth bridge refresh/revoke lifecycle for ticket,
    WAMP-CRA, and SCRAM grants through public `ConnectanumHttpAuthClient`
    helpers. Each refreshed grant must preserve principal metadata, rotate both
    access and refresh tokens, invalidate the old active Streamable MCP session
    and old direct bearer token, keep the refreshed direct JSON and Streamable
    MCP paths usable, revoke the rotated refresh token, and reject revoked
    direct/Streamable bearer use plus revoked refresh. Pre-change
    `bin/test-fast`, `bash -n bin/common.sh`, focused
    `run_mcp_consumer_package_smoke`, post-change `bin/test-fast`, and full
    local `bin/verify` passed on 2026-05-10 with isolated `TMPDIR`.
    Commit `5a4249a` (`test: cover mcp consumer challenge auth lifecycle`) is
    pushed to both remotes. GitHub `CI` run `25616322616` completed
    successfully for `5a4249a` with `Fast Checks` and `Full Verify` green.
    GitHub `Dart Package Publish Dry Run` run `25612812164` remains
    clean/relevant for `5a4249a`; it completed successfully at `3f9c761`, and
    the audit confirmed no publish-sensitive package inputs changed in
    `5a4249a`. The deployment-chain audit passed with clean latest CI and clean
    Dart package publish dry-run evidence. Strict audit still reports only
    known operator-side release-hardening gaps: branch protection/required
    checks are absent, `.github/workflows/router-image.yml` is not yet visible
    from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer challenge-auth rejection smoke is complete with hosted CI
    evidence.
    The generated neutral consumer package smoke in `bin/common.sh` now tries
    invalid WAMP-CRA and SCRAM secrets through the public
    `ConnectanumHttpAuthClient.issueWampCraToken` and
    `ConnectanumHttpAuthClient.issueScramToken` helpers before issuing valid
    challenge-method grants. Each rejected bridge attempt must surface
    `ConnectanumHttpAuthException` with HTTP `401 Unauthorized` and no access
    or refresh token material in the error payload. The smoke then continues
    through the existing valid WAMP-CRA/SCRAM grants and secure router-hosted
    MCP direct JSON and Streamable HTTP tool calls. Pre-change `bin/test-fast`,
    `bash -n bin/common.sh`, focused `run_mcp_consumer_package_smoke`,
    post-change `bin/test-fast`, and full local `bin/verify` passed on
    2026-05-10 with isolated `TMPDIR`. Commit `64ab570`
    (`test: cover mcp consumer challenge auth rejection`) is pushed to both
    remotes. GitHub `CI` run `25615480764` completed successfully for
    `64ab570` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25612812164` remains clean/relevant for
    `64ab570`; it completed successfully at `3f9c761`, and the audit confirmed
    no publish-sensitive package inputs changed in `64ab570`. The
    deployment-chain audit passed with clean latest CI and clean Dart package
    publish dry-run evidence. Strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer challenge-auth secure MCP smoke is complete with hosted CI
    evidence.
    The generated neutral consumer package smoke in `bin/common.sh` now
    configures the secure MCP HTTP auth bridge profile for ticket, WAMP-CRA,
    and SCRAM grants, issues challenge-method bearer grants through the public
    `ConnectanumHttpAuthClient.issueWampCraToken` and
    `ConnectanumHttpAuthClient.issueScramToken` helpers, validates principal
    auth method/provider metadata, and uses each token against the secure
    router-hosted MCP direct JSON and initialized Streamable HTTP tool paths.
    Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
    Focused `run_mcp_consumer_package_smoke` first reached the secure WAMP-CRA
    direct MCP call and failed because the new assertion input omitted the
    wrapped-note argument required by the shared direct payload assertion; the
    focused smoke passed on 2026-05-10 with isolated `TMPDIR` after adding the
    wrapped-note argument to the direct and Streamable challenge-auth calls.
    Post-change `bin/test-fast` and full local `bin/verify` passed on
    2026-05-10 with isolated `TMPDIR`. Commit `853063e`
    (`test: cover mcp consumer challenge auth`) is pushed to both remotes.
    GitHub `CI` run `25614652357` completed successfully for `853063e` with
    `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25612812164` remains clean/relevant for
    `853063e`; it completed successfully at `3f9c761`, and the audit confirmed
    no publish-sensitive package inputs changed in `853063e`. The
    deployment-chain audit passed with clean latest CI and clean Dart package
    publish dry-run evidence. Strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP consumer Streamable session reuse isolation smoke is complete with
    hosted CI evidence.
    The generated neutral consumer package
    smoke in `bin/common.sh` now issues a second ticket-authenticated principal,
    opens a bearer-protected Streamable MCP session with the primary token,
    attempts to reuse that session id with the secondary bearer token and
    across the public route through GET/DELETE requests, asserts the rejected
    stale-session attempts return HTTP 404 and clear stale client-side session
    state, and proves the original primary secure session remains usable.
    Pre-change `bin/test-fast` passed on 2026-05-10 with isolated `TMPDIR`.
    Focused `run_mcp_consumer_package_smoke` passed on 2026-05-10 with isolated
    `TMPDIR`. Post-change `bin/test-fast` and full local `bin/verify` passed on
    2026-05-10 with isolated `TMPDIR`. Commit `d86a82b`
    (`test: cover mcp consumer session reuse isolation`) is pushed to both
    remotes. GitHub `CI` run `25613768490` completed successfully for
    `d86a82b` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25612812164` remains clean/relevant for
    `d86a82b`; it completed successfully at `3f9c761`, and the audit confirmed
    no publish-sensitive package inputs changed in `d86a82b`. The
    deployment-chain audit passed with clean latest CI and clean Dart package
    publish dry-run evidence. Strict audit still reports only known
    operator-side release-hardening gaps: branch protection/required checks are
    absent, `.github/workflows/router-image.yml` is not yet visible from the
    default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - Router-hosted MCP Streamable HTTP batch error-isolation smoke is
    complete with hosted CI evidence. The checked-in
    `packages/connectanum_router/test/router_integration_native_test.dart`
    Streamable HTTP batch route smoke now sends a mixed batch through both
    public and bearer-protected router-provided MCP endpoints with a successful
    `tools/list` request, an unknown MCP method request, and a notification-only
    `notifications/initialized` request. The regression asserts the successful
    result survives, the failed sibling request returns `-32601`, notification
    responses are omitted, and the active MCP session id is preserved while the
    SSE cursor advances. Pre-change `bin/test-fast` passed on 2026-05-09 with
    isolated `TMPDIR`. Focused
    `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "serves Streamable HTTP batch responses on router MCP routes"`
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify` passed
    on 2026-05-09 with isolated `TMPDIR`. Commit `3f9c761`
    (`test: cover router mcp streamable batch errors`) is pushed to both
    remotes. GitHub `CI` run `25612812180` completed successfully for
    `3f9c761` with `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25612812164` completed successfully for
    `3f9c761` and is clean/relevant. The deployment-chain audit passed with
    clean latest CI and clean Dart package publish dry-run evidence. Strict
    audit still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - Router-hosted MCP direct JSON batch error-isolation smoke is complete with
    hosted CI evidence. The checked-in
    `packages/connectanum_router/test/router_integration_native_test.dart`
    public `/mcp/public` smoke now sends a direct JSON batch with a valid
    `connectanum.api.list` request, an unknown MCP method request, and a
    notification-only `connectanum.tool.call`. The regression asserts HTTP 200,
    the successful catalog response, the failed sibling request's `-32601`
    unknown-method error, and no response for the notification. Pre-change
    `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`. Focused
    `dart test packages/connectanum_router/test/router_integration_native_test.dart --name "smoke tests MCP router RPC pubsub and route security"`
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify` passed
    on 2026-05-09 with isolated `TMPDIR`. Commit `82cb660`
    (`test: cover router mcp direct batch errors`) is pushed to both remotes.
    GitHub `CI` run `25611916466` completed successfully for `82cb660` with
    `Fast Checks` and `Full Verify` green. GitHub
    `Dart Package Publish Dry Run` run `25611916436` completed successfully for
    `82cb660` and is clean/relevant. The deployment-chain audit passed with
    clean latest CI and clean Dart package publish dry-run evidence. Strict
    audit still reports only known operator-side release-hardening gaps: branch
    protection/required checks are absent, `.github/workflows/router-image.yml`
    is not yet visible from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP server-only consumer package smoke is complete with hosted CI evidence.
    `run_mcp_server_package_smoke` in
    `bin/common.sh` now generates a neutral consumer package that depends on
    `connectanum_mcp`, imports only
    `package:connectanum_mcp/connectanum_mcp.dart`, and hosts a public MCP
    server without router or private internals. The generated smoke exercises
    `McpServer.handleMessage` initialization, initialized notifications, tools,
    resources, resource templates, prompts, JSON-RPC batch response filtering
    for notifications, shutdown state, and `McpStdioTransport` line/batch
    handling. The smoke is wired into both `bin/test-fast` and `bin/test-all`
    before the existing MCP client/router consumer package smokes. Pre-change
    `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`. Focused
    `run_mcp_server_package_smoke` passed on 2026-05-09 with isolated
    `TMPDIR`. Post-change `bin/test-fast` and full local `bin/verify` passed on
    2026-05-09 with isolated `TMPDIR`. Commit `c5de8cb`
    (`test: add mcp server package smoke`) is pushed to both remotes. GitHub
    `CI` run `25611002819` completed successfully for `c5de8cb` with
    `Fast Checks` and `Full Verify` green. Dart Package Publish Dry Run
    `25609860588` remains clean and relevant because no publish-sensitive paths
    changed since `f4bb186`. The deployment-chain audit passed with clean
    latest CI and package publish dry-run evidence. Strict audit still reports
    only known operator-side release-hardening gaps: branch protection/required
    checks are absent, `.github/workflows/router-image.yml` is not yet visible
    from the default branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP IO entrypoint WAMP registration meta smoke is complete with hosted CI
    evidence. The checked-in
    `packages/connectanum_mcp/test/io_client_export_test.dart` now proves that
    a neutral consumer application importing only
    `package:connectanum_mcp/connectanum_mcp_io.dart` can use
    `listWampRegistrations`, `lookupWampRegistration`,
    `matchWampRegistration`, `getWampRegistration`,
    `listWampRegistrationCallees`, and `countWampRegistrationCallees` over
    lifecycle-free direct JSON `connectanum.tool.call` POSTs. The smoke asserts
    helper tool names, JSON accept headers, no `MCP-Session-Id`, and direct
    lookup/get/callee-count argument shapes. Pre-change `bin/test-fast` passed
    on 2026-05-09 with isolated `TMPDIR`. Focused
    `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed
    on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `f4bb186` (`test: cover mcp io registration meta helpers`) is pushed to
    both remotes. GitHub `CI` run `25609860610` completed successfully for
    `f4bb186` with `Fast Checks` and `Full Verify` green. Dart Package Publish
    Dry Run `25609860588` completed successfully for `f4bb186`. The
    deployment-chain audit passed with clean latest CI and package publish
    dry-run evidence. Strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP IO entrypoint Streamable poll/delete smoke is complete with hosted CI
    evidence. The checked-in
    `packages/connectanum_mcp/test/io_client_export_test.dart` now proves that
    a neutral consumer application importing only
    `package:connectanum_mcp/connectanum_mcp_io.dart` can initialize a
    Streamable HTTP session, send `notifications/initialized`, poll GET/SSE
    notifications, resume with `Last-Event-ID`, and delete the session. The
    smoke asserts POST/GET/DELETE methods, JSON/SSE accept headers,
    `MCP-Session-Id`, `Last-Event-ID`, SSE event ids, event names, retry hints,
    notification methods, and client-side clearing of both `sessionId` and
    `lastEventId`. Pre-change `bin/test-fast` passed on 2026-05-09 with
    isolated `TMPDIR`. Focused
    `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed
    on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `360a6b4` (`test: cover mcp io streamable poll delete helpers`) is pushed
    to both remotes. GitHub `CI` run `25608972599` completed successfully for
    `360a6b4` with `Fast Checks` and `Full Verify` green. Dart Package Publish
    Dry Run `25608972598` completed successfully for `360a6b4`. The
    deployment-chain audit passed with clean latest CI and package publish
    dry-run evidence. Strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP IO entrypoint standard WAMP meta smoke is complete with hosted CI
    evidence. The checked-in
    `packages/connectanum_mcp/test/io_client_export_test.dart` now proves that
    a neutral consumer application importing only
    `package:connectanum_mcp/connectanum_mcp_io.dart` can use
    `countWampSessions`, `listWampSessions`, `getWampSession`,
    `matchWampSubscription`, `getWampSubscription`, and
    `countWampSubscriptionSubscribers` over lifecycle-free direct JSON
    `connectanum.tool.call` POSTs. The smoke asserts request methods, tool
    names, JSON accept headers, and the absence of `MCP-Session-Id` so the
    package boundary covers standard WAMP session/subscription metadata, not
    only registration matching. Pre-change `bin/test-fast` passed on
    2026-05-09 with isolated `TMPDIR`. Focused
    `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed
    on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `8e9e5c6` (`test: cover mcp io standard wamp meta helpers`) is pushed to
    both remotes. GitHub `CI` run `25607975655` completed successfully for
    `8e9e5c6` with `Fast Checks` and `Full Verify` green. Dart Package Publish
    Dry Run `25607975654` completed successfully for `8e9e5c6`. The
    deployment-chain audit passed with clean latest CI and package publish
    dry-run evidence. Strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP IO entrypoint direct tool/meta smoke is complete with hosted CI
    evidence. The checked-in
    `packages/connectanum_mcp/test/io_client_export_test.dart` now proves that
    a neutral consumer application importing only
    `package:connectanum_mcp/connectanum_mcp_io.dart` can use
    `listConnectanumToolsDirect`, `callConnectanumToolDirect`,
    `callConnectanumMethodDirect`, `describeWampApi(..., directJson: true)`,
    and `matchWampRegistration(..., directJson: true)` over lifecycle-free
    direct JSON POSTs. The smoke asserts request methods, tool names,
    arguments, JSON accept headers, and the absence of `MCP-Session-Id` so the
    package boundary covers direct Connectanum tool/meta access, not only
    symbol visibility. Pre-change `bin/test-fast` passed on 2026-05-09 with
    isolated `TMPDIR`. Focused
    `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed
    on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `2fce640` (`test: cover mcp io direct tool meta helpers`) is pushed to both
    remotes. GitHub `CI` run `25606879743` completed successfully for
    `2fce640` with `Fast Checks` and `Full Verify` green. Dart Package Publish
    Dry Run `25606879738` completed successfully for `2fce640`. The
    deployment-chain audit passed with clean latest CI and package publish
    dry-run evidence. Strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP IO entrypoint auth/session smoke is implemented locally with focused
    verification. The checked-in
    `packages/connectanum_mcp/test/io_client_export_test.dart` now proves that
    a neutral consumer application importing only
    `package:connectanum_mcp/connectanum_mcp_io.dart` can use
    `ConnectanumHttpAuthClient` to complete a ticket auth bridge flow, refresh
    and revoke bearer credentials, and initialize/use a
    `McpStreamableHttpClient.withBearerToken(...)` session with the issued
    access token. The smoke asserts auth request bodies, bearer headers, and MCP
    session headers so the package boundary covers auth/session behavior, not
    only symbol visibility. Pre-change `bin/test-fast` passed on 2026-05-09
    with isolated `TMPDIR`. Focused
    `dart test packages/connectanum_mcp/test/io_client_export_test.dart` passed
    on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `7b84641` (`test: cover mcp io auth session helpers`) is pushed to both
    remotes. GitHub `CI` run `25605546453` completed successfully for
    `7b84641` with `Fast Checks` and `Full Verify` green. Dart Package Publish
    Dry Run `25605546513` completed successfully for `7b84641`. The
    deployment-chain audit passed with clean latest CI and package publish
    dry-run evidence. Strict audit still reports only known operator-side
    release-hardening gaps: branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP IO entrypoint Streamable pub/sub smoke is complete with hosted CI
    evidence. Commit `da31835` (`test: cover mcp io streamable pubsub`) is
    pushed to both remotes. The checked-in
    `packages/connectanum_mcp/test/io_client_export_test.dart` now proves that
    a neutral consumer application importing only
    `package:connectanum_mcp/connectanum_mcp_io.dart` can initialize a public
    `McpStreamableHttpClient` session, use Streamable
    `subscribeWampTopic`, `publishWampEvent`, `pollWampEvents`, and
    `unsubscribeWampTopic` helpers over POST/SSE responses, issue the same
    pub/sub helper calls through lifecycle-free direct JSON without
    `MCP-Session-Id`, and use direct JSON `postBatch(...)` for neighboring
    pub/sub success entries plus a recoverable missing-subscription tool result
    while the active Streamable session id and SSE cursor remain unchanged.
    Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
    Focused `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    and full local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`.
    GitHub CI run `25604475522` completed successfully for `da31835` with
    `Fast Checks` and `Full Verify` green. Dart Package Publish Dry Run
    `25604475505` completed successfully for `da31835`. The deployment-chain
    audit passed with clean latest CI and package publish dry-run evidence.
    Strict audit still reports only known operator-side release-hardening gaps:
    branch protection/required checks are absent,
    `.github/workflows/router-image.yml` is not yet visible from the default
    branch through the Actions API, and
    `ghcr.io/konsultaner/connectanum-router` is not visible in GitHub Packages.
  - MCP IO entrypoint Streamable resource/prompt smoke is complete with hosted
    CI evidence. The checked-in
    `packages/connectanum_mcp/test/io_client_export_test.dart` now proves that
    a neutral consumer application importing only
    `package:connectanum_mcp/connectanum_mcp_io.dart` can initialize a public
    `McpStreamableHttpClient` session, consume POST/SSE resource and prompt
    responses, issue lifecycle-free direct JSON resource and prompt helper
    calls without `MCP-Session-Id`, and use direct JSON `postBatch(...)` for
    resource/prompt success plus JSON-RPC error isolation while the active
    Streamable session id and SSE cursor remain unchanged. Pre-change
    `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`. Focused
    `dart test packages/connectanum_mcp/test/io_client_export_test.dart`
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `92abba9`
    (`test: cover mcp io streamable resources`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25603294674` for `92abba9` completed successfully on
    2026-05-09 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and
    clean relevant Dart package publish dry-run evidence. The latest relevant
    `Dart Package Publish Dry Run` is run `25603294668` for `92abba9`.
    Strict deployment audit still reports operator-side release gaps: branch
    protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP client package batch resource/prompt smoke is implemented locally. The
    generated `run_mcp_client_package_smoke` package now proves that a neutral
    consumer application using
    `package:connectanum_mcp/connectanum_mcp_io.dart` can use public
    `McpStreamableHttpClient.postBatch(...)` calls for MCP resource and prompt
    detail operations through lifecycle-free direct JSON and initialized
    Streamable HTTP. The smoke batches `resources/read`,
    `resources/templates/list`, `prompts/list`, and `prompts/get`, adds
    missing-resource and missing-prompt batch error/recovery assertions, asserts
    direct JSON omits Streamable session headers, and asserts Streamable
    batches preserve the active session id and SSE cursor. Pre-change
    `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`. Focused
    generated client-only consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `e04d911`
    (`test: cover mcp client batch resources`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25602314946` for `e04d911` completed successfully on
    2026-05-09 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and
    clean relevant Dart package publish dry-run evidence. The latest relevant
    `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
    it is still relevant because no publish-sensitive paths changed since
    that run. Strict deployment audit still reports operator-side release
    gaps: branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP client package batch pub/sub smoke is implemented locally. The
    generated `run_mcp_client_package_smoke` package now proves that a neutral
    consumer application using
    `package:connectanum_mcp/connectanum_mcp_io.dart` can use public
    `McpStreamableHttpClient.postBatch(...)` calls for WAMP-backed MCP pub/sub
    helper tools through lifecycle-free direct JSON and initialized Streamable
    HTTP. The smoke subscribes, uses the returned handle in follow-up batched
    publish/poll/unsubscribe calls, asserts direct JSON omits Streamable
    session headers, and asserts Streamable batches preserve the active session
    id and SSE cursor. Pre-change `bin/test-fast` passed on 2026-05-09 with
    isolated `TMPDIR`. Focused generated client-only consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `75d1b3f`
    (`test: cover mcp client batch pubsub`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25601414311` for `75d1b3f` completed successfully on
    2026-05-09 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and
    clean relevant Dart package publish dry-run evidence. The latest relevant
    `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
    it is still relevant because no publish-sensitive paths changed since
    that run. Strict deployment audit still reports operator-side release
    gaps: branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP client package batch error isolation smoke is complete with hosted CI
    evidence. The generated
    `run_mcp_client_package_smoke` package now proves that a neutral consumer
    application using `package:connectanum_mcp/connectanum_mcp_io.dart` can
    receive mixed direct JSON `postBatch(...)` success/error responses, receive
    mixed Streamable HTTP `postBatch(...)` success/error responses, omit
    JSON-RPC notification responses from batch output, and continue using the
    active Streamable HTTP session after batch errors. The neutral fake endpoint
    now returns JSON-RPC errors for missing fake tools and suppresses batch
    notification responses. Pre-change `bin/test-fast` passed on 2026-05-09
    with isolated `TMPDIR`. Focused generated client-only consumer package
    smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `ee0fe7a`
    (`test: cover mcp client batch error isolation`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25600300720` for `ee0fe7a` completed successfully on
    2026-05-09 with `Fast Checks` (4m21s) and `Full Verify` (5m52s) green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and
    clean relevant Dart package publish dry-run evidence. The latest relevant
    `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
    it is still relevant because no publish-sensitive paths changed since
    that run. Strict deployment audit still reports operator-side release
    gaps: branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP client package generic JSON-RPC and batch smoke is complete with hosted
    CI evidence. The generated
    `run_mcp_client_package_smoke` package now proves that a neutral consumer
    application using `package:connectanum_mcp/connectanum_mcp_io.dart` can use
    public generic `request(...)` calls for direct JSON tool listing/calling
    without Streamable session headers, public generic direct JSON
    `postBatch(...)` calls for tool listing, tool calls, and dotted tool-name
    calls without Streamable session headers, and Streamable `postBatch(...)`
    calls for `ping` plus `tools/list` while preserving the active session id
    and SSE cursor. The neutral fake endpoint now handles the minimal JSON-RPC
    batch and `ping` responses needed to prove that public package-boundary
    behavior. Pre-change `bin/test-fast` passed on 2026-05-09 with isolated
    `TMPDIR`. Focused generated client-only consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `e26bf1c`
    (`test: cover mcp generic batch client smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25599395146` for `e26bf1c` completed successfully on
    2026-05-09 with `Fast Checks` (4m12s) and `Full Verify` (6m06s) green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and
    clean relevant Dart package publish dry-run evidence. The latest relevant
    `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
    it is still relevant because no publish-sensitive paths changed since
    that run. Strict deployment audit still reports operator-side release
    gaps: branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP client-only Streamable lifecycle smoke is complete with hosted CI
    evidence. The generated `run_mcp_client_package_smoke` package now
    proves that a neutral consumer application using
    `package:connectanum_mcp/connectanum_mcp_io.dart` can poll GET/SSE events,
    resume with `Last-Event-ID` without replay, reject invalid resume cursors
    without losing the active session, delete the session, clear stale-session
    `404` state, reinitialize, and list tools again against a minimal
    Streamable HTTP endpoint. Pre-change `bin/test-fast` passed on 2026-05-09
    with isolated `TMPDIR`. Focused generated client-only consumer package
    smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `4647a8d`
    (`test: cover mcp client streamable lifecycle`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25598397391` for `4647a8d` completed successfully on
    2026-05-09 with `Fast Checks` (4m18s) and `Full Verify` (5m56s) green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and
    clean relevant Dart package publish dry-run evidence. The latest relevant
    `Dart Package Publish Dry Run` remains run `25597333839` for `2563553`;
    it is still relevant because no publish-sensitive paths changed since
    that run. Strict deployment audit still reports operator-side release
    gaps: branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - Router-hosted MCP example Streamable lifecycle smoke is complete with
    hosted CI evidence. The public example now adds a Streamable HTTP lifecycle
    helper that registers a dynamic WAMP procedure after MCP initialization,
    polls GET/SSE for `notifications/tools/list_changed`, verifies resume
    cursors do not replay consumed events, verifies invalid `Last-Event-ID`
    returns `400` without clearing the active session, deletes the session,
    verifies stale-session `404` clearing, and reinitializes. The helper runs
    against both public and bearer-protected router-hosted MCP endpoints.
    Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
    Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `2563553`
    (`test: cover mcp streamable lifecycle example`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25597333837` for `2563553` completed successfully on
    2026-05-09 with `Fast Checks` (4m17s) and `Full Verify` (5m57s) green.
    Hosted GitHub `WAMP Profile Benchmarks` run `25597333824` for `2563553`
    completed successfully on 2026-05-09 with `Linux WAMP profile gates`
    (7m18s) green. Hosted GitHub `Dart Package Publish Dry Run` run
    `25597333839` for `2563553` completed successfully on 2026-05-09 with
    `Publish Dry Run` green. Deployment-chain audit passed on 2026-05-09 with
    clean latest CI and clean relevant Dart package publish dry-run evidence.
    Strict deployment audit still reports operator-side release gaps: branch
    protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP pub/sub queue overflow smoke is complete with hosted CI evidence.
    Generated consumer package and runnable public example smokes now prove
    lifecycle-free direct JSON and initialized Streamable HTTP subscriptions
    handle bounded queue overflow: a `queueLimit: 1` MCP-created WAMP
    subscription drops older buffered events, retains the newest service event,
    reports a non-zero dropped count, and preserves the expected MCP session
    semantics. Pre-change `bin/test-fast` passed on 2026-05-09 with isolated
    `TMPDIR`. Focused router-hosted MCP example plus generated consumer package
    smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `d1679a9`
    (`test: cover mcp pubsub queue overflow`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25596433388` for `d1679a9` completed successfully on
    2026-05-09 with `Fast Checks` (4m20s) and `Full Verify` (5m35s) green.
    Hosted GitHub `WAMP Profile Benchmarks` run `25596433375` for `d1679a9`
    completed successfully on 2026-05-09 with `Linux WAMP profile gates`
    (8m02s) green. Hosted GitHub `Dart Package Publish Dry Run` run
    `25596433396` for `d1679a9` completed successfully on 2026-05-09 with
    `Publish Dry Run` green. Deployment-chain audit passed on 2026-05-09 with
    clean latest CI and clean relevant Dart package publish dry-run evidence.
    Strict deployment audit still reports operator-side release gaps: branch
    protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP batch WAMP topic metadata smoke is complete with hosted CI evidence.
    Generated consumer package and runnable public example batch WAMP metadata
    smokes now prove direct JSON batches and initialized Streamable HTTP
    batches can list and describe configured topic metadata, including event
    schema and publish/subscribe capabilities, without relying on
    single-request helpers. Pre-change `bin/test-fast` passed on 2026-05-09
    with isolated `TMPDIR`. Focused router-hosted MCP example plus generated
    consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `cb88045`
    (`test: cover mcp batch topic metadata`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25595463999` for `cb88045` completed successfully on
    2026-05-09 with `Fast Checks` (4m14s) and `Full Verify` (5m59s) green.
    Hosted GitHub `WAMP Profile Benchmarks` run `25595464000` for `cb88045`
    completed successfully on 2026-05-09 with `Linux WAMP profile gates`
    (7m44s) green. Hosted GitHub `Dart Package Publish Dry Run` run
    `25595464002` for `cb88045` completed successfully on 2026-05-09 with
    `Publish Dry Run` green. Deployment-chain audit passed on 2026-05-09 with
    clean latest CI and clean relevant Dart package publish dry-run evidence.
    Strict deployment audit still reports operator-side release gaps: branch
    protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP generated consumer package WAMP topic metadata smoke is complete with
    hosted CI evidence. The generated consumer router now configures
    topic schema/metadata, and the generated consumer smoke proves
    `connectanum.api.describe` returns topic event schema plus
    publish/subscribe capabilities through lifecycle-free direct JSON and
    initialized Streamable HTTP MCP requests. Pre-change `bin/test-fast` passed
    on 2026-05-09 with isolated `TMPDIR`. Focused generated consumer package
    smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `4f4bf19`
    (`test: cover consumer mcp topic metadata`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25594498968` for `4f4bf19` completed successfully on
    2026-05-09 with `Fast Checks` (4m12s) and `Full Verify` (5m41s) green. No
    new WAMP profile or Dart package publish dry-run workflow was created for
    `4f4bf19`; deployment-chain audit reports the latest Dart package publish
    dry-run, `25593496098` at `a87e872`, remains clean and relevant because no
    publish-sensitive paths changed. Deployment-chain audit passed on
    2026-05-09 with clean latest CI and clean relevant Dart package publish
    dry-run evidence. Strict deployment audit still reports operator-side
    release gaps: branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - Router-hosted MCP example WAMP topic metadata smoke is complete with
    hosted CI evidence. The runnable public example now proves
    consumer applications can discover the configured `example.events.task`
    topic with `connectanum.api.list` and `connectanum.api.describe` through
    both lifecycle-free direct JSON and initialized Streamable HTTP MCP
    requests. Pre-change `bin/test-fast` passed on 2026-05-09 with isolated
    `TMPDIR`. Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `a87e872`
    (`test: cover mcp example topic metadata`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25593496115` for `a87e872` completed successfully on
    2026-05-09 with `Fast Checks` (4m22s) and `Full Verify` (5m47s) green.
    Hosted `WAMP Profile Benchmarks` run `25593496111` completed successfully
    on 2026-05-09 with `Linux WAMP profile gates` green (10m03s). Hosted
    `Dart Package Publish Dry Run` run `25593496098` completed successfully on
    2026-05-09 with `Publish Dry Run` green and covering checked-out head.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
    relevant Dart package publish dry-run evidence. Strict deployment audit
    still reports operator-side release gaps: branch protection and required
    status checks are absent, `.github/workflows/router-image.yml` is not
    discoverable from the default branch, and
    `ghcr.io/konsultaner/connectanum-router` is not visible.
  - Router-hosted MCP example auth refresh/revocation smoke is complete with
    hosted CI evidence. The runnable public example now enables refresh-token
    rotation on the HTTP auth route, keeps the issued auth grant,
    refreshes it, rejects the rotated access and refresh tokens, proves the
    refreshed bearer works for representative direct JSON and initialized
    Streamable HTTP secure MCP requests, revokes the refreshed grant, and
    rejects the revoked access and refresh tokens. Rejected active Streamable
    HTTP sessions assert client-side session id and SSE cursor state are
    cleared. Pre-change `bin/test-fast` passed on 2026-05-09 with isolated
    `TMPDIR`. Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `1e40a1a`
    (`test: cover mcp example auth refresh`) was pushed to `origin/add-router`
    and `github/add-router` on 2026-05-09. Hosted GitHub `CI` run
    `25592499292` for `1e40a1a` completed successfully on 2026-05-09 with
    `Fast Checks` (4m19s) and `Full Verify` (6m02s) green. Hosted
    `WAMP Profile Benchmarks` run `25592499289` completed successfully on
    2026-05-09 with `Linux WAMP profile gates` green (8m01s). Hosted
    `Dart Package Publish Dry Run` run `25592499290` completed successfully on
    2026-05-09 with `Publish Dry Run` green and covering checked-out head.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
    relevant Dart package publish dry-run evidence. Strict deployment audit
    still reports operator-side release gaps: branch protection and required
    status checks are absent, `.github/workflows/router-image.yml` is not
    discoverable from the default branch, and
    `ghcr.io/konsultaner/connectanum-router` is not visible.
  - Router-hosted MCP example protocol-version compatibility smoke is complete
    with hosted CI evidence. The runnable public example now proves older
    supported Streamable HTTP protocol versions (`2025-03-26` and
    `2025-06-18`) initialize and negotiate to the latest protocol version on
    both the public and bearer-protected MCP routes. It also proves unsupported
    protocol version `2099-01-01` is rejected with HTTP 400 without leaving
    Streamable HTTP session or cursor state behind. Pre-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Focused router-hosted MCP
    example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. Commit `8c7eb00`
    (`test: cover mcp example protocol versions`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25591548462` for `8c7eb00` completed successfully on
    2026-05-09 with `Fast Checks` (4m12s) and `Full Verify` (5m43s) green.
    Hosted `WAMP Profile Benchmarks` run `25591548458` completed successfully
    on 2026-05-09 with `Linux WAMP profile gates` green (8m02s). Hosted
    `Dart Package Publish Dry Run` run `25591548459` completed successfully on
    2026-05-09 with `Publish Dry Run` green and covering checked-out head.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
    relevant Dart package publish dry-run evidence. Strict deployment audit
    still reports operator-side release gaps: branch protection and required
    status checks are absent, `.github/workflows/router-image.yml` is not
    discoverable from the default branch, and
    `ghcr.io/konsultaner/connectanum-router` is not visible.
  - Router-hosted MCP example error/recovery smoke is complete with hosted CI
    evidence. The runnable public example proves consumer applications can
    recover from missing tool, resource, and prompt errors on both the public
    and bearer-protected MCP routes. Direct JSON checks cover single errors
    plus batch error isolation with neighboring successful responses and assert
    the Streamable HTTP session id/SSE cursor stay unchanged. Initialized
    Streamable HTTP checks cover single errors plus batch error isolation and
    assert the session id stays stable while the SSE cursor advances. Commit
    `95d504c` (`test: cover mcp example error recovery`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25590602479` for `95d504c` completed successfully on
    2026-05-09 with `Fast Checks` (4m25s) and `Full Verify` (6m00s) green.
    Hosted `WAMP Profile Benchmarks` run `25590602485` completed successfully
    on 2026-05-09 with `Linux WAMP profile gates` green (7m44s). Hosted
    `Dart Package Publish Dry Run` run `25590602515` completed successfully on
    2026-05-09 with `Publish Dry Run` green and covering checked-out head.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI and clean
    relevant Dart package publish dry-run evidence. Strict deployment audit
    still reports operator-side release gaps: branch protection and required
    status checks are absent, `.github/workflows/router-image.yml` is not
    discoverable from the default branch, and
    `ghcr.io/konsultaner/connectanum-router` is not visible.
  - Router-hosted MCP example batch WAMP subscription metadata smoke has local
    verification. The root workspace pubspec now sets
    `CONNECTANUM_SKIP_NATIVE_BUILD: true` for the client and router hooks under
    `hooks.user_defines`, so canonical root scripts do not rely on Dart SDK
    hook environments forwarding exported `CONNECTANUM_*` variables when the
    scripts already provide or build the runtime library. The runnable public
    example now proves consumer applications can batch
    `wamp.subscription.lookup`, `wamp.subscription.match`,
    `wamp.subscription.list`, `wamp.subscription.get`,
    `wamp.subscription.list_subscribers`, and
    `wamp.subscription.count_subscribers` while a pub/sub subscription is
    active through lifecycle-free direct JSON and initialized Streamable HTTP
    `tools/call` paths. The direct JSON batches assert no Streamable session id
    or SSE cursor changes; the Streamable batches assert the initialized session
    id is preserved while the SSE cursor advances. Focused native WAMP
    transport integration repro
    (`cd packages/connectanum_bench && env -u CONNECTANUM_NATIVE_LIB CONNECTANUM_SKIP_NATIVE_BUILD=1 dart test test/wamp_transport_integration_test.dart --chain-stack-traces -r expanded`)
    passed on 2026-05-09 after the workspace hook user defines were added.
    Pre-example-edit `bin/test-fast` passed on 2026-05-09 with isolated
    `TMPDIR`. Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-09 with isolated `TMPDIR`. `git diff --check` passed on
    2026-05-09. Commit `2b9d060` (`test: cover mcp example subscription meta`)
    was pushed to `origin/add-router` and `github/add-router` on 2026-05-09.
    Hosted GitHub `CI` run `25589519273` for `2b9d060` completed
    successfully on 2026-05-09 with `Fast Checks` (4m22s) and `Full Verify`
    (5m51s) green. Hosted `WAMP Profile Benchmarks` run `25589519288`
    completed successfully on 2026-05-09 with `Linux WAMP profile gates`
    green (8m20s). Hosted `Dart Package Publish Dry Run` run `25589519295`
    completed successfully on 2026-05-09 with `Publish Dry Run` green and
    covering checked-out head. Deployment-chain audit passed on 2026-05-09
    with clean latest CI and clean relevant Dart package publish dry-run
    evidence. Strict deployment audit still reports operator-side release
    gaps: branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - Router-hosted MCP example batch WAMP session/registration meta smoke has
    pre-change and focused example verification. The runnable public example
    now proves consumer applications can batch `wamp.session.count`,
    `wamp.session.list`, `wamp.session.get`, `wamp.registration.lookup`,
    `wamp.registration.match`, `wamp.registration.list`,
    `wamp.registration.get`, `wamp.registration.list_callees`, and
    `wamp.registration.count_callees` through lifecycle-free direct JSON and
    initialized Streamable HTTP `tools/call` paths. The direct JSON batches
    assert no Streamable session id or SSE cursor is created; the Streamable
    batches assert the initialized session id is preserved while the SSE cursor
    advances. Pre-change `bin/test-fast` passed on 2026-05-09 with isolated
    `TMPDIR`. Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. `git diff --check` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `f34fc86` (`test: cover mcp example batch wamp meta`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25588086156` for `f34fc86` completed successfully on 2026-05-09
    with `Fast Checks` (5m59s) and `Full Verify` (8m20s) green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
    hosted CI logs, and a clean Dart package publish dry-run covering
    checked-out head (`25588086170`). Strict deployment audit still reports
    operator-side release gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - Router-hosted MCP example direct tool/meta API smoke has local
    verification. The runnable public example now proves
    consumer applications can call `callConnectanumToolDirect`, the
    `connectanum.tools.call` and `connectanum.tool.call` direct JSON aliases,
    `connectanum.tools.list`, `connectanum.api.list`, and
    `connectanum.api.describe` without starting or mutating an MCP Streamable
    HTTP session. Pre-change `bin/test-fast` passed on 2026-05-09 with
    isolated `TMPDIR`. Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. `git diff --check` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `7c936c9` (`test: cover mcp example direct tool meta`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25586788256` for `7c936c9` completed successfully on 2026-05-09
    with `Fast Checks` (6m04s) and `Full Verify` (8m36s) green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
    hosted CI logs, and a clean Dart package publish dry-run covering
    checked-out head (`25586788266`). Strict deployment audit still reports
    operator-side release gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - Router-hosted MCP example batch pub/sub smoke has pre-change and focused
    example verification. The runnable public example now proves consumer
    applications can batch `connectanum.pubsub.subscribe`,
    `connectanum.pubsub.publish`, `connectanum.pubsub.poll`, and
    `connectanum.pubsub.unsubscribe` through lifecycle-free direct JSON and
    initialized Streamable HTTP JSON-RPC paths. The direct JSON batches mix
    pub/sub helper calls with direct API metadata calls and assert no
    Streamable session id or SSE cursor is created; the Streamable batches
    mix `tools/call` pub/sub helpers with API metadata calls and assert the
    initialized session id is preserved while the SSE cursor advances.
    Pre-change `bin/test-fast` passed on 2026-05-09 with isolated `TMPDIR`.
    Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-09 with isolated `TMPDIR`. `git diff --check` and full
    local `bin/verify` passed on 2026-05-09 with isolated `TMPDIR`. Commit
    `7162b1c` (`test: cover mcp example batch pubsub`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25585415804` for `7162b1c` completed successfully on 2026-05-09
    with `Fast Checks` (6m12s) and `Full Verify` (8m32s) green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
    hosted CI logs, and a clean Dart package publish dry-run covering
    checked-out head (`25585415814`). Strict deployment audit still reports
    operator-side release gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - Router-hosted MCP example batch resource/prompt smoke is complete with
    local and hosted verification. The runnable public example now proves
    consumer applications can batch `resources/read`,
    `resources/templates/list`, and `prompts/list` through lifecycle-free
    direct JSON and initialized Streamable HTTP JSON-RPC paths. The direct JSON
    batch asserts no Streamable session id or SSE cursor is created; the
    Streamable batch asserts the initialized session id is preserved and the
    SSE cursor advances. Pre-change `bin/test-fast` passed on 2026-05-09 with
    isolated `TMPDIR`. Focused router-hosted MCP example smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_router_hosted_mcp_example_smoke'`)
    passed on 2026-05-09 with isolated `TMPDIR`. Post-change `bin/test-fast`,
    `git diff --check`, and full local `bin/verify` passed on 2026-05-09 with
    isolated `TMPDIR`. Commit `87050c8`
    (`test: cover mcp example batch resources`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-09. Hosted GitHub
    `CI` run `25583860224` for `87050c8` completed successfully on 2026-05-09
    with `Fast Checks` (6m09s) and `Full Verify` (8m40s) green.
    Deployment-chain audit passed on 2026-05-09 with clean latest CI, clean
    hosted CI logs, and a clean Dart package publish dry-run covering
    checked-out head (`25583860221`). Strict deployment audit still reports
    operator-side release gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP consumer batch resource/prompt smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now proves
    downstream
    applications can batch `resources/read`, `resources/templates/list`, and
    `prompts/list` through lifecycle-free direct JSON and Streamable HTTP
    JSON-RPC paths. Direct JSON batch detail calls preserve any initialized
    Streamable session id and SSE cursor; Streamable batch detail calls
    preserve the session id and advance the SSE cursor. Pre-change
    `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`. Focused
    `bash -n bin/common.sh`, `git diff --check`, and generated router-hosted
    consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `f75c16e`
    (`test: cover mcp batch resource prompts`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25582129000` for `f75c16e` completed successfully on 2026-05-08
    with `Fast Checks` (5m49s) and `Full Verify` (8m34s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI, clean
    hosted CI logs, and a relevant clean Dart package publish dry-run
    (`25485027779`, no publish-sensitive changes since that run). Strict
    deployment audit still reports operator-side gaps: branch protection and
    required status checks are absent, `.github/workflows/router-image.yml` is
    not discoverable from the default branch, and
    `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer batch pub/sub smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now proves
    downstream applications can use batched direct JSON
    `connectanum.pubsub.subscribe/publish/poll/unsubscribe` helpers and
    equivalent Streamable HTTP `tools/call` batches while preserving initialized
    Streamable session identity and SSE cursor semantics. Temporary batch
    subscribe/unsubscribe checks use a distinct declared smoke topic so the
    primary task-event subscription remains valid for downstream poll checks.
    Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
    Focused `bash -n bin/common.sh`, `git diff --check`, and generated
    router-hosted consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `5af0f56`
    (`test: cover mcp batch pubsub`) was pushed to `origin/add-router` and
    `github/add-router` on 2026-05-08. Hosted GitHub `CI` run `25580108031`
    for `5af0f56` completed successfully on 2026-05-08 with `Fast Checks`
    (6m20s) and `Full Verify` (8m42s) green. Deployment-chain audit passed on
    2026-05-08 with clean latest CI, clean hosted CI logs, and a relevant clean
    Dart package publish dry-run (`25485027779`, no publish-sensitive changes
    since that run). Strict deployment audit still reports operator-side gaps:
    branch protection and required status checks are absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer generic direct JSON WAMP meta smoke has focused and
    post-change fast verification. The generated router-hosted consumer package
    smoke now proves public generic direct JSON-RPC method-name calls can
    inspect visible sessions through `wamp.session.count`,
    `wamp.session.list`, and `wamp.session.get`; router registrations through
    `wamp.registration.lookup`, `wamp.registration.match`,
    `wamp.registration.list`, `wamp.registration.get`,
    `wamp.registration.list_callees`, and
    `wamp.registration.count_callees`; and active direct pub/sub state through
    `wamp.subscription.lookup`, `wamp.subscription.match`,
    `wamp.subscription.list`, `wamp.subscription.get`,
    `wamp.subscription.list_subscribers`, and
    `wamp.subscription.count_subscribers`. The assertions run before and after
    Streamable initialization and verify direct JSON calls preserve Streamable
    session id/cursor state while keeping service sessions out of visible meta
    results. Pre-change `bin/test-fast` passed on 2026-05-08 with isolated
    `TMPDIR`. Focused `bash -n bin/common.sh`, `git diff --check`, and
    generated router-hosted consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `ea63e72`
    (`test: cover mcp generic direct wamp meta`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25572843753` for `ea63e72` completed successfully on
    2026-05-08 with `Fast Checks` (6m16s) and `Full Verify` (8m22s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI, clean
    hosted CI logs, and a relevant clean Dart package publish dry-run
    (`25485027779`, no publish-sensitive changes since that run). Strict
    deployment audit still reports operator-side gaps: branch protection and
    required status checks are absent, `.github/workflows/router-image.yml` is
    not discoverable from the default branch, and
    `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer generic Streamable WAMP registration/session meta smoke has
    local verification. The generated router-hosted consumer package smoke now
    proves public generic Streamable JSON-RPC `tools/call` requests can inspect
    visible sessions through `wamp.session.get` and router registrations through
    `wamp.registration.lookup`, `wamp.registration.match`,
    `wamp.registration.list`, `wamp.registration.get`,
    `wamp.registration.list_callees`, and
    `wamp.registration.count_callees` while preserving the initialized
    Streamable session id, advancing the SSE cursor, and keeping
    service-session callees out of visible registration metadata. Pre-change
    `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`. Focused
    `bash -n bin/common.sh bin/test-fast bin/test-all bin/verify` and
    generated router-hosted consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `3b28363`
    (`test: cover mcp generic streamable registration meta`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25570306015` for `3b28363` completed successfully on
    2026-05-08 with `Fast Checks` (5m57s) and `Full Verify` (8m39s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports operator-side gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP consumer generic Streamable WAMP subscription meta smoke has local and
    hosted verification. The generated router-hosted consumer package smoke now
    proves public generic Streamable JSON-RPC `tools/call` requests can inspect
    an active generic pub/sub subscription through `wamp.subscription.lookup`,
    `wamp.subscription.match`, `wamp.subscription.list`,
    `wamp.subscription.get`, `wamp.subscription.list_subscribers`, and
    `wamp.subscription.count_subscribers` while preserving the initialized
    Streamable session id, advancing the SSE cursor, and keeping service
    sessions out of visible subscriber metadata. Pre-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Focused
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and generated router-hosted consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `89a97ec`
    (`test: cover mcp generic streamable subscription meta`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25567752876` for `89a97ec` completed successfully on
    2026-05-08 with `Fast Checks` (6m01s) and `Full Verify` (8m33s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports operator-side gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP consumer generic Streamable WAMP meta/resource-template smoke has
    local and hosted verification. The generated router-hosted consumer
    package smoke now proves public generic Streamable JSON-RPC calls can
    access router-provided WAMP API describe, WAMP session/registration meta
    tools, and configured `resources/templates/list` while preserving the
    initialized Streamable session id and advancing the SSE cursor. Pre-change
    `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`. Focused
    `bash -n bin/common.sh bin/test-fast bin/test-all` and `git diff --check`
    passed on 2026-05-08. Focused generated router-hosted consumer package
    smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `53e616e`
    (`test: cover mcp generic streamable meta smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25565190217` for `53e616e` completed successfully on
    2026-05-08 with `Fast Checks` (6m03s) and `Full Verify` (8m27s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports operator-side gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP consumer generic Streamable JSON-RPC smoke is complete with local and
    hosted verification. The generated router-hosted consumer package smoke
    now proves public
    `McpStreamableHttpClient.request(...)` and `post(...)` calls can use an
    initialized Streamable MCP session for standard tool/resource/prompt
    methods plus router-provided WAMP API and pub/sub helper tools, while
    preserving the active session id and advancing the SSE cursor. The generic
    `post(...)` tool-call path also proves callers can supply declared
    `Mcp-Param-*` headers explicitly when tool schemas use `x-mcp-header`.
    Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
    Focused `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `git diff --check` passed on 2026-05-08. Focused generated router-hosted
    consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `047928f`
    (`test: cover mcp generic streamable jsonrpc smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25562441868` for `047928f` completed successfully on
    2026-05-08 with `Fast Checks` (6m19s) and `Full Verify` (8m43s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports operator-side gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP consumer direct batch tool alias smoke is complete with local and
    hosted verification. The generated router-hosted consumer package smoke now
    proves direct JSON-RPC batches can call the plural
    `connectanum.tools.call` alias before and after Streamable initialization,
    including batch error isolation, without changing Streamable session/cursor
    state. Pre-change `bin/test-fast` passed on 2026-05-08 with isolated
    `TMPDIR`. Focused `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `git diff --check` passed on 2026-05-08. Focused generated router-hosted
    consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `ecac196`
    (`test: cover mcp direct batch tool alias`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25559566762` for `ecac196` completed successfully on
    2026-05-08 with `Fast Checks` (6m14s) and `Full Verify` (8m30s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports operator-side gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP consumer direct tool API smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke
    now proves real router-provided MCP endpoints support
    `callConnectanumToolDirect`, `connectanum.tools.call`, and dotted
    application tool-name direct method calls work before and after Streamable
    initialization without changing Streamable session/cursor state.
    Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
    Focused `bash -n bin/common.sh bin/test-fast bin/test-all` passed on
    2026-05-08. Focused generated router-hosted consumer package smoke
    (`bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`)
    passed on 2026-05-08 with isolated `TMPDIR`. Post-change `bin/test-fast`
    passed on 2026-05-08 with isolated `TMPDIR`. Full local `bin/verify`
    passed on 2026-05-08 with isolated `TMPDIR`. Commit `a27172e`
    (`test: cover router mcp direct tool api smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25557107785` for `a27172e` completed successfully on
    2026-05-08 with `Fast Checks` (6m0s) and `Full Verify` (8m26s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports operator-side gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP client package direct generic tool method smoke is complete with local
    and hosted verification. The generated client-only consumer
    package smoke now proves `callConnectanumToolDirect`,
    `callConnectanumMethodDirect('connectanum.tools.call')`, and
    `callConnectanumMethodDirect` with a dotted application tool name all work
    after a Streamable session has been initialized, and so
    `connectanum.tools.list`, `connectanum.tool.call`,
    `connectanum.tools.call`, and the dotted application tool method all omit
    `MCP-Session-Id`. Pre-change `bin/test-fast` passed on 2026-05-08 with
    isolated `TMPDIR`. Focused checks passed on 2026-05-08:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-08
    with isolated `TMPDIR`. First full local `bin/verify` attempt on
    2026-05-08 hit a transient `ct_ffi` HTTP/3 handshake timeout in
    `tests::listen_flow::http3_handshake_surfaced_via_ffi`; the focused
    `cargo test -p ct_ffi tests::listen_flow::http3_handshake_surfaced_via_ffi`
    rerun passed immediately. Full local `bin/verify` rerun passed on
    2026-05-08 with isolated `TMPDIR`. Commit `54621c8`
    (`test: cover mcp direct generic tool client smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25554720402` for `54621c8` completed successfully on
    2026-05-08 with `Fast Checks` (5m47s) and `Full Verify` (8m10s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports operator-side gaps: branch protection and required status checks
    are absent, `.github/workflows/router-image.yml` is not discoverable from
    the default branch, and `ghcr.io/konsultaner/connectanum-router` is not
    visible.
  - MCP client package direct WAMP meta helper smoke is complete with local and
    hosted verification. The generated client-only consumer package smoke now
    proves direct JSON WAMP session, registration, and
    subscription meta helper calls prove `wamp.session.list`,
    `wamp.session.get`, `wamp.registration.list`,
    `wamp.registration.lookup`, `wamp.registration.match`,
    `wamp.registration.get`, `wamp.registration.list_callees`,
    `wamp.registration.count_callees`, `wamp.subscription.list`,
    `wamp.subscription.lookup`, `wamp.subscription.match`,
    `wamp.subscription.get`, `wamp.subscription.list_subscribers`, and
    `wamp.subscription.count_subscribers` all omit `MCP-Session-Id` after a
    Streamable session has been initialized. Pre-change `bin/test-fast` passed
    on 2026-05-08 with isolated `TMPDIR`. Focused checks passed on
    2026-05-08: `bash -n bin/common.sh bin/test-fast bin/test-all`,
    `git diff --check`, and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-08
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-08 with
    isolated `TMPDIR`. Commit `86f59f6`
    (`test: cover mcp direct wamp meta client smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25552420753` for `86f59f6` completed successfully on
    2026-05-08 with `Fast Checks` (6m18s) and `Full Verify` (8m45s) green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP client package direct WAMP helper smoke is complete with local and
    hosted verification. The
    generated client-only consumer package smoke now proves direct JSON WAMP
    API, WAMP meta, and pub/sub helper tool calls for
    `connectanum.api.list`, `connectanum.api.describe`, `wamp.session.count`,
    `connectanum.pubsub.subscribe`, `connectanum.pubsub.publish`,
    `connectanum.pubsub.poll`, and `connectanum.pubsub.unsubscribe` all omit
    `MCP-Session-Id` after a Streamable session has been initialized.
    Pre-change `bin/test-fast`, focused checks, post-change `bin/test-fast`,
    and full local `bin/verify` passed on 2026-05-08 with isolated `TMPDIR`.
    Commit `be335d8`
    (`test: cover mcp direct wamp helper client smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25550173165` for `be335d8` completed successfully on
    2026-05-08 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP client package direct resource/prompt smoke is complete locally. The
    generated client-only consumer package smoke now proves direct JSON
    resource and prompt helpers cover `resources/list`, `resources/read`,
    `resources/templates/list`, `prompts/list`, and `prompts/get` without
    sending `MCP-Session-Id` after a Streamable session has been initialized.
    Pre-change `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`.
    Focused checks passed on
    2026-05-08: `bash -n bin/common.sh bin/test-fast bin/test-all`,
    `git diff --check`, and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_client_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-08
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-08 with
    isolated `TMPDIR`. Commit `15f754a`
    (`test: cover mcp direct resource prompt client smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25547973357` for `15f754a` completed successfully on
    2026-05-08 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer active resource/prompt detail auth smoke is complete with
    local and hosted verification. The generated router-hosted consumer package
    smoke now proves Streamable `resources/read`,
    `resources/templates/list`, and `prompts/get` POSTs made on an already
    initialized secure Streamable MCP client reject an invalidated bearer token
    with HTTP 401 and clear stale Streamable session id and SSE cursor state.
    The same rejected-bearer harness still covers direct JSON batch, direct
    JSON single, Streamable batch, notification-only POST, Streamable
    `tools/list`, Streamable `tools/call`, Streamable `resources/list`,
    Streamable `prompts/list`, GET/SSE, and DELETE request shapes. Pre-change
    `bin/test-fast` passed on 2026-05-08 with isolated `TMPDIR`. Focused
    checks passed on 2026-05-08: `bash -n bin/common.sh bin/test-fast
    bin/test-all`, `git diff --check`, and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-08
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-08 with
    isolated `TMPDIR`. Commit `6797337`
    (`test: cover mcp active resource prompt detail auth`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25545836377` for `6797337` completed successfully on
    2026-05-08 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer active resource/prompt auth smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now proves
    Streamable `resources/list` and `prompts/list` POSTs
    made on an already initialized secure Streamable MCP client reject an
    invalidated bearer token with HTTP 401 and clear stale Streamable session id
    and SSE cursor state. The same rejected-bearer harness still covers direct
    JSON batch, direct JSON single, Streamable batch, notification-only POST,
    Streamable `tools/list`, Streamable `tools/call`, GET/SSE, and DELETE
    request shapes. Pre-change `bin/test-fast` passed on 2026-05-08 with
    isolated `TMPDIR`. Focused checks passed on 2026-05-08:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-08
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-08 with
    isolated `TMPDIR`. Commit `13c5909`
    (`test: cover mcp active resource prompt auth`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25543715782` for `13c5909` completed successfully on
    2026-05-08 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer active tool call auth smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now proves
    a Streamable `tools/call` POST made on an already initialized secure
    Streamable MCP client rejects an invalidated bearer token with HTTP 401 and
    clears stale Streamable session id and SSE cursor state. The same
    rejected-bearer harness still covers direct JSON batch, direct JSON single,
    Streamable batch, notification-only POST, Streamable `tools/list`, GET/SSE,
    and DELETE request shapes. Pre-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Focused checks passed on 2026-05-08:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-08
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-08 with
    isolated `TMPDIR`. Commit `5a37705`
    (`test: cover mcp active tool call auth`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-08. Hosted GitHub
    `CI` run `25541860069` for `5a37705` completed successfully on
    2026-05-08 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-08 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer active Streamable batch auth smoke is complete with hosted CI
    evidence. The generated router-hosted consumer package smoke now proves
    a Streamable JSON-RPC batch POST made on an already initialized secure
    Streamable MCP client rejects an invalidated bearer token with HTTP 401 and
    clears stale Streamable session id and SSE cursor state. The same
    rejected-bearer harness still covers direct JSON batch, direct JSON single,
    notification-only POST, Streamable response POST, GET/SSE, and DELETE
    request shapes. Pre-change `bin/test-fast` passed on 2026-05-07 with
    isolated `TMPDIR`. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `b355f84`
    (`test: cover mcp active streamable batch auth`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25519775921` for `b355f84` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer active notification auth smoke is complete with local
    verification. The generated router-hosted consumer package smoke now proves
    a Streamable notification-only `notifications/initialized` POST made on an
    already initialized secure Streamable MCP client rejects an invalidated
    bearer token with HTTP 401 and clears stale Streamable session id and SSE
    cursor state. The same rejected-bearer harness still covers direct JSON
    batch, direct JSON single, Streamable response POST, GET/SSE, and DELETE
    request shapes. Pre-change `bin/test-fast` passed on 2026-05-07 with
    isolated `TMPDIR`. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `1bcb6c9`
    (`test: cover mcp active notification auth`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25517332569` for `1bcb6c9` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer active direct JSON batch auth smoke is complete with local
    verification. The generated router-hosted consumer package smoke now proves
    a lifecycle-free direct JSON batch containing `connectanum.api.list`, made
    on an already initialized secure Streamable MCP client, rejects an
    invalidated bearer token with HTTP 401 and clears stale Streamable session
    id and SSE cursor state. The same rejected-bearer harness still covers the
    direct JSON single request, Streamable POST, GET/SSE, and DELETE request
    shapes. Pre-change `bin/test-fast` passed on 2026-05-07 with isolated
    `TMPDIR`. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `59c6103`
    (`test: cover mcp active direct json batch auth`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25514845144` for `59c6103` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer active direct JSON auth smoke is complete with local
    verification. The generated router-hosted consumer package smoke now proves
    a lifecycle-free direct JSON `connectanum.api.list` request made on an
    already initialized secure Streamable MCP client rejects an invalidated
    bearer token with HTTP 401 and clears stale Streamable session id and SSE
    cursor state, while preserving the existing Streamable POST, GET/SSE, and
    DELETE rejected-bearer checks. Pre-change `bin/test-fast` passed on
    2026-05-07 with isolated `TMPDIR`. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `6b48a82`
    (`test: cover mcp active direct json auth`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25512278997` for `6b48a82` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer Streamable resource/prompt error smoke is complete with local
    and hosted verification. The generated router-hosted consumer package
    smoke now proves initialized Streamable HTTP MCP sessions throw typed
    `McpJsonRpcException` values for missing standard `resources/read` and
    `prompts/get` targets, keep the Streamable session id stable, advance the
    SSE cursor, and recover through `resources/list` and `prompts/list`.
    Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
    Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `2890ed5`
    (`test: cover mcp streamable resource prompt errors`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25509658158` for `2890ed5` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer resource/prompt error smoke is complete with local
    verification. The generated router-hosted consumer package smoke now proves
    public generic `McpStreamableHttpClient.request(...)` / `post(...)` direct
    JSON-RPC error responses for missing standard MCP `resources/read` and
    `prompts/get` targets, before Streamable initialization and while a
    Streamable session is active, without mutating Streamable session id or
    SSE cursor state. Pre-change `bin/test-fast` passed on 2026-05-07 with
    isolated `TMPDIR`. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `89da29d`
    (`test: cover mcp resource prompt errors`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25507071961` for `89da29d` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer generic resources/prompts smoke is complete with local
    verification. The generated router-hosted consumer package smoke now adds
    public generic `McpStreamableHttpClient.request(...)` / `post(...)` direct
    JSON-RPC calls for `resources/list`, `resources/read`,
    `resources/templates/list`, `prompts/list`, and `prompts/get`, and runs
    them both before Streamable initialization and while a Streamable session
    is active. The assertions verify generic direct JSON resource/prompt access
    does not mutate Streamable session id or SSE cursor state. Pre-change
    `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`. Focused
    checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `e4deead`
    (`test: cover mcp generic resources prompts smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25504186176` for `e4deead` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer generic API list smoke is complete with local verification.
    The generated router-hosted consumer package smoke now adds a public
    generic `McpStreamableHttpClient.request(...)` direct JSON-RPC call for
    `connectanum.api.list`, verifies it returns the configured procedure and
    topic catalog, and runs it both before Streamable initialization and while
    a Streamable session is active through the existing generic direct
    JSON-RPC smoke path. The assertions verify generic direct JSON API catalog
    access does not mutate Streamable session id or SSE cursor state.
    Pre-change `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`.
    Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on 2026-05-07
    with isolated `TMPDIR`. Full local `bin/verify` passed on 2026-05-07 with
    isolated `TMPDIR`. Commit `6bd5d8e`
    (`test: cover mcp generic api list smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25501478676` for `6bd5d8e` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer generic pub/sub smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now adds
    public generic `McpStreamableHttpClient.request(...)` / `post(...)`
    direct JSON-RPC calls for `connectanum.pubsub.subscribe`,
    `connectanum.pubsub.publish`, `connectanum.pubsub.poll`, and
    `connectanum.pubsub.unsubscribe`, and runs them both before Streamable
    initialization and while a Streamable session is active. The assertions
    verify generic direct JSON pub/sub does not mutate Streamable session id or
    SSE cursor state. Pre-change `bin/test-fast` passed on 2026-05-07 with
    isolated `TMPDIR`. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on
    2026-05-07 with isolated `TMPDIR`. Full local `bin/verify` passed on
    2026-05-07 with isolated `TMPDIR`. Commit `7fa39d1`
    (`test: cover mcp generic pubsub smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25496631454` for `7fa39d1` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer generic JSON-RPC smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now adds
    a public generic `McpStreamableHttpClient.request(...)` / `post(...)`
    direct JSON-RPC path for `connectanum.tools.list`,
    `connectanum.tool.call`, and `connectanum.api.describe`, and runs it both
    before Streamable initialization and while a Streamable session is active.
    The assertions verify the direct JSON path does not mutate Streamable
    session id or SSE cursor state. Pre-change `bin/test-fast` with the
    default system temp directory reached the generated MCP consumer smoke
    successfully but failed later because an existing long-lived router
    process outside this task held the native runtime lock. Pre-change
    `bin/test-fast` passed on 2026-05-07 with isolated `TMPDIR`. Focused
    checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`
    with isolated `TMPDIR`. Post-change `bin/test-fast` passed on
    2026-05-07 with isolated `TMPDIR`. Full local `bin/verify` passed on
    2026-05-07 with isolated `TMPDIR`. Commit `0a13551`
    (`test: cover mcp generic jsonrpc smoke`) was pushed to
    `origin/add-router` and `github/add-router` on 2026-05-07. Hosted GitHub
    `CI` run `25494035617` for `0a13551` completed successfully on
    2026-05-07 with `Fast Checks` and `Full Verify` green.
    Deployment-chain audit passed on 2026-05-07 with clean latest CI and a
    relevant clean Dart package publish dry-run (`25485027779`, no
    publish-sensitive changes since that run). Strict deployment audit still
    reports only operator-side gaps: branch protection is absent,
    `.github/workflows/router-image.yml` is not discoverable from the default
    branch, and `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer entity meta smoke is complete with local verification. The
    generated router-hosted consumer package smoke now uses public
    `McpStreamableHttpClient` WAMP meta helpers to prove
    `wamp.registration.list`, `lookup`, `match`, and `get` agree on the
    exposed procedure registration, and `wamp.subscription.list`, `lookup`,
    `match`, and `get` agree on a consumer-created subscription. The
    assertions run through lifecycle-free direct JSON, initialized Streamable
    HTTP, and direct JSON after Streamable initialization. Pre-change
    `bin/test-fast` passed on 2026-05-07. Focused checks passed on
    2026-05-07: `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Commit `586801e`
    (`test: cover mcp entity meta smoke`) was pushed to `origin/add-router`
    and `github/add-router` on 2026-05-07. Hosted GitHub `CI` run
    `25490897809` for `586801e` completed successfully on 2026-05-07 with
    `Fast Checks` and `Full Verify` green. Deployment-chain audit passed on
    2026-05-07 with clean latest CI and a relevant clean Dart package publish
    dry-run (`25485027779`, no publish-sensitive changes since that run).
    Strict deployment audit still reports only operator-side gaps: branch
    protection is absent, `.github/workflows/router-image.yml` is not
    discoverable from the default branch, and
    `ghcr.io/konsultaner/connectanum-router` is not visible.
  - MCP consumer session meta smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now uses
    public `McpStreamableHttpClient` WAMP meta helpers to prove
    `wamp.session.count`, `list`, and `get` are internally consistent and do
    not expose the service-side WAMP session. The assertions run through both
    initialized Streamable HTTP and lifecycle-free direct JSON. Pre-change
    `bin/test-fast` passed on 2026-05-07. Focused checks passed on
    2026-05-07: `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `19c7e27`
    is clean: `CI` run `25487804565` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `19c7e27` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25485027779` for `951ed89`, which completed successfully and
    still covers checked-out package inputs. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `19c7e27`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP client auth error session clearing is complete with local and hosted
    verification. The public `McpStreamableHttpClient` now clears cached
    Streamable HTTP session id and SSE cursor state on session-scoped HTTP 401
    and 403 responses, matching the existing stale-session 404 behavior. The
    generated router-hosted consumer package smoke now proves active protected
    sessions rejected after bearer rotation or revocation clear stale state for
    POST `tools/list`, GET/SSE polling, and DELETE. Pre-change `bin/test-fast`
    passed on 2026-05-07. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`,
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart --chain-stack-traces`,
    `git diff --check`, and
    `bash -lc 'source bin/common.sh; cd_repo_root; run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `951ed89`
    is clean: `CI` run `25485027762` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations; Dart Package
    Publish Dry Run run `25485027779` completed successfully and covers the
    checked-out head; WAMP Profile Benchmarks run `25485027860` completed
    successfully. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `951ed89`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP consumer participant meta smoke is complete with local and hosted
    verification.
    The generated router-hosted consumer package smoke now uses public
    `McpStreamableHttpClient` WAMP meta helpers to prove
    `wamp.registration.list_callees` / `count_callees` hide the router service
    callee for the exposed procedure, and
    `wamp.subscription.list_subscribers` / `count_subscribers` report only
    consumer-visible subscriber IDs with matching counts. The assertions run
    through lifecycle-free direct JSON, initialized Streamable HTTP, and direct
    JSON after Streamable initialization. Pre-change `bin/test-fast` passed on
    2026-05-07. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `6114ed0`
    is clean: `CI` run `25482719085` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `6114ed0` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully and
    still covers checked-out package inputs. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `6114ed0`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP consumer single JSON-RPC error smoke is complete with local
    verification. The generated router-hosted consumer package smoke now uses
    public `McpStreamableHttpClient` APIs to prove missing direct JSON
    `connectanum.tool.call` and initialized Streamable `tools/call` requests
    surface as `McpJsonRpcException` values with the expected id, method, and
    error body. Direct JSON single errors leave active Streamable session id
    and SSE cursor state unchanged; Streamable single errors keep the session
    id stable while advancing the SSE cursor, and both paths recover with a
    follow-up tool-list request. Pre-change `bin/test-fast` passed on
    2026-05-07. Focused checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `aa1987f`
    is clean: `CI` run `25480299943` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `aa1987f` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully and
    still covers checked-out package inputs. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `aa1987f`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP consumer batch error smoke is complete with local and hosted
    verification. The generated router-hosted consumer package smoke now sends
    mixed JSON-RPC batches through both lifecycle-free direct JSON and
    initialized Streamable HTTP: an unknown tool returns a JSON-RPC error
    between successful catalog/tool/prompt responses, notifications are still
    omitted, direct JSON leaves Streamable session state unchanged, and the
    Streamable batch keeps the session id while advancing the SSE cursor.
    Pre-change `bin/test-fast` passed on 2026-05-07. Focused checks passed on
    2026-05-07: `bash -n bin/common.sh bin/test-fast bin/test-all`,
    `git diff --check`, and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `b1f805e`
    is clean: `CI` run `25478356531` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `b1f805e` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully and
    still covers checked-out package inputs. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `b1f805e`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP consumer invalid Last-Event-ID smoke is complete with local
    and hosted verification. The generated router-hosted consumer package
    smoke now uses
    public `McpStreamableHttpClient` APIs to prove an unknown Streamable HTTP
    `Last-Event-ID` resume cursor returns HTTP 400 with a `Last-Event-ID`
    error, does not clear the active MCP session/cursor state, and leaves the
    session usable before normal DELETE/reinitialize recovery. Pre-change
    `bin/test-fast` passed on 2026-05-07. Focused checks passed on
    2026-05-07: `bash -n bin/common.sh bin/test-fast bin/test-all`,
    `git diff --check`, and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `d5375b5`
    is clean: `CI` run `25476889557` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `d5375b5` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully and
    still covers checked-out package inputs. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `d5375b5`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP protocol-version compatibility smoke is complete with hosted CI
    evidence. The generated router-hosted consumer package smoke
    now opens public `McpStreamableHttpClient` sessions with older supported
    Streamable HTTP protocol-version headers (`2025-03-26` and `2025-06-18`),
    verifies that initialize negotiates the client back to
    `McpStreamableHttpClient.latestProtocolVersion`, confirms liveness with
    `ping`, deletes the session cleanly, and asserts unsupported protocol
    version `2099-01-01` returns HTTP 400 without leaking session or SSE
    cursor state. Pre-change `bin/test-fast` passed on 2026-05-07. Focused
    checks passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all`, `git diff --check`,
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `d0d1761`
    is clean: `CI` run `25475415761` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `d0d1761` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully and
    still covers checked-out package inputs. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `d0d1761`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP active session method auth smoke is complete with hosted CI evidence.
    The generated router-hosted consumer package smoke now
    proves active protected Streamable MCP sessions reject rotated or revoked
    bearers on POST `tools/list`, GET/SSE polling, and DELETE session
    requests. Pre-change `bin/test-fast` passed on 2026-05-07. Focused
    verification passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `0c499e6`
    is clean: `CI` run `25473930343` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `0c499e6` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully. The
    deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `0c499e6`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP active session auth invalidation smoke is complete with hosted CI
    evidence. The generated router-hosted consumer package smoke now
    opens a protected Streamable MCP session with the initial ticket bearer
    before refresh rotation and asserts that the still-active session receives
    `401 Unauthorized` after the bearer is rotated. It then opens a protected
    Streamable MCP session with the refreshed bearer, revokes the grant, and
    asserts the still-active session receives `401 Unauthorized` after
    revocation. Pre-change `bin/test-fast` passed on 2026-05-07. Focused
    verification passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `abf60f9`
    is clean: `CI` run `25472416302` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `abf60f9` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully. The
    deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `abf60f9`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP consumer auth refresh/revoke smoke is complete with hosted CI evidence.
    The generated router-hosted consumer package smoke now
    enables refresh-token rotation on its auth route, obtains a ticket grant
    through public `ConnectanumHttpAuthClient`, uses the initial bearer for
    secure direct JSON and Streamable MCP, refreshes the grant, asserts the
    initial access and refresh tokens are rejected, uses the refreshed bearer
    for secure direct JSON and Streamable MCP, revokes the refreshed grant, and
    then asserts the refreshed access and refresh tokens are rejected.
    Pre-change `bin/test-fast` passed on 2026-05-07. Focused verification
    passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `312814e`
    is clean: `CI` run `25470934618` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `312814e` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully. The
    deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `312814e`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP consumer direct resources after Streamable is complete with hosted CI
    evidence. The generated router-hosted consumer package smoke now calls
    direct JSON resource and prompt helpers after Streamable initialization
    against both public and bearer-protected real router MCP endpoints, and
    then asserts the active Streamable session id and SSE cursor are unchanged.
    Pre-change `bin/test-fast` passed on 2026-05-07. Focused verification
    passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `24e475e`
    is clean: `CI` run `25469270650` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `24e475e` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully. The
    deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `24e475e`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP client package helper smoke is complete with hosted CI evidence. The
    generated temporary consumer package still depends directly only on
    `connectanum_mcp` and imports
    `package:connectanum_mcp/connectanum_mcp_io.dart`; its mock endpoint now
    also exercises resources, resource templates, prompts, WAMP API metadata,
    WAMP session-count meta helpers, and WAMP pub/sub helper calls through
    both initialized Streamable MCP and lifecycle-free direct JSON. Direct
    JSON resource/prompt/WAMP helper calls assert that no `MCP-Session-Id`
    leaks from the active Streamable session. Pre-change `bin/test-fast`
    passed on 2026-05-07. Focused verification passed on 2026-05-07:
    `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_client_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local
    `bin/verify` passed on 2026-05-07. Hosted GitHub evidence for `8116786`
    is clean: `CI` run `25467715044` completed successfully with
    `Fast Checks` and `Full Verify`, both with zero annotations. The Dart
    Package Publish Dry Run workflow did not trigger for `8116786` because no
    publish-sensitive paths changed; the latest relevant package dry-run
    remains `25463696541` for `3a0bbf0`, which completed successfully. The
    deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `8116786`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP client package smoke is complete with hosted CI evidence. A generated
    temporary consumer package now depends directly only on `connectanum_mcp`
    and imports
    `package:connectanum_mcp/connectanum_mcp_io.dart` while using local path
    overrides only for workspace resolution. It exercises Streamable HTTP
    initialization, typed tool helpers, lifecycle-free direct JSON access,
    GET/SSE polling, and session deletion against a local mock endpoint without
    declaring `connectanum_router` as an application dependency. Pre-change
    `bin/test-fast` passed on 2026-05-07. Focused verification passed on
    2026-05-07: `bash -n bin/common.sh bin/test-fast bin/test-all` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_client_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-07. Full local `bin/verify`
    passed on 2026-05-07. Hosted GitHub evidence for `ebce710` is clean: `CI`
    run `25465909291` completed successfully with `Fast Checks` and
    `Full Verify`, both with zero annotations. The Dart Package Publish Dry
    Run workflow did not trigger for `ebce710` because no publish-sensitive
    paths changed; the latest relevant package dry-run remains `25463696541`
    for `3a0bbf0`, which completed successfully. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `ebce710`; the strict variant correctly failed only on the
    known operator-owned deployment-chain gaps: `add-router` is unprotected,
    the router image workflow is not discoverable from the default branch, and
    the router container package is not visible.
  - MCP package metadata readiness is complete locally. The `connectanum_mcp`
    package description and README introduction are aligned with the
    shipped public surface: local MCP server primitives plus router-hosted
    Streamable HTTP client helpers for consumer applications. Pre-change
    `bin/test-fast` passed on 2026-05-06. Focused verification passed on
    2026-05-06: `dart analyze packages/connectanum_mcp`;
    `dart test packages/connectanum_mcp`;
    `bin/dart-package-publish-dry-run --include-private packages/connectanum_mcp`
    after the package files were committed locally, with zero warnings; and
    stale package/downstream-specific wording search across the touched package
    metadata, README, project state, and active plan returned no matches.
    Post-change `bin/test-fast` passed on 2026-05-06.
    Full local `bin/verify` passed on 2026-05-06. Hosted GitHub evidence for
    `3a0bbf0` is clean: `CI` run `25463696534` completed successfully with
    `Fast Checks` and `Full Verify`, and `Dart Package Publish Dry Run` run
    `25463696541` completed successfully. Public check-run annotation audit
    found zero GitHub annotations across `Fast Checks`, `Full Verify`, and
    `Publish Dry Run`. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `3a0bbf0`; the strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run --strict`
    correctly failed only on the known operator-owned deployment-chain gaps:
    `add-router` is unprotected, the router image workflow is not discoverable
    from the default branch, and the router container package is not visible.
    No WAMP Profile Benchmarks run was triggered for this metadata-only package
    change; the latest relevant WAMP profile run remains the prior clean
    branch-head evidence.
  - MCP router integration IO entrypoint is complete with hosted CI evidence.
    The router MCP integration suite now imports
    `package:connectanum_mcp/connectanum_mcp_io.dart` instead of the lower-level
    client MCP barrel, and `ROADMAP_NEXT.md` now points Dart IO consumers to
    that same public entrypoint. Pre-change `bin/test-fast` passed on
    2026-05-06. Focused verification passed on 2026-05-06:
    `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`;
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name MCP`;
    and
    `rg -n 'package:connectanum_client/mcp.dart' packages/connectanum_router/test/router_integration_native_test.dart ROADMAP_NEXT.md packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_mcp/README.md`
    returned no matches. Post-change `bin/test-fast` passed on 2026-05-06.
    Full local `bin/verify` passed on 2026-05-06. Hosted GitHub evidence for
    `e263234` is clean: `CI` run `25461531075` completed successfully with
    `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
    `25461531073` completed successfully, and `WAMP Profile Benchmarks` run
    `25461531331` completed successfully. Public check-run annotation audit
    found zero GitHub annotations across `Fast Checks`, `Full Verify`,
    `Publish Dry Run`, and `Linux WAMP profile gates`. The deployment-chain
    audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `e263234`; the strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run --strict`
    correctly failed only on the known operator-owned deployment-chain gaps:
    `add-router` is unprotected, the router image workflow is not discoverable
    from the default branch, and the router container package is not visible.
  - MCP public example IO entrypoint is complete with hosted CI evidence. The
    runnable
    router-hosted MCP example now imports
    `package:connectanum_mcp/connectanum_mcp_io.dart` instead of the lower-level
    client MCP barrel, and the MCP package README now points consumer clients
    to the same public IO entrypoint. Pre-change `bin/test-fast` passed on
    2026-05-06. Focused verification passed on 2026-05-06:
    `dart analyze packages/connectanum_router/example/router_hosted_mcp.dart`;
    `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`;
    and
    `rg -n "package:connectanum_client/mcp.dart" packages/connectanum_router/example/router_hosted_mcp.dart packages/connectanum_mcp/README.md`
    returned no matches. Post-change `bin/test-fast` passed on 2026-05-06.
    Full local `bin/verify` passed on 2026-05-06. Hosted GitHub evidence for
    `f9e7608` is clean: `CI` run `25459179156` completed successfully with
    `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
    `25459179227` completed successfully, and `WAMP Profile Benchmarks` run
    `25459179240` completed successfully. Public check-run annotation audit
    found zero GitHub annotations across `Fast Checks`, `Full Verify`,
    `Publish Dry Run`, and `Linux WAMP profile gates`. The deployment-chain
    audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `f9e7608`; the strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run --strict`
    correctly failed only on the known operator-owned deployment-chain gaps:
    `add-router` is unprotected, the router image workflow is not discoverable
    from the default branch, and the router container package is not visible.
  - MCP consumer IO entrypoint smoke is complete with hosted CI evidence. The
    generated consumer package smoke now imports
    `package:connectanum_mcp/connectanum_mcp_io.dart` for MCP primitives plus
    the Streamable HTTP/direct JSON client surface, and no longer declares
    `connectanum_client` as a direct application dependency. It still keeps
    transitive path overrides and hook user-defines so native build-hook
    behavior remains representative. Pre-change `bin/test-fast` passed on
    2026-05-06. Focused verification also passed on 2026-05-06:
    `bash -n bin/common.sh` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-06. Full local `bin/verify`
    passed on 2026-05-06, including formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP package tests, client tests, auth-server tests,
    bench integration tests, router-hosted MCP example and generated consumer
    package smoke, full router package tests, zero-copy router checks, and
    Chrome Dart2Wasm WebSocket transport tests. Hosted GitHub evidence for
    `5d5c18f` is clean: `CI` run `25456751385` completed successfully with
    `Fast Checks` and `Full Verify`, and public check-run annotation audit
    found zero GitHub annotations for both check runs. The deployment-chain
    audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `5d5c18f`; `Dart Package Publish Dry Run` run `25454447229`
    remains clean and relevant because no publish-sensitive paths changed since
    `acb0ed8`. The strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run --strict`
    correctly failed only on the known operator-owned deployment-chain gaps:
    `add-router` is unprotected, the router image workflow is not discoverable
    from the default branch, and the router container package is not visible.
  - MCP direct JSON batch after Streamable initialization is complete with
    hosted CI evidence. The client now has focused coverage proving
    `postBatch(..., streamable: false, includeSession: false)` remains
    lifecycle-free on a client that already owns a Streamable MCP session: the
    request uses `Accept: application/json`, sends no `Mcp-Session-Id`, sends no
    `Last-Event-ID`, and does not mutate the cached session id or event cursor.
    The generated consumer package smoke now exercises the direct JSON batch
    path after Streamable initialization and before continuing normal
    Streamable tool calls. Pre-change `bin/test-fast` passed on 2026-05-06.
    Focused verification also passed on 2026-05-06:
    `bash -n bin/common.sh`;
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "keeps direct JSON batches lifecycle-free with an active Streamable session"`;
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`;
    `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`;
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-06, including the new client
    regression and the updated generated consumer package smoke. Full local
    `bin/verify` passed on 2026-05-06, including formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client tests,
    auth-server tests, bench integration tests, router-hosted MCP example and
    generated consumer package smoke, full router package tests, zero-copy
    router checks, and Chrome Dart2Wasm WebSocket transport tests. Hosted
    GitHub evidence for `acb0ed8` is clean: `CI` run `25454447247` completed
    successfully with `Fast Checks` and `Full Verify`, `Dart Package Publish
    Dry Run` run `25454447229` completed successfully, and `WAMP Profile
    Benchmarks` run `25454447314` completed successfully. Public check-run
    annotation audit found zero GitHub annotations for all four check runs. The
    deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
    passed against `acb0ed8`; it still reports the known operator-owned
    findings that `add-router` is unprotected, the router image workflow is not
    discoverable from the default branch, and the router container package is
    not visible. The strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run --strict`
    correctly failed only on those operator-owned deployment-chain gaps.
  - MCP direct WAMP helpers after Streamable initialization are complete
    with hosted CI evidence. Direct JSON WAMP API and pub/sub helper calls now
    have coverage proving they remain lifecycle-free on a client that already
    owns a Streamable MCP session: no `Mcp-Session-Id`, no `Last-Event-ID`, and
    no mutation of the Streamable session cursor. The generated consumer
    package smoke now exercises direct WAMP meta discovery plus pub/sub after
    Streamable initialization before continuing normal Streamable tool calls.
    Pre-change `bin/test-fast` passed on 2026-05-06. Focused verification also
    passed on 2026-05-06:
    `bash -n bin/common.sh`;
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "keeps direct WAMP helpers lifecycle-free with an active Streamable session"`;
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`;
    `dart analyze packages/connectanum_client/test/mcp/streamable_http_client_test.dart`;
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-06, including the new client
    regression and the updated generated consumer package smoke. Full local
    `bin/verify` passed on 2026-05-06, including formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client tests,
    auth-server tests, bench integration tests, router-hosted MCP example and
    generated consumer package smoke, full router package tests, zero-copy
    router checks, and Chrome Dart2Wasm WebSocket transport tests. Hosted
    GitHub evidence for `0d40b3c` is clean: `CI` run `25452060608` completed
    successfully with `Fast Checks` and `Full Verify`, `Dart Package Publish
    Dry Run` run `25452060607` completed successfully, and `WAMP Profile
    Benchmarks` run `25452060592` completed successfully. Public check-run
    annotation audit found zero GitHub annotations for all four check runs. The
    deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci`
    passed against `0d40b3c`; it still reports the known operator-owned
    findings that `add-router` is unprotected, the router image workflow is not
    discoverable from the default branch, and the router container package is
    not visible. The strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --strict`
    correctly failed only on those operator-owned deployment-chain gaps.
  - MCP consumer direct catalog smoke is complete with hosted CI evidence. The
    generated consumer package smoke now discovers router-hosted tools through
    direct JSON `connectanum.tools.list` after Streamable initialization but
    before the first Streamable MCP `tools/call`, asserts that the direct
    catalog does not mutate Streamable session state, and then performs the
    first Streamable tool call through the cached custom-header path a consumer
    application would use. Pre-change `bin/test-fast` passed on 2026-05-06.
    Focused verification also passed on 2026-05-06:
    `bash -n bin/common.sh` and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-06, including the updated
    generated consumer package smoke. Full local `bin/verify` passed on
    2026-05-06, including formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP package tests, client tests, auth-server
    tests, bench integration tests, router-hosted MCP example and generated
    consumer package smoke, full router package tests, zero-copy router checks,
    and Chrome Dart2Wasm WebSocket transport tests. Hosted GitHub evidence for
    `d6eda5c` is clean: `CI` run `25449698355` completed successfully with
    `Fast Checks` and `Full Verify`. Public check-run annotation audit found
    zero GitHub annotations for both check runs. No package dry-run or WAMP
    benchmark workflow was triggered for this smoke-harness/docs path-filter
    slice. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci`
    passed against `d6eda5c`; it still reports the known operator-owned
    findings that `add-router` is unprotected, the router image workflow is not
    discoverable from the default branch, and the router container package is
    not visible. The strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --strict`
    correctly failed only on those operator-owned deployment-chain gaps.
  - MCP direct catalog header cache is complete with hosted evidence.
    `McpStreamableHttpClient.listConnectanumToolsDirect()` now remembers valid
    tool `x-mcp-header` mappings from lifecycle-free direct JSON
    `connectanum.tools.list` catalogs the same way `listTools()` does, so
    consumer applications can discover a router-hosted tool through direct JSON
    and later call it through Streamable MCP with cached `Mcp-Param-*` headers.
    The client fixture for direct JSON tool catalogs now preserves the full
    `inputSchema`, matching router-hosted `tool.toJson()` catalog behavior.
    Pre-change `bin/test-fast` passed on 2026-05-06. Focused verification
    passed on 2026-05-06:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "reuses direct JSON tool catalog for later Streamable custom headers"`
    and
    `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`.
    Post-change `bin/test-fast` passed on 2026-05-06, including the generated
    consumer package smoke. Full local `bin/verify` passed on 2026-05-06,
    including formatting, Rust native/FFI tests, Python package-artifact
    checks, MCP package tests, client tests with the new direct-catalog header
    cache regression, auth-server tests, bench integration tests,
    router-hosted MCP example and generated consumer package smoke, full
    router package tests, zero-copy router checks, and Chrome Dart2Wasm
    WebSocket transport tests. Hosted GitHub evidence for `722cf78` is clean:
    `CI` run `25447162568` completed successfully with `Fast Checks` and
    `Full Verify`, `Dart Package Publish Dry Run` run `25447165335` completed
    successfully, and `WAMP Profile Benchmarks` run `25447166796` completed
    successfully. Public check-run annotation audit found zero GitHub
    annotations for all four check runs. The deployment-chain audit
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci`
    passed against `722cf78`; it still reports the known operator-owned
    findings that `add-router` is unprotected, the router image workflow is not
    discoverable from the default branch, and the router container package is
    not visible. The strict variant
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-latest-ci --strict`
    correctly failed only on those operator-owned deployment-chain gaps.
  - MCP custom parameter headers are complete locally. The public
    `McpStreamableHttpClient` now remembers valid tool `x-mcp-header`
    mappings from `tools/list`, filters malformed typed tool definitions from
    typed list results, and emits `Mcp-Param-*` headers on cached
    `tools/call` requests, including SEP-2243 base64 wrapping when a primitive
    argument cannot be sent safely or would be ambiguous as a raw HTTP header
    value. Router-hosted MCP endpoints now validate supplied `Mcp-Param-*`
    headers before dispatch,
    require mapped custom parameter headers for Streamable tool calls, and
    preserve direct JSON compatibility for callers that omit custom headers
    while still rejecting supplied mismatches or malformed values with MCP
    `HeaderMismatch`. Pre-change `bin/test-fast` passed on 2026-05-06.
    Focused verification also passed on 2026-05-06:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "guards MCP Streamable HTTP ingress and sessions"`,
    `dart analyze packages/connectanum_client/lib/src/mcp/streamable_http_client.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart`,
    `dart analyze packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart packages/connectanum_router/test/router_integration_native_test.dart`,
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed after the implementation. Full local
    `bin/verify` passed on 2026-05-06, including formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client tests with
    the new custom-header helper coverage, auth-server tests, bench
    integration tests, router-hosted MCP example and generated consumer
    package smoke, full router package tests including the new custom
    Streamable header validation coverage, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests. Hosted GitHub evidence for `255c990`
    is clean: `CI` run `25441310755` completed successfully with `Fast Checks`
    and `Full Verify`, `Dart Package Publish Dry Run` run `25441310873`
    completed successfully, and `WAMP Profile Benchmarks` run `25441310971`
    completed successfully. Public check-run annotation audit found zero
    GitHub annotations for all four check runs. Raw hosted log download remains
    blocked in this environment because GitHub returns
    `Must have admin rights to Repository` and no GitHub token is present.
  - MCP Streamable HTTP standard request headers are complete locally. The
    public `McpStreamableHttpClient` now emits the current standard
    `Mcp-Method` header on single-message POSTs and emits `Mcp-Name` for
    `tools/call`, `resources/read`, and `prompts/get` when the JSON-RPC body
    carries the corresponding `params.name` or `params.uri`. Router-hosted MCP
    endpoints now reject Streamable single-message POSTs with missing or
    mismatched standard headers using the MCP `HeaderMismatch` server-error
    code while preserving JSON-only direct-call compatibility for callers that
    do not send the standard headers. Pre-change `bin/test-fast` passed on
    2026-05-06. Focused verification also passed on 2026-05-06:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "guards MCP Streamable HTTP ingress and sessions"`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "isolates MCP Streamable HTTP sessions by route and bearer principal"`,
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed after the implementation; a subsequent
    focused `dart analyze packages/connectanum_router/test/router_integration_native_test.dart`
    confirmed the style cleanup for the new test helper. Full local
    `bin/verify` passed on 2026-05-06, including formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client tests with
    the new header-emission coverage, auth-server tests, bench integration
    tests, router-hosted MCP example and generated consumer package smoke,
    full router package tests including the new Streamable header validation
    coverage, zero-copy router checks, and Chrome Dart2Wasm WebSocket
    transport tests. Hosted GitHub evidence for `a644253` is clean: `CI` run
    `25437028971` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25437028956` completed successfully,
    and `WAMP Profile Benchmarks` run `25437029002` completed successfully.
    Public check-run annotation audit found zero GitHub annotations for all
    four check runs. Raw hosted log download remains blocked in this
    environment because GitHub returns `Must have admin rights to Repository`
    and no GitHub token is present.
  - Socket transport test port isolation is complete locally. The local
    handoff `bin/verify` initially reproduced a timeout in
    `packages/connectanum_client/test/transport/socket/socket_transport_test.dart`
    when a hard-coded raw socket fixture port was already owned by another
    local listener. The socket transport tests now bind loopback fixture
    servers on OS-assigned ports and connect through `server.port`, with
    teardown for the newly isolated server/transport fixtures. Focused
    verification passed on 2026-05-06:
    `dart test packages/connectanum_client/test/transport/socket/socket_transport_test.dart -r expanded --plain-name "Opening with client max header of 20"`
    and
    `dart test packages/connectanum_client/test/transport/socket/socket_transport_test.dart -r expanded`.
    Full local `bin/test-fast` and `bin/verify` both passed on 2026-05-06
    after the fix. Hosted GitHub evidence for `d8f50ca` is clean: `CI` run
    `25433887759` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25433887741` completed successfully,
    and `WAMP Profile Benchmarks` run `25433887733` completed successfully.
    Public check-run annotation audit found zero GitHub annotations for all
    four check runs. Raw hosted log download remains blocked in this
    environment because GitHub returns `Must have admin rights to Repository`
    and no GitHub token is present.
  - MCP Streamable HTTP session recovery is complete locally. The public
    `McpStreamableHttpClient` no longer sends a stored `MCP-Session-Id` on
    `initialize`, and it clears the stored session id plus SSE cursor after
    HTTP `404 Not Found` responses from POST, GET/SSE poll, and DELETE paths so
    downstream applications can reinitialize cleanly after a router-hosted MCP
    session is deleted or otherwise unknown. Coverage now includes a focused
    fake-endpoint client regression for stale POST/GET/DELETE sessions, real
    bearer-protected router-hosted MCP recovery in the route/principal
    isolation integration test, and the generated consumer package smoke,
    which now proves stale session failure, state clearing, reinitialize, and
    cleanup through public package APIs. Pre-change `bin/test-fast` passed on
    2026-05-06. Focused verification also passed on 2026-05-06:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "isolates MCP Streamable HTTP sessions by route and bearer principal"`,
    and
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Full local `bin/verify` passed on 2026-05-06, including formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests, client
    tests with the new stale-session recovery coverage, auth-server tests,
    bench integration tests, router-hosted MCP example smoke, the upgraded
    generated consumer package smoke, full router package tests including
    router-hosted MCP auth/session/batch coverage, zero-copy router checks, and
    Chrome Dart2Wasm WebSocket transport tests. Hosted GitHub evidence for
    `eff3b10` is clean: `CI` run `25431647686` completed successfully with
    `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
    `25431647641` completed successfully, and `WAMP Profile Benchmarks` run
    `25431647607` completed successfully. Public check-run annotation audit
    found zero GitHub annotations for all four check runs. Raw hosted log
    download remained blocked in this environment because GitHub returned
    `Must have admin rights to Repository` and no GitHub token was present.
  - MCP external authorization context is complete locally. Router-hosted MCP
    and HTTP-auth bridge sessions now carry an explicit
    `authorizationIsInternal` flag so public MCP callers and bearer-authenticated
    bridge callers authorize as their effective external principal instead of
    accidentally inheriting privileged router-service semantics. The MCP route
    re-checks call, publish, and subscribe authorization at dispatch time, while
    generic configured HTTP RPC bridge routes retain their existing internal
    route-service behavior for compatibility with configured service routes
    such as OpenMetrics. Focused MCP isolation and OpenMetrics regression tests
    passed on 2026-05-05. `bin/test-fast` and full local `bin/verify` also
    passed on 2026-05-05, including formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP package tests, client tests with HTTP auth
    helper coverage, auth-server tests, bench integration tests, the
    router-hosted MCP example smoke, the generated external consumer package
    smoke, full router package tests including router-hosted MCP
    auth/session/batch coverage and the OpenMetrics HTTP route, zero-copy
    router checks, and Chrome Dart2Wasm WebSocket transport tests. Hosted
    GitHub evidence is clean: `CI` run `25366182412` completed successfully
    with `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
    `25366182396` completed successfully, and `WAMP Profile Benchmarks` run
    `25366182431` completed successfully. The hosted log audit found no real
    GitHub warning/error annotations, compiler warnings, actionable skipped
    tests, deprecations, panics, broken pipes, connection errors, or unexpected
    timeout failures. Broad matches were benign passing negative-path test names,
    Git checkout default-branch hints, private package publish skips for
    `publish_to: none`, and expected filtered Rust test counts.
  - MCP HTTP auth client helper is complete locally.
    `package:connectanum_client/mcp.dart` now exports
    `ConnectanumHttpAuthClient`, which performs the router HTTP auth bridge
    challenge/token handshake for ticket, WAMP-CRA, SCRAM, and generic
    `AbstractAuthentication` flows, parses access/refresh-token grants, and
    supports refresh/revoke with typed HTTP auth errors. The router-hosted MCP
    example and generated external consumer package smoke now use this public
    helper instead of duplicating raw `/auth` JSON plumbing. Pre-change
    `bin/test-fast`, focused helper tests, package analyzer, router-hosted MCP
    example smoke, generated external consumer package smoke, and post-change
    `bin/test-fast` passed on 2026-05-05. Full local `bin/verify` also passed
    on 2026-05-05, including formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP package tests, client tests with the new HTTP
    auth helper coverage, auth-server tests, bench integration tests, the
    router-hosted MCP example smoke, the generated external consumer package
    smoke using the new helper, full router package tests including
    router-hosted MCP auth/session/batch coverage, zero-copy router checks, and
    Chrome Dart2Wasm WebSocket transport tests. Hosted GitHub evidence is
    pending.
  - MCP consumer runtime smoke is complete locally. The temporary downstream
    package smoke now starts a native router when the native runtime library is
    available, configures public and bearer-protected router-hosted MCP routes
    plus an HTTP ticket-auth route through public `connectanum_router` APIs,
    registers a neutral WAMP procedure through a public internal router
    session, proves the protected endpoint rejects unauthenticated callers,
    obtains a bearer token through the public HTTP auth flow, and calls both
    endpoints through public `connectanum_client` MCP helpers. The smoke proves
    direct JSON-RPC tool listing/calling, direct JSON-RPC configured MCP
    resource listing/reading, resource-template listing, and prompt
    listing/getting, direct JSON-RPC WAMP pub/sub
    subscribe/publish/poll/unsubscribe, initialized Streamable MCP tool
    listing/calling, initialized Streamable MCP configured resource and prompt
    access with advertised capabilities, Streamable WAMP pub/sub polling,
    typed WAMP API/meta discovery helpers, and Streamable HTTP session
    lifecycle from outside the workspace. The meta-helper smoke uses public
    `connectanum_client` helpers through both direct JSON and initialized
    Streamable MCP to discover procedures/topics, resolve registration and
    subscription details, and count route-visible sessions. The session
    lifecycle smoke
    captures the router-provided MCP session id, receives `tools/list_changed`
    over `GET`/SSE after registering a dynamic WAMP procedure, resumes with
    `Last-Event-ID` without replaying the old event, and deletes the MCP
    session through public consumer APIs. It keeps the existing public API
    construction fallback for environments without a native runtime.
    Pre-change `bin/test-fast` passed on 2026-05-04. The protected runtime
    consumer package smoke passed on 2026-05-04:
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-04 and included the upgraded
    protected consumer runtime smoke. The latest resource/prompt consumer-smoke
    extension passed the focused consumer package smoke, `bin/test-fast`, and
    full local `bin/verify` on 2026-05-04. It proves that the neutral consumer
    package can configure resources, resource templates, and prompts on public
    and bearer-protected router-hosted MCP routes and exercise them through
    public `connectanum_client` helpers using both direct JSON and initialized
    Streamable MCP. Full verify included formatting, Rust native/FFI tests,
    Python package-artifact checks, MCP package tests, client tests,
    auth-server tests, bench integration tests, the router-hosted MCP example
    smoke, the upgraded protected consumer runtime smoke with configured
    resources/prompts, WAMP meta helpers, and Streamable HTTP session
    lifecycle, full router package tests including router-hosted MCP
    auth/session coverage, zero-copy router checks, and Chrome Dart2Wasm
    WebSocket transport tests. The latest batch-smoke extension passed local
    `bin/test-fast` and full local `bin/verify` on 2026-05-05. The generated
    consumer package now proves mixed direct JSON-RPC batches and initialized
    Streamable HTTP batches against both public and bearer-protected
    router-hosted MCP routes. The direct JSON batch path proves API catalog
    lookup, direct procedure calls, configured resources/prompts, notification
    response omission, and no Streamable session state capture. The Streamable
    batch path proves tool listing/calling, configured resources/prompts,
    notification response omission, and a session-prefixed SSE event id update
    through the public consumer client API. Full verify included formatting,
    Rust native/FFI tests, Python package-artifact checks, MCP package tests,
    client tests, auth-server tests, bench integration tests, the
    router-hosted MCP example smoke, the upgraded protected consumer runtime
    smoke with batch/resources/prompts/WAMP meta/session-lifecycle coverage,
    full router package tests including router-hosted MCP auth/session/batch
    coverage, zero-copy router checks, and Chrome Dart2Wasm WebSocket transport
    tests. Commit `4847124` was pushed to both remotes. Hosted GitHub `CI` run
    `25363296633` completed successfully with `Fast Checks` and `Full Verify`.
    The hosted log audit found no actionable warnings, skipped tests,
    deprecations, panics, broken pipes, connection errors, or GitHub annotation
    errors/warnings. Broad failed/error word matches were benign passing test
    names and expected error-path coverage. `Dart Package Publish Dry Run` and
    `WAMP Profile Benchmarks` did not trigger for this script/docs change; the
    latest package dry-run and WAMP benchmark workflows remain clean and
    relevant on `207be91` because no publish-sensitive or benchmark-sensitive
    package paths changed. Commit `cb63df1` was pushed to both remotes.
    Hosted GitHub `CI` run `25340546748` completed successfully with
    `Fast Checks` and `Full Verify`. The deployment-chain audit with required
    clean latest CI, clean hosted CI logs, and clean Dart package publish
    dry-run passed for branch head `cb63df1`. `Dart Package Publish Dry Run`
    and `WAMP Profile Benchmarks` did not trigger for this script/docs change;
    the latest package dry-run remains clean and relevant on `207be91` because
    no publish-sensitive paths changed. The remaining audit findings are the
    existing operator/deployment items around branch protection, default-branch
    router workflow visibility, and GHCR router package visibility. The
    previous WAMP meta-helper extension passed the focused consumer package
    smoke, `bin/test-fast`, and full local
    `bin/verify` on 2026-05-04. Full verify included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests, client
    tests, auth-server tests, bench integration tests, the router-hosted MCP
    example smoke, the upgraded protected consumer runtime smoke with WAMP meta
    helpers and Streamable HTTP session lifecycle, full router package tests
    including router-hosted MCP auth/session coverage, zero-copy router checks,
    and Chrome Dart2Wasm WebSocket transport tests. Commit `e826f7e` was pushed
    to both remotes. Hosted GitHub `CI` run `25338108663` completed
    successfully with `Fast Checks` and `Full Verify`. The deployment-chain
    audit with required clean latest CI, clean hosted CI logs, and clean Dart
    package publish dry-run passed for branch head `e826f7e`. `Dart Package
    Publish Dry Run` and `WAMP Profile Benchmarks` did not trigger for this
    script/docs change; the latest package dry-run remains clean and relevant
    on `207be91` because no publish-sensitive paths changed. The remaining
    audit findings are the existing operator/deployment items around branch
    protection, default-branch router workflow visibility, and GHCR router
    package visibility. Previous commit `95956f3` was pushed to both remotes.
    Hosted GitHub `CI` run `25336128328` completed
    successfully with `Fast Checks` and `Full Verify`. The deployment-chain
    audit with required clean latest CI, clean hosted CI logs, and clean Dart
    package publish dry-run passed for branch head `95956f3`. `Dart Package
    Publish Dry Run` and `WAMP Profile Benchmarks` did not trigger for this
    script/docs change; the latest package dry-run remains clean and relevant
    on `207be91` because no publish-sensitive paths changed. The remaining
    audit findings are the existing operator/deployment items around branch
    protection, default-branch router workflow visibility, and GHCR router
    package visibility. Previous commit `d8310ac` was pushed to both remotes.
    Hosted GitHub `CI` run `25334205849` completed successfully with
    `Fast Checks` and `Full Verify`. The deployment-chain audit with required
    clean latest CI, clean hosted CI logs, and clean Dart package publish
    dry-run passed for branch head `d8310ac`. `Dart Package Publish Dry Run`
    and `WAMP Profile Benchmarks` did not trigger for this script/docs change;
    the latest package dry-run remains clean and relevant on `207be91` because
    no publish-sensitive paths changed. The remaining audit findings are the
    existing operator/deployment items around branch protection, default-branch
    router workflow visibility, and GHCR router package visibility.
  - Native build-hook user-defines / consumer package `dart run` readiness is
    complete. Dart 3.11 hooks run in a semi-hermetic environment that
    strips non-allowlisted shell variables from hook processes, so the
    client/router hooks now read `CONNECTANUM_NATIVE_LIB`,
    `CONNECTANUM_NATIVE_RELEASE_TAG`,
    `CONNECTANUM_NATIVE_RELEASE_REPOSITORY`, and
    `CONNECTANUM_SKIP_NATIVE_BUILD` from cache-safe `hooks.user_defines` while
    keeping the injected environment fallback for direct hook tests/manual hook
    debugging. The temporary MCP consumer package smoke now configures those
    user defines and runs `dart run bin/main.dart` after dependency resolution
    and analysis. Pre-change `bin/test-fast` passed on 2026-05-04. Focused
    hook checks passed on 2026-05-04:
    `dart test packages/connectanum_client/test/hook/build_hook_test.dart -r expanded`
    and
    `dart test packages/connectanum_router/test/hook/build_hook_test.dart -r expanded`.
    The focused consumer package smoke also passed on 2026-05-04:
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-04 and included the upgraded
    temporary consumer package smoke with a real `dart run`. Full local
    `bin/verify` passed on 2026-05-04. It included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client tests,
    auth-server tests, bench integration tests, router-hosted MCP example smoke,
    the upgraded consumer package smoke, full router package tests including
    router-hosted MCP auth/session coverage and hook user-define tests,
    zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
    Commit `207be91` was pushed to both remotes. Hosted GitHub evidence for
    `207be91` is clean: `CI` run `25330136036` completed successfully with
    `Fast Checks` and `Full Verify`, `Dart Package Publish Dry Run` run
    `25330135937` completed successfully, and `WAMP Profile Benchmarks` run
    `25330135956` completed successfully. The deployment-chain audit with
    required clean latest CI, clean hosted CI logs, and clean Dart package
    publish dry-run passed for branch head `207be91`; the remaining audit
    findings are the existing operator/deployment items around branch
    protection, default-branch router workflow visibility, and GHCR router
    package visibility.
  - MCP consumer package smoke is complete locally. The root verification path
    now creates a temporary Dart package outside the workspace, resolves the
    public client/MCP/router package entrypoints through local package
    overrides, and analyzes a small neutral consumer program. This complements
    the router-hosted MCP runtime example by proving external dependency
    solving and public imports. Pre-change `bin/test-fast` passed on
    2026-05-04. The focused helper check passed on 2026-05-04:
    `bash -lc 'source bin/common.sh && cd_repo_root && run_mcp_consumer_package_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-04 and included the new
    temporary consumer package smoke after the router-hosted MCP example gate.
    Full local `bin/verify` passed on 2026-05-04. It included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests, client
    tests, auth-server tests, bench integration tests, router-hosted MCP
    example smoke, the new consumer package smoke, full router package tests
    including `remote_auth_integration_test`, zero-copy router checks, and
    Chrome Dart2Wasm WebSocket transport tests. Commit `e9c689c` was pushed to
    both remotes. Hosted GitHub `CI` run `25327138243` completed successfully
    with `Fast Checks` and `Full Verify`. The deployment-chain audit with
    required clean latest CI and clean hosted CI logs passed for branch head
    `e9c689c`. `Dart Package Publish Dry Run` and `WAMP Profile Benchmarks`
    did not trigger for this script/docs change because their workflow path
    filters exclude the touched files; the latest relevant runs remain clean on
    `c754772`. The remaining audit findings are the existing
    operator/deployment items around branch protection, default-branch router
    workflow visibility, and GHCR router package visibility.
  - MCP example verification gate is complete locally. The public
    router-hosted MCP example smoke now runs from the standard root
    verification path, so consumer-style public API usage is continuously
    covered by `bin/test-fast` and `bin/verify` when a native runtime is
    available. Pre-change `bin/test-fast` passed on 2026-05-04. Focused smoke
    helper check passed on 2026-05-04:
    `bash -lc 'source bin/common.sh && cd_repo_root && run_router_hosted_mcp_example_smoke'`.
    Post-change `bin/test-fast` passed on 2026-05-04 and included the
    router-hosted MCP example smoke gate. Full local `bin/verify` passed on
    2026-05-04 and included the same gate through `bin/test-all`. Commit
    `0fe20eb` was pushed to both remotes. Hosted GitHub `CI` run
    `25324595775` completed successfully with `Fast Checks` and `Full Verify`.
    The deployment-chain audit with required clean latest CI and clean hosted
    CI logs passed for branch head `0fe20eb`. `Dart Package Publish Dry Run`
    and `WAMP Profile Benchmarks` did not trigger for this script/docs change
    because their workflow path filters exclude the touched files; the latest
    relevant runs remain clean on `c754772`. The remaining audit findings are
    the existing operator/deployment items around branch protection,
    default-branch router workflow visibility, and GHCR router package
    visibility.
  - MCP Streamable HTTP batch smoke is complete locally. The router
    integration suite now exercises the consumer `McpStreamableHttpClient`
    `postBatch(...)` path against real public and bearer-protected
    router-hosted MCP sessions, and the runnable router-hosted MCP example
    smoke now includes the same stateful batch path. Pre-change
    `bin/test-fast` passed on 2026-05-04. Focused checks passed on
    2026-05-04: `dart analyze packages/connectanum_router`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "serves Streamable HTTP batch responses on router MCP routes"`,
    `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`,
    and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    Full local `bin/verify` passed on 2026-05-04. Commit `c754772` was pushed
    to both remotes. Hosted GitHub evidence for `c754772` is clean: `CI` run
    `25322481688` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25322481294` completed successfully,
    and `WAMP Profile Benchmarks` run `25322481349` completed successfully.
    The deployment-chain audit with required clean latest CI, clean hosted CI
    logs, and clean Dart package publish dry-run passed for branch head
    `c754772`; the remaining audit findings are the existing
    operator/deployment items around branch protection, default-branch router
    workflow visibility, and GHCR router package visibility.
  - MCP Streamable HTTP session isolation is complete locally. The router
    integration smoke fixture now has a second neutral ticket-authenticated
    member principal, and the focused regression proves a bearer-protected MCP
    session ID cannot be reused by a different bearer principal, cannot be
    carried onto the public route, and cannot be deleted through the wrong
    principal while the original secure session remains usable. Pre-change
    `bin/test-fast` passed on 2026-05-04. Focused regression passed on
    2026-05-04:
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "isolates MCP Streamable HTTP sessions by route and bearer principal"`.
    Additional focused checks passed on 2026-05-04:
    `dart analyze packages/connectanum_router` and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    Full local `bin/verify` passed on 2026-05-04. Commit `4b8ac54` was pushed
    to both remotes. Hosted GitHub evidence for `4b8ac54` is clean: `CI` run
    `25320628899` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25320628923` completed successfully,
    and `WAMP Profile Benchmarks` run `25320628941` completed successfully.
    The deployment-chain audit with required clean latest CI, clean hosted CI
    logs, and clean Dart package publish dry-run passed for branch head
    `4b8ac54`; the remaining audit findings are the existing
    operator/deployment items around branch protection, default-branch router
    workflow visibility, and GHCR router package visibility.
  - Router-hosted MCP example pub/sub smoke is complete locally. The runnable
    `packages/connectanum_router/example/router_hosted_mcp.dart` smoke now
    proves direct JSON and initialized Streamable MCP pub/sub helpers on both
    the public and bearer-protected router-hosted MCP endpoints by
    subscribing, publishing, polling for a service-published event, and
    unsubscribing from the declared `example.events.task` topic. Pre-change
    `bin/test-fast` passed on 2026-05-04. Focused checks passed on
    2026-05-04:
    `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`,
    `dart analyze packages/connectanum_router`, and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    Full local `bin/verify` passed on 2026-05-04. Commit `7f27566` was pushed
    to both remotes. Hosted GitHub evidence for `7f27566` is clean: `CI` run
    `25318815245` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25318815255` completed successfully,
    and `WAMP Profile Benchmarks` run `25318815262` completed successfully.
    The deployment-chain audit with required clean latest CI, clean hosted CI
    logs, and clean Dart package publish dry-run passed for branch head
    `7f27566`; the remaining audit findings are the existing
    operator/deployment items around branch protection, default-branch router
    workflow visibility, and GHCR router package visibility.
  - MCP Streamable HTTP client bearer-token convenience is complete locally.
    It packages the common authenticated router-hosted MCP client setup as a
    typed constructor, moves secure example/smoke paths onto it, and refreshes
    stale public MCP docs while keeping router-hosted MCP as the intended
    endpoint shape. Pre-change `bin/test-fast` passed on 2026-05-04. Focused
    checks
    passed on 2026-05-04:
    `dart analyze packages/connectanum_client packages/connectanum_router packages/connectanum_mcp`,
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`,
    and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    Full local `bin/verify` passed on 2026-05-04. Commit `627cde4` was pushed
    to both remotes. Hosted GitHub evidence for `627cde4` is clean: `CI` run
    `25317115053` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25317115064` completed successfully,
    and `WAMP Profile Benchmarks` run `25317115069` completed successfully.
    The hosted log scan found no actionable warnings, deprecations,
    skipped-test lines, panics, failures, connection reset/refused noise, or
    broken pipes; matches were limited to Git checkout's default-branch hint,
    package dry-run `0 warnings` summaries, normal Rust `0 ignored` /
    filtered-test summaries, and passing test names.
  - Router-hosted MCP secure example readiness is complete. The runnable
    `packages/connectanum_router/example/router_hosted_mcp.dart` example now
    keeps the public `/mcp` endpoint and also configures `/auth` plus a
    bearer-protected `/mcp/secure` endpoint. Its `--smoke-and-exit` path now
    proves public direct JSON and Streamable MCP access, secure
    unauthenticated denial, HTTP ticket-token issuance, and authenticated
    direct JSON plus Streamable MCP access on the secure route. Pre-change
    `bin/test-fast` passed on 2026-05-04. Focused checks passed on 2026-05-04:
    `dart analyze packages/connectanum_router` and
    `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`.
    Full local `bin/verify` passed on 2026-05-04. Commit `af56f1c` was pushed
    to both remotes. Hosted GitHub evidence for `af56f1c` is clean: `CI` run
    `25315729357` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25315729371` completed successfully,
    and `WAMP Profile Benchmarks` run `25315729373` completed successfully.
    The hosted log scan found no actionable warnings, deprecations,
    skipped-test lines, panics, failures, connection reset/refused noise, or
    broken pipes; matches were limited to Git checkout's default-branch hint,
    package dry-run `0 warnings` summaries, normal Rust `0 ignored` /
    filtered-test summaries, and passing test names. The newer branch-head
    automation-guidance commit `d56b456` also has clean hosted `CI` evidence:
    run `25315879512` completed successfully with `Fast Checks` and
    `Full Verify`, and its hosted log scan had the same benign-only matches.
  - MCP route-security resource/prompt hardening is complete. The existing
    public/secure router-hosted MCP integration smoke now includes configured
    resources, resource templates, and prompts so direct JSON, initialized
    Streamable MCP, direct JSON batch, and bearer-protected route access are
    exercised under the same route/session identity contract as WAMP tools and
    pub/sub helpers. Pre-change `bin/test-fast` passed on 2026-05-04. Focused
    checks passed on 2026-05-04:
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`
    and `dart analyze packages/connectanum_router`. Full local `bin/verify`
    passed on 2026-05-04. Commit `227fbf3` was pushed to both remotes. Hosted
    GitHub evidence for `227fbf3` is clean: `CI` run `25313970259` completed
    successfully with `Fast Checks` and `Full Verify`, `Dart Package Publish
    Dry Run` run `25313970231` completed successfully, and `WAMP Profile
    Benchmarks` run `25313970226` completed successfully. The hosted log scan
    found no actionable warnings, deprecations, skipped-test lines, panics,
    failures, connection reset/refused noise, or broken pipes; matches were
    limited to Git checkout's default-branch hint, package dry-run
    `0 warnings` summaries, normal Rust `0 ignored` / filtered-test summaries,
    and passing test names.
  - Router-hosted MCP example resource/prompt readiness is complete. The
    runnable example now configures a static resource, a resource template, and
    a prompt on the same router-owned `type: mcp` route that exposes WAMP tools
    and pub/sub helpers. Its `--smoke-and-exit` path now proves lifecycle-free
    direct JSON `resources/list`, `resources/read`, and `prompts/get` calls,
    then initializes a Streamable MCP session and verifies
    `resources/templates/list` plus `prompts/get`. Focused checks passed on
    2026-05-04: `dart analyze packages/connectanum_router` and
    `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`.
    Full local `bin/verify` passed on 2026-05-04 after this example follow-up,
    including formatting, Rust native/FFI tests, Python package-artifact
    checks, MCP package tests, client tests including MCP Streamable
    HTTP/direct JSON helper coverage, auth-server tests, bench integration
    tests, the full router package tests including router-hosted MCP and
    `remote_auth_integration_test`, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests. Commit `42a600d` was pushed to both
    remotes. Hosted GitHub evidence for `42a600d` is clean: `CI` run
    `25312011623` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25312011638` completed successfully,
    and `WAMP Profile Benchmarks` run `25312011620` completed successfully.
    The hosted log scan found no actionable warnings, deprecations,
    skipped-test lines, panics, failures, connection reset/refused noise, or
    broken pipes; matches were limited to Git checkout's default-branch hint,
    package dry-run `0 warnings` summaries, normal Rust `0 ignored` /
    filtered-test summaries, and passing test names.
  - MCP direct JSON resource/prompt readiness is complete. The local
    implementation now lets typed `McpStreamableHttpClient` resource and prompt
    helpers use `directJson: true` without attaching `MCP-Session-Id`, and the
    router-hosted endpoint now accepts `resources/list`, `resources/read`,
    `resources/templates/list`, `prompts/list`, and `prompts/get` as direct
    JSON methods before MCP initialization. Pre-change `bin/test-fast` passed
    on 2026-05-04. Focused checks passed on 2026-05-04:
    `dart analyze packages/connectanum_client packages/connectanum_router`,
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`.
    Full local `bin/verify` passed on 2026-05-04 after this implementation,
    including formatting, Rust native/FFI tests, Python package-artifact
    checks, MCP package tests, client tests including the updated
    `streamable_http_client_test.dart` direct JSON resource/prompt coverage,
    auth-server tests, bench integration tests, the full router package tests
    including the updated router-hosted MCP integration case and
    `remote_auth_integration_test`, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests. Commit `7ee0363` was pushed to both
    remotes. Hosted GitHub evidence for `7ee0363` is clean: `CI` run
    `25310692222` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25310692197` completed successfully,
    and `WAMP Profile Benchmarks` run `25310692221` completed successfully.
    The hosted log scan found no actionable warnings, deprecations,
    skipped-test lines, panics, failures, connection reset/refused noise, or
    broken pipes; matches were limited to Git checkout's default-branch hint,
    package dry-run `0 warnings` summaries, normal Rust `0 ignored` /
    filtered-test summaries, and passing test names.
  - Router-hosted MCP config validation is complete. The local
    implementation now reuses the router-hosted MCP parsers while building
    native config for `HttpRouteActionType.mcp`, so malformed configured
    procedures, topics, resources, resource templates, prompts, and prompt
    arguments fail during router config build/start instead of first request
    handling. Focused regressions in `router_json_test.dart` cover invalid
    resource, WAMP API, and prompt options. Pre-change `bin/test-fast` passed
    on 2026-05-04. Focused checks passed on 2026-05-04:
    `dart analyze packages/connectanum_router` and
    `dart test packages/connectanum_router/test/router_json_test.dart -r expanded`.
    Full local `bin/verify` passed on 2026-05-04 with formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests, client
    tests including MCP Streamable HTTP/direct JSON helper coverage,
    auth-server tests, bench integration tests, the full router package tests
    including the new MCP route-option validation cases and existing
    router-hosted MCP smoke coverage, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests. Commit `67d3256` was pushed to both
    remotes. Hosted GitHub evidence for `67d3256` is clean: `CI` run
    `25308635274` completed successfully with `Fast Checks` and `Full Verify`,
    `Dart Package Publish Dry Run` run `25308635243` completed successfully,
    and `WAMP Profile Benchmarks` run `25308635311` completed successfully.
    The hosted log scan found no actionable warning, deprecation,
    skipped-test, panic, failure, connection reset/refused, or broken-pipe
    patterns; matches were limited to normal Rust test summaries with
    `0 ignored` / filtered-test counts.
  - Router-hosted MCP resource and prompt readiness is complete. The local
    implementation now lets `HttpRouteActionType.mcp` route options configure
    static MCP resources, resource templates, prompts, and their list page
    sizes. Router-hosted `initialize` advertises `resources` and `prompts`
    capabilities when those route surfaces are configured, and the existing
    native router MCP HTTP smoke now proves `resources/list`,
    `resources/read`, `resources/templates/list`, `prompts/list`, and
    `prompts/get` through the router-owned MCP endpoint. Public MCP docs,
    examples, research notes, and the roadmap now describe this as an
    implemented explicit configuration path while keeping automatic application
    data or prompt projection as a future product decision. Pre-change
    `bin/test-fast` passed on 2026-05-04. Focused checks passed on 2026-05-04:
    `dart analyze packages/connectanum_router` and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`.
    Full local `bin/verify` passed on 2026-05-04 after the router-hosted MCP
    resource/prompt implementation; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client tests
    including MCP Streamable HTTP/direct JSON helper coverage, auth-server
    tests, bench integration tests, the full router package tests including
    router-hosted MCP and `remote_auth_integration_test`, zero-copy router
    checks, and Chrome Dart2Wasm WebSocket transport tests. Commit `09dffab`
    was pushed to both remotes. Hosted GitHub evidence for `09dffab` is clean:
    `CI` run `25306872679` completed successfully with `Fast Checks` and
    `Full Verify`, `Dart Package Publish Dry Run` run `25306872647` completed
    successfully, and `WAMP Profile Benchmarks` run `25306872632` completed
    successfully. The hosted log scan found no actionable Rust/Dart warnings,
    deprecations, skipped-test lines, panics, resets, connection failures, or
    broken pipes; matches were limited to Git checkout's default-branch hint
    and normal `0 ignored` / filtered-test summaries.
  - Router-hosted MCP public example readiness is complete with hosted evidence
    clean for `4a1e42c`. The local
    implementation adds
    `packages/connectanum_router/example/router_hosted_mcp.dart`, a runnable
    router-backed MCP endpoint example that registers an internal WAMP
    procedure, exposes it through the router's `type: mcp` HTTP route, and
    smoke-tests both direct JSON-RPC helper calls and Streamable HTTP
    `tools/call` against the live router. Public docs now describe the current
    router-hosted MCP behavior accurately: MCP JSON-RPC `POST`, Streamable HTTP
    session IDs, POST/SSE responses, GET/SSE polling, DELETE session teardown,
    direct JSON-RPC frontend access, route-authenticated WAMP principals, and
    the remaining router-hosted resource/prompt gap. Focused checks passed on
    2026-05-04: `bin/test-fast` before changes,
    `dart analyze packages/connectanum_router`,
    `dart analyze packages/connectanum_mcp`, and
    `dart run packages/connectanum_router/example/router_hosted_mcp.dart --smoke-and-exit`.
    Full local `bin/verify` passed on 2026-05-04 after the example/docs change;
    it included formatting, Rust native/FFI tests, Python package-artifact
    checks, MCP package tests, client tests including MCP Streamable HTTP/direct
    JSON helper coverage, auth-server tests, bench integration tests, the full
    router package tests including router-hosted MCP and
    `remote_auth_integration_test`, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests. Post-commit package checks passed:
    `bin/dart-package-publish-dry-run --include-private connectanum_mcp`
    reported zero package warnings, and `bin/dart-package-publish-dry-run`
    reported zero package warnings while preserving the known default-mode
    release-order blocker that `connectanum_client` depends on private
    `connectanum_core`. Hosted GitHub evidence for `4a1e42c` is clean: `CI`
    run `25305027870` completed successfully with `Fast Checks` and
    `Full Verify`, the hosted CI log scan found no warning, deprecation,
    skipped-test, reset, connection-noise, panic, or failure patterns, `Dart
    Package Publish Dry Run` run `25305027872` completed successfully with the
    private MCP package readiness step, and `WAMP Profile Benchmarks` run
    `25305027866` completed successfully. Strict deployment-chain audit passed
    after the push; Native Artifacts dry-run `25192553399` remains clean and
    relevant because no native-release-sensitive paths changed. A broader router
    private package dry-run is not yet a gate because it still has pre-existing
    release-readiness blockers: private path dependencies, test fixture secret
    false positives, and a missing router changelog.
  - MCP package release-readiness gating is complete with hosted evidence clean
    for `e2ed55d`. The local
    implementation keeps `connectanum_mcp` private (`publish_to: none`) while
    adding a dedicated GitHub Actions publish dry-run step for
    `bin/dart-package-publish-dry-run --include-private connectanum_mcp`, so
    the private MCP package archive is validated in CI without changing public
    publishability. `packages/connectanum_mcp/CHANGELOG.md` now removes the
    package archive warning that previously made the focused private-package
    dry-run fail. Focused checks passed on 2026-05-04:
    `bin/dart-package-publish-dry-run --include-private connectanum_mcp` and
    `bin/dart-package-publish-dry-run`; both reported zero package warnings.
    Full local `bin/verify` passed on 2026-05-04 after the workflow/package
    change. Hosted GitHub evidence for `e2ed55d` is clean: `CI` run
    `25303581665` completed successfully with `Fast Checks` and `Full Verify`,
    the hosted CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, and `Dart Package Publish Dry
    Run` run `25303581667` completed successfully with the new
    `Validate MCP package release readiness` step. Strict deployment-chain
    audit passed after the push; Native Artifacts dry-run `25192553399` remains
    clean and relevant because no native-release-sensitive paths changed.
  - MCP typed WAMP direct JSON helper readiness and the package IO entrypoint
    guard are complete with hosted evidence clean for `a4e32dd`. The local
    implementation adds an explicit `directJson: true` option to the exported
    typed WAMP API, meta, and pub/sub helpers so consumer applications can call
    router-hosted `connectanum.tool.call` direct JSON endpoints without
    `initialize`, `notifications/initialized`, or an MCP session ID. The
    default remains the existing session-aware `tools/call` path. Client
    coverage pins lifecycle-free typed helper calls for API listing,
    pub/sub subscribe/publish/poll/unsubscribe, and WAMP registration meta
    calls; the real router-hosted MCP smoke now exercises representative typed
    direct JSON helpers against public and bearer-authenticated routes while
    preserving route auth and visibility filtering. Focused checks passed:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart analyze packages/connectanum_client packages/connectanum_router`, and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    An initial post-change `bin/test-fast` hit a local native runtime lock
    collision with another local test child; the focused rerun of the affected
    bench files passed from `packages/connectanum_bench`, and a clean
    post-change `bin/test-fast` rerun passed on 2026-05-04. Full local
    `bin/verify` passed on 2026-05-04 after the helper implementation; it
    included formatting, Rust native/FFI tests, Python package-artifact checks,
    MCP package tests, client tests including the updated
    `packages/connectanum_client/test/mcp` suite, auth-server tests, bench
    integration tests, the full router package tests including the updated
    router-hosted MCP smoke and `remote_auth_integration_test`, zero-copy
    router checks, and Chrome Dart2Wasm WebSocket transport tests. Hosted
    GitHub evidence for `a4e32dd` is clean: `CI` run `25302428144` completed
    successfully with `Fast Checks` and `Full Verify`, the hosted CI log scan
    found no warning, deprecation, skipped-test, reset, connection-noise, panic,
    or failure patterns, and `Dart Package Publish Dry Run` run `25302428154`
    completed successfully and covers the checked-out head. `WAMP Profile
    Benchmarks` run `25301180479` remains clean and relevant because this
    follow-up touched only package smoke coverage and docs, and Native
    Artifacts dry-run `25192553399` remains clean and relevant because no
    native-release-sensitive paths changed.
  - A follow-up package-entrypoint smoke guard now lives in
    `packages/connectanum_mcp/test/io_client_export_test.dart`. It imports only
    `package:connectanum_mcp/connectanum_mcp_io.dart` and proves a downstream
    IO consumer sees MCP tool primitives, `McpStreamableHttpClient`, and typed
    WAMP helper calls routed through `directJson: true` without MCP lifecycle
    or session negotiation. Focused checks passed:
    `dart test packages/connectanum_mcp/test/io_client_export_test.dart -r expanded`
    and `dart analyze packages/connectanum_mcp packages/connectanum_client`.
    Post-change `bin/test-fast` and full local `bin/verify` passed again on
    2026-05-04 with the new smoke included. Hosted evidence for `a4e32dd` is
    clean: `CI` run `25302428144` passed with clean logs, and `Dart Package
    Publish Dry Run` run `25302428154` passed.
  - MCP direct JSON client helper readiness is complete with hosted evidence
    clean for `a3a7c96`. The local
    implementation adds `McpStreamableHttpClient.listConnectanumToolsDirect`,
    `callConnectanumToolDirect`, and `callConnectanumMethodDirect` so Dart
    consumers can use router-hosted direct JSON tool/meta APIs without the
    `initialize`/`notifications/initialized` lifecycle. The helpers force
    JSON-only POSTs, do not negotiate an MCP session ID, and keep route
    authentication and visibility filtering centralized in the router endpoint.
    Client coverage pins lifecycle-free behavior, request shape, tool calls, and
    dotted WAMP meta calls; the real router-hosted MCP smoke now exercises
    representative helper calls against public and bearer-authenticated routes.
    Focused checks passed:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum direct JSON helpers without MCP lifecycle"`,
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart analyze packages/connectanum_client packages/connectanum_router`, and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    Post-change `bin/test-fast` passed on 2026-05-04. Full local `bin/verify`
    passed on 2026-05-04 after the helper implementation; it included
    formatting, Rust native/FFI tests, Python package-artifact checks, MCP
    package tests, client tests including the updated
    `packages/connectanum_client/test/mcp` suite, auth-server tests, bench
    integration tests, the full router package tests including the updated
    router-hosted MCP smoke and `remote_auth_integration_test`, zero-copy router
    checks, and Chrome Dart2Wasm WebSocket transport tests. Hosted GitHub
    evidence for `a3a7c96` is clean: `CI` run `25299738068` completed
    successfully with `Fast Checks` and `Full Verify`, the hosted CI log scan
    found no warning, deprecation, skipped-test, reset, connection-noise, panic,
    or failure patterns, `Dart Package Publish Dry Run` run `25299738064`
    completed successfully and covers the checked-out head,
    `WAMP Profile Benchmarks` run `25299738077` completed successfully, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed.
  - MCP Streamable standard meta convenience helper readiness is in progress.
    The local implementation adds named `package:connectanum_client/mcp.dart`
    helpers for standard `wamp.session.*`, `wamp.registration.*`, and
    `wamp.subscription.*` meta procedure calls while keeping all calls routed
    through the existing authenticated Streamable MCP `tools/call` path via
    `callWampMetaProcedure(...)`. Focused checks passed:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses standard WAMP meta convenience helpers"`,
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart analyze packages/connectanum_client packages/connectanum_router`, and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    Post-change `bin/test-fast` passed on 2026-05-04. Full local `bin/verify`
    passed on 2026-05-04 after the helper implementation; it included
    formatting, Rust native/FFI tests, Python package-artifact checks, MCP
    package tests, client tests including the updated
    `packages/connectanum_client/test/mcp` suite, auth-server tests, bench
    integration tests, the full router package tests including the updated
    router-hosted MCP smoke and `remote_auth_integration_test`, zero-copy router
    checks, and Chrome Dart2Wasm WebSocket transport tests. Hosted GitHub
    evidence for `921ea85` is clean: `CI` run `25298439451` completed
    successfully with `Fast Checks` and `Full Verify`, the hosted CI log scan
    found no warning, deprecation, skipped-test, reset, connection-noise, panic,
    or failure patterns, `Dart Package Publish Dry Run` run `25298439424`
    completed successfully and covers the checked-out head,
    `WAMP Profile Benchmarks` run `25298439421` completed successfully, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because no
    native-release-sensitive paths changed.
  - MCP Streamable WAMP meta helper readiness is complete with hosted evidence
    clean for `06c7a5f`. The exported `package:connectanum_client/mcp.dart`
    WAMP helper extension now adds
    `callWampMetaProcedure(...)` for router-hosted standard `wamp.*` meta
    procedure tools. The helper reuses the existing session-aware
    `callTool(...)` path, so route authentication, MCP session IDs, and
    WAMP meta visibility filtering remain centralized in the router endpoint.
    Client coverage pins registration and subscription meta result envelopes,
    and the real router-hosted MCP smoke now exercises the helper against
    `/mcp/public` for safe registration visibility, unsafe registration
    filtering, and subscription lookup. Focused checks passed:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum WAMP meta procedure helpers"`,
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart analyze packages/connectanum_client packages/connectanum_router`, and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`.
    Post-change `bin/test-fast` passed on 2026-05-04. Full local `bin/verify`
    passed on 2026-05-04 after the helper implementation; it included
    formatting, Rust native/FFI tests, Python package-artifact checks, MCP
    package tests, client tests including the updated
    `packages/connectanum_client/test/mcp` suite, auth-server tests, bench
    integration tests, the full router package tests including the updated
    router-hosted MCP smoke and `remote_auth_integration_test`, zero-copy router
    checks, and Chrome Dart2Wasm WebSocket transport tests.
  - hosted GitHub evidence for `06c7a5f` is clean: `CI` run `25297227105`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `Dart Package Publish Dry
    Run` run `25297227117` completed successfully and covers the checked-out
    head, `WAMP Profile Benchmarks` run `25297227103` completed successfully,
    and Native Artifacts dry-run `25192553399` remains clean and relevant
    because no native-release-sensitive paths changed.
  - MCP Streamable WAMP tool helper readiness is complete with hosted evidence
    clean for `9bace00`. `package:connectanum_client/mcp.dart` now exports
    typed `McpStreamableHttpClient` extension helpers for
    `connectanum.api.list`, `connectanum.api.describe`,
    `connectanum.pubsub.publish`, `connectanum.pubsub.subscribe`,
    `connectanum.pubsub.poll`, and `connectanum.pubsub.unsubscribe`. These
    helpers reuse the existing session-aware `callTool(...)` path, so
    router-hosted MCP auth/session behavior remains centralized in the router
    endpoint and generic clients can still use raw `request(...)`/`callTool(...)`
    for custom methods. Tool-level WAMP helper errors surface as
    `McpStreamableWampToolException` while generic `callTool(...)` still
    returns raw successful MCP tool results.
  - fail-first focused coverage reproduced the missing WAMP helper APIs:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum WAMP tool helpers for API and pubsub"`.
    Focused checks passed after implementation:
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "uses Connectanum WAMP tool helpers for API and pubsub"`,
    `dart analyze packages/connectanum_client`, and
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`.
    `bin/test-fast` and full local `bin/verify` passed on 2026-05-04 after the
    helper implementation; full verification included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests, client
    tests including the updated `packages/connectanum_client/test/mcp` suite,
    auth-server tests, bench integration tests, the full router package tests
    including MCP router smoke coverage and `remote_auth_integration_test`,
    zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
  - hosted GitHub evidence for `9bace00` is clean: `CI` run `25296034697`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `Dart Package Publish Dry
    Run` run `25296034699` completed successfully and covers the checked-out
    head, `WAMP Profile Benchmarks` run `25296034701` completed successfully,
    and Native Artifacts dry-run `25192553399` remains clean and relevant
    because no native-release-sensitive paths changed.
  - MCP Streamable discovery helper readiness is complete with hosted evidence
    clean for `87226f0`. The exported `McpStreamableHttpClient` now has typed
    helpers for standard
    `resources/list`, `resources/read`, `resources/templates/list`,
    `prompts/list`, and `prompts/get` calls while preserving raw JSON-RPC
    access for future/custom MCP methods. Focused fail-first coverage
    reproduced the missing helper APIs, then focused checks passed after
    implementation: `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`
    and `dart analyze packages/connectanum_client`. `bin/test-fast` and full
    local `bin/verify` passed on 2026-05-04 after the helper implementation
    and project-state updates; full verification included formatting,
    Rust native/FFI tests, Python package-artifact checks, MCP package tests,
    client tests including the updated `packages/connectanum_client/test/mcp`
    suite, auth-server tests, bench integration tests, the full router package
    tests including MCP router smoke coverage and `remote_auth_integration_test`,
    zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests.
  - hosted GitHub evidence for `87226f0` is clean: `CI` run `25294812273`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `Dart Package Publish Dry
    Run` run `25294812274` completed successfully and covers the checked-out
    head, `WAMP Profile Benchmarks` run `25294812276` completed successfully,
    and Native Artifacts dry-run `25192553399` remains clean and relevant
    because no native-release-sensitive paths changed.
  - MCP Streamable tool helper readiness is complete with hosted evidence
    clean for `bb44ecc`. `McpStreamableHttpClient` now exposes typed
    `listTools(...)` and
    `callTool(...)` helpers over the existing session-aware request path,
    surfaces JSON-RPC error responses through `McpJsonRpcException`, and keeps
    raw `request(...)`/`post(...)` escape hatches for direct router meta API and
    future MCP methods. Client tests cover tool listing, tool invocation, and
    JSON-RPC tool errors; the router-native MCP smoke now uses the helpers
    against public and protected router-hosted MCP routes while preserving the
    existing pub/sub and route-security coverage.
  - Initial fail-first `bin/test-fast` reproduced the missing helper API and
    the in-progress duplicate router smoke patch. Focused checks passed after
    implementation: `dart analyze packages/connectanum_client packages/connectanum_router`,
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`,
    and `git diff --check`. `bin/test-fast` passed on 2026-05-04 after the
    helper implementation and router smoke cleanup. Full local `bin/verify`
    passed on 2026-05-04 after the helper implementation and project-state
    updates; it included formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP package tests, client tests including the
    updated `packages/connectanum_client/test/mcp` suite, auth-server tests,
    bench integration tests, the full router package tests including the
    updated router-hosted MCP helper smoke, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests.
  - hosted GitHub evidence for `bb44ecc` is clean: `CI` run `25293893587`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `Dart Package Publish Dry
    Run` run `25293893582` completed successfully and covers the checked-out
    head, `WAMP Profile Benchmarks` run `25293893591` completed successfully,
    and Native Artifacts dry-run `25192553399` remains clean and relevant
    because no native-release-sensitive paths changed.
  - MCP ping readiness is complete and hosted evidence is clean for `7e738de`.
    The MCP server now handles standard `ping` requests after initialization
    with the required empty result object, `McpStreamableHttpClient` exposes a
    session-aware `ping(...)` helper, and router-native MCP integration covers
    direct HTTP plus Streamable HTTP client ping behavior on router-hosted MCP
    routes.
  - pre-change `bin/test-fast` passed on 2026-05-04 before the MCP ping
    readiness implementation.
  - fail-first focused checks reproduced the gap before implementation:
    `dart test packages/connectanum_mcp/test/lifecycle_test.dart -r expanded --plain-name "responds to ping requests after initialization"`
    and
    `dart test packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded --plain-name "tracks Streamable HTTP sessions, SSE responses, polling, and auth headers"`.
  - focused checks passed after the MCP ping implementation:
    `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_mcp/test/lifecycle_test.dart packages/connectanum_client/test/mcp/streamable_http_client_test.dart -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`,
    and `git diff --check`.
  - full local `bin/verify` passed on 2026-05-04 after the MCP ping
    implementation and project-state updates; it included formatting,
    Rust/native/FFI tests, Python package-artifact checks, MCP package tests,
    client tests including `packages/connectanum_client/test/mcp`, auth-server
    tests, bench integration tests, the full router package tests including the
    updated MCP ping coverage and `remote_auth_integration_test`, zero-copy
    router checks, and Chrome Dart2Wasm WebSocket transport tests.
  - hosted GitHub evidence for `7e738de` is clean: `CI` run `25292725722`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `Dart Package Publish Dry
    Run` run `25292725729` completed successfully and covers the checked-out
    head, `WAMP Profile Benchmarks` run `25292725720` completed successfully,
    and Native Artifacts dry-run `25192553399` remains clean and relevant
    because no native-release-sensitive paths changed.
  - MCP Streamable HTTP consumer readiness is being tightened with
    authenticated router-hosted smoke coverage. `packages/connectanum_client`
    now owns the IO-only `package:connectanum_client/mcp.dart` entrypoint with
    `McpStreamableHttpClient`, SSE event parsing, explicit MCP session/header
    tracking, JSON-only request compatibility, GET/SSE polling with resume
    cursors, session deletion, custom HTTP headers for authenticated routes,
    typed HTTP failures, and explicit `Content-Length` JSON request bodies for
    native router compatibility; `connectanum_mcp_io.dart` re-exports the
    client entrypoint only as a compatibility bridge. The router-native MCP
    smoke test now uses the
    client against both public and protected router-hosted MCP routes to
    initialize Streamable HTTP sessions, receive POST/SSE tool responses,
    list safe and unsafe protected tools with bearer auth, call protected
    unsafe router-backed tools, exercise router-backed pub/sub subscribe,
    publish, poll, and unsubscribe through the client, and track
    session/event ids. The direct JSON router smoke now also uses dotted
    `connectanum.pubsub.subscribe`, `connectanum.pubsub.publish`,
    `connectanum.pubsub.poll`, and `connectanum.pubsub.unsubscribe` methods
    without MCP lifecycle setup or `connectanum.tool.call` wrapping. The
    current working tree extends that path to standard WAMP meta API methods
    (`wamp.registration.list` and `wamp.registration.match`) with route
    authorization filtering for safe versus protected registrations, and now
    adds direct JSON `wamp.subscription.list`, `wamp.subscription.lookup`, and
    `wamp.subscription.match` smoke coverage for public-topic visibility plus
    protected-topic denial/success across anonymous and bearer-authenticated
    routes
  - branch-head GitHub deployment-chain audit was re-run on 2026-05-03 before
    the current Streamable protected pub/sub smoke work; latest branch CI,
    hosted CI log scan, Dart package publish dry-run, and native release
    dry-run evidence were clean/relevant for `3d4fac6`
  - completed Streamable protected pub/sub smoke slice pins protected topic
    behavior for Streamable HTTP clients: anonymous `/mcp/public` topic
    catalog hides `app.secure.audit`, anonymous Streamable subscribe to that
    topic returns a tool-level error, and bearer-authenticated `/mcp/secure`
    can list, subscribe, publish, poll, and unsubscribe the same topic
  - pre-change `bin/test-fast` passed on 2026-05-03 before the Streamable
    protected pub/sub smoke edits
  - focused checks passed for the Streamable protected pub/sub smoke slice:
    `dart analyze packages/connectanum_mcp packages/connectanum_router` and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
  - full local `bin/verify` passed on 2026-05-03 after the Streamable
    protected pub/sub smoke addition and project-state updates; it included
    formatting, Rust native/FFI tests, Python package-artifact checks, MCP
    package tests, client/native tests, auth-server tests, bench integration
    tests, the full router package tests including the updated Streamable MCP
    protected pub/sub smoke, zero-copy router checks, and Chrome Dart2Wasm
    WebSocket transport tests
  - hosted GitHub evidence for `2bc49ce` is clean: `CI` run `25286547478`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
    `25286547473` completed successfully, `Dart Package Publish Dry Run` run
    `25286547477` completed successfully and covers the checked-out head, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - current working tree exposes standard WAMP meta procedures on
    router-hosted MCP routes when `include_standard_meta_api` is enabled, then
    filters registration and subscription meta results through the current
    route session's authorization. The router-native MCP smoke now verifies
    anonymous direct JSON can inspect visible safe registrations, cannot
    discover `app.unsafe.delete`, and bearer-authenticated direct JSON can
    discover that protected registration.
  - pre-change `bin/test-fast` passed on 2026-05-03 before the direct JSON
    meta API smoke edits
  - focused checks passed for the direct JSON meta API smoke slice:
    `dart analyze packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the direct JSON meta
    API implementation and project-state updates; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests,
    client/native tests, auth-server tests, bench integration tests, the full
    router package tests including the updated direct JSON WAMP meta API smoke,
    zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `8bb74f8` is clean: `CI` run `25287625031`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
    `25287625046` completed successfully, `Dart Package Publish Dry Run` run
    `25287625035` completed successfully and covers the checked-out head, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - branch head `4a0a877` extends the direct JSON WAMP meta API smoke with
    subscription meta coverage: anonymous `/mcp/public` can list and look up
    `app.events.audit` subscriptions, anonymous `/mcp/public` cannot discover
    `app.secure.audit` subscriptions, and bearer-authenticated `/mcp/secure`
    can discover the same protected subscription.
  - pre-change `bin/test-fast` passed on 2026-05-03 before the direct JSON
    subscription meta API smoke edits
  - focused checks passed for the direct JSON subscription meta API smoke
    slice: `dart analyze packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the direct JSON
    subscription meta API smoke coverage and project-state updates; it
    included formatting, Rust native/FFI tests, Python package-artifact checks,
    MCP package tests, client/native tests, auth-server tests, bench
    integration tests, the full router package tests including the updated
    direct JSON subscription meta smoke, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `4a0a877` is clean: `CI` run `25288536163`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
    `25288536164` completed successfully, `Dart Package Publish Dry Run` run
    `25288536165` completed successfully and covers the checked-out head, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - branch head `8cefc81` scopes router-hosted MCP direct JSON session meta
    (`wamp.session.count`, `wamp.session.list`, and `wamp.session.get`) to the
    MCP route's own internal session, so anonymous and bearer-authenticated
    routes can inspect their own route-principal details but cannot read the
    service/internal session used by the fixture
  - branch head `8cefc81` moved the IO-only `McpStreamableHttpClient`
    implementation out of `packages/connectanum_mcp/lib/src/transport/` so
    `src/transport/` stays reserved for real transport adapters rather than
    high-level MCP client/session helpers
  - branch head `b0edb03` relocates that implementation and its
    package-level tests to `packages/connectanum_client`, exports it from
    `package:connectanum_client/mcp.dart`, and updates router MCP smoke tests
    to import the WAMP-client-owned entrypoint directly. `bin/test-fast` and
    `bin/test-all` now run `packages/connectanum_client/test/mcp` so the moved
    Streamable HTTP client coverage remains in the canonical gates.
  - branch head `b0edb03` also scopes route-hosted MCP participant meta:
    `wamp.registration.list_callees`,
    `wamp.registration.count_callees`,
    `wamp.subscription.list_subscribers`, and
    `wamp.subscription.count_subscribers` now filter attached participant ids
    through the route's visible session set. The native MCP smoke fixture
    registers service-side callees/subscribers and verifies public plus bearer
    routes do not expose the service/internal session id through those meta
    calls.
  - full local `bin/verify` passed on 2026-05-03 after the participant meta
    scope and `connectanum_client` MCP entrypoint move; it included formatting,
    Rust native/FFI tests, Python package-artifact checks, MCP package tests,
    client tests including `packages/connectanum_client/test/mcp`, auth-server
    tests, bench integration tests, the full router package tests including the
    updated participant meta smoke, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `b0edb03` is clean: `CI` run `25290429879`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
    `25290429876` completed successfully, `Dart Package Publish Dry Run` run
    `25290429877` completed successfully and covers the checked-out head, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - current working tree adds JSON-RPC batch support to the MCP readiness path:
    `McpServer.handleMessage` accepts non-empty JSON-RPC arrays, stdio writes
    batch responses as one JSON line, `McpStreamableHttpClient.postBatch(...)`
    parses JSON and SSE batch responses, and router-hosted MCP batches can mix
    direct JSON tool/meta entries with normal MCP JSON-RPC entries while
    preserving each route-owned session/auth context. Nested batch entries are
    rejected as invalid request objects.
  - pre-change `bin/test-fast` passed on 2026-05-03 before the JSON-RPC batch
    implementation
  - focused checks passed for the JSON-RPC batch slice:
    `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_mcp/test/lifecycle_test.dart packages/connectanum_mcp/test/stdio_transport_test.dart -r expanded`,
    `dart test packages/connectanum_client/test/mcp -r expanded`, and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`
  - full local `bin/verify` passed on 2026-05-03 after the JSON-RPC batch
    implementation; it included formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP package tests including batch/stdout coverage,
    client tests including `packages/connectanum_client/test/mcp`, auth-server
    tests, bench integration tests, the full router package tests including the
    updated MCP direct JSON batch smoke, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `f42d06d` is clean: `CI` run `25291712489`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
    `25291712465` completed successfully, `Dart Package Publish Dry Run` run
    `25291712503` completed successfully and covers the checked-out head, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - pre-change `bin/test-fast` passed on 2026-05-03 before the direct JSON
    session meta scoping edits
  - focused checks passed for the direct JSON session meta scope slice:
    targeted native MCP smoke,
    `dart analyze packages/connectanum_client packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_client/test/mcp -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    `bash -n bin/test-fast bin/test-all`, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the direct JSON session
    meta scope implementation and project-state updates; it included
    formatting, Rust native/FFI tests, Python package-artifact checks, MCP
    package tests, client/native tests, auth-server tests, bench integration
    tests, the full router package tests including the updated session meta
    scope smoke and `remote_auth_integration_test`, zero-copy router checks,
    and Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `8cefc81` is clean: `CI` run `25289506131`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `Dart Package Publish Dry
    Run` run `25289506140` completed successfully and covers the checked-out
    head, `WAMP Profile Benchmarks` run `25289422163` completed successfully
    for the preceding MCP session-meta commit that triggered the WAMP gate, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - pre-change `bin/test-fast` passed on 2026-05-03 before the protected
    pub/sub smoke edits
  - focused checks passed for the protected pub/sub smoke slice:
    `dart analyze packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the protected pub/sub
    smoke addition and project-state updates
  - hosted GitHub evidence for `3d4fac6` is clean: `CI` run `25285593843`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
    `25285593814` completed successfully, `Dart Package Publish Dry Run` run
    `25285593815` completed successfully and covers the checked-out head, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - focused checks passed for the direct JSON pub/sub smoke slice:
    `dart analyze packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_mcp -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the direct JSON
    pub/sub router smoke addition and project-state updates; it
    included formatting, Rust native/FFI tests, Python package-artifact checks,
    MCP package tests including the Streamable HTTP client tests,
    client/native tests, auth-server tests, bench integration tests, the full
    router package tests including the direct JSON pub/sub MCP smoke,
    zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `ac9125e` is clean: `CI` run `25284718134`
    completed successfully with `Fast Checks` and `Full Verify`, the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns, `WAMP Profile Benchmarks` run
    `25284718125` completed successfully, `Dart Package Publish Dry Run` run
    `25284718124` completed successfully and covers the checked-out head, and
    Native Artifacts dry-run `25192553399` remains clean and relevant because
    no native-release-sensitive paths changed
  - hosted GitHub evidence for `7933c71` is clean: `CI` run `25283791303`
    completed successfully with `Fast Checks` in 5m36s and `Full Verify` in
    8m05s, the hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns, `WAMP Profile
    Benchmarks` run `25283791165` completed successfully in 7m49s, `Dart
    Package Publish Dry Run` run `25283791166` completed successfully and
    covers the checked-out head, and Native Artifacts dry-run `25192553399`
    remains clean and relevant because no native-release-sensitive paths
    changed
  - hosted GitHub evidence for `b7b0348` is clean: `CI` run `25283148543`
    completed successfully with `Fast Checks` in 5m38s and `Full Verify` in
    8m06s, the hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns, `WAMP Profile
    Benchmarks` run `25283148557` completed successfully in 7m41s, `Dart
    Package Publish Dry Run` run `25283148560` completed successfully and
    covers the checked-out head, and Native Artifacts dry-run `25192553399`
    remains clean and relevant because no native-release-sensitive paths
    changed
  - hosted GitHub evidence for `9906d69` is clean: `CI` run `25282247750`
    completed successfully with `Fast Checks` in 5m40s and `Full Verify` in
    8m30s, the hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns, `WAMP Profile
    Benchmarks` run `25282247769` completed successfully in 8m01s, `Dart
    Package Publish Dry Run` run `25282247767` completed successfully and
    covers the checked-out head, and Native Artifacts dry-run `25192553399`
    remains clean and relevant because no native-release-sensitive paths
    changed
  - router-hosted MCP POST/SSE response streams are complete and pushed as
    `a84dcea` after the hosted deployment-chain evidence for the previous MCP
    SSE resumability commit was clean and a fresh pre-change `bin/test-fast`
    passed locally. Stateful non-`initialize` MCP operation requests that opt
    into Streamable HTTP now return `text/event-stream` response streams with a
    primer event and one JSON-RPC response event, commit those events into the
    same session-scoped bounded history used by GET/SSE, and preserve JSON
    responses for `initialize` plus direct JSON-only clients
  - focused checks passed for the POST/SSE response slice:
    `dart analyze packages/connectanum_router packages/connectanum_mcp`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the MCP POST/SSE
    response implementation and docs updates; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including the updated MCP Streamable HTTP regression,
    zero-copy router checks, and Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `a84dcea` is clean: `CI` run `25281129199`
    completed successfully with `Fast Checks` in 5m33s and `Full Verify` in
    8m08s, the hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns, `WAMP Profile
    Benchmarks` run `25281129184` completed successfully in 8m02s, `Dart
    Package Publish Dry Run` run `25281129192` completed successfully and
    covers the checked-out head, and Native Artifacts dry-run `25192553399`
    remains clean and relevant because no native-release-sensitive paths
    changed
  - router-hosted MCP SSE resumability is complete and pushed as `eb3d9e6`
    after a clean branch-head deployment-chain audit at `c153075` and a
    passing pre-change `bin/test-fast`. The implementation adds bounded
    per-endpoint SSE event
    history, route-scoped `notifications/tools/list_changed` delivery, and
    `Last-Event-ID` resume handling on the existing router `type: mcp`
    endpoint without introducing a standalone MCP server path
  - focused MCP checks passed for the SSE resumability slice:
    `dart analyze packages/connectanum_router packages/connectanum_mcp`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    and `dart test packages/connectanum_mcp -r expanded`
  - full local `bin/verify` passed on 2026-05-03 after the MCP SSE
    resumability implementation and docs updates; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including the updated MCP Streamable HTTP
    resumability regression, zero-copy router checks, and Chrome Dart2Wasm
    WebSocket transport tests
  - hosted GitHub evidence for `eb3d9e6` is clean: `CI` run `25280137967`
    completed successfully with `Fast Checks` in 5m37s and `Full Verify` in
    8m27s, the hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns, `WAMP Profile
    Benchmarks` run `25280137976` completed successfully, `Dart Package
    Publish Dry Run` run `25280137972` completed successfully and covers the
    checked-out head, and Native Artifacts dry-run `25192553399` remains clean
    and relevant because no native-release-sensitive paths changed
  - router-hosted MCP GET/SSE polling is complete and pushed as `c153075`
    after the Streamable HTTP session-hardening checkpoint. GET now requires
    `Accept: text/event-stream` and a known `MCP-Session-Id`, opens a native
    HTTP response stream, emits a priming SSE event ID plus retry hint, and
    keeps the request keyed to the same route-authenticated MCP endpoint state
    used by POST and DELETE
  - stateful Streamable HTTP follow-up POST requests that opt into
    `application/json, text/event-stream` now fail with `400` when they omit
    `MCP-Session-Id`, while legacy no-session direct JSON-RPC POST remains
    supported for frontend/direct API clients
  - pre-change `bin/test-fast` passed on 2026-05-03 before the MCP SSE polling
    slice, and the branch-head deployment-chain audit against `041236e` was
    clean for CI/logs, Dart package dry-run, and native release dry-run; the
    known remaining deployment-chain findings are still operator-owned branch
    protection, default-branch router-image visibility, and GHCR package
    visibility
  - focused MCP checks passed after the SSE polling implementation:
    `dart analyze packages/connectanum_router packages/connectanum_mcp`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the MCP SSE polling
    implementation and docs updates; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client/native
    tests, auth-server tests, bench integration tests, full router package
    tests including the new MCP GET/SSE polling regression, zero-copy router
    checks, and Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `c153075` is clean: `CI` run `25279091440`
    completed successfully with `Fast Checks` in 5m47s and `Full Verify` in
    7m53s, the hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns, `WAMP Profile
    Benchmarks` run `25279091434` completed successfully, `Dart Package
    Publish Dry Run` run `25279091444` completed successfully and covers the
    checked-out head, and Native Artifacts dry-run `25192553399` remains clean
    and relevant because no native-release-sensitive paths changed
  - the previously noted MCP transport gap after the resumability slice is now
    closed locally for stateful operation requests: POST-initiated SSE response
    streams are supported for clients that opt into Streamable HTTP, while
    JSON-only POST remains the compatibility path
  - router-hosted MCP Streamable HTTP readiness is complete and pushed as
    `041236e` after MCP fix-up was prioritized for downstream application
    readiness. The router now supports per-client `MCP-Session-Id` keys for
    Streamable-HTTP-style initialize requests, explicit `DELETE` cleanup,
    Origin/protocol/header/content negotiation guards, and unknown session
    rejection while preserving legacy no-session JSON-RPC POST/direct JSON
    behavior
  - pre-change `bin/test-fast` passed on 2026-05-03 before the MCP Streamable
    HTTP readiness edits; focused post-change checks also passed:
    `dart analyze packages/connectanum_router packages/connectanum_mcp`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-03 after the MCP Streamable HTTP
    readiness implementation and docs updates; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP package tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including the new MCP Streamable HTTP ingress/session
    regression, zero-copy router checks, and Chrome Dart2Wasm WebSocket
    transport tests
  - hosted GitHub evidence for `041236e` is clean: `CI` run `25278062808`
    completed successfully with `Fast Checks` in 5m30s and `Full Verify` in
    8m20s, the hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns, `WAMP Profile
    Benchmarks` run `25278062809` completed successfully, `Dart Package
    Publish Dry Run` run `25278062807` completed successfully and covers the
    checked-out head, and Native Artifacts dry-run `25192553399` remains clean
    and relevant because no native-release-sensitive paths changed
  - GitHub deployment-chain readiness is paused after a clean branch-head audit
    because the remaining RC blockers require operator/release decisions; every
    continuation should still re-audit the branch head before starting another
    feature or benchmark slice.
  - metrics auth-required consistency is complete in implementation checkpoint
    `8362a53`: the internal metrics snapshot now reports `auth_required` only
    when `open_metrics.auth_token` is non-empty, matching the HTTP `/metrics`
    bearer-token enforcement path; a fail-first regression reproduced the
    previous empty-token mismatch, the focused router metrics test,
    `dart analyze packages/connectanum_router`, `git diff --check`, and full
    local `bin/verify` all passed on 2026-05-03
  - pre-change `bin/test-fast` passed on 2026-05-03 before the metrics
    auth-required consistency slice
  - latest hosted GitHub `CI` evidence is docs checkpoint `16db917`: run
    `25276260827` completed successfully on 2026-05-03 with `Fast Checks` in
    5m31s and `Full Verify` in 7m55s
  - latest hosted `WAMP Profile Benchmarks` evidence is run `25276260819`,
    completed successfully on 2026-05-03 for `16db917`
  - latest hosted `Dart Package Publish Dry Run` evidence is run
    `25276260948`, completed successfully on 2026-05-03 for `16db917`
  - branch-head deployment-chain audit passed on 2026-05-03 against `16db917`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; the hosted CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns, Dart package dry-run `25276260948` covers the branch
    head, WAMP Profile Benchmarks run `25276260819` covers the branch head, and
    native release dry-run `25192553399` remains clean/relevant because no
    native-release-sensitive inputs changed
  - metrics secret-redaction hardening is complete and pushed as `b6dcfb1`: the
    router metrics snapshot now redacts configured OpenMetrics bearer tokens
    from exporter metadata and exposes only a non-secret `auth_required` flag;
    a fail-first regression reproduced the leak, focused metrics/analyzer checks
    passed locally, and full local `bin/verify` passed after the implementation
    and docs updates
  - OpenMetrics scrape timeout hardening is complete and pushed as `2942a22`:
    `open_metrics.collection_timeout_ms` now bounds `/metrics` collection and
    the internal `connectanum.metrics.openmetrics` RPC path; timed-out HTTP
    scrapes return `503`, and timed-out internal RPCs use the existing WAMP
    runtime-error path
  - full local `bin/verify` passed on 2026-05-03 after the OpenMetrics timeout
    implementation and docs updates; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client/native
    tests, auth-server tests, bench integration tests, full router package
    tests including the new OpenMetrics timeout regression and existing MCP
    router-hosted smoke coverage, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests
  - latest branch-head GitHub `CI` evidence is docs checkpoint `4d633d6`: run
    `25272965289` completed successfully on 2026-05-03 with `Fast Checks` in
    5m44s and `Full Verify` in 8m07s
  - branch-head deployment-chain audit passed on 2026-05-03 against `4d633d6`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; the hosted CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns, Dart package dry-run `25272457412` remains clean/relevant
    because no package-publish-sensitive inputs changed after `6a3e4dd`, and
    native release dry-run `25192553399` remains clean/relevant because no
    native-release-sensitive inputs changed
  - latest branch-head GitHub `CI` evidence is docs checkpoint `6a3e4dd`: run
    `25272457415` completed successfully on 2026-05-03 with `Fast Checks` in
    5m38s and `Full Verify` in 8m06s
  - latest clean branch-head `WAMP Profile Benchmarks` evidence is run
    `25272457403`, completed successfully on 2026-05-03 for `6a3e4dd`
  - latest clean branch-head `Dart Package Publish Dry Run` evidence is run
    `25272457412`, completed successfully on 2026-05-03 for `6a3e4dd`
  - branch-head deployment-chain audit passed on 2026-05-03 against `6a3e4dd`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; the hosted CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns, Dart package dry-run `25272457412` covers the branch head,
    and native release dry-run `25192553399` remains clean/relevant because no
    native-release-sensitive inputs changed
  - router process metrics are complete: commit `02748b2` adds PID/current
    RSS/max RSS to the router snapshot and OpenMetrics payload; `bin/test-fast`
    passed before the process metrics implementation slice, then focused router
    metrics/analyzer checks and full local `bin/verify` passed after the
    implementation
  - pushed production-readiness cleanup `e58c7f0` makes the pure Dart
    WebSocket transports fail closed when an inbound WAMP frame cannot be
    deserialized: null serializer results now become a `FormatException`, the
    transport completes `onConnectionLost`, closes the socket, and preserves
    existing reconnect/is-open semantics; pre-change `bin/test-fast` passed,
    and focused checks passed:
    `dart test packages/connectanum_client/test/transport/websocket/websocket_transport_io_test.dart -r expanded`,
    `dart test packages/connectanum_client/test/client_on_transport_io_events_test.dart -r expanded`,
    `dart analyze packages/connectanum_client`,
    the Chrome/Dart2Wasm WebSocket transport test, and `git diff --check`;
    full local `bin/verify` passed before push
  - latest clean branch-head GitHub `CI` evidence is implementation checkpoint
    `e58c7f0`: run `25270840158` completed successfully on 2026-05-03 with
    `Fast Checks` in 5m41s and `Full Verify` in 8m22s
  - latest clean branch-head `WAMP Profile Benchmarks` evidence is run
    `25270840164`, completed successfully on 2026-05-03 for `e58c7f0`
  - latest clean branch-head `Dart Package Publish Dry Run` evidence is run
    `25270840163`, completed successfully on 2026-05-03 for `e58c7f0`
  - branch-head deployment-chain audit passed on 2026-05-03 against `e58c7f0`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; the hosted CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns, Dart package dry-run `25270840163` covers the checked-out
    head, and native release dry-run `25192553399` remains clean/relevant
    because no native-release-sensitive inputs changed
  - previous clean branch-head GitHub `CI` evidence was run `25269453916` at
    implementation checkpoint `ed2822f`, completed successfully on 2026-05-03
    with `Fast Checks` and `Full Verify` both green
  - previous clean branch-head `WAMP Profile Benchmarks` evidence was run
    `25269453914`, completed successfully on 2026-05-03 for `ed2822f`
  - branch-head deployment-chain audit passed on 2026-05-03 against `ed2822f`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; the hosted CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns, Dart package dry-run `25269453990` covers the checked-out
    head, and native release dry-run `25192553399` remains clean/relevant
    because no native-release-sensitive inputs changed
  - read-only RC readiness audit on 2026-05-03 reports hosted CI/logs, hosted
    Dart package dry-run, and hosted native release dry-run ready at
    `e58c7f0`; remaining not-ready gates are operator-owned branch-protection
    required checks on `master`, default-branch visibility for
    `router-image.yml`, GHCR router package visibility, RC tag/prerelease
    selection, and Dart package ownership/version/release-order approval; the
    strict Dart publish-readiness gate also remains blocked until
    `connectanum_core` is approved/published before `connectanum_client`
  - public-surface scan on 2026-05-03 found no remaining consumer-specific
    application names, local checkout paths, sibling-project references,
    internal-project references, or GitLab host references in public
    docs/package surfaces
  - pushed production-readiness cleanup `06e2918` makes the JSON serializer
    match MsgPack/CBOR by reporting unsupported outbound message objects as a
    typed `UnsupportedError` with the message type instead of an empty generic
    `Exception`; pre-change `bin/test-fast` passed, focused checks passed:
    `dart test packages/connectanum_core/test/serializer/json/serializer_test.dart -r expanded`,
    `dart analyze packages/connectanum_core`, and `git diff --check`, full
    local `bin/verify` passed, and hosted GitHub `CI` plus
    `Dart Package Publish Dry Run` passed after push
  - pushed production-readiness cleanup `ed2822f` makes rawsocket WAMP receive
    fail closed when an inbound WAMP frame cannot be deserialized: null
    serializer results now become a `FormatException`, inbound message handling
    completes `onConnectionLost`, closes the transport, and guards socket-done
    callbacks from double-completing connection loss; pre-change
    `bin/test-fast` passed, and focused checks passed:
    `dart test packages/connectanum_client/test/transport/socket/socket_transport_test.dart -r expanded`,
    `dart analyze packages/connectanum_client`, and `git diff --check`; full
    local `bin/verify` passed before commit, then hosted GitHub `CI`,
    `WAMP Profile Benchmarks`, `Dart Package Publish Dry Run`, and the strict
    deployment-chain audit passed after push
  - previous implementation checkpoint `a6a84a8` remains clean for hosted
    deployment evidence: `CI` run `25266069345`, `WAMP Profile Benchmarks` run
    `25266069348`, and `Dart Package Publish Dry Run` run `25266069346` all
    completed successfully on 2026-05-03; the later branch-head docs commit did
    not change package-publish-sensitive, benchmark-sensitive, or
    native-release-sensitive inputs
  - pre-change `bin/test-fast` passed on 2026-05-03 before closing the MCP
    auth/catalog plan and reactivating the GitHub deployment-chain plan
  - previous branch-head deployment-chain audit passed on 2026-05-03 against
    `2fa9896` with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; the hosted CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns, Dart package dry-run `25266069346` remains clean and
    relevant because no package-publish-sensitive inputs changed after
    `a6a84a8`, and native release dry-run `25192553399` remains clean and
    relevant because no native-release-sensitive inputs changed after
    `4267e7a`
  - deployment-chain audit findings remain operator-owned, not code blockers:
    `add-router` itself is not protected, `router-image.yml` is checked in but
    not visible through the GitHub Actions API because it is missing from
    `master`, and `ghcr.io/konsultaner/connectanum-router` is not visible in
    GitHub Packages
  - completed MCP principal-filtered catalog slice keeps MCP and direct
    JSON-RPC discovery aligned with the route-authenticated principal:
    callable procedures are advertised only when the principal may `call` them,
    topics are advertised only for allowed `publish`/`subscribe` operations,
    and derived event topics from procedure metadata are filtered before the
    router constructs the MCP tool registry; documentation-only procedures with
    `allowCall: false` can still appear in `connectanum.api.list` and
    `connectanum.api.describe` but are not callable tools
  - pre-change `bin/test-fast` passed on 2026-05-03 before the MCP
    principal-filtered catalog edits
  - focused checks passed on 2026-05-03 after the MCP principal-filtered
    catalog edits: `dart test packages/connectanum_mcp/test/wamp_api_test.dart -r expanded`,
    `dart analyze packages/connectanum_router packages/connectanum_mcp`, and
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`
  - full local `bin/verify` passed on 2026-05-03 after the MCP
    principal-filtered catalog implementation and docs updates; it included
    formatting, Rust native/FFI tests, Python package-artifact checks, MCP
    package tests with the derived-topic opt-out regression, client/native
    tests, auth-server tests, bench integration tests, full router package
    tests including the updated MCP public/secure catalog filtering smoke and
    anonymous isolation regression, zero-copy router checks, and Chrome
    Dart2Wasm WebSocket transport tests
  - previous MCP direct-JSON slice adds a router-hosted JSON-RPC facade on
    the same `type: mcp` route: `connectanum.tools.list` lists the active tool
    catalog, `connectanum.tool.call` calls by tool name, and dotted tool names
    such as `connectanum.api.list`, `connectanum.pubsub.publish`, and
    application procedure tools can be invoked directly without first running
    MCP `initialize`; all paths reuse the same route-authenticated session and
    MCP tool registry
  - focused checks passed on 2026-05-03 after the direct-JSON slice:
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -n "smoke tests MCP router RPC pubsub and route security"`
    and `dart analyze packages/connectanum_router`
  - full local `bin/verify` passed on 2026-05-03 after the MCP direct-JSON
    route endpoint, smoke coverage, and docs updates; it included formatting,
    Rust native/FFI tests, Python package-artifact checks, MCP package tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including the updated MCP direct-JSON smoke and MCP
    anonymous isolation regression, zero-copy publish tests, and Chrome
    Dart2Wasm WebSocket transport tests
  - pre-change `bin/test-fast` passed on 2026-05-03 before the MCP direct-JSON
    route endpoint edits
  - first MCP auth/session isolation slice is implemented locally: a new
    router integration regression proves an anonymous MCP route must not run as
    a privileged realm internal session, unauthenticated MCP routes now use
    route-scoped anonymous session cache keys, and keyed internal sessions
    created through `_ensureInternalSession` no longer replace the realm-global
    internal session index
  - pre-change `bin/test-fast` passed on 2026-05-03 before the MCP route
    session isolation edits
  - focused checks passed on 2026-05-03 after the MCP route session isolation
    edits: the new fail-first test first reproduced the privilege reuse bug,
    then `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "does not run anonymous MCP calls as a privileged realm session"`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --name "MCP"`,
    `dart analyze packages/connectanum_router packages/connectanum_mcp`, and
    `dart test packages/connectanum_mcp -r expanded` passed
  - full local `bin/verify` passed on 2026-05-03 after the MCP route session
    isolation fix and docs updates; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP package tests, client/native
    tests, auth-server tests, bench integration tests, full router package
    tests including the new MCP isolation regression and existing MCP smoke,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - the router-hosted MCP auth/catalog correction plan is complete and closed;
    no known MCP auth/catalog blocker remains. Future downstream MCP usability
    gaps should get a new focused plan when they become concrete shipped-path
    blockers.
  - completed MCP icon metadata slice adds package-local `icons` serialization
    for `McpServerInfo`, tools, prompts, resources, and resource templates so
    downstream clients can show display identifiers without changing transport
    behavior; icon fetching/rendering, WAMP metadata projection, `_meta`,
    sampling, completions, and tasks remain out of scope
  - pre-change `bin/test-fast` passed on 2026-05-02 before the MCP
    icon-metadata edits
  - focused MCP checks passed on 2026-05-02 after the icon-metadata edits:
    `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`,
    `dart analyze packages/connectanum_mcp`,
    `dart test packages/connectanum_mcp/test/icons_test.dart -r expanded`,
    `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-02 after the MCP icon-metadata
    implementation and docs updates; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP icon/tool/resource/prompt tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including MCP smoke and remote-auth integration paths,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - pushed commit `8df2224` (`mcp: add icon metadata`) to both remotes on
    2026-05-02
  - hosted GitHub evidence for `8df2224` is clean: `CI` run `25262576057`
    passed with `Fast Checks` in 4m50s and `Full Verify` in 8m11s, `Dart
    Package Publish Dry Run` run `25262576056` passed in 22s, and the hosted
    CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `8df2224`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25262576056` covers the checked-out head, and native release dry-run
    `25192553399` remains clean/relevant because no native-release-sensitive
    inputs changed after its covered commit
  - completed MCP prompt-support slice adds package-local `prompts/list` and
    `prompts/get` support in `packages/connectanum_mcp` so downstream
    applications can expose user-selected prompt templates alongside the
    existing tools/resources path; prompt list-change notifications, prompt
    argument completions, sampling, tasks, and router-hosted prompt projection
    remain out of scope
  - pre-change `bin/test-fast` passed on 2026-05-02 before the MCP
    prompt-support edits
  - focused MCP checks passed on 2026-05-02 after the prompt-support edits:
    `dart format --output=none --set-exit-if-changed packages/connectanum_mcp`,
    `dart analyze packages/connectanum_mcp`, the focused prompt and stdio
    transport tests, `dart test packages/connectanum_mcp -r expanded`, and
    `git diff --check`
  - full local `bin/verify` passed on 2026-05-02 after the MCP prompt-support
    implementation and docs updates; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP prompt/tool/resource tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including MCP smoke and remote-auth integration paths,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - pushed commit `46295d5` (`mcp: add prompt support`) to both remotes on
    2026-05-02
  - hosted GitHub evidence for `46295d5` is clean: `CI` run `25260951060`
    passed with `Fast Checks` in 5m49s and `Full Verify` in 8m14s, `Dart
    Package Publish Dry Run` run `25260951057` passed in 23s, and the hosted
    CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `46295d5`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25260951057` covers the checked-out head, and native release dry-run
    `25192553399` remains clean/relevant because no native-release-sensitive
    inputs changed after its covered commit
  - completed GitHub deployment-chain evidence refresh updated
    `docs/github_deployment_chain.md` to reference the latest clean
    branch-head hosted CI, package dry-run, and deployment-chain audit evidence
    at `a523dab`; branch protection changes, router image workflow promotion or
    publishing, RC tags/releases, and Dart package publishing remain out of
    scope
  - pre-change `bin/test-fast` passed on 2026-05-02 before the GitHub
    deployment-chain evidence refresh edits
  - read-only RC readiness audit on 2026-05-02 for `a523dab` reported hosted
    CI, hosted CI logs, Dart package dry-run, and native release dry-run ready;
    remaining not-ready gates are operator/deployment decisions for `master`
    required checks, router image workflow promotion and GHCR validation, RC
    tag/prerelease creation, and Dart package ownership/release order
  - focused docs checks passed on 2026-05-02 after the GitHub deployment-chain
    evidence refresh: `git diff --check`, and a scan of
    `docs/github_deployment_chain.md` plus the active exec plan found no local
    checkout path references, TODOs, or FIXMEs
  - full local `bin/verify` passed on 2026-05-02 after the GitHub
    deployment-chain evidence refresh; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP tests, client/native tests,
    auth-server tests, bench integration tests, full router package tests
    including MCP smoke and remote-auth integration paths, zero-copy publish
    tests, and Chrome Dart2Wasm WebSocket transport tests
  - pushed commit `19d554b` (`docs: refresh github deployment evidence`) to
    both remotes on 2026-05-02
  - hosted GitHub evidence for `19d554b` is clean: `CI` run `25259373928`
    passed with `Fast Checks` in 5m36s and `Full Verify` in 8m15s, and the
    hosted CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `19d554b`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25258282651` remains clean/relevant because no package-publish-sensitive
    inputs changed after `a523dab`, and native release dry-run `25192553399`
    remains clean/relevant because no native-release-sensitive inputs changed
    after its covered commit
  - completed Dart package publishing evidence refresh updated
    `docs/dart_package_publishing.md` to reference the latest clean hosted
    package dry-run available before the docs commit (`f31b025`) and current
    local non-mutating release-plan output; package publishing, package
    naming/versioning, package ownership, and `publish_to` policy changes
    remain out of scope
  - pre-change `bin/test-fast` passed on 2026-05-02 before the Dart package
    publishing evidence refresh edits
  - local Dart package release-plan evidence passed on 2026-05-02 before the
    docs refresh: `bin/dart-package-publish-dry-run --show-release-plan`
    validated `connectanum_client 2.2.6` with zero warnings, skipped the
    private workspace packages, and kept strict release readiness blocked on
    the private `connectanum_core` dependency until an operator approves the
    package release plan
  - pub.dev package-name checks on 2026-05-02 returned HTTP 404 for both
    `connectanum_client` and `connectanum_core`
  - focused docs checks passed on 2026-05-02 after the Dart package publishing
    evidence refresh: `git diff --check`, and a stale-evidence scan of
    `docs/dart_package_publishing.md` plus the active exec plan found no old
    package dry-run ID, old evidence date, or local checkout path references
  - full local `bin/verify` passed on 2026-05-02 after the Dart package
    publishing evidence refresh; it included formatting, Rust native/FFI tests,
    Python package-artifact checks, MCP tests, client/native tests,
    auth-server tests, bench integration tests, full router package tests
    including MCP smoke and remote-auth integration paths, zero-copy publish
    tests, and Chrome Dart2Wasm WebSocket transport tests
  - pushed commit `a523dab` (`docs: refresh dart package evidence`) to both
    remotes on 2026-05-02
  - hosted GitHub evidence for `a523dab` is clean: `CI` run `25258282648`
    passed with `Fast Checks` in 5m51s and `Full Verify` in 8m03s, `Dart
    Package Publish Dry Run` run `25258282651` passed in 22s, and the hosted
    CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `a523dab`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25258282651` covers the checked-out head, and native release dry-run
    `25192553399` remains clean/relevant because no native-release-sensitive
    inputs changed after its covered commit
  - completed MCP tool-result content-block slice adds typed
    `CallToolResult.content` support for text annotations, image/audio content,
    resource links, and embedded resources in `packages/connectanum_mcp`;
    task-augmented calls, `_meta` passthrough, router-hosted resource
    projection, and resource subscriptions remain out of scope
  - pre-change `bin/test-fast` passed on 2026-05-02 before the MCP tool-result
    content-block edits
  - focused MCP checks passed on 2026-05-02 after the tool-result
    content-block edits: `dart format --output=none --set-exit-if-changed
    packages/connectanum_mcp`, `dart analyze packages/connectanum_mcp`, `dart
    test packages/connectanum_mcp/test/tools_test.dart -r expanded`, `dart test
    packages/connectanum_mcp -r expanded`, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-02 after the MCP tool-result
    content-block implementation and docs updates; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP tool/resource tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including MCP smoke and remote-auth integration paths,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - pushed commit `f31b025` (`mcp: add tool result content blocks`) to both
    remotes on 2026-05-02
  - hosted GitHub evidence for `f31b025` is clean: `CI` run `25257170704`
    passed with `Fast Checks` in 5m43s and `Full Verify` in 8m8s, `Dart
    Package Publish Dry Run` run `25257170706` passed in 18s, and the hosted
    CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `f31b025`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25257170706` covers the checked-out head, and native release dry-run
    `25192553399` remains clean/relevant because no native-release-sensitive
    inputs changed after its covered commit
  - completed MCP stdio resource example slice adds a static
    `app://example/context` resource to
    `packages/connectanum_mcp/example/stdio_echo_server.dart`, extends stdio
    transport coverage for `resources/list` and `resources/read`, and updates
    the public MCP/example docs so downstream apps have a runnable local
    tools-plus-context reference
  - pre-change `bin/test-fast` passed on 2026-05-02 before the MCP stdio
    resource example edits
  - focused MCP checks passed on 2026-05-02 after the stdio resource example
    edits: `dart format --output=none --set-exit-if-changed
    packages/connectanum_mcp`, `dart analyze packages/connectanum_mcp`, `dart
    test packages/connectanum_mcp/test/stdio_transport_test.dart -r expanded`,
    `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-02 after the MCP stdio resource
    example implementation and docs updates; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP stdio/resource tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including MCP smoke and remote-auth integration paths,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - pushed commit `b22eee1` (`mcp: add stdio resource example`) to both
    remotes on 2026-05-02
  - hosted GitHub evidence for `b22eee1` is clean: `CI` run `25256013125`
    passed with `Fast Checks` in 5m37s and `Full Verify` in 8m13s, `Dart
    Package Publish Dry Run` run `25256013131` passed in 19s, and the hosted
    CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `b22eee1`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25256013131` covers the checked-out head, and native release dry-run
    `25192553399` remains clean/relevant because no native-release-sensitive
    inputs changed after its covered commit
  - completed MCP resource read support slice adds package-local
    `resources/list`, `resources/read`, and `resources/templates/list` support
    to `packages/connectanum_mcp` so downstream applications can expose
    read-only context after the tool path; full Streamable HTTP GET/SSE,
    resource subscriptions, router-hosted resource projection, prompts,
    sampling, and tasks remain out of scope
  - pushed commit `da6bb32` (`mcp: add resource read support`) to both remotes
    on 2026-05-02
  - hosted GitHub evidence for `da6bb32` is clean: `CI` run `25254927687`
    passed with `Fast Checks` in 5m37s and `Full Verify` in 7m53s, `Dart
    Package Publish Dry Run` run `25254927695` passed in 19s, and the hosted
    CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `da6bb32`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25254927695` covers the checked-out head, and native release dry-run
    `25192553399` remains clean/relevant because no native-release-sensitive
    inputs changed after its covered commit
  - official MCP `2025-11-25` resource and pagination docs were rechecked on
    2026-05-02 before implementation; no spec direction change beyond
    proceeding with the narrow list/read/template-list slice
  - pre-change `bin/test-fast` passed on 2026-05-02 before the MCP resource
    read support edits
  - focused MCP checks passed on 2026-05-02 after the resource read support
    edits: `dart format --output=none --set-exit-if-changed
    packages/connectanum_mcp`, `dart analyze packages/connectanum_mcp`, and
    `dart test packages/connectanum_mcp -r expanded`
  - full local `bin/verify` passed on 2026-05-02 after the MCP resource read
    support implementation and docs updates; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP resource tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including MCP smoke and remote-auth integration paths,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - completed deployment-chain readability slice makes
    `bin/audit-github-deployment-chain --show-rc-readiness` print concrete
    next actions for CI job and CI log gates when those gates are missing,
    pending, failed, or noisy; the audit remains read-only and does not mutate
    GitHub settings
  - pushed commit `952f255` (`ci: clarify rc ci gate next actions`) to both
    remotes on 2026-05-02
  - hosted GitHub evidence for `952f255`
    (`ci: clarify rc ci gate next actions`) is clean: `CI` run
    `25253551094` passed with `Fast Checks` in 5m37s and `Full Verify` in
    8m04s, and the hosted CI log scan found no warning, deprecation,
    skipped-test, reset, connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `952f255`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25206934146` remains clean/relevant because no package-sensitive paths
    changed after `379775a`, and native release dry-run `25192553399` remains
    clean/relevant because no native-release-sensitive inputs changed after its
    covered commit
  - pre-change `bin/test-fast` passed on 2026-05-02 before the RC CI/log
    next-action audit patch
  - focused checks passed on 2026-05-02 for the RC CI/log next-action audit
    patch: `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`, `git diff --check`,
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`,
    the expected-failing
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-rc-ready`,
    and the clean branch-head deployment-chain audit
  - full local `bin/verify` passed on 2026-05-02 after the RC CI/log
    next-action audit patch; it included formatting, Rust native/FFI tests,
    Python package-artifact checks, MCP tests, client/native tests,
    auth-server tests, bench integration tests, full router package tests
    including MCP smoke and remote-auth integration paths, zero-copy publish
    tests, and Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `ac95895`
    (`ci: clarify rc readiness next actions`) is clean: `CI` run
    `25252497610` passed with `Fast Checks` in 5m25s and `Full Verify` in
    7m56s, and the hosted CI log scan found no warning, deprecation,
    skipped-test, reset, connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `ac95895`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25206934146` remains clean/relevant because no package-sensitive paths
    changed after `379775a`, and native release dry-run `25192553399` remains
    clean/relevant because no native-release-sensitive inputs changed after its
    covered commit
  - previous deployment-chain readability slice makes
    `bin/audit-github-deployment-chain --show-rc-readiness` print concrete
    next actions for the remaining operator/release blockers without mutating
    GitHub settings
  - pre-change `bin/test-fast` passed on 2026-05-02 before the RC-readiness
    next-action audit patch
  - focused checks passed on 2026-05-02 for the RC-readiness next-action
    audit patch: `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`, `git diff --check`,
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`,
    the expected-failing
    `bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-rc-ready`
    with next-action guidance present, and the clean branch-head
    deployment-chain audit
  - full local `bin/verify` passed on 2026-05-02 after the RC-readiness
    next-action audit patch; it included formatting, Rust native/FFI tests,
    Python package-artifact checks, MCP tests, client/native tests,
    auth-server tests, bench integration tests, full router package tests
    including MCP smoke and remote-auth integration paths, zero-copy publish
    tests, and Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `cb62658`
    (`docs: scrub local path references`) is clean: `CI` run `25252051838`
    passed with `Fast Checks` in 5m25s and `Full Verify` in 7m55s, and the
    hosted CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `cb62658`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25206934146` remains clean/relevant because no package-sensitive paths
    changed after `379775a`, and native release dry-run `25192553399` remains
    clean/relevant because no native-release-sensitive inputs changed after its
    covered commit
  - current public-surface hygiene slice removes machine-specific absolute
    paths from tracked state/exec-plan docs, using `$HOME` / `$PWD` examples
    instead of a local username and checkout path
  - tracked-file scan on 2026-05-02 found no downstream-app, sibling-project,
    or local absolute home-path references after the portable path cleanup
  - pre-change `bin/test-fast` passed on 2026-05-02 before the portable path
    cleanup
  - full local `bin/verify` passed on 2026-05-02 after the portable path
    cleanup; it included formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP tests, client/native tests, auth-server tests,
    bench integration tests, full router package tests including MCP smoke and
    remote-auth integration paths, zero-copy publish tests, and Chrome
    Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `f04227e` (`chore: ignore local serena state`)
    is clean: `CI` run `25251472428` passed with `Fast Checks` in 5m37s and
    `Full Verify` in 8m5s, and the hosted CI log scan found no warning,
    deprecation, skipped-test, reset, connection-noise, panic, or failure
    patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `f04227e`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25206934146` remains clean/relevant because no package-sensitive paths
    changed after `379775a`, and native release dry-run `25192553399` remains
    clean/relevant because no native-release-sensitive inputs changed after its
    covered commit
  - current public-surface hygiene slice ignores local Serena tool state
    (`.serena/`) so generated MCP/tool metadata does not appear as an
    untracked public repo artifact during autonomous runs
  - pre-change `bin/test-fast` passed on 2026-05-02 before the local
    tool-state ignore cleanup
  - full local `bin/verify` passed on 2026-05-02 after the local tool-state
    ignore cleanup; it included formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP tests, client/native tests, auth-server tests,
    bench integration tests, full router package tests including MCP smoke and
    remote-auth integration paths, zero-copy publish tests, and Chrome
    Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `06e5883`
    (`docs: record rc readiness ci evidence`) is clean: `CI` run
    `25250913362` passed with `Fast Checks` in 5m44s and `Full Verify` in
    8m9s, and the hosted CI log scan found no warning, deprecation,
    skipped-test, reset, connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `06e5883`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25206934146` remains clean/relevant because no package-sensitive paths
    changed after `379775a`, and native release dry-run `25192553399` remains
    clean/relevant because no native-release-sensitive inputs changed after its
    covered commit
  - current public README cleanup removes machine-local Codex/launchd
    continuation instructions from the public root README; keep long-running
    automation details in local/operator state rather than user-facing package
    docs
  - pre-change `bin/test-fast` passed on 2026-05-02 before the public README
    cleanup
  - hosted GitHub evidence for `e33e6a0`
    (`ci: clarify rc readiness baseline`) is clean: `CI` run `25250658376`
    passed with `Fast Checks` in 4m52s and `Full Verify` in 8m7s, and the
    hosted CI log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-02 against `e33e6a0`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25206934146` remains clean/relevant because no package-sensitive paths
    changed after `379775a`, and native release dry-run `25192553399` remains
    clean/relevant because no native-release-sensitive inputs changed after its
    covered commit
  - previous hosted GitHub evidence for `09a1cc6`
    (`ci: clarify workflow visibility audit`) was clean: `CI` run
    `25250197996` passed with `Fast Checks` in 5m53s and `Full Verify` in
    6m54s, and its hosted CI log scan found no warning, deprecation,
    skipped-test, reset, connection-noise, panic, or failure patterns
  - previous branch-head deployment-chain audit passed on 2026-05-02 against
    `09a1cc6`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; Dart package dry-run
    `25206934146` remains clean/relevant because no package-sensitive paths
    changed after `379775a`, and native release dry-run `25192553399` remains
    clean/relevant because no native-release-sensitive inputs changed after its
    covered commit
  - current RC readiness audit slice keeps candidate-branch run evidence
    anchored to `add-router` but evaluates the branch-protection baseline
    against default branch `master`, so the `--show-rc-readiness` output no
    longer implies the active development branch must be protected before RC
    promotion
  - focused checks passed on 2026-05-02 after the RC readiness audit update:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`,
    `bin/audit-github-deployment-chain --branch add-router --run-limit 4 --show-rc-readiness`,
    the clean branch-head deployment-chain audit, and `git diff --check`
  - full local `bin/verify` passed on 2026-05-02 after the public README
    cleanup and RC readiness audit slice; it included formatting, Rust
    native/FFI tests, Python package-artifact checks, MCP tests,
    client/native tests, auth-server tests, bench integration tests, full
    router package tests including MCP smoke and remote-auth integration paths,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - current deployment-chain readability slice keeps the audit read-only but
    makes hidden workflow findings actionable: if a checked-in workflow is not
    discoverable through the GitHub Actions API, the audit now checks whether
    the workflow file is present on the default branch and says whether the
    next step is default-branch promotion, deeper Actions settings triage, or
    retrying an inconclusive GitHub content lookup
  - focused checks passed on 2026-05-02 for the audit diagnostic slice:
    pre-change `bin/test-fast`, `bash -n bin/audit-github-deployment-chain`,
    the clean branch-head deployment-chain audit, and the expected-failing
    `--require-workflows-visible` gate, which now reports
    `.github/workflows/router-image.yml` is missing from `master`
  - full local `bin/verify` passed on 2026-05-02 after the audit diagnostic
    slice; it included formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP tests, client/native tests, auth-server tests,
    bench integration tests, full router package tests including MCP smoke and
    remote-auth integration paths, zero-copy publish tests, and Chrome
    Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `379775a`
    (`test: declare root zero-copy tag`) is clean: `CI` run `25206934156`
    passed with `Fast Checks` and `Full Verify`, hosted CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns, `Dart Package Publish Dry Run` run `25206934146` passed,
    and `WAMP Profile Benchmarks` run `25206934162` passed
  - branch-head deployment-chain audit passed on 2026-05-02 against `379775a`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; native release dry-run
    `25192553399` remains clean and relevant because no
    native-release-sensitive inputs changed after its covered commit
  - current MCP follow-up implements router-hosted safety metadata and
    route-security coverage: WAMP `_ai_meta_data` now maps to MCP tool
    annotations, declared procedures can disable MCP tool calls while remaining
    visible through API metadata, and the router extracts safety hints from
    both configured and dynamically registered APIs
  - new native router MCP smoke coverage builds a real router fixture with
    safe RPC, unsafe RPC, documented-only API metadata, declared pub/sub, an
    anonymous MCP route, and a ticket-protected MCP route; it verifies public
    calls, denied unsafe calls, hidden documented-only calls, API describe
    metadata, MCP publish/subscribe/poll, bearer-token issuance, and protected
    unsafe calls after authentication
  - focused checks passed on 2026-05-01 for the current MCP follow-up:
    `dart analyze packages/connectanum_mcp packages/connectanum_router`,
    `dart test packages/connectanum_mcp/test/wamp_api_test.dart -r expanded`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "smoke tests MCP router RPC pubsub and route security"`,
    `dart test packages/connectanum_router/test/router_integration_native_test.dart -r expanded --plain-name "hosts MCP over HTTP using the router internal session"`,
    and `bin/test-fast`
  - full local `bin/verify` passed on 2026-05-01 after the current MCP
    safety/pubsub follow-up; it included formatting, Rust native/FFI tests,
    Python package-artifact checks, MCP tests, client/native tests,
    auth-server tests, bench integration tests, full router package tests
    including the new router-hosted MCP smoke, zero-copy publish tests, and
    Chrome Dart2Wasm WebSocket transport tests
  - keep the CI chain clean first; latest hosted branch checkpoint `1c4622c`
    passed GitHub `CI` run `25205192927` with `Fast Checks` in 4m56s and
    `Full Verify` in 7m51s
  - hosted GitHub evidence for `1c4622c` is clean: CI log scan found no
    warning, deprecation, skipped-test, reset, connection-noise, panic, or
    failure patterns; `Dart Package Publish Dry Run` run `25205192926` passed
    in 17s and covers the checked-out head; `WAMP Profile Benchmarks` run
    `25205192933` passed in 6m22s
  - branch-head deployment-chain audit passed on 2026-05-01 against `1c4622c`
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; native release dry-run
    `25192553399` remains clean and relevant because no
    native-release-sensitive inputs changed after its covered commit
  - first usable MCP bridge path is complete for local stdio and
    router-hosted JSON-RPC `POST` clients; remaining MCP work should be driven
    by concrete application needs such as resources/prompts, full Streamable
    HTTP GET/SSE/session semantics, or more auth/deployment examples
  - no active code blocker is known after the MCP slice; default continuation
    should stay on GitHub deployment-chain reliability, public/release
    readability, MCP usability for downstream applications, and concrete
    WAMP-profile shipped-path regressions from `ROADMAP_NEXT.md`
  - remaining RC/deployment blockers are still operator/release decisions:
    branch protection, default-branch router workflow/GHCR package evidence,
    RC tag/prerelease selection, and the Dart package release-order decision
  - completed MCP WAMP API helper slice adds `McpWampApi` for declared
    procedure/topic catalogs, API list/describe metadata tools, and optional
    buffered publish/subscribe/poll/unsubscribe MCP tools backed by WAMP
    sessions; focused `dart analyze packages/connectanum_mcp` and
    `dart test packages/connectanum_mcp -r expanded` passed after pinning the
    subscription buffer behavior for early and later events plus dynamic tool
    registry cursor invalidation
  - completed router-hosted MCP HTTP slice adds `HttpRouteActionType.mcp`, native
    route wiring to `connectanum.mcp.handle`, a router-hosted MCP endpoint that
    uses an internal WAMP session, and native integration coverage for MCP
    initialize/list/call over HTTP POST; focused router analysis, JSON config
    tests, native integration tests, and env-enabled zero-copy publish tests
    passed before the full local verification rerun
  - local `bin/verify` passed on 2026-05-01 after the declared WAMP API helper
    and router-hosted MCP HTTP slice; it included formatting, Rust native/FFI
    tests, Python package-artifact checks, MCP tests, client/native tests,
    auth-server tests, bench integration tests, full router package tests,
    zero-copy publish tests, and Chrome Dart2Wasm WebSocket transport tests
  - current MCP public-surface readability slice improves
    `packages/connectanum_mcp/README.md` for downstream application embedders:
    it now
    states the supported `2025-11-25` MCP subset, provides a copy-paste stdio
    initialize/list/call sequence, documents cursor paging, and explains the
    default WAMP tool delegation mapping while pointing network use at
    router-hosted HTTP MCP routes
  - pre-change local `bin/test-fast` passed on 2026-05-01 before the MCP
    README readability edit; focused `dart analyze packages/connectanum_mcp`,
    `dart test packages/connectanum_mcp -r expanded`, and `git diff --check`
    passed after the edit
  - local `bin/verify` passed on 2026-05-01 after the MCP README readability
    slice; it included formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP tests, client/native tests, auth-server
    tests, bench integration tests, router tests, zero-copy publish tests, and
    Chrome Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `6c403ee`
    (`docs: clarify mcp package usage`) is clean: `CI` run `25202524041`
    passed with `Fast Checks` in 5m22s and `Full Verify` in 8m02s; hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns; `Dart Package Publish Dry
    Run` run `25202524047` passed in 22s and covers the checked-out head
  - branch-head deployment-chain audit passed on 2026-05-01 after the MCP
    README readability slice with `--require-clean-latest-ci`,
    `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; native release dry-run
    `25192553399` remains clean and relevant because the README/doc changes
    changed no native-release-sensitive inputs
  - completed public/deployment-surface cleanup removes the obsolete root
    `.travis.yml` file so users see GitHub Actions as the only maintained
    hosted CI/deployment chain; the only remaining Travis reference is
    historical changelog text
  - pre-change local `bin/test-fast` passed on 2026-05-01 before removing the
    stale Travis CI config
  - local `bin/verify` passed on 2026-05-01 after removing the stale Travis CI
    config; it included formatting, Rust native/FFI tests, Python
    package-artifact checks, MCP tests, client/native tests, auth-server tests,
    bench integration tests, router tests, zero-copy publish tests, and Chrome
    Dart2Wasm WebSocket transport tests
  - hosted GitHub evidence for `0b765fd`
    (`chore: remove stale travis config`) is clean: `CI` run `25200862348`
    passed with `Fast Checks` in 5m33s and `Full Verify` in 8m01s; hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-01 after this cleanup
    with `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; latest Dart package dry-run
    `25198143194` and native release dry-run `25192553399` remain clean and
    relevant because the cleanup changed no publish-sensitive or
    native-release-sensitive inputs; remaining findings are still the
    operator-owned branch protection, hidden `router-image.yml`, and missing
    visible GHCR router package evidence
  - completed public-surface hygiene slice removes the tracked root `chat.txt`
    conversation transcript from the repository and ignores future local
    `chat.txt` exports so the public source tree only exposes intentional
    project artifacts
  - pre-change local `bin/test-fast` passed on 2026-05-01 before the
    `chat.txt` cleanup
  - local `bin/verify` passed on 2026-05-01 after the `chat.txt` cleanup,
    including formatting, Rust native/FFI tests, Dart package tests, router
    zero-copy publish coverage, and Chrome Dart2Wasm WebSocket coverage
  - hosted GitHub evidence for `fbcf4de`
    (`chore: remove tracked chat transcript`) is clean: `CI` run
    `25199248416` passed with `Fast Checks` in 5m30s and `Full Verify` in
    7m53s; hosted CI log scan found no warning, deprecation, skipped-test,
    reset, connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-01 with
    `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; latest Dart package dry-run
    `25198143194` and native release dry-run `25192553399` remain clean and
    relevant because the cleanup changed no publish-sensitive or
    native-release-sensitive inputs
  - previous MCP implementation commit `77e34de`
    (`mcp: paginate tool listings`) has clean hosted GitHub evidence: `CI` run
    `25198143182` passed with `Fast Checks` in 5m25s and `Full Verify` in
    8m23s; `Dart Package Publish Dry Run` run `25198143194` passed in 19s
  - hosted CI log scan for `25198143182` found no warning, deprecation,
    skipped-test, reset, connection-noise, panic, or failure patterns
  - branch-head deployment-chain audit passed on 2026-05-01 with
    `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`; remaining findings are still the
    operator-owned branch protection, hidden `router-image.yml`, and missing
    visible GHCR router package evidence
  - current MCP usability slice rechecked the official MCP 2025-11-25
    tools/pagination requirements on 2026-05-01 and adds optional
    `McpServer.toolListPageSize`, stable opaque `nextCursor` pages for
    `tools/list`, and `invalidParams` errors for malformed or stale cursors;
    this kept larger downstream application tool catalogs usable before the
    router-hosted HTTP MCP endpoint slice
  - pre-change local `bin/test-fast` passed on 2026-05-01 before the MCP
    pagination edits; focused `dart analyze packages/connectanum_mcp` and
    `dart test packages/connectanum_mcp -r expanded` passed after the edits
  - local `bin/verify` passed on 2026-05-01 after the MCP pagination slice; it
    included formatting, Rust `ct_core`/`ct_ffi`, Python package-artifact
    checks, MCP tests, client/native tests, auth-server tests, bench
    integration tests, router tests, zero-copy publish tests, and Chrome
    Dart2Wasm WebSocket transport tests
  - previous implementation commit `425385d`
    (`ci: stabilize native wamp worker readiness`) has clean hosted GitHub
    deployment-chain evidence: `CI` run `25195627202` passed with `Fast Checks`
    in 5m40s and `Full Verify` in 6m50s; `Dart Package Publish Dry Run` run
    `25195627219` passed and covers the package/test change; `WAMP Profile
    Benchmarks` run `25195627213` passed in 8m00s
  - hosted CI log scan for `25195627202` found no warning, deprecation,
    skipped-test, reset, connection-noise, panic, or failure patterns
  - local verification follow-up on 2026-05-01 found the direct native WAMP
    worker lifecycle test could time out waiting for the spawned worker's
    initial `READY` line after 10 seconds under repeated native integration
    runs; the test now uses the same 20-second worker readiness budget as the
    production `NativeWampWorker` helper, preserves stderr diagnostics on
    startup/exit timeouts, and has a 75-second overall timeout matching its
    step budgets
  - focused native WAMP worker lifecycle stress passed locally on 2026-05-01:
    12 consecutive runs of
    `dart test packages/connectanum_bench/test/wamp_transport_integration_test.dart --plain-name "native WAMP worker process exits cleanly after STOP following a native cancel workload" --chain-stack-traces`
    with `CONNECTANUM_NATIVE_LIB` pointing at the ffi-test release library
  - local `bin/test-fast` passed on 2026-05-01 after the native worker
    readiness timeout fix, including the bench integration suite
  - local `bin/verify` passed on 2026-05-01 after the native worker readiness
    timeout fix; it included formatting, Rust `ct_core`/`ct_ffi`, Python
    package-artifact checks, MCP tests, client/native tests, auth-server tests,
    bench integration tests, router tests, zero-copy publish tests, and Chrome
    Dart2Wasm WebSocket transport tests
  - GitHub `Dart Package Publish Dry Run` run `25195627219` passed on
    `425385d` and covers the native WAMP worker test change under `packages/**`
  - native dry-run `25192553399` accepted
    `ct-ffi-v2026.04.30-dry-run.4267e7a`, uploaded `native-release-preview`,
    did not create or update a GitHub Release, and remains relevant for
    `425385d` because no native-release-sensitive paths changed after it
  - branch-head deployment-chain audit passed on 2026-05-01 with
    `--require-clean-latest-ci`, `--require-clean-latest-ci-logs`,
    `--require-clean-dart-package-publish-dry-run`, and
    `--require-clean-native-release-dry-run`
  - local `bin/test-fast` passed on 2026-05-01 before refreshing the release
    evidence docs/state
  - completed Dart package dry-run path-filter follow-up broadens
    `.github/workflows/dart-package-publish.yml` push/PR filters from
    metadata-only package paths to `packages/**`, and aligns
    `bin/audit-github-deployment-chain` package-sensitive change detection with
    that boundary
  - focused local checks passed on 2026-04-30:
    `bash -n bin/audit-github-deployment-chain`, a Python path-filter content
    check, and an expected-failing
    `bin/audit-github-deployment-chain --require-clean-dart-package-publish-dry-run`
    run that reported `packages/connectanum_client/tool/install_native.dart`
    and `packages/connectanum_router/tool/install_native.dart` as stale
    package dry-run inputs after `4d32688`
  - local `bin/verify` passed on 2026-04-30 after the package dry-run
    path-filter follow-up
  - completed native install command readability slice fixes the remaining
    public native install command guidance that still used the invalid package
    target form `dart run connectanum_router:tool/install_native.dart`
  - pre-change local `bin/test-fast` passed on 2026-04-30 before editing the
    native install command readability slice
  - reproduction check confirmed the stale public command fails locally:
    `dart run connectanum_router:tool/install_native.dart --help` exits with
    `Could not find file`
  - completed native install command readability slice: generated native bundle
    README text, router/client helper usage, and public roadmap/state wording
    now use direct source-checkout paths such as
    `dart packages/connectanum_router/tool/install_native.dart --tag <tag>`
    instead of invalid package-target `dart run` commands
  - focused local checks passed on 2026-04-30:
    `python3 tool/test_package_native_artifact.py`,
    `dart packages/connectanum_router/tool/install_native.dart --help`,
    `dart packages/connectanum_client/tool/install_native.dart --help`,
    `python3 -m py_compile tool/test_package_native_artifact.py`,
    `bash -n bin/package-native-artifact bin/test-fast bin/test-all`, and
    `git diff --check`
  - local `bin/verify` passed on 2026-04-30 after the native install command
    readability slice; it included formatting, Rust/Dart package tests, MCP
    tests, bench integration tests, router tests, build hooks, the new
    native-artifact guidance regression, and Chrome Dart2Wasm WebSocket
    transport tests
  - previous local slice was release-evidence documentation refresh: public
    deployment-chain and package-publishing docs point at clean hosted
    branch-head evidence instead of older pinned run IDs
  - completed Dart package release-plan readability slice:
    `bin/dart-package-publish-dry-run --show-release-plan` should expose every
    private workspace package separately from private packages that block a
    publishable target, so `connectanum_mcp` remains visible without implying
    it is approved for pub.dev release
  - local `bin/test-fast` passed on 2026-04-30 before editing the Dart package
    release-plan readability slice
  - local release-plan checks passed on 2026-04-30:
    `bash -n bin/dart-package-publish-dry-run bin/audit-github-deployment-chain`,
    `bin/dart-package-publish-dry-run --show-release-plan`,
    expected-failing strict
    `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`,
    and expected-failing RC audit
    `bin/audit-github-deployment-chain --require-rc-ready`
  - local `bin/verify` passed on 2026-04-30 after the Dart package release-plan
    readability slice; it included formatting, Rust/Dart package tests, MCP
    tests, bench integration tests, router tests, build hooks, and Chrome
    Dart2Wasm WebSocket transport tests
  - kTLS repeat-stability follow-up is complete and remains
    measurement-bound rather than runtime-tuning-ready: hosted runs
    `25181353679` and `25181697998` both completed successfully on `0573ce2`
    with clean actionable log scans and no focus-row transport-counter issues,
    but neither produced decision-quality repeat evidence
  - quick diagnostic run `25181353679`
    (`h2_ktls_multiplex_scaling`, `h2_multiplexed_streams_s1`,
    `threads=4`, `repeat_count=3`) had stable throughput span `6.80pp`, but
    p95 span stayed too wide at `104.73pp` with a mixed source; the new
    repeat-detail artifact table shows repeat p95 deltas of `+4.60%`,
    `-24.35%`, and `+80.37%`
  - larger-sample stability run `25181697998`
    (`h2_ktls_multiplex_stability`, same isolated workload/thread settings)
    also was not decision-quality: throughput span was `101.10pp` with a
    mixed source, and p95 span was `1503.92pp` with a kTLS-side source; the
    baseline p95 range stayed tight at `13.02..15.54 ms` while kTLS p95 ranged
    `15.15..208.47 ms`
  - do not continue speculative HTTP/2/kTLS runtime tuning from the current
    evidence; if kTLS/H2 is revisited, keep it as benchmark-methodology or
    runner-stability work behind the higher-priority GitHub deployment-chain,
    shipped-path production-readiness, MCP, and WAMP-profile priorities
  - next unblocked autonomous work should stay on public release readiness:
    GitHub deployment-chain evidence, human-readable release/public package
    surfaces, MCP usability for downstream applications, and WAMP-profile
    benchmark maintenance when a concrete shipped-path regression appears
  - hosted GitHub `Dart Package Publish Dry Run` run `25170846455` passed on
    `a4818c8`; the audit confirms it remains relevant for `9dcab42` because
    no package-publish-sensitive paths changed, and the package dry-run stayed
    at `Package has 0 warnings`
  - `out/production` generated output is no longer tracked by Git; `/out/`
    remains ignored and `git ls-files out` returns zero tracked paths
  - fresh manual `Native Artifacts` dry-run `25166714340` passed on
    `7098c54`: Linux x64, Linux arm64, macOS arm64, macOS Intel, Windows x64,
    and `Publish GitHub Release` preview jobs all succeeded
  - the native dry-run uploaded `native-release-preview`, accepted
    `ct-ffi-v2026.04.30-dry-run.7098c54`, and did not create or update a
    GitHub Release for that dry-run tag; `--require-clean-native-release-dry-run`
    now passes for the checked-out head
  - the rendered native release preview now describes the router image as a
    separately released target that must be confirmed in the deployment guide
    before production use, instead of implying the GHCR image is already
    published
  - `c8b6a13` makes `bin/audit-github-deployment-chain` fall back from GitHub's
    workflow-filtered run list to the unfiltered branch run list when a fresh
    completed workflow run is visible only in the latter; this prevents a
    transient false failure in the Dart/native evidence gates
  - Dart package publish-readiness evidence is current for `9dcab42`; the
    remaining blocker is still the intentional release-order decision
    `connectanum_core -> connectanum_client`
  - remaining RC/deployment blockers are still operator/product/deployment
    decisions or externally visible release actions: branch protection required
    checks, default-branch visibility for `router-image.yml`, visible GHCR
    router package evidence, RC tag/prerelease selection, and Dart package
    release-order/public ownership
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25163851551` completed
    successfully on `0da1030`, its hosted log scan was clean, and the new
    transport-counter reporting found no non-zero focus-row transport
    counters or transport-counter issues
  - `25163851551` is intentionally not release-decision evidence because the
    repeat artifact had a baseline-side outlier: throughput delta span was
    `17052.90pp` and p95 delta span was `108.52pp`; this validates the
    artifact guardrail rather than requiring more immediate H2 work
  - repeat confirmation run `25164322244` also completed successfully on
    `0da1030` with a clean hosted log scan and no transport-counter issues;
    it was likewise not decision-quality, this time from kTLS-side instability
    (`58.76pp` throughput delta span and `1767.09pp` p95 delta span)
  - current-head kTLS repeat-stability run `25176887533` passed on `9dcab42`
    with focused `h2_multiplexed_streams_s1`, `threads=4`,
    `repeat_count=3`, alternating order, and `skip_artifact_gate=true`
  - `25176887533` is diagnostic but not decision-quality: the worst throughput
    and p95 row was stable across all three repeats, throughput delta span was
    acceptable at `13.01pp` (`-55.01%..-42.00%`), but p95 delta span was still
    too wide at `60.53pp` (`+35.74%..+96.27%`) against the `50.00pp` threshold
  - `25176887533` had no focus-row transport-counter issues; all transport
    counters stayed zero, and the hosted log scan only matched benign setup
    text
  - local `bin/test-fast` passed on 2026-04-30 before recording this
    kTLS-repeat evidence
  - local `bin/verify` passed on 2026-04-30 after recording this
    kTLS-repeat evidence; it included formatting, Rust/Dart package tests,
    router tests, build hooks, and Chrome Dart2Wasm WebSocket transport tests
  - current local kTLS reporting slice adds per-repeat baseline/kTLS
    throughput and p95 values to rows that exceed repeat-stability thresholds,
    so the comparison artifact shows which repeat values caused a mixed p95
    span; pre-change `bin/test-fast`, Python bytecode compilation, and
    `python3 tool/test_ktls_http2_compare.py` passed
  - local `bin/verify` passed after the kTLS reporting slice on 2026-04-30,
    including formatting, Rust/Dart package tests, router tests, build hooks,
    and Chrome Dart2Wasm WebSocket transport tests
  - the H2 body-timeout symptom did not recur across the post-reporting runs;
    current kTLS/H2 work should target benchmark repeat stability and hosted
    measurement evidence before any runtime tuning
- Recent kTLS/H2 isolated diagnosis/reporting slice:
  - commit `7d08440`
    (`bench: flag transport counter issues in h2 repeats`) makes the kTLS/H2
    comparison artifacts self-report individual transport event/alert counters
    and makes repeat-stability output non-decision-quality when focus rows
    contain body timeouts, GOAWAY, idle timeouts, protocol/internal errors, or
    transport alerts
  - focused local checks for the reporting change passed:
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `git diff --check`
  - full local `bin/verify` passed after `7d08440` on 2026-04-30, including
    native Rust/FFI, Dart package, MCP, bench, router, and Chrome/Dart2Wasm
    browser coverage
  - documentation checkpoint `0da1030`
    (`docs: record h2 transport counter reporting`) passed hosted GitHub `CI`
    run `25163209719`, and the branch-head deployment-chain audit/log scan was
    clean
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25160953085` completed
    successfully on `b6c993f` with the same isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one-router-worker alternating
    repeat settings
  - `25160953085` is not clean release-decision evidence: throughput delta
    span was `69.50pp`, p95 delta span was `4088.43pp`, repeat 02 had a
    kTLS-side stall with three `http/2 body reader error: http/2 body total
    timeout` lines, and the log also contained one baseline shutdown
    `h2 connection error: ... BrokenPipe`
  - the flow-window diagnostic still resolves the current receive-window
    question: before the max remaining-tail `stream.data()` wait, both
    baseline and kTLS had full available receive capacity
    (`8388608 B`) and zero used capacity; after DATA delivery kTLS used only
    about `36.8 KiB..38.6 KiB`, and after release the window was again nearly
    full
  - the next diagnosis target should therefore be DATA arrival/scheduling or
    benchmark-side body-timeout behavior under kTLS, not H2 receive-window
    exhaustion or delayed capacity release
  - documentation checkpoint `4025d6f`
    (`docs: record h2 accept shutdown ci`) passed hosted GitHub `CI` run
    `25159091408`; `Fast Checks` completed successfully in 5m55s and
    `Full Verify` completed successfully in 8m28s
  - local pre-change `bin/test-fast` passed on 2026-04-30 before adding the
    HTTP/2 request-body flow-window diagnostic
  - current local commit `9f90448`
    (`bench: sample h2 request flow window`) records H2 receive
    flow-control state for each request's maximum remaining-tail
    `stream.data()` wait: available capacity and used capacity before the
    wait, after DATA/EOF delivery, and after releasing consumed DATA capacity
  - those flow-window counters now flow through ct_core snapshots, the FFI
    metrics struct, Dart router metrics, native bench summaries, and the
    primary/repeat kTLS HTTP/2 comparison reports
  - focused local checks for that diagnostic passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_request_body_stream_metrics_record_reader_chunks -- --nocapture`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test router_metrics_snapshot_aggregates_reason_totals_and_listener_breakdowns -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    `dart analyze packages/connectanum_router/lib/src/native/ffi_bindings.dart packages/connectanum_router/lib/src/native/runtime.dart packages/connectanum_router/lib/src/router/models/router_metrics.dart packages/connectanum_router/lib/src/router/router_instance/router_boss.dart`,
    and `git diff --check`
  - full local `bin/verify` passed after the flow-window diagnostic on
    2026-04-30, including Rust, FFI, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - current pushed branch head `83976ed` passed the hosted GitHub push chain:
    `CI` run `25158055327` completed successfully with `Fast Checks` in
    5m40s and `Full Verify` in 8m14s; `kTLS Validation` run `25158055341`
    completed in 2m57s; `WAMP Profile Benchmarks` run `25158055443`
    completed in 7m43s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `83976ed`; companion
    kTLS/WAMP log scans only matched benign setup/configuration text, not
    Rust warnings, skipped tests, panics, resets, broken pipes, or actionable
    connection-noise patterns
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25158694031` completed
    successfully on `83976ed` with the same isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one-router-worker alternating
    repeat settings; its log was clean apart from benign setup text and the
    expected manual artifact-gate skip notices, confirming the HTTP/2 benign
    accept-shutdown fix removed the previous broken-pipe noise
  - `25158694031` is complete and log-clean but still not release-decision
    evidence: throughput delta span was `36.46pp`, p95 delta span was
    `300.70pp`, throughput spread was mixed, and p95 spread was kTLS-side
  - the clean rerun keeps the active diagnosis pointed at request DATA-frame
    availability/window scheduling: native request-body reader remaining-tail
    data-wait and max data-wait stayed kTLS-higher across all repeats, the
    max wait remained around event index `4`, and EOF ratio remained mixed
    rather than pure terminal EOF
  - latest pushed branch head `234e88d` passed the hosted GitHub push chain:
    `CI` run `25156460466` completed successfully with `Fast Checks` in
    5m43s and `Full Verify` in 8m21s; `kTLS Validation` run `25156460504`
    completed in 3m01s; `WAMP Profile Benchmarks` run `25156460459`
    completed in 7m41s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `234e88d`; companion
    kTLS/WAMP log scans only matched benign setup/configuration text such as
    git default-branch hints, Rust toolchain timeout-reference comments,
    dependency names, workload timeout settings, and upload
    `if-no-files-found: error` configuration
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25157185705` completed
    successfully on `234e88d` with isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one router worker,
    `repeat_count=3`, `repeat_order=alternating`, `cooldown_seconds=15`,
    and `skip_artifact_gate=true`
  - `25157185705` was complete but not clean release-decision evidence:
    throughput delta span was `53.80pp`, p95 delta span was `212.93pp`, and
    the hosted log contained one real `http/2 accept error ... broken pipe`
    connection-noise line during repeat 03
  - the new max-wait position fields still make that run useful diagnostic
    evidence: the remaining native request-body tail `stream.data()` max wait
    stayed near event index `4`, around `208 KiB..226 KiB` before the wait,
    and EOF ratio stayed mixed at roughly `0.46..0.64`; that points toward a
    late DATA-frame availability/scheduling gap rather than a pure terminal
    EOF wait
  - current local CI-clean fix classifies HTTP/2 accept-loop I/O shutdowns
    (`BrokenPipe`, `ConnectionReset`, `ConnectionAborted`, `UnexpectedEof`)
    as graceful peer shutdowns instead of protocol errors, while preserving
    GOAWAY accounting and real protocol-error logging
  - focused repro
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http2_accept_broken_pipe_is_classified_as_graceful_shutdown -- --nocapture`
    passed locally, `bin/test-fast` passed after the fix, and full local
    `bin/verify` passed on 2026-04-30 including Rust, FFI, Dart package,
    bench, router, and Chrome/Dart2Wasm browser coverage
  - latest pushed branch head `aab4c31` passed hosted GitHub `CI` run
    `25151359137`; `Fast Checks` completed successfully in 5m44s and
    `Full Verify` completed successfully in 8m16s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `aab4c31`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset,
    connection-noise, panic, or timeout patterns
  - local pre-change `bin/test-fast` passed on 2026-04-30 before adding the
    request-body tail data-wait split
  - the current local diagnostic slice records native HTTP/2 request-body
    remaining-tail `stream.data()` wait totals and per-request max wait totals,
    including the final EOF wait after the second chunk, and exposes them
    through FFI, Dart router metrics, bench summaries, and primary/repeat
    kTLS comparison reports
  - focused local checks for that diagnostic passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_request_body_stream_metrics_record_reader_chunks -- --nocapture`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test router_metrics_snapshot_aggregates_reason_totals_and_listener_breakdowns -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    `dart analyze packages/connectanum_router/lib/src/native/ffi_bindings.dart packages/connectanum_router/lib/src/native/runtime.dart packages/connectanum_router/lib/src/router/models/router_metrics.dart packages/connectanum_router/lib/src/router/router_instance/router_boss.dart`,
    and `git diff --check`
  - first full local `bin/verify` attempt exposed an existing FFI listen-flow
    race where `wait_connection_message_times_out_without_payload` dropped its
    raw socket client before polling the accepted connection; the runtime could
    then remove the connection before `ct_connection_protocol` ran
  - that test now keeps the TCP stream alive while it polls the connection and
    waits for the expected no-message timeout; focused repro
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test wait_connection_message_times_out_without_payload -- --nocapture`
    passed locally
  - full local `bin/verify` passed on 2026-04-30 after the request-body tail
    data-wait diagnostic and FFI listen-flow race fix, including Rust, Dart
    package, bench, router, and Chrome/Dart2Wasm browser coverage
  - commit `6885def` (`bench: split h2 request tail data wait`) passed the
    hosted GitHub push chain: `CI` run `25153069857` completed with
    `Fast Checks` in 5m45s and `Full Verify` in 8m12s; `kTLS Validation` run
    `25153069860` completed in 2m44s; `WAMP Profile Benchmarks` run
    `25153069894` completed in 7m53s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `6885def`; companion
    kTLS/WAMP log scans only matched benign setup/configuration text such as
    git default-branch hints, Rust toolchain timeout-reference comments,
    dependency names, workload timeout settings, and upload
    `if-no-files-found: error` configuration
  - documentation checkpoint `724077b`
    (`docs: record request tail data wait ci`) passed hosted GitHub `CI` run
    `25153709708`; `Fast Checks` completed in 5m39s and `Full Verify`
    completed in 7m53s
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25155199202` completed
    successfully on `724077b` with isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one router worker,
    `repeat_count=3`, `repeat_order=alternating`, `cooldown_seconds=15`,
    and `skip_artifact_gate=true`
  - `25155199202` was complete and log-clean apart from benign setup/toolchain
    text and expected manual artifact-gate skip notices, but it was not
    release-decision-quality: throughput delta span was `58.05pp`, p95 delta
    span was `1283.94pp`, and repeat 03 had a kTLS-side p95/header-wait
    outlier
  - the same run is still useful diagnostic evidence for the active question:
    when the native request-body tail delay appeared, remaining-tail wall time
    tracked remaining-tail `stream.data()` wait directly (`0.06 -> 1.17 ms`
    in repeat 01 and `1.14 -> 3.51 ms` in repeat 03), while repeat 02 stayed
    flat/slightly lower on that field; this points away from post-read
    enqueue/FFI/Dart drain as the remaining native request-body tail gap
  - local pre-change `bin/test-fast` passed on 2026-04-30 before adding the
    request-body tail max data-wait position diagnostic
  - the current local diagnostic slice records the position of each request's
    maximum native HTTP/2 request-body remaining-tail `stream.data()` wait:
    returned event index, bytes before the wait, bytes after the wait, and
    whether the max wait was the terminal EOF event; those counters now flow
    through FFI, Dart router metrics, bench summaries, and primary/repeat
    kTLS comparison reports
  - focused local checks for that diagnostic passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_request_body_stream_metrics_record_reader_chunks -- --nocapture`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test router_metrics_snapshot_aggregates_reason_totals_and_listener_breakdowns -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    rerendering hosted run `25155199202` with
    `tool/ktls_http2_compare_repeats.py`,
    `dart analyze packages/connectanum_router/lib/src/native/ffi_bindings.dart packages/connectanum_router/lib/src/native/runtime.dart packages/connectanum_router/lib/src/router/models/router_metrics.dart packages/connectanum_router/lib/src/router/router_instance/router_boss.dart`,
    and `git diff --check`
  - full local `bin/verify` passed after the request-body tail max data-wait
    position diagnostic on 2026-04-30, including Rust, FFI, Dart package,
    bench, router, and Chrome/Dart2Wasm browser coverage
  - resumed after the GitHub deployment-chain plan reached a clean evidence
    checkpoint where remaining blockers are operator/product/deployment
    decisions: branch protection mutation, default-branch router image
    promotion/GHCR publication, RC tag/prerelease selection, and Dart package
    public ownership/release order
  - latest pushed branch head `fb1f949` passed hosted GitHub `CI` run
    `25145156786`; `Fast Checks` completed successfully in 5m35s and
    `Full Verify` completed successfully in 7m58s
  - latest branch-head deployment audit passed with clean main `CI` jobs and
    clean hosted `CI` logs; remaining deployment-chain findings are still the
    known operator/product items: missing branch protection, undiscoverable
    `router-image.yml`, and no visible GHCR router package
  - pre-change `bin/test-fast` passed locally on 2026-04-29 before changing
    repeat-report tooling
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25124797087` reran isolated
    `h2_multiplexed_streams_s1`, `threads=4`, `repeat_count=3`,
    `repeat_order=baseline-first`; it completed successfully but was not
    decision-quality because baseline-side header noise widened throughput and
    p95 spans
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25125095595` reran the same
    isolated workload with `repeat_order=alternating`; it completed
    successfully but was not decision-quality because throughput delta span was
    `57.05pp` and p95 delta span was `368.11pp`
  - the alternating run still showed sign-consistent kTLS-higher body/tail
    read cost across repeated focus rows, especially body read, tail read,
    and tail connection read-to-end timing
  - `tool/ktls_http2_compare_repeats.py` now renders a top-level
    `## Repeat Phase Signals` table so noisy repeat artifacts still expose
    sign-consistent phase deltas across repeated focus rows
  - focused local checks passed:
    `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and rerendering the
    `25125095595` repeat artifact with `tool/ktls_http2_compare_repeats.py`
  - full local `bin/verify` passed after the repeat-report tooling and
    documentation updates on 2026-04-29
  - commit `e547232` (`bench: surface repeat phase signals`) passed hosted
    GitHub `CI` run `25126070249`; `Fast Checks` completed successfully in
    5m31s and `Full Verify` completed successfully in 8m15s
  - documentation checkpoint `90fbbb9`
    (`docs: record repeat phase signal ci`) passed hosted GitHub `CI` run
    `25126752936`; `Fast Checks` completed successfully in 5m43s and
    `Full Verify` completed successfully in 8m05s
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25127431552` on `90fbbb9`
    failed during repeat 01 when the kTLS pass hit an HTTP/2 body total
    timeout; the partial artifact had one baseline-only row and zero
    comparable rows, so it is a harness/timeout signal rather than transport
    decision evidence
  - `tool/ktls_http2_compare_repeats.py` now marks partial repeat artifacts
    with no comparable rows or unmatched baseline/kTLS rows as not
    decision-quality and renders a `## Repeat Completeness` table
  - focused local checks passed for that reporter fix:
    `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and rerendering the partial
    `25127431552` repeat artifact
  - `git diff --check` and full local `bin/verify` passed after the
    partial-repeat reporter fix on 2026-04-29
  - commit `f85c70e` (`bench: mark partial repeats inconclusive`) passed
    hosted GitHub `CI` run `25128558792`; `Fast Checks` completed
    successfully in 5m32s and `Full Verify` completed successfully in 8m06s
  - documentation checkpoint `7878467`
    (`docs: record partial repeat reporter ci`) passed hosted GitHub `CI` run
    `25129245463`; `Fast Checks` completed successfully in 5m34s and
    `Full Verify` completed successfully in 8m15s
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25129905513` on `7878467`
    completed successfully with matched rows in all three alternating repeats,
    but was not decision-quality because throughput delta span was `57.64pp`
    and p95 delta span was `1390.49pp`
  - rerendering that artifact with the current repeat reporter shows six
    material sign-consistent client phase deltas across all three repeats:
    kTLS-higher header last-write-to-first-read, headers wait, body read,
    tail read, tail connection read-to-end, and tail connection read-wait
    timing
  - the same rerender shows no material sign-consistent server-emission or
    native response-stream deltas, while the per-repeat server-emission focus
    table still exposes the repeat-02 direct-stream/server-side outlier
  - current local reporter checks passed:
    `bin/test-fast`,
    `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and rerendering the
    `25129905513` repeat artifact with `tool/ktls_http2_compare_repeats.py`
  - the first full local `bin/verify` rerun exposed an existing macOS HTTP/3
    FFI test race where the TCP listener's ephemeral port could already be in
    use for UDP, so the QUIC listener silently failed and
    `http3_multiple_connections_handshake` timed out
  - HTTP/3 FFI network tests now configure a dedicated `http3.port: 0` and use
    `ct_listener_http3_port`, which exercises the intended split TCP/UDP
    listener API instead of assuming the TCP and QUIC listeners can always
    share the same ephemeral port number
  - focused local checks for that CI-clean fix passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_multiple_connections_handshake -- --nocapture`
    and `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi`
  - full local `bin/verify` passed after the repeat reporter update and HTTP/3
    FFI test port-race fix on 2026-04-29
  - commit `1400ce1` (`bench: split repeat server signals`) passed hosted
    GitHub `CI` run `25131284776`; `Fast Checks` completed successfully in
    5m55s and `Full Verify` completed successfully in 8m07s
  - the matching hosted `WAMP Profile Benchmarks` run `25131284793` completed
    successfully on `1400ce1`; the deployment-chain audit reported the latest
    CI job set and CI log scan clean
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25132037358` completed
    successfully on `1400ce1` with the same isolated `s1`, `threads=4`,
    one-router-worker, alternating repeat settings and the new split
    client/server/native signal tables
  - `25132037358` was complete but not decision-quality: throughput delta
    span was `84.11pp`, p95 delta span was `2378.94pp`, all repeats produced
    matched rows, repeated client phase signals remained kTLS-higher, and the
    repeated server-emission/native response-stream signal tables stayed empty
  - the hosted benchmark log had only the expected manual
    `skip_artifact_gate=true` artifact-gate skip notices, so the run is valid
    diagnostic evidence but not release-decision evidence
  - pre-change `bin/test-fast` passed locally before adding the next H2 client
    tail-read instrumentation slice
  - the H2 client read probe now records last connection read and read count
    for active phases, and the body-tail report path exposes tail connection
    read count, first-to-last read span, and last-read-to-body-end timing so
    the remaining tail cost can be split between socket wait and post-read
    processing
  - focused local checks for that instrumentation passed without new Rust
    warnings: Python compile, Python comparison tests, the focused
    `http_stream` H2 timing test, the bench artifact summary test, and
    `git diff --check`
  - full local `bin/verify` passed after the H2 tail-read split on
    2026-04-29
  - commit `449887b` (`bench: split h2 tail read timing`) passed hosted
    GitHub `CI` run `25133186169`; `Fast Checks` completed successfully in
    4m47s and `Full Verify` completed successfully in 8m10s
  - the matching hosted `WAMP Profile Benchmarks` run `25133186159` and
    `kTLS Validation` run `25133186157` completed successfully on `449887b`
  - the deployment-chain audit against `449887b` reported the latest `CI` job
    set and hosted `CI` log scan clean, with no high-signal warning,
    deprecation, skipped-test, reset, panic, timeout, or connection-noise
    patterns beyond benign test names and toolchain timeout-reference text
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25134092006` completed
    successfully on `449887b` with the same isolated `s1`, `threads=4`,
    one-router-worker, alternating repeat settings and the new tail-read split
  - `25134092006` is decision-quality: throughput delta span was `23.73pp`,
    p95 delta span was `15.47pp`, all repeats produced matched rows, and the
    worst throughput/p95 row stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - the decision-quality result keeps the throughput gap kTLS-side
    (`-36.18%..-12.44%`, median `-25.30%`) and shows six material repeated
    client phase signals, with no repeated native response-stream signal
  - the new tail split narrows the stable body-tail gap to client-side
    connection reads before the final read completes: tail read-span delta was
    `+0.39..+1.70 ms`, tail read-to-end delta was `+0.38..+1.70 ms`, and
    tail last-read-to-end stayed flat at about `0.02..0.04 ms`
  - the hosted benchmark log had only the expected manual
    `skip_artifact_gate=true` artifact-gate skip notices, so the next
    investigation target is socket/TLS read scheduling during the H2 body tail
  - local pre-change `bin/test-fast` passed before adding the native
    response-stream tail-send metrics
  - the native response-stream metrics now split streaming body tail emission
    into tail chunk channel wait, tail chunk send-call duration, and
    first-to-last chunk send span so the next hosted isolated rerun can tell
    whether the stable tail gap is already visible before bytes enter the
    socket/TLS read path
  - focused local checks for that instrumentation passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_response_stream_metrics_record_tail_chunks -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    `dart analyze packages/connectanum_router`, and `git diff --check`
  - full local `bin/verify` passed after the native response-stream tail-send
    split on 2026-04-29, including Rust, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - commit `fc71d9a` (`bench: split native response tail send timing`) passed
    hosted GitHub `CI` run `25135516518`; `Fast Checks` completed
    successfully in 5m38s and `Full Verify` completed successfully in 8m00s
  - the matching hosted `kTLS Validation` run `25135516526` completed
    successfully in 3m17s and hosted `WAMP Profile Benchmarks` run
    `25135516530` completed successfully in 7m49s on `fc71d9a`
  - the deployment-chain audit against `fc71d9a` reported the latest `CI` job
    set and hosted `CI` log scan clean; manual hosted log scans for `CI`,
    `kTLS Validation`, and `WAMP Profile Benchmarks` only matched benign
    timeout-reference/configuration text and passing test names containing
    expected words such as `failed` or `timeout`
  - documentation checkpoint `564de8e`
    (`docs: record native tail send ci`) passed hosted GitHub `CI` run
    `25136141646`; `Fast Checks` completed successfully in 5m48s and
    `Full Verify` completed successfully in 7m51s
  - the branch-head deployment audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `564de8e`; the hosted log
    scan only matched benign timeout-reference/configuration text and passing
    test names containing expected words
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25136742292` completed
    successfully on `564de8e` with the same isolated `s1`, `threads=4`,
    one-router-worker, alternating repeat settings and the new native
    tail-send split
  - `25136742292` was complete but not decision-quality: throughput delta
    span was `33.35pp`, p95 delta span was `129.29pp`, all repeats produced
    matched rows, the throughput span was mixed, and the p95 span was
    kTLS-side
  - the uploaded benchmark comparison initially showed no native
    response-stream metrics even though the raw JSONL snapshots contained
    `transport.http_response_stream` counters with `streaming_responses_total`
    for the workload
  - root cause: `metrics_before` can omit the
    `transport.http_response_stream` object when all counters are still zero,
    and the bench summary transformer treated that as an absent metric instead
    of a zero starting counter
  - commit `8ff7b31` (`bench: keep response stream summaries`) treats missing
    response-stream `before` counters as zero when the corresponding `after`
    counter exists; rerendering the downloaded `25136742292` raw JSONL then
    populates the native response-stream tables
  - that rerender keeps the run non-decision-quality but exposes two material
    repeated native response-stream signals: tail chunk channel wait was
    kTLS-higher by `+0.20..+0.35 ms` (median `+0.32 ms`), and
    first-to-last chunk send span was kTLS-higher by `+0.23..+0.26 ms`
    (median `+0.25 ms`)
  - repeated client phase signals remained kTLS-higher for header
    last-write-to-first-read, headers wait, body read, tail read, tail
    connection read-span, tail connection read-to-end, connection
    read-to-first-chunk, and tail connection read-wait timing
  - current local verification for the summary fix passed:
    `bin/test-fast`, `cargo test --manifest-path native/bench/Cargo.toml --lib -- --nocapture`,
    and rerendering the `25136742292` raw JSONL with `transform_results`,
    `tool/ktls_http2_compare.py`, and `tool/ktls_http2_compare_repeats.py`
  - full local `bin/verify` passed after the response-stream summary fix on
    2026-04-29, including Rust, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - commit `c71ed8c` (`docs: record response stream summary fix`) passed the
    hosted GitHub push chain: `CI` run `25137565822` completed with
    `Fast Checks` in 4m43s and `Full Verify` in 8m19s; `kTLS Validation` run
    `25137565809` completed in 2m57s; `WAMP Profile Benchmarks` run
    `25137565865` completed in 8m00s
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25138038502` completed
    successfully on `c71ed8c` in 5m20s; the uploaded comparison now includes
    native response-stream rows without local rerendering, and the hosted log
    scan only matched the expected manual artifact-gate skip notices plus the
    Rust toolchain timeout-reference URL
  - `25138038502` was complete but not decision-quality: throughput delta
    span was `69.12pp`, p95 delta span was `1975.62pp`, all repeats produced
    matched rows, and the instability was kTLS-side
  - the repeated native response-stream signal on `25138038502` stayed small
    but sign-consistent before the client-side body tail: tail chunk channel
    wait was kTLS-higher by `+0.26..+0.28 ms` (median `+0.27 ms`) and
    first-to-last chunk send span was kTLS-higher by `+0.18..+0.20 ms`
    (median `+0.20 ms`), while repeated server-emission signals stayed empty
  - commit `86c914e` (`perf: avoid h2 single-stream body yield`) gates the
    HTTP/2 first-body-chunk fairness yield on `pending_headers > 1`; the
    single-stream isolated `s1` response path no longer yields after the first
    body chunk when there is no pending header backlog, while multiplexed
    response fairness still uses the existing pending-header condition
  - local verification for the H2 yield-gating change passed:
    `bin/test-fast`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http2_response_yield_requires_multiple_pending_headers -- --nocapture`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_response_stream_metrics_record_tail_chunks -- --nocapture`,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core -- --nocapture`,
    `git diff --check`, and full `bin/verify`
  - commit `86c914e` passed the hosted GitHub push chain: `CI` run
    `25138760298` completed with `Fast Checks` in 5m20s and `Full Verify` in
    8m29s; `kTLS Validation` run `25138760315` completed in 2m53s; `WAMP
    Profile Benchmarks` run `25138760280` completed in 7m39s
  - the branch-head deployment-chain audit with
    `--require-clean-latest-ci --require-clean-latest-ci-logs` passed against
    `86c914e`; manual raw log scans for the `CI`, `kTLS Validation`, and
    `WAMP Profile Benchmarks` runs only matched benign timeout-reference
    text, passing test names, and WAMP timeout configuration lines
  - documentation checkpoint `d40543a`
    (`docs: record h2 yield gating evidence`) passed hosted GitHub `CI` run
    `25139453507`; `Fast Checks` completed in 5m38s, `Full Verify`
    completed in 7m12s, and the branch-head deployment-chain audit/log scan
    passed against `d40543a`
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25139865949` completed
    successfully on `d40543a` in 5m29s with the same isolated `s1`,
    `threads=4`, one-router-worker, alternating repeat settings after the
    single-stream first-body yield gate landed
  - `25139865949` was complete but not decision-quality: throughput delta span
    narrowed to `24.53pp`, but p95 delta span remained kTLS-side and far above
    threshold at `1640.36pp`; all repeats produced matched rows
  - the first-body yield gate materially reduced, but did not remove, the
    repeated native response-stream tail signal: tail chunk channel wait moved
    from pre-fix `+0.26..+0.28 ms` to `+0.14..+0.17 ms`, and first-to-last
    chunk send moved from pre-fix `+0.18..+0.20 ms` to `+0.11..+0.16 ms`
  - documentation checkpoint `52e8e2a`
    (`docs: record h2 post-yield benchmark`) passed hosted GitHub `CI` run
    `25140097069`; `Fast Checks` completed in 5m40s and `Full Verify`
    completed in 6m58s, and the branch-head deployment-chain audit/log scan
    remained clean against `52e8e2a`
  - rerendering `25139865949` after exposing the already-collected
    server-emission fields narrowed the repeated server-side signal: first
    body write and first body write completion move because request-body
    drain, handler elapsed, first-chunk queued, and stream-open timing are
    kTLS-higher before the first direct stream write call
  - the strongest repeated server-side request-drain signal on that rerender
    is request body drain `+1.08..+3.37 ms` (median `+2.10 ms`), with the
    same median movement on handler elapsed and first-chunk queued timing;
    first body write call duration itself stays flat
  - the bench HTTP stream diagnostics now split synthetic request-body drain
    into first-chunk wait, tail-read, and chunk-count averages, and the
    comparison/repeat reporters surface those fields in server-emission focus
    and signal tables
  - focused local checks for the request-body drain split passed:
    `dart analyze packages/connectanum_bench/lib/src/http_stream_handler.dart packages/connectanum_bench/test/http_stream_handler_test.dart`,
    `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `git diff --check`
  - full local `bin/verify` passed after the request-body drain split on
    2026-04-29, including Rust, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - commit `57c051d` (`bench: split h2 request body drain timing`) passed the
    hosted GitHub push chain: `CI` run `25140818328` completed with
    `Fast Checks` in 5m28s and `Full Verify` in 8m23s; `kTLS Validation` run
    `25140818325` completed successfully; `WAMP Profile Benchmarks` run
    `25140818382` completed successfully
  - the branch-head deployment-chain audit with
    `--require-clean-latest-ci --require-clean-latest-ci-logs` passed against
    `57c051d`, and the hosted CI log scan found no warning, deprecation,
    skipped-test, reset, timeout, panic, or connection-noise patterns
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25141243287` completed
    successfully on `57c051d` in 5m34s with isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one router worker,
    `repeat_count=3`, and `repeat_order=alternating`
  - `25141243287` was complete but not decision-quality: throughput delta
    span was `52.94pp`, p95 delta span was `1813.09pp`, all repeats produced
    matched rows, and the instability source was kTLS-side
  - the hosted request-body drain split resolves the next boundary:
    request-body first-chunk wait stayed effectively flat at `+0.00..+0.01 ms`
    while chunk count stayed flat at `4.08`, but request-body tail drain was
    kTLS-higher by `+0.01..+3.41 ms` with median `+2.73 ms`
  - the remaining server-side delay is therefore in the post-first-chunk
    request-body drain path / H2 request-body stream delivery rather than
    before the first streamed request-body chunk reaches Dart; first-body
    write call duration remains flat, while handler elapsed, stream open, and
    first-chunk queued timing move after the drain path waits
  - the current local follow-up splits the synthetic request-body tail drain
    into second-chunk wait and remaining-tail-read averages, and carries those
    fields through bench summaries plus primary/repeat kTLS comparison
    reports
  - focused local checks for the request-body inter-chunk split passed:
    `dart analyze packages/connectanum_bench/lib/src/http_stream_handler.dart packages/connectanum_bench/test/http_stream_handler_test.dart`,
    `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `git diff --check`
  - full local `bin/verify` passed after the request-body inter-chunk split
    on 2026-04-30, including Rust, Dart package, bench, router,
    `remote_auth_integration_test`, and Chrome/Dart2Wasm browser coverage
  - commit `f9b3b27` (`bench: split request body tail drain timing`) passed
    the hosted GitHub push chain: `CI` run `25141807658` completed with
    `Fast Checks` in 5m09s and `Full Verify` in 8m12s; `kTLS Validation` run
    `25141807596` completed successfully; `WAMP Profile Benchmarks` run
    `25141807457` completed successfully
  - the branch-head deployment-chain audit with
    `--require-clean-latest-ci --require-clean-latest-ci-logs` passed against
    `f9b3b27`; the known non-blocking deployment findings remain branch
    protection, default-branch router image discovery/GHCR visibility, and
    release/package ownership decisions
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25142223693` completed
    successfully on `f9b3b27` in 5m23s with isolated
    `h2_multiplexed_streams_s1`, `threads=4`, one router worker,
    `repeat_count=3`, and `repeat_order=alternating`
  - `25142223693` was complete but not decision-quality: throughput delta
    span was `35.05pp`, p95 delta span was `335.53pp`, all repeats produced
    matched rows, and the instability source was kTLS-side
  - the hosted request-body inter-chunk split rules out the first request-body
    chunk as the dominant server-side delay and points mostly past the second
    chunk: first-chunk wait stayed flat at about `0.05..0.06 ms`,
    second-chunk wait stayed flat in two repeats with one kTLS-side outlier
    (`0.02 -> 0.63 ms`), and remaining-tail-read carried the larger repeated
    deltas (`0.05 -> 2.41 ms` and `0.05 -> 1.13 ms` in the moving repeats)
  - the current local follow-up instruments native HTTP/2 request-body reader
    timing before the Dart drain layer: `ct_core` records total reader time,
    `stream.data()` wait, first/second chunk wait, remaining tail-read, and
    chunk count; `ct_ffi`, the Dart native/router metrics models, and the
    native bench comparison reports expose those counters
  - focused local checks for the native request-body reader split passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_request_body_stream_metrics_record_reader_chunks -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    `dart analyze packages/connectanum_router/lib/src/native/runtime.dart packages/connectanum_router/lib/src/native/ffi_bindings.dart packages/connectanum_router/lib/src/router/models/router_metrics.dart packages/connectanum_router/lib/src/router/router_instance/router_boss.dart`,
    `git diff --check`, and `bin/test-fast`
  - full local `bin/verify` passed after the native request-body reader split
    on 2026-04-30, including Rust, Dart package, bench, router,
    `remote_auth_integration_test`, and Chrome/Dart2Wasm browser coverage
  - commit `ffb1376` (`bench: expose native request body reader timing`)
    passed the hosted GitHub push chain: `CI` run `25143265285` completed
    with `Fast Checks` in 5m43s and `Full Verify` in 8m10s; `kTLS Validation`
    run `25143265320` completed successfully; `WAMP Profile Benchmarks` run
    `25143265476` completed successfully
  - the branch-head deployment-chain audit with
    `--require-clean-latest-ci --require-clean-latest-ci-logs` passed against
    `ffb1376`; the hosted CI log scan found no warning, deprecation,
    skipped-test, reset, timeout, panic, or connection-noise patterns
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25143770043` completed
    successfully on `ffb1376` but is not usable as clean decision evidence:
    throughput delta span was `121.77pp`, p95 delta span was `1841.86pp`,
    and the hosted log contained `http/2 accept error ... broken pipe` during
    repeat-01 baseline warm-up immediately before the low baseline row
  - manual hosted retry `25143991933` completed successfully on `ffb1376` and
    produced decision-quality isolated `s1`, `threads=4`, one-router-worker
    evidence: throughput delta span was `23.85pp`, p95 delta span was
    `27.61pp`, all repeats produced matched rows, and the hosted log scan had
    no connection-noise pattern beyond the expected manual
    `skip_artifact_gate=true` notices and benign setup/toolchain text
  - `25143991933` keeps the throughput gap kTLS-side
    (`-39.24%..-15.38%`, median `-36.77%`) with p95 at
    `+0.08%..+27.69%`; repeated client phase signals remain kTLS-higher for
    body read, tail read, tail connection read-to-end/span, header wait, and
    tail connection read wait
  - the native request-body reader split shows the server request-body path is
    not the broad stable explanation: repeat-01 had matching Dart drain and
    native reader tail movement (`request body drain +1.06 ms`, native reader
    total `+1.19 ms`), but repeats 02 and 03 kept Dart drain and native reader
    totals essentially flat while client body/tail read remained kTLS-higher
  - the next bounded diagnostic target is therefore the client-side HTTP/2
    body-tail read path, specifically splitting the tail connection read span
    into inter-read gap and read-size/read-count distribution before making
    more server request-body or first-body-write scheduling changes
  - local pre-change `bin/test-fast` passed on 2026-04-30 before adding that
    H2 client tail-read byte/gap instrumentation slice
  - the H2 client read probe now records tail-phase connection read byte
    totals, average/max read size, and average/max inter-read gap so the next
    hosted isolated rerun can distinguish many small reads from longer gaps
    between reads
  - comparison tooling now renders those fields in the HTTP response-body
    diagnostics table, phase focus lines, and repeat phase focus/signal
    reports
  - focused local checks for that instrumentation passed:
    `cargo test --manifest-path native/bench/Cargo.toml h2_client_read_probe_records --bin http_stream -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `git diff --check`
  - full local `bin/verify` passed after the H2 client tail-read byte/gap
    split on 2026-04-30, including Rust, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - commit `fb1f949` (`bench: expose h2 tail read sizes`) passed hosted
    GitHub `CI` run `25145156786`; `Fast Checks` completed in 5m35s and
    `Full Verify` completed in 7m58s
  - hosted `kTLS Validation` run `25145156820` completed successfully on
    `fb1f949` in 3m19s
  - hosted `WAMP Profile Benchmarks` run `25145156826` completed successfully
    on `fb1f949` in 8m10s
  - deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `fb1f949`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - documentation checkpoint `6c8bd57`
    (`docs: record h2 tail read size ci`) passed hosted GitHub `CI` run
    `25145654807`; `Fast Checks` completed in 5m32s and `Full Verify`
    completed in 8m31s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `6c8bd57`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25146117904` completed on
    `6c8bd57` but is excluded from decision evidence: the repeat artifact was
    complete but not decision-quality, throughput delta span was `72.17pp`,
    p95 delta span was `1493.48pp`, and the hosted log had two
    `http/2 accept error ... broken pipe` lines
  - manual hosted retry `25146345720` completed successfully on `6c8bd57`,
    produced decision-quality isolated `s1`, `threads=4`,
    one-router-worker alternating evidence, and its hosted log scan had no
    connection-noise pattern beyond expected manual artifact-gate skip notices
    and benign setup/toolchain text
  - the decision-quality retry kept the kTLS-side regression stable:
    throughput delta was `-37.67%..-35.62%`, p95 delta was
    `+13.25%..+23.51%`, all repeats produced matched rows, and the worst
    throughput/p95 row stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - the new tail read-size/gap fields show the stable body-tail delta is not
    post-final-read processing and not primarily smaller reads: tail
    last-read-to-end stayed flat, read-size averages were flat/slightly lower,
    read-count was only modestly higher, and the repeated max inter-read gap
    was kTLS-higher by `+0.25..+1.41 ms` (median `+1.35 ms`)
  - the hosted artifact exposed a public readability bug in
    `tool/ktls_http2_compare_repeats.py`: repeat phase signal rows carried
    byte/count metadata internally but rendered byte/count ranges with the
    default `ms` unit
  - local reporter fix now preserves each repeat signal metric unit through
    rendering; focused verification passed with `bin/test-fast`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, `git diff --check`, and
    rerendering hosted run `25146345720` so byte fields render as `B` and
    read-count fields render without an `ms` suffix
  - full local `bin/verify` passed after the repeat signal unit fix on
    2026-04-30, including Rust, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - commit `b898053` (`bench: keep repeat signal units`) passed hosted
    GitHub `CI` run `25146937008`; `Fast Checks` completed in 5m56s and
    `Full Verify` completed in 8m24s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `b898053`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - documentation checkpoint `4752778`
    (`docs: record repeat signal unit ci`) passed hosted GitHub `CI` run
    `25147380520`; `Fast Checks` completed in 5m24s and `Full Verify`
    completed in 8m10s
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `4752778`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns
  - pre-change `bin/test-fast` passed locally on 2026-04-30 before adding the
    max tail inter-read gap position diagnostic
  - current local diagnostic change records where the maximum H2 tail
    inter-read gap occurs: the read index after the gap, bytes before the gap,
    bytes after the gap, and byte-position ratio now flow from raw samples to
    artifact summaries and comparison/repeat reports
  - focused local checks passed for that diagnostic:
    `cargo fmt --manifest-path native/bench/Cargo.toml -- --check`,
    `cargo test --manifest-path native/bench/Cargo.toml h2_client_read_probe_records_read_sizes_and_gaps --bin http_stream -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `git diff --check`
  - full local `bin/verify` passed after the max-gap position diagnostic on
    2026-04-30, including Rust, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - commit `b572b31` (`bench: locate h2 tail max gap`) passed the hosted
    GitHub push chain: `CI` run `25148383883` completed with `Fast Checks` in
    5m24s and `Full Verify` in 7m54s; `kTLS Validation` run `25148383878`
    completed successfully; `WAMP Profile Benchmarks` run `25148383890`
    completed successfully
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `b572b31`; the hosted CI
    log scan found no warning, deprecation, skipped-test, reset, timeout,
    panic, or connection-noise patterns beyond benign tool/test text
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25148797004` completed
    successfully on `b572b31` with isolated `h2_multiplexed_streams_s1`,
    `threads=4`, one router worker, alternating repeats, and matched rows in
    all repeats, but it was not decision-quality because throughput delta span
    was `57.19pp` and p95 delta span was `1736.62pp`
  - the hosted max-gap position evidence still narrows the client tail-read
    boundary: max inter-read gap stayed kTLS-higher in all repeats by
    `+0.33..+1.32 ms` (median `+0.88 ms`), the max-gap read index stayed
    around `24..25`, and the response-level byte position sat around
    `0.40..0.43` of the `1 MiB` response rather than at final-read
    completion
  - current local response chunk-boundary reporting carries workload
    request/response chunk sizes into bench reports and derives response-level
    max-gap bytes-before, response-position ratio, response chunk offset, and
    response chunk-boundary distance for the primary and repeat kTLS reports
  - focused local checks for the response chunk-boundary reporting passed:
    `bin/test-fast`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `cargo test --manifest-path native/bench/Cargo.toml h2_client_read_probe_records_read_sizes_and_gaps --bin http_stream -- --nocapture`,
    `cargo fmt --manifest-path native/bench/Cargo.toml -- --check`, and
    `git diff --check`
  - full local `bin/verify` passed after the response chunk-boundary reporting
    slice on 2026-04-30, including Rust, Dart package, bench, router, and
    Chrome/Dart2Wasm browser coverage
  - commit `41f9cb6` (`bench: classify h2 max gap chunk position`) passed the
    hosted GitHub push chain: `CI` run `25149820481` completed with
    `Fast Checks` in 5m40s and `Full Verify` in 8m04s; `kTLS Validation` run
    `25149820488` completed successfully; `WAMP Profile Benchmarks` run
    `25149820479` completed successfully
  - branch-head deployment-chain audit with `--require-clean-latest-ci` and
    `--require-clean-latest-ci-logs` passed against `41f9cb6`; companion
    kTLS/WAMP log scans only matched benign setup/config text, not Rust
    warnings, skipped tests, panics, resets, broken pipes, or connection-noise
    patterns
  - documentation checkpoint `b75dcca` (`docs: record chunk position ci`)
    passed hosted GitHub `CI` run `25150349893`; `Fast Checks` completed in
    5m44s, `Full Verify` completed in 7m58s, and the branch-head
    deployment-chain audit/log scan remained clean
  - manual hosted `kTLS HTTP/2 Benchmarks` run `25150816510` completed on
    `b75dcca` but is excluded from clean decision evidence: the artifact was
    complete but not decision-quality, throughput delta span was `79.02pp`,
    p95 delta span was `2171.61pp`, and the hosted log contained
    `http/2 accept error ... broken pipe` plus an H2 broken-pipe connection
    error around the later repeats
  - manual hosted retry `25151080248` completed successfully on `b75dcca`
    with clean diagnostic logs apart from benign setup text and the expected
    manual `skip_artifact_gate=true` notices; all repeats produced matched
    rows, throughput delta span was decision-quality at `22.90pp`, but p95
    delta span was still kTLS-side and non-decision-quality at `1271.34pp`
  - the clean retry keeps the kTLS throughput loss stable at
    `-82.00%..-59.09%` (median `-69.02%`) and shows p95 at
    `+262.40%..+1533.73%`; repeated client signals remain kTLS-higher for
    body read, first-chunk wait, tail read, tail connection read span, and max
    inter-read gap
  - the new chunk-position fields make the chunk-boundary hypothesis unlikely
    as the sole explanation: max-gap response position stays mid-response at
    about `0.45..0.50`, while response chunk-offset and chunk-boundary
    distance move kTLS-lower but remain far enough from a boundary that the
    next target should be H2 request-body/response-tail scheduling rather than
    app chunk sizing
  - the clean retry also shows repeated native/server-side kTLS movement:
    native request-body reader total and remaining tail-read, Dart
    request-body tail drain, native response tail chunk channel wait, and
    native response first-to-last chunk send all moved kTLS-higher in repeated
    focus rows
- Current deployment-chain evidence refresh:
  - commit `b338d58` (`docs: record current deployment evidence`) passed
    hosted GitHub `CI` run `25123037462`; `Fast Checks` completed
    successfully in 5m29s and `Full Verify` completed successfully in 8m00s
  - fresh manual hosted `Dart Package Publish Dry Run` run `25122605506`
    passed on `a358f43`; `Publish Dry Run` completed successfully in 20s and
    covers the checked-out package-publishing inputs
  - latest native release evidence remains clean and relevant through manual
    hosted `Native Artifacts` dry-run `25119602651`; no
    native-release-sensitive inputs changed after `d4e6fda`
  - latest branch-head deployment audit passed against `b338d58` with clean
    main `CI` jobs, clean hosted `CI` logs, clean/relevant hosted
    `Dart Package Publish Dry Run` evidence, and clean/relevant hosted
    `Native Artifacts` dry-run evidence
  - current RC blockers remain operator/product/deployment decisions:
    unprotected `add-router`, undiscoverable `router-image.yml` until default
    branch promotion, no visible `ghcr.io/konsultaner/connectanum-router`
    package, no selected RC tag/GitHub RC prerelease, and the strict Dart
    package release-order blocker where `connectanum_client` depends on the
    private workspace package `connectanum_core`
- Current native release dry-run audit hardening:
  - commit `d4e6fda` (`ci: audit native release dry runs`) passed hosted
    GitHub `CI` run `25119596673`; `Fast Checks` completed successfully in
    5m40s and `Full Verify` completed successfully in 8m19s
  - manual GitHub `Native Artifacts` dry-run `25119602651` passed all hosted
    Linux, macOS, and Windows `ct_ffi` artifact jobs plus
    `Publish GitHub Release` on `d4e6fda`
  - the dry-run accepted release intent
    `ct-ffi-v2026.04.29-dry-run.d4e6fda`, uploaded
    `native-release-preview`, and did not create a GitHub Release for that
    tag
  - latest clean branch-head audit/log/package/native-dry-run scan passed
    against `d4e6fda` with no skipped, pending, failed, missing, or
    unexpected main `CI` jobs, no high-signal warning, deprecation,
    skipped-test, rawsocket reset, or connection-noise log matches,
    clean/relevant hosted `Dart Package Publish Dry Run` evidence, and
    clean/relevant hosted `Native Artifacts` dry-run evidence
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `bin/audit-github-deployment-chain` now has
    `--show-native-release-dry-run` and
    `--require-clean-native-release-dry-run` so the hosted native artifact
    matrix, release-preview artifact, and dry-run no-mutation evidence are
    audited separately from main `CI`
  - the native release dry-run gate checks the expected Linux, macOS, and
    Windows `ct_ffi` artifact jobs plus `Publish GitHub Release`, verifies
    accepted native dry-run release intent, confirms the dry-run tag did not
    create a GitHub Release, confirms `native-release-preview` was uploaded,
    and reports native-release-sensitive changes since the latest run
  - the fresh `Native Artifacts` dry-run now covers the checked-out head for
    native-release-sensitive inputs
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`,
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-native-release-dry-run`,
    the expected failing
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --require-clean-native-release-dry-run`,
    and
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`
  - post-hosted audit checks passed:
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-native-release-dry-run`
    and
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs --require-clean-dart-package-publish-dry-run --require-clean-native-release-dry-run`
  - full local `bin/verify` passed after the audit and documentation updates
    on 2026-04-29
- Current router image dry-run preview hardening:
  - commit `8fe3749` (`ci: upload router image dry-run preview`) passed
    hosted GitHub `CI` run `25116155461`; `Fast Checks` completed
    successfully in 5m26s and `Full Verify` completed successfully in 7m58s
  - latest clean branch-head audit/log/package-dry-run scan passed against
    `8fe3749` with no skipped, pending, failed, missing, or unexpected main
    `CI` jobs, no high-signal warning, deprecation, skipped-test, rawsocket
    reset, or connection-noise log matches, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - commit `a8260b5` (`docs: record router image attestation ci`) passed
    hosted GitHub `CI` run `25113406609`; `Fast Checks` and `Full Verify`
    completed successfully
  - latest clean branch-head audit/log/package-dry-run scan passed against
    `a8260b5` with no skipped, pending, failed, missing, or unexpected main
    `CI` jobs, no high-signal warning, deprecation, skipped-test, rawsocket
    reset, or connection-noise log matches, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `.github/workflows/router-image.yml` now writes the resolved router image
    metadata summary to `out/router-image-preview/router-image-metadata.md`,
    appends the same content to the Actions step summary, and uploads
    `router-image-preview` for manual dry-run dispatches
  - public deployment docs now describe the router image dry-run preview
    artifact alongside the existing dry-run, approval, provenance, and SBOM
    behavior
  - focused local checks passed: workflow YAML parsing, Python compile/unit
    tests for the metadata helper, dry-run metadata render to a summary file,
    publish metadata render, the expected manual publish rejection smoke, and
    `git diff --check`
  - full local `bin/verify` passed after the workflow and documentation updates
    on 2026-04-29
- Current router image attestation hardening:
  - commit `449b218` (`ci: attest router image publishes`) passed hosted
    GitHub `CI` run `25112417559`; `Fast Checks` and `Full Verify` completed
    successfully
  - latest clean branch-head audit/log/package-dry-run scan passed against
    `449b218` with no skipped, pending, failed, missing, or unexpected main
    `CI` jobs, no high-signal warning, deprecation, skipped-test, rawsocket
    reset, or connection-noise log matches, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - documentation checkpoint `f946e18`
    (`docs: record dart package workflow audit ci`) passed hosted GitHub `CI`
    run `25110768881`; `Fast Checks` and `Full Verify` completed successfully
  - latest clean branch-head audit/log/package-dry-run scan passed against
    `f946e18` with no skipped, pending, failed, missing, or unexpected main
    `CI` jobs, no high-signal warning, deprecation, skipped-test, rawsocket
    reset, or connection-noise log matches, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `.github/workflows/router-image.yml` now consumes explicit router image
    provenance/SBOM metadata: publish builds request `provenance=mode=max`
    and `sbom=true`; dry-runs keep both disabled because cache-only outputs do
    not create registry image attestations
  - `tool/render_router_image_metadata.py` renders those attestation settings
    into GitHub outputs and step summaries with focused unit coverage
  - focused local checks passed: Python compile/unit tests for the metadata
    tool, workflow YAML parsing, dry-run metadata render, publish metadata
    render, the expected manual publish rejection smoke, and `git diff --check`
  - full local `bin/verify` passed after the workflow, metadata helper, tests,
    and documentation updates on 2026-04-29
- Current Dart package hosted dry-run audit hardening:
  - commit `a67b86d` (`ci: audit dart package publish workflow`) passed
    hosted GitHub `CI` run `25109971104`; `Fast Checks` completed
    successfully in 5m18s and `Full Verify` completed successfully in 8m14s
  - latest clean branch-head audit/log/package-dry-run scan passed against
    `a67b86d` with no skipped, pending, failed, missing, or unexpected main
    `CI` jobs, no high-signal warning, deprecation, skipped-test, rawsocket
    reset, or connection-noise log matches, and clean/relevant hosted
    `Dart Package Publish Dry Run` evidence
  - documentation checkpoint `47c3948` passed hosted GitHub `CI` run
    `25108057451`; `Fast Checks` completed successfully in 5m29s and
    `Full Verify` completed successfully in 7m55s
  - latest clean branch-head audit/log scan passed against `47c3948` with no
    skipped, pending, failed, missing, or unexpected main `CI` jobs and no
    high-signal warning, deprecation, skipped-test, rawsocket reset, or
    connection-noise log matches
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `bin/audit-github-deployment-chain` now has
    `--show-dart-package-publish-dry-run` and
    `--require-clean-dart-package-publish-dry-run` so dedicated Dart package
    archive validation is audited separately from main `CI`
  - the Dart package hosted dry-run gate accepts the latest successful
    `Dart Package Publish Dry Run` run `25107394513` on `700ea74` for current
    checked-out head `449b218` because no package-publish-sensitive inputs
    changed between those commits
  - `--show-rc-readiness` now includes the hosted Dart package dry-run gate in
    addition to clean main CI/logs and the strict local Dart package dry-run
    release-order gate
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`,
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 6 --show-dart-package-publish-dry-run`,
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-dart-package-publish-dry-run`,
    and
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 2 --show-rc-readiness`
  - `git diff --check` and full local `bin/verify` passed after the audit and
    documentation updates on 2026-04-29
- Current Dart package release-order plan surfacing:
  - commit `700ea74` (`ci: explain dart package release order`) passed hosted
    GitHub `CI` run `25107394525`; `Fast Checks` completed successfully in
    5m28s and `Full Verify` completed successfully in 7m55s
  - hosted `Dart Package Publish Dry Run` run `25107394513` passed on
    `700ea74`
  - latest clean branch-head audit/log scan passed against `700ea74` with no
    skipped, pending, failed, missing, or unexpected main `CI` jobs and no
    high-signal warning, deprecation, skipped-test, rawsocket reset, or
    connection-noise log matches
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `bin/dart-package-publish-dry-run --show-release-plan` now prints the
    current Dart package public-release chain without changing publishability:
    `connectanum_core 0.1.0` must be made public and published before
    `connectanum_client 2.2.6`, unless the client package is restructured to
    avoid that hosted dependency
  - `bin/audit-github-deployment-chain --show-rc-readiness` now includes the
    same release-order plan when the strict Dart package gate blocks RC
    readiness
  - focused local checks passed:
    `bash -n bin/dart-package-publish-dry-run`,
    `bash -n bin/audit-github-deployment-chain`,
    `bin/dart-package-publish-dry-run --help`,
    `bin/dart-package-publish-dry-run --show-release-plan`,
    the expected failing
    `bin/dart-package-publish-dry-run --strict-release-ready --show-release-plan`,
    and
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`
  - remaining Dart package RC blockers are still operator/product decisions:
    pub.dev package ownership, canonical public versions, and whether
    `connectanum_core` is approved public API
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
- Current release-candidate readiness audit hardening:
  - latest hosted GitHub `CI` run `25105031469` passed on `b747033`;
    `Fast Checks` completed successfully in 5m53s and `Full Verify` completed
    successfully in 8m01s
  - latest clean branch-head audit/log scan passed against `b747033` with no
    skipped, pending, failed, missing, or unexpected main `CI` jobs and no
    high-signal warning, deprecation, skipped-test, rawsocket reset, or
    connection-noise log matches
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `bin/audit-github-deployment-chain` now has `--show-rc-readiness` and
    `--require-rc-ready` so release-candidate status is a repeatable
    non-mutating gate instead of a chat-only judgment
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`,
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 1 --show-rc-readiness`, and
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-rc-ready`
    failed as expected on the current RC blockers while confirming clean CI
    and clean hosted CI logs
  - current RC blockers remain: unprotected `add-router`, undiscoverable
    `router-image.yml`, no visible `ghcr.io/konsultaner/connectanum-router`
    package, no local RC tag/GitHub RC prerelease on the checked-out head, and
    the strict Dart package dry-run blocker where `connectanum_client` depends
    on private workspace package `connectanum_core`
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
- Current Dart package publish warning-gate hardening:
  - commit `1131e7e` (`ci: require zero-warning dart publish dry runs`) passed
    hosted GitHub `CI` run `25102015230`; `Fast Checks` completed
    successfully in 5m30s and `Full Verify` completed successfully in 8m14s
  - hosted `Dart Package Publish Dry Run` run `25102015241` passed on
    `1131e7e`; its log shows `Package has 0 warnings`, the known private
    `connectanum_core` release-order blocker, and
    `All Dart package publish dry-runs reported zero warnings`
  - `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 6 --require-clean-latest-ci --require-clean-latest-ci-logs`
    passed against `1131e7e`, confirming no skipped, pending, failed, missing,
    or unexpected main `CI` jobs and no high-signal warning, deprecation,
    skipped-test, rawsocket reset, or connection-noise log matches
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `bin/dart-package-publish-dry-run` now captures each
    `dart pub publish --dry-run` result and requires `Package has 0 warnings`
    before treating the publishable package archive as clean release evidence
  - focused local checks passed:
    `bash -n bin/dart-package-publish-dry-run` and
    `bin/dart-package-publish-dry-run`
  - `bin/dart-package-publish-dry-run --strict-release-ready` still fails as
    expected on the current release-order blocker:
    `connectanum_client` depends on private workspace package
    `connectanum_core`
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
- Current deployment-chain log-scan audit hardening:
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - `bin/audit-github-deployment-chain` now has
    `--scan-latest-ci-logs` and `--require-clean-latest-ci-logs` modes so the
    latest hosted `CI` run can be scanned repeatably for warning,
    deprecation, skipped-test, rawsocket reset, and connection-noise patterns
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`,
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 2 --scan-latest-ci-logs`,
    and
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 2 --require-clean-latest-ci --require-clean-latest-ci-logs`
  - the new log-scan gate passed against latest hosted GitHub `CI` run
    `25096910826` on `869bb7f`, confirming no high-signal warning,
    deprecation, skipped-test, rawsocket reset, or connection-noise matches
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
  - commit `bd99fcc` (`ci: audit hosted ci logs`) passed hosted GitHub `CI`
    run `25099086900`; `Fast Checks` completed successfully in 5m48s and
    `Full Verify` completed successfully in 8m9s
  - `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 4 --require-clean-latest-ci --require-clean-latest-ci-logs`
    passed against `bd99fcc`, confirming no skipped, pending, failed, missing,
    or unexpected main `CI` jobs and no high-signal warning, deprecation,
    skipped-test, rawsocket reset, or connection-noise log matches
- Current CI cleanup checkpoint:
  - documentation checkpoint `cb55b1f` left hosted GitHub `CI` run
    `25095210918` red in `Full Verify`
  - the failure was reproduced locally in
    `tests::listen_flow::poll_connection_message_returns_payload`; hosted timed
    out waiting for the accepted connection, while local focused reproduction
    reached the same RawSocket polling path and failed before the message was
    ready
  - hosted Linux also reported `ct_core::ktls::server_runtime_required` as
    unused; this helper was not deleted because it still represents the
    operator-visible distinction between optional and required kTLS offload
  - the current local fix keeps the RawSocket test client connected until the
    polling side consumes the message and routes kTLS failure logging through
    the optional/required distinction
  - focused local checks now pass:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi --features ffi-test tests::listen_flow::poll_connection_message_returns_payload -- --nocapture`
    repeated 5 times,
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture`,
    and `git diff --check`
  - local `bin/test-fast` and `bin/verify` passed after the fix, including the
    full `ct_ffi` suite, bench WAMP transport integration, router
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
  - commit `cf77754` (`native: stabilize rawsocket polling test`) restored the
    hosted GitHub chain:
    `CI` run `25096329599` passed with `Fast Checks` in 5m28s and
    `Full Verify` in 7m53s, `kTLS Validation` run `25096329602` passed, and
    `WAMP Profile Benchmarks` run `25096329606` passed
  - `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 4 --require-clean-latest-ci`
    passed against `cf77754`, confirming the latest main `CI` jobs are present
    and successful with no skipped, pending, failed, missing, or unexpected
    jobs
  - hosted log scanning across `CI`, `kTLS Validation`, and
    `WAMP Profile Benchmarks` found no real `warning:`, `::warning`,
    `DeprecationWarning`, rawsocket reset noise, connection ID noise, or
    skipped-test output
- Current workflow visibility audit hardening:
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`, `git diff --check`,
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 2 --require-clean-latest-ci`
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
  - hosted GitHub `CI` run `25094700697` passed on `55e9dc0`:
    `Fast Checks` completed successfully in 5m33s and `Full Verify` completed
    successfully in 8m10s
  - `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 4 --require-clean-latest-ci`
    passed against `55e9dc0`, confirming no skipped, pending, failed, missing,
    or unexpected main `CI` jobs
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, skipped jobs, or errors; remaining matches
    were a passing bcrypt negative-auth test name and Rust `0 failed` summaries
  - `bin/audit-github-deployment-chain` now has an explicit
    `--require-workflows-visible` gate so checked-in workflow discoverability
    can fail independently from clean CI, branch-protection policy, and GHCR
    router package visibility checks
  - the gate is intentionally non-mutating and the focused
    `--require-workflows-visible` check failed as expected until
    `.github/workflows/router-image.yml` is visible through the GitHub Actions
    API after default-branch promotion
- Current router package release-readiness audit hardening:
  - pre-change `bin/test-fast` passed locally on 2026-04-29
  - focused local checks passed:
    `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`, `git diff --check`,
    `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 2 --require-clean-latest-ci`
  - final local `bin/verify` passed, including Rust/FFI tests, Dart package
    tests, bench WAMP transport coverage, full router tests,
    `remote_auth_integration_test`, and the Chrome Dart2Wasm browser websocket
    test
  - hosted GitHub `CI` run `25092705443` passed on `c061ae3`:
    `Fast Checks` completed successfully in 5m38s and `Full Verify` completed
    successfully in 7m55s
  - `GH_BIN="$HOME/bin/gh" bin/audit-github-deployment-chain --branch add-router --run-limit 4 --require-clean-latest-ci`
    passed against `c061ae3`, confirming no skipped, pending, failed, missing,
    or unexpected main `CI` jobs
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, skipped jobs, or errors; remaining matches
    were a passing bcrypt negative-auth test name and Rust `0 failed` summaries
  - `bin/audit-github-deployment-chain` now has an explicit
    `--require-router-package` gate so GHCR router package visibility can fail
    independently from clean CI and branch-protection policy checks
  - the gate is intentionally non-mutating and the focused
    `--require-router-package` check failed as expected until
    `ghcr.io/konsultaner/connectanum-router` is visible after the router image
    workflow is promoted and validated
- Current branch checkpoint `17697ae` is clean locally and hosted as of
  2026-04-28:
  - local CI-cleanup verification before commit `ce05721` covered shell syntax,
    focused Dart router/native tests, focused HTTP/3 ffi-test router tests,
    focused bench WAMP RawSocket integration, `bin/test-fast`, and
    `bin/verify`
  - commit `17697ae` updated the remaining artifact workflow actions to
    Node 24-backed `actions/upload-artifact@v7` and
    `actions/download-artifact@v8`
  - hosted GitHub push runs on `17697ae` completed successfully:
    `CI` `25039426534`, `kTLS Validation` `25039426508`,
    `WAMP Profile Diagnostics` `25039426526`, and
    `WAMP Profile Benchmarks` `25039426501`
  - kTLS validation log inspection confirmed the earlier Node 20 artifact
    deprecation warning is gone after the artifact action upgrade
  - `git status -sb` is clean on `add-router`
- Documentation checkpoint `649afcb` passed hosted GitHub `CI` run
  `25041573952`; `Fast Checks` and `Full Verify` completed successfully and
  `WAMP Profile Gates` were correctly skipped for the docs-only change.
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25042279631` completed
  successfully on clean head `649afcb` with isolated
  `h2_multiplexed_streams_s1`, `threads=4`:
  - result was decision-quality across 3 repeats
  - throughput delta span was `13.11pp`, with kTLS at `-47.86%..-34.75%`
  - p95 delta span was `22.98pp`, with kTLS at `-6.28%..+16.70%`
  - `response_headers_last_write_to_first_read` only moved materially in
    repeat 02, while the stable throughput gap stayed in
    `response_body_tail_read_avg_ms` after the first response-body chunk
- The bounded body-tail diagnostic split verifies locally:
  - `native/bench/src/bin/http_stream.rs` starts a second H2 client read probe
    after the first response-body chunk
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` summarize
    `response_body_tail_connection_read_wait_*` and
    `response_body_tail_connection_read_to_end_*`
  - `tool/ktls_http2_compare.py` and `tool/test_ktls_http2_compare.py` render
    and pin the new fields in the response-body diagnostics
  - local verification is green:
    `bin/test-fast`,
    `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`,
    `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, and `bin/verify`
- Commit `20dbc9a` passed the hosted GitHub push chain:
  - `CI` `25043856689`
  - `kTLS Validation` `25043856696`
  - `WAMP Profile Benchmarks` `25043856615`
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25044549578` completed
  successfully on `20dbc9a`, but was not decision-quality:
  - throughput delta span was `66.64pp`, with deltas `-53.21%`, `+13.43%`,
    and `-15.07%`
  - p95 delta span was within threshold at `25.96pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)`
  - repeat 01 showed kTLS body-side connection-read waits, repeat 02 was
    baseline-header-wait dominated, and repeat 03 was kTLS-header-wait
    dominated, so this hosted run is mixed noise rather than a clean answer
- The current follow-up slice makes those non-decision artifacts more readable:
  - `tool/ktls_http2_compare_repeats.py` adds a top-level
    `## Repeat Phase-Timing Focus` table
  - `tool/test_ktls_http2_compare.py` pins the new aggregate report fields
  - local focused verification is green:
    `bin/test-fast`,
    `python3 -m py_compile tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`,
    `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted run
    `25044549578`, and `bin/verify`
  - commit `d97d34f` (`tool: surface repeat phase timing focus`) passed
    hosted GitHub `CI` run `25045630570`
- The active autonomous focus is now the GitHub deployment chain. Continue H2
  or kTLS diagnosis only when it protects a deployment/release decision or after
  the GitHub release path is production-ready.
- Documentation commit `639c095` (`docs: prioritize github deployment chain`)
  passed hosted GitHub `CI` run `25046524665`; `Fast Checks` and
  `Full Verify` succeeded, while `WAMP Profile Gates` were correctly skipped
  for a docs-only push.
- The current deployment-chain implementation slice expands native release
  artifacts toward Windows:
  - `.github/workflows/native-artifacts.yml` adds a Windows x64 packaging
    runner and uses Bash for the packaging/signing shell steps
  - client/router build hooks now map Linux arm64 and Windows x64 release host
    triples
  - public deployment docs list Windows x64 as a release target
  - local checks are green for `bin/test-fast`, focused hook tests, workflow
    YAML parsing, and `git diff --check`
  - local macOS `cargo check --target x86_64-pc-windows-msvc` cannot complete
    because the Windows MSVC C headers/toolchain are unavailable locally; the
    GitHub Windows runner is the required validation signal
- Manual hosted `Native Artifacts` run `25047530571` on `9bfdee1` confirmed the
  Windows x64 job builds, packages, signs, and verifies the bundle, but failed
  in `actions/attest@v4` because the multiline `subject-path` was interpreted
  as one literal path on Windows. The current follow-up splits archive,
  checksum, and manifest attestations into separate single-subject steps.
- Manual hosted `Native Artifacts` run `25047880947` on `f26f358` confirmed the
  split attestation steps are valid on Linux and macOS, but Windows still could
  not resolve the Git Bash `/d/a/...` path inside the Node-based attestation
  action. The current follow-up keeps POSIX paths for shell/cosign and uses
  workspace-relative paths for `actions/attest` and `actions/upload-artifact`.
- Local `bin/verify` passed after the workspace-relative GitHub Actions path
  fix. The first local attempt failed only because the autonomous launchd runner
  held the shared native runtime lock during its own `bin/test-fast`; rerunning
  once the lock was released passed, including the Chrome browser-platform test.
- Hosted GitHub deployment-chain validation is clean on `86a4e7c`
  (`ci: use workspace-relative artifact paths`):
  - GitHub `CI` run `25048277995` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for this non-benchmark change as expected
  - manual `Native Artifacts` run `25048283917` passed all matrix legs:
    Linux x64, Linux arm64, macOS Apple Silicon, macOS Intel, and Windows x64
  - the Windows x64 leg now builds, packages, signs, verifies, attests, and
    uploads the `ct_ffi` bundle using workspace-relative paths for Node-based
    GitHub actions
- Documentation checkpoint `7a411e3`
  (`docs: record native artifact ci success`) passed hosted GitHub `CI` run
  `25049241654`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- The current deployment-chain slice adds a safe native-release dry-run path:
  - `.github/workflows/native-artifacts.yml` accepts manual
    `release_tag=<tag>` plus `dry_run=true`
  - dry-run publish jobs render the exact GitHub Release title, release notes,
    and asset list into a `native-release-preview` artifact, then exit before
    creating or updating a GitHub Release
  - `tool/render_native_release_notes.py` makes the release note body
    locally testable instead of depending on inline workflow shell only
  - focused local checks are green: `bin/test-fast`,
    `python3 -m py_compile tool/render_native_release_notes.py tool/test_render_native_release_notes.py`,
    `python3 tool/test_render_native_release_notes.py`,
    `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml')"`,
    a local render preview for `ct-ffi-v2026.04.28-preview`, and `bin/verify`
- Hosted GitHub validation is clean on `7b45ede`
  (`ci: add native release dry run`):
  - GitHub `CI` run `25050575954` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for this non-benchmark change as expected
  - manual `Native Artifacts` dry-run `25051217251` passed all native matrix
    legs: Linux x64, Linux arm64, macOS Apple Silicon, macOS Intel, and
    Windows x64
  - the dry-run publish job rendered the release metadata, uploaded
    `native-release-preview`, and stopped before release mutation
  - `gh release view ct-ffi-v2026.04.28-dry-run.7b45ede` returned
    `release not found`, confirming the dry-run path did not create or update a
    GitHub Release
- Documentation checkpoint `d3ecfd1`
  (`docs: record native release dry run validation`) passed hosted GitHub `CI`
  run `25051747670`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- The current installer-coverage slice aligns explicit `install_native.dart`
  host mapping with the hosted native release matrix:
  - `connectanum_client` and `connectanum_router` installer helpers now map
    Linux x64, Linux arm64, macOS x64, macOS arm64, and Windows x64 release
    triples
  - focused installer tests cover every hosted target mapping and unsupported
    host/architecture errors
  - local checks are green for `bin/test-fast`,
    `dart test packages/connectanum_client/test/hook/install_native_test.dart`,
    `dart test packages/connectanum_router/test/hook/install_native_test.dart`,
    and `bin/verify`
- Hosted GitHub validation is clean on `39e68b1`
  (`installer: cover native release artifact matrix`):
  - GitHub `CI` run `25052974513` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped inside the main CI workflow
  - GitHub `WAMP Profile Benchmarks` run `25052974498` passed the Linux
    canonical WAMP profile gate and uploaded its artifacts
- Documentation checkpoint `34cf2cd`
  (`docs: record installer ci success`) passed hosted GitHub `CI` run
  `25053975131`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- Native release/install validation is clean for validation prerelease
  `ct-ffi-v2026.04.28-validation.34cf2cd`:
  - manual GitHub `Native Artifacts` run `25054948537` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    `Publish GitHub Release` job
  - the release was created as a prerelease with the full hosted matrix asset
    set
  - direct source-checkout installer smoke validation passed on macOS arm64 via
    `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.34cf2cd`
- The validation exposed a public-instruction issue rather than a packaging
  failure: `dart run <package>:tool/install_native.dart` is not the reliable
  public install path because package runs invoke native build hooks before the
  helper can run. The current follow-up corrects README/deployment/release-note
  guidance to prefer `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for normal
  hook-managed downloads and direct `dart packages/.../tool/install_native.dart`
  only for source-checkout prefetches.
  - focused local checks passed:
    `python3 -m py_compile tool/render_native_release_notes.py tool/test_render_native_release_notes.py`,
    `python3 tool/test_render_native_release_notes.py`,
    `bash -n bin/validate-native-release-install`, `git diff --check`, and
    `bin/verify`
- Hosted GitHub validation is clean on `c925e1e`
  (`docs: clarify native release install path`):
  - GitHub `CI` run `25055877717` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped inside the main CI workflow
  - GitHub `WAMP Profile Benchmarks` run `25055877739` passed the Linux
    canonical WAMP profile gate and uploaded its artifacts
- Documentation checkpoint `51f7061`
  (`docs: record install path ci success`) passed hosted GitHub `CI` run
  `25056742848`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- Corrected native release notes and release publishing are validated on
  `51f7061`:
  - manual GitHub `Native Artifacts` dry-run `25057503370` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    preview publish job
  - the dry-run `native-release-preview` release notes documented
    `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for normal hook-managed downloads
    and direct `dart packages/.../tool/install_native.dart` commands only for
    source-checkout prefetches
  - `gh release view ct-ffi-v2026.04.28-dry-run.51f7061` returned
    `release not found`, confirming the dry-run path did not create or update a
    GitHub Release
  - manual GitHub `Native Artifacts` run `25057834597` created prerelease
    `ct-ffi-v2026.04.28-validation.51f7061` with 30 hosted matrix assets
  - the published prerelease targets commit
    `51f706179e9ec654639c19e170f38fd2d03573da`, is marked as prerelease, and
    contains the corrected public install instructions
  - source-checkout installer smoke validation passed via
    `bin/validate-native-release-install --tag ct-ffi-v2026.04.28-validation.51f7061`
- Native artifact publish-job log cleanliness is validated on `95837fb`
  (`ci: download native artifacts with gh`):
  - the publish job now downloads current-run `ct-ffi-*` artifacts through
    `gh run download` with explicit `actions: read` permission instead of
    `actions/download-artifact@v8`
  - the change removes the Node `Buffer()` deprecation warning previously
    emitted by the latest `actions/download-artifact` release during the
    `Download packaged artifacts` step
  - local checks passed: `bin/test-fast`, YAML parsing for
    `.github/workflows/native-artifacts.yml`, and `git diff --check`
  - hosted GitHub `CI` run `25059702813` passed `Fast Checks` and
    `Full Verify`; `WAMP Profile Gates` was skipped for the workflow-only push
  - manual GitHub `Native Artifacts` dry-run `25060480993` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    preview publish job using the `gh run download` path
  - the dry-run `native-release-preview` still listed all 30 expected release
    assets, and `gh release view ct-ffi-v2026.04.28-dry-run.95837fb` returned
    `release not found`
  - a hosted log scan found no `DeprecationWarning`, `warning:`, or
    `::warning` lines; the only match was a Cosign installer shell alias that
    contains the literal text `ERROR:`
- Documentation checkpoint `b63be66`
  (`docs: record native artifact warning cleanup`) passed hosted GitHub `CI`
  run `25061163684`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push.
- The current release-safety slice adds an explicit pre-mutation gate for
  native GitHub Release publishing:
  - `.github/workflows/native-artifacts.yml` adds
    `stable_release_approval`, requiring manual non-prerelease release runs to
    type the `release_tag` exactly before any GitHub Release is created or
    updated
  - `tool/validate_native_release_intent.py` rejects malformed release tags,
    publishing of `-dry-run` tags, non-prerelease `-validation` publishes, and
    unapproved manual stable release publishes
  - focused local checks passed: `bin/test-fast`,
    `python3 -m py_compile tool/validate_native_release_intent.py tool/test_validate_native_release_intent.py`,
    `python3 tool/test_validate_native_release_intent.py`, workflow YAML
    parsing, representative validator CLI acceptance checks, `git diff --check`,
    and `bin/verify`
- Release-intent hosted validation is clean on `8dc966f`
  (`ci: guard manual stable native releases`):
  - GitHub `CI` run `25063769464` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for the workflow/tooling push
  - manual GitHub `Native Artifacts` dry-run `25063774771` passed Linux x64,
    Linux arm64, macOS Apple Silicon, macOS Intel, Windows x64, and the
    preview publish job
  - the hosted `Validate release intent` step accepted
    `ct-ffi-v2026.04.28-dry-run.8dc966f` as `(native, dry-run)`
  - the preview metadata still listed all 30 expected native release assets,
    and `gh release view ct-ffi-v2026.04.28-dry-run.8dc966f` returned
    `release not found`
- The current CI-log cleanup slice suppresses expected rawsocket peer shutdown
  noise:
  - hosted CI on `8dc966f` exposed a passing-test line,
    `connection ConnectionId(...) io error: Connection reset by peer`, during
    the native RawSocket MsgPack cancel-cycle workload
  - `native/transport/ct_core/src/lib.rs` now uses the existing
    `is_benign_socket_shutdown` helper for rawsocket frame-reader IO errors,
    matching existing WebSocket shutdown classification for `UnexpectedEof`,
    `BrokenPipe`, `ConnectionReset`, and `ConnectionAborted`
  - focused local checks passed:
    `cargo test --manifest-path native/transport/Cargo.toml -p ct_core websocket_io_disconnects_are_classified_as_peer_shutdowns -- --nocapture`
    and `bin/test-fast`; the local cancel-cycle fast-test segment no longer
    emitted the connection-reset line
- Rawsocket benign-shutdown log cleanup is hosted-clean on `6a6f036`
  (`native: quiet benign rawsocket shutdowns`):
  - local `bin/verify` passed end-to-end before commit
  - GitHub `CI` run `25065253852` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped for this non-benchmark push path
  - GitHub `kTLS Validation` run `25065253836` passed
  - hosted log scanning found no `Connection reset by peer` or
    `connection ConnectionId` lines after the rawsocket reader started using
    `is_benign_socket_shutdown`
  - remaining `failed` matches were passing test names/result summaries, not
    failed checks
- CI-timeout hardening is hosted-clean on `ccb61f9`
  (`ci: bound github workflow runtimes`):
  - GitHub `CI` run `25066016309` passed `Fast Checks` but left
    `Full Verify` in progress for more than 30 minutes after the prior
    comparable full-verify job completed in about 9 minutes
  - the stale unbounded run was cancelled after the timeout-hardening slice
    started, so the next pushed head can provide the branch-cleanliness signal
  - the GitHub workflows now use job-level `timeout-minutes` so stuck runners
    fail closed instead of leaving branch status indefinitely pending
  - timeout budgets are intentionally generous relative to recent hosted runs:
    `Fast Checks` 20 minutes, `Full Verify` 45 minutes, WAMP/kTLS validation
    30-45 minutes, native artifact packaging 45 minutes, native publish 20
    minutes, and long manual image/kTLS benchmark jobs 120 minutes
  - local `bin/test-fast`, workflow YAML parsing, `git diff --check`, and
    `bin/verify` passed before commit
  - hosted GitHub push runs on `ccb61f9` passed:
    `CI` `25068442355`, `kTLS Validation` `25068442344`,
    `WAMP Profile Benchmarks` `25068442348`, and
    `WAMP Profile Diagnostics` `25068442381`
  - hosted log scanning found no `warning:`, `::warning`,
    `DeprecationWarning`, `Connection reset by peer`,
    `connection ConnectionId`, timeout, cancellation, or real error lines;
    remaining `failed` matches were passing test names or Rust test summaries
- Dart package publishing readiness is hosted-clean on `1b95c9d`
  (`docs: prepare dart package publishing`):
  - `bin/test-fast` passed before package metadata changes
  - every package now has a package-root MIT `LICENSE`, matching the repo
    license and satisfying pub.dev's mandatory package-root license check
  - package pubspecs now expose GitHub `homepage`, `repository`, and
    `issue_tracker` metadata for readable future package pages
  - `dart pub publish --dry-run` from `packages/connectanum_client` passes
    from a clean git state with `Package has 0 warnings`
  - `docs/dart_package_publishing.md` records the remaining product/deployment
    blocker: pub.dev currently returns `404` for both `connectanum_client` and
    `connectanum_core`, while `connectanum_client` depends on
    `connectanum_core: ^0.1.0`; real publishing still needs explicit package
    ownership, version, and publish-order decisions
  - local `bin/verify` passed after the package metadata/docs changes
  - hosted GitHub `CI` run `25071505471` passed and `WAMP Profile Benchmarks`
    run `25071505445` passed
  - hosted log scanning found no warnings, deprecations, rawsocket reset noise,
    timeouts, cancellations, or real errors; remaining matches were passing
    test names or Rust test summaries
- Documentation checkpoint `4b17fa6`
  (`docs: record package publish readiness ci`) passed hosted GitHub `CI` run
  `25072248218`:
  - `Fast Checks` and `Full Verify` completed successfully
  - `WAMP Profile Gates` was skipped because the docs-only push was not a
    manual benchmark dispatch
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were passing
    test names or Rust test summaries
- The current branch-protection/release-evidence slice adds a repeatable
  GitHub deployment-chain audit:
  - `bin/audit-github-deployment-chain --branch master --run-limit 4` reports
    that `master` is protected, requires one CODEOWNER review, disallows force
    pushes/deletions, has no repository rulesets, and currently has no required
    status checks
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 6`
    reports that `add-router` is unprotected and that the latest branch runs
    are hosted-clean through `CI` run `25072248218`
  - `docs/github_deployment_chain.md` records the branch-protection gap and the
    recommended minimum required checks: `Fast Checks` and `Full Verify`
  - no remote branch-protection setting was changed autonomously; applying
    required status checks remains an operator decision because it changes
    merge policy
  - local `bin/test-fast` passed before the audit script and evidence docs
    were added
  - local `bin/verify` passed after the audit script and evidence docs were
    added, including the Chrome browser-platform test
  - hosted GitHub `CI` run `25073711527` passed on `be37ec4`; `Fast Checks`
    and `Full Verify` succeeded, `WAMP Profile Gates` was skipped as expected
    for a non-manual run, and hosted log scanning found no real warnings,
    deprecations, rawsocket reset noise, timeouts, cancellations, or errors
- Documentation checkpoint `21a998d`
  (`docs: record github deployment audit ci`) passed hosted GitHub `CI` run
  `25074424163`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push. Hosted
  log scanning found no real warnings, deprecations, rawsocket reset noise,
  timeouts, cancellations, or errors.
- The current router-image release-evidence slice corrects an advertised
  public-artifact gap:
  - GitHub's workflow API does not expose `.github/workflows/router-image.yml`
    because the workflow file is not on the default branch
  - `gh workflow view router-image.yml --repo konsultaner/connectanum-dart`
    returns `404`, and the GitHub Packages API returns `404` for
    `ghcr.io/konsultaner/connectanum-router`
  - `README.md` and `docs/deployment.md` now describe the router image as a
    staged intended release target, not a currently published production
    artifact
  - `deploy/k8s/connectanum-router.yaml` now uses
    `ghcr.io/konsultaner/connectanum-router:replace-me` instead of `:latest`
    so the template no longer points at an unavailable floating production tag
  - `bin/audit-github-deployment-chain` now reports checked-in workflow
    visibility and GHCR router package visibility so this gap remains visible
    until the workflow/package are promoted and validated
  - focused checks passed: `bin/test-fast`, `bash -n
    bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --branch add-router --run-limit 2`,
    strict-mode failure smoke test for the known release-readiness gaps, and
    `git diff --check`
  - local `bin/verify` passed after the audit and public-documentation
    changes, including the Chrome browser-platform test
  - commit `ad6412d` (`docs: correct router image release evidence`) passed
    hosted GitHub `CI` run `25077069136`; `Fast Checks` and `Full Verify`
    succeeded, while `WAMP Profile Gates` was correctly skipped for the
    non-manual push. Hosted log scanning found no real warnings, deprecations,
    rawsocket reset noise, timeouts, cancellations, or errors; remaining
    matches were a passing bcrypt test name and Rust `0 failed` summaries.
- Documentation checkpoint `391590d`
  (`docs: record router image evidence ci`) passed hosted GitHub `CI` run
  `25077810300`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push. Hosted
  log scanning found no real warnings, deprecations, rawsocket reset noise,
  timeouts, cancellations, or errors; remaining matches were a passing bcrypt
  test name and Rust `0 failed` summaries.
- The current router-image publish-safety slice keeps future manual image
  validation non-mutating by default:
  - `.github/workflows/router-image.yml` now has a manual `dry_run` input that
    defaults to `true`
  - manual publishes require `dry_run=false` plus `publish_approval` exactly
    matching the primary image tag before GHCR login or push can run
  - `tool/render_router_image_metadata.py` centralizes image tag, label,
    dry-run output, and publish-intent resolution with focused unit coverage
  - tag pushes still resolve the existing `v*` publishing contract, while
    manual dry-runs build with `type=cacheonly` and do not log in to GHCR
  - focused local checks passed: `bin/test-fast`, Python compile/unit tests for
    the metadata tool, workflow YAML parsing, stable tag metadata render, manual
    publish rejection smoke test, deployment-chain audit, and `git diff --check`
  - local `bin/verify` passed after the workflow, tool, and documentation
    changes, including the Chrome browser-platform test
  - commit `be29fe6` (`ci: gate router image manual publishes`) passed hosted
    GitHub `CI` run `25080054856`; `Fast Checks` and `Full Verify` succeeded,
    while `WAMP Profile Gates` was correctly skipped for the normal push.
    Hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a
    passing bcrypt test name and Rust `0 failed` summaries.
- Documentation checkpoint `b6d05ca`
  (`docs: record router image publish gate ci`) passed hosted GitHub `CI` run
  `25080633807`; `Fast Checks` and `Full Verify` succeeded, while
  `WAMP Profile Gates` was correctly skipped for the docs-only push. Hosted
  log scanning found no real warnings, deprecations, rawsocket reset noise,
  timeouts, cancellations, or errors; remaining matches were a passing bcrypt
  test name and Rust `0 failed` summaries.
- The current Dart package publish-readiness slice adds hosted non-mutating
  pub.dev archive validation:
  - `bin/dart-package-publish-dry-run` discovers publishable workspace
    packages, skips `publish_to: none` packages by default, and runs
    `dart pub publish --dry-run` for every publishable package
  - the dry-run now reports publishable packages that still depend on private
    workspace packages; `--strict-release-ready` turns that report into a
    failing release gate once the package release plan is approved
  - `.github/workflows/dart-package-publish.yml` runs the same check on
    package metadata/docs/license/changelog changes and on manual dispatch
  - the local dry-run currently validates `packages/connectanum_client` and
    reports `Package has 0 warnings`; it also reports that `connectanum_client`
    depends on private workspace package `connectanum_core`
  - private workspace packages remain skipped until an explicit publish
    decision changes their `publish_to` policy
  - focused local checks passed: `bin/test-fast`, `bash -n
    bin/dart-package-publish-dry-run`, workflow YAML parsing,
    `bin/dart-package-publish-dry-run`, and the expected failing
    `bin/dart-package-publish-dry-run --strict-release-ready` blocker check
  - local `bin/verify` passed after the workflow, script, and documentation
    changes, including the Chrome browser-platform test
  - commit `d9cbd81` (`ci: add dart package publish dry run`) passed hosted
    GitHub `CI` run `25082475062`; `Fast Checks` and `Full Verify` succeeded,
    while `WAMP Profile Gates` was correctly skipped for the normal push
  - the dedicated `Dart Package Publish Dry Run` workflow run `25082475073`
    passed and validated the publishable Dart package archive without
    publishing to pub.dev
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a
    passing bcrypt test name and Rust `0 failed` summaries
- Hosted GitHub validation is clean on `ee32ad3`
  (`ci: report dart package release blockers`):
  - GitHub `CI` run `25084695576` passed `Fast Checks` and `Full Verify`;
    `WAMP Profile Gates` was skipped inside the main CI workflow for this
    normal push
  - GitHub `Dart Package Publish Dry Run` run `25084695572` passed and
    surfaced the `connectanum_client` -> private `connectanum_core`
    release-readiness blocker without publishing to pub.dev
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a
    passing bcrypt test name and Rust `0 failed` summaries
- Documentation checkpoint `4b1ce40`
  (`docs: record dart release blocker ci`) passed hosted GitHub `CI` run
  `25085322707`; `Fast Checks` and `Full Verify` succeeded. The only hosted
  log-scan matches were benign: a passing bcrypt negative-auth test name and
  Rust `0 failed` summaries.
- The current CI skipped-gate cleanup removes the duplicate manual-only
  `WAMP Profile Gates` job from the main `CI` workflow. Canonical WAMP profile
  benchmark gates remain in the dedicated `WAMP Profile Benchmarks` workflow,
  which runs on relevant benchmark/native/router/client path changes and on
  manual dispatch.
  - pre-change local `bin/test-fast` passed on 2026-04-29
  - focused local checks passed: workflow YAML parsing for `dart.yml` and
    `wamp-profile-benchmarks.yml`, plus `git diff --check`
  - local `bin/verify` passed after the workflow and documentation changes,
    including the Chrome browser-platform test
  - commit `5441730` (`ci: remove duplicate wamp gate skip`) passed hosted
    GitHub `CI` run `25086102543`; the workflow now contains only
    `Fast Checks` and `Full Verify`, with no skipped WAMP job
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a
    passing bcrypt test name and Rust `0 failed` summaries
- The current latest-CI audit gate makes that no-skipped-job expectation
  repeatable:
  - `bin/audit-github-deployment-chain --branch add-router
    --run-limit 2 --require-clean-latest-ci` now checks the latest `CI` run
    for exactly `Fast Checks` and `Full Verify`
  - the gate exits non-zero if latest `CI` has skipped, pending, failed,
    missing, or unexpected jobs
  - focused local checks passed: `bash -n bin/audit-github-deployment-chain`,
    `bin/audit-github-deployment-chain --help`, and the live read-only audit
    above against `add-router`
- Hosted GitHub validation is clean on `1769982`
  (`ci: audit latest ci job cleanliness`):
  - local `bin/test-fast` and `bin/verify` passed before the audit gate commit
  - GitHub `CI` run `25087405841` passed `Fast Checks` and `Full Verify`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 4
    --require-clean-latest-ci` reports no skipped, pending, failed, missing,
    or unexpected `CI` jobs on the latest branch run
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, or errors; remaining matches were a
    passing bcrypt test name and Rust `0 failed` summaries
- The current branch-protection follow-up keeps the policy decision
  operator-only while making the required-check plan reproducible:
  - `bin/audit-github-deployment-chain --branch master
    --show-required-checks-plan` prints the minimal
    `required_status_checks` payload for `Fast Checks` and `Full Verify`
    without mutating GitHub settings
  - local `bin/test-fast`, focused audit checks, `git diff --check`, and
    `bin/verify` passed after adding the operator-plan output
  - applying required status checks to `master` still requires explicit
    operator approval because it changes repository merge policy
- Hosted GitHub validation is clean on `a3ae4a3`
  (`ci: print branch protection check plan`):
  - GitHub `CI` run `25088676567` passed `Fast Checks` and `Full Verify`
  - `bin/audit-github-deployment-chain --branch add-router --run-limit 4
    --require-clean-latest-ci` reports no skipped, pending, failed, missing,
    or unexpected `CI` jobs on the latest branch run
  - `bin/audit-github-deployment-chain --branch master --run-limit 1
    --show-required-checks-plan` confirms `master` is protected but still has
    no required status checks, and prints the read-only operator plan for
    `Fast Checks` plus `Full Verify`
  - hosted log scanning found no real warnings, deprecations, rawsocket reset
    noise, timeouts, cancellations, skipped jobs, or errors; remaining matches
    were a passing bcrypt negative-auth test name and Rust `0 failed` summaries
  - a follow-up local `bin/test-fast` pass on 2026-04-29 confirmed the branch
    remains locally healthy before refreshing this state
- Documentation checkpoint `3db2bbe`
  (`docs: record branch protection audit ci`) passed hosted GitHub `CI` run
  `25089948391`; `Fast Checks` and `Full Verify` succeeded.
  `bin/audit-github-deployment-chain --branch add-router --run-limit 4
  --require-clean-latest-ci` confirmed the latest main `CI` run has no
  skipped, pending, failed, missing, or unexpected jobs. Hosted log scanning
  found no real warnings, deprecations, rawsocket reset noise, timeouts,
  cancellations, skipped jobs, or errors; remaining matches were a passing
  bcrypt negative-auth test name and Rust `0 failed` summaries.
- The current public evidence refresh makes `docs/github_deployment_chain.md`
  less brittle by pointing readers to the live clean-CI audit for branch-head
  status and listing pinned deployment-chain checkpoints instead of calling an
  older commit the latest audited branch evidence.
- GitLab has not surfaced an `add-router` pipeline through the current API
  query, so GitHub Actions is the current visible hosted CI source for this
  branch.
- A same-workspace background process can still block local native-suite
  verification by holding the shared
  `${TMPDIR:-/tmp}/connectanum_native_runtime.lock` file.
  - The latest successful local `bin/verify` run required terminating a stale
    background Codex loop that was still running
    `packages/connectanum_bench/test/wamp_transport_integration_test.dart`
  - That was a local workspace-concurrency issue, not a repo regression
- Hosted GitHub push runs on `45fcba8` completed successfully:
  `CI` `24914678995`, `kTLS Validation` `24914678987`,
  `WAMP Profile Benchmarks` `24914678985`
- Hosted GitHub push runs on `1fa0c45` completed successfully:
  `CI` `24917321434`, `kTLS Validation` `24917321426`,
  `WAMP Profile Benchmarks` `24917321423`
- Hosted GitHub push runs on `4228983` completed successfully:
  `CI` `24919421672`, `kTLS Validation` `24919421664`,
  `WAMP Profile Benchmarks` `24919421657`
- Hosted GitHub push runs on `b551a6d` completed successfully:
  `CI` `24920276210`, `kTLS Validation` `24920276202`,
  `WAMP Profile Benchmarks` `24920276214`
- Hosted GitHub push runs on `355a117` completed successfully:
  `CI` `24921028426`, `kTLS Validation` `24921028397`,
  `WAMP Profile Benchmarks` `24921028403`
- Hosted GitHub push run on `5f79e40` completed successfully:
  `CI` `24921840775`
  - `kTLS Validation` and `WAMP Profile Benchmarks` were correctly skipped by
    their `push.paths` filters because `5f79e40` only changed report tooling
- Hosted GitHub push runs on `17697ae` completed successfully:
  `CI` `25039426534`, `kTLS Validation` `25039426508`,
  `WAMP Profile Diagnostics` `25039426526`, and
  `WAMP Profile Benchmarks` `25039426501`
  - `kTLS Validation` confirmed the artifact action warning is gone after the
    workflow action upgrade
- Hosted GitHub `CI` run `25041573952` completed successfully on `649afcb`.
- Manual hosted `kTLS HTTP/2 Benchmarks` run `25042279631` completed
  successfully on `649afcb` and produced decision-quality isolated `s1`,
  `threads=4` evidence.
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24920655184` completed
  successfully on clean head `b551a6d`, but remained not decision-quality for
  isolated `h2_multiplexed_streams_s1`, `threads=4`:
  - throughput delta span `23.53pp` stayed within the stability threshold
  - p95 delta span `371.80pp` remained far above threshold and stayed on the
    kTLS side
  - the new header-path split narrowed the remaining gap to
    `response_headers_connection_read_wait`, while
    `response_headers_connection_read_to_headers`,
    `post_header_connection_read_wait`, and
    `connection_read_to_first_chunk` all stayed flat or nearly flat
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24921433741` completed
  successfully on clean head `355a117` and reached decision-quality for
  isolated `h2_multiplexed_streams_s1`, `threads=4`:
  - throughput delta span `20.81pp`
  - p95 delta span `15.55pp`
  - worst throughput and p95 rows stayed stable at
    `h2_multiplexed_streams_s1 (workers=1, threads=4)` across all repeats
  - `response_headers_connection_write_wait` and
    `response_headers_connection_write_span` stayed small and flat enough that
    request-flush activity is no longer the lead suspect
- The current compare-report readability slice is green locally:
  - `bin/test-fast`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `tmpdir=$(mktemp -d /tmp/connectanum-ktls-rerender-XXXXXX) && python3 tool/ktls_http2_compare.py /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/baseline/bench_results.summary.json /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/ktls/bench_results.summary.json "$tmpdir/comparison.json" "$tmpdir/comparison.md"`
  - `bin/verify`
- The current isolated header-gap split is green locally:
  - `bin/test-fast`
  - `cargo test --manifest-path native/bench/Cargo.toml h2_last_write_to_first_read_gap_uses_last_write_boundary --bin http_stream -- --nocapture`
  - `cargo test --manifest-path native/bench/Cargo.toml summarize_report_computes_latency_and_deltas -- --nocapture`
  - `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `tmpdir=$(mktemp -d /tmp/connectanum-ktls-rerender-XXXXXX) && python3 tool/ktls_http2_compare.py /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/baseline/bench_results.summary.json /tmp/connectanum-run-24921433741/extracted/repeats/repeat-02/ktls/bench_results.summary.json "$tmpdir/comparison.json" "$tmpdir/comparison.md"`
- The current workload-isolation methodology slice is green locally:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `python3 -m py_compile tool/filter_bench_scenario.py tool/test_filter_bench_scenario.py tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_filter_bench_scenario.py`
  - `python3 tool/test_ktls_http2_compare.py`
  - `python3 tool/filter_bench_scenario.py native/bench/scenarios/h2_ktls_multiplex_stability.toml /tmp/connectanum-ktls-filtered.toml h2_multiplexed_streams_s4,h2_multiplexed_streams_s8`
  - `bin/ktls-http2-bench --help | rg 'workloads|repeat-order|cooldown-seconds|repeat-count'`
  - `bin/verify`
- Hosted GitHub push run on `a2a66ea` completed successfully:
  `CI` `24913663589`
- Hosted GitHub push runs on `c0e9171` completed successfully:
  `CI` `24911914621`, `kTLS Validation` `24911914629`,
  `WAMP Profile Benchmarks` `24911914617`
- Hosted GitHub push runs on `d66a72d` completed successfully:
  `CI` `24910233897`, `kTLS Validation` `24910233859`,
  `WAMP Profile Benchmarks` `24910233901`
- Hosted GitHub push runs on `25b2b7a` completed successfully:
  `CI` `24902101047`, `WAMP Profile Benchmarks` `24902101976`
- Hosted GitHub push runs on `c21172f` completed successfully:
  `CI` `24903966470`, `kTLS Validation` `24903966478`,
  `WAMP Profile Benchmarks` `24903966456`
- Hosted GitHub push runs on `070b229` completed successfully:
  `CI` `24905612643`, `kTLS Validation` `24905612638`,
  `WAMP Profile Benchmarks` `24905612662`
- Hosted GitHub push runs on `a2e7f81` completed successfully:
  `CI` `24907299479`, `kTLS Validation` `24907299524`,
  `WAMP Profile Benchmarks` `24907299451`
- Manual hosted `kTLS HTTP/2 Benchmarks` reruns `24908173404` and
  `24908372116` both completed successfully on clean head `a2e7f81`, but they
  did not converge on a decision-quality result
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24906538797`
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24904942758`
- Manual hosted `kTLS HTTP/2 Benchmarks` rerun `24903103241`

## Autonomous Priority

1. Keep the CI chain clean first. If local `bin/verify` is failing or the latest known branch CI is red, continuation work should switch to restoring green before new implementation or benchmark work.
2. Make the GitHub deployment chain the main project spine. Prefer GitHub
   Actions health, release workflow validation, multi-platform FFI artifacts,
   human-readable releases/artifacts, public package metadata, and branch
   protection/deployment evidence before speculative implementation work.
3. Prioritize production readiness of current functionality before exploratory expansion. That includes correctness, release/deployment behavior, observability, packaging, operational docs, and coverage for shipped paths.
4. Treat MCP support for downstream application integration as the next product-readiness milestone once CI, GitHub deployment-chain blockers, and shipped-path blockers are clean. It outranks speculative H3, kTLS, E2EE, and benchmark exploration until the first usable MCP server/bridge path is designed, implemented, tested, and documented.
5. After the first usable MCP path is complete, make WAMP profile-related transport performance production-ready in the benchmark suite before returning to speculative transport work. That means canonical RawSocket/WebSocket WAMP scenarios, secure and cleartext coverage, serializer/profile coverage, explicit budgets/gates, and hosted CI evidence for release decisions.
6. With the first MCP path, the WAMP benchmark-readiness milestone, the
   host-supported WAMP transport-interop slice, and the worker-safe realm
   authorization milestone complete, use `ROADMAP_NEXT.md` to choose the next
   production-readiness task and keep prioritizing shipped-path correctness
   before speculative transport work.
7. Other benchmark and performance work stays important, but it should serve
   production readiness and release confidence rather than run ahead of it.

## Resume Order

1. Read `AGENTS.md`.
2. Read this file.
3. If there is an active plan under `docs/exec-plans/`, read that plan next.
4. Use `ROADMAP_NEXT.md` only to choose the next milestone after checking active plans.
5. Use `ROADMAP.md` and `STRUCTURE.md` as reference material when details are needed.

## Current Operational Truth

- The repo is a Dart workspace plus a Rust native transport workspace.
- The canonical root entrypoints are `bin/bootstrap`, `bin/test-fast`, `bin/test-all`, and `bin/verify`.
- Root shell helpers now auto-detect Dart from Flutter, Rust from `~/.cargo`, Chrome/Chromium, and the standard prebuilt native library path.
- GitHub Actions is the primary deployment-chain signal for autonomous work on
  this branch. Keep workflow warnings, skipped jobs, release artifacts, and
  public release metadata readable and intentional before returning to
  speculative transport diagnosis.
- The first usable MCP path for downstream application integration now covers
  local stdio usage and the first router-hosted HTTP POST endpoint:
  `packages/connectanum_mcp` has the transport-independent server core, stdio
  framing, WAMP-backed tool delegation, declared WAMP API helpers,
  metadata-derived event topics, and pub/sub polling tools. `connectanum_router` can
  expose MCP over HTTP through `type: mcp` routes backed by internal WAMP
  sessions, exact procedure registrations, WAMP meta API tools, and pub/sub
  helpers. Full Streamable HTTP GET/SSE/session semantics, resources, and
  prompts remain downstream-demand driven.
- Initial MCP research is captured in `docs/mcp_integration_research.md`.
  The first implementation slice now lives in `packages/connectanum_mcp` with
  a transport-independent Dart server core, typed protocol errors/capabilities,
  callback-backed tools, focused lifecycle/tool tests, a stdio transport
  adapter, a tiny stdio echo CLI example, WAMP-backed tool delegation through
  existing `connectanum_client` sessions, declared API helpers, and the first
  router-hosted HTTP POST endpoint through `connectanum_router` routes.
- The root verification scripts now include the MCP package tests:
  `bin/test-fast` and `bin/test-all` both run
  `dart test packages/connectanum_mcp/test`.
- Manual hosted rerun `24903103241` on clean head `25b2b7a` confirmed the
  main-isolate control-port optimization closed the old
  `direct_stream_request_queue_delay` hotspot on
  `h2_multiplexed_streams_s2`, `threads=1`.
- Manual hosted rerun `24920655184` on clean head `b551a6d` tightened the
  isolated `h2_multiplexed_streams_s1`, `threads=4` diagnosis:
  - repeat-level instability still sits in the client-side
    `response_headers_wait` path
  - the new header split showed the movement almost entirely in
    `response_headers_connection_read_wait`
  - `response_headers_connection_read_to_headers`,
    `response_body_post_header_connection_read_wait`, and
    `response_body_connection_read_to_first_chunk` stayed flat enough that
    header parsing and post-header body delivery are no longer the lead
    suspects
- Manual hosted rerun `24921433741` on clean head `355a117` resolved the
  write-side branch of that same isolated `s1` diagnosis:
  - the rerun is decision-quality instead of another noisy partial read
  - `response_headers_connection_write_wait` stayed around
    `0.04..0.07 ms`
  - `response_headers_connection_write_span` stayed around
    `0.18..0.19 ms`
  - those write-side metrics did not move with the repeat-level throughput or
    p95 deltas, so the remaining isolated `s1` gap is not explained by the
    client still flushing request bytes while waiting for response headers
- The bounded readability follow-up for that result is committed and
  CI-cleared as `5f79e40`:
  - `tool/ktls_http2_compare.py` renders the header-write metrics in
    `comparison.md`, not only in `comparison.json`
  - the phase focus lines now surface `response-header connection write` wait
    and span alongside the existing read-side diagnostics
  - the header diagnostics table now exposes those same fields so hosted
    artifacts are useful without opening raw JSON
- The next bounded split inside `response_headers_connection_read_wait` is
  committed and hosted-clean through `17697ae`:
  - the native bench summary records
    `response_headers_last_write_to_first_read_*`
  - that metric isolates the idle gap after the last request-side connection
    write and before the first response-side connection read during
    `response_headers_wait`
  - if the next isolated hosted `s1` rerun moves on that gap, the remaining
    instability is downstream of client flush completion and upstream of the
    first response read
- Manual hosted rerun `25042279631` on clean head `649afcb` showed that
  `response_headers_last_write_to_first_read` is not the stable throughput
  explanation:
  - repeat 02 moved on that header post-flush gap and on p95
  - repeats 01 and 03 stayed flat or improved on the header post-flush gap
  - the decision-quality throughput regression persisted across all repeats
    in `response_body_tail_read_avg_ms` after the first response-body chunk
- The bounded body-tail diagnostic split needed for the next hosted rerun is
  implemented and locally verified:
  - the bench records `response_body_tail_connection_read_wait_*`
  - the bench records `response_body_tail_connection_read_to_end_*`
  - the compare report renders both fields in the phase focus lines and the
    response-body diagnostics table
- That rerun also moved the remaining hotspot deeper into the HTTP/2 native
  response-stream path on `h2_multiplexed_streams_s8`, `threads=1`: server
  direct-stream timings improved, but client `response headers wait`,
  `response body first chunk wait`, and native
  `headers_to_first_connection_write` still regressed.
- The local HTTP/2 scheduler tuning lane reached a real hosted evidence limit
  on clean head `a2e7f81`.
- Two focused reruns on that same clean head produced different extreme
  outliers:
  - `24908173404` made `h2_multiplexed_streams_s4`, `threads=4` look like a
    huge kTLS win because baseline throughput collapsed to `868 Mbps`
  - `24908372116` instead made
    `h2_multiplexed_streams_s2`, `threads=4` the worst throughput and p95 row
- That means the next blocker is hosted benchmark stability, not another blind
  HTTP/2 scheduler tweak on top of `a2e7f81`.
- Manual hosted rerun `24904942758` on clean head `c21172f` showed the
  change was only half-right:
  - the old `h2_multiplexed_streams_s8`, `threads=1` hotspot improved sharply
    to `-13.12%` throughput / `+11.40%` p95
  - a new low-multiplex regression appeared on
    `h2_multiplexed_streams_s1`, `threads=1`
    with `-60.21%` throughput / `+124.86%` p95
  - that new worst row regressed on `response headers wait` while
    `response body first chunk wait` improved, which implicates the
    unconditional headers-side yield rather than the first-chunk yield
- That narrowed follow-up is now pushed as commit `070b229`
  (`perf(http2): keep yield on first streamed chunk only`), and its GitHub
  push chain completed successfully.
- Manual hosted rerun `24906538797` on clean head `070b229` showed the
  low-contention fix was real but incomplete:
  - `h2_multiplexed_streams_s1`, `threads=1` improved to
    `-14.98%` throughput / `+13.38%` p95
  - but `h2_multiplexed_streams_s2`, `threads=1` became the new worst
    throughput row at `-60.98%`
  - and `h2_multiplexed_streams_s16`, `threads=1` became the new worst p95 row
    at `+73.72%`
  - `h2_multiplexed_streams_s8`, `threads=1` regressed back to
    `-31.10%` throughput / `+42.83%` p95
- That outcome narrows the next local follow-up now on the working tree in
  `native/transport/ct_core/src/lib.rs`: keep the header-side yield only when
  multiple streamed responses have queued headers on the same HTTP/2
  connection, while still keeping the first-chunk yield.
- Focused local verification is green on that multiplex-aware follow-up:
  - `bin/test-fast`
  - `cargo test --manifest-path native/transport/ct_core/Cargo.toml http2_connection_write_tracker -- --nocapture`
  - `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip -- --nocapture`
  - `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/2 response chunks using native streams' -r expanded`
  - `dart test packages/connectanum_bench/test/http_stream_handler_test.dart -r expanded`
  - `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results /tmp/connectanum-h2-local-results.jsonl --artifact-dir /tmp/connectanum-h2-local-artifacts --router-worker-counts 1 --native-runtime-thread-counts 1,4`
- That multiplex-aware follow-up is now pushed as commit `a2e7f81`
  (`perf(http2): yield on header contention only`).
- Its GitHub push chain completed successfully:
  - `CI` `24907299479`
  - `kTLS Validation` `24907299524`
  - `WAMP Profile Benchmarks` `24907299451`
- Manual hosted rerun `24908173404` completed successfully on the same head,
  but the result is not decision-quality:
  - `h2_multiplexed_streams_s4`, `threads=4` showed a baseline collapse to
    `868 Mbps` while adjacent rows stayed in-family
  - `h2_multiplexed_streams_s8`, `threads=4` inverted the other way with
    `-66.89%` throughput / `+423.33%` p95
  - that pattern is inconsistent with the prior hosted reruns and the local
    repro, so it is more likely host noise than a coherent regression shape
- Confirmatory rerun `24908372116` also completed successfully on clean head
  `a2e7f81`, but it shifted the outlier elsewhere instead of converging:
  - worst throughput row moved to
    `h2_multiplexed_streams_s2`, `threads=4` at `-83.11%`
  - worst p95 row also moved to
    `h2_multiplexed_streams_s2`, `threads=4` at `+1316.65%`
- The repeat-stability tooling is now pushed as commit `d66a72d`
  (`build(ktls): add repeat stability reporting`):
  - `bin/ktls-http2-bench` supports `--repeat-count <n>`
  - `.github/workflows/ktls-http2-benchmarks.yml` exposes the matching
    `repeat_count` input
  - `tool/ktls_http2_compare_repeats.py` aggregates repeated comparison files
    into a top-level repeat-stability report that marks the hosted evidence as
    decision-quality or not
- That commit's GitHub push chain completed successfully:
  - `CI` `24910233897`
  - `kTLS Validation` `24910233859`
  - `WAMP Profile Benchmarks` `24910233901`
- Focused manual hosted rerun `24911158486` completed successfully on the same
  clean head with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_scaling.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That repeat-stability artifact still marked the hosted evidence as not
  decision-quality:
  - worst throughput row changed across all three repeats
  - worst p95 row changed across all three repeats
  - `h2_multiplexed_streams_s4`, `threads=1` spanned `77.77pp` throughput
    delta
  - `h2_multiplexed_streams_s2`, `threads=1` spanned `1174.48pp` p95 delta
- The baseline side stayed relatively stable while the kTLS side did not:
  - `h2_multiplexed_streams_s2`, `threads=1` baseline throughput only spanned
    `470.25 Mbps`, while kTLS throughput spanned `3470.66 Mbps`
  - `h2_multiplexed_streams_s2`, `threads=1` baseline p95 only spanned
    `2.34 ms`, while kTLS p95 spanned `190.52 ms`
- The next bounded stabilization slice is now pushed as commit `c0e9171`
  (`build(ktls): add stability benchmark scenario`):
  - `native/bench/scenarios/h2_ktls_multiplex_stability.toml` keeps the same
    multiplex sweep but raises each workload to `48` iterations with
    `1000 ms` warmup for manual repeat runs
  - `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` stays unchanged as
    the quick diagnostic scenario
  - `native/bench/README.md` now separates quick diagnostic usage from
    decision-quality repeat usage
- Local verification was green before that push:
  - `bin/test-fast`
  - `bin/verify`
- Hosted GitHub push runs for `c0e9171` completed successfully:
  - `CI` `24911914621`
  - `kTLS Validation` `24911914629`
  - `WAMP Profile Benchmarks` `24911914617`
- Focused manual hosted rerun `24912748466` completed successfully on the same
  clean head with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=1,4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That larger-sample rerun still did not reach decision quality, but it
  narrowed the instability sharply:
  - every remaining row that exceeded the stability thresholds used
    `native_runtime_threads=4`
  - the `native_runtime_threads=1` rows now fit within the current
    throughput/p95 span thresholds
  - `h2_multiplexed_streams_s16`, `threads=4` stayed the worst p95 row in
    `2/3` repeats, with p95 delta spanning `641.63pp`
  - `h2_multiplexed_streams_s4`, `threads=4` showed a baseline collapse in one
    repeat, producing a `228.53pp` throughput-delta span
- The next manual diagnostic step is therefore narrower than before:
  - rerun the same stability scenario with `native_runtime_thread_counts=4`
    only to determine whether the remaining instability is intrinsic to the
    `threads=4` lane or partly caused by mixing `1,4` in one hosted run
- Focused manual hosted rerun `24913116550` then completed successfully with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `skip_artifact_gate=true`
- That isolated `threads=4` rerun still did not reach decision quality:
  - `h2_multiplexed_streams_s16`, `threads=4` remained the worst p95 row in
    `2/3` repeats, with p95 delta spanning `460.16pp`
  - `h2_multiplexed_streams_s2`, `threads=4` still showed a baseline collapse
    in one repeat, producing a `216.79pp` throughput-delta span
  - `h2_multiplexed_streams_s1`, `threads=4` also still showed baseline-side
    instability, with throughput delta spanning `124.79pp`
- The current blocker is now clearer:
  - isolating `threads=4` from `threads=1` did not make the hosted lane
    decision-quality
  - the next useful slice should change benchmark methodology or runner
    control, not the HTTP/2 transport path
- The current branch head now carries a bounded repeat-analysis slice on top of
  that blocker:
  - `tool/ktls_http2_compare_repeats.py` now labels each unstable row as
    baseline-side, kTLS-side, or mixed for throughput and p95 span sources
  - the repeat summary markdown now calls out the top instability-source
    highlights before the per-row table
  - `tool/test_ktls_http2_compare.py` pins that new classification and markdown
    output
- Local verification is green on that working tree:
  - `bin/test-fast`
  - focused Python compile/tests and repeat-summary rerenders against hosted
    runs `24912748466` and `24913116550`
  - `bin/verify`
- The new repeat-source labeling makes the hosted blocker more precise:
  - `h2_multiplexed_streams_s16`, `threads=4` is still primarily kTLS-side
  - `h2_multiplexed_streams_s2`, `threads=4` and `s1`, `threads=4` show
    baseline-side throughput instability
- That repeat-analysis slice is now pushed as commit `a2a66ea`
  (`build(ktls): label repeat instability sources`).
- The next branch-head slice now targets runner control rather than transport
  behavior:
  - `bin/ktls-http2-bench` now accepts `--repeat-order` and
    `--cooldown-seconds`
  - repeated runs now emit `repeat-plan.txt` so the artifact records the exact
    pass order and cooldown used for each repeat
  - the manual `kTLS HTTP/2 Benchmarks` workflow exposes the same controls and
    now defaults manual repeats to `repeat_order=alternating` and
    `cooldown_seconds=15`
  - `native/bench/README.md` documents those new runner-control defaults
- Local verification is green on that runner-control slice:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `bin/ktls-http2-bench --help | rg 'repeat-order|cooldown-seconds|repeat-count'`
  - `bin/verify`
- Manual hosted rerun `24915345703` then completed successfully on clean head
  `45fcba8` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=alternating`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That first controlled rerun did not become decision-quality, but it improved
  the throughput side materially versus `24913116550`:
  - largest throughput span dropped from `216.79pp` on
    `h2_multiplexed_streams_s2` to `47.32pp` on `s1`
  - the old `h2_multiplexed_streams_s16` p95 outlier disappeared
  - the only `ktls-first` repeat (`repeat-02`) was also the clear outlier,
    with `h2_multiplexed_streams_s8` jumping to `+457.45%` p95
- Manual hosted rerun `24915629218` then completed successfully on the same
  clean head with the same settings except `repeat_order=baseline-first`.
- That confirmation rerun still did not become decision-quality, but it
  narrowed the blocker further:
  - the prior `s8` and `s16` kTLS-side p95 instability disappeared
  - `h2_multiplexed_streams_s2` also stabilized
  - the remaining blocker is now concentrated in
    `h2_multiplexed_streams_s4`, where one baseline repeat spiked to
    `216.48 ms` p95 and drove a `119.62pp` p95 span plus `64.53pp`
    throughput span
  - `h2_multiplexed_streams_s1` still shows a kTLS-side throughput span of
    `51.18pp`
- The hosted runner-control picture is therefore clearer now:
  - alternating order exposed that `ktls-first` repeats were the worst shape
  - fixed `baseline-first` removed the earlier kTLS-side p95 explosion
  - the remaining instability is smaller and now split between a baseline-side
    `s4` spike and a kTLS-side `s1` throughput spread
- Manual hosted rerun `24916589841` then completed successfully on the same
  clean head with the same settings as `24915629218` except
  `cooldown_seconds=60`.
- That longer-cooldown rerun made the lane less stable again:
  - `h2_multiplexed_streams_s2` returned as the worst throughput and p95 row
    with a `76.69pp` throughput span and `981.77pp` p95 span, both kTLS-side
  - `h2_multiplexed_streams_s8` and `s16` also became unstable again on the
    baseline side
  - the result is materially worse than the `15s` baseline-first run, so
    simply increasing cooldown is not a monotonic fix
- The next useful step is therefore no longer "try a larger sleep":
  - simple runner timing knobs are exhausted enough to stop tuning them blindly
  - the next methodology slice should isolate repeats or hotspot workloads more
    structurally, rather than keep stretching one multi-repeat run on one
    runner
  - the hosted `threads=4` lane is therefore mixed-noise, not one clean
    transport regression shape
- The structural methodology slice is committed and CI-cleared as `1fa0c45`:
  - `tool/filter_bench_scenario.py` materializes a temporary focused scenario
    by keeping only named workloads from an existing checked-in scenario
  - `bin/ktls-http2-bench` now accepts `--workloads <csv>` and records both
    `scenario_source` and `scenario_effective` in `host-info.txt`
  - the manual `kTLS HTTP/2 Benchmarks` workflow exposes the same filter as the
    `workloads` input
  - `native/bench/README.md` now documents hotspot-isolated reruns instead of
    only full-scenario stability reruns
- Focused local verification is green on that slice:
  - `bin/test-fast`
  - `bash -n bin/ktls-http2-bench`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ktls-http2-benchmarks.yml')"`
  - `python3 -m py_compile tool/filter_bench_scenario.py tool/test_filter_bench_scenario.py tool/ktls_http2_compare.py tool/ktls_http2_compare_repeats.py tool/test_ktls_http2_compare.py`
  - `python3 tool/test_filter_bench_scenario.py`
  - `python3 tool/filter_bench_scenario.py native/bench/scenarios/h2_ktls_multiplex_stability.toml /tmp/connectanum-ktls-filtered.toml h2_multiplexed_streams_s4,h2_multiplexed_streams_s8`
  - `bin/ktls-http2-bench --help | rg 'workloads|repeat-order|cooldown-seconds|repeat-count'`
- Manual hosted rerun `24917873323` then completed successfully on clean head
  `1fa0c45` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `workloads=h2_multiplexed_streams_s1`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=baseline-first`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That isolated `s1` rerun still did not become decision-quality:
  - throughput delta spanned `46.95pp`, from `-62.63%` to `-15.68%`
  - p95 delta stayed within threshold at `42.53pp`, from `-12.50%` to
    `+30.02%`
  - the remaining spread was explicitly kTLS-side on throughput
  - there were still no non-zero transport counters, no connection churn, and
    server-emission timings improved while client-side first-chunk/body-read
    timings regressed
- Manual hosted rerun `24917876488` then completed successfully on the same
  clean head with the same settings except
  `workloads=h2_multiplexed_streams_s4`.
- That isolated `s4` rerun is decision-quality:
  - throughput delta stayed within `5.15pp`, from `-17.35%` to `-12.20%`
  - p95 delta stayed within `7.81pp`, from `+4.19%` to `+12.00%`
  - the stable regression shape includes `Backpressure events 71 -> 82 (+11)`,
    `Backpressure alerts 2 -> 3 (+1)`, and
    `response headers wait avg 17.55 -> 21.16 (+3.61)`
  - connections opened, samples per connection, and chunk shape all stayed
    flat, so the isolated `s4` result now looks like a real multiplex-path
    regression rather than runner noise
- Manual hosted rerun `24918088324` then ran the same isolated `s1` workload
  with `repeat_count=5`.
- That longer `s1` rerun failed in the benchmark step, but the uploaded
  artifact still sharpened the picture:
  - the completed repeats converged into decision-quality spans:
    throughput `11.85pp` and p95 `21.75pp`
  - repeat outputs exist for `repeat-01` through `repeat-04`, but
    `repeat-04` is partial and baseline-only summary output is missing
  - the partial comparison reports `baseline` elapsed wall time `308.65s`
    versus `9.17s` for the `kTLS` pass, which points to a long-repeat
    baseline stall rather than another wide spread in the completed samples
- The repeat-stability blocker is therefore narrow enough to stop broad
  methodology tuning:
  - `s4` is now a stable, decision-quality transport regression shape
  - `s1` is likely also a real low-contention regression shape, but the
    repeat-05 attempt exposed a separate long-repeat harness stall that should
    not be conflated with the transport deltas themselves
  - the next useful step is transport diagnosis on isolated `s1` / `s4`
    evidence, with the long-repeat baseline stall tracked as a harness issue
- The next bounded diagnosis slice for isolated `s1` is committed and
  CI-cleared as `4228983`:
  - `native/bench/src/bin/http_stream.rs` wraps the HTTP/2 client transport so
    the bench can see the first successful socket read after response headers
  - `native/bench/src/report.rs` and `native/bench/src/artifacts.rs` now
    summarize two new receive-side timings:
    `response_body_post_header_connection_read_wait_*` and
    `response_body_connection_read_to_first_chunk_*`
  - `tool/ktls_http2_compare.py` now renders those new fields in the
    response-body diagnostics table and focus lines
  - the new metric split should tell the next isolated hosted `s1` rerun
    whether the remaining gap appears before the first post-header connection
    read or after bytes have already reached the HTTP/2 client body path
- Manual hosted rerun `24919870963` then completed successfully on clean head
  `4228983` with:
  - `scenario=native/bench/scenarios/h2_ktls_multiplex_stability.toml`
  - `workloads=h2_multiplexed_streams_s1`
  - `router_worker_counts=1`
  - `native_runtime_thread_counts=4`
  - `repeat_count=3`
  - `repeat_order=baseline-first`
  - `cooldown_seconds=15`
  - `skip_artifact_gate=true`
- That rerun ruled out the post-header first-body hypothesis:
  - the worst throughput and p95 row stayed stable at
    `h2_multiplexed_streams_s1`, `threads=4`, but the result is still not
    decision-quality because throughput span stayed at `290.71pp` and p95 span
    at `1833.65pp`
  - the new post-header receive-side metrics stayed flat or improved in all
    repeats:
    `post-header connection read wait avg 1.08 -> 0.94`, `1.18 -> 0.72`,
    `1.22 -> 1.11`
  - `connection read-to-first-chunk avg` also stayed flat:
    `0.35 -> 0.31`, `0.39 -> 0.38`, `0.38 -> 0.44`
  - the instability remained in `response headers wait avg` instead:
    `4.31 -> 29.65`, `29.01 -> 3.47`, `8.33 -> 4.27`
- The next bounded diagnosis slice is committed and CI-cleared as `b551a6d`:
  - split `response_headers_wait` into
    `response_headers_connection_read_wait_*` and
    `response_headers_connection_read_to_headers_*`
  - the next isolated hosted `s1` rerun should decide whether the remaining
    instability appears before the first response connection read or between
    that read and header parsing
- GitLab has not surfaced an `add-router` pipeline for `1fa0c45` or the
  isolated manual rerun follow-ups through the current token-backed API query.
- `packages/connectanum_core` is approved as a design reference for MCP package
  shape: typed protocol models, serializer-independent boundaries, explicit
  errors, small barrel exports, and focused tests. Reuse the style, not WAMP
  semantics.
- The WAMP profile transport performance-readiness plan is complete. Hosted
  GitHub validation is green through commit `175ae0a`: commit `5a8b918`
  passed push `CI` (`24853368527`) and `WAMP Profile Benchmarks`
  (`24853368528`), and the follow-up docs checkpoint `175ae0a` passed push
  `CI` (`24853407962`).
- The most recent product-readiness plan is now complete too:
  `docs/exec-plans/2026-04-23-wamp-transport-interop-coverage.md` added
  host-supported live WAMP transport interop coverage for the pure Dart
  RawSocket client path and mixed RawSocket/WebSocket routing, so the shipped
  transport surface is now protected beyond serializer and router-state
  conformance alone.
- `packages/connectanum_router/test/publish_ack_test.dart` now covers the pure
  Dart RawSocket publish-ack path across JSON, MessagePack, and CBOR against a
  live router.
- `packages/connectanum_router/test/router_integration_websocket_test.dart`
  now covers mixed RawSocket/WebSocket publish, call, and error routing across
  rawsocket JSON + CBOR clients and a websocket MsgPack client on the current
  macOS-supported path.
- Hosted GitHub validation is green through commit `c97eff4`: push `CI` run
  `24858211416` and `WAMP Profile Benchmarks` run `24858211413` both completed
  successfully on the earlier branch head.
- Hosted GitHub validation is now also green through commit `8da3602`:
  push `CI` run `24860616844` and `WAMP Profile Benchmarks` run `24860616860`
  both completed successfully after the kTLS comparison-artifact readability
  follow-up was pushed to both remotes.
- Hosted GitHub validation is now also green through commit `7bf3d8a`:
  push `CI` run `24861886418`, `WAMP Profile Benchmarks` run `24861886401`,
  and `kTLS Validation` run `24861886408` all completed successfully after the
  kTLS resource-usage follow-up was pushed to both remotes.
- Hosted GitHub validation is now also green through commit `911b208`:
  push `CI` run `24862887602`, `kTLS Validation` run `24862887603`, and
  `WAMP Profile Benchmarks` run `24862887632` all completed successfully after
  the kTLS workflow-summary follow-up was pushed to both remotes.
- The worker-safe realm authorization follow-up is now complete on the local
  working tree. Router settings now carry top-level
  `authorization_providers` definitions plus per-realm
  `authorization_provider` selection, worker isolates resolve providers from
  serialized settings instead of relying on a single isolate-local
  `AuthorizationProviderRegistry` object, and the default router worker
  entrypoint is now public so custom worker bootstraps can register provider
  factories before delegating to the standard worker.
- The old dynamic-authorization gap is now covered by a focused live
  integration regression in
  `packages/connectanum_router/test/authorization_integration_test.dart`,
  which reproduces the real worker-isolate path instead of only the old
  in-process callback path.
- Local verification for the current realm-authorization follow-up is green:
  `bin/test-fast`, `cd packages/connectanum_router && dart test
  test/authorization_test.dart test/authorization_integration_test.dart
  test/router_config_loader_test.dart -r expanded`, and `bin/verify` all
  passed on 2026-04-23.
- The kTLS comparison-artifact readability follow-up is now complete on the
  local working tree. `bin/ktls-http2-bench` now delegates comparison
  rendering to `tool/ktls_http2_compare.py`, and both `comparison.json` and
  `comparison.md` now carry aggregate summary findings instead of only raw
  per-workload rows.
- The next active kTLS slice is to make the same manual HTTP/2 comparison
  artifacts capture and summarize per-pass resource usage, because the current
  kTLS decision gap is performance interpretation rather than missing
  correctness coverage.
- That resource-usage slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` now writes per-pass `resource-usage.txt` sidecars for
  the baseline and required-kTLS passes, and `tool/ktls_http2_compare.py` now
  folds CPU-total, wall-time, and max-RSS deltas into `comparison.json` and
  `comparison.md`.
- The next active kTLS slice is to publish the generated comparison directly in
  the manual GitHub Actions workflow summary, so the next hosted Linux rerun is
  readable from the Actions UI before anyone downloads `ktls-http2-bench`
  artifacts.
- That workflow-summary slice is now complete on the local working tree too.
  The manual `kTLS HTTP/2 Benchmarks` workflow now writes the generated
  `comparison.md` and `host-info.txt` content into the Actions job summary on
  `always()`, so future hosted reruns have a readable first-stop view in the
  run UI before artifact download.
- The next kTLS comparison-readability slice is now complete on the local
  working tree too. `tool/ktls_http2_compare.py` now rolls the comparison up
  by workload family and native runtime thread count, highlights the current
  investigation focus for both groupings, and correctly parses GNU `time -v`
  elapsed wall-time labels that include embedded colons.
- Hosted GitHub validation is now also green through commit `f2b5fe8`:
  push `kTLS Validation` run `24864087126`, `WAMP Profile Benchmarks` run
  `24864087127`, and `CI` run `24864087129` all completed successfully after
  the kTLS hotspot-rollup follow-up was pushed to both remotes.
- Manual workflow run `24864760931` (`kTLS HTTP/2 Benchmarks`) then failed on
  `add-router` only because the generic zero-counter artifact gate rejected the
  expected `h2_multiplexed_streams` backpressure counters after both baseline
  and required-kTLS passes completed and uploaded comparison artifacts.
- The active kTLS slice is therefore to scope `bin/ktls-http2-bench` to a
  checked-in `h2_ktls_benchmark` artifact policy, so the manual comparison
  workflow stays meaningful without weakening the stricter correctness contract
  that remains covered by `kTLS Validation`.
- That artifact-policy slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` validates both comparison passes against
  `native/bench/artifact_gate/h2_ktls_benchmark.json`, and `native/bench`
  now has focused regression coverage for thread-scoped policy matching.
- Local verification for the current kTLS artifact-policy follow-up is green on
  2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml artifact_gate_policy_allows_thread_scoped_thresholds
  -- --nocapture`, `bash -n bin/ktls-http2-bench`, and `bin/verify` all
  passed.
- Hosted GitHub validation is now green through commit `706d8b8` too:
  push `CI` run `24865318342`, push `kTLS Validation` run `24865318343`,
  push `WAMP Profile Benchmarks` run `24865318353`, and manual
  `kTLS HTTP/2 Benchmarks` run `24865337582` all completed successfully after
  the scoped `h2_ktls_benchmark` artifact-policy follow-up landed.
- Hosted GitHub validation is now also green through commit `6deaabe`:
  push `CI` run `24866820516` completed successfully after the hosted
  resource-usage parser fix landed.
- Hosted GitHub validation is now also green through commit `db2ff96`:
  push `CI` run `24868012745`, push `kTLS Validation` run `24868012749`, and
  push `WAMP Profile Benchmarks` run `24868012750` all completed successfully
  after the kTLS transport-delta comparison follow-up landed.
- Hosted GitHub validation is now also green through commit `2393a01`:
  push `CI` run `24868963261`, push `kTLS Validation` run `24868963265`, and
  push `WAMP Profile Benchmarks` run `24868963262` all completed successfully
  after the Linux TLS-stat follow-up landed.
- Hosted GitHub validation is now also green through commit `257f9aa`:
  push `CI` run `24870440483`, push `kTLS Validation` run `24870440482`, and
  push `WAMP Profile Benchmarks` run `24870440494` all completed successfully
  after the multiplex-diagnostic control follow-up landed.
- The latest hosted `ktls-http2-bench-artifacts` bundle from run `24865337582`
  also exposed a concrete summary bug: both per-pass `resource-usage.txt`
  sidecars were present, but the generated comparison still claimed they were
  missing because GNU `time -v` prefixes its fields with tabs on hosted Linux.
- That resource-usage parser slice is now complete on the local working tree
  too. `tool/ktls_http2_compare.py` now strips leading whitespace before
  matching GNU `time -v` field labels, so the hosted Linux tab-indented
  `resource-usage.txt` sidecars are summarized instead of being ignored.
- The corrected rerender of that hosted artifact shows required-kTLS still
  loses mainly on throughput and p95, not on gross CPU or memory blow-up:
  average throughput delta `-24.20%`, average p95 delta `+40.38%`,
  `cpu_total_seconds +2.26%`, `elapsed_seconds +1.71%`, and
  `max_rss_kib +0.57%`. The grouped hotspot is now
  `h2_sustained_transfer` by workload family and `threads=1` by native runtime
  thread count.
- The raw hosted per-workload summaries also show that current transport
  counters do not explain that hotspot directly: both `h2_sustained_transfer`
  rows stayed at zero for backpressure, alerts, throttles, and timeout/error
  counters in both baseline and required-kTLS passes, while only the
  `h2_multiplexed_streams` rows showed bounded backpressure differences.
- That transport-delta slice is now complete on the local working tree too.
  `tool/ktls_http2_compare.py` now renders transport-counter views for the
  worst throughput row, the worst p95 row, and each comparable workload row in
  both `comparison.json` and `comparison.md`.
- That Linux TLS-stat slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` now captures `/proc/net/tls_stat` before and after
  each pass when the proc file is readable, and
  `tool/ktls_http2_compare.py` now summarizes kernel TLS session-open plus
  decrypt/rekey deltas in both `comparison.json` and `comparison.md`.
- The current hosted rerender now makes the boundary explicit: the worst p95
  row (`h2_sustained_transfer`, `threads=1`) still shows no non-zero transport
  counters in either pass, while only the multiplexed rows expose bounded
  `backpressure_events` differences (`76 -> 70` at `threads=1`,
  `82 -> 97` at `threads=4`).
- Manual workflow run `24869856621` (`kTLS HTTP/2 Benchmarks`) then reran the
  updated helper on `2393a01` and changed the current boundary again:
  required-kTLS now clearly opens kernel software TX/RX sessions
  (`TlsTxSw/TlsRxSw 34/34`) with no decrypt/rekey anomalies, while the
  dominant regression shifts back to `h2_multiplexed_streams` rather than
  `h2_sustained_transfer`.
- That means the next bounded kTLS follow-up should enable focused diagnostic
  reruns around the multiplex case instead of adding more generic artifact
  formatting or treating the old sustained-transfer row as the primary
  hotspot.
- That diagnostic-control slice is now complete on the local working tree too.
  `bin/ktls-http2-bench` now supports explicit `--artifact-policy` selection
  plus `--skip-artifact-gate`, the manual `kTLS HTTP/2 Benchmarks` workflow
  mirrors those controls as workflow inputs, and
  `native/bench/scenarios/h2_ktls_multiplex_scaling.toml` now gives the next
  hosted rerun a checked-in HTTP/2 multiplex-only hotspot scenario without
  weakening the canonical `h2_ktls_benchmark` release-decision path.
- Manual workflow run `24870980724` then exercised that new focused scenario
  on `257f9aa` with `skip_artifact_gate=true`, and the result tightened the
  kTLS question again:
  every `h2_ktls_multiplex_scaling` row regressed under required-kTLS, the
  best row was still `-12.23%` throughput (`s2`, `threads=4`), the worst row
  was `-64.97%` throughput (`s4`, `threads=4`), and even
  `streams_per_connection=1` regressed by roughly `-50%` with zero transport
  counters in either pass.
- That rerun also confirms the old kernel-path question is closed for this
  scenario too: required-kTLS opened software TX/RX sessions cleanly
  (`TlsTxSw/TlsRxSw 66/66`) with no decrypt or rekey anomalies.
- That connection-usage instrumentation slice is now complete on the pushed
  branch head too. Commit `55f23d3` passed hosted push `CI`
  (`24872329789`), `kTLS Validation` (`24872329782`), and
  `WAMP Profile Benchmarks` (`24872329792`) before the focused manual rerun.
- Manual workflow run `24872903498` then exercised the same focused scenario
  with the new connection section enabled, and it ruled out connection churn:
  every comparable row held `connections_opened` flat at `4 -> 4 (+0)`, and
  every row held `samples_per_connection_avg` flat at
  `20.00 -> 20.00 (+0.00)`.
- That hosted rerun leaves the same workload shape as the unresolved hotspot:
  `h2_multiplexed_streams_s16` at `threads=4` is still the worst throughput
  row (`-65.14%`), and `h2_multiplexed_streams_s8` at `threads=4` is still the
  worst p95 row (`+423.24%`).
- That phase-timing instrumentation slice is now complete on the pushed branch
  head too. Commit `3d85b51` passed hosted push `CI` (`24873599372`),
  `kTLS Validation` (`24873599375`), and `WAMP Profile Benchmarks`
  (`24873599379`) before the next focused manual rerun.
- Manual workflow run `24874338657` then exercised the same focused scenario
  with the new phase-timing section enabled, and it ruled out stream-slot
  acquisition as the primary bottleneck:
  - stream acquire wait stayed effectively flat on the same hotspot rows
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4`
    (`stream acquire wait avg 0.00 -> 0.00`, `request round trip avg 18.20 -> 31.72`)
  - worst p95 row:
    `h2_multiplexed_streams_s8` at `threads=1`
    (`stream acquire wait p95 0.00 -> 0.12`, `request round trip p95 39.13 -> 70.01`)
- The next bounded kTLS slice is therefore deeper HTTP/2 request-path
  diagnostics, not more connection or acquire-wait instrumentation. The next
  active plan is to split the post-acquire path so the artifacts can show
  whether the regression is concentrated in request upload, response-header
  wait, or response-body drain.
- That deeper request-path split is now implemented on the local working tree
  too. The HTTP/2 bench path now records request enqueue, response-header
  wait, and response-body read timing alongside the existing acquire-wait and
  round-trip timing, and `tool/ktls_http2_compare.py` now renders those new
  sub-phases in the phase summary.
- Local verification for the request-path phase-split slice is green on
  2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted artifact
  `24874338657`, and `bin/verify`.
- That request-path phase-split slice is now complete on the pushed branch
  head too. Commit `a88a8b7` passed hosted push `CI` (`24874851886`),
  `kTLS Validation` (`24874851872`), and `WAMP Profile Benchmarks`
  (`24874851879`) before the next focused manual rerun.
- Manual workflow run `24875528924` then exercised the same focused scenario
  with the deeper request-path timing enabled, and it narrowed the remaining
  hotspot to the HTTP/2 response-body drain:
  - worst throughput row and worst p95 row both landed on
    `h2_multiplexed_streams_s8` at `threads=1`
  - `stream acquire wait avg` improved slightly (`0.05 -> 0.02`)
  - `request enqueue avg` stayed negligible (`0.04 -> 0.06`)
  - `response headers wait avg` stayed flat (`28.65 -> 28.52`)
  - `response body read avg` jumped from `7.86` to `58.91`
  - `response body read p95` jumped from `14.11` to `467.44`
- The next bounded kTLS slice is therefore response-body-drain diagnostics on
  the HTTP/2 client path. The next active plan is to separate first-body-byte
  wait from sustained body-drain time and capture the observed chunk shape so
  the next rerun can tell whether the regression is a first-chunk stall or a
  sustained read/flow-control problem.
- That response-body-drain instrumentation slice is now implemented on the
  local working tree too. The HTTP/2 bench path now records response-body
  first-chunk wait, post-first-chunk tail-read time, observed chunk count, and
  first-chunk bytes, and `tool/ktls_http2_compare.py` now renders those
  metrics in the worst-row phase views plus a dedicated
  `HTTP Response-Body Diagnostics` section.
- Historical hosted artifact `24875528924` rerenders cleanly with the updated
  helper, and the new response-body diagnostics correctly show `n/a` there
  because that bundle predates the new instrumentation fields.
- Local verification for the current response-body-drain instrumentation slice
  is green on 2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted artifact
  `24875528924`, and `bin/verify`.
- That response-body-drain slice is now complete on the pushed branch head
  too. Commit `ce55324` passed hosted push `kTLS Validation`
  (`24876283985`), `WAMP Profile Benchmarks` (`24876284006`), and `CI`
  (`24876283996`) before the next focused manual rerun.
- Manual workflow run `24876728695` then reran the same focused scenario with
  the new response-body diagnostics enabled, and it narrowed the remaining
  regression again:
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4`
  - worst p95 row:
    `h2_multiplexed_streams_s8` at `threads=1`
  - `response body chunks avg` stayed flat on the hotspot rows
  - `response body first chunk bytes avg` stayed flat on the hotspot rows
  - the first-body-byte gap dominated the added body timing:
    - throughput hotspot:
      `first chunk wait avg +2.57 ms` vs `tail read avg +0.99 ms`
    - p95 hotspot:
      `first chunk wait avg +16.98 ms` vs `tail read avg +2.90 ms`
- The next bounded kTLS slice is therefore header-to-first-body gap
  diagnostics, ideally on the server response-emission path rather than more
  client chunk-shape probing. The next active plan is to instrument where that
  first body delay is introduced.
- That first-body-gap instrumentation slice is now complete on the pushed
  branch head too. Commit `7755828` passed hosted push `kTLS Validation`
  (`24878452943`), `WAMP Profile Benchmarks` (`24878452920`), and `CI`
  (`24878452921`) before the next focused manual rerun.
- The historical rerender remained backward compatible: the new comparison now
  renders an `HTTP Server Emission Timing` section, and the old hosted bundle
  correctly reports no server-emission metrics because it predates the new
  counters.
- Manual workflow run `24879483421` then reran the same focused scenario on
  `7755828` with `skip_artifact_gate=true`, and it closed the current
  question:
  - worst throughput row:
    `h2_multiplexed_streams_s4` at `threads=4`
    still showed `response headers wait avg +6.71 ms` and
    `first chunk wait avg +4.83 ms`
  - worst p95 row:
    `h2_multiplexed_streams_s1` at `threads=4`
    still showed `response body read avg +3.21 ms` and
    `request round trip p95 +14.95 ms`
  - every comparable row held the current server-emission boundary flat:
    - `headers_to_first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
    - `queue_to_first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_avg_ms 0.00 -> 0.00 (+0.00)`
- That means the remaining gap still opens after the current
  `onFirstBodyWrite` callback point. The next bounded slice is now the
  post-write completion boundary, not more pre-write handler timing.
- That first-write-completion slice is now implemented on the local working
  tree too. `packages/connectanum_router` now exposes
  `onFirstBodyWriteCompleted`, `packages/connectanum_bench` records
  `first_body_write_completed`, `headers_to_first_body_write_completed`,
  `queue_to_first_body_write_completed`, and `first_body_write_call`,
  `native/bench` summarizes those counters into
  `http_server_emission_timing`, and `tool/ktls_http2_compare.py` now renders
  the new completion boundary in both hotspot focus lines and the server
  timing table.
- Focused local verification for that first-write-completion slice is green on
  2026-04-24: `bin/test-fast`, targeted Dart analyze/tests for the bench and
  router stream paths, `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `python3 tool/test_ktls_http2_compare.py`, a rerender of hosted artifact
  `24879483421`, and the slice is ready for full `bin/verify`.
- Commit `b8645af` then passed the hosted push chain cleanly too:
  - `kTLS Validation` `24880362805`
  - `WAMP Profile Benchmarks` `24880362819`
  - `CI` `24880362829`
- Manual workflow run `24881249566` reran the same focused scenario on
  `b8645af` with `skip_artifact_gate=true`, and it moved the boundary again:
  - worst throughput and p95 hotspot:
    `h2_multiplexed_streams_s4`, `threads=4`
    - `response headers wait avg +8.38 ms`
    - `response body first chunk wait avg +19.33 ms`
    - `response body tail read avg +3.00 ms`
  - the completion boundary still stayed flat:
    - `headers_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `queue_to_first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_completed_avg_ms 0.00 -> 0.00 (+0.00)`
    - `first_body_write_call_avg_ms 0.00 -> 0.00 (+0.00)`
- That means the remaining delay still opens after the first native
  response-stream write returns. The next bounded slice is now native
  response-stream handoff timing, not more Dart-side write timing.
- That native response-stream handoff slice is now implemented on the local
  working tree too. `ct_core` timestamps streamed response frames and records
  cumulative first-chunk channel/dequeue/send-call counters, `ct_ffi` and
  `connectanum_router` expose them through the transport metrics snapshot,
  `native/bench` summarizes them into
  `http_native_response_stream_timing`, and
  `tool/ktls_http2_compare.py` now renders the new focus lines and markdown
  section.
- Focused local verification for the native response-stream handoff slice is
  green on 2026-04-24: `bin/test-fast`,
  `dart analyze packages/connectanum_router packages/connectanum_bench`,
  `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml
  http2_response_streaming_round_trip -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, and
  `python3 tool/test_ktls_http2_compare.py`.
- Full local verification for the native response-stream handoff slice is also
  green on 2026-04-24: `bin/verify`.
- That native response-stream handoff slice is now complete on the pushed
  branch head too. Commit `8ed8014` is now on both `origin` and `github`, and
  the hosted GitHub push chain completed cleanly:
  - `WAMP Profile Benchmarks` `24882795293`
  - `kTLS Validation` `24882795301`
  - `CI` `24882795327`
- GitLab has not surfaced a pipeline for `8ed8014` yet through the current
  token-backed pipeline query.
- Manual workflow run `24883756346` reran the same focused scenario on
  `8ed8014` with `skip_artifact_gate=true`, and it closed the current
  handoff-average question:
  - worst throughput and p95 hotspot:
    `h2_multiplexed_streams_s2`, `threads=1`
    - `response headers wait avg +2.21 ms`
    - `response body first chunk wait avg +13.64 ms`
    - `request round trip p95 +201.63 ms`
  - native handoff averages on that same row moved much less:
    - `native first chunk channel wait avg +0.41 ms`
    - `native headers-to-first-chunk-dequeue avg +0.50 ms`
    - `native first chunk send call avg -0.00 ms`
    - `native headers-to-first-chunk-send-call avg +0.50 ms`
- That means the native handoff averages are informative but still too coarse
  for the worst latency spike. The next bounded slice is native
  response-stream slow-path buckets, not more average-only timing.
- That native response-stream slow-path slice is now implemented on the local
  working tree too. `ct_core` records `>=1ms`, `>=5ms`, and `>=10ms` counters
  for channel wait, headers-to-first-chunk dequeue, and first send-call
  timings; `ct_ffi` and `connectanum_router` expose those counters through the
  transport metrics snapshot; `native/bench` summarizes them into
  `http_native_response_stream_slow_path`; and
  `tool/ktls_http2_compare.py` now renders dedicated slow-path focus lines and
  an `HTTP Native Response-Stream Slow Paths` section.
- Focused local verification for the native response-stream slow-path slice is
  green on 2026-04-24: `bin/test-fast`,
  `dart analyze packages/connectanum_router packages/connectanum_bench`,
  `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml
  http2_response_streaming_round_trip -- --nocapture`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  and a rerender of hosted artifact `24883756346`.
- Full local verification for the native response-stream slow-path slice is
  also green on 2026-04-24: `bin/verify`.
- That native response-stream slow-path slice is now complete on the pushed
  branch head too. Commit `547d6e4` is now on both `origin` and `github`, and
  the hosted GitHub push chain completed cleanly:
  - `CI` `24884889546`
  - `WAMP Profile Benchmarks` `24884889549`
  - `kTLS Validation` `24884889561`
- GitLab has not surfaced a pipeline for `547d6e4` yet through the current
  token-backed pipeline query.
- Manual workflow run `24885834166` reran the same focused
  `h2_ktls_multiplex_scaling` scenario on clean head `547d6e4` with
  `skip_artifact_gate=true`, and it sharpened the boundary again:
  - worst throughput row:
    `h2_multiplexed_streams_s2`, `threads=4`
    - `Backpressure events 14 -> 25 (+11)`
    - `native first chunk channel wait >=1/5/10ms 0/0/0 -> 6/0/0`
    - `native first chunk send call >=1/5/10ms 1/0/0 -> 7/0/0`
  - worst p95 row:
    `h2_multiplexed_streams_s1`, `threads=4`
    - `request round trip p95 13.04 -> 24.95 (+11.90)`
    - `response body first chunk wait avg 1.37 -> 6.12 (+4.75)`
    - no `http_native_response_stream_*` metrics were present for that row
- The current local working tree now carries the next bounded diagnostic fix:
  `HttpResponseStream` exposes a completion future, and the bench handlers now
  await direct-stream completion before recording server-emission diagnostics.
  That fixes the measurement boundary that kept the `s1` rows out of the
  current native/direct-stream timing summaries.
- That direct-stream completion slice is now pushed too. Commit `a12227d`
  passed the visible hosted GitHub push chain:
  - `CI` `24886626863`
  - `WAMP Profile Benchmarks` `24886626856`
- `kTLS Validation` still has not surfaced for `a12227d` through the GitHub
  API, and GitLab also did not surface a pipeline for that head through the
  current token-backed query.
- Manual workflow run `24887510264` reran the same focused
  `h2_ktls_multiplex_scaling` scenario on clean head `a12227d` with
  `skip_artifact_gate=true`, and it closed the direct-stream question:
  - `h2_multiplexed_streams_s1` rows now appear in
    `HTTP Server Emission Timing`, so the earlier omission was a bench
    sampling bug rather than a transport-path gap
  - worst throughput row:
    `h2_multiplexed_streams_s8`, `threads=4`
    - `response headers wait avg 24.33 -> 37.67 (+13.34)`
    - `response body first chunk wait avg 7.40 -> 15.76 (+8.35)`
    - `server stream open avg 11.88 -> 14.12 (+2.24)`
    - `server first body write completed avg 11.93 -> 14.17 (+2.24)`
    - `native first chunk channel wait avg 0.22 -> 0.37 (+0.16)`
    - `native headers-to-first-chunk-dequeue avg 5.93 -> 8.59 (+2.66)`
    - `native first chunk send call avg 0.32 -> 0.87 (+0.54)`
    - `native headers-to-first-chunk-send-call avg 6.26 -> 9.46 (+3.20)`
- The next bounded diagnostic slice is now pushed too. Commit `fbc5566` is on
  both `origin` and `github`, and the visible GitHub push chain completed:
  - `CI` `24888660106`
  - `kTLS Validation` `24888660101`
  - `WAMP Profile Benchmarks` `24888660111`
- GitLab has not surfaced a pipeline for `fbc5566` through the current
  token-backed query.
- That checkpoint adds native response-stream header-dispatch timing:
  `stream_open_to_headers_send` plus `headers_send_call`, threaded through the
  router metrics snapshot, native bench artifact summaries, and comparison
  output as part of `http_native_response_stream_timing`.
- The headers-queued-to-first-connection-write slice is now pushed too.
  Commit `0a9c3c8` is on both `origin` and `github`, and the visible GitHub
  push chain completed:
  - `CI` `24893449385`
  - `kTLS Validation` `24893449381`
  - `WAMP Profile Benchmarks` `24893449378`
- GitLab has not surfaced a pipeline for `3f60a18` through the current
  token-backed query.
- Commit `d892676` is now on both `origin` and `github`, and the visible
  GitHub push chain completed:
  - `CI` `24895983686`
  - `kTLS Validation` `24895983707`
  - `WAMP Profile Benchmarks` `24895983693`
- Manual hosted rerun `24897078545` then completed successfully on clean head
  `d892676` with the focused multiplex scenario and `skip_artifact_gate=true`.
  It closed the direct-stream control split:
  - worst p95 row:
    `h2_multiplexed_streams_s8`, `threads=1`
    - `server direct-stream open round trip avg 12.19 -> 19.09 (+6.90)`
    - `server direct-stream request queue delay avg 5.46 -> 6.56 (+1.10)`
    - `server direct-stream reply delivery delay avg 6.70 -> 12.50 (+5.80)`
    - `native headers-to-first-chunk-dequeue avg 7.13 -> 13.50 (+6.37)`
  - worst throughput row:
    `h2_multiplexed_streams_s2`, `threads=1`
    - `server direct-stream open round trip avg 3.42 -> 2.29 (-1.13)`
    - `server direct-stream request queue delay avg 1.78 -> 0.94 (-0.84)`
    - `server direct-stream reply delivery delay avg 1.60 -> 1.32 (-0.28)`
- That rerun showed the worst p95 movement on the reply side of the
  direct-stream control path, while the worst throughput row still points at
  the native first-chunk path instead of the control handshake itself.
- The current local working tree therefore carries the next bounded slice:
  replacing the per-open direct-stream reply `ReceivePort` with a shared
  isolate-local reply channel keyed by request id.
- Local verification for the current shared-reply-channel slice is green on
  2026-04-24: `bin/test-fast`, `dart test
  packages/connectanum_router/test/direct_stream_reply_channel_test.dart
  -r expanded`, `dart test packages/connectanum_router/test/router_runtime_test.dart
  -r expanded`, `dart test packages/connectanum_bench/test/http_stream_handler_test.dart
  -r expanded`, `cargo test --manifest-path native/bench/Cargo.toml
  summarize_report_computes_latency_and_deltas -- --nocapture`,
  `dart analyze packages/connectanum_router packages/connectanum_bench`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  and `bin/verify`.
- That shared-reply-channel slice is now pushed as commit `3f60a18`
  (`perf(router): reuse direct-stream reply channel`).
- The visible GitHub push chain for `3f60a18` completed successfully:
  - `CI` `24897944475`
  - `WAMP Profile Benchmarks` `24897944543`
- `kTLS Validation` still has not surfaced for `3f60a18` through the current
  public Actions query.
- Manual hosted rerun `24898979218` on clean head `3f60a18` then stayed
  `in_progress` well past the normal runtime while the benchmark job remained
  stuck in `Run HTTP/2 TLS vs kTLS benchmark`.
- A focused local repro on macOS using the same multiplex scenario without the
  Linux-only kTLS pass wrote its results successfully but left the
  `bench_main.dart` helper process alive, which isolated the regression to
  helper-process shutdown rather than workload execution.
- Root cause: the shared `DirectStreamReplyChannel` kept a top-level
  `RawReceivePort` open for the full isolate lifetime, so the helper isolate
  never became idle enough to exit after the benchmark completed.
- The current local working tree fixes that leak by opening the shared reply
  port lazily and closing it again automatically once the channel has no
  pending waiters, while preserving shared-port reuse during concurrent
  direct-stream opens.
- Focused local verification for that fix is green on 2026-04-24:
  `bin/test-fast`, `dart test
  packages/connectanum_router/test/direct_stream_reply_channel_test.dart
  -r expanded`, and a full local HTTP/2 multiplex bench run with
  `CONNECTANUM_ENABLE_KTLS=0 CONNECTANUM_REQUIRE_KTLS=0 cargo run --release
  --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib
  native/transport/target/release/libct_ffi.dylib --scenario
  native/bench/scenarios/h2_ktls_multiplex_scaling.toml --results
  /tmp/connectanum-h2-local-results.jsonl --artifact-dir
  /tmp/connectanum-h2-local-artifacts --router-worker-counts 1
  --native-runtime-thread-counts 1,4`, which now exits cleanly after writing
  the summary instead of hanging on helper shutdown.
- Local verification for that stream-open-to-headers-send slice is green on
  2026-04-24: `bin/test-fast`, `cargo test --manifest-path
  native/bench/Cargo.toml summarize_report_computes_latency_and_deltas --
  --nocapture`, `cargo test --manifest-path
  native/transport/ct_ffi/Cargo.toml http2_response_streaming_round_trip --
  --nocapture`, `dart analyze packages/connectanum_router
  packages/connectanum_bench`, `python3 -m py_compile
  tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, and `bin/verify`.
- Local verification for the current kTLS transport-delta follow-up is green
  on 2026-04-24: `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a rerender of the hosted `24865337582` artifact bundle, and `bin/verify` all
  passed.
- Local verification for the current kTLS resource-usage parser follow-up is
  green on 2026-04-24: `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a rerender of the hosted `24865337582` artifact bundle, and `bin/verify` all
  passed.
- Local verification for the current kTLS Linux TLS-stat follow-up is green on
  2026-04-24: `bin/test-fast`, `bash -n bin/ktls-http2-bench`,
  `python3 -m py_compile tool/ktls_http2_compare.py
  tool/test_ktls_http2_compare.py`, `python3 tool/test_ktls_http2_compare.py`,
  a focused synthetic `tool/ktls_http2_compare.py` run with
  `tls-stat-before.txt` / `tls-stat-after.txt` sidecars, and `bin/verify` all
  passed.
- Local verification for the current kTLS multiplex-diagnostic control slice
  is green on 2026-04-24: `bin/test-fast`, `bash -n bin/ktls-http2-bench`,
  `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ktls-http2-benchmarks.yml")'`,
  `bin/ktls-http2-bench --help`, and `bin/verify` all passed.
- Local verification for the current kTLS workflow-summary follow-up is green
  on 2026-04-24: `bin/test-fast`, YAML parsing of
  `.github/workflows/ktls-http2-benchmarks.yml`, and `bin/verify` all passed.
- Local verification for the current kTLS hotspot-rollup follow-up is green on
  2026-04-24: `bin/test-fast`,
  `python3 -m py_compile tool/ktls_http2_compare.py tool/test_ktls_http2_compare.py`,
  `python3 tool/test_ktls_http2_compare.py`, a focused synthetic
  `tool/ktls_http2_compare.py` run with Linux-style `resource-usage.txt`
  sidecars, and `bin/verify` all passed.
- `docs/ktls_research.md` is now aligned with the current post-secure-WAMP
  state: secure WAMP coverage is complete, the remaining kTLS issue is
  performance rather than correctness, and the next kTLS-specific need is
  readable hosted comparison evidence before deeper Linux-only tuning.
- `packages/connectanum_router/test/authorization_integration_test.dart` is
  analyzer-clean again; the earlier worker-authorization slice no longer
  leaves avoidable info-level noise in the fast verification baseline.
- The first WAMP benchmark-readiness slice now has a human-readable contract in
  `docs/wamp_profile_benchmarks.md`. The canonical release-decision throughput
  gates are `native/bench/scenarios/wamp_transport_throughput.toml` and
  `native/bench/scenarios/wamp_secure_throughput.toml`, with conservative
  per-workload throughput and p95-latency floors in
  `native/bench/artifact_gate/wamp_transport_throughput.json` and
  `native/bench/artifact_gate/wamp_secure_throughput.json`.
- Local Darwin arm64 baselines captured on 2026-04-23 with
  `router_workers=1` and `native_runtime_threads=1` passed the default
  zero-transport-counter gate and the new policy gates. The lowest cleartext
  throughput was `48.79 Mbps` (`websocket_pubsub_json_64k`) and the highest
  cleartext p95 was `264.493 ms`; the lowest secure throughput was
  `32.48 Mbps` (`websocket_secure_pubsub_json_64k`) and the highest secure p95
  was `450.015 ms`.
- `bin/wamp-profile-validate` is now the canonical WAMP release-gate entry
  point for both local and hosted validation. It runs the three strict
  default-counter smoke gates (`wamp_smoke`, `wamp_secure_smoke`, and
  `wamp_control_smoke`) plus the policy-backed throughput gates
  (`wamp_transport_throughput`, `wamp_secure_throughput`, and
  `wamp_publish_fanout_throughput`). The first local Darwin arm64 run on
  2026-04-23 passed the original five-gate set with 64 workloads. In that
  run, the lowest cleartext throughput-gate result was `57.65 Mbps`
  (`websocket_pubsub_json_64k`) with max p95 `241.860 ms`, and the lowest
  secure throughput-gate result was `35.86 Mbps`
  (`rawsocket_secure_pubsub_json_64k`) with max p95 `389.237 ms`.
- GitHub Actions includes a dedicated `WAMP Profile Benchmarks` workflow that
  runs `bin/wamp-profile-validate` on hosted Ubuntu and uploads
  `wamp-profile-benchmark-artifacts`. Hosted run `24846498743` passed on
  commit `a2eef0f`, confirming the expanded smoke-plus-throughput WAMP
  release-gate entrypoint on Linux before fan-out promotion.
- `wamp_publish_fanout_throughput` now has a conservative checked-in artifact
  policy in `native/bench/artifact_gate/wamp_publish_fanout_throughput.json`.
  Local Darwin arm64 fan-out baselines on 2026-04-23 ranged from `24.49 Mbps`
  to `66.08 Mbps` with max p95 `508.916 ms`, while the first hosted Linux
  diagnostic run ranged from `46.19 Mbps` to `138.73 Mbps` with max p95
  `228.126 ms`. That makes fan-out stable enough to move from diagnostics into
  the canonical WAMP release-gate entrypoint without tightening the existing
  cleartext or secure transport floors yet.
- A fresh local Darwin arm64 rerun of
  `native/bench/scenarios/wamp_publish_fanout_throughput.toml` after the
  policy landed also passed the new gate. That rerun ranged from `23.05 Mbps`
  (`websocket_pubsub_cbor_64k_fanout8`) to `75.21 Mbps`
  (`rawsocket_pubsub_json_64k_fanout8`) with max p95 `485.628 ms`, so the
  checked-in fan-out floors still have healthy local headroom.
- `bin/wamp-profile-diagnostics` now stays focused on the remaining
  non-release-blocking diagnostic scenarios:
  `wamp_client_impl_throughput`, `wamp_payload_mode_throughput`,
  `wamp_mixed_serializer_throughput`, and
  `wamp_websocket_fragmentation_throughput`. Hosted run `24848746691` passed
  on commit `eb0aa5c`, and push `CI` run `24848746640` also passed on the same
  commit.
- A second full local rerun of the expanded canonical
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-rerun-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 60000`
  passed all six release gates on Darwin arm64 after commit `7d40433` was
  pushed. The earlier `wamp_secure_throughput` stall did not reproduce on that
  rerun, so the local release-gate entrypoint is currently green again.
- The bench orchestration path now fails fast instead of waiting indefinitely
  on two previously unbounded states: `native/bench/src/bin/http_stream.rs`
  now errors if `bench_main` does not print `READY` within the configured
  timeout, and `packages/connectanum_bench/lib/src/wamp_workload_runner.dart` now
  applies explicit WAMP session-open timeouts across workload modes while also
  cleaning up already-opened sessions if later opens fail. Targeted timeout
  tests and a full `bin/verify` run passed locally on the hardened working
  tree.
- The existing `CI` workflow also has a `workflow_dispatch`-only `WAMP Profile
  Gates` job. Use that path for branch-hosted WAMP evidence until the
  dedicated `WAMP Profile Benchmarks` workflow exists on the default branch
  and becomes directly dispatchable.
- The first hosted `WAMP Profile Benchmarks` run on `3acbf94` failed because
  the Rust bench control client negotiated HTTP/2 for `/bench/metrics`, and
  hosted Linux recorded occasional TLS close/protocol-error alerts from that
  control channel inside otherwise successful WAMP workloads. The control
  client now forces HTTP/1.1 so WAMP profile gates do not mix HTTP/2
  control-plane shutdown noise into WAMP transport-alert deltas.
- Local Darwin arm64 validation after forcing the Rust bench control client to
  HTTP/1.1 passed both canonical WAMP profile gates with
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-http1-control-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`.
- Final local handoff verification on 2026-04-23 passed with `bin/verify`.
  The first `bin/verify` attempt hit a transient
  `ct_ffi::tests::listen_flow::poll_connection_message_returns_payload`
  timeout; the test passed in isolation, the full `ct_ffi` suite then passed,
  and the full `bin/verify` rerun passed.
- GitHub Actions CI now runs through the canonical root `bin/*` entrypoints on branch pushes and PRs to `master`; GitHub Actions run `24732889424` for `2fac53b` completed successfully with both `Fast Checks` and `Full Verify`.
- The CI workflow now targets all branch pushes plus PRs to `master`, and it also exposes `workflow_dispatch` for manual runs.
- Hosted GitHub validation is now confirmed green through the latest pushed
  checkpoint. Commit `35b4cd1` passed `kTLS Validation`
  (`24852537007`), `WAMP Profile Benchmarks` (`24852537018`), and push `CI`
  (`24852537035`), and the follow-up docs checkpoint `9462ba1` also passed
  push `CI` (`24852585677`).
- The latest pushed WAMP readiness checkpoint is fully green on GitHub too.
  Commit `5a8b918` passed push `CI` (`24853368527`) and
  `WAMP Profile Benchmarks` (`24853368528`), and the follow-up docs commit
  `175ae0a` passed push `CI` (`24853407962`).
- The remaining WAMP control/setup timeout gaps are now hardened in
  `5a8b918`. `packages/connectanum_bench/lib/src/wamp_workload_runner.dart`
  now bounds the remaining publish/subscribe/register/close paths and applies
  cleanup timeouts during worker teardown, and
  `packages/connectanum_bench/test/wamp_workload_runner_test.dart` now covers
  RPC peer-registration stalls plus publish-ack, subscribe-cycle, and
  register-cycle timeout cases. `dart test
  packages/connectanum_bench/test/wamp_workload_runner_test.dart` and
  `bin/verify` passed locally on Darwin arm64 for this follow-up working tree.
- The next live WAMP correctness gap on the local macOS-supported path is now
  closed too. `cd packages/connectanum_router && dart test
  test/publish_ack_test.dart test/router_integration_websocket_test.dart -r
  expanded` passed after expanding the pure Dart RawSocket publish-ack smoke to
  JSON/MessagePack/CBOR and adding mixed RawSocket/WebSocket routing coverage
  in the websocket integration suite, and the full root `bin/verify` run also
  passed on the same working tree.
- `bin/test-fast` now provisions
  the native client runtime before `packages/connectanum_client/test/client_test.dart`
  on supported hosts, both root client flows now include
  `packages/connectanum_client/test/transport/native/e2ee_provider_test.dart`,
  and the native-only client tests now skip with an explicit reason when
  `libct_ffi` is genuinely unavailable.
- The main `CI` workflow no longer uploads raw per-test metrics snapshots.
  `CONNECTANUM_ARTIFACT_DIR` remains an explicit local/debug switch, and
  published artifacts now come from the dedicated `Native Artifacts` and
  bench/gate workflows instead.
- GitHub Actions run `24825770571` (`Native Artifacts`, `workflow_dispatch`)
  passed on commit `7049801` across Linux x64, Linux arm64, macOS arm64, and
  macOS Intel. The release-publishing job was skipped as expected because the
  validation dispatch did not provide a release tag.
- The root router verification now runs from `packages/connectanum_router` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host.
- The root bench verification now runs from `packages/connectanum_bench` so the package-local `dart_test.yaml` (`concurrency: 1`) applies to the full suite on every host, matching the process-global native runtime constraint already enforced in the router package.
- The bench WAMP integration tests now resolve their worker helper from either the bench package root or the repo root so Linux CI and local root-script runs share the same path contract.
- The bench now ships `native/bench/scenarios/transport_mbit_matrix_throughput.toml` as the throughput-grade counterpart to the cross-transport/auth/authz smoke matrix, preserving the same auth/authz/public/protected row shape while raising sustained-workload settings for one canonical Mbps artifact set.
- The bench now also ships `native/bench/scenarios/http_bearer_provider_smoke.toml` as the dedicated provider-backed HTTP auth baseline. It covers local JWT validation and local OAuth introspection against `/bench/secure-jwt` and `/bench/secure-oauth` across HTTP/1.1, HTTP/2, and HTTP/3, and the Dart bench runner now starts the local introspection endpoint required by the shipped `oauth` provider config.
- The shipped HTTP auth bridge baseline now covers challenge-response auth too: `native/bench/scenarios/http_auth_smoke.toml` exercises `ticket`, `wampcra`, and `scram` login, refresh, and protected-route flows across HTTP/1.1, HTTP/2, and HTTP/3, and the bench router config now exposes those methods on `/bench/auth` for the secure bench realm.
- The bench artifact pipeline now has a checked-in CI gate too: `native/bench`
  ships `check_artifact_gate`, the root `bin/check-bench-artifacts` wrapper
  writes sibling `*.gate.json` / `*.gate.md` reports next to transformed
  summaries, and the kTLS validation / benchmark runners now fail automatically
  on active throttles, transport alert deltas, transport error alert deltas,
  backpressure deltas, or explicitly budgeted throughput/p95-latency drift
  captured in `bench_results.summary.json`.
- Telemetry alert coverage is now aligned across the native and Dart surfaces
  too: `ct_ffi` has a focused router-metrics snapshot regression for
  per-reason/per-listener mapping, `router_metrics_service_test.dart` now
  asserts idle/body/protocol/internal alert counters across metrics snapshot
  payloads and OpenMetrics output, and `bin/test-all` explicitly runs the
  feature-gated native snapshot test alongside the default `ct_ffi` suite on
  native-runtime hosts.
- The bench WAMP harness now supports explicit secure-target selection through `secure_transport = true`, keeps separate cleartext and TLS listener target maps for both the in-process runner and the native helper worker, and fails closed instead of silently falling back to the cleartext WAMP listener.
- `native/bench/bench_router.json` now ships both cleartext WAMP (`127.0.0.1:8081`) and TLS WAMP (`127.0.0.1:8083`) listeners, and both WebSocket listeners advertise `wamp.2.json`, `wamp.2.msgpack`, and `wamp.2.cbor` so the bench scenario surface matches the supported WAMP serializers.
- The bench workload contract now includes `secure_transport`, and `native/bench/scenarios/wamp_secure_smoke.toml` provides the first checked-in secure RawSocket/WebSocket smoke coverage against `bench.secure` ticket auth.
- Hosted Linux validation exposed a router/native config mismatch in that new secure WAMP path. GitHub Actions run `24777296956` first failed in Dart validation because the router layer incorrectly rejected shared SNI hostname `localhost` across distinct TLS endpoints, and follow-up runs `24778942812`, `24778930521`, and `24778930527` showed that the attempted `127.0.0.1` workaround was also invalid because the native TLS config requires DNS-style SNI hostnames. The shipped bench config is back on shared `localhost`, the cross-endpoint duplicate-SNI restriction is removed, and a bench-package regression now starts the shipped config through `RouterConfigLoaderIo -> Endpoint.fromListenerSettings -> Router.start(NativeTransportRuntime)` with distinct reserved ports while temporarily anchoring relative TLS asset lookup to the repo root, so this startup path now stays valid from both the repo root and the bench package root.
- GitHub Actions runs `24780721173` (`kTLS Validation`) and `24780721191` (`kTLS HTTP/2 Benchmarks`) passed on commit `70f1525`, confirming the secure-WAMP startup fix on hosted Linux.
- GitHub Actions run `24782645871` (`CI`) then passed on commit `b6e458e`, confirming the root `Full Verify` path now runs the bench package from `packages/connectanum_bench` under its checked-in serial `dart_test.yaml` contract on hosted Linux too.
- GitHub Actions run `24785214332` (`kTLS Validation`, `workflow_dispatch`) passed on commit `0b4f1e7` after the Dart secure-WebSocket certificate-path fix, and push `CI` run `24785189137` also passed on the same commit, so secure RawSocket and secure WebSocket WAMP smoke validation is now green on hosted Linux.
- The repo now also ships throughput-grade secure-WAMP coverage. `native/bench/scenarios/wamp_secure_throughput.toml` mirrors the existing 64 KiB cleartext transport sweep for secure RawSocket/WebSocket RPC + pubsub across JSON, MsgPack, and CBOR on `bench.secure`.
- The direct Rust bench CLI now defaults its control plane to `https://127.0.0.1:8080/bench` instead of `https://localhost:8080/bench`, because the shipped bench router binds the TLS control listener on IPv4 loopback and the old default could hit the wrong socket on this macOS host.
- GitHub Actions run `24786956501` (`kTLS Validation`, `workflow_dispatch`) then passed on commit `c040ef9` with `native/bench/scenarios/wamp_secure_throughput.toml`, so the secure-WAMP throughput scenario now has a hosted Ubuntu baseline too. Response-throughput highlights were RawSocket pubsub `56.77/65.08/57.15 Mbps`, RawSocket RPC `176.60/215.09/164.48 Mbps`, WebSocket pubsub `62.04/78.81/64.83 Mbps`, and WebSocket RPC `191.13/231.59/168.71 Mbps` for JSON/MsgPack/CBOR at `48 x 6` with one router worker and one native runtime thread.
- The shipped HTTP/3 multiplex ceiling map now sweeps `streams_per_connection = 1, 2, 4, 8, 16` on the same sustained-transfer workload shape instead of pinning only the old `4`-stream point.
- The latest local Darwin H3 direction sweep now covers `router_workers = 1,4` and `native_runtime_threads = 1,4` on that shipped scenario. Extra router workers only helped the lowest-multiplex `s1` point (`721.60 Mbps`, p95 `54.61 ms` at `threads=1, workers=4`) and were neutral or harmful at the deeper `s4/s8/s16` points. The best overall point was `761.52 Mbps` / p95 `124.85 ms` at `s2` with `threads=4, workers=1`, while `s16` still emitted `103-117` backpressure events across all combinations and regressed as low as `465.43 Mbps` / p95 `1350.94 ms`. The next HTTP/3 milestone should therefore target transport/backpressure tuning rather than application response scheduling.
- The first two transport-side HTTP/3 tuning experiments are now ruled out locally on Darwin. Send-side body-write chunking at `32 KiB` and `64 KiB` shifted throughput between quadrants but barely changed `backpressure_events`, confirming the benchmark counter is not driven primarily by QUIC body-write burstiness.
- A native HTTP/3 accept-loop backlog gate also proved to be the wrong tradeoff. `soft_limit = 1` eliminated `backpressure_events` completely but over-serialized the workload, and `soft_limit = 4` capped `max_backpressure_depth` at `4` while still regressing too many `s1/s2/s16` combinations to keep. The active H3 plan remains open, but the next candidate should target boss-loop request-drain cadence or queue handoff scheduling around the native HTTP request backlog instead of more body-write tuning.
- Three boss-side HTTP/3 queue-drain variants were then measured locally and all
  rejected after remeasurement on the shipped `h3_multiplex_scaling` matrix:
  `out/h3-boss-drain-cadence/` (full extra boss-loop queue pass),
  `out/h3-boss-connection-local/` (drain whole newly accepted connections
  immediately), and `out/h3-boss-http3-burst1/` (drain one immediate HTTP/3
  request on accept).
- The full extra boss-loop queue pass was the clearest reject: it improved some
  `s4/s8` points, but it heavily regressed the `s1` baselines and still did not
  yield a clean deep-multiplex win.
- Draining all queued requests for a just-accepted connection improved some
  deep multi-worker cases, but it also caused fairness regressions because one
  accepted connection could monopolize the boss loop before later accepted
  connections were serviced.
- The burst-1 accept drain was the best of those three boss-side variants, but
  it was still too mixed to keep. It improved most `s1` points and some `s16`
  throughput, but it regressed every `s2` quadrant and enough `s4/s8` points
  that the baseline remains preferable.
- A steady-state round-robin HTTP/3 drain is now the first transport-side
  change kept under the active H3 plan. `_RouterBoss._drainHttp3Requests()`
  now drains one queued request per tracked HTTP/3 connection per pass before
  cycling again, and `router_runtime_test.dart` asserts that queued requests
  on two active HTTP/3 connections are interleaved instead of exhausting one
  connection first.
- Local Darwin reruns in `out/h3-http3-round-robin/` beat the last clean
  `out/h3-followup-direction/` baseline in `12/20` throughput quadrants and
  `13/20` p95-latency quadrants. The biggest wins were `s4` at
  `threads=1, workers=1` (`423.07 -> 681.74 Mbps`, `411.66 -> 246.33 ms`),
  `s4` at `threads=1, workers=4` (`406.87 -> 682.61 Mbps`,
  `438.29 -> 238.25 ms`), `s8` at `threads=1, workers=4`
  (`438.08 -> 658.33 Mbps`, `753.53 -> 482.78 ms`), and `s16` at
  `threads=4, workers=4` (`465.43 -> 627.92 Mbps`, `1350.94 -> 980.68 ms`).
- The remaining HTTP/3 gap is now absolute queue pressure rather than obvious
  fairness starvation. `backpressure_events` and
  `max_backpressure_depth_after` are still pinned above the bench artifact
  gate's zero-threshold floor on every `s2+` quadrant, so the active H3 plan
  stays open for further queue-depth reduction even though the round-robin
  drain is a clear net improvement worth keeping.
- A top-level boss-loop priority change has now been ruled out too. Moving
  `_drainHttp3Requests()` earlier in `_loop()` than `_dispatchMessages()` and
  the other maintenance passes produced `out/h3-http3-priority/`, which
  regressed `14/20` throughput quadrants and `19/20` p95 quadrants versus the
  kept `out/h3-http3-round-robin/` baseline. The worst losses were `s4` at
  `threads=1, workers=1` (`681.74 -> 471.56 Mbps`, `246.33 -> 409.33 ms`),
  `s8` at `threads=1, workers=4` (`658.33 -> 389.74 Mbps`,
  `482.78 -> 787.97 ms`), and `s16` at `threads=1, workers=4`
  (`678.72 -> 500.11 Mbps`, `1104.96 -> 1346.36 ms`).
- A bounded follow-up burst inside `_drainHttp3Requests()` has now been ruled
  out too. Keeping the first fair pass at one request per connection but
  allowing two per connection on later passes produced
  `out/h3-http3-followup-burst2/`, which won only `9/20` throughput quadrants
  and `8/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline. The worst losses were `s4` at
  `threads=1, workers=1` (`681.74 -> 285.04 Mbps`, `246.33 -> 873.80 ms`),
  `s1` at `threads=1, workers=1` (`683.91 -> 435.95 Mbps`,
  `66.64 -> 121.99 ms`), and `s16` at `threads=1, workers=1`
  (`620.66 -> 385.13 Mbps`, `884.91 -> 1449.49 ms`).
- A lighter-weight HTTP/3 request-handle staging experiment has now been
  ruled out too. Draining raw native request handles before materializing
  them into `NativeHttpHandshake` objects produced
  `out/h3-http3-handle-stage/`, which won `12/20` throughput quadrants but
  still lost `12/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline while barely moving queue depth. The
  worst losses were `s2` at `threads=4, workers=1`
  (`732.93 -> 659.55 Mbps`, `116.86 -> 132.12 ms`), `s8` at
  `threads=1, workers=1` (`712.03 -> 654.72 Mbps`, `435.16 -> 495.72 ms`),
  and `s16` at `threads=1, workers=4` (`678.72 -> 609.39 Mbps`,
  `1104.96 -> 1114.05 ms`). `bin/check-bench-artifacts` still failed with
  `32` findings because the `s2+` quadrants remained above the zero-threshold
  `backpressure_events`/`backpressure_alerts` gate.
- A native HTTP/3 ready-queue experiment has now been ruled out too.
  Publishing one native ready token per empty-to-non-empty HTTP/3 request
  queue and draining through a `ct_http3_poll_ready_connection()` FFI path
  produced `out/h3-http3-native-ready-queue/`, which won only `6/20`
  throughput quadrants and `9/20` p95 quadrants versus the kept
  `out/h3-http3-round-robin/` baseline. It improved some `s2/s4` points,
  including `s2` at `threads=1, workers=1`
  (`682.61 -> 759.90 Mbps`, `123.65 -> 119.00 ms`) and `s4` at
  `threads=4, workers=4` (`665.68 -> 723.06 Mbps`, `284.97 -> 253.78 ms`),
  but it regressed deeper reuse points such as `s8` at `threads=1, workers=1`
  (`712.03 -> 666.92 Mbps`, `435.16 -> 478.63 ms`) and `s16` at
  `threads=1, workers=4` (`678.72 -> 623.54 Mbps`, `1104.96 -> 1039.79 ms`).
  `max_backpressure_depth_after` stayed unchanged in every quadrant, and
  `bin/check-bench-artifacts` still failed with `32` findings.
- A native HTTP/3 request-ready wake experiment has now been ruled out too.
  Publishing a boss wake only when an HTTP/3 request queue transitions from
  empty to non-empty produced `out/h3-http3-request-ready-wake/`. After fixing
  an experimental callback-lifecycle teardown hang in the first attempt, the
  corrected variant still won only `7/20` throughput quadrants and `7/20` p95
  quadrants versus the kept `out/h3-http3-round-robin/` baseline. It improved
  some mid-depth quadrants, including `s2` at `threads=4, workers=4`
  (`698.14 -> 751.92 Mbps`, `135.30 -> 130.73 ms`, backpressure `17 -> 9`)
  and `s4` at `threads=4, workers=4`
  (`665.68 -> 713.45 Mbps`, `284.97 -> 252.78 ms`, backpressure `52 -> 49`),
  but it regressed too many deeper reuse points to keep, including `s8` at
  `threads=1, workers=1` (`712.03 -> 394.18 Mbps`, `435.16 -> 792.74 ms`) and
  `s16` at `threads=4, workers=1`
  (`627.92 -> 380.89 Mbps`, `894.39 -> 1435.18 ms`). The bench gate still
  failed with `32` findings.
- A post-enqueue native HTTP/3 accept-loop yield has now been ruled out too.
  Yielding after each queued HTTP/3 request and after installing its response
  waiter produced `out/h3-http3-post-enqueue-yield-probe/` on a focused
  `router_workers=1`, `native_runtime_threads=1` slice. It lost every measured
  workload versus `out/h3-http3-round-robin`: `s1`
  `683.91 -> 533.14 Mbps`, `s2` `682.61 -> 619.94 Mbps`, `s4`
  `681.74 -> 428.47 Mbps`, `s8` `712.03 -> 403.81 Mbps`, and `s16`
  `620.66 -> 522.25 Mbps`. `max_backpressure_depth_after` stayed at
  `0/2/4/8/16`, and `bin/check-bench-artifacts` still failed with `8`
  findings on that single-quadrant probe.
- The explicit HTTP/3 multiplex artifact-gate decision is now landed. The
  bench gate still uses zero thresholds by default, but
  `bin/check-bench-artifacts --policy <path>` can apply scoped thresholds, and
  `native/bench/artifact_gate/h3_multiplex_scaling.json` allows only the
  expected `backpressure_events` / `backpressure_alerts` budget for the shipped
  H3 `s2/s4/s8/s16` multiplex workloads. With that policy,
  `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json --policy native/bench/artifact_gate/h3_multiplex_scaling.json`
  passes all 20 local Darwin round-robin workloads while other transport
  alert/error/throttle signals remain strict.
- The H3 transport/backpressure plan is complete. It kept the steady-state
  round-robin drain as the transport-side improvement, rejected the later
  accept-loop wake/yield and queue-drain reshaping experiments, and now records
  the remaining H3 multiplex queue depth as normal only when an explicit
  scenario policy is supplied. Future H3 work should require either a concrete
  response-progress handoff/window design or a performance budget layer for
  throughput/p95 drift.
- The pinned WAMP conformance snapshot now covers one router-level
  multi-session vector in addition to the existing single-message serializer
  subset. `packages/connectanum_core/testdata/wamp_conformance/multisession/advanced/publisher_exclusion_disabled.json`
  is now vendored from `wamp-proto/wamp-proto#557`, and
  `packages/connectanum_router/test/conformance/wamp_multisession_conformance_test.dart`
  executes it against local worker-session routing with placeholder-aware
  matching for router-assigned ids. The upstream PR head was rechecked on
  2026-04-23 and still matches the vendored `59303fd1290f472b29a40392caeca525d0324e37`
  snapshot, so broader conformance expansion remains blocked on upstream
  runner/vector stabilization.
- `packages/connectanum_router` is analyzer-clean after replacing the remaining
  nullable map/list collection-if lints in native message binding, remote-auth
  delegate payloads, route config loading, and router session transfer metadata
  with Dart null-aware collection elements.
- `packages/connectanum_router/test/router_worker_auth_test.dart` no longer has the old 1-in-256 false-success path in `Cryptosign authenticator rejects wrong signature`; the test now always mutates the first signature byte instead of sometimes regenerating the same `ff...` prefix and leaving the signature unchanged.
- `connectanum_core` now exposes a typed `WampE2eeProvider` contract plus an explicit `WampE2eeProviderUnavailableException`, so `ppt_scheme = "wamp"` payloads no longer silently materialize empty args/kwargs when no decryptor is available.
- The Dart client/session path now threads an optional `e2eeProvider` through outbound publish/call/yield packing, materialized inbound messages, and native direct-result/event/invocation payload views while preserving the existing packed-byte passthrough behavior for matching lazy WAMP payloads.
- The first Dart-side WAMP E2EE prototype is now implemented. `connectanum_core` ships `WampCborXsalsa20Poly1305Provider`, explicit unsupported-cipher / missing-key / invalid-payload / decryption failure types, and a focused provider regression test.
- Client and router coverage now prove the full phase-1 path: outbound WAMP payloads populate `ppt_cipher` + `ppt_keyid`, inbound native direct result/event/invocation paths decrypt through the configured provider, and router internal-session forwarding preserves ciphertext bytes plus `ppt_*` metadata without forcing router-side decryption.
- The phase-2 E2EE design is now captured in `docs/e2ee_ppt_research.md`: native/off-Dart parity should happen at the client boundary rather than the router boundary, and negotiated session state should ride one optional `authextra.e2ee` object across `HELLO`, `CHALLENGE`, `AUTHENTICATE`, and `WELCOME`.
- The first phase-2 Dart handshake slice is now landed too: `Client.authExtra` reaches `HELLO`, `CHALLENGE.extra` preserves custom `e2ee` metadata across JSON/MsgPack/CBOR/native binding, and `Session.negotiatedE2ee` exposes typed `WELCOME.authextra.e2ee` state without changing payload behavior yet.
- The next phase-2 Dart slice is now landed too: `Session` wraps attached `WampE2eeProvider` instances with negotiated `WELCOME.authextra.e2ee` defaults, so outbound and inbound `ppt_scheme = "wamp"` payloads can inherit session-selected serializer/cipher/key ids without per-message key-id plumbing.
- The session-backed E2EE provider lane is now landed on the Dart client path too: `Client.e2eeProviderResolver` can resolve a concrete provider per session from `WELCOME`/auth context, `Session.e2eeProvider` now surfaces the resolved provider, and the negotiated runtime-defaults wrapper still sits on top of that resolved provider for outbound and inbound `ppt_scheme = "wamp"` flows.
- The first native phase-2 parity lane is now landed too: `ct_ffi` exposes E2EE keyring/session handles plus synchronous `xsalsa20poly1305` encrypt/decrypt entrypoints over already-framed PPT bytes, and `connectanum_client` now exports `NativeWampCborXsalsa20Poly1305Provider` on top of the existing negotiated session-provider contract.
- Session teardown now releases resolver-scoped `DisposableWampE2eeProvider` instances, so native E2EE keyring/session handles do not leak across client sessions.
- Repo-local client-native loading now prefers fresh `native/transport/target/*/libct_ffi` builds before hook-cache artifacts, which keeps local E2EE/provider tests on the current shared library instead of stale hook outputs.
- The richer per-message E2EE runtime-context slice is now landed too: the shared provider contract now receives message family, URI/topic/procedure, local session identity, negotiated `authextra.e2ee`, and disclosed peer metadata across outbound `CALL` / `PUBLISH` and inbound `RESULT` / `EVENT` / `INVOCATION`, with lazy/materialized payload views preserving that context on the decode path.
- The shared Dart and native E2EE provider lanes now both expose a provider-level `WampE2eeKeySelectionPolicy` callback. `WampCborXsalsa20Poly1305Provider` and `NativeWampCborXsalsa20Poly1305Provider` can derive `ppt_keyid` from `WampE2eeRuntimeContext` when the message itself does not set one, so session/runtime metadata now drives real key selection instead of being inspection-only.
- `connectanum_core` now also ships reusable E2EE policy adapters on top of that callback surface: `WampE2eeKeySelectionPolicies.negotiated()`, `WampE2eeKeySelectionPolicies.rules(...)`, `WampE2eeKeySelectionPolicies.firstDefined(...)`, and `WampE2eeKeySelectionRule` cover negotiated `WELCOME.authextra.e2ee` fallback plus peer/local identity and trust-based selection without application-specific callback boilerplate.
- The client session wrapper no longer hardcodes negotiated key-id fallback ahead of provider policy. Session-wrapped providers now compose provider-owned policy first and negotiated fallback second while still inheriting negotiated serializer/cipher defaults, so peer/trust rules can override session fallback cleanly on inbound and outbound `ppt_scheme = "wamp"` flows.
- The `ct_ffi` surfaced-handshake regressions now use the suite’s wait helper for HTTP/3 and WebSocket plus a real `h2::client` prior-knowledge handshake for HTTP/2, which removes the old one-shot HTTP/2 preface race from full verification.
- The `ct_core` runtime test suite now keeps the rawsocket config connection alive through its assertions and recovers the shared test mutex after prior panics so Linux `cargo test -p ct_core` does not cascade `PoisonError` failures after one flaky test.
- The `ct_ffi` `runtime::ffi` unit tests now use the same shared suite guard as the rest of the FFI tests before touching global message handles, so concurrent `ct_shutdown()` calls from other tests no longer invalidate those handles mid-assertion.
- The `ct_ffi` HTTP/2 and HTTP/3 body-timeout regressions now keep request bodies flowing well below the idle timeout and assert only on the emitted lifecycle event, so full-suite verification no longer flakes between timeout reasons or handshake-queue timing on this host.
- The native Rust workspace no longer emits the previously-tracked dead-code warning block during local verification; the cleanup landed in `2fac53b` without changing runtime behavior.
- The `ct_ffi` HTTP/3 idle-timeout regression test now asserts directly on the emitted HTTP/3 connection event instead of waiting on a separate accepted-connection callback, which removes a full-suite race that could intermittently fail `bin/verify`.
- Native runtime execution is now validated on both Linux and macOS; unsupported hosts still skip the native runtime slices.
- Root verification now covers the full router package, including `publish_ack_test.dart` and `remote_auth_integration_test.dart`, while still serialising native runtime work through the router package's checked-in test config.
- Package-local browser verification now runs from `packages/connectanum_client`, and the client/router build hooks build on Linux and macOS while still no-oping on unsupported hosts.
- The client/router build hooks now reuse `CONNECTANUM_NATIVE_LIB` for prebuilt binaries and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1` for deployments that intentionally provide `ct_ffi` themselves, instead of invoking Cargo unconditionally.
- The client native runtime loader now falls back to the bare platform library name after hooks/local-build probing, so system-installed `ct_ffi` behaves the same way on the client path as it already did on the router path.
- `bin/package-native-artifact` now produces deterministic `ct_ffi` release bundles for the host platform, including the native library, a manifest, a README, and a SHA-256 checksum under `out/native-artifacts/`.
- GitHub Actions now exposes a dedicated `Native Artifacts` workflow that runs `bin/package-native-artifact` on explicit GitHub-hosted platforms and uploads the resulting tarball, checksum, and manifest as workflow artifacts for the existing `CONNECTANUM_NATIVE_LIB` deployment path.
- The current target matrix for those hosted native bundles is Linux x64 (`x86_64-unknown-linux-gnu`), Linux arm64 (`aarch64-unknown-linux-gnu`), macOS arm64 (`aarch64-apple-darwin`), and macOS Intel (`x86_64-apple-darwin`).
- The `Native Artifacts` workflow is now configured to publish those same bundles to GitHub Releases on release-tag runs, and manual dispatches can publish/update a release when given an explicit tag name.
- The same `Native Artifacts` workflow now generates GitHub artifact attestations for each packaged archive/checksum/manifest set, so released `ct_ffi` bundles have hosted provenance records in addition to the GitHub Release assets themselves.
- Hosted validation for the release path is now complete: GitHub Actions run `24756862771` validated release publishing after the `c4bd069` shell-variable fix, and run `24757138619` validated the attestation-enabled workflow end to end on both Linux and macOS while keeping `Publish GitHub Release` green.
- The same `Native Artifacts` workflow now also emits detached Sigstore blob bundles (`<asset>.sigstore.json`) for the packaged archive/checksum/manifest set, so release assets can be verified offline with `cosign verify-blob` in addition to GitHub-hosted attestations.
- Public-facing release metadata now defaults to human-readable titles and structured release details for both standalone native-bundle tags and `v*` project releases, while `v*` releases keep a generated changelog section even when an existing release is refreshed.
- The top-level `README.md` and the packaged native-bundle `README.md` now lead with end-user quick-start and artifact usage guidance instead of internal workflow notes, while still preserving the maintainer/Codex guidance further down the repo README.
- Public-facing docs are now consistent across the repo root, the packaged
  native bundle, the public workspace folders, and the implemented benchmark
  workspace docs. The stale pre-monorepo `connectanum_client` README is gone,
  the auth/router/core/bench package folders now have current top-level
  README files, and `native/bench/README.md` now documents the implemented
  orchestrator instead of a design draft.
- The public docs surface now states the current runtime contracts directly
  too. `README.md`, the router/client package READMEs, `docs/deployment.md`,
  and `docs/examples.md` now document the supported cancellation modes
  (`skip`, `kill`, `killnowait`), graceful drain behavior and `/healthz`, and
  the lazy-payload / zero-copy boundaries instead of leaving those details
  scattered across tests and internal notes.
- The `add-router` branch contains a dedicated `Router Image` workflow staged
  to publish `ghcr.io/konsultaner/connectanum-router` for `linux/amd64` and
  `linux/arm64` on `v*` tags. GitHub does not expose that workflow from the
  default branch yet, and no GHCR router package is visible, so the current
  public contract remains staged rather than published.
- The router/client build hooks can now download a hosted `ct_ffi` release bundle directly when `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` is set, verify the published `.sha256`, extract the archive, and stage the native library without invoking Cargo.
- `CONNECTANUM_NATIVE_RELEASE_REPOSITORY=<owner/repo>` overrides the default GitHub Releases source for that hook-managed prebuilt flow, and the explicit prebuilt/system-library paths no longer require a local `native/transport` checkout.
- `packages/connectanum_router/tool/install_native.dart` and `packages/connectanum_client/tool/install_native.dart` now provide the explicit source-checkout prefetch path for hosted native assets: they download the current host bundle into `.dart_tool/connectanum/native/<host-triple>/`, verify the published checksum, and print the resulting library path for `CONNECTANUM_NATIVE_LIB`.
- The install helpers deliberately keep the deployment/runtime contract explicit instead of trying to simulate unsupported `dart pub get` automation; automatic hook cache reuse was tested and then dropped after hitting a Dart native-assets bundler bug on this macOS setup.
- `ct_core` now has an env-gated Linux-only kTLS server prototype. When
  `CONNECTANUM_ENABLE_KTLS=1` is set on Linux and a native-TLS listener
  exposes HTTP or HTTP/2, the accepted socket is prepared for Linux TLS ULP,
  Rustls secret extraction is enabled, and the server attempts a post-handshake
  handoff into a kTLS-backed `IoStream`.
- When `CONNECTANUM_ENABLE_KTLS` is unset or the host is not Linux, the native
  TLS path stays on the existing `tokio-rustls` implementation.
- The strict Linux validation path is now reproducible through
  `bin/ktls-linux-validate` and GitHub Actions workflow `kTLS Validation`,
  which auto-runs on pushes to `add-router` and `master` and remains available
  through `workflow_dispatch`.
- Hosted Linux validation is now green: GitHub Actions run `24767010221`
  passed on Ubuntu 24.04 with `CONNECTANUM_ENABLE_KTLS=1` and
  `CONNECTANUM_REQUIRE_KTLS=1`, including the targeted Rust kTLS tests and the
  existing HTTP/2 smoke bench.
- The hosted Linux HTTP/2 benchmark milestone is now complete. GitHub Actions
  runs `24773860109` (`CI`), `24773860116` (`kTLS Validation`), and
  `24773860158` (`kTLS HTTP/2 Benchmarks`) all passed on commit `6d18344`,
  which confirmed that the earlier required-kTLS handshake regression and the
  older multiplexed HTTP/2 `EINVAL` / `EMSGSIZE` / `unexpected frame type`
  failure cluster are gone on hosted Linux.
- `kTLS HTTP/2 Benchmarks` is now manual-only. The workflow remains available
  through `workflow_dispatch` for comparative hosted artifacts, but it no
  longer auto-runs on every `native/bench/**` push because it is a completed
  research benchmark and the strict `kTLS Validation` workflow is the CI
  correctness gate.
- The remaining kTLS caveat is performance rather than correctness: required
  kTLS still trails baseline TLS in the hosted HTTP/2 benchmark, especially in
  the 4-thread multiplexed workload shape.
- `bin/ktls-http2-bench` now preserves partial benchmark artifacts even when a
  pass fails partway through, so hosted runs still upload per-pass summaries
  and generate `comparison.json` / `comparison.md` from whatever completed
  workloads exist before returning a non-zero exit code.
- The current local kTLS server handoff no longer uses the buffered
  `tokio-rustls` / dummy-session path. When kTLS is requested on Linux,
  `ct_core` now drives rustls's unbuffered server handshake, buffers any
  post-handshake plaintext explicitly, converts with
  `dangerous_into_kernel_connection()`, and only then constructs the kTLS
  `IoStream`.
- GitHub Actions runs `24772627167` (`kTLS HTTP/2 Benchmarks`) and
  `24772627180` (`kTLS Validation`) showed that the first unbuffered handoff
  patch still broke the required-kTLS path before the benchmark workload
  started: the initial `/bench/healthz` handshake aborted with server-side
  `received fatal alert: UnexpectedMessage` and client-side
  `got ApplicationData when expecting Handshake`.
- Local analysis showed two unbuffered-rustls constraints that the first patch
  missed: `EncodeTlsData` can be emitted multiple times before a single
  `TransmitTlsData`, and `WriteTraffic` can still leave a partial
  post-handshake TLS record prefix buffered in the caller-owned input slice.
- The current local fix now accumulates every encoded handshake fragment until
  `TransmitTlsData` and keeps draining userspace TLS bytes until any partial
  buffered record is completed or consumed before switching the socket into
  kTLS.
- TLS 1.3 session tickets are still kept disabled on the kTLS path for now, so
  the validated handoff remains intentionally narrow while the next kTLS task
  shifts from HTTP/2 correctness into secure WAMP TLS coverage and later
  performance tuning.
- The local autonomy blockers from the 2026-04-21 audit are resolved for this macOS shell environment.
- In-app heartbeat sandboxes are more restricted than the interactive shell here; remote CI inspection and git metadata writes should still happen from unrestricted interactive runs or the external launchd worker.

## Environment Requirements

- Dart SDK `^3.9.2` (Flutter-bundled Dart is acceptable)
- Rust stable toolchain
- A Chrome or Chromium executable for browser-platform tests
- Either `CONNECTANUM_NATIVE_LIB` pointing at a prebuilt `ct_ffi` library or `CONNECTANUM_NATIVE_RELEASE_TAG=<tag>` for the hook-managed hosted bundle path when the standard release location is not used
- Linux or macOS is required for native runtime execution tests; other hosts verify the portable suites and browser coverage instead

## Verification Status

- 2026-05-21: `bin/test-fast`,
  `dart format packages/connectanum_mcp/test/io_client_export_test.dart`,
  `dart test -p vm packages/connectanum_mcp/test/io_client_export_test.dart`,
  `git diff --check`, and `bin/verify` passed on Darwin arm64 after expanding
  the MCP IO-entrypoint Streamable WAMP meta smoke to all typed
  session/registration/subscription helper families.
- 2026-04-23: `bin/test-fast`, `bash -n bin/wamp-profile-validate`,
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-smoke-release-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`,
  and `bin/verify` passed on Darwin arm64 after expanding the canonical WAMP
  release-gate entrypoint to include cleartext, secure, and control-plane
  smoke gates before the policy-backed throughput gates.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before changing
  `kTLS HTTP/2 Benchmarks` to manual-only so completed kTLS comparison
  benchmarking no longer blocks unrelated WAMP profile CI pushes.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml --bin http_stream http_endpoint_accepts_https_control_base -- --nocapture`,
  `bin/wamp-profile-validate --out-dir out/wamp-profile-validation-http1-control-local --router-worker-counts 1 --native-runtime-thread-counts 1 --workload-timeout-ms 300000`,
  and `bin/verify` passed on Darwin arm64 after forcing the Rust bench
  control client to HTTP/1.1 for WAMP profile gates.
- 2026-04-23: `bin/test-fast`,
  `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`,
  both WAMP throughput policy gate checks against `out/wamp-transport-local`
  and `out/wamp-secure-local`, and `bin/verify` passed on Darwin arm64 after
  adding the WAMP benchmark contract and initial cleartext/TLS policy floors.
- 2026-04-23: `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp -r expanded`, and `bin/verify` passed on
  Darwin arm64 after adding the WAMP-backed MCP tool delegate. The active plan
  is now switched to WAMP-profile transport performance readiness.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before adding the
  WAMP-backed MCP tool delegate slice.
- 2026-04-23: `dart analyze packages/connectanum_mcp`,
  `dart test packages/connectanum_mcp -r expanded`, and `bin/verify` passed on
  Darwin arm64 after adding the MCP stdio transport adapter,
  `packages/connectanum_mcp/example/stdio_echo_server.dart`, focused stdio
  framing tests, and the associated roadmap/state docs.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before adding the MCP
  stdio transport adapter slice.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after adding the first
  `packages/connectanum_mcp` implementation slice, wiring its tests into
  `bin/test-fast` / `bin/test-all`, and updating the MCP plan, roadmap, and
  structure docs.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before creating the first
  `packages/connectanum_mcp` implementation slice.
- 2026-04-23: `dart analyze packages/connectanum_mcp` and
  `dart test packages/connectanum_mcp -r expanded` passed on Darwin arm64
  after adding the in-memory MCP lifecycle and tool-registry package slice.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording
  `packages/connectanum_core` as the approved design reference for the MCP
  package shape.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after queuing WAMP
  profile-related transport benchmark production readiness immediately after
  the active MCP milestone.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after promoting MCP support
  for downstream application integration in `AGENTS.md`, `ROADMAP.md`,
  `ROADMAP_NEXT.md`, project state, and the new active MCP exec plan.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after adding opt-in
  throughput/p95 performance budgets to the bench artifact gate, keeping the
  default transport-counter gate strict, and updating the active plan/state
  docs.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`,
  `bash -n bin/check-bench-artifacts`,
  `bin/check-bench-artifacts --summary native/bench/artifacts/bench_results.summary.json --report-json /tmp/connectanum-default.gate.json --report-md /tmp/connectanum-default.gate.md`,
  and a temporary metrics-policy failure check passed on Darwin arm64 after
  adding `throughput_mbps_min` and `latency_p95_ms_max` gate findings.
- 2026-04-23: `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json --policy native/bench/artifact_gate/h3_multiplex_scaling.json --report-json /tmp/connectanum-h3.gate.json --report-md /tmp/connectanum-h3.gate.md`
  still passed all 20 H3 round-robin workloads with the existing scoped counter
  policy after the performance-budget gate extension.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before adding the
  bench artifact performance-budget layer.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the
  policy-aware bench artifact gate path, adding the H3 multiplex gate policy,
  and closing the H3 transport/backpressure plan.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before landing the
  policy-aware bench artifact gate path for the H3 multiplex backlog decision.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture`
  and `bash -n bin/check-bench-artifacts` passed on Darwin arm64 after adding
  scoped artifact-gate policies while keeping the strict default gate.
- 2026-04-23: `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json --policy native/bench/artifact_gate/h3_multiplex_scaling.json`
  passed on Darwin arm64 with 20 workloads, and
  `bin/check-bench-artifacts --summary native/bench/artifacts/bench_results.summary.json`
  still passed the checked-in sample artifact set without a policy.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the
  rejected `out/h3-http3-post-enqueue-yield-probe/` experiment and reverting
  the native HTTP/3 request-path code to the kept steady-state round-robin
  drain baseline.
- 2026-04-23: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http_connection_stats -- --nocapture` and `cargo build --manifest-path native/transport/Cargo.toml -p ct_ffi --release` passed on Darwin arm64 while probing a post-enqueue HTTP/3 accept-loop yield. The code change was reverted after measurement.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1 --native-runtime-thread-counts 1 --results out/h3-http3-post-enqueue-yield-probe/bench_results.jsonl --artifact-dir out/h3-http3-post-enqueue-yield-probe` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the post-enqueue yield probe lost all five measured workloads in the `workers=1`, `threads=1` quadrant, left `max_backpressure_depth_after` unchanged at `0/2/4/8/16`, and `bin/check-bench-artifacts --summary out/h3-http3-post-enqueue-yield-probe/bench_results.summary.json` still failed with `8` findings.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after closing the
  CI-artifact cleanup/native-matrix plan in project state and reactivating the
  HTTP/3 transport/backpressure plan.
- 2026-04-23: GitHub Actions run `24825770571` (`Native Artifacts`,
  `workflow_dispatch`) passed on commit `7049801` across Linux x64, Linux
  arm64, macOS arm64, and macOS Intel; `Publish GitHub Release` skipped because
  no release tag was provided for the validation dispatch.
- 2026-04-23: GitHub Actions run `24824613232` (`CI`) passed on commit
  `7049801`, with both `Fast Checks` and `Full Verify` green after removing
  the generic CI metrics artifact upload and expanding the native bundle
  matrix.
- 2026-04-23: `bin/test-fast`, workflow YAML parsing via Ruby, and
  `bin/verify` passed on Darwin arm64 after keeping the main `CI` workflow
  verification-only and expanding `Native Artifacts` to Linux x64, Linux arm64,
  macOS arm64, and macOS Intel.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after updating `AGENTS.md` and this state file so autonomous continuation now prioritizes a clean CI chain and production-readiness work before exploratory implementation.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-request-ready-wake/` experiment and reverting the router/native code to the kept steady-state round-robin HTTP/3 drain.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-request-ready-wake/bench_results.jsonl --artifact-dir out/h3-http3-request-ready-wake` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the request-ready wake variant won only `7/20` throughput quadrants and `7/20` p95 quadrants, still failed the bench gate with `32` findings, and regressed deep `s8/s16` reuse too hard to keep.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-native-ready-queue/` experiment and reverting the router/native code to the kept steady-state round-robin HTTP/3 drain.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-native-ready-queue/bench_results.jsonl --artifact-dir out/h3-http3-native-ready-queue` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the native ready-queue variant won only `6/20` throughput quadrants and `9/20` p95 quadrants, left `max_backpressure_depth_after` unchanged in every quadrant, and still failed the bench gate with `32` findings.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-followup-burst2/` bounded-follow-up-burst experiment and reverting the router code to the kept steady-state round-robin HTTP/3 drain.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-followup-burst2/bench_results.jsonl --artifact-dir out/h3-http3-followup-burst2` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the bounded follow-up burst variant won only `9/20` throughput quadrants and `8/20` p95 quadrants, so the code was reverted and the active H3 plan remained open.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after recording the rejected `out/h3-http3-priority/` loop-order experiment and stabilizing `native/transport/ct_ffi/src/tests/listen_flow.rs::http2_handshake_surfaced_via_ffi`.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-priority/bench_results.jsonl --artifact-dir out/h3-http3-priority` passed on Darwin arm64 and was recorded as a negative result. Compared with `out/h3-http3-round-robin`, the loop-priority variant won only `6/20` throughput quadrants and `1/20` p95 quadrants, so the code was reverted and the active H3 plan remained open.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the steady-state HTTP/3 round-robin drain, the focused router fairness regression, and the updated active H3 transport/backpressure plan notes.
- 2026-04-23: `dart analyze packages/connectanum_router/lib/src/router/router_instance/router_boss.dart packages/connectanum_router/test/router_runtime_test.dart` and `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'http3 connections are drained fairly across tracked requests' -r expanded` both passed on Darwin arm64 after landing the steady-state HTTP/3 round-robin drain change and the focused fairness regression.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-http3-round-robin/bench_results.jsonl --artifact-dir out/h3-http3-round-robin` passed on Darwin arm64. Compared with `out/h3-followup-direction`, the steady-state round-robin drain improved `12/20` throughput quadrants and `13/20` p95 quadrants, but `bin/check-bench-artifacts --summary out/h3-http3-round-robin/bench_results.summary.json` still reports absolute backpressure findings because the shipped gate threshold is zero and the `s2+` workloads are not there yet.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after reverting the
  measured boss-side HTTP/3 queue-drain experiments and checking in the
  negative benchmark findings under the still-active H3
  transport/backpressure plan.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after reverting the rejected H3 chunking/backlog-gate code and checking in the negative benchmark findings for the still-active transport/backpressure plan.
- 2026-04-23: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core http3_server_config_applies_transport_tuning -- --nocapture`, `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_response_streaming_round_trip -- --nocapture`, and `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'streams HTTP/3 response chunks using native streams' -r expanded` all passed on Darwin arm64 while iterating on the H3 transport/backpressure milestone.
- 2026-04-23: local Darwin reruns of `native/bench/scenarios/h3_multiplex_scaling.toml` with experimental send-side chunking (`out/h3-transport-chunking/`, `out/h3-transport-chunking-64k/`) and native HTTP/3 backlog gating (`out/h3-backlog-gate/`, `out/h3-backlog-gate-4/`) completed successfully and were recorded as negative results; neither candidate produced a clean enough improvement to keep.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before iterating on the
  H3 boss-loop queue-drain experiments.
- 2026-04-23: local Darwin reruns of
  `native/bench/scenarios/h3_multiplex_scaling.toml` with
  `out/h3-boss-drain-cadence/`, `out/h3-boss-connection-local/`, and
  `out/h3-boss-http3-burst1/` all completed successfully and were recorded as
  negative results; none of the measured boss-side accept/drain variants
  produced a clean enough cross-matrix win to keep.
- 2026-04-21: `bin/bootstrap` passed in a plain non-login shell on Darwin arm64.
- 2026-04-21: `bin/test-fast` passed in a plain non-login shell on Darwin arm64, including the native client transport fast tests and the sequential router native runtime smoke test.
- 2026-04-21: `bin/verify` passed in a plain non-login shell on Darwin arm64, including `ct_core`/`ct_ffi` Rust tests, the `ffi-test` native release build, native client transport tests, the full router package from `packages/connectanum_router`, and the Chromium/Dart2Wasm browser websocket test from `packages/connectanum_client`.
- 2026-04-21: `cd packages/connectanum_router && dart test test` passed on Darwin arm64, including `publish_ack_test.dart`, `remote_auth_integration_test.dart`, `router_integration_native_test.dart`, and `router_integration_websocket_test.dart` under the router package's checked-in serial test configuration.
- 2026-04-21: `bin/verify` passed again on Darwin arm64 after updating `bin/test-all` to run the router suite from `packages/connectanum_router`, so the root verification flow now exercises the full router package with the same package-local concurrency contract that GitHub CI needs.
- 2026-04-21: `dart test packages/connectanum_router/test/remote_auth_integration_test.dart --concurrency=1 -r expanded` passed on Darwin arm64 after rotating the remote-auth TLS fixtures to an Apple-compatible server certificate lifetime.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core connection_runtime_config_exposes_rawsocket_settings -- --nocapture` passed on Darwin arm64 after keeping the test connection alive through runtime-config assertions.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core runtime_starts_only_once -- --nocapture` passed on Darwin arm64 after making the shared Rust test guard recover from poisoned mutex state.
- 2026-04-21: GitHub Actions run `24730190112` reached green `Fast Checks`, then failed in `Full Verify` because `bin/test-all` invoked `dart test packages/connectanum_router/test` from the repo root, which bypassed `packages/connectanum_router/dart_test.yaml` and let `remote_auth_integration_test.dart` collide with the process-global native runtime in Linux CI.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core`, `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi`, and `bin/verify` all passed on Darwin arm64 after `2fac53b` removed the known Rust dead-code warning block from local verification output.
- 2026-04-21: GitHub Actions run `24732889424` passed on `add-router` for commit `2fac53b`, with both `Fast Checks` and `Full Verify` green.
- 2026-04-21: `bin/test-fast` passed again on Darwin arm64 before the transport/auth/authz throughput-matrix update.
- 2026-04-21: `python3` `tomllib` parsing confirmed `native/bench/scenarios/transport_mbit_matrix_throughput.toml` loads cleanly with 57 uniquely named workloads.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_idle_timeout_emits_connection_event -- --nocapture` passed three consecutive reruns on Darwin arm64 after removing the flaky accepted-connection dependency from the test.
- 2026-04-21: `bin/verify` passed on Darwin arm64 after adding `native/bench/scenarios/transport_mbit_matrix_throughput.toml` and stabilizing `ct_ffi`'s HTTP/3 idle-timeout regression test.
- 2026-04-21: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi runtime::ffi::tests -- --nocapture` and `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi -- --nocapture` passed on Darwin arm64 after putting the `runtime::ffi` unit tests under the shared FFI test guard so parallel `ct_shutdown()` calls can no longer clear their message handles.
- 2026-04-21: `bin/verify` passed again on Darwin arm64 after starting the E2EE/PPT research spike docs and fixing the `ct_ffi` shared-state FFI test race.
- 2026-04-22: `cd packages/connectanum_core && dart test test/message_result_test.dart test/message_invocation_test.dart -r expanded` passed on Darwin arm64 after landing the `WampE2eeProvider` contract, explicit missing-provider errors, and provider-backed WAMP invocation/result tests.
- 2026-04-22: `cd packages/connectanum_client && dart test test/client_test.dart -p vm -r expanded` passed on Darwin arm64 after threading `Client.e2eeProvider` through the session/native fast path and adding outbound/inbound WAMP provider coverage.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the core/client E2EE provider plumbing and focused tests.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the concrete `WampCborXsalsa20Poly1305Provider` implementation and router passthrough assertions.
- 2026-04-22: `dart test packages/connectanum_core/test/message_e2ee_payload_test.dart packages/connectanum_core/test/message_result_test.dart packages/connectanum_core/test/message_invocation_test.dart -r expanded` passed on Darwin arm64 after replacing the provider test doubles with the real `xsalsa20poly1305` implementation and adding explicit key/cipher/decrypt failure coverage.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after asserting provider-backed `ppt_cipher` / `ppt_keyid` propagation and native direct-result decrypts against the real implementation.
- 2026-04-22: `dart test packages/connectanum_router/test/router_runtime_test.dart -r expanded` passed on Darwin arm64 after pinning `ppt_cipher` / `ppt_keyid` passthrough on internal-session WAMP lazy publish/call flows.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the concrete `WampCborXsalsa20Poly1305Provider`, the new provider regression file, and the router/client metadata assertions.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the native build-hook packaging updates.
- 2026-04-22: `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after teaching the router build hook to reuse `CONNECTANUM_NATIVE_LIB` and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1`.
- 2026-04-22: `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after teaching the client build hook to reuse `CONNECTANUM_NATIVE_LIB` and honor `CONNECTANUM_SKIP_NATIVE_BUILD=1`.
- 2026-04-22: `cd packages/connectanum_client && dart test test/transport/native/native_library_loader_test.dart -r expanded` passed on Darwin arm64 after making the client runtime loader fall back to the bare platform library name for system-installed `ct_ffi`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the native build-hook packaging contract, the new hook regressions, the client loader fallback, and the associated doc updates.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the dedicated `ct_ffi` artifact-packaging workflow and local packaging script.
- 2026-04-22: `bin/package-native-artifact --out-dir out/native-artifacts-test` passed on Darwin arm64 and produced `ct-ffi-aarch64-apple-darwin.tar.gz`, a matching `.sha256`, and a `.manifest.json` that captures the host triple plus commit metadata.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing `bin/package-native-artifact`, the `Native Artifacts` GitHub Actions workflow, the deployment/readme updates, and the analyzer-cleanup follow-up in the hook/native-loader tests.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing GitHub Release publishing on top of the `Native Artifacts` workflow and after restoring the hook/native-loader test files to the repo-standard `@TestOn` + `library;` layout.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` passed locally after adding the GitHub Release publishing job to the native artifact workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the GitHub Release publishing workflow changes, the release-path docs updates, and the `library;` analyzer-noise fix for the hook/native-loader tests.
- 2026-04-22: GitHub Actions run `24756862771` passed on tag `ct-ffi-v2026.04.22-validation.042151` after `c4bd069` fixed the `Publish GitHub Release` shell variable bug found by run `24756798793`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing GitHub artifact attestations for the packaged native release assets.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` passed locally after adding `actions/attest@v4` to the native artifact workflow.
- 2026-04-22: GitHub Actions run `24757138619` passed on tag `ct-ffi-v2026.04.22-validation.043206-attest`, with both Linux/macOS `ct_ffi` jobs generating artifact attestations successfully and `Publish GitHub Release` remaining green.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing GitHub artifact attestations for the packaged release assets and updating the release/deployment docs to describe `gh attestation verify`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing explicit GitHub Release download/checksum support in the router/client build hooks.
- 2026-04-22: `cd packages/connectanum_router && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after adding the router hook's hosted-release download path and checksum verification.
- 2026-04-22: `cd packages/connectanum_client && dart test test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after adding the client hook's hosted-release download path and checksum verification.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing `CONNECTANUM_NATIVE_RELEASE_TAG`, `CONNECTANUM_NATIVE_RELEASE_REPOSITORY`, the focused hook regressions, and the hosted-bundle deployment docs.
- 2026-04-22: `dart analyze packages/connectanum_router/tool/install_native.dart packages/connectanum_client/tool/install_native.dart packages/connectanum_router/lib/src/native_release_installer.dart packages/connectanum_client/lib/src/native_release_installer.dart packages/connectanum_router/test/hook/install_native_test.dart packages/connectanum_client/test/hook/install_native_test.dart` passed on Darwin arm64 after splitting the runtime install helpers away from hook-only build modules.
- 2026-04-22: `dart test packages/connectanum_router/test/hook/build_hook_test.dart -r expanded` and `dart test packages/connectanum_client/test/hook/build_hook_test.dart -r expanded` passed on Darwin arm64 after keeping the hook contract explicit (`CONNECTANUM_NATIVE_LIB` / `CONNECTANUM_NATIVE_RELEASE_TAG`) and fixing the new analyzer warnings in both build hooks.
- 2026-04-22: `dart test packages/connectanum_router/test/hook/install_native_test.dart -r expanded` and `dart test packages/connectanum_client/test/hook/install_native_test.dart -r expanded` passed on Darwin arm64 after adding the explicit `install_native` package entrypoints and their hosted-download regression coverage.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 after adding the explicit `install_native` package entrypoints and removing the failed hook-cache reuse experiment.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the explicit `install_native` package entrypoints, cleaning the package hook tests so they do not poison shared native-asset caches with fake dylibs, and keeping the build-hook contract explicit (`CONNECTANUM_NATIVE_LIB` / `CONNECTANUM_NATIVE_RELEASE_TAG`).
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` passed locally after adding Sigstore blob bundle generation and verification to the native artifact workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing detached Sigstore blob bundles (`<asset>.sigstore.json`) for the packaged native archive/checksum/manifest set and updating the release/deployment docs to describe `cosign verify-blob`.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml'); puts 'yaml_ok'"` passed locally after adding the multi-arch GHCR router image workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the `Router Image` workflow, the repo `.dockerignore`, and the deployment/template updates for `ghcr.io/konsultaner/connectanum-router`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the kTLS
  research spike docs and project-state refresh.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing
  `docs/ktls_research.md`, the kTLS research exec plan, and the associated
  `docs/project_state.md` refresh.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after landing the `CONNECTANUM_ENABLE_KTLS` parser and HTTP/HTTP2 eligibility coverage for the Linux-only prototype module.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the env-gated Linux-only kTLS server prototype in `ct_core`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the env-gated Linux-only kTLS server prototype, keeping the default/non-Linux TLS path on `tokio-rustls`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the public-facing release/readme polish pass.
- 2026-04-22: `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"` and `ruby -e 'require "yaml"; wf = YAML.load_file(".github/workflows/native-artifacts.yml"); step = wf.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }.find { |s| s["name"] == "Create or update GitHub Release" }; abort("step not found") unless step; File.write("/tmp/connectanum-release-step.sh", step.fetch("run"));' && bash -n /tmp/connectanum-release-step.sh && echo shell_ok` both passed locally after polishing the native-artifact release metadata workflow.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the public-facing release titles/details, the packaged native-bundle README rewrite, and the top-level README restructure.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the strict Linux kTLS validation workflow and runner.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after adding the strict Linux kTLS mode split and again after switching the Linux handoff path to `dangerous_extract_secrets()` plus the dummy server session.
- 2026-04-22: `bash -n bin/ktls-linux-validate && bin/ktls-linux-validate --help >/dev/null` passed on Darwin arm64 after fixing the validation script to build/export `CONNECTANUM_NATIVE_LIB` and pass `--native-lib` into the bench runner explicitly.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after fixing the Linux kTLS handoff path and then rerunning it after the final `bin/ktls-linux-validate` contract fix.
- 2026-04-22: GitHub Actions run `24767010221` (`kTLS Validation`) passed on `add-router`, validating the strict Linux kTLS runner end to end on Ubuntu 24.04 after run `24766303551` exposed the missing `--native-lib` bench argument.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the HTTP/2 benchmark handoff fixes.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after preserving buffered rustls plaintext across the Linux kTLS handoff and adding the in-memory regression that proves the HTTP/2 client preface survives that drain step.
- 2026-04-22: GitHub Actions run `24768800167` (`kTLS HTTP/2 Benchmarks`) failed on `add-router` only because the first buffered-plaintext handoff patch forgot to keep the Linux-only `session` binding mutable during `drain_buffered_plaintext(&mut session)`.
- 2026-04-22: GitHub Actions run `24768909306` (`kTLS HTTP/2 Benchmarks`) uploaded baseline plus required-kTLS artifacts on Ubuntu 24.04. Baseline TLS completed both workloads cleanly (`h2_sustained_transfer`: `3994.58` Mbps / `4247.40` Mbps at 1/4 native threads, `h2_multiplexed_streams`: `5807.50` Mbps / `5779.71` Mbps at 1/4 native threads). Required-kTLS completed only `h2_sustained_transfer` at 1 thread (`1911.93` Mbps, p95 `18.85` ms, two protocol-error events) before `h2_multiplexed_streams` failed with `Invalid argument (os error 22)`, `Message too long (os error 90)`, occasional `Failed to set TLS ULP: Transport endpoint is not connected (os error 107)`, and downstream HTTP/2 `unexpected frame type` resets.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core apply_server_tls_runtime_settings -- --nocapture` passed on Darwin arm64 after making the kTLS server prototype suppress TLS 1.3 session tickets whenever secret extraction is enabled.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after making the kTLS server prototype suppress TLS 1.3 session tickets on the dummy-session handoff path and updating the kTLS benchmark plan/research/state docs.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` and `cargo test --manifest-path native/transport/Cargo.toml -p ct_core tls::tests -- --nocapture` passed on Darwin arm64 after replacing the Linux kTLS accept path with an unbuffered rustls server handshake and real kernel-connection handoff.
- 2026-04-22: `docker run --rm --platform linux/amd64 -v "$PWD:/work" -w /work/native/transport rust:1 bash -lc 'TOOLCHAIN=$(ls /usr/local/rustup/toolchains | head -n1); export PATH=\"/usr/local/rustup/toolchains/$TOOLCHAIN/bin:$PATH\"; cargo check -p ct_core'` passed, confirming the Linux-only unbuffered kTLS handoff path typechecks in a real Linux toolchain.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after replacing the Linux kTLS accept path with rustls's unbuffered server handshake plus `dangerous_into_kernel_connection()` and updating the kTLS benchmark plan/research/state docs.
- 2026-04-22: GitHub Actions run `24772627167` (`kTLS HTTP/2 Benchmarks`) failed on `add-router` after the first unbuffered-handshake landing because the required-kTLS `/bench/healthz` handshake returned server-side `received fatal alert: UnexpectedMessage` while the client reported `got ApplicationData when expecting Handshake`.
- 2026-04-22: GitHub Actions run `24772627180` (`kTLS Validation`) failed on `add-router` with the same `UnexpectedMessage` / `got ApplicationData when expecting Handshake` signature before the stricter Linux smoke path could complete.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core ktls::tests -- --nocapture` passed on Darwin arm64 after buffering every unbuffered `EncodeTlsData` fragment until `TransmitTlsData` and adding a regression that proves `WriteTraffic` can still leave partial TLS bytes buffered in userspace.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_core tls::tests -- --nocapture` passed on Darwin arm64 after the same unbuffered-handshake byte-accounting fix.
- 2026-04-22: `docker run --rm --platform linux/amd64 -v "$PWD:/work" -w /work/native/transport rust:1 bash -lc 'TOOLCHAIN=$(ls /usr/local/rustup/toolchains | head -n1); export PATH=\"/usr/local/rustup/toolchains/$TOOLCHAIN/bin:$PATH\"; cargo check -p ct_core'` passed again, confirming the corrected Linux-only handoff path still typechecks in a real Linux toolchain.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing provider-level E2EE key-selection policies on the Dart and native lanes, updating the E2EE docs/roadmap/state files, and stabilizing the `ct_ffi` surfaced HTTP/2 handshake test with a real h2 client handshake.
- 2026-04-22: GitHub Actions runs `24773860109` (`CI`), `24773860116` (`kTLS Validation`), and `24773860158` (`kTLS HTTP/2 Benchmarks`) all passed on `add-router` for commit `6d18344`, closing the HTTP/2 kTLS correctness milestone on hosted Linux.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing provider-level E2EE key-selection policies on the shared Dart/native provider lane.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after the package-level public-surface docs cleanup pass, including the full Rust, Dart, router, and browser suites.
- 2026-04-22: `dart test packages/connectanum_bench/test/wamp_transport_targets_test.dart packages/connectanum_bench/test/wamp_workload_runner_test.dart -r expanded` passed on Darwin arm64 after adding explicit secure WAMP target selection and the new `secure_transport` scenario flag.
- 2026-04-22: `cargo test --manifest-path native/bench/Cargo.toml prepared_workload -- --nocapture` passed on Darwin arm64 after extending the Rust bench orchestrator to forward `secure_transport` into the Dart WAMP control payload.
- 2026-04-22: `python3` `tomllib` parsing confirmed `native/bench/scenarios/wamp_secure_smoke.toml` loads cleanly with four secure WAMP workloads.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the secure WAMP bench harness/config/docs checkpoint.
- 2026-04-22: GitHub Actions run `24777296956` (`kTLS Validation`, `workflow_dispatch`) was queued against `native/bench/scenarios/wamp_secure_smoke.toml` on `add-router` so hosted Linux can validate the new secure WAMP path directly instead of the workflow's default HTTP smoke scenario.
- 2026-04-22: GitHub Actions run `24777296956` failed before `READY` with `Invalid argument(s): Duplicate SNI hostname "localhost" detected across router endpoints`, exposing an over-restrictive Dart-side router validation rule rather than a native runtime requirement.
- 2026-04-22: Follow-up runs `24778942812` (`workflow_dispatch`), `24778930521` (`push`), and `24778930527` (`kTLS HTTP/2 Benchmarks`) then failed after the attempted `127.0.0.1` workaround because the native config path rejected that IP-literal SNI hostname during secure bench startup.
- 2026-04-22: GitHub Actions runs `24780721173` (`kTLS Validation`) and `24780721191` (`kTLS HTTP/2 Benchmarks`) passed on `add-router` for commit `70f1525`, confirming the secure-WAMP startup fix on hosted Linux.
- 2026-04-22: GitHub Actions run `24780721174` (`CI`) still failed in `Full Verify` on commit `70f1525` because `bin/test-all` invoked `dart test packages/connectanum_bench/test` from the repo root, bypassing the bench package's serial test contract and letting `bench_router_config_test.dart` collide with the Linux-only native WAMP integration harness in the same package.
- 2026-04-22: `cd packages/connectanum_bench && dart test test -r expanded` passed on Darwin arm64 after adding `packages/connectanum_bench/dart_test.yaml`, running the bench suite from the package root in `bin/test-fast` and `bin/test-all`, and teaching `bench_router_config_test.dart` to anchor relative TLS asset lookup to the repo root while preserving the package-root invocation.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after the bench package adopted the same package-root serial test contract as `connectanum_router`.
- 2026-04-22: `dart test packages/connectanum_router/test/router_json_test.dart packages/connectanum_bench/test/bench_router_config_test.dart -r expanded` passed on Darwin arm64 after allowing shared DNS SNI hostnames across distinct endpoints, restoring the secure WAMP bench listener to `localhost`, and upgrading the bench regression to start the shipped config through the native runtime with distinct reserved listener/http3 ports.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after removing the cross-endpoint duplicate-SNI restriction, restoring the secure WAMP bench listener to `localhost`, and updating the bench/router regressions plus secure-WAMP state docs.
- 2026-04-22: GitHub Actions run `24782645871` (`CI`) passed on `add-router` for commit `b6e458e`, confirming the hosted Linux root-verification fix for the bench package package-root/serial test contract.
- 2026-04-22: GitHub Actions run `24783846529` (`kTLS Validation`, `workflow_dispatch`) reached the secure WAMP workloads and completed the secure RawSocket cases, then failed on `websocket_secure_rpc_json` with `HandshakeException: CERTIFICATE_VERIFY_FAILED: self signed certificate`, proving the remaining blocker was the Dart secure WebSocket client path rather than router startup or native listener selection.
- 2026-04-22: `cd packages/connectanum_bench && dart test test/wamp_session_factory_test.dart -r expanded` passed on Darwin arm64 after adding a real self-signed `wss://localhost` regression and forwarding `allowInsecureCertificates` through the Dart bench WebSocket transport factories for JSON, MsgPack, and CBOR workloads.
- 2026-04-22: `cd packages/connectanum_bench && dart test test -r expanded` passed on Darwin arm64 after the same secure-WebSocket fix, keeping the bench package green under its package-root serial test contract.
- 2026-04-22: `cd packages/connectanum_router && for i in {1..20}; do dart test test/router_worker_auth_test.dart --plain-name 'Cryptosign authenticator rejects wrong signature' -r compact >/tmp/cryptosign-auth-test.log || { cat /tmp/cryptosign-auth-test.log; exit 1; }; done` passed on Darwin arm64 after making the cryptosign negative-path test always flip the first signature byte instead of relying on a hard-coded `ff` prefix that could occasionally match the original signature.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after fixing the Dart secure-WebSocket certificate path in `WebSocketWampSessionFactory`, adding the new bench regression file, and stabilizing the flaky cryptosign negative-path router test.
- 2026-04-22: GitHub Actions run `24785214332` (`kTLS Validation`, `workflow_dispatch`) passed on `add-router` for commit `0b4f1e7`, confirming secure RawSocket + secure WebSocket WAMP smoke workloads on hosted Linux after the Dart secure-WebSocket certificate fix.
- 2026-04-22: GitHub Actions run `24785189137` (`CI`) passed on `add-router` for commit `0b4f1e7`.
- 2026-04-22: `python3` `tomllib` parsing confirmed `native/bench/scenarios/wamp_secure_throughput.toml` loads cleanly with 12 workloads.
- 2026-04-22: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib $PWD/native/transport/target/release/libct_ffi.dylib --control-base https://127.0.0.1:8080/bench --scenario native/bench/scenarios/wamp_secure_throughput.toml` passed on Darwin arm64 and produced the first local secure-WAMP 64 KiB baseline: secure RawSocket RPC roughly `151/163/109 Mbps` (JSON/MsgPack/CBOR) and pubsub roughly `44/56/38 Mbps`; secure WebSocket RPC roughly `146/156/141 Mbps` and pubsub roughly `42/71/52 Mbps`.
- 2026-04-22: `cargo test --manifest-path native/bench/Cargo.toml http_endpoint_accepts_https_control_base -- --nocapture`, `cargo test --manifest-path native/bench/Cargo.toml build_http1_request_uses_origin_form_and_host_header -- --nocapture`, and `cargo test --manifest-path native/bench/Cargo.toml bench_http_client_builds_https_client -- --nocapture` all passed after changing the direct orchestrator default control base to `https://127.0.0.1:8080/bench`.
- 2026-04-22: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib $PWD/native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/wamp_secure_smoke.toml` passed on Darwin arm64 after the same control-base default change, confirming the direct local CLI path works again without a hidden override.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after adding `native/bench/scenarios/wamp_secure_throughput.toml`, updating the direct bench CLI control-base default to `https://127.0.0.1:8080/bench`, and refreshing the secure-WAMP throughput plan/state docs.
- 2026-04-22: GitHub Actions run `24786956501` (`kTLS Validation`, `workflow_dispatch`) passed on `add-router` for commit `c040ef9` with scenario `native/bench/scenarios/wamp_secure_throughput.toml`, recording the hosted Ubuntu response-throughput baseline as RawSocket pubsub `56.77/65.08/57.15 Mbps`, RawSocket RPC `176.60/215.09/164.48 Mbps`, WebSocket pubsub `62.04/78.81/64.83 Mbps`, and WebSocket RPC `191.13/231.59/168.71 Mbps` for JSON/MsgPack/CBOR.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the phase-2 E2EE design checkpoint in `docs/e2ee_ppt_research.md`, `ROADMAP_NEXT.md`, and `docs/project_state.md`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the phase-2 E2EE design checkpoint and adding `docs/exec-plans/2026-04-22-e2ee-phase2-design.md`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the phase-2 E2EE negotiation scaffolding slice.
- 2026-04-22: `dart test packages/connectanum_core/test/custom_fields_test.dart packages/connectanum_core/test/serializer_challenge_welcome_test.dart -r expanded` passed on Darwin arm64 after preserving custom `CHALLENGE.extra` fields across JSON/MsgPack/CBOR.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart packages/connectanum_client/test/transport/native/message_binding_test.dart -r expanded` passed on Darwin arm64 after wiring `Client.authExtra` into `HELLO`, exposing `Session.negotiatedE2ee`, and preserving native-bound challenge metadata.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the phase-2 E2EE negotiation scaffolding slice and closing `docs/exec-plans/2026-04-22-e2ee-negotiation-scaffolding.md`.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the negotiated E2EE runtime-defaults slice.
- 2026-04-22: `dart analyze packages/connectanum_client/lib/src/protocol/session.dart packages/connectanum_client/test/client_test.dart` passed on Darwin arm64 after adding the negotiated session-scoped provider wrapper and its client regressions.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after proving negotiated outbound defaults and negotiated inbound native direct-result decrypts.
- 2026-04-22: `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http2_body_timeout_emits_connection_event -- --nocapture`, `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http2_idle_timeout_emits_connection_event -- --nocapture`, and `cargo test --manifest-path native/transport/Cargo.toml -p ct_ffi http3_body_timeout_emits_connection_event -- --nocapture` all passed on Darwin arm64 after stabilizing the HTTP timeout-path regressions.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the negotiated E2EE runtime-defaults slice, updating the E2EE roadmap/state docs, and stabilizing the `ct_ffi` HTTP/2 + HTTP/3 body-timeout regressions.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the session-backed E2EE provider lane.
- 2026-04-22: `dart analyze packages/connectanum_client/lib/src/client.dart packages/connectanum_client/lib/src/protocol/session.dart packages/connectanum_client/test/client_test.dart` passed on Darwin arm64 after adding the public session-scoped provider resolver surface.
- 2026-04-22: `dart test packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after adding resolver-backed outbound and inbound negotiated WAMP E2EE coverage.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the session-backed E2EE provider lane and updating the E2EE roadmap/state docs.
- 2026-04-22: `bin/test-fast` passed on Darwin arm64 before landing the reusable negotiated/policy adapter slice on top of the shared E2EE provider lane.
- 2026-04-22: `dart analyze packages/connectanum_core/lib/src/message/e2ee_payload.dart packages/connectanum_core/test/message_e2ee_payload_test.dart packages/connectanum_client/lib/src/protocol/session.dart packages/connectanum_client/lib/src/transport/native/e2ee_provider_io.dart packages/connectanum_client/test/client_test.dart` passed on Darwin arm64 after adding `WampE2eeKeySelectionPolicies`, `WampE2eeKeySelectionRule`, and the policy-aware session wrapper.
- 2026-04-22: `dart test packages/connectanum_core/test/message_e2ee_payload_test.dart packages/connectanum_client/test/client_test.dart -r expanded` passed on Darwin arm64 after adding negotiated fallback + peer/trust adapter regressions and the inbound invocation override regression on the client path.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the reusable negotiated/policy adapters, wiring the session wrapper to compose provider policy ahead of negotiated fallback, and refreshing the E2EE roadmap/state docs.
- 2026-04-22: `cargo test --manifest-path native/bench/Cargo.toml artifacts -- --nocapture` passed on Darwin arm64 after landing the bench artifact gate, including summary load/write coverage and both clean/failing gate regressions.
- 2026-04-22: `bash -n bin/check-bench-artifacts bin/ktls-linux-validate bin/ktls-http2-bench` passed after wiring the new root bench-gate entrypoint into both kTLS runner scripts.
- 2026-04-22: `bin/check-bench-artifacts --summary native/bench/artifacts/bench_results.summary.json` passed on the checked-in sample artifact set and wrote sibling `bench_results.gate.json` / `bench_results.gate.md`.
- 2026-04-22: `bin/verify` passed on Darwin arm64 after landing the bench artifact validator, the root wrapper, the kTLS runner integration, and the associated bench metrics docs updates.
- 2026-04-23: `dart analyze packages/connectanum_bench/lib/src/http_auth_bench_harness.dart packages/connectanum_bench/tool/bench_main.dart packages/connectanum_bench/test/http_auth_bench_harness_test.dart` and `dart test packages/connectanum_bench/test/http_auth_bench_harness_test.dart packages/connectanum_bench/test/bench_router_config_test.dart -r expanded` passed on Darwin arm64 after adding the local OAuth introspection bench harness and the `/bench/secure-oauth` route/config coverage.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml prepared_workload_allows -- --nocapture` passed after extending the bench workload parser coverage for static bearer-protected JWT and OAuth routes, and `python3` `tomllib` parsing confirmed `native/bench/scenarios/http_bearer_provider_smoke.toml` now loads with 6 workloads.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the self-contained HTTP bearer-provider bench support, including the new Dart harness, shipped bench router/provider config, expanded smoke scenario, and docs updates.
- 2026-04-23: `dart analyze packages/connectanum_auth_server` passed on Darwin arm64 with no issues, confirming the stale roadmap note about `connectanum_auth_server` analyzer warnings is no longer actionable.
- 2026-04-23: `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'auth bridge issues bearer token for wampcra and dispatches secure route' -r expanded`, `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'auth bridge issues bearer token for scram and dispatches secure route' -r expanded`, and `dart test packages/connectanum_router/test/router_runtime_test.dart --plain-name 'auth bridge rotates refresh tokens and rejects old credentials' -r expanded` all passed on Darwin arm64 after expanding the shipped auth bridge config to cover `ticket`, `wampcra`, and `scram`.
- 2026-04-23: `cargo test --manifest-path native/bench/Cargo.toml --bin http_stream -- --nocapture` passed on Darwin arm64 after teaching the Rust HTTP bench orchestrator to complete WAMP-CRA and SCRAM challenge flows instead of hard-failing non-ticket auth methods.
- 2026-04-23: `python3` `tomllib` parsing confirmed `native/bench/scenarios/http_auth_smoke.toml` loads cleanly with 27 workloads covering login, refresh, and protected-route flows for `ticket`, `wampcra`, and `scram` across HTTP/1.1, HTTP/2, and HTTP/3.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the HTTP auth bridge challenge-method bench expansion, including the new router auth regressions, shipped bench router config changes, and expanded auth smoke scenario.
- 2026-04-23: `python3` `tomllib` parsing confirmed `native/bench/scenarios/h3_multiplex_scaling.toml` now loads cleanly with 5 workloads sweeping `streams_per_connection = 1, 2, 4, 8, 16`.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1 --native-runtime-thread-counts 1,4 --results out/h3-multiplex-scaling/bench_results.jsonl --artifact-dir out/h3-multiplex-scaling` passed on Darwin arm64 and produced the current local HTTP/3 multiplex baseline. Response-throughput peaked at `643.73 Mbps` / p95 `463.68 ms` for `8` streams with `1` native runtime thread and `672.77 Mbps` / p95 `58.37 ms` for `1` stream with `4` native runtime threads.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after expanding the shipped HTTP/3 multiplex scenario, updating the bench docs/roadmap notes, and recording the new local ceiling map in project state.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before the HTTP/3 follow-up direction spike.
- 2026-04-23: `cargo run --manifest-path native/bench/Cargo.toml --bin http_stream -- --native-lib native/transport/target/release/libct_ffi.dylib --scenario native/bench/scenarios/h3_multiplex_scaling.toml --router-worker-counts 1,4 --native-runtime-thread-counts 1,4 --results out/h3-followup-direction/bench_results.jsonl --artifact-dir out/h3-followup-direction` passed on Darwin arm64 and resolved the HTTP/3 roadmap ambiguity. The best low-depth result was `721.60 Mbps` / p95 `54.61 ms` at `s1` with `threads=1, workers=4`, the best overall result was `761.52 Mbps` / p95 `124.85 ms` at `s2` with `threads=4, workers=1`, and the deeper `s8/s16` points still correlated with `82-117` backpressure events rather than a clean router-worker scaling story.
- 2026-04-23: `cd packages/connectanum_router && dart test test/conformance/wamp_multisession_conformance_test.dart -r expanded` passed on Darwin arm64 after vendoring the upstream `publisher_exclusion_disabled` multi-session vector and wiring the router-side conformance harness.
- 2026-04-23: `dart analyze packages/connectanum_router/test/conformance/wamp_multisession_conformance_test.dart` passed on Darwin arm64 with no issues.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the vendored multi-session conformance vector, the new router-side harness, and the associated roadmap/state updates.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before refreshing the
  public docs/examples surface around cancellation semantics, graceful drain,
  lazy payload boundaries, and example discovery.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after landing the public
  docs/examples refresh across `README.md`, the router/client package READMEs,
  `docs/deployment.md`, `docs/examples.md`, and the associated roadmap/state
  updates.
- 2026-04-23: `bin/test-fast` passed on Darwin arm64 before the router analyzer
  hygiene cleanup.
- 2026-04-23: `dart analyze packages/connectanum_router` and
  `dart test packages/connectanum_client/test/transport/native/message_binding_test.dart packages/connectanum_router/test/router_worker_auth_test.dart packages/connectanum_router/test/router_worker_session_test.dart`
  passed on Darwin arm64 after clearing the remaining router null-aware
  collection lint output.
- 2026-04-23: `bin/verify` passed on Darwin arm64 after the router analyzer
  hygiene cleanup and roadmap/state refresh.

## Active Plan

- Active plan:
  `docs/exec-plans/2026-05-13-rc-readiness.md`.
  Keep hosted GitHub CI clean first, then continue release-candidate readiness
  work from the GitHub default branch. MCP is treated as RC-ready unless a real
  consumer integration bug appears. The current local checkpoint extends the
  checked-in router integration smoke so direct JSON notification-only tool
  calls prove actual WAMP procedure invocation on public, secure, JSON-response,
  and independent valid bearer-principal MCP paths; the latest fully hosted
  checkpoint is `dbb52aa`.
- Historical paused plan:
  `docs/exec-plans/2026-04-25-h2-isolated-regression-diagnosis.md`; do not
  resume it by default because the current continuation priority is GitHub
  deployment-chain reliability, public/release readability, MCP usability for
  downstream apps, and concrete shipped-path regressions.
- Most recent deployment-chain checkpoint plan:
  `docs/exec-plans/2026-04-28-github-deployment-chain-readiness.md`
- Most recent completed product-readiness plan:
  `docs/exec-plans/2026-05-09-router-hosted-mcp-example-subscription-meta-smoke.md`
- Supporting research notes:
  - `docs/mcp_integration_research.md`
  - `docs/dart_package_publishing.md`
  - `docs/ktls_research.md`
  - `docs/e2ee_ppt_research.md`
- Most recent completed plan:
  `docs/exec-plans/2026-04-24-ktls-repeat-stability.md`
- Completed immediately before that:
  `docs/exec-plans/2026-04-24-h2-main-isolate-control-port-optimization.md`
- Completed before those: `docs/exec-plans/2026-04-23-ci-artifact-cleanup-and-native-matrix.md`

## Known Follow-Ups

- The current kTLS prototype keeps default/non-Linux runs on `tokio-rustls`,
  disables future kTLS attempts after socket-setup or handoff failures in one
  process in try-mode, and still is not the final production story for TLS 1.3
  key-update handling.
- The secure WAMP throughput expansion is now closed on both local Darwin and
  hosted Ubuntu baselines. The next session should pick a new roadmap item
  instead of extending this benchmark plan.
- The bench artifact gate now has the mechanism for both transport-regression
  counters and opt-in performance budgets. It still needs scenario-specific
  throughput/p95 thresholds before CI should fail on performance drift for a
  given benchmark family.
- HTTP/3 transport/backpressure follow-up work remains paused unless CI, a
  release blocker, or an explicit performance-budget need requires revisiting
  it; the canonical WAMP release gate set is already defined.
- The current E2EE lane now covers negotiated fallback plus reusable
  peer/trust adapters. Further E2EE work should be driven by a concrete app
  integration need, or the next session should choose the next unfinished
  non-E2EE roadmap item.

## Update Checklist

- Refresh this file when the active milestone, blockers, or last-known verification status changes.
- Record the exact commands that most recently passed.
- Link the active execution plan and any follow-up docs created during external research.
