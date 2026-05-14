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
              'authorization_provider': 'realm-authz',
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
                      'refresh_token_ttl_ms': 240000,
                      'rotate_refresh_tokens': true,
                    },
                  },
                  <String, Object?>{
                    'match': <String, Object?>{
                      'path': '/health',
                      'protocols': ['http/2', 'http/3'],
                    },
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
                'http_provider': 'edge-jwt',
              },
              'roles': <String, Object?>{
                'callee': const {'features': <String, Object?>{}},
              },
            },
          ],
          'http_auth_providers': <String, Object?>{
            'edge-jwt': <String, Object?>{
              'type': 'jwt',
              'options': <String, Object?>{
                'issuer': 'https://issuer.example',
                'audience': ['connectanum-http'],
              },
            },
          },
          'authorization_providers': <String, Object?>{
            'realm-authz': <String, Object?>{
              'type': 'remote',
              'options': <String, Object?>{'endpoint': 'wamp://authz'},
            },
          },
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
        settings
            .listeners
            .single
            .http
            ?.routes
            .first
            .action
            .options['refresh_token_ttl_ms'],
        240000,
      );
      expect(
        settings
            .listeners
            .single
            .http
            ?.routes
            .first
            .action
            .options['rotate_refresh_tokens'],
        isTrue,
      );
      expect(
        settings.listeners.single.http?.routes.last.action.sessionProfile,
        'http-handler',
      );
      expect(settings.listeners.single.http?.routes.last.match.protocols, [
        'http/2',
        'http/3',
      ]);
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
      expect(
        settings.sessionProfiles
            .firstWhere((profile) => profile.name == 'http-handler')
            .auth
            .httpProvider,
        'edge-jwt',
      );
      expect(settings.httpAuthProviders.keys, contains('edge-jwt'));
      expect(settings.authorizationProviders.keys, contains('realm-authz'));
      expect(settings.realms.single.authorizationProvider, 'realm-authz');
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
              'collection_timeout_ms': 1500,
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
      expect(openMetrics.collectionTimeout, const Duration(milliseconds: 1500));
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
              collectionTimeout: Duration(milliseconds: 2500),
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
      expect(openMetrics.collectionTimeout, const Duration(milliseconds: 2500));
    });

    test('codec round-trips shared session profiles and references', () {
      final updatedBuilder = RouterSettingsBuilder()
        ..addRealmFromBuilder(
          RealmSettingsBuilder('realm1')
            ..addAuthMethod('anonymous')
            ..setAuthorizationProvider('realm-authz'),
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
            ..setHttpProvider('edge-jwt')
            ..putRole('callee', const {'features': <String, Object?>{}}),
        )
        ..addHttpAuthProvider(
          'edge-jwt',
          const HttpAuthProviderDefinition(
            type: 'jwt',
            options: <String, Object?>{
              'issuer': 'https://issuer.example',
              'audience': <String>['connectanum-http'],
            },
          ),
        )
        ..addAuthorizationProvider(
          'realm-authz',
          const AuthorizationProviderDefinition(
            type: 'remote',
            options: <String, Object?>{'endpoint': 'wamp://authz'},
          ),
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
                      options: <String, Object?>{
                        'token_ttl_ms': 45000,
                        'refresh_token_ttl_ms': 240000,
                        'rotate_refresh_tokens': true,
                      },
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
        decoded
            .listeners
            .single
            .http
            ?.routes
            .first
            .action
            .options['refresh_token_ttl_ms'],
        240000,
      );
      expect(
        decoded
            .listeners
            .single
            .http
            ?.routes
            .first
            .action
            .options['rotate_refresh_tokens'],
        isTrue,
      );
      expect(
        decoded.listeners.single.http?.routes.last.action.sessionProfile,
        'http-handler',
      );
      expect(decoded.httpAuthProviders.keys, contains('edge-jwt'));
      expect(decoded.authorizationProviders.keys, contains('realm-authz'));
      expect(decoded.realms.single.authorizationProvider, 'realm-authz');
      expect(
        decoded.sessionProfiles
            .firstWhere((profile) => profile.name == 'http-handler')
            .auth
            .httpProvider,
        'edge-jwt',
      );
      expect(decoded.internalRealms.single.sessionProfile, 'http-handler');
    });

    test('parses native-style HTTP method action maps', () {
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
              'protocols': ['http'],
              'http': <String, Object?>{
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'path': '/api/items'},
                    'methods': <String, Object?>{
                      'get': <String, Object?>{
                        'type': 'rpc',
                        'realm': 'realm1',
                        'procedure': 'com.example.items.list',
                      },
                      'POST': <String, Object?>{
                        'type': 'rpc',
                        'realm': 'realm1',
                        'procedure': 'com.example.items.create',
                      },
                    },
                  },
                ],
              },
            },
          ],
        },
      });

      final route = settings.listeners.single.http!.routes.single;
      expect(route.match.methods, ['GET', 'POST']);
      expect(route.actionForMethod('get').procedure, 'com.example.items.list');
      expect(
        route.actionForMethod('post').procedure,
        'com.example.items.create',
      );

      final encoded = RouterSettingsCodec.toMap(settings);
      final decoded = RouterSettingsCodec.fromMap(encoded);
      final decodedRoute = decoded.listeners.single.http!.routes.single;
      expect(decodedRoute.match.methods, ['GET', 'POST']);
      expect(decodedRoute.methodActions.keys, containsAll(['GET', 'POST']));
      expect(
        decodedRoute.actionForMethod('POST').procedure,
        'com.example.items.create',
      );
    });

    test('parses catch-all HTTP wildcard routes', () {
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
              'protocols': ['http'],
              'http': <String, Object?>{
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'catch_all': true},
                    'action': <String, Object?>{
                      'type': 'rpc',
                      'realm': 'realm1',
                      'procedure': 'com.example.http.fallback',
                    },
                  },
                ],
              },
            },
          ],
        },
      });

      final route = settings.listeners.single.http!.routes.single;
      expect(route.match.isCatchAll, isTrue);
      expect(route.match.path, isNull);
      expect(route.match.prefix, isNull);
      expect(route.action.procedure, 'com.example.http.fallback');

      final encoded = RouterSettingsCodec.toMap(settings);
      final encodedRoute =
          ((encoded['listeners']! as List).single as Map)['http'] as Map;
      final encodedMatch =
          ((encodedRoute['routes']! as List).single as Map)['match'] as Map;
      expect(encodedMatch['catch_all'], isTrue);

      final decoded = RouterSettingsCodec.fromMap(encoded);
      expect(
        decoded.listeners.single.http!.routes.single.match.isCatchAll,
        isTrue,
      );
    });

    test('parses deterministic HTTP route shorthand aliases', () {
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
              'protocols': ['http'],
              'http': <String, Object?>{
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'prefix': '/'},
                    'action': <String, Object?>{
                      'type': 'reservedRealm',
                      'namespace': 'Public.Http',
                      'appendMethodSuffix': false,
                    },
                  },
                  <String, Object?>{
                    'match': <String, Object?>{'prefix': '/api/'},
                    'action': <String, Object?>{
                      'type': 'namespace',
                      'targetRealm': 'realm1',
                      'namespace': 'consumer.api',
                      'appendMethodSuffix': true,
                    },
                  },
                ],
              },
            },
          ],
        },
      });

      final routes = settings.listeners.single.http!.routes;
      expect(routes.first.action.type, HttpRouteActionType.reservedRealm);
      expect(routes.first.action.namespace, 'Public.Http');
      expect(routes.first.action.appendMethodSuffix, isFalse);
      expect(routes.last.action.type, HttpRouteActionType.namespace);
      expect(routes.last.action.options['targetRealm'], 'realm1');
      expect(routes.last.action.appendMethodSuffix, isTrue);

      final encoded = RouterSettingsCodec.toMap(settings);
      final decoded = RouterSettingsCodec.fromMap(encoded);
      final decodedRoutes = decoded.listeners.single.http!.routes;
      expect(
        decodedRoutes.first.action.type,
        HttpRouteActionType.reservedRealm,
      );
      expect(decodedRoutes.first.action.appendMethodSuffix, isFalse);
      expect(decodedRoutes.last.action.options['targetRealm'], 'realm1');
    });

    test('parses HTTP session proxy route aliases', () {
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
              'protocols': ['http'],
              'http': <String, Object?>{
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'path': '/proxy'},
                    'action': <String, Object?>{
                      'type': 'sessionProxy',
                      'procedure': 'com.example.proxy.handle',
                    },
                  },
                ],
              },
            },
          ],
        },
      });

      final route = settings.listeners.single.http!.routes.single;
      expect(route.action.type, HttpRouteActionType.sessionProxy);
      expect(route.action.procedure, 'com.example.proxy.handle');

      final encoded = RouterSettingsCodec.toMap(settings);
      final decoded = RouterSettingsCodec.fromMap(encoded);
      expect(
        decoded.listeners.single.http!.routes.single.action.type,
        HttpRouteActionType.sessionProxy,
      );
    });

    test('parses HTTP publish routes with topics', () {
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
              'protocols': ['http'],
              'http': <String, Object?>{
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'path': '/events'},
                    'action': <String, Object?>{
                      'type': 'publish',
                      'topic': 'com.example.http.events',
                    },
                  },
                ],
              },
            },
          ],
        },
      });

      final route = settings.listeners.single.http!.routes.single;
      expect(route.action.type, HttpRouteActionType.publish);
      expect(route.action.topic, 'com.example.http.events');

      final encoded = RouterSettingsCodec.toMap(settings);
      final decoded = RouterSettingsCodec.fromMap(encoded);
      expect(
        decoded.listeners.single.http!.routes.single.action.type,
        HttpRouteActionType.publish,
      );
      expect(
        decoded.listeners.single.http!.routes.single.action.topic,
        'com.example.http.events',
      );
    });

    test('parses HTTP route middleware limits', () {
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
              'protocols': ['http'],
              'http': <String, Object?>{
                'routes': [
                  <String, Object?>{
                    'match': <String, Object?>{'path': '/limited'},
                    'action': <String, Object?>{
                      'type': 'rpc',
                      'procedure': 'com.example.http.limited',
                      'rateLimit': <String, Object?>{
                        'maxRequests': 2,
                        'windowMs': 1500,
                        'key': 'header:x-client-id',
                      },
                      'concurrencyLimit': <String, Object?>{
                        'maxConcurrent': 3,
                        'key': 'bearer',
                      },
                    },
                  },
                ],
              },
            },
          ],
        },
      });

      final rateLimit =
          settings.listeners.single.http!.routes.single.action.rateLimit!;
      expect(rateLimit.maxRequests, 2);
      expect(rateLimit.window, const Duration(milliseconds: 1500));
      expect(rateLimit.key, 'header:x-client-id');
      final concurrencyLimit = settings
          .listeners
          .single
          .http!
          .routes
          .single
          .action
          .concurrencyLimit!;
      expect(concurrencyLimit.maxConcurrent, 3);
      expect(concurrencyLimit.key, 'bearer');

      final encoded = RouterSettingsCodec.toMap(settings);
      final decoded = RouterSettingsCodec.fromMap(encoded);
      final decodedRateLimit =
          decoded.listeners.single.http!.routes.single.action.rateLimit!;
      expect(decodedRateLimit.maxRequests, 2);
      expect(decodedRateLimit.window, const Duration(milliseconds: 1500));
      expect(decodedRateLimit.key, 'header:x-client-id');
      final decodedConcurrencyLimit =
          decoded.listeners.single.http!.routes.single.action.concurrencyLimit!;
      expect(decodedConcurrencyLimit.maxConcurrent, 3);
      expect(decodedConcurrencyLimit.key, 'bearer');
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
