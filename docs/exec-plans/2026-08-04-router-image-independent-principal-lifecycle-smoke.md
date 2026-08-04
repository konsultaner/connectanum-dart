# Exec Plan: Router Image Independent Principal Lifecycle Smoke

## Status

Completed.

## Goal

Prove that the second valid bearer principal used for compatibility-session
isolation can independently use the packaged Router Image after cross-principal
reuse is rejected, without mutating the primary owner's live session.

## Scope

- Keep the existing valid-other-principal POST, GET, and DELETE rejection
  matrix against the primary protected compatibility session.
- Use the second principal's router-issued bearer for modern discovery, direct
  WAMP registration/session metadata, and a complete direct JSON pub/sub
  lifecycle without MCP session state.
- Initialize a distinct compatibility Streamable HTTP session for the second
  principal and complete subscribe, publish, poll, unsubscribe, and DELETE.
- Require the independently created session ID to differ from the primary
  owner's live session ID.
- Continue the primary owner through publish, poll, unsubscribe, and DELETE so
  the second principal's successful lifecycle demonstrably preserves it.
- Retain both token revocations, the four bounded package-client evidence
  lines, and add one bounded independent-principal marker for hosted logs.

## Non-Goals

- Change router authentication, authorization, or session ownership behavior.
- Duplicate the full resource, prompt, listener, and authentication-lifecycle
  matrix already exercised by the globally activated package client.
- Add another protected route or another credential type.
- Change public-route behavior or MCP protocol negotiation.

## Verification

- Pre-change `bin/test-fast`.
- A focused failing Router Image independent-principal contract before runner
  implementation.
- Python compilation and the complete Router Image contract suite.
- The canonical runner against a freshly built current-source local image,
  followed by the canonical Linux/amd64 image in the hosted Router Image dry
  run.
- Full `bin/verify` before handoff.
- Exact-head CI and Router Image dry run, relevant package/native/WAMP
  evidence, hosted log inspection, and the comprehensive strict deployment
  chain audit after the implementation push.

## Progress

- 2026-08-04: Selected after the packaged image proved that a second valid
  bearer cannot reuse the primary principal's compatibility session. Native
  router, public example, and generated consumer coverage already prove the
  stronger independent direct JSON and Streamable lifecycle; the canonical
  loaded-image evidence stopped after reuse rejection.
- 2026-08-04: Pre-change `bin/test-fast` passed. The focused Router Image
  contract then failed first because the runner had no independent-principal
  lifecycle helper.
- 2026-08-04: The loaded-image runner now uses the second principal's bearer
  for modern discovery, direct WAMP registration/session metadata, and a
  complete direct JSON pub/sub lifecycle. It then creates a distinct
  compatibility session, completes pub/sub and DELETE, and lets the primary
  owner finish its original lifecycle. Python compilation and all 25 Router
  Image contracts pass.
- 2026-08-04: The complete runner passed against a fresh current-source
  Linux/amd64 image assembled from the previously verified cached canonical
  build inputs. The normal Dockerfile build could not reach Docker Hub's
  Dockerfile-frontend metadata locally, so the canonical hosted Linux/amd64
  build remains required before closure. The local loaded-image log contains
  the bounded independent-principal marker and exactly four public/protected
  package-client evidence lines.
- 2026-08-04: Full `bin/verify` passed formatting, all Rust and FFI suites,
  360 core tests, 94 MCP tests, 193 MCP/client authorization cases, all 96
  benchmark tests with live WAMP workloads, every isolated and globally
  activated consumer smoke, the complete 380-case router suite, 13
  native-forwarding follow-ups, and Chrome/Dart2Wasm coverage.
- 2026-08-04: Implementation commit `8d241b1` was pushed to GitLab and GitHub.
  Exact-head CI `30866566807` passed Fast Checks, Dart VM Coverage, Full
  Verify, Codecov upload, the clean hosted-log scan, and coverage artifact
  `8876620154`. Router Image dry run `30866579221` passed its canonical
  Linux/amd64 current-source build, loaded-image runtime smoke, non-publishing
  multi-architecture build, skipped GHCR login, and clean annotations, and
  uploaded preview artifact `8876322227`. Its hosted log contains exactly four
  public/protected package-client evidence lines and the bounded
  `independent_principal_ready=true direct_meta=true direct_pubsub=true
  sessionless_direct=true distinct_streamable_session=true
  streamable_pubsub=true owner_preserved=true` marker. The package publish,
  native release, and WAMP profile evidence remains relevant because no
  corresponding sensitive inputs changed. The comprehensive strict
  deployment-chain audit exited zero with every required gate ready; RC
  tagging and prerelease creation remain separate approval-gated release
  actions.
