# Exec Plan: macos-remote-auth-tls

Status: completed
Owner: Codex
Created: 2026-04-21
Last updated: 2026-04-21

## Goal

Make `packages/connectanum_router/test/remote_auth_integration_test.dart` pass on this macOS machine by fixing the local mTLS fixture set instead of weakening certificate verification.

## Scope

- In scope: diagnosing the macOS TLS handshake failure, rotating the remote-auth test certificates, and refreshing checked-in project state.
- Out of scope: changing the remote auth protocol, adding insecure macOS test exceptions, or modifying CI workflow structure.

## Files Expected To Change

- `packages/connectanum_router/test/certs/remote_auth_ca_cert.pem`
- `packages/connectanum_router/test/certs/remote_auth_server_cert.pem`
- `packages/connectanum_router/test/certs/remote_auth_server_key.pem`
- `packages/connectanum_router/test/certs/remote_auth_client_cert.pem`
- `packages/connectanum_router/test/certs/remote_auth_client_key.pem`
- `docs/project_state.md`

## Preconditions

- `openssl` and the macOS `security` CLI are available locally.
- The remote-auth test fixtures are allowed to rotate as long as file names and SAN coverage stay stable.

## Plan

1. Reproduce the failing remote-auth integration test and verify whether the macOS platform trust evaluator rejects the bundled server certificate.
2. Regenerate the remote-auth CA/server/client fixture set with Apple-compatible leaf certificate lifetimes while preserving `localhost` and `127.0.0.1` coverage.
3. Re-run the remote-auth integration test plus the root verification entrypoints and update the checked-in project state.

## Verification

- `security verify-cert -c packages/connectanum_router/test/certs/remote_auth_server_cert.pem -r packages/connectanum_router/test/certs/remote_auth_ca_cert.pem -p ssl -s localhost`
- `dart test packages/connectanum_router/test/remote_auth_integration_test.dart --concurrency=1 -r expanded`
- `bin/test-fast`
- `bin/verify`

## Decision Log

- 2026-04-21: Reproduced the failure as a macOS `CERTIFICATE_VERIFY_FAILED: application verification failure` during the remote-auth rawsocket TLS handshake.
- 2026-04-21: Confirmed with `security verify-cert` that the previous bundled server certificate was rejected by macOS, while a freshly minted short-lived replacement verified successfully.
- 2026-04-21: Fixed the issue by rotating the remote-auth fixture CA and both leaf certificates instead of disabling certificate verification in tests.

## Handoff

- The remote-auth integration suite now passes on Darwin arm64 with normal certificate verification enabled.
- `bin/test-fast` and `bin/verify` both pass after the fixture rotation.
- The remote-auth server fixture now has an Apple-compatible leaf lifetime and still covers both `localhost` and `127.0.0.1`.
