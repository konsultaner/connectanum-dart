import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

import 'discovery_test_expectations.dart';

void main() {
  for (final entry in <(String, Map<String, Object?>, List<String>?)>[
    ('absent', {}, null),
    ('null', {'bearer_methods_supported': null}, null),
    ('empty', {'bearer_methods_supported': <String>[]}, <String>[]),
    (
      'header',
      {
        'bearer_methods_supported': ['header'],
      },
      ['header'],
    ),
    (
      'ordered',
      {
        'bearer_methods_supported': ['body', 'header'],
      },
      ['body', 'header'],
    ),
    (
      'extension',
      {
        'bearer_methods_supported': ['custom'],
      },
      ['custom'],
    ),
  ]) {
    test('protected resource preserves ${entry.$1} bearer methods', () async {
      final endpoint = await _metadataEndpoint(entry.$2);
      final pending = discoverMcpProtectedResourceMetadata(endpoint);
      final discovery = await expectDiscoverySuccess(pending);
      final metadata = discovery.metadata;
      expect(discovery.metadataUri, endpoint);
      expect(metadata.resource, endpoint);
      expect(metadata.bearerMethodsSupported, entry.$3);
      expect(metadata.authorizationServers, [
        Uri.parse('https://auth.example'),
      ]);
      expect(metadata.scopesSupported, ['tools:read']);
      expect(
        () => metadata.authorizationServers.add(
          Uri.parse('https://other.example'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => metadata.scopesSupported!.add('tools:write'),
        throwsUnsupportedError,
      );
      if (entry.$3 != null) {
        expect(
          () => metadata.bearerMethodsSupported!.add('query'),
          throwsUnsupportedError,
        );
        expect(metadata.bearerMethodsSupported, entry.$3);
      }
    });
  }

  for (final value in <Object>[
    42,
    'header',
    <String, Object?>{},
    [''],
    ['header', 7],
  ]) {
    test(
      'protected resource rejects malformed bearer methods $value',
      () async {
        final endpoint = await _metadataEndpoint({
          'bearer_methods_supported': value,
        });
        await expectLater(
          discoverMcpProtectedResourceMetadata(endpoint),
          throwsA(
            isA<McpAuthorizationDiscoveryException>().having(
              (error) => error.message,
              'message',
              contains('bearer_methods_supported'),
            ),
          ),
        );
      },
    );
  }
}

Future<Uri> _metadataEndpoint(Map<String, Object?> fields) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final endpoint = Uri.parse(
    'http://${server.address.address}:${server.port}/mcp',
  );
  final requests = <String>[];
  addTearDown(() => expect(requests, ['/mcp']));
  server.listen((request) async {
    requests.add(request.uri.path);
    await request.drain<void>();
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'resource': endpoint.toString(),
        'authorization_servers': ['https://auth.example'],
        'scopes_supported': ['tools:read'],
        ...fields,
      }),
    );
    await request.response.close();
  });
  return endpoint;
}
