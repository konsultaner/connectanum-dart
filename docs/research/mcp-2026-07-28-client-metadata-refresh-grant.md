# MCP 2026-07-28 Client Metadata Refresh Grant

Date: 2026-08-14

## Question

Should a public MCP Client ID Metadata Document advertise `refresh_token` when
the client implements refresh-token exchange and persistence?

## Stable Protocol Findings

- MCP clients that desire refresh tokens should include `refresh_token` in
  their `grant_types` client metadata.
- A client may request the `offline_access` scope when the authorization server
  advertises it, but refresh-token issuance remains at the authorization
  server's discretion.
- Client ID Metadata Documents use the registered OAuth client metadata fields,
  including `grant_types`, and MCP requires public clients to use
  `token_endpoint_auth_method: none` unless they adopt an allowed asymmetric
  authentication mechanism.
- The existing Connectanum Dynamic Client Registration request already
  advertises both `authorization_code` and `refresh_token`. The preferred
  Client ID Metadata Document path advertises only `authorization_code` even
  though its returned client authentication is accepted by the public refresh,
  persistence, and revocation APIs.

## Implementation Direction

- Public Client ID Metadata Documents should advertise `refresh_token` by
  default so their published capabilities match the shipped client behavior
  and the fallback Dynamic Client Registration path.
- Consumers that do not want refresh credentials should be able to opt out and
  publish only `authorization_code`.
- Do not add `offline_access` implicitly. Callers already control requested
  scopes, and silently broadening them would conflict with MCP's least-
  privilege scope-selection guidance.
- Keep the metadata immutable and cover both shapes through the public package
  boundary.

## Sources

- MCP 2026-07-28 authorization, Refresh Tokens:
  <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization#refresh-tokens>
- MCP 2026-07-28 Client Registration:
  <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/client-registration>
- OAuth Client ID Metadata Document draft used by MCP 2026-07-28:
  <https://datatracker.ietf.org/doc/html/draft-ietf-oauth-client-id-metadata-document-00>
