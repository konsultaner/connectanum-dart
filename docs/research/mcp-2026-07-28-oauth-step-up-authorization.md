# MCP 2026-07-28 OAuth Step-Up Authorization

Date: 2026-08-14

## Question

What should a public MCP client derive from a runtime
`insufficient_scope` response before asking a user to authorize broader access?

## Stable Protocol Findings

- A protected MCP resource reports insufficient runtime authorization with HTTP
  403 and a Bearer challenge containing `error="insufficient_scope"`, a `scope`
  parameter, and protected-resource metadata.
- Clients acting for a user should perform step-up authorization after that
  response.
- The new authorization request must include the union of the scopes requested
  during the previous authorization request and the authoritative scopes from
  the runtime challenge.
- Clients must bound step-up attempts and avoid retry loops.

## Implementation Direction

- Accept only an unambiguous HTTP 403 Bearer `insufficient_scope` challenge
  with non-empty valid OAuth scope tokens.
- Bind the new authorization request to the current validated grant's
  authorization server, client identifier, and canonical MCP resource rather
  than trusting those values to response-controlled data.
- Preserve the current grant scopes, accept caller-supplied scopes from the
  preceding authorization transaction, and add each challenge scope once.
- Return a request value only. Browser interaction, callback handling, token
  exchange, grant replacement, operation retry, and retry limits remain owned
  by the consumer application.
- Reject malformed or ambiguous challenges with a redacted public exception so
  response-controlled scope text is not copied into logs.

## Source

- MCP 2026-07-28 authorization, Step-up Authorization:
  <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization#step-up-authorization>
