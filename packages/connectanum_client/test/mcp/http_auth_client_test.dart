import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectanumHttpAuthClient', () {
    test('issues ticket bearer tokens through the HTTP auth bridge', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind();
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final grant = await client.issueTicketToken(
        realm: 'realm1',
        authId: 'user-1',
        ticket: 'ticket-secret',
      );

      expect(grant.accessToken, 'access-token-1');
      expect(grant.refreshToken, 'refresh-token-1');
      expect(grant.tokenType, 'Bearer');
      expect(grant.realm, 'realm1');
      expect(grant.authId, 'user-1');
      expect(grant.authRole, 'member');
      expect(grant.authMethod, 'ticket');
      expect(grant.authProvider, 'consumer-local');
      expect(grant.accessTokenExpiresIn, const Duration(seconds: 60));
      expect(grant.refreshTokenExpiresIn, const Duration(seconds: 600));
      expect(endpoint.requests, hasLength(2));
      expect(endpoint.requests[0].body, {
        'realm': 'realm1',
        'authmethod': 'ticket',
        'authid': 'user-1',
      });
      expect(endpoint.requests[1].body, {
        'state': 'state-1',
        'signature': 'ticket-secret',
      });
    });

    test(
      'forwards per-call headers while owning JSON request headers',
      () async {
        final endpoint = await _FakeHttpAuthEndpoint.bind();
        addTearDown(endpoint.close);

        final client = ConnectanumHttpAuthClient(
          endpoint.uri,
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer default-auth-bridge',
            HttpHeaders.acceptHeader: 'text/plain',
            HttpHeaders.contentTypeHeader: 'text/plain',
            HttpHeaders.contentLengthHeader: '999',
            'x-consumer-default': 'auth-default',
          },
        );
        addTearDown(() => client.close(force: true));

        final grant = await client.issueTicketToken(
          realm: 'realm1',
          authId: 'user-1',
          ticket: 'ticket-secret',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer issue-auth-bridge',
            HttpHeaders.acceptHeader: 'text/plain',
            HttpHeaders.contentTypeHeader: 'text/plain',
            'x-consumer-trace': 'issue-grant',
          },
        );
        final refreshed = await client.refreshToken(
          grant.refreshToken!,
          headers: const <String, String>{'x-consumer-trace': 'refresh-grant'},
        );
        await client.revokeToken(
          refreshed.refreshToken!,
          tokenTypeHint: 'refresh_token',
          headers: const <String, String>{
            HttpHeaders.authorizationHeader: 'Bearer revoke-auth-bridge',
            'x-consumer-trace': 'revoke-grant',
          },
        );

        expect(endpoint.requests, hasLength(4));
        expect(
          endpoint.requests.map((request) => request.defaultTrace),
          everyElement('auth-default'),
        );
        expect(endpoint.requests[0].consumerTrace, 'issue-grant');
        expect(endpoint.requests[1].consumerTrace, 'issue-grant');
        expect(endpoint.requests[2].consumerTrace, 'refresh-grant');
        expect(endpoint.requests[3].consumerTrace, 'revoke-grant');
        expect(endpoint.requests[0].authorization, 'Bearer issue-auth-bridge');
        expect(endpoint.requests[1].authorization, 'Bearer issue-auth-bridge');
        expect(
          endpoint.requests[2].authorization,
          'Bearer default-auth-bridge',
        );
        expect(endpoint.requests[3].authorization, 'Bearer revoke-auth-bridge');
        for (final request in endpoint.requests) {
          expect(request.accept, 'application/json');
          expect(request.contentType, 'application/json');
        }
      },
    );

    test('uses WAMP-CRA challenge details from the bridge response', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind(
        authMethod: 'wampcra',
        challenge: const <String, Object?>{
          'challenge': 'router-challenge',
          'salt': 'salt',
          'iterations': 2,
          'keylen': 32,
        },
      );
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await client.issueWampCraToken(
        realm: 'realm1',
        authId: 'user-1',
        secret: 'cra-secret',
      );

      final signature = endpoint.requests[1].body['signature'] as String;
      expect(
        signature,
        CraAuthentication.signChallenge(
          secret: 'cra-secret',
          challenge: Extra(
            challenge: 'router-challenge',
            salt: 'salt',
            iterations: 2,
            keyLen: 32,
          ),
        ),
      );
    });

    test('sends SCRAM hello extras using the HTTP auth method name', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind(authMethod: 'scram');
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.authenticate(
          realm: 'realm1',
          authId: 'user-1',
          authentication: _NoopAuthentication('wamp-scram'),
        ),
        completion(isA<ConnectanumHttpAuthGrant>()),
      );

      expect(endpoint.requests.first.body['authmethod'], 'scram');
    });

    test('refreshes and revokes bridge tokens', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind();
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final refreshed = await client.refreshToken(' refresh-token-1 ');
      await client.revokeToken(
        ' ${refreshed.refreshToken!} ',
        tokenTypeHint: 'refresh_token',
      );

      expect(refreshed.accessToken, 'refreshed-access-token');
      expect(endpoint.requests, hasLength(2));
      expect(endpoint.requests[0].body, {
        'grant_type': 'refresh_token',
        'refresh_token': 'refresh-token-1',
      });
      expect(endpoint.requests[1].body, {
        'grant_type': 'revoke',
        'token': 'refreshed-refresh-token',
        'token_type_hint': 'refresh_token',
      });
    });

    test('rejects invalid refresh and revoke tokens before requests', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind();
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      for (final token in ['  ', 'refresh token', 'refresh\token', 'tok\nen']) {
        await expectLater(client.refreshToken(token), throwsArgumentError);
        await expectLater(client.revokeToken(token), throwsArgumentError);
      }

      expect(endpoint.requests, isEmpty);
    });

    test('rejects blank auth request parameters before requests', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind();
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.issueTicketToken(
          realm: '  ',
          authId: 'user-1',
          ticket: 'ticket-secret',
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.issueTicketToken(
          realm: 'realm1',
          authId: '  ',
          ticket: 'ticket-secret',
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.authenticate(
          realm: 'realm1',
          authId: 'user-1',
          authentication: TicketAuthentication('ticket-secret'),
          authMethod: '  ',
        ),
        throwsArgumentError,
      );

      expect(endpoint.requests, isEmpty);
    });

    test('throws typed exceptions for rejected auth requests', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind(failChallenge: true);
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.issueTicketToken(
          realm: 'realm1',
          authId: 'user-1',
          ticket: 'ticket-secret',
        ),
        throwsA(
          isA<ConnectanumHttpAuthException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having(
                (error) => error.error,
                'error',
                containsPair('reason', 'bad_request'),
              ),
        ),
      );
    });

    test('throws typed exceptions for non-JSON auth error bodies', () async {
      final endpoint = await _FakeHttpAuthEndpoint.bind(
        failChallengeWithText: true,
      );
      addTearDown(endpoint.close);

      final client = ConnectanumHttpAuthClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      await expectLater(
        client.issueTicketToken(
          realm: 'realm1',
          authId: 'user-1',
          ticket: 'ticket-secret',
        ),
        throwsA(
          isA<ConnectanumHttpAuthException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.serviceUnavailable,
              )
              .having(
                (error) => error.body,
                'body',
                contains('auth bridge unavailable'),
              )
              .having((error) => error.error, 'error', isNull),
        ),
      );
    });

    test(
      'throws format exceptions for malformed auth grant responses',
      () async {
        final cases = <(Map<String, Object?>, Matcher)>[
          (
            const <String, Object?>{'realm': 123},
            contains('"realm" must be a string'),
          ),
          (
            const <String, Object?>{'access_token': 'bad token'},
            contains('"access_token" must not contain whitespace'),
          ),
          (
            const <String, Object?>{
              'details': <Object?>['not-object'],
            },
            contains('"details" must be a JSON object'),
          ),
        ];

        for (final (grantOverrides, messageMatcher) in cases) {
          final endpoint = await _FakeHttpAuthEndpoint.bind(
            grantOverrides: grantOverrides,
          );
          addTearDown(endpoint.close);

          final client = ConnectanumHttpAuthClient(endpoint.uri);
          addTearDown(() => client.close(force: true));

          await expectLater(
            client.issueTicketToken(
              realm: 'realm1',
              authId: 'user-1',
              ticket: 'ticket-secret',
            ),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                messageMatcher,
              ),
            ),
          );
        }
      },
    );
  });
}

final class _FakeHttpAuthEndpoint {
  _FakeHttpAuthEndpoint._(
    this._server, {
    required this.authMethod,
    required this.challenge,
    required this.grantOverrides,
    required this.failChallenge,
    required this.failChallengeWithText,
  }) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final String authMethod;
  final Map<String, Object?> challenge;
  final Map<String, Object?> grantOverrides;
  final bool failChallenge;
  final bool failChallengeWithText;
  final requests = <_SeenAuthRequest>[];
  late final StreamSubscription<HttpRequest> _subscription;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/auth',
  );

  static Future<_FakeHttpAuthEndpoint> bind({
    String authMethod = 'ticket',
    Map<String, Object?> challenge = const <String, Object?>{},
    Map<String, Object?> grantOverrides = const <String, Object?>{},
    bool failChallenge = false,
    bool failChallengeWithText = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeHttpAuthEndpoint._(
      server,
      authMethod: authMethod,
      challenge: challenge,
      grantOverrides: grantOverrides,
      failChallenge: failChallenge,
      failChallengeWithText: failChallengeWithText,
    );
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final bodyText = await utf8.decoder.bind(request).join();
    final body = Map<String, Object?>.from(jsonDecode(bodyText) as Map);
    requests.add(_SeenAuthRequest.from(request, body));

    switch (body['grant_type']) {
      case 'refresh_token':
        _writeJson(request, <String, Object?>{
          'status': 'ok',
          'token_type': 'Bearer',
          'access_token': 'refreshed-access-token',
          'refresh_token': 'refreshed-refresh-token',
        });
        return;
      case 'revoke':
        _writeJson(request, const <String, Object?>{'status': 'revoked'});
        return;
    }

    if (!body.containsKey('state')) {
      if (failChallenge) {
        _writeJson(request, const <String, Object?>{
          'status': 'error',
          'reason': 'bad_request',
        }, statusCode: HttpStatus.badRequest);
        return;
      }
      if (failChallengeWithText) {
        _writeText(
          request,
          'auth bridge unavailable',
          statusCode: HttpStatus.serviceUnavailable,
        );
        return;
      }
      expect(body['authmethod'], authMethod);
      _writeJson(request, <String, Object?>{
        'state': 'state-1',
        'challenge': challenge,
      }, statusCode: HttpStatus.unauthorized);
      return;
    }

    expect(body['state'], 'state-1');
    expect(
      body['signature'],
      isA<String>().having((value) => value, 'value', isNotEmpty),
    );
    _writeJson(request, <String, Object?>{
      'status': 'ok',
      'token_type': 'Bearer',
      'access_token': 'access-token-1',
      'refresh_token': 'refresh-token-1',
      'realm': 'realm1',
      'authid': 'user-1',
      'authrole': 'member',
      'authmethod': authMethod,
      'authprovider': 'consumer-local',
      'expires_in': 60,
      'refresh_token_expires_in': 600,
      ...grantOverrides,
    });
  }

  void _writeJson(
    HttpRequest request,
    Map<String, Object?> body, {
    int statusCode = HttpStatus.ok,
  }) {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    unawaited(request.response.close());
  }

  void _writeText(
    HttpRequest request,
    String body, {
    int statusCode = HttpStatus.ok,
  }) {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.text;
    request.response.write(body);
    unawaited(request.response.close());
  }
}

final class _SeenAuthRequest {
  _SeenAuthRequest({
    required this.method,
    required this.authorization,
    required this.accept,
    required this.contentType,
    required this.consumerTrace,
    required this.defaultTrace,
    required this.body,
  });

  final String method;
  final String? authorization;
  final String? accept;
  final String? contentType;
  final String? consumerTrace;
  final String? defaultTrace;
  final Map<String, Object?> body;

  factory _SeenAuthRequest.from(
    HttpRequest request,
    Map<String, Object?> body,
  ) {
    return _SeenAuthRequest(
      method: request.method,
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      accept: request.headers.value(HttpHeaders.acceptHeader),
      contentType: request.headers.contentType?.mimeType,
      consumerTrace: request.headers.value('x-consumer-trace'),
      defaultTrace: request.headers.value('x-consumer-default'),
      body: body,
    );
  }
}

final class _NoopAuthentication extends AbstractAuthentication {
  _NoopAuthentication(this._method);

  final String _method;
  final StreamController<Extra> _challengeController =
      StreamController<Extra>.broadcast();

  @override
  Stream<Extra> get onChallenge => _challengeController.stream;

  @override
  Future<void> hello(String? realm, Details details) async {
    details.authextra = <String, Object?>{'nonce': 'client-nonce'};
  }

  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited(_challengeController, extra);
    return Authenticate(signature: 'noop-signature');
  }

  @override
  String getName() => _method;
}
