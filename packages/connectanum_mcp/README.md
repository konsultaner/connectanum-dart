# connectanum_mcp

`connectanum_mcp` lets a Dart or Flutter application expose a small MCP server
without taking a dependency on a private bridge protocol. It is designed for the
first production shape needed by Connectanum apps: local stdio MCP servers and
MCP tools backed by normal Connectanum WAMP procedures.

The supported MCP protocol revision is `2025-11-25`. The package intentionally
implements a narrow, stable subset first:

- lifecycle negotiation with `initialize` and `notifications/initialized`
- `tools/list`, including optional cursor pagination for large tool catalogs
- `tools/call`, including structured tool results
- newline-delimited stdio transport for local MCP clients
- WAMP-backed tool delegation through an existing `connectanum_client` session

It does not yet ship Streamable HTTP, router-hosted MCP sessions, prompts,
resources, sampling, or tasks. Tool execution failures are returned as MCP tool
results with `isError: true`; malformed JSON-RPC messages, unknown methods, and
invalid parameters remain protocol errors.

## Quick Start

Create an in-memory server and register tools:

```dart
import 'package:connectanum_mcp/connectanum_mcp.dart';

final server = McpServer(
  serverInfo: const McpServerInfo(name: 'example', version: '0.1.0'),
  tools: [
    McpTool(
      name: 'echo',
      description: 'Echoes text arguments.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
      },
      handler: (request) {
        final text = request.arguments['text'] as String? ?? '';
        return McpToolResult.text(text, structuredContent: {'echo': text});
      },
    ),
  ],
);
```

Transport adapters call `server.handleMessage(...)` with decoded JSON-RPC
objects and serialize the returned map when a response is produced. MCP
notifications return `null`.

Large tool catalogs can be paged by setting `toolListPageSize`:

```dart
final server = McpServer(
  serverInfo: const McpServerInfo(name: 'tools', version: '1.0.0'),
  toolListPageSize: 50,
  tools: tools,
);
```

Clients should pass `nextCursor` back unchanged. Malformed or stale cursors are
rejected with MCP `invalidParams` errors.

## Stdio Example

Run the example server with:

```bash
dart run packages/connectanum_mcp/example/stdio_echo_server.dart
```

The stdio transport reads one UTF-8 JSON-RPC message per line from `stdin` and
writes one JSON-RPC response per line to `stdout`. Notifications do not produce
response lines.

Minimal manual request sequence:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"demo","version":"0.1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hello"}}}
```

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

That default mapping is useful for app integrations because the MCP surface can
stay stable while the application keeps its existing WAMP procedure names and
authorization model. A Groli-style app can expose a curated set of tools by
connecting a normal `Session`, wrapping selected procedures with
`McpWampToolDelegate`, and serving them over stdio to the local MCP client.

## Compatibility Notes

The package follows MCP JSON-RPC semantics instead of WAMP semantics at the
public MCP boundary. WAMP is only an optional backend used by
`McpWampToolDelegate`.

Networked MCP deployments should wait for an explicit Streamable HTTP or
router-backed adapter. Until then, stdio is the supported transport for local
agent integrations.
