import 'package:connectanum_router/src/router/config/router_config_loader.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/config/router_settings_codec.dart';
import 'package:test/test.dart';

void main() {
  group('RouterConfigLoader', () {
    test('parses shared session profiles and references', () {
      final settings = RouterConfigLoader.fromMap({
        'router': <String, Object?>{
          'realms': [
            <String, Object?>{
              'name': 'realm1',
              'auth': <String, Object?>{
                'authmethods': ['anonymous'],
              },
            },
          ],
          'listeners': [
            <String, Object?>{
              'type': 'rawsocket',
              'endpoint': '127.0.0.1:0',
              'session_profile': 'public-wamp',
              'http': <String, Object?>{
                'session_profile': 'public-http',
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'path': '/auth'},
                    'action': <String, Object?>{
                      'type': 'auth',
                      'session_profile': 'http-handler',
                      'token_ttl_ms': 45000,
                    },
                  },
                  <String, Object?>{
                    'match': <String, Object?>{'path': '/health'},
                    'action': <String, Object?>{
                      'type': 'rpc',
                      'procedure': 'com.example.health',
                      'session_profile': 'http-handler',
                    },
                  },
                ],
              },
            },
          ],
          'session_profiles': [
            <String, Object?>{
              'name': 'public-wamp',
              'auth': <String, Object?>{
                'methods': ['ticket', 'scram', 'wampcra'],
              },
            },
            <String, Object?>{
              'name': 'public-http',
              'auth': <String, Object?>{'methods': <String>[]},
            },
            <String, Object?>{
              'name': 'http-handler',
              'realm': 'realm1',
              'auth': <String, Object?>{
                'auth_id': 'http-handler',
                'auth_role': 'internal',
              },
              'roles': <String, Object?>{
                'callee': const {'features': <String, Object?>{}},
              },
            },
          ],
          'internal_realms': [
            <String, Object?>{
              'name': 'connectanum.metrics',
              'session_profile': 'http-handler',
              'services': ['metrics'],
            },
          ],
        },
      });

      expect(settings.sessionProfiles, hasLength(3));
      expect(settings.listeners.single.sessionProfile, 'public-wamp');
      expect(settings.listeners.single.http?.sessionProfile, 'public-http');
      expect(
        settings.listeners.single.http?.routes.first.action.type,
        HttpRouteActionType.auth,
      );
      expect(
        settings
            .listeners
            .single
            .http
            ?.routes
            .first
            .action
            .options['token_ttl_ms'],
        45000,
      );
      expect(
        settings.listeners.single.http?.routes.last.action.sessionProfile,
        'http-handler',
      );
      expect(settings.sessionProfiles.first.auth.methods, [
        'ticket',
        'scram',
        'wampcra',
      ]);
      expect(
        settings.sessionProfiles
            .firstWhere((profile) => profile.name == 'http-handler')
            .auth
            .authRole,
        'internal',
      );
      expect(settings.internalRealms.single.sessionProfile, 'http-handler');
    });

    test('parses internal realms and open metrics settings', () {
      final settings = RouterConfigLoader.fromMap({
        'router': <String, Object?>{
          'realms': [
            <String, Object?>{
              'name': 'realm1',
              'auto_create': false,
              'auth': <String, Object?>{
                'authmethods': ['anonymous'],
              },
              'roles': [
                <String, Object?>{
                  'name': 'member',
                  'permissions': [
                    <String, Object?>{
                      'uri': '',
                      'match': 'prefix',
                      'allow': ['subscribe', 'publish'],
                    },
                  ],
                },
              ],
            },
          ],
          'listeners': [
            <String, Object?>{
              'type': 'rawsocket',
              'endpoint': '127.0.0.1:0',
              'authmethods': ['anonymous'],
              'options': const <String, Object?>{},
            },
          ],
          'internal_realms': [
            <String, Object?>{
              'name': 'connectanum.metrics',
              'auth_id': 'metrics',
              'auth_role': 'metrics-role',
              'roles': <String, Object?>{
                'metrics': const {'subscribe': true},
              },
              'services': ['metrics', 'http_bridge'],
            },
          ],
          'metrics': <String, Object?>{
            'open_metrics': <String, Object?>{
              'enabled': true,
              'listen': '127.0.0.1:9100',
              'path': '/open-metrics',
              'auth_token': 'secret-token',
              'realm': 'connectanum.metrics',
            },
          },
        },
      });

      expect(settings.internalRealms, hasLength(1));
      final internalRealm = settings.internalRealms.first;
      expect(internalRealm.name, 'connectanum.metrics');
      expect(internalRealm.authId, 'metrics');
      expect(internalRealm.authRole, 'metrics-role');
      expect(internalRealm.roles.containsKey('metrics'), isTrue);
      expect(
        internalRealm.services.containsAll(<String>['metrics', 'http_bridge']),
        isTrue,
      );

      final metrics = settings.metrics;
      expect(metrics, isNotNull);
      final openMetrics = metrics!.openMetrics;
      expect(openMetrics, isNotNull);
      expect(openMetrics!.enabled, isTrue);
      expect(openMetrics.listen, '127.0.0.1:9100');
      expect(openMetrics.path, '/open-metrics');
      expect(openMetrics.authToken, 'secret-token');
      expect(openMetrics.realm, 'connectanum.metrics');
    });

    test('parses transport/backpressure alert settings', () {
      final settings = RouterConfigLoader.fromMap({
        'router': <String, Object?>{
          'realms': [
            <String, Object?>{
              'name': 'realm1',
              'auth': <String, Object?>{
                'authmethods': ['anonymous'],
              },
            },
          ],
          'listeners': [
            <String, Object?>{
              'type': 'rawsocket',
              'endpoint': '127.0.0.1:0',
              'authmethods': ['anonymous'],
            },
          ],
          'metrics': <String, Object?>{
            'open_metrics': <String, Object?>{'enabled': true},
            'backpressure': <String, Object?>{
              'depth_threshold': 8,
              'new_events_threshold': 2,
              'cooldown_ms': 750,
            },
            'transport_alerts': <String, Object?>{
              'goaway_delta_threshold': 2,
              'idle_timeout_delta_threshold': 3,
              'body_timeout_delta_threshold': 4,
              'protocol_error_delta_threshold': 5,
              'internal_error_delta_threshold': 6,
              'cooldown_ms': 900,
              'throttle_on_alert': false,
            },
          },
        },
      });

      final metrics = settings.metrics!;
      expect(metrics.backpressure.depthThreshold, 8);
      expect(metrics.backpressure.newEventsThreshold, 2);
      expect(metrics.backpressure.cooldown, const Duration(milliseconds: 750));

      final alerts = metrics.transportAlerts;
      expect(alerts.goAwayDeltaThreshold, 2);
      expect(alerts.idleTimeoutDeltaThreshold, 3);
      expect(alerts.bodyTimeoutDeltaThreshold, 4);
      expect(alerts.protocolErrorDeltaThreshold, 5);
      expect(alerts.internalErrorDeltaThreshold, 6);
      expect(alerts.cooldown, const Duration(milliseconds: 900));
      expect(alerts.throttleOnAlert, isFalse);
    });
  });

  group('RouterSettingsBuilder', () {
    RouterSettingsBuilder createBaseBuilder() => RouterSettingsBuilder()
      ..addRealmFromBuilder(
        RealmSettingsBuilder('realm1')..addAuthMethod('anonymous'),
      )
      ..addListenerFromBuilder(
        ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
          ..addAuthMethod('anonymous')
          ..setOptions(const {'max_rawsocket_size_exponent': 16}),
      );

    test('builds settings with internal realms and open metrics', () {
      final builder = createBaseBuilder()
        ..addInternalRealmFromBuilder(
          InternalRealmSettingsBuilder('connectanum.metrics')
            ..setAuthId('metrics')
            ..setAuthRole('metrics-role')
            ..addService('metrics'),
        )
        ..metrics(
          const MetricsSettings(
            openMetrics: OpenMetricsSettings(
              enabled: true,
              listen: '127.0.0.1:9100',
            ),
          ),
        );

      final settings = builder.build();

      expect(settings.internalRealms, hasLength(1));
      expect(settings.internalRealms.first.name, 'connectanum.metrics');
      expect(
        settings.listeners.first.protocols,
        contains(ListenerProtocol.rawsocket),
      );
      expect(settings.metrics, isNotNull);
      expect(settings.metrics!.openMetrics, isNotNull);
      expect(settings.metrics!.openMetrics!.enabled, isTrue);
    });

    test('codec round-trips internal realms and metrics', () {
      final builder = createBaseBuilder()
        ..addInternalRealmFromBuilder(
          InternalRealmSettingsBuilder('connectanum.metrics')
            ..setAuthId('metrics')
            ..addService('metrics'),
        )
        ..metrics(
          const MetricsSettings(
            openMetrics: OpenMetricsSettings(
              enabled: false,
              path: '/custom',
              realm: 'custom.realm',
            ),
          ),
        );

      final settings = builder.build();
      final Map<String, Object?> encoded = RouterSettingsCodec.toMap(settings);
      expect(encoded['internal_realms'], isA<List>());
      final decoded = RouterSettingsCodec.fromMap(encoded);

      expect(decoded.internalRealms, hasLength(1));
      expect(decoded.internalRealms.first.name, 'connectanum.metrics');
      expect(
        decoded.listeners.first.protocols,
        contains(ListenerProtocol.rawsocket),
      );
      final openMetrics = decoded.metrics?.openMetrics;
      expect(openMetrics, isNotNull);
      expect(openMetrics!.enabled, isFalse);
      expect(openMetrics.path, '/custom');
      expect(openMetrics.realm, 'custom.realm');
    });

    test('codec round-trips shared session profiles and references', () {
      final updatedBuilder = RouterSettingsBuilder()
        ..addRealmFromBuilder(
          RealmSettingsBuilder('realm1')..addAuthMethod('anonymous'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-wamp')
            ..setAuthMethods(const ['ticket', 'scram', 'wampcra']),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('public-http'),
        )
        ..addSessionProfileFromBuilder(
          SessionProfileSettingsBuilder('http-handler')
            ..setRealm('realm1')
            ..setAuthId('http-handler')
            ..setAuthRole('internal')
            ..putRole('callee', const {'features': <String, Object?>{}}),
        )
        ..addListenerFromBuilder(
          ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
            ..setSessionProfile('public-wamp')
            ..setOptions(const {'max_rawsocket_size_exponent': 16})
            ..setHttpOptions(
              const HttpListenerSettings(
                sessionProfile: 'public-http',
                routes: <HttpRouteSettings>[
                  HttpRouteSettings(
                    match: HttpRouteMatch(path: '/auth'),
                    action: HttpRouteAction(
                      type: HttpRouteActionType.auth,
                      sessionProfile: 'http-handler',
                      options: <String, Object?>{'token_ttl_ms': 45000},
                    ),
                  ),
                  HttpRouteSettings(
                    match: HttpRouteMatch(path: '/health'),
                    action: HttpRouteAction(
                      type: HttpRouteActionType.rpc,
                      procedure: 'com.example.health',
                      sessionProfile: 'http-handler',
                    ),
                  ),
                ],
              ),
            ),
        )
        ..addInternalRealmFromBuilder(
          InternalRealmSettingsBuilder('connectanum.metrics')
            ..setSessionProfile('http-handler')
            ..addService('metrics'),
        );

      final settings = updatedBuilder.build();
      final encoded = RouterSettingsCodec.toMap(settings);
      final decoded = RouterSettingsCodec.fromMap(encoded);

      expect(decoded.sessionProfiles, hasLength(3));
      expect(decoded.listeners.single.sessionProfile, 'public-wamp');
      expect(decoded.listeners.single.http?.sessionProfile, 'public-http');
      expect(
        decoded.listeners.single.http?.routes.first.action.type,
        HttpRouteActionType.auth,
      );
      expect(
        decoded
            .listeners
            .single
            .http
            ?.routes
            .first
            .action
            .options['token_ttl_ms'],
        45000,
      );
      expect(
        decoded.listeners.single.http?.routes.last.action.sessionProfile,
        'http-handler',
      );
      expect(decoded.internalRealms.single.sessionProfile, 'http-handler');
    });

    test('parses multi-protocol listener with http routes', () {
      final settings = RouterConfigLoader.fromMap({
        'router': <String, Object?>{
          'realms': [
            <String, Object?>{
              'name': 'realm1',
              'auth': <String, Object?>{
                'authmethods': ['anonymous'],
              },
            },
          ],
          'listeners': [
            <String, Object?>{
              'endpoint': '0.0.0.0:8080',
              'authmethods': ['anonymous'],
              'protocols': ['rawsocket', 'http'],
              'rawsocket': <String, Object?>{'max_rawsocket_size_exponent': 18},
              'http': <String, Object?>{
                'alpn': ['h2', 'http/1.1'],
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'prefix': '/api/'},
                    'action': <String, Object?>{
                      'type': 'rpc',
                      'procedure': 'com.example.api.{path}',
                      'serializer': 'msgpack',
                    },
                  },
                ],
              },
            },
          ],
        },
      });

      final listener = settings.listeners.single;
      expect(listener.protocols, [
        ListenerProtocol.rawsocket,
        ListenerProtocol.http,
      ]);
      expect(listener.rawsocket?.maxFrameExponent, 18);
      final http = listener.http;
      expect(http, isNotNull);
      expect(http!.alpn, ['h2', 'http/1.1']);
      expect(http.routes, hasLength(1));
      final route = http.routes.first;
      expect(route.match.prefix, '/api/');
      expect(route.action.type, HttpRouteActionType.rpc);
      expect(route.action.procedure, 'com.example.api.{path}');

      final encoded = RouterSettingsCodec.toMap(settings);
      final decoded = RouterSettingsCodec.fromMap(encoded);
      final decodedListener = decoded.listeners.single;
      expect(decodedListener.protocols, [
        ListenerProtocol.rawsocket,
        ListenerProtocol.http,
      ]);
      expect(
        decodedListener.http!.routes.first.action.procedure,
        'com.example.api.{path}',
      );
    });
  });
}
