# connectanum_mcp

Model Context Protocol (MCP) server primitives and stdio transport support for
Connectanum applications.

This package is intentionally narrow in its first slice. It provides:

- JSON-RPC response/error helpers for MCP server messages.
- Typed server info and capability objects.
- A small in-memory `McpServer` lifecycle implementation.
- A callback-backed `McpToolRegistry` with `tools/list`, optional cursor
  pagination, and `tools/call`.
- A newline-delimited stdio transport adapter for local MCP clients.
- A WAMP-backed tool delegate for forwarding MCP tool calls to Connectanum
  procedures through an existing client `Session`.

The first supported protocol revision is `2025-11-25`, matching the current
MCP `latest` specification checked on 2026-04-23.

## Current Scope

The package provides the in-memory server core, a stdio adapter, callback tools,
and WAMP-backed procedure delegation. It does not yet provide Streamable HTTP
or router-backed transport adapters. Tool execution errors are returned as MCP
tool results with `isError: true`; malformed requests, parse failures, unknown
methods, and invalid parameters remain JSON-RPC protocol errors.

## Minimal Example

```dart
import 'package:connectanum_mcp/connectanum_mcp.dart';

final server = McpServer(
  serverInfo: const McpServerInfo(name: 'example', version: '0.1.0'),
  tools: [
    McpTool(
      name: 'echo',
      description: 'Echoes text arguments.',
      handler: (request) {
        final text = request.arguments['text'] as String? ?? '';
        return McpToolResult.text(text, structuredContent: {'echo': text});
      },
    ),
  ],
);
```

Transport adapters should call `server.handleMessage(...)` with decoded
JSON-RPC objects and serialize the returned map when a response is produced.

Set `toolListPageSize` on `McpServer` to return large tool lists in stable
pages. Clients should pass the returned `nextCursor` back unchanged; malformed
or stale cursors are rejected as MCP `invalidParams` errors.

## Stdio Example

Run the example server with:

```bash
dart run packages/connectanum_mcp/example/stdio_echo_server.dart
```

The stdio transport reads one UTF-8 JSON-RPC message per line from `stdin` and
writes one JSON-RPC response per line to `stdout`. Notifications do not produce
response lines.

## WAMP Tool Delegation

Use `McpWampToolDelegate.session(...)` when an MCP tool should call an existing
Connectanum WAMP procedure:

```dart
final tool = McpWampToolDelegate.session(
  session: session,
  procedure: 'app.echo',
).toTool(
  name: 'echo',
  description: 'Calls app.echo through the current WAMP session.',
);
```

By default, MCP tool arguments are forwarded as WAMP keyword arguments. WAMP
results are returned as a lossless JSON-shaped MCP tool result containing
`arguments`, `argumentsKeywords`, and `details` when present. Custom argument
builders and result mappers can override that mapping for application-specific
tool contracts.
