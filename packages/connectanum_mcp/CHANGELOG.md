# Changelog

## 3.0.0-beta

- Join the synchronized Connectanum 3.0 beta package graph.
- Complete router-hosted MCP support for authenticated Streamable HTTP,
  direct JSON tools and Meta APIs, resources, prompts, and WAMP pub/sub.
- Re-export the public MCP OAuth authorization, Client ID Metadata Document,
  dynamic client registration, token refresh, and revocation lifecycle through
  the IO entrypoint.
- Re-export the native OAuth loopback callback listener through the IO
  entrypoint and exercise it in the public authorization lifecycle.
- Re-export validated in-place OAuth grant replacement so consumers can retry
  insufficient-scope operations on the same Streamable HTTP session.
- Add isolated server, client, executable, and consumer application smokes.

## 0.1.0

- Added MCP server primitives, stdio transport support, router-hosted Streamable HTTP entrypoints, and WAMP-backed tool integration helpers.
