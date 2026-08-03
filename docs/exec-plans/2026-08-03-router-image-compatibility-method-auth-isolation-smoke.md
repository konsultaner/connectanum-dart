# Exec Plan: Router Image Compatibility Method Auth Isolation Smoke

## Status

Completed.

## Goal

Prove that missing and unknown bearer credentials cannot use GET/SSE or DELETE
to poll or terminate a real protected MCP `2025-11-25` Streamable HTTP session
in the packaged Router Image, while the authenticated owner retains the full
pub/sub and session lifecycle.

## Scope

- Reuse the real bearer-protected compatibility pub/sub session in the
  canonical loaded Router Image smoke.
- Send GET and DELETE requests carrying the live `MCP-Session-Id` first without
  a bearer and then with an unknown bearer.
- Require HTTP 401, a Bearer challenge, the compatibility protocol response
  header, and no response `MCP-Session-Id` from every rejected method.
- Continue the authenticated owner through publish, poll, unsubscribe, and
  DELETE so the smoke proves rejected callers neither consumed events nor
  terminated the session.
- Emit one bounded hosted-log marker for missing/unknown bearer GET/DELETE
  isolation.

## Non-Goals

- Change router authentication policy or Streamable session ownership.
- Rework revoked-token lifecycle coverage or token refresh behavior.
- Add authorization checks to the anonymous public MCP route.
- Duplicate the complete generated-consumer session-reuse matrix.

## Verification

- Pre-change `bin/test-fast`.
- A focused failing Router Image method-auth contract before runner
  implementation.
- The complete Router Image contract suite and canonical runner against a
  freshly built current-source local image, followed by the canonical
  Linux/amd64 image in the hosted Router Image dry run.
- Full `bin/verify` before handoff.
- Exact-head CI and Router Image dry run, relevant package/native/WAMP
  evidence, hosted log inspection, and the comprehensive strict
  deployment-chain audit after the implementation push.

## Progress

- 2026-08-03: Selected after the modern GET/DELETE live-session isolation
  checkpoint completed. Generated-consumer coverage already proves bearerless
  secure-route GET/DELETE isolation, while the canonical loaded-image smoke
  only rejects a bearerless POST before proving the authenticated session
  remains usable.
- 2026-08-03: Pre-change `bin/test-fast` passed. The focused Router Image
  contract then failed first because the runner had no protected compatibility
  GET/DELETE bearer-isolation helper.
- 2026-08-03: The loaded-image runner now probes missing and unknown bearer
  credentials through GET and DELETE with the real compatibility session ID.
  Every rejection must return HTTP 401, a Bearer challenge, the negotiated
  compatibility protocol header, and no response session ID before the valid
  owner continues its complete lifecycle.
- 2026-08-03: Python compilation, all 21 Router Image contracts, and the
  complete runner against a freshly built current-source Linux/arm64 image
  passed. The raw marker records missing/unknown bearer GET/DELETE isolation,
  and all four globally activated package-client evidence lines remain green.
  Docker Desktop's credential helper blocked the local tagged-base refresh, so
  the canonical Linux/amd64 Dockerfile build remains part of the exact-head
  hosted Router Image evidence.
- 2026-08-03: Full `bin/verify` passed formatting, all Rust and FFI suites,
  360 core tests, 94 MCP tests, the complete 193-case MCP/client authorization
  suite, all 96 benchmark tests with live WAMP workloads, every isolated and
  globally activated consumer smoke, the complete 380-case router suite, 13
  native-forwarding follow-ups, and Chrome/Dart2Wasm coverage.
- 2026-08-03: Implementation commit `8698877` was pushed to GitLab and GitHub.
  Exact-head CI `30857570369` passed Fast Checks, Full Verify, Dart VM
  Coverage, Codecov upload, the clean hosted-log scan, and coverage artifact
  `8873442353`. Router Image dry run `30857594325` passed the canonical
  Linux/amd64 loaded-image smoke and multi-architecture dry build, then
  uploaded preview artifact `8873068535`. Its log contains
  `compatibility_method_auth_isolated=true missing_bearer=true unknown_bearer=true compatibility_get=true compatibility_delete=true`
  plus exactly four public/protected package evidence lines. The retained
  package publish dry run, native release dry run, and WAMP profile benchmark
  remain relevant because no sensitive inputs changed. The comprehensive
  strict deployment-chain audit exited zero with every required gate clean.
