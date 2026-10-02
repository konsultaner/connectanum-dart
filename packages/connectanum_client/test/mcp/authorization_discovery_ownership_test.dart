import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

final _endpoint = Uri.parse('https://mcp.example/mcp');

Map<String, Object?> _resource(String name) => {
  'resource': _endpoint.toString(),
  'authorization_servers': ['https://auth.example'],
  'resource_name': name,
};

class _Headers implements HttpHeaders {
  _Headers([Map<String, List<String>>? values]) : values = values ?? {};
  final Map<String, List<String>> values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = [value.toString()];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.body, {
    this.statusCode = 200,
    String? type = 'application/json',
  }) : headers = _Headers({
         if (type != null) HttpHeaders.contentTypeHeader: [type],
       });
  final String body;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([utf8.encode(body)]).listen(
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
  @override
  final _Headers headers = _Headers();
  var sends = 0;
  final aborts = <Object?>[];

  @override
  Future<HttpClientResponse> close() async {
    sends++;
    return response;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts.add(exception);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final HttpClientResponse Function(Uri uri) respond;
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

void main() {
  for (final authorizationServer in [false, true]) {
    for (final supplied in [false, true]) {
      for (final closeClient in [false, true]) {
        for (final failOpen in [false, true]) {
          test(
            'ownership AS=$authorizationServer supplied=$supplied '
            'close=$closeClient error=$failOpen',
            () async {
              final failure = StateError('controlled open failure');
              HttpClientResponse respond(Uri uri) {
                if (failOpen) throw failure;
                return _Response(
                  jsonEncode(
                    authorizationServer
                        ? {
                            'issuer': _endpoint.toString(),
                            'authorization_endpoint':
                                'https://mcp.example/authorize',
                            'token_endpoint': 'https://mcp.example/token',
                            'response_types_supported': ['code'],
                            'code_challenge_methods_supported': ['S256'],
                          }
                        : _resource('direct'),
                  ),
                );
              }

              final external = _Client(respond);
              final internal = _Client(respond);
              var factories = 0;
              await HttpOverrides.runZoned(
                () async {
                  final pending = authorizationServer
                      ? discoverMcpAuthorizationServerMetadata(
                          _endpoint,
                          httpClient: supplied ? external : null,
                          closeHttpClient: closeClient,
                        )
                      : discoverMcpProtectedResourceMetadata(
                          _endpoint,
                          httpClient: supplied ? external : null,
                          closeHttpClient: closeClient,
                        );
                  if (failOpen) {
                    await expectLater(pending, throwsA(same(failure)));
                  } else {
                    final result = await pending;
                    if (authorizationServer) {
                      expect(
                        (result as McpAuthorizationServerDiscovery)
                            .metadata
                            .issuer,
                        _endpoint,
                      );
                    } else {
                      expect(
                        (result as McpProtectedResourceDiscovery)
                            .metadata
                            .resource,
                        _endpoint,
                      );
                    }
                  }
                },
                createHttpClient: (_) {
                  factories++;
                  return internal;
                },
              );
              final selected = supplied ? external : internal;
              final unused = supplied ? internal : external;
              expect(factories, supplied ? 0 : 1);
              expect(unused.requested, isEmpty);
              expect(unused.closes, isEmpty);
              expect(selected.requested, [
                authorizationServer
                    ? _endpoint.resolve(
                        '/.well-known/oauth-authorization-server/mcp',
                      )
                    : _endpoint,
              ]);
              expect(
                selected.closes,
                !supplied || closeClient ? [true] : isEmpty,
              );
              expect(selected.requests, hasLength(failOpen ? 0 : 1));
              for (final request in selected.requests) {
                expect(request.sends, 1);
                expect(request.aborts, isEmpty);
                expect(request.headers.values, {
                  'accept': ['application/json'],
                });
              }
            },
          );
        }
      }
    }
  }

  for (final status in [200, 401, 404]) {
    for (final type in [
      'application/json',
      ' Application/JSON ; charset=utf-8',
      'text/plain',
      null,
    ]) {
      for (final bodyKind in [
        'resource',
        'empty',
        'invalid',
        'array',
        'scalar',
        'no-resource',
      ]) {
        test('direct probe status=$status type=$type body=$bodyKind', () async {
          final body = switch (bodyKind) {
            'resource' => jsonEncode(_resource('direct')),
            'empty' => '',
            'invalid' => '{',
            'array' => '[{}]',
            'scalar' => '42',
            _ => '{}',
          };
          final client = _Client(
            (uri) => uri == _endpoint
                ? _Response(body, statusCode: status, type: type)
                : _Response(jsonEncode(_resource('fallback'))),
          );
          var defaultClients = 0;
          final result = await HttpOverrides.runZoned(
            () => discoverMcpProtectedResourceMetadata(
              _endpoint,
              httpClient: client,
            ),
            createHttpClient: (_) {
              defaultClients++;
              return client;
            },
          );
          expect(defaultClients, 0);
          final direct =
              status == 200 &&
              (type == 'application/json' ||
                  type == ' Application/JSON ; charset=utf-8') &&
              bodyKind == 'resource';
          final fallback = _endpoint.resolve(
            '/.well-known/oauth-protected-resource/mcp',
          );
          expect(result.metadataUri, direct ? _endpoint : fallback);
          expect(result.metadata.resourceName, direct ? 'direct' : 'fallback');
          expect(result.metadata.resource, _endpoint);
          expect(result.metadata.authorizationServers, [
            Uri.parse('https://auth.example'),
          ]);
          expect(
            client.requested,
            direct ? [_endpoint] : [_endpoint, fallback],
          );
          expect(client.closes, isEmpty);
        });
      }
    }
  }

  for (final timeout in [Duration.zero, const Duration(microseconds: -1)]) {
    test('AS timeout $timeout fails before client construction', () async {
      var factories = 0;
      await HttpOverrides.runZoned(
        () async {
          await expectLater(
            discoverMcpAuthorizationServerMetadata(_endpoint, timeout: timeout),
            throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'timeout'),
            ),
          );
        },
        createHttpClient: (_) {
          factories++;
          return _Client((_) => throw StateError('No network access expected'));
        },
      );
      expect(factories, 0);
    });
  }
}
