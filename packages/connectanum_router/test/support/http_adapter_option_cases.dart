part of router_runtime_test;

void registerHttpAdapterOptionCases() {
  test('reverse proxy numeric aliases preserve minimum and recovery', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    var bodyLength = 1;
    final subscription = upstream.listen((request) async {
      requests++;
      request.response
        ..statusCode = HttpStatus.ok
        ..add(List<int>.filled(bodyLength, 65));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await upstream.close(force: true);
    });
    final optionsCases = <Map<String, Object?>>[
      for (final value in [1, 1.9, ' 1 '])
        {'max_response_bytes': value, 'maxResponseBytes': 2},
      for (final value in [null, 'unknown', true, <String>[]])
        {'max_response_bytes': value, 'maxResponseBytes': 1},
      {'maxResponseBytes': 1},
    ];
    for (final options in optionsCases) {
      final fixture = await _ProxyResponseFixture.start({
        'target': 'http://${upstream.address.host}:${upstream.port}/',
        ...options,
      });
      final initialRequests = requests;
      for (final length in [1, 2, 1]) {
        bodyLength = length;
        final response = await fixture.request();
        if (length == 1) {
          expect(response.status, HttpStatus.ok, reason: '$options');
          expect((response.body as NativeHttpResponseBytes).bytes, [65]);
        } else {
          expect(response.status, HttpStatus.badGateway, reason: '$options');
          expect(
            _jsonResponseBody(response)['reason'],
            'reverse_proxy_response_too_large',
          );
        }
      }
      expect(requests, initialRequests + 3, reason: '$options');
      expect(
        fixture.events.where(
          (event) => event['type'] == 'http_reverse_proxy_response_sent',
        ),
        hasLength(2),
      );
      expect(
        fixture.events.where(
          (event) => event['type'] == 'http_reverse_proxy_error',
        ),
        hasLength(1),
      );
      await fixture.binding.dispose();
    }
    for (final value in [0, -1, 0.9, ' 0 ']) {
      final fixture = await _ProxyResponseFixture.start({
        'target': 'http://${upstream.address.host}:${upstream.port}/',
        'max_response_bytes': value,
        'maxResponseBytes': 1,
      });
      final previousRequests = requests;
      final response = await fixture.request();
      expect(response.status, HttpStatus.badGateway);
      expect(
        _jsonResponseBody(response)['reason'],
        'reverse_proxy_invalid_option',
      );
      expect(
        requests,
        previousRequests,
        reason: 'Invalid first alias must not fall back or connect.',
      );
      await fixture.binding.dispose();
    }
  });
  test(
    'reverse proxy boolean aliases preserve precedence and fallback',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      final subscription = upstream.listen((request) async {
        requests.add(request.uri.toString());
        request.response
          ..statusCode = HttpStatus.ok
          ..write(request.uri.path);
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await upstream.close(force: true);
      });
      final cases = <(Map<String, Object?>, String)>[
        for (final value in [false, 'false', '0', 'no', 'off', '  FaLsE  '])
          (
            {'strip_prefix': value, 'stripPrefix': true},
            '/backend/api/resource',
          ),
        for (final value in [true, 'true', '1', 'yes', 'on', '  YeS  '])
          ({'strip_prefix': value, 'stripPrefix': false}, '/backend/resource'),
        for (final value in [null, '', 'unknown', 0, 1, <String>[]])
          ({'strip_prefix': value, 'stripPrefix': true}, '/backend/resource'),
        ({}, '/backend/api/resource'),
        (
          {'strip_prefix': 'unknown', 'stripPrefix': 'unknown'},
          '/backend/api/resource',
        ),
      ];
      for (final (options, expectedPath) in cases) {
        final fixture = await _ProxyResponseFixture.start({
          'target': 'http://${upstream.address.host}:${upstream.port}/backend',
          ...options,
        });
        final previousCount = requests.length;
        final response = await fixture.request();
        expect(response.status, HttpStatus.ok, reason: '$options');
        expect(requests.length, previousCount + 1, reason: '$options');
        expect(requests.last, expectedPath, reason: '$options');
        expect(
          utf8.decode((response.body as NativeHttpResponseBytes).bytes),
          expectedPath,
          reason: '$options',
        );
        await fixture.binding.dispose();
      }
      expect(requests, hasLength(cases.length));
    },
  );
  test(
    'handler route option aliases preserve configured callback identity',
    () async {
      const aliases = [
        'handler',
        'handler_id',
        'handlerId',
        'callback',
        'callback_id',
        'callbackId',
      ];
      final runtime = _HandleRuntime();
      final routes = <HttpRouteSettings>[];
      for (var index = 0; index < aliases.length; index++) {
        routes.add(
          HttpRouteSettings(
            match: HttpRouteMatch(path: '/handler-$index'),
            action: HttpRouteAction(
              type: HttpRouteActionType.handler,
              options: <String, Object?>{aliases[index]: '  callback-$index  '},
            ),
          ),
        );
      }
      final settings = RouterSettingsBuilder()
        ..addListenerFromBuilder(
          ListenerSettingsBuilder('http', '127.0.0.1:0')
            ..addProtocol(ListenerProtocol.http)
            ..setHttpOptions(HttpListenerSettings(routes: routes)),
        );
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
            settings: settings.build(),
          ).start(
            runtime,
            onEvent: (event) {
              if (event is Map<String, Object?>) events.add(event);
            },
          );
      addTearDown(binding.dispose);
      await Future<void>.delayed(Duration.zero);
      final listenerId = binding.listeners.single.listenerId;
      for (var index = 0; index < aliases.length; index++) {
        final connectionId = 500 + index;
        runtime.setConnectionProtocol(
          connectionId,
          NativeConnectionProtocol.http,
        );
        final path = '/handler-$index';
        runtime.enqueueHttpHandshake(
          listenerId,
          connectionId,
          NativeHttpHandshake.synthetic(
            handle: connectionId,
            method: 'GET',
            target: path,
            path: path,
            protocol: 'http/1.1',
            headers: const {},
            body: Uint8List(0),
            realm: 'router.http',
            procedure: 'router.http.handler',
          ),
        );
      }
      await _waitUntil(
        () => runtime.httpResponses.length == aliases.length,
        timeout: const Duration(seconds: 2),
      );
      for (var index = 0; index < aliases.length; index++) {
        final response = runtime.httpResponses[500 + index]!.single;
        expect(
          response.status,
          HttpStatus.notImplemented,
          reason: aliases[index],
        );
        expect(
          (response.body as NativeHttpResponseJson).value,
          containsPair('reason', 'handler_not_registered'),
        );
        expect(
          events,
          contains(
            allOf(
              containsPair('type', 'http_handler_missing'),
              containsPair('handlerId', 'callback-$index'),
            ),
          ),
        );
      }
    },
  );

  test(
    'reverse proxy option aliases retain upstream path and response ownership',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      final subscription = upstream.listen((request) async {
        requests.add(request.uri.toString());
        request.response
          ..statusCode = HttpStatus.ok
          ..write('proxy-ok');
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await upstream.close(force: true);
      });

      const aliases = [
        'target',
        'target_url',
        'targetUrl',
        'upstream',
        'upstream_url',
        'upstreamUrl',
        'socket',
        'socket_path',
        'socketPath',
      ];
      final upstreamUri =
          'http://${upstream.address.host}:${upstream.port}/backend';
      for (final alias in aliases) {
        final fixture = await _ProxyResponseFixture.start({
          alias: upstreamUri,
          'stripPrefix': 'on',
          'timeoutMs': '2000',
          'maxResponseBytes': 1024,
        });
        final response = await fixture.request();
        expect(response.status, HttpStatus.ok, reason: alias);
        expect(
          utf8.decode((response.body as NativeHttpResponseBytes).bytes),
          'proxy-ok',
          reason: alias,
        );
      }
      expect(requests, hasLength(aliases.length));
      expect(requests, everyElement('/backend/resource'));
    },
  );

  test(
    'configured file route option aliases serve the same representation',
    () async {
      const aliases = ['directory', 'root', 'document_root', 'documentRoot'];
      for (final alias in aliases) {
        final fixture = await _configuredFileFixture(
          actionBuilder: (directory) => HttpRouteAction(
            type: HttpRouteActionType.file,
            options: <String, Object?>{
              alias: directory,
              'contentType': 'text/custom',
              'cacheControl': 'max-age=7',
            },
          ),
        );
        final response = await fixture.request();
        expect(response.status, HttpStatus.ok, reason: alias);
        expect(response.headers[HttpHeaders.contentTypeHeader], 'text/custom');
        expect(response.headers[HttpHeaders.cacheControlHeader], 'max-age=7');
        final body = response.body as NativeHttpResponseFile;
        expect(await File(body.path).readAsString(), '0123456789abcdef');
      }
    },
  );

  test('publish route topic option aliases dispatch the same event', () async {
    const aliases = ['topic', 'uri', 'eventTopic', 'event_topic'];
    for (var index = 0; index < aliases.length; index++) {
      final topic = 'com.example.option.$index';
      final fixture = await _HttpEdgeFixture.start([
        HttpRouteSettings(
          match: const HttpRouteMatch(path: '/edge'),
          action: HttpRouteAction(
            type: HttpRouteActionType.publish,
            realm: 'realm1',
            options: <String, Object?>{aliases[index]: topic},
          ),
        ),
      ]);
      final subscriber = await fixture.binding.createInternalSession(
        realmUri: 'realm1',
      );
      addTearDown(subscriber.close);
      final subscription = await subscriber.subscribe(topic);
      final eventCompleter = Completer<Event>();
      subscription.onEvent((event) {
        if (!eventCompleter.isCompleted) eventCompleter.complete(event);
      });

      final response = await fixture.request(
        method: 'POST',
        body: Uint8List.fromList(utf8.encode('{"index":$index}')),
      );
      expect(response.status, HttpStatus.accepted, reason: aliases[index]);
      final event = await eventCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      final kwargs = event.argumentsKeywords!;
      final http = Map<String, Object?>.from(kwargs['_http'] as Map);
      expect(http['path'], '/edge', reason: aliases[index]);
      expect(
        utf8.decode(http['body'] as Uint8List),
        '{"index":$index}',
        reason: aliases[index],
      );
    }
  });
}
