# Exec Plan: MCP Consumer CORS Preflight Smoke

Status: complete; hosted CI and deployment-chain evidence clean
Owner: Codex
Created: 2026-05-12
Last updated: 2026-05-12

## Goal

Make router-hosted MCP endpoints usable from browser-like downstream
applications by returning explicit CORS metadata for configured allowed origins
and by handling MCP preflight requests on public and bearer-protected routes
without requiring bearer credentials or Streamable HTTP session state.

## Scope

- In scope: adding CORS response headers for allowed-origin router-hosted MCP
  responses, including exposed MCP session/protocol headers.
- In scope: handling `OPTIONS` preflight requests on public and
  bearer-protected MCP routes after Origin validation but before auth/session
  resolution.
- In scope: scoping the native listener-side bearer bypass to MCP-derived CORS
  preflight route config so non-MCP HTTP routes keep their existing bearer
  behavior.
- In scope: generated consumer package smoke coverage for allowed and
  disallowed preflight requests plus allowed direct JSON response CORS headers.
- Out of scope: changing default Origin policy semantics, adding
  application-specific hosts, or broadening non-MCP HTTP route CORS behavior.

## Files Expected To Change

- `packages/connectanum_router/lib/src/router/router_instance/router_mcp.dart`
- `packages/connectanum_router/lib/src/router/config/http_route_transport_auth.dart`
- `packages/connectanum_router/lib/src/router/router_instance/router_binding.dart`
- `packages/connectanum_router/test/http_route_transport_auth_test.dart`
- `native/transport/ct_core/src/config.rs`
- `native/transport/ct_core/src/lib.rs`
- `native/transport/ct_ffi/src/tests/listen_flow.rs`
- `bin/common.sh`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-12-mcp-consumer-cors-preflight-smoke.md`
- Existing docs-only hosted-evidence updates from the Origin policy slice remain
  bundled with this implementation commit.

## Preconditions

- Serena project onboarding is complete for this repository.
- The latest pushed branch checkpoint `6dfcb87` has clean hosted CI and
  deployment-chain evidence; remaining strict-audit gaps are operator-side
  release-hardening items.
- Pre-change `bin/test-fast` passed on 2026-05-12.

## Plan

1. Add MCP-specific CORS response helpers that echo configured allowed origins,
   expose MCP session/protocol headers, and echo requested preflight headers.
2. Handle `OPTIONS` for router-hosted MCP routes before bearer/session
   resolution while preserving Origin rejection for disallowed origins.
3. Extend the generated consumer package smoke to prove public and secure MCP
   preflight succeeds for the neutral allowed origin, disallowed preflight is
   rejected, and actual direct JSON responses expose the expected CORS headers.
4. Run focused generated smoke, `bin/test-fast`, and `bin/verify`; then push
   and collect hosted deployment-chain evidence.

## Verification

- Pre-change `bin/test-fast` passed on 2026-05-12.
- `dart test packages/connectanum_router/test/http_route_transport_auth_test.dart`
  passed on 2026-05-12.
- `cargo test --manifest-path native/transport/ct_ffi/Cargo.toml --features
  ffi-test http_transport_auth_allows_bearerless_cors_preflight_when_configured
  -- --nocapture` passed on 2026-05-12.
- Focused generated consumer smoke (`source bin/common.sh;
  run_mcp_consumer_package_smoke`) passed on 2026-05-12.
- Post-change `bin/test-fast` passed on 2026-05-12.
- Full local `bin/verify` passed on 2026-05-12.
- Commit `e35cab0` (`fix: allow mcp cors preflight`) was pushed to both
  configured remotes on 2026-05-12.
- GitHub Actions `CI` run `25735530396` passed on `e35cab0`: `Fast Checks`
  completed successfully at 2026-05-12T12:55:04Z and `Full Verify` completed
  successfully at 2026-05-12T13:01:33Z.
- GitHub Actions `Dart Package Publish Dry Run` run `25735530321`,
  `kTLS Validation` run `25735530322`, and `WAMP Profile Benchmarks` run
  `25735530337` completed successfully for `e35cab0`.
- `bin/audit-github-deployment-chain --branch add-router --require-clean-latest-ci --require-clean-latest-ci-logs --show-dart-package-publish-dry-run --require-clean-dart-package-publish-dry-run`
  passed on 2026-05-12. The audit found latest CI clean, latest CI log scan
  clean, and a clean relevant Dart package publish dry-run for `e35cab0`.
- Strict deployment-chain audit still fails only known operator-side
  release-hardening gaps: branch protection/required checks are not configured,
  `.github/workflows/router-image.yml` is not yet visible from the default
  branch, and the router GHCR package is not visible.

## Decision Log

- 2026-05-12: Continue MCP downstream-readiness hardening on browser-like
  consumer requirements. The previous slice proved configured Origin policy
  enforcement through public clients; this slice makes the same endpoints return
  browser-readable CORS metadata and lets protected MCP routes answer preflight
  without leaking auth/session assumptions.
- 2026-05-12: The focused smoke showed protected preflight was rejected at the
  native listener-side bearer gate before Dart MCP handling. The implementation
  therefore carries a route transport-auth flag for MCP CORS preflight and
  requires the actual preflight header shape before skipping the bearer check.

## Handoff

Implementation is complete and pushed. Local verification, hosted CI, hosted
log scan, and the non-strict deployment-chain audit are clean for `e35cab0`.
The only remaining strict-audit gaps are operator-side release-hardening items.
