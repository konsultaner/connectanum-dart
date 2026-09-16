import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/state/subscription.dart';
import 'package:test/test.dart';

void main() {
  test(
    'auth options are selected by method without substituting another method',
    () {
      const settings = RealmAuthSettings(
        methods: ['ticket', 'scram'],
        methodOptions: {
          'ticket': {'provider': 'tickets'},
          'scram': {'provider': 'passwords'},
        },
      );
      expect(settings.optionsFor('ticket'), {'provider': 'tickets'});
      expect(settings.optionsFor('scram'), {'provider': 'passwords'});
      expect(settings.optionsFor('missing'), isNull);
    },
  );

  test(
    'listener protocol spellings and HTTP classification remain distinct',
    () {
      final cases = {
        ListenerProtocol.rawsocket: ('rawsocket', false),
        ListenerProtocol.websocket: ('websocket', false),
        ListenerProtocol.http: ('http', true),
        ListenerProtocol.http2: ('http2', true),
        ListenerProtocol.http3: ('http3', true),
      };
      expect(cases.keys, unorderedEquals(ListenerProtocol.values));
      for (final entry in cases.entries) {
        expect(listenerProtocolFromString(entry.value.$1), entry.key);
        expect(listenerProtocolToString(entry.key), entry.value.$1);
        expect(entry.key.isHttp, entry.value.$2);
      }
      expect(
        () => listenerProtocolFromString('unknown'),
        throwsFormatException,
      );
    },
  );

  test('permission policies keep their public string and topic meanings', () {
    for (final entry in {
      'exact': (PermissionMatchPolicy.exact, TopicMatchPolicy.exact),
      'prefix': (PermissionMatchPolicy.prefix, TopicMatchPolicy.prefix),
      'wildcard': (PermissionMatchPolicy.wildcard, TopicMatchPolicy.wildcard),
    }.entries) {
      expect(permissionMatchPolicyFromString(entry.key), entry.value.$1);
      expect(
        PermissionSettings(
          uri: 'app.topic',
          matchPolicy: entry.value.$1,
        ).toTopicMatchPolicy(),
        entry.value.$2,
      );
    }
    for (final invalid in ['', 'EXACT', 'unknown']) {
      expect(
        () => permissionMatchPolicyFromString(invalid),
        throwsFormatException,
      );
    }
  });

  test('HTTP action aliases retain canonical spelling', () {
    final cases = <HttpRouteActionType, List<String>>{
      HttpRouteActionType.rpc: ['rpc'],
      HttpRouteActionType.internalCall: ['internal_call'],
      HttpRouteActionType.auth: ['auth'],
      HttpRouteActionType.reservedRealm: ['reserved_realm'],
      HttpRouteActionType.namespace: ['namespace'],
      HttpRouteActionType.mcp: ['mcp'],
      HttpRouteActionType.file: ['file'],
      HttpRouteActionType.sessionProxy: [
        'session_proxy',
        'sessionProxy',
        'session-proxy',
      ],
      HttpRouteActionType.fastCgi: [
        'fastcgi',
        'fast_cgi',
        'fastCgi',
        'fastCGI',
        'php_fpm',
        'php-fpm',
        'phpFpm',
      ],
      HttpRouteActionType.reverseProxy: [
        'reverse_proxy',
        'reverseProxy',
        'reverse-proxy',
        'proxy',
      ],
      HttpRouteActionType.publish: ['publish'],
      HttpRouteActionType.handler: [
        'handler',
        'custom_handler',
        'customHandler',
      ],
    };
    expect(cases.keys, unorderedEquals(HttpRouteActionType.values));
    for (final entry in cases.entries) {
      expect(httpRouteActionTypeToString(entry.key), entry.value.first);
      for (final alias in entry.value) {
        expect(httpRouteActionTypeFromString(alias), entry.key);
      }
    }
    expect(
      () => httpRouteActionTypeFromString('unknown'),
      throwsFormatException,
    );
  });

  group('OpenMetrics route enrichment', () {
    for (final metrics in <MetricsSettings?>[
      null,
      const MetricsSettings(),
      const MetricsSettings(
        openMetrics: OpenMetricsSettings(
          enabled: false,
          listen: '127.0.0.1:9000',
        ),
      ),
      const MetricsSettings(openMetrics: OpenMetricsSettings(enabled: true)),
      const MetricsSettings(
        openMetrics: OpenMetricsSettings(enabled: true, listen: '  '),
      ),
    ]) {
      test(
        'inactive or unbound metrics preserve settings identity ${metrics?.openMetrics?.listen}',
        () {
          final settings = RouterSettings(
            realms: [],
            listeners: [],
            metrics: metrics,
          );
          expect(settings.withOpenMetricsHttpRoutes(), same(settings));
        },
      );
    }

    for (final path in {
      'metrics': '/metrics',
      ' /custom ': '/custom',
      ' ': '/',
      '/': '/',
    }.entries) {
      test('new endpoint normalizes metrics path ${path.key}', () {
        final original = _settings(path: path.key);
        final result = original.withOpenMetricsHttpRoutes();
        expect(original.listeners, isEmpty);
        expect(result.metrics, same(original.metrics));
        final listener = result.listeners.single;
        expect(listener.endpoint, '127.0.0.1:9000');
        expect(listener.type, 'http');
        expect(listener.protocols, [
          ListenerProtocol.http,
          ListenerProtocol.http2,
        ]);
        expect(listener.options, {'connectanum_open_metrics_listener': true});
        _expectRoutes(listener.http!.routes, path.value);
        expect(result.withOpenMetricsHttpRoutes(), same(result));
      });
    }

    test(
      'existing listener keeps TLS, auth and transport-specific settings',
      () {
        final applicationRoute = _route('/app');
        final listener = ListenerSettings(
          type: 'websocket',
          endpoint: ' 127.0.0.1:9000 ',
          authmethods: ['ticket', 'scram'],
          sessionProfile: 'secure',
          path: '/ws',
          tls: {'certificate': 'cert.pem', 'key': 'key.pem'},
          options: {'idle': 12},
          protocols: [
            ListenerProtocol.websocket,
            ListenerProtocol.http2,
            ListenerProtocol.websocket,
          ],
          rawsocket: const RawSocketListenerSettings(maxFrameExponent: 24),
          websocket: const WebSocketListenerSettings(
            path: '/ws',
            subprotocols: ['wamp.2.cbor'],
          ),
          http: HttpListenerSettings(
            alpn: ['h2'],
            http3: const Http3Settings(enabled: true, port: 9443),
            sessionProfile: 'http-secure',
            routes: [applicationRoute],
            options: {'body_limit': 1024},
          ),
        );
        const unrelated = ListenerSettings(
          endpoint: '127.0.0.1:8000',
          type: 'rawsocket',
        );
        final original = _settings(listeners: [unrelated, listener]);
        final result = original.withOpenMetricsHttpRoutes();
        expect(result.listeners.length, 2);
        expect(result.listeners.first, same(unrelated));
        final updated = result.listeners.last;
        expect(updated.endpoint, listener.endpoint);
        expect(updated.type, listener.type);
        expect(updated.authmethods, listener.authmethods);
        expect(updated.sessionProfile, listener.sessionProfile);
        expect(updated.path, listener.path);
        expect(updated.tls, listener.tls);
        expect(updated.options, listener.options);
        expect(updated.rawsocket, listener.rawsocket);
        expect(updated.websocket, listener.websocket);
        expect(updated.protocols, [
          ListenerProtocol.websocket,
          ListenerProtocol.http2,
          ListenerProtocol.http,
        ]);
        expect(updated.http!.alpn, ['h2']);
        expect(
          updated.http!.http3,
          const Http3Settings(enabled: true, port: 9443),
        );
        expect(updated.http!.sessionProfile, 'http-secure');
        expect(updated.http!.options, {'body_limit': 1024});
        _expectRoutes(updated.http!.routes.take(3).toList(), '/metrics');
        expect(updated.http!.routes.last, same(applicationRoute));
        expect(listener.http!.routes, [applicationRoute]);
        expect(result.withOpenMetricsHttpRoutes(), same(result));
      },
    );

    test(
      'explicit exact routes win, but prefix routes do not suppress injection',
      () {
        final metrics = _route('/metrics', methods: ['POST']);
        final health = _route('/health');
        final prefix = HttpRouteSettings(
          match: const HttpRouteMatch(prefix: '/'),
          action: const HttpRouteAction(type: HttpRouteActionType.handler),
        );
        final original = _settings(
          listeners: [
            ListenerSettings(
              endpoint: '127.0.0.1:9000',
              protocols: [ListenerProtocol.http, ListenerProtocol.http2],
              http: HttpListenerSettings(routes: [prefix, metrics, health]),
            ),
          ],
        );
        final result = original.withOpenMetricsHttpRoutes();
        final routes = result.listeners.single.http!.routes;
        expect(routes.map((route) => route.match.path), [
          '/healthz',
          null,
          '/metrics',
          '/health',
        ]);
        expect(routes[1], same(prefix));
        expect(routes[2], same(metrics));
        expect(routes[2].match.methods, ['POST']);
        expect(routes[3], same(health));
        expect(result.withOpenMetricsHttpRoutes(), same(result));
      },
    );

    test(
      'explicit protocols take precedence over the legacy listener type',
      () {
        final original = _settings(
          listeners: [
            const ListenerSettings(
              type: 'websocket',
              endpoint: '127.0.0.1:9000',
              protocols: [ListenerProtocol.rawsocket],
            ),
          ],
        );
        final result = original.withOpenMetricsHttpRoutes();
        expect(result.listeners.single.protocols, [
          ListenerProtocol.rawsocket,
          ListenerProtocol.http,
          ListenerProtocol.http2,
        ]);
        _expectRoutes(result.listeners.single.http!.routes, '/metrics');
        expect(original.listeners.single.protocols, [
          ListenerProtocol.rawsocket,
        ]);
        expect(result.withOpenMetricsHttpRoutes(), same(result));
      },
    );

    for (final (type, expected) in <(String?, List<ListenerProtocol>)>[
      (
        ' rawsocket ',
        [
          ListenerProtocol.rawsocket,
          ListenerProtocol.http,
          ListenerProtocol.http2,
        ],
      ),
      ('http', [ListenerProtocol.http, ListenerProtocol.http2]),
      ('unknown', [ListenerProtocol.http, ListenerProtocol.http2]),
      (' ', [ListenerProtocol.http, ListenerProtocol.http2]),
      (null, [ListenerProtocol.http, ListenerProtocol.http2]),
    ]) {
      test('legacy listener type $type enriches only known protocols', () {
        final result = _settings(
          listeners: [ListenerSettings(type: type, endpoint: '127.0.0.1:9000')],
        ).withOpenMetricsHttpRoutes();
        expect(result.listeners.single.type, type);
        expect(result.listeners.single.protocols, expected);
        _expectRoutes(result.listeners.single.http!.routes, '/metrics');
      });
    }
  });
}

RouterSettings _settings({
  String path = '/metrics',
  List<ListenerSettings> listeners = const [],
}) => RouterSettings(
  realms: [],
  listeners: listeners,
  metrics: MetricsSettings(
    openMetrics: OpenMetricsSettings(
      enabled: true,
      listen: ' 127.0.0.1:9000 ',
      path: path,
      realm: 'private.metrics',
    ),
  ),
);

HttpRouteSettings _route(String path, {List<String> methods = const ['GET']}) =>
    HttpRouteSettings(
      match: HttpRouteMatch(path: path, methods: methods),
      action: const HttpRouteAction(
        type: HttpRouteActionType.rpc,
        procedure: 'app.custom',
      ),
    );

void _expectRoutes(List<HttpRouteSettings> routes, String metricsPath) {
  expect(routes.map((route) => route.match.path), [
    '/healthz',
    '/health',
    metricsPath,
  ]);
  expect(routes.map((route) => route.action.procedure), [
    'connectanum.metrics.healthz',
    'connectanum.metrics.healthz',
    'connectanum.metrics.openmetrics',
  ]);
  for (final route in routes) {
    expect(route.match.methods, ['GET', 'HEAD']);
    expect(route.action.type, HttpRouteActionType.internalCall);
    expect(route.action.realm, 'private.metrics');
    expect(route.methodActions, isEmpty);
  }
}
