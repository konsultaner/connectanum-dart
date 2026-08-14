# MCP 2026-07-28 Authorization Response Issuer

Date: 2026-08-14

## Sources

- [MCP 2026-07-28 authorization specification](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/authorization/index.mdx)
- [RFC 9207: OAuth 2.0 Authorization Server Issuer Identification](https://www.rfc-editor.org/rfc/rfc9207.html)

## Finding

The stable MCP authorization flow requires clients to record the validated
authorization-server issuer and validate the RFC 9207 `iss` parameter on the
authorization response before using a code or displaying OAuth error data.
Authorization Server Metadata advertises the parameter through
`authorization_response_iss_parameter_supported`.

The required client matrix is:

- When the metadata flag is `true`, `iss` must be present and must exactly
  match the recorded issuer.
- When the flag is `false` or absent, an absent `iss` remains compatible.
- Whenever `iss` is present, it must exactly match even if the server did not
  advertise the parameter.
- Comparison is a simple string comparison. Scheme or host casing, default
  ports, trailing slashes, and percent encoding must not be normalized.
- The same validation applies to success and error callbacks. A mismatch must
  reject the response before error data is surfaced.

## Implementation Direction

- Parse the metadata flag as an optional boolean and preserve it in the
  validated metadata JSON used by pending authorization transactions.
- Expose the exact validated issuer identifier separately from the convenient
  parsed `Uri` representation.
- Treat `iss` as a singleton controlled callback parameter. Validate it before
  redirect/state/code/error processing and omit the callback URI and OAuth
  error fields from issuer-validation exceptions.
- Exercise advertised-required, optional-present, exact-string mismatch,
  duplicate, and error-callback behavior plus a public IO/package loopback
  flow.
