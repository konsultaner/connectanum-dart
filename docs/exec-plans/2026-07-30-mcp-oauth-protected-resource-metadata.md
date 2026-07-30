# Exec Plan: MCP OAuth Protected Resource Metadata

## Status

Complete.

## Goal

Make protected router-hosted MCP endpoints discoverable by standards-aware MCP
clients without replacing the existing Connectanum HTTP authentication bridge.

## Scope

- Add validated route configuration for OAuth Protected Resource Metadata.
- Serve configured metadata publicly from the MCP endpoint through JSON content
  negotiation while retaining bearer enforcement for MCP traffic.
- Add the configured `resource_metadata` URL to missing-token and invalid-token
  `WWW-Authenticate` challenges.
- Cover configuration failures and the live native HTTP security boundary.
- Document the operator contract and the remaining external OAuth authorization
  server responsibility.

## Non-Goals

- Implement an OAuth 2.1 authorization server in the router.
- Replace ticket, WAMP-CRA, SCRAM, or bearer-grant authentication.
- Implement an OAuth browser authorization flow in the Dart MCP client.

## Verification

- `bin/test-fast`
- Focused router config and native MCP security tests
- `dart analyze packages/connectanum_router`
- `bin/verify`

## Progress

- 2026-07-30: Confirmed the current MCP authorization specification requires
  protected-resource discovery for HTTP authorization.
- 2026-07-30: Pre-change `bin/test-fast` passed.
- 2026-07-30: Added failing configuration and live native HTTP regressions.
- 2026-07-30: Implemented strict metadata validation, public JSON discovery,
  and standard bearer challenge metadata while preserving Streamable HTTP
  bearer enforcement.
- 2026-07-30: The first full verifier exposed an overly narrow CORS test
  fixture on protected HTTP/3 routes. Restored the production same-origin
  default, reran both protected HTTP/3 regressions against the FFI test
  library, and completed a clean `bin/verify`.
- 2026-07-30: Final review narrowed the discovery exemption to bearer
  presence so configured TLS and mTLS requirements remain enforced. Added an
  insecure-listener regression and completed the final clean `bin/verify`.
