part of '../router_runtime_test.dart';

class _HttpEdgeHandshake implements NativeHttpHandshake {
  _HttpEdgeHandshake(this.delegate);

  final NativeHttpHandshake delegate;
  int releases = 0;

  @override
  int get handle => delegate.handle;
  @override
  String get method => delegate.method;
  @override
  String get target => delegate.target;
  @override
  String get path => delegate.path;
  @override
  String get protocol => delegate.protocol;
  @override
  int get version => delegate.version;
  @override
  Map<String, String> get headers => delegate.headers;
  @override
  Map<String, List<String>> get headerValues => delegate.headerValues;
  @override
  Set<String> get duplicateHeaderNames => delegate.duplicateHeaderNames;
  @override
  NativeHttpRequestBody get body => delegate.body;
  @override
  String? get query => delegate.query;
  @override
  String? get realm => delegate.realm;
  @override
  String? get procedure => delegate.procedure;

  @override
  void release() {
    releases++;
    delegate.release();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HttpEdgeFixture {
  _HttpEdgeFixture(this.runtime, this.binding, this.events, this.handled);

  final _HandleRuntime runtime;
  final RouterBinding binding;
  final List<Map<String, Object?>> events;
  final List<RouterHttpRequest> handled;
  final handshakes = <_HttpEdgeHandshake>[];
  int nextId = 23000;

  static Future<_HttpEdgeFixture> start(
    List<HttpRouteSettings> routes, {
    FutureOr<NativeHttpResponse> Function(RouterHttpRequest)? handler,
    _HandleRuntime? nativeRuntime,
  }) async {
    final runtime = nativeRuntime ?? _HandleRuntime();
    final builder = RouterSettingsBuilder()
      ..addRealmFromBuilder(
        RealmSettingsBuilder('realm1')
          ..addAuthMethod('anonymous')
          ..addRoleFromBuilder(
            RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
              PermissionSettingsBuilder('')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations([
                  'subscribe',
                  'unsubscribe',
                  'publish',
                ]),
            ),
          ),
      )
      ..addSessionProfileFromBuilder(
        SessionProfileSettingsBuilder('protected')
          ..setRealm('realm1')
          ..addAuthMethod('ticket'),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('http', '127.0.0.1:0')
          ..addProtocol(ListenerProtocol.http)
          ..setHttpOptions(HttpListenerSettings(routes: routes)),
      );
    final handled = <RouterHttpRequest>[];
    final events = <Map<String, Object?>>[];
    final binding =
        Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.native,
                maxRawSocketSizeExponent: 16,
                sniCertificates: [_cert('localhost')],
              ),
            ],
          ),
          settings: builder.build(),
        ).start(
          runtime,
          httpRouteHandlers: {
            'edge': (request) async {
              handled.add(request);
              return handler == null
                  ? NativeHttpResponse(
                      status: HttpStatus.ok,
                      body: NativeHttpResponseJson({'path': request.path}),
                    )
                  : await handler(request);
            },
          },
          onEvent: (event) {
            if (event is Map<String, Object?>) events.add(event);
          },
        );
    final fixture = _HttpEdgeFixture(runtime, binding, events, handled);
    addTearDown(() async {
      await binding.dispose();
      for (final handshake in fixture.handshakes) {
        expect(
          handshake.releases,
          1,
          reason: 'Disposal must not release twice',
        );
      }
    });
    await Future<void>.delayed(Duration.zero);
    return fixture;
  }

  Future<NativeHttpResponse> request({
    String path = '/edge',
    String method = 'GET',
    String protocol = 'http/1.1',
    Map<String, String> headers = const {},
    String? realm = 'realm1',
    Uint8List? body,
    String? query,
  }) async {
    final id = nextId++;
    final handshake = _HttpEdgeHandshake(
      NativeHttpHandshake.synthetic(
        handle: id,
        method: method,
        target: query == null ? path : '$path?$query',
        path: path,
        query: query,
        protocol: protocol,
        realm: realm,
        procedure: 'router.http.publish',
        headers: headers,
        body: body ?? Uint8List(0),
      ),
    );
    handshakes.add(handshake);
    runtime.setConnectionProtocol(id, NativeConnectionProtocol.http);
    runtime.enqueueHttpHandshake(
      binding.listeners.single.listenerId,
      id,
      handshake,
    );
    await _waitUntil(
      () => runtime.httpResponses[id]?.isNotEmpty ?? false,
      timeout: const Duration(seconds: 3),
    );
    await Future<void>.delayed(Duration.zero);
    expect(handshake.releases, 1, reason: 'Every HTTP request releases once');
    return runtime.httpResponses[id]!.single;
  }
}

HttpRouteSettings _edgeHandlerRoute(HttpRouteMatch match) => HttpRouteSettings(
  match: match,
  action: const HttpRouteAction(
    type: HttpRouteActionType.handler,
    delegate: 'edge',
  ),
);

void _httpEdgeCases() {
  group('HTTP edge contracts', () {
    _proxyEdgeCases();
    for (final (label, match, path, headers, expectedStatus)
        in <(String, HttpRouteMatch, String, Map<String, String>, int)>[
          (
            'path takes precedence',
            const HttpRouteMatch(path: '/edge', prefix: '/other'),
            '/edge',
            {},
            200,
          ),
          (
            'path rejects prefix fallback',
            const HttpRouteMatch(path: '/other', prefix: '/edge'),
            '/edge',
            {},
            404,
          ),
          (
            'prefix mismatch',
            const HttpRouteMatch(prefix: '/other'),
            '/edge',
            {},
            404,
          ),
          (
            'prefix suffix',
            const HttpRouteMatch(prefix: '/edge'),
            '/edge/child',
            {},
            200,
          ),
          (
            'host absent',
            const HttpRouteMatch(path: '/edge', host: 'consumer.example'),
            '/edge',
            {},
            404,
          ),
          (
            'host mismatch',
            const HttpRouteMatch(path: '/edge', host: 'consumer.example'),
            '/edge',
            {'host': 'other.example'},
            404,
          ),
          (
            'host case and port',
            const HttpRouteMatch(path: '/edge', host: ' Consumer.Example '),
            '/edge',
            {'HOST': 'CONSUMER.EXAMPLE:8443'},
            200,
          ),
          (
            'header name case',
            const HttpRouteMatch(path: '/edge', headers: {'X-Tenant': 'a'}),
            '/edge',
            {'x-tenant': 'a'},
            200,
          ),
          (
            'header value case',
            const HttpRouteMatch(path: '/edge', headers: {'x-tenant': 'a'}),
            '/edge',
            {'X-TENANT': 'A'},
            404,
          ),
          (
            'header missing',
            const HttpRouteMatch(path: '/edge', headers: {'x-tenant': 'a'}),
            '/edge',
            {},
            404,
          ),
          (
            'all headers required',
            const HttpRouteMatch(
              path: '/edge',
              headers: {'x-tenant': 'a', 'x-region': 'eu'},
            ),
            '/edge',
            {'x-tenant': 'a'},
            404,
          ),
        ]) {
      test('route matching $label', () async {
        final fixture = await _HttpEdgeFixture.start([
          _edgeHandlerRoute(match),
        ]);
        final response = await fixture.request(path: path, headers: headers);
        expect(response.status, expectedStatus);
        expect(fixture.handled, hasLength(expectedStatus == 200 ? 1 : 0));
        expect(
          _jsonResponseBody(response),
          expectedStatus == 200
              ? {'path': path}
              : containsPair('reason', 'route_not_found'),
        );
      });
    }

    test(
      'method diagnostics aggregate only matching hosts and headers',
      () async {
        final fixture = await _HttpEdgeFixture.start([
          _edgeHandlerRoute(
            const HttpRouteMatch(path: '/edge', methods: ['POST', 'GET']),
          ),
          _edgeHandlerRoute(
            const HttpRouteMatch(path: '/edge', methods: ['PATCH', 'POST']),
          ),
          _edgeHandlerRoute(
            const HttpRouteMatch(
              path: '/edge',
              host: 'private.example',
              methods: ['DELETE'],
            ),
          ),
          _edgeHandlerRoute(
            const HttpRouteMatch(
              path: '/edge',
              headers: {'x-secret': 'yes'},
              methods: ['PUT'],
            ),
          ),
        ]);
        final response = await fixture.request(method: 'OPTIONS');
        expect(response.status, HttpStatus.methodNotAllowed);
        expect(response.headers[HttpHeaders.allowHeader], 'GET, PATCH, POST');
        expect(fixture.handled, isEmpty);
        expect(_jsonResponseBody(response)['reason'], 'method_not_allowed');
        expect((await fixture.request(method: 'POST')).status, HttpStatus.ok);
        expect(fixture.handled, hasLength(1));
      },
    );

    test('protocol diagnostics omit routes with another host', () async {
      final fixture = await _HttpEdgeFixture.start([
        _edgeHandlerRoute(
          const HttpRouteMatch(path: '/edge', protocols: ['h2']),
        ),
        _edgeHandlerRoute(
          const HttpRouteMatch(path: '/edge', protocols: ['http/3']),
        ),
        _edgeHandlerRoute(
          const HttpRouteMatch(
            path: '/edge',
            host: 'private.example',
            protocols: ['http/1.0'],
          ),
        ),
      ]);
      final response = await fixture.request();
      expect(response.status, HttpStatus.upgradeRequired);
      expect(response.headers[HttpHeaders.upgradeHeader], 'http2, http3');
      expect(_jsonResponseBody(response)['reason'], 'protocol_not_allowed');
      expect(fixture.handled, isEmpty);
      expect((await fixture.request(protocol: 'http/2')).status, HttpStatus.ok);
      expect(fixture.handled, hasLength(1));
    });

    for (final asynchronous in [false, true]) {
      test(
        'handler failure ($asynchronous) is sanitized and recoverable',
        () async {
          var fail = true;
          final fixture = await _HttpEdgeFixture.start(
            [
              _edgeHandlerRoute(const HttpRouteMatch(path: '/edge')),
            ],
            handler: (request) {
              if (fail) {
                final error = StateError('private-backend-secret');
                if (asynchronous) {
                  return Future<NativeHttpResponse>.error(error);
                }
                throw error;
              }
              return NativeHttpResponse(
                status: HttpStatus.noContent,
                body: NativeHttpResponseBytes(Uint8List(0)),
              );
            },
          );
          final response = await fixture.request();
          expect(response.status, HttpStatus.internalServerError);
          expect(_jsonResponseBody(response), {
            'status': 'error',
            'reason': 'handler_failed',
            'message': 'HTTP route handler failed',
          });
          expect(
            fixture.events.where(
              (event) => event['type'] == 'http_handler_error',
            ),
            hasLength(1),
          );
          fail = false;
          expect((await fixture.request()).status, HttpStatus.noContent);
          expect(fixture.handled, hasLength(2));
          expect(
            fixture.events.where(
              (event) => event['type'] == 'http_handler_response_sent',
            ),
            hasLength(1),
          );
        },
      );
    }

    for (final topic in <String?>[null, '', '   ']) {
      test('publish rejects missing topic $topic', () async {
        final runtime = _HandleRuntime();
        await expectLater(
          _HttpEdgeFixture.start([
            HttpRouteSettings(
              match: const HttpRouteMatch(path: '/edge'),
              action: HttpRouteAction(
                type: HttpRouteActionType.publish,
                realm: 'realm1',
                topic: topic,
              ),
            ),
          ], nativeRuntime: runtime),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'reason',
              contains('require a topic'),
            ),
          ),
        );
        expect(runtime.listenCalls, isEmpty);
        expect(runtime.appliedConfig, isNull);
        expect(runtime.httpResponses, isEmpty);
      });
    }

    for (final realm in <String?>[null, '']) {
      test('publish rejects missing native mapping realm $realm', () async {
        final fixture = await _HttpEdgeFixture.start([
          const HttpRouteSettings(
            match: HttpRouteMatch(path: '/edge'),
            action: HttpRouteAction(
              type: HttpRouteActionType.publish,
              topic: 'com.example.events',
            ),
          ),
        ]);
        final response = await fixture.request(method: 'POST', realm: realm);
        expect(response.status, HttpStatus.internalServerError);
        expect(_jsonResponseBody(response)['reason'], 'publish_realm_missing');
        expect(
          fixture.events.where(
            (event) => event['type'] == 'http_publish_unmapped_realm',
          ),
          hasLength(1),
        );
        expect(
          fixture.events.where(
            (event) => event['type'] == 'http_publish_dispatched',
          ),
          isEmpty,
        );
      });
    }

    for (final protected in [false, true]) {
      test(
        'publish invalid bearer never falls back to anonymous ($protected)',
        () async {
          final fixture = await _HttpEdgeFixture.start([
            HttpRouteSettings(
              match: const HttpRouteMatch(path: '/edge'),
              action: HttpRouteAction(
                type: HttpRouteActionType.publish,
                topic: 'com.example.events',
                sessionProfile: protected ? 'protected' : null,
              ),
            ),
          ]);
          final response = await fixture.request(
            method: 'POST',
            headers: {'authorization': 'Bearer unrecognized-secret'},
          );
          expect(response.status, HttpStatus.unauthorized);
          expect(
            response.headers[HttpHeaders.wwwAuthenticateHeader],
            contains('Bearer'),
          );
          expect(
            jsonEncode(_jsonResponseBody(response)),
            isNot(contains('unrecognized-secret')),
          );
          expect(
            fixture.events.where(
              (event) => event['type'] == 'http_publish_dispatched',
            ),
            isEmpty,
          );
        },
      );
    }

    test('publish protected profile requires a bearer token', () async {
      final fixture = await _HttpEdgeFixture.start([
        const HttpRouteSettings(
          match: HttpRouteMatch(path: '/edge'),
          action: HttpRouteAction(
            type: HttpRouteActionType.publish,
            topic: 'com.example.events',
            sessionProfile: 'protected',
          ),
        ),
      ]);
      final response = await fixture.request(method: 'POST');
      expect(response.status, HttpStatus.unauthorized);
      expect(_jsonResponseBody(response)['message'], 'Bearer token required');
      expect(
        fixture.events.where(
          (event) => event['type'] == 'http_publish_dispatched',
        ),
        isEmpty,
      );
    });

    for (final (type, options, reason)
        in <(HttpRouteActionType, Map<String, Object?>, String)>[
          (HttpRouteActionType.reverseProxy, {}, 'missing_target'),
          (
            HttpRouteActionType.reverseProxy,
            {'target': 'http://'},
            'invalid_target',
          ),
          (
            HttpRouteActionType.reverseProxy,
            {'target': 'http://[bad'},
            'invalid_target',
          ),
          (HttpRouteActionType.fastCgi, {}, 'missing_target'),
          (HttpRouteActionType.fastCgi, {'target': 'unix:'}, 'invalid_target'),
          (
            HttpRouteActionType.fastCgi,
            {'target': 'https://private.example'},
            'invalid_target',
          ),
          (
            HttpRouteActionType.fastCgi,
            {'target': 'tcp://:9000'},
            'invalid_target',
          ),
          (
            HttpRouteActionType.fastCgi,
            {'target': 'tcp://127.0.0.1'},
            'invalid_target',
          ),
          (
            HttpRouteActionType.fastCgi,
            {'target': 'tcp://127.0.0.1:65536'},
            'invalid_target',
          ),
          (
            HttpRouteActionType.fastCgi,
            {'target': 'tcp://127.0.0.1:9000'},
            'missing_script_mapping',
          ),
          (
            HttpRouteActionType.fastCgi,
            {'target': 'tcp://127.0.0.1:9000', 'timeoutMs': ' 0 '},
            'invalid_option',
          ),
          (
            HttpRouteActionType.fastCgi,
            {'target': 'tcp://127.0.0.1:9000', 'maxResponseBytes': -1},
            'invalid_option',
          ),
        ]) {
      test(
        'adapter configuration ${type.name} $options fails closed',
        () async {
          if (reason == 'missing_target') {
            final runtime = _HandleRuntime();
            await expectLater(
              _HttpEdgeFixture.start([
                HttpRouteSettings(
                  match: const HttpRouteMatch(path: '/edge'),
                  action: HttpRouteAction(type: type, options: options),
                ),
              ], nativeRuntime: runtime),
              throwsA(
                isA<StateError>().having(
                  (error) => error.message,
                  'reason',
                  contains('require an adapter endpoint'),
                ),
              ),
            );
            expect(runtime.listenCalls, isEmpty);
            expect(runtime.appliedConfig, isNull);
            expect(runtime.httpResponses, isEmpty);
            return;
          }
          final fixture = await _HttpEdgeFixture.start([
            HttpRouteSettings(
              match: const HttpRouteMatch(path: '/edge'),
              action: HttpRouteAction(type: type, options: options),
            ),
          ]);
          final response = await fixture.request();
          final prefix = type == HttpRouteActionType.fastCgi
              ? 'fastcgi'
              : 'reverse_proxy';
          expect(response.status, HttpStatus.badGateway);
          expect(_jsonResponseBody(response)['reason'], '${prefix}_$reason');
          expect(
            jsonEncode(_jsonResponseBody(response)),
            isNot(contains('private.example')),
          );
          expect(
            fixture.events.where(
              (event) => event['type'] == 'http_${prefix}_config_error',
            ),
            hasLength(1),
          );
          expect(
            fixture.events.where(
              (event) => event['type'] == 'http_${prefix}_request',
            ),
            isEmpty,
          );
          expect(fixture.handled, isEmpty);
        },
      );
    }
  });
}

void _proxyEdgeCases() {
  for (final status in [200, 401, 500]) {
    test(
      'reverse proxy cookie fields cross the native wire for $status',
      () async {
        const cookies = [
          'session=opaque; Expires=Wed, 09 Jun 2032 10:18:14 GMT; HttpOnly; Secure',
          'language=de; Path=/; SameSite=Lax',
          'removed=; Max-Age=0; Path=/',
        ];
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = upstream.listen((request) async {
          await request.drain<void>();
          request.response.statusCode = status;
          request.response.headers.add(HttpHeaders.setCookieHeader, cookies);
          request.response.add([0, 128, 255]);
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await upstream.close(force: true);
        });
        final runtime = NativeTransportRuntime(
          libraryPath: Platform.environment['CONNECTANUM_NATIVE_LIB'],
        )..start();
        addTearDown(() {
          try {
            runtime.shutdown();
          } finally {
            runtime.dispose();
          }
        });
        final settings = RouterSettingsBuilder()
          ..addListenerFromBuilder(
            ListenerSettingsBuilder('http', '127.0.0.1:0')
              ..addProtocol(ListenerProtocol.http)
              ..setHttpOptions(
                HttpListenerSettings(
                  routes: [
                    HttpRouteSettings(
                      match: const HttpRouteMatch(path: '/edge'),
                      action: HttpRouteAction(
                        type: HttpRouteActionType.reverseProxy,
                        delegate: 'http://127.0.0.1:${upstream.port}',
                      ),
                    ),
                  ],
                ),
              ),
          );
        final binding = Router(
          RouterConfig(
            endpoints: [
              Endpoint(
                host: '127.0.0.1',
                port: 0,
                tlsMode: TlsMode.disabled,
                maxRawSocketSizeExponent: 16,
                sniCertificates: const [],
              ),
            ],
          ),
          settings: settings.build(),
        ).start(runtime);
        addTearDown(binding.dispose);
        final port = runtime.getLocalPort(binding.listeners.single.listenerId);
        expect(port, greaterThan(0));
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/edge'),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        final body = await response.fold<List<int>>(
          [],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        expect(response.statusCode, status);
        expect(body, [0, 128, 255]);
        expect(response.headers[HttpHeaders.setCookieHeader], cookies);
        expect(response.cookies.map((cookie) => cookie.name), [
          'session',
          'language',
          'removed',
        ]);
      },
    );
  }

  for (final status in [200, 401, 500]) {
    test(
      'reverse proxy preserves distinct cookies and headers for $status',
      () async {
        const cookies = [
          'session=opaque; Expires=Wed, 09 Jun 2032 10:18:14 GMT; HttpOnly; Secure',
          'language=de; Path=/; SameSite=Lax',
          'removed=; Max-Age=0; Path=/',
        ];
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = upstream.listen((request) async {
          await request.drain<void>();
          request.response.statusCode = status;
          request.response.headers
            ..add(HttpHeaders.setCookieHeader, cookies)
            ..add('x-repeat', ['first', 'second'])
            ..noFolding('x-repeat')
            ..add(HttpHeaders.connectionHeader, ['x-private', 'x-other'])
            ..add('x-private', ['secret-one', 'secret-two'])
            ..add('x-other', 'secret-three');
          request.response.add([0, 1, 128, 255]);
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await upstream.close(force: true);
        });
        final fixture = await _HttpEdgeFixture.start([
          HttpRouteSettings(
            match: const HttpRouteMatch(path: '/edge'),
            action: HttpRouteAction(
              type: HttpRouteActionType.reverseProxy,
              delegate: 'http://127.0.0.1:${upstream.port}',
            ),
          ),
        ]);
        final response = await fixture.request();
        expect(response.status, status);
        expect((response.body as NativeHttpResponseBytes).bytes, [
          0,
          1,
          128,
          255,
        ]);
        final entries = [
          ...response.headers.entries,
          ...response.additionalHeaders,
        ];
        expect(
          entries
              .where((entry) => entry.key.toLowerCase() == 'set-cookie')
              .map((entry) => entry.value),
          cookies,
        );
        expect(
          entries
              .where((entry) => entry.key.toLowerCase() == 'x-repeat')
              .map((entry) => entry.value),
          ['first', 'second'],
        );
        for (final name in [
          'connection',
          'content-length',
          'transfer-encoding',
          'x-private',
          'x-other',
        ]) {
          expect(
            entries.where((entry) => entry.key.toLowerCase() == name),
            isEmpty,
            reason: '$name is hop-by-hop or recomputed',
          );
        }
        expect(
          fixture.events.where(
            (event) => event['type'] == 'http_reverse_proxy_response_sent',
          ),
          hasLength(1),
        );
      },
    );
  }

  for (final (option, strip) in <(Object, bool)>[
    (true, true),
    (' TRUE ', true),
    ('yes', true),
    ('1', true),
    ('on', true),
    (false, false),
    (' FALSE ', false),
    ('no', false),
    ('0', false),
    ('off', false),
    ('unknown', false),
    (1, false),
  ]) {
    test(
      'reverse proxy strip-prefix option $option (${option.runtimeType}) preserves request',
      () async {
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, Object?>>[];
        final subscription = upstream.listen((request) async {
          final bytes = await request.fold<List<int>>(
            [],
            (result, chunk) => result..addAll(chunk),
          );
          requests.add({
            'method': request.method,
            'uri': request.uri.toString(),
            'body': bytes,
            'host': request.headers.value('host'),
            'forwardedHost': request.headers.value('x-forwarded-host'),
            'secret': request.headers.value('x-secret'),
          });
          request.response
            ..statusCode = HttpStatus.created
            ..write('accepted');
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await upstream.close(force: true);
        });
        final fixture = await _HttpEdgeFixture.start([
          HttpRouteSettings(
            match: const HttpRouteMatch(prefix: '/edge'),
            action: HttpRouteAction(
              type: HttpRouteActionType.reverseProxy,
              options: {
                'targetUrl': 'http://127.0.0.1:${upstream.port}/base/?fixed=a',
                'stripPrefix': option,
                'timeoutMs': ' 2000 ',
                'maxResponseBytes': 8.0,
              },
            ),
          ),
        ]);
        final response = await fixture.request(
          path: '/edge/child',
          method: 'POST',
          query: 'item=b',
          headers: {
            'host': 'consumer.example:443',
            'connection': 'x-secret',
            'x-secret': 'sensitive',
          },
          body: Uint8List.fromList([0, 128, 255]),
        );
        expect(response.status, HttpStatus.created);
        expect(
          (response.body as NativeHttpResponseBytes).bytes,
          utf8.encode('accepted'),
        );
        expect(requests, [
          {
            'method': 'POST',
            'uri': strip
                ? '/base/child?fixed=a&item=b'
                : '/base/edge/child?fixed=a&item=b',
            'body': [0, 128, 255],
            'host': 'consumer.example:443',
            'forwardedHost': 'consumer.example:443',
            'secret': null,
          },
        ]);
      },
    );
  }
}
