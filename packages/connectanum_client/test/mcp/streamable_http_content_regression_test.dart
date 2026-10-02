@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  final validBlocks = <McpJsonMap>[
    {'type': 'text', 'text': ''},
    {'type': 'image', 'data': 'AAEC/w==', 'mimeType': 'image/png'},
    {'type': 'audio', 'data': 'AAEC/w==', 'mimeType': 'audio/wav'},
    {
      'type': 'resource',
      'resource': {'uri': 'urn:example:text', 'text': 'value'},
    },
    {
      'type': 'resource',
      'resource': {
        'uri': 'urn:example:blob',
        'blob': 'AAEC/w==',
        'mimeType': 'application/octet-stream',
      },
    },
    {'type': 'resource_link', 'uri': 'urn:example:link', 'name': 'linked data'},
  ];
  final invalidBlocks = <Object?>[
    null,
    'text',
    {},
    {'type': 1},
    {'type': ''},
    {'type': 'unknown'},
    {'type': 'text'},
    {'type': 'text', 'text': false},
    for (final type in ['image', 'audio']) ...[
      {'type': type, 'mimeType': 'image/png'},
      {'type': type, 'data': 'AA=='},
      {'type': type, 'data': 1, 'mimeType': 'image/png'},
      {'type': type, 'data': 'AA==', 'mimeType': false},
      {'type': type, 'data': 'not base64!', 'mimeType': 'image/png'},
    ],
    {'type': 'resource', 'resource': null},
    for (final uri in [null, '', 'relative', 'urn:has space', 'http://[bad'])
      {'type': 'resource_link', 'uri': uri, 'name': 'data'},
    for (final name in [null, '', false])
      {'type': 'resource_link', 'uri': 'urn:example:link', 'name': name},
  ];
  final invalidResources = <McpJsonMap>[
    for (final uri in [null, '', 'relative', 'urn:has space', 'http://[bad'])
      {'uri': uri, 'text': 'value'},
    {'uri': 'urn:example:data', 'text': 'value', 'mimeType': 1},
    {'uri': 'urn:example:data'},
    {'uri': 'urn:example:data', 'text': 'value', 'blob': 'AA=='},
    {'uri': 'urn:example:data', 'text': null},
    {'uri': 'urn:example:data', 'blob': false},
    {'uri': 'urn:example:data', 'blob': 'not base64!'},
  ];
  for (final resource in invalidResources) {
    invalidBlocks.add({'type': 'resource', 'resource': resource});
  }

  final invalidResults = <(String, McpJsonMap)>[
    for (final content in [null, false, 'text'])
      ('tools/call', {'content': content}),
    for (final block in invalidBlocks)
      (
        'tools/call',
        {
          'content': [block],
        },
      ),
    ('tools/call', {'content': [], 'isError': 'false'}),
    ('tools/call', {'content': [], '_meta': []}),
    ('prompts/get', {'description': false, 'messages': []}),
    ('prompts/get', {'messages': null}),
    (
      'prompts/get',
      {
        'messages': [null],
      },
    ),
    for (final role in [null, '', 'system', 1])
      (
        'prompts/get',
        {
          'messages': [
            {
              'role': role,
              'content': {'type': 'text', 'text': 'value'},
            },
          ],
        },
      ),
    for (final block in invalidBlocks)
      (
        'prompts/get',
        {
          'messages': [
            {'role': 'assistant', 'content': block},
          ],
        },
      ),
    ('resources/read', {'contents': null}),
    (
      'resources/read',
      {
        'contents': [null],
      },
    ),
    for (final resource in invalidResources)
      (
        'resources/read',
        {
          'contents': [resource],
        },
      ),
    for (final (method, key, nameKey) in [
      ('tools/list', 'tools', 'name'),
      ('resources/list', 'resources', 'uri'),
      ('resources/templates/list', 'resourceTemplates', 'uriTemplate'),
      ('prompts/list', 'prompts', 'name'),
    ]) ...[
      (method, {key: null}),
      (
        method,
        {
          key: [false],
        },
      ),
      for (final name in [null, '', 'with space', 'with\ncontrol', 1])
        (
          method,
          {
            key: [
              {nameKey: name},
            ],
          },
        ),
      for (final cursor in [1, '', 'with space', 'with\ncontrol'])
        (method, {key: [], 'nextCursor': cursor}),
    ],
  ];

  for (final version in [
    McpStreamableHttpClient.latestSessionProtocolVersion,
    McpStreamableHttpClient.latestProtocolVersion,
  ]) {
    for (final direct in [false, true]) {
      group(
        '$version ${direct ? 'Direct JSON' : 'Streamable HTTP'} content',
        () {
          for (var i = 0; i < invalidResults.length; i++) {
            final (method, malformed) = invalidResults[i];
            test('$method rejects malformed result $i and recovers', () async {
              final endpoint = await _ContentEndpoint.bind(malformed);
              addTearDown(endpoint.close);
              final client = McpStreamableHttpClient(
                endpoint.uri,
                defaultProtocolVersion: version,
                clientInfo: const {
                  'name': 'content-regression',
                  'version': '1',
                },
              );
              addTearDown(() => client.close(force: true));
              await expectLater(
                _invoke(client, method, direct),
                throwsFormatException,
              );
              endpoint.result = _validResult(method, validBlocks);
              expect(await _invoke(client, method, direct), endpoint.result);
              expect(endpoint.methods, [method, method]);
              expect(
                endpoint.accepts,
                List.filled(
                  2,
                  direct &&
                          version ==
                              McpStreamableHttpClient
                                  .latestSessionProtocolVersion
                      ? 'application/json'
                      : 'application/json, text/event-stream',
                ),
              );
            });
          }

          for (final method in [
            'tools/call',
            'prompts/get',
            'resources/read',
          ]) {
            test(
              '$method preserves every supported content representation',
              () async {
                final result = _validResult(method, validBlocks);
                final endpoint = await _ContentEndpoint.bind(result);
                addTearDown(endpoint.close);
                final client = McpStreamableHttpClient(
                  endpoint.uri,
                  defaultProtocolVersion: version,
                  clientInfo: const {
                    'name': 'content-regression',
                    'version': '1',
                  },
                );
                addTearDown(() => client.close(force: true));
                expect(await _invoke(client, method, direct), result);
                expect(endpoint.methods, [method]);
              },
            );
          }
        },
      );
    }
  }
}

McpJsonMap _validResult(String method, List<McpJsonMap> blocks) =>
    switch (method) {
      'tools/call' => {
        'resultType': 'complete',
        'content': blocks,
        'isError': false,
        '_meta': {'trace': 'test'},
      },
      'prompts/get' => {
        'resultType': 'complete',
        'description': 'Instructions',
        'messages': [
          for (final role in ['user', 'assistant'])
            for (final block in blocks) {'role': role, 'content': block},
        ],
      },
      'resources/read' => {
        'contents': [
          {'uri': 'urn:example:text', 'text': ''},
          {
            'uri': 'urn:example:blob',
            'blob': 'AAEC/w==',
            'mimeType': 'application/octet-stream',
          },
        ],
      },
      'tools/list' => {
        'tools': [
          {'name': 'example.tool'},
        ],
        'nextCursor': 'page-2',
      },
      'resources/list' => {
        'resources': [
          {'uri': 'urn:example:data'},
        ],
        'nextCursor': 'page-2',
      },
      'resources/templates/list' => {
        'resourceTemplates': [
          {'uriTemplate': 'urn:example:{id}'},
        ],
        'nextCursor': 'page-2',
      },
      'prompts/list' => {
        'prompts': [
          {'name': 'instructions'},
        ],
        'nextCursor': 'page-2',
      },
      _ => throw StateError('Unexpected test method: $method'),
    };

Future<McpJsonMap> _invoke(
  McpStreamableHttpClient client,
  String method,
  bool direct,
) async {
  switch (method) {
    case 'tools/call':
      return direct
          ? client.callToolDirect('example.tool')
          : client.callTool('example.tool');
    case 'prompts/get':
      return direct
          ? client.getPromptDirect('instructions')
          : client.getPrompt('instructions');
    case 'resources/read':
      final contents = await (direct
          ? client.readResourceDirect('urn:example:data')
          : client.readResource('urn:example:data'));
      return {'contents': contents};
    case 'tools/list':
      final page = await (direct
          ? client.listToolsDirect()
          : client.listTools());
      return {'tools': page.tools, 'nextCursor': page.nextCursor};
    case 'resources/list':
      final page = await (direct
          ? client.listResourcesDirect()
          : client.listResources());
      return {'resources': page.resources, 'nextCursor': page.nextCursor};
    case 'resources/templates/list':
      final page = await (direct
          ? client.listResourceTemplatesDirect()
          : client.listResourceTemplates());
      return {
        'resourceTemplates': page.resourceTemplates,
        'nextCursor': page.nextCursor,
      };
    case 'prompts/list':
      final page = await (direct
          ? client.listPromptsDirect()
          : client.listPrompts());
      return {'prompts': page.prompts, 'nextCursor': page.nextCursor};
    default:
      throw StateError('Unexpected test method: $method');
  }
}

class _ContentEndpoint {
  _ContentEndpoint(this.server, this.result) {
    server.listen((request) async {
      final message =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      methods.add(message['method']);
      accepts.add(request.headers.value(HttpHeaders.acceptHeader));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': message['id'],
          'result': {...result, 'resultType': 'complete'},
        }),
      );
      await request.response.close();
    });
  }

  final HttpServer server;
  McpJsonMap result;
  final methods = <Object?>[];
  final accepts = <String?>[];

  static Future<_ContentEndpoint> bind(McpJsonMap result) async =>
      _ContentEndpoint(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        result,
      );

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/mcp');

  Future<void> close() async {
    await server.close(force: true);
  }
}
