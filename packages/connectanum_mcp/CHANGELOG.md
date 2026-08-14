# Changelog

## 3.0.0-beta

- Join the synchronized Connectanum 3.0 beta package graph.
- Complete router-hosted MCP support for authenticated Streamable HTTP,
  direct JSON tools and Meta APIs, resources, prompts, and WAMP pub/sub.
- Add typed prompt/resource-template `completion/complete` support with bounded
  results, server capability advertisement, router-configured candidates, and
  authorization-safe standard/direct/stateless dispatch.
- Advertise procedure-specific named JSON parameters and lossless result
  schemas for all standard WAMP Meta API tools while retaining raw WAMP and
  legacy direct-JSON compatibility forms.
- Let readable resource templates resolve concrete Level 1 URI expressions,
  pass decoded variables to their callbacks, and preserve exact-resource
  precedence.
- Expose deterministic readable-template matches so router hosts can apply the
  same concrete-URI resolution to reads and resource subscriptions.
- Share one public Level 1 resource-URI-template parser between server matching
  and consumer expansion, and exercise advertised-template reads from the
  packaged router-hosted client.
- Make the packaged router-hosted client traverse opaque catalog cursors when
  selecting tools, resources, prompts, and resource templates through typed
  and raw direct JSON or compatibility Streamable HTTP calls.
- Add bounded, filter-bound pagination for `connectanum.api.list` and make the
  packaged client traverse WAMP procedure/topic pages through typed, raw
  method, batch, direct JSON, and compatibility Streamable HTTP paths.
- Add MCP 2026 form-elicitation MRTR requests, scoped capability enforcement,
  WAMP detail bridging, bounded client retries, and direct JSON support.
- Preserve optional MCP result `_meta` across ordinary, error, text, and
  `input_required` results, including JSON-compatible WAMP result details.
- Accept every JSON-compatible `structuredContent` value in public tool
  results, including arrays, scalars, and explicit null, and expose field
  presence separately from its value.
- Re-export the public MCP OAuth authorization, Client ID Metadata Document,
  dynamic client registration, token refresh, and revocation lifecycle through
  the IO entrypoint.
- Exercise RFC 9207 authorization-response issuer validation through the
  public IO OAuth loopback lifecycle.
- Re-export the native OAuth loopback callback listener through the IO
  entrypoint and exercise it in the public authorization lifecycle.
- Re-export validated in-place OAuth grant replacement so consumers can retry
  insufficient-scope operations on the same Streamable HTTP session.
- Re-export in-place router HTTP-auth grant replacement for refreshes that
  continue on an established Streamable HTTP session.
- Add isolated server, client, executable, and consumer application smokes.
- Export the `2025-03-26` compatibility fallback for legacy HTTP requests that
  omit `MCP-Protocol-Version`.
- Let the public router-hosted client executable run either the session-era
  Streamable HTTP lifecycle or the `2026-07-28` stateless discovery lifecycle,
  including direct JSON tools, WAMP metadata, and pub/sub coverage.
- Add reusable `McpWampPubSubState` so applications can regenerate a declared
  WAMP API catalog without orphaning buffered subscription handles.
- Add topic reconciliation for retained WAMP pub/sub state so hosts can revoke
  no-longer-authorized handles and in-flight subscribes with retry-safe
  mandatory cleanup.

## 0.1.0

- Added MCP server primitives, stdio transport support, router-hosted Streamable HTTP entrypoints, and WAMP-backed tool integration helpers.
