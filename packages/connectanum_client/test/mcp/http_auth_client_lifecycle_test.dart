import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectanumHttpAuthClient lifecycle', () {
    late _LifecycleAuthEndpoint endpoint;
    late HttpClient sharedHttpClient;

    setUp(() async {
      endpoint = await _LifecycleAuthEndpoint.bind();
      sharedHttpClient = HttpClient();
    });

    tearDown(() async {
      sharedHttpClient.close(force: true);
      await endpoint.close();
    });

    test(
      'close rejects new auth work while shared transport stays reusable',
      () async {
        final client = ConnectanumHttpAuthClient(
          endpoint.uri,
          httpClient: sharedHttpClient,
        );

        client.close();
        client.close(force: true);

        await expectLater(
          client.issueTicketToken(
            realm: 'realm1',
            authId: 'user-1',
            ticket: 'ticket-1',
          ),
          throwsA(_closedStateError),
        );
        await expectLater(
          client.refreshToken('refresh-token-1'),
          throwsA(_closedStateError),
        );
        await expectLater(
          client.revokeToken('access-token-1'),
          throwsA(_closedStateError),
        );
        expect(endpoint.requestBodies, isEmpty);

        final replacement = ConnectanumHttpAuthClient(
          endpoint.uri,
          httpClient: sharedHttpClient,
        );
        final grant = await replacement.refreshToken(
          'replacement-refresh-token',
        );
        expect(grant.accessToken, 'refreshed-access-token');
        replacement.close();
      },
    );

    test(
      'close aborts auth, refresh, and revoke requests awaiting headers',
      () async {
        final operations =
            <Future<Object?> Function(ConnectanumHttpAuthClient)>[
              (client) => client.issueTicketToken(
                realm: 'realm1',
                authId: 'user-1',
                ticket: 'ticket-1',
              ),
              (client) => client.refreshToken('refresh-token-1'),
              (client) async {
                await client.revokeToken('access-token-1');
                return null;
              },
            ];

        for (final operation in operations) {
          endpoint.mode = _ResponseMode.holdHeaders;
          final client = ConnectanumHttpAuthClient(
            endpoint.uri,
            httpClient: sharedHttpClient,
          );
          final requestCount = endpoint.requestBodies.length + 1;
          final pending = operation(client);
          await endpoint.waitForRequestCount(requestCount);

          client.close();

          await expectLater(
            pending.timeout(const Duration(seconds: 1)),
            throwsA(_closedStateError),
          );
          endpoint.mode = _ResponseMode.normal;

          final replacement = ConnectanumHttpAuthClient(
            endpoint.uri,
            httpClient: sharedHttpClient,
          );
          final grant = await replacement.refreshToken(
            'replacement-refresh-token',
          );
          expect(grant.accessToken, 'refreshed-access-token');
          replacement.close();
        }
      },
    );

    test('close aborts a refresh response body read', () async {
      endpoint.mode = _ResponseMode.holdBody;
      final client = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: sharedHttpClient,
      );
      final pending = client.refreshToken('refresh-token-1');
      await endpoint.waitForHeldBodyCount(1);

      client.close();

      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(_closedStateError),
      );
      endpoint.mode = _ResponseMode.normal;
      final replacement = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: sharedHttpClient,
      );
      final grant = await replacement.refreshToken('replacement-refresh-token');
      expect(grant.accessToken, 'refreshed-access-token');
      replacement.close();
    });

    test('validates operation bounds before opening requests', () {
      expect(
        () => ConnectanumHttpAuthClient(
          endpoint.uri,
          httpClient: sharedHttpClient,
          requestTimeout: Duration.zero,
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'requestTimeout')
              .having(
                (error) => error.invalidValue,
                'invalidValue',
                Duration.zero,
              ),
        ),
      );
      expect(
        () => ConnectanumHttpAuthClient(
          endpoint.uri,
          httpClient: sharedHttpClient,
          maxResponseBytes: 0,
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'maxResponseBytes')
              .having((error) => error.invalidValue, 'invalidValue', 0),
        ),
      );
      expect(endpoint.requestBodies, isEmpty);
    });

    test('aborts a request that opens after the operation deadline', () async {
      final delayedHttpClient = _DelayedPostHttpClient(sharedHttpClient);
      final client = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: delayedHttpClient,
        requestTimeout: const Duration(milliseconds: 80),
      );
      addTearDown(client.close);

      final pending = client.refreshToken('refresh-token-1');
      await delayedHttpClient.postStarted.future.timeout(
        const Duration(seconds: 1),
      );
      await expectLater(pending, throwsA(isA<TimeoutException>()));

      delayedHttpClient.releasePost();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(endpoint.requestBodies, isEmpty);

      final grant = await client.refreshToken('replacement-refresh-token');
      expect(grant.accessToken, 'refreshed-access-token');
    });

    test('times out a response before headers and reuses the client', () async {
      endpoint.mode = _ResponseMode.holdHeaders;
      final client = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: sharedHttpClient,
        requestTimeout: const Duration(milliseconds: 80),
      );
      addTearDown(client.close);

      final pending = client.refreshToken('refresh-token-1');
      await endpoint.waitForRequestCount(1);
      await expectLater(
        pending,
        throwsA(
          isA<TimeoutException>()
              .having(
                (error) => error.duration,
                'duration',
                const Duration(milliseconds: 80),
              )
              .having(
                (error) => error.message,
                'message',
                'Connectanum HTTP auth operation exceeded 80 ms.',
              ),
        ),
      );

      endpoint.mode = _ResponseMode.normal;
      final grant = await client.refreshToken('replacement-refresh-token');
      expect(grant.accessToken, 'refreshed-access-token');
    });

    test('times out a stalled response body and reuses the client', () async {
      endpoint.mode = _ResponseMode.holdBody;
      final client = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: sharedHttpClient,
        requestTimeout: const Duration(milliseconds: 80),
      );
      addTearDown(client.close);

      final pending = client.refreshToken('refresh-token-1');
      await endpoint.waitForHeldBodyCount(1);
      await expectLater(pending, throwsA(isA<TimeoutException>()));

      endpoint.mode = _ResponseMode.normal;
      final grant = await client.refreshToken('replacement-refresh-token');
      expect(grant.accessToken, 'refreshed-access-token');
    });

    test('rejects an oversized successful auth response', () async {
      endpoint.mode = _ResponseMode.oversizedBody;
      final client = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: sharedHttpClient,
      );
      addTearDown(client.close);

      await expectLater(
        client.refreshToken('refresh-token-1'),
        throwsA(
          isA<ConnectanumHttpAuthProtocolException>().having(
            (error) => error.message,
            'message',
            'Connectanum HTTP auth response exceeds 65536 bytes.',
          ),
        ),
      );

      endpoint.mode = _ResponseMode.normal;
      final grant = await client.refreshToken('replacement-refresh-token');
      expect(grant.accessToken, 'refreshed-access-token');
    });

    test('redacts an oversized rejected auth response', () async {
      endpoint.mode = _ResponseMode.oversizedErrorBody;
      final client = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: sharedHttpClient,
      );
      addTearDown(client.close);

      late Object caught;
      try {
        await client.refreshToken('refresh-token-1');
        fail('oversized rejected auth response was accepted');
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<ConnectanumHttpAuthProtocolException>());
      expect(caught.toString(), isNot(contains('sensitive-error-detail')));

      endpoint.mode = _ResponseMode.normal;
      final grant = await client.refreshToken('replacement-refresh-token');
      expect(grant.accessToken, 'refreshed-access-token');
    });

    test(
      'close cancels authentication paused before the token request',
      () async {
        final authentication = _BlockingAuthentication();
        final client = ConnectanumHttpAuthClient(
          endpoint.uri,
          httpClient: sharedHttpClient,
        );
        final pending = client.authenticate(
          realm: 'realm1',
          authId: 'user-1',
          authentication: authentication,
          authMethod: 'ticket',
        );
        await authentication.challengeEntered.future.timeout(
          const Duration(seconds: 1),
        );
        expect(endpoint.requestBodies, hasLength(1));

        client.close();

        await expectLater(
          pending.timeout(const Duration(seconds: 1)),
          throwsA(_closedStateError),
        );
        authentication.releaseChallenge();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(endpoint.requestBodies, hasLength(1));

        final replacement = ConnectanumHttpAuthClient(
          endpoint.uri,
          httpClient: sharedHttpClient,
        );
        final grant = await replacement.refreshToken(
          'replacement-refresh-token',
        );
        expect(grant.accessToken, 'refreshed-access-token');
        replacement.close();
      },
    );

    test('times out authentication paused before the token request', () async {
      final authentication = _BlockingAuthentication();
      final client = ConnectanumHttpAuthClient(
        endpoint.uri,
        httpClient: sharedHttpClient,
        requestTimeout: const Duration(milliseconds: 80),
      );
      addTearDown(client.close);
      final pending = client.authenticate(
        realm: 'realm1',
        authId: 'user-1',
        authentication: authentication,
        authMethod: 'ticket',
      );
      await authentication.challengeEntered.future.timeout(
        const Duration(seconds: 1),
      );
      expect(endpoint.requestBodies, hasLength(1));

      await expectLater(pending, throwsA(isA<TimeoutException>()));
      authentication.releaseChallenge();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(endpoint.requestBodies, hasLength(1));

      final grant = await client.refreshToken('replacement-refresh-token');
      expect(grant.accessToken, 'refreshed-access-token');
    });
  });
}

final Matcher _closedStateError = isA<StateError>().having(
  (error) => error.message,
  'message',
  'ConnectanumHttpAuthClient is closed.',
);

enum _ResponseMode {
  normal,
  holdHeaders,
  holdBody,
  oversizedBody,
  oversizedErrorBody,
}

final class _LifecycleAuthEndpoint {
  _LifecycleAuthEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final requestBodies = <Map<String, Object?>>[];
  final _requestCounts = StreamController<int>.broadcast(sync: true);
  final _heldBodyCounts = StreamController<int>.broadcast(sync: true);
  final _heldResponses = <HttpResponse>[];
  late final StreamSubscription<HttpRequest> _subscription;
  _ResponseMode mode = _ResponseMode.normal;
  int _heldBodyCount = 0;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/auth',
  );

  static Future<_LifecycleAuthEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _LifecycleAuthEndpoint._(server);
  }

  Future<void> waitForRequestCount(int expected) async {
    if (requestBodies.length >= expected) {
      return;
    }
    await _requestCounts.stream
        .firstWhere((count) => count >= expected)
        .timeout(const Duration(seconds: 1));
  }

  Future<void> waitForHeldBodyCount(int expected) async {
    if (_heldBodyCount >= expected) {
      return;
    }
    await _heldBodyCounts.stream
        .firstWhere((count) => count >= expected)
        .timeout(const Duration(seconds: 1));
  }

  Future<void> close() async {
    for (final response in _heldResponses) {
      unawaited(
        response.close().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
    await _subscription.cancel();
    await _server.close(force: true);
    await _requestCounts.close();
    await _heldBodyCounts.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final bodyText = await utf8.decoder.bind(request).join();
    final body = Map<String, Object?>.from(jsonDecode(bodyText) as Map);
    requestBodies.add(body);
    _requestCounts.add(requestBodies.length);

    if (mode == _ResponseMode.holdHeaders) {
      _hold(request.response);
      return;
    }

    final responseBody = _responseBody(body);
    if (mode == _ResponseMode.oversizedBody) {
      responseBody['extension'] = List<String>.filled(30000, '€').join();
    } else if (mode == _ResponseMode.oversizedErrorBody) {
      responseBody['error'] = 'sensitive-error-detail';
      responseBody['extension'] = List<String>.filled(30000, '€').join();
    }
    request.response.statusCode = mode == _ResponseMode.oversizedErrorBody
        ? HttpStatus.badGateway
        : _responseStatus(body);
    request.response.headers.contentType = ContentType.json;
    if (mode == _ResponseMode.holdBody) {
      request.response.write(jsonEncode(responseBody).substring(0, 8));
      await request.response.flush();
      _hold(request.response);
      _heldBodyCount += 1;
      _heldBodyCounts.add(_heldBodyCount);
      return;
    }

    request.response.write(jsonEncode(responseBody));
    await request.response.close();
  }

  void _hold(HttpResponse response) {
    _heldResponses.add(response);
    unawaited(
      response.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  static int _responseStatus(Map<String, Object?> body) {
    if (!body.containsKey('grant_type') && !body.containsKey('state')) {
      return HttpStatus.unauthorized;
    }
    return HttpStatus.ok;
  }

  static Map<String, Object?> _responseBody(Map<String, Object?> body) {
    switch (body['grant_type']) {
      case 'refresh_token':
        return <String, Object?>{
          'status': 'ok',
          'token_type': 'Bearer',
          'access_token': 'refreshed-access-token',
          'refresh_token': 'refreshed-refresh-token',
        };
      case 'revoke':
        return const <String, Object?>{'status': 'revoked'};
    }
    if (!body.containsKey('state')) {
      return const <String, Object?>{
        'state': 'state-1',
        'challenge': <String, Object?>{},
      };
    }
    return const <String, Object?>{
      'status': 'ok',
      'token_type': 'Bearer',
      'access_token': 'access-token-1',
      'refresh_token': 'refresh-token-1',
    };
  }
}

final class _BlockingAuthentication extends AbstractAuthentication {
  final challengeEntered = Completer<void>();
  final _challengeRelease = Completer<void>();

  @override
  Stream<Extra> get onChallenge => const Stream<Extra>.empty();

  @override
  Future<void> hello(String? realm, Details details) async {}

  @override
  Future<Authenticate> challenge(Extra extra) async {
    challengeEntered.complete();
    await _challengeRelease.future;
    return Authenticate(signature: 'ticket-1');
  }

  void releaseChallenge() {
    if (!_challengeRelease.isCompleted) {
      _challengeRelease.complete();
    }
  }

  @override
  String getName() => 'ticket';
}

final class _DelayedPostHttpClient implements HttpClient {
  _DelayedPostHttpClient(this._delegate);

  final HttpClient _delegate;
  final postStarted = Completer<void>();
  final _postRelease = Completer<void>();

  void releasePost() {
    if (!_postRelease.isCompleted) {
      _postRelease.complete();
    }
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (!postStarted.isCompleted) {
      postStarted.complete();
    }
    await _postRelease.future;
    return _delegate.postUrl(url);
  }

  @override
  dynamic noSuchMethod(dynamic invocation) => super.noSuchMethod(invocation);
}
