import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp.dart';

Future<void> main() {
  final server = McpServer(
    serverInfo: const McpServerInfo(
      name: 'connectanum-stdio-echo',
      version: '0.1.0',
    ),
    instructions: 'Example MCP server that echoes text arguments.',
    tools: [
      McpTool(
        name: 'echo',
        description: 'Echoes the provided text argument.',
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

  return McpStdioTransport(server: server, input: stdin, output: stdout).run();
}
