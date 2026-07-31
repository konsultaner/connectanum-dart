import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP OAuth loopback callback listener', () {
    late HttpServer authorizationServerHost;
    late Uri issuer;
    late McpAuthorizationServerMetadata authorizationServer;

    setUpAll(() async {
      authorizationServerHost = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      issuer = Uri.parse(
        'http://${authorizationServerHost.address.address}:'
        '${authorizationServerHost.port}/issuer',
      );
      authorizationServerHost.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'issuer': issuer.toString(),
            'authorization_endpoint': issuer
                .replace(path: '/authorize')
                .toString(),
            'token_endpoint': issuer.replace(path: '/token').toString(),
            'response_types_supported': <String>['code'],
            'grant_types_supported': <String>['authorization_code'],
            'code_challenge_methods_supported': <String>['S256'],
          }),
        );
        await request.response.close();
      });
      authorizationServer = (await discoverMcpAuthorizationServerMetadata(
        issuer,
      )).metadata;
    });

    tearDownAll(() => authorizationServerHost.close(force: true));

    test('receives one valid callback on an ephemeral IPv4 port', () async {
      final listener = await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri,
      );

      final completion = listener.waitForAuthorizationCode(request: request);
      final response = await _sendCallback(
        listener.redirectUri,
        query: Uri(
          queryParameters: <String, String>{
            'code': 'authorization-code',
            'state': request.state,
          },
        ).query,
      );
      final code = await completion;

      expect(listener.redirectUri.scheme, 'http');
      expect(listener.redirectUri.host, InternetAddress.loopbackIPv4.address);
      expect(listener.redirectUri.port, greaterThan(0));
      expect(listener.redirectUri.path, '/oauth/callback');
      expect(code.code, 'authorization-code');
      expect(code.callbackUri.host, listener.redirectUri.host);
      expect(code.callbackUri.port, listener.redirectUri.port);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.cacheControl, contains('no-store'));
      expect(response.contentSecurityPolicy, contains("default-src 'none'"));
      expect(response.contentTypeOptions, 'nosniff');
      expect(response.body, contains('Authorization complete'));
      expect(response.body, isNot(contains('authorization-code')));
      expect(response.body, isNot(contains(request.state)));
      expect(listener.isClosed, isTrue);
    });

    test('isolates stray requests and ignores a spoofed Host header', () async {
      final listener = await McpOAuthLoopbackCallbackListener.bind(
        path: '/native/callback',
      );
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri,
      );
      final completion = listener.waitForAuthorizationCode(
        request: request,
        maxRequests: 6,
      );

      final wrongPath = await _sendCallback(
        listener.redirectUri,
        path: '/other',
        query: 'state=${Uri.encodeQueryComponent(request.state)}',
      );
      final wrongMethod = await _sendCallback(
        listener.redirectUri,
        method: 'POST',
        query: 'state=${Uri.encodeQueryComponent(request.state)}',
      );
      final wrongState = await _sendCallback(
        listener.redirectUri,
        query: 'code=stray&state=wrong-state',
      );
      final duplicateState = await _sendCallback(
        listener.redirectUri,
        query: 'code=stray&state=${request.state}&state=${request.state}',
      );
      final accepted = await _sendCallback(
        listener.redirectUri,
        hostHeader: 'attacker.example:65535',
        query: 'code=accepted&state=${request.state}',
      );
      final code = await completion;

      expect(wrongPath.statusCode, HttpStatus.notFound);
      expect(wrongMethod.statusCode, HttpStatus.methodNotAllowed);
      expect(wrongMethod.allow, 'GET');
      expect(wrongState.statusCode, HttpStatus.badRequest);
      expect(duplicateState.statusCode, HttpStatus.badRequest);
      expect(accepted.statusCode, HttpStatus.ok);
      expect(code.code, 'accepted');
      expect(code.callbackUri.host, listener.redirectUri.host);
      expect(code.callbackUri.port, listener.redirectUri.port);
      expect(code.callbackUri.host, isNot('attacker.example'));
    });

    test('returns a static page and preserves a typed OAuth error', () async {
      final listener = await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri,
      );
      final completion = listener.waitForAuthorizationCode(request: request);
      final expectation = expectLater(
        completion,
        throwsA(
          isA<McpAuthorizationFlowException>()
              .having(
                (error) => error.oauthError,
                'oauthError',
                'access_denied',
              )
              .having(
                (error) => error.errorDescription,
                'errorDescription',
                'private browser detail',
              )
              .having(
                (error) => error.toString(),
                'redacted toString',
                isNot(contains('private browser detail')),
              ),
        ),
      );

      final response = await _sendCallback(
        listener.redirectUri,
        query: Uri(
          queryParameters: <String, String>{
            'error': 'access_denied',
            'error_description': 'private browser detail',
            'state': request.state,
          },
        ).query,
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.body, contains('Authorization failed'));
      expect(response.body, isNot(contains('access_denied')));
      expect(response.body, isNot(contains('private browser detail')));
      expect(response.body, isNot(contains(request.state)));
      await expectation;
      expect(listener.isClosed, isTrue);
    });

    test('times out once and closes without exposing request state', () async {
      final listener = await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri,
      );

      await expectLater(
        listener.waitForAuthorizationCode(
          request: request,
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(
          isA<McpOAuthLoopbackCallbackException>().having(
            (error) => error.toString(),
            'redacted toString',
            isNot(contains(request.state)),
          ),
        ),
      );

      expect(listener.isClosed, isTrue);
      await expectLater(
        listener.waitForAuthorizationCode(request: request),
        throwsA(isA<McpOAuthLoopbackCallbackException>()),
      );
    });

    test('bounds unrelated local requests and closes the listener', () async {
      final listener = await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri,
      );
      final completion = listener.waitForAuthorizationCode(
        request: request,
        maxRequests: 2,
      );
      final expectation = expectLater(
        completion,
        throwsA(isA<McpOAuthLoopbackCallbackException>()),
      );

      expect(
        (await _sendCallback(
          listener.redirectUri,
          query: 'state=wrong-one',
        )).statusCode,
        HttpStatus.badRequest,
      );
      expect(
        (await _sendCallback(
          listener.redirectUri,
          query: 'state=wrong-two',
        )).statusCode,
        HttpStatus.badRequest,
      );

      await expectation;
      expect(listener.isClosed, isTrue);
    });

    test('rejects unsafe binding and waiting configuration', () async {
      await expectLater(
        McpOAuthLoopbackCallbackListener.bind(
          address: InternetAddress('192.0.2.1'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        McpOAuthLoopbackCallbackListener.bind(port: -1),
        throwsArgumentError,
      );
      await expectLater(
        McpOAuthLoopbackCallbackListener.bind(port: 65536),
        throwsArgumentError,
      );
      await expectLater(
        McpOAuthLoopbackCallbackListener.bind(path: 'relative/callback'),
        throwsArgumentError,
      );
      await expectLater(
        McpOAuthLoopbackCallbackListener.bind(path: '//other/callback'),
        throwsArgumentError,
      );
      await expectLater(
        McpOAuthLoopbackCallbackListener.bind(path: '/callback?state=fixed'),
        throwsArgumentError,
      );

      final listener = await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri,
      );
      await expectLater(
        listener.waitForAuthorizationCode(
          request: request,
          timeout: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(listener.isClosed, isTrue);

      final requestBoundListener =
          await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(requestBoundListener.close);
      final requestBoundAuthorization = _authorizationRequest(
        authorizationServer,
        issuer,
        requestBoundListener.redirectUri,
      );
      await expectLater(
        requestBoundListener.waitForAuthorizationCode(
          request: requestBoundAuthorization,
          maxRequests: 0,
        ),
        throwsArgumentError,
      );
      expect(requestBoundListener.isClosed, isTrue);
    });

    test('maps external closure to a typed one-shot failure', () async {
      final listener = await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri,
      );
      final expectation = expectLater(
        listener.waitForAuthorizationCode(request: request),
        throwsA(isA<McpOAuthLoopbackCallbackException>()),
      );

      await listener.close();

      await expectation;
      expect(listener.isClosed, isTrue);
    });

    test(
      'supports an explicit IPv6 loopback redirect when available',
      () async {
        McpOAuthLoopbackCallbackListener listener;
        try {
          listener = await McpOAuthLoopbackCallbackListener.bind(
            address: InternetAddress.loopbackIPv6,
          );
        } on SocketException {
          return;
        }
        addTearDown(listener.close);

        expect(listener.redirectUri.host, InternetAddress.loopbackIPv6.address);
        expect(listener.redirectUri.toString(), contains('[::1]'));
      },
    );

    test('rejects a request registered for a different redirect', () async {
      final listener = await McpOAuthLoopbackCallbackListener.bind();
      addTearDown(listener.close);
      final request = _authorizationRequest(
        authorizationServer,
        issuer,
        listener.redirectUri.replace(port: listener.redirectUri.port + 1),
      );

      await expectLater(
        listener.waitForAuthorizationCode(request: request),
        throwsA(isA<McpOAuthLoopbackCallbackException>()),
      );

      expect(listener.isClosed, isTrue);
    });
  });
}

McpAuthorizationRequest _authorizationRequest(
  McpAuthorizationServerMetadata authorizationServer,
  Uri issuer,
  Uri redirectUri,
) => createMcpAuthorizationRequest(
  authorizationServer: authorizationServer,
  resource: issuer.replace(path: '/mcp'),
  clientId: 'consumer-client',
  redirectUri: redirectUri,
);

Future<
  ({
    String? allow,
    String body,
    String? cacheControl,
    String? contentSecurityPolicy,
    String? contentTypeOptions,
    int statusCode,
  })
>
_sendCallback(
  Uri redirectUri, {
  String method = 'GET',
  String? path,
  String? query,
  String? hostHeader,
}) async {
  final client = HttpClient();
  try {
    final callback = redirectUri.replace(path: path, query: query);
    final request = await client.openUrl(method, callback);
    if (hostHeader != null) {
      request.headers.set(HttpHeaders.hostHeader, hostHeader);
    }
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (
      allow: response.headers.value(HttpHeaders.allowHeader),
      body: body,
      cacheControl: response.headers.value(HttpHeaders.cacheControlHeader),
      contentSecurityPolicy: response.headers.value('content-security-policy'),
      contentTypeOptions: response.headers.value('x-content-type-options'),
      statusCode: response.statusCode,
    );
  } finally {
    client.close(force: true);
  }
}
