# MCP 2026-07-28 pre-registered client issuer binding

Checked: 2026-08-15

Primary sources:

- MCP `2026-07-28` Authorization, Client Registration, and Authorization
  Server Discovery specification pages.
- SEP-2352, authorization-server binding and migration.

## Normative direction

- Pre-registered credentials and persisted Dynamic Client Registration
  credentials are specific to the authorization server that issued them.
- Clients must associate those credentials with the exact issuer identifier and
  must not reuse them after Protected Resource Metadata selects another issuer.
- A mismatch should be surfaced instead of silently trying the credentials.
- Client ID Metadata Document client IDs are portable across authorization
  servers because the HTTPS document is resolved by each server on demand.

## Connectanum direction

- Token-endpoint authentication records carry an optional exact issuer stamp.
- Public or confidential pre-registered identities require validated
  authorization-server metadata when constructed.
- Dynamic registrations propagate their persisted validated issuer into the
  authentication record they expose.
- An unstamped identity is accepted only as a portable HTTPS Client ID Metadata
  Document identity against a server that advertises CIMD support.
- Authorization-code exchange, refresh, and revocation validate this boundary
  before opening a request and use redacted static failures.
- Secret persistence remains out of scope.
