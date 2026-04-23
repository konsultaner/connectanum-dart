# connectanum_mcp

Transport-independent Model Context Protocol (MCP) server primitives for
Connectanum applications.

This package is intentionally narrow in its first slice. It provides:

- JSON-RPC response/error helpers for MCP server messages.
- Typed server info and capability objects.
- A small in-memory `McpServer` lifecycle implementation.
- A callback-backed `McpToolRegistry` with `tools/list` and `tools/call`.

The first supported protocol revision is `2025-11-25`, matching the current
MCP `latest` specification checked on 2026-04-23.

## Current Scope

The package does not yet provide stdio, Streamable HTTP, or router-backed
transport adapters. Those are planned after the in-memory protocol surface is
stable. Tool execution errors are returned as MCP tool results with
`isError: true`; malformed requests, unknown methods, and invalid parameters
remain JSON-RPC protocol errors.

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
