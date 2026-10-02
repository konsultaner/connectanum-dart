@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

import 'discovery_test_expectations.dart';

class _Headers implements HttpHeaders {
  _Headers([Map<String, List<String>>? values]) : values = values ?? {};
  final Map<String, List<String>> values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = [value.toString()];
  }

  @override
  void forEach(void Function(String, List<String>) action) =>
      values.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.body, {
    String type = 'application/json',
  }) : headers = _Headers({
         HttpHeaders.contentTypeHeader: [type],
       });
  final String body;
  @override
  int get statusCode => 200;
  @override
  final HttpHeaders headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final HttpClientResponse response;
  final aborts = <Object?>[];
  var sends = 0;
  @override
  final _Headers headers = _Headers();

  @override
  Future<HttpClientResponse> close() async {
    sends++;
    return response;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      aborts.add(exception);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final HttpClientResponse Function(Uri) respond;
  final requested = <Uri>[];
  final requests = <_Request>[];
  final closes = <bool>[];

  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    requested.add(uri);
    final request = _Request(respond(uri));
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => closes.add(force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _metadata(Uri resource) => {
  'resource': resource.toString(),
  'authorization_servers': ['https://auth.example'],
};

void main() {
  final validHeaders = <(List<String>, List<Map<String, String>>)>[
    ([''], []),
    ([' , \t, '], []),
    (['Bearer'], [{}]),
    (['Bearer,'], [{}]),
    (['Bearer, , \t'], [{}]),
    (
      ['Bearer , scope=read'],
      [
        {'scope': 'read'},
      ],
    ),
    (['Bearer, Basic'], [{}]),
    (['Basic, Bearer'], [{}]),
    (
      ['Bearer scope=read, Bearer'],
      [
        {'scope': 'read'},
        {},
      ],
    ),
    (
      ['Bearer , , scope=read, , realm=test'],
      [
        {'scope': 'read', 'realm': 'test'},
      ],
    ),
    (
      ['Bearer scope=read,', ',Bearer scope=write,'],
      [
        {'scope': 'read'},
        {'scope': 'write'},
      ],
    ),
    (
      ['Bearer realm="first", Basic realm="legacy",'],
      [
        {'realm': 'first'},
      ],
    ),
  ];
  for (final character in ['!', ' ', '\t', '#', '~']) {
    validHeaders.add((
      ['Bearer realm="\\$character"'],
      [
        {'realm': character},
      ],
    ));
  }
  for (final (headers, expected) in validHeaders) {
    test('challenge boundary preserves ${jsonEncode(headers)}', () {
      List<McpBearerChallenge>? parsed;
      expect(() => parsed = parseMcpBearerChallenges(headers), returnsNormally);
      expect(parsed!.map((value) => value.parameters).toList(), expected);
      expect(() => parsed!.clear(), throwsUnsupportedError);
      for (final challenge in parsed!) {
        expect(() => challenge.parameters.clear(), throwsUnsupportedError);
      }
    });
  }

  for (final header in [
    'Bearer realm=first, REALM=second, Bearer scope=untrusted',
    'Bearer scope=read, scope=write, Bearer realm=untrusted',
    'Bearer realm="unterminated',
    'Bearer realm="trailing\\',
  ]) {
    test(
      'malformed field cannot contaminate recovery ${jsonEncode(header)}',
      () {
        List<McpBearerChallenge>? parsed;
        expect(
          () => parsed = parseMcpBearerChallenges([
            header,
            'Bearer realm=independent, scope=read',
          ]),
          returnsNormally,
        );
        expect(parsed!.map((value) => value.parameters).toList(), [
          {'realm': 'independent', 'scope': 'read'},
        ]);
      },
    );
  }

  final endpoint = Uri.parse('https://mcp.example:8443/mcp');
  for (final (field, allowEmpty) in [
    ('authorization_servers', false),
    ('scopes_supported', false),
    ('bearer_methods_supported', true),
  ]) {
    for (final value in <Object>['not-an-array', <Object>[]]) {
      if (allowEmpty && value is List) continue;
      test('$field has an exact array diagnostic for $value', () async {
        final document = _metadata(endpoint)..[field] = value;
        final client = _Client((_) => _Response(jsonEncode(document)));
        await expectLater(
          discoverMcpProtectedResourceMetadata(endpoint, httpClient: client),
          throwsA(
            isA<McpAuthorizationDiscoveryException>().having(
              (error) => error.message,
              'message',
              'Protected Resource Metadata $field must be a '
                  '${allowEmpty ? '' : 'non-empty '}string array.',
            ),
          ),
        );
        expect(client.requested, [endpoint]);
        expect(client.closes, isEmpty);
      });
    }
  }

  for (final port in [8443, 8444, 9443]) {
    test('protected resource identity checks explicit port $port', () async {
      final resource = endpoint.replace(port: port);
      final client = _Client((_) => _Response(jsonEncode(_metadata(resource))));
      final discovery = discoverMcpProtectedResourceMetadata(
        endpoint,
        httpClient: client,
      );
      if (port == endpoint.port) {
        final result = await expectDiscoverySuccess(discovery);
        expect(result.metadata.resource, endpoint);
        expect(result.metadataUri, endpoint);
        expect(result.metadata.authorizationServers, [
          Uri.parse('https://auth.example'),
        ]);
        expect(
          () => result.metadata.authorizationServers.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => result.metadata.authorizationServers.add(endpoint),
          throwsUnsupportedError,
        );
      } else {
        await expectLater(
          discovery,
          throwsA(
            isA<McpAuthorizationDiscoveryException>()
                .having((error) => error.uri, 'uri', resource)
                .having(
                  (error) => error.message,
                  'message',
                  'Protected Resource Metadata resource $resource does not match $endpoint.',
                ),
          ),
        );
      }
      expect(client.requested, [endpoint]);
      expect(client.closes, isEmpty);
      expect(client.requests.single.aborts, isEmpty);
      expect(client.requests.single.sends, 1);
    });
  }

  test(
    'well-known JSON metadata fallback succeeds without aborting requests',
    () async {
      final client = _Client(
        (uri) => uri == endpoint
            ? _Response('<html></html>', type: 'text/html')
            : _Response(jsonEncode(_metadata(endpoint))),
      );
      final result = await expectDiscoverySuccess(
        discoverMcpProtectedResourceMetadata(
          endpoint,
          httpClient: client,
        ),
      );
      final metadataUri = endpoint.resolve(
        '/.well-known/oauth-protected-resource/mcp',
      );
      expect(client.requested, [endpoint, metadataUri]);
      expect(result.metadataUri, metadataUri);
      expect(result.metadata.resource, endpoint);
      for (final request in client.requests) {
        expect(request.aborts, isEmpty);
        expect(request.sends, 1);
        expect(request.headers.values, {
          'accept': ['application/json'],
        });
      }
      expect(client.closes, isEmpty);
    },
  );
}
