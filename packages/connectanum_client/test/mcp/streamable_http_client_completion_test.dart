import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  test(
    'typed completion helpers work through stateless and direct JSON',
    () async {
      final seen = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final message = body.cast<String, Object?>();
        seen.add(message);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': <String, Object?>{
              if (request.headers.value('MCP-Protocol-Version') == '2026-07-28')
                'resultType': 'complete',
              'completion': <String, Object?>{
                'values': <String>['T-100', 'T-101'],
                'total': 3,
                'hasMore': true,
              },
            },
          }),
        );
        await request.response.close();
      });

      final endpoint = Uri.parse('http://127.0.0.1:${server.port}/mcp');
      final stateless = McpStreamableHttpClient.stateless(
        endpoint,
        clientInfo: <String, Object?>{'name': 'test-client', 'version': '1'},
      );
      addTearDown(stateless.close);
      final completion = await stateless.complete(
        McpCompletionRequest(
          reference: McpPromptReference(name: 'summarize-task'),
          argument: McpCompletionArgument(name: 'taskId', value: 'T-'),
        ),
        id: 'modern-completion',
      );
      expect(completion.values, <String>['T-100', 'T-101']);
      expect(completion.total, 3);
      expect(completion.hasMore, isTrue);
      expect(seen.single['method'], 'completion/complete');
      expect(
        ((seen.single['params'] as Map)['_meta']
            as Map)['io.modelcontextprotocol/protocolVersion'],
        '2026-07-28',
      );

      final direct = McpStreamableHttpClient(endpoint);
      addTearDown(direct.close);
      final directCompletion = await direct.completeDirect(
        McpCompletionRequest(
          reference: McpResourceTemplateReference(
            uri: 'app://tasks/{taskId}',
          ),
          argument: McpCompletionArgument(name: 'taskId', value: 'T-1'),
        ),
        id: 'direct-completion',
      );
      expect(directCompletion.values, <String>['T-100', 'T-101']);
      expect(seen.last['method'], 'completion/complete');
    },
  );
}
