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
  });
}

final Matcher _closedStateError = isA<StateError>().having(
  (error) => error.message,
  'message',
  'ConnectanumHttpAuthClient is closed.',
);

enum _ResponseMode { normal, holdHeaders, holdBody }

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
    request.response.statusCode = _responseStatus(body);
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
