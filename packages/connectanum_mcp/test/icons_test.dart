import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP icons', () {
    test('serializes implementation, tool, prompt, and resource icons', () {
      const icon = McpIcon(
        src: 'https://example.com/icons/task.png',
        mimeType: 'image/png',
        sizes: ['48x48', '96x96'],
        theme: McpIconTheme.dark,
      );
      final iconJson = {
        'src': 'https://example.com/icons/task.png',
        'mimeType': 'image/png',
        'sizes': ['48x48', '96x96'],
        'theme': 'dark',
      };

      expect(
        const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
          icons: [icon],
        ).toJson(),
        {
          'name': 'connectanum-test',
          'version': '0.1.0',
          'icons': [iconJson],
        },
      );

      expect(
        McpTool(
          name: 'task.create',
          icons: const [icon],
          handler: (_) => McpToolResult.text('created'),
        ).toJson(),
        {
          'name': 'task.create',
          'inputSchema': {'type': 'object', 'additionalProperties': false},
          'icons': [iconJson],
        },
      );

      expect(
        McpPrompt(
          name: 'task.summary',
          icons: const [icon],
          handler: (_) => McpPromptResult.text('summarize'),
        ).toJson(),
        {
          'name': 'task.summary',
          'icons': [iconJson],
        },
      );

      expect(
        McpResource(
          uri: 'app://tasks/open',
          name: 'open-tasks',
          icons: const [icon],
          read: (request) => [
            McpTextResourceContent(uri: request.uri, text: '[]'),
          ],
        ).toJson(),
        {
          'uri': 'app://tasks/open',
          'name': 'open-tasks',
          'icons': [iconJson],
        },
      );

      expect(
        McpResourceTemplate(
          uriTemplate: 'app://tasks/{id}',
          name: 'task',
          icons: const [icon],
        ).toJson(),
        {
          'uriTemplate': 'app://tasks/{id}',
          'name': 'task',
          'icons': [iconJson],
        },
      );
    });

    test('serializes data URI icons with optional light theme', () {
      expect(
        const McpIcon(
          src: 'data:image/svg+xml;base64,PHN2Zy8+',
          theme: McpIconTheme.light,
        ).toJson(),
        {'src': 'data:image/svg+xml;base64,PHN2Zy8+', 'theme': 'light'},
      );
    });

    test('validates icon source and optional display fields', () {
      expect(() => const McpIcon(src: '').toJson(), throwsArgumentError);
      expect(
        () => const McpIcon(src: 'app://tasks/icon').toJson(),
        throwsArgumentError,
      );
      expect(
        () => const McpIcon(
          src: 'https://example.com/icon.png',
          mimeType: '',
        ).toJson(),
        throwsArgumentError,
      );
      expect(
        () => const McpIcon(
          src: 'https://example.com/icon.png',
          sizes: [''],
        ).toJson(),
        throwsArgumentError,
      );
    });
  });
}
