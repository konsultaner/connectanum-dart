import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp.dart';

Future<void> main() {
  final server = McpServer(
    serverInfo: const McpServerInfo(
      name: 'connectanum-stdio-echo',
      version: '0.1.0',
    ),
    instructions:
        'Example MCP server that echoes text arguments and exposes context.',
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
    resources: [
      McpResource(
        uri: 'app://example/context',
        name: 'example-context',
        title: 'Example Context',
        description: 'Static read-only context served by the stdio example.',
        mimeType: 'application/json',
        read: (request) => [
          McpTextResourceContent(
            uri: request.uri,
            mimeType: 'application/json',
            text: jsonEncode({
              'server': 'connectanum-stdio-echo',
              'summary': 'Echo tool plus one package-local context resource.',
            }),
          ),
        ],
      ),
    ],
  );

  return McpStdioTransport(server: server, input: stdin, output: stdout).run();
}
