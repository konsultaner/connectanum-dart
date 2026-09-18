import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_router/src/router/config/router_config_loader.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

import 'support/config_assertions.dart';

void main() {
  group('valid configuration assertions', () {
    test('evaluate once and preserve the parsed result', () async {
      final result = Object();
      var calls = 0;
      expect(
        expectConfigSuccess(() {
          calls++;
          return result;
        }),
        same(result),
      );
      expect(
        await expectConfigLoad(() async {
          calls++;
          return result;
        }),
        same(result),
      );
      expect(calls, 2);
      expect(expectConfigSuccess<Object?>(() => null), isNull);
      expect(await expectConfigLoad<Object?>(() async => null), isNull);
    });

    for (final error in <Object>[
      const FormatException('invalid format'),
      ArgumentError('invalid value'),
      StateError('missing value'),
      TypeError(),
    ]) {
      test(
        'report parser failure $error as a failed success assertion',
        () async {
          final assertion = throwsA(
            isA<TestFailure>().having(
              (failure) => failure.message,
              'diagnostic',
              contains(error.toString()),
            ),
          );
          expect(
            () => expectConfigSuccess<Object>(() => throw error),
            assertion,
          );
          await expectLater(
            expectConfigLoad<Object>(() async => throw error),
            assertion,
          );
        },
      );
    }

    for (final error in <Object>[
      TimeoutException('deadline'),
      const FileSystemException('read failed'),
      const SocketException('connection failed'),
      const ProcessException('dart', [], 'launch failed'),
      Exception('unexpected failure'),
    ]) {
      test('preserve infrastructure error $error unchanged', () async {
        expect(
          () => expectConfigSuccess<Object>(() => throw error),
          throwsA(same(error)),
        );
        await expectLater(
          expectConfigLoad<Object>(() async => throw error),
          throwsA(same(error)),
        );
        await expectLater(
          expectConfigLoad<Object>(() => throw error),
          throwsA(same(error)),
        );
      });
    }
  });

  group('configuration input boundaries', () {
    final cases = <(String, Object?, String)>[
      ('realms', false, 'Expected "realms" to be a list'),
      ('realms.0', false, 'Each realm entry must be a map'),
      ('realms.0.name', null, 'Expected "realm.name" to be a string'),
      ('realms.0.auth', null, 'Realm "auth" section is required'),
      ('realms.0.auth', false, 'Realm "auth" must be a map'),
      (
        'realms.0.auth.authmethods',
        false,
        'Realm auth "authmethods" must be a list',
      ),
      (
        'realms.0.auth.authmethods',
        [false],
        'Auth method names must be strings',
      ),
      ('realms.0.roles', false, 'Realm "roles" must be a list'),
      ('realms.0.roles.0', false, 'Role entries must be maps'),
      (
        'realms.0.roles.0.permissions',
        false,
        'Role "permissions" must be a list',
      ),
      (
        'realms.0.roles.0.permissions.0',
        false,
        'Permission entries must be maps',
      ),
      (
        'realms.0.roles.0.permissions.0.disclose',
        false,
        'permission.disclose must be a map',
      ),
      (
        'realms.0.roles.0.permissions.0.disclose.caller',
        'false',
        'Expected boolean value',
      ),
      (
        'realms.0.roles.0.permissions.0.allow',
        'call',
        'Expected list of strings',
      ),
      (
        'realms.0.roles.0.permissions.0.deny',
        [false],
        'List entries must be strings',
      ),
      ('realms.0.limits', false, 'Realm "limits" must be a map'),
      ('realms.0.limits.auth_timeout_ms', '100', 'Expected integer value'),
      ('realms.0.auto_create', 'false', 'Expected boolean value'),
      ('listeners', false, 'Router "listeners" must be a list'),
      ('listeners.0', false, 'Listener entries must be maps'),
      ('listeners.0.protocols', false, 'listener.protocols must be a list'),
      (
        'listeners.0.protocols',
        [false],
        'listener.protocols entries must be strings',
      ),
      ('listeners.0.rawsocket', false, 'listener.rawsocket must be a map'),
      ('listeners.0.websocket', false, 'listener.websocket must be a map'),
      ('listeners.0.http', false, 'listener.http must be a map'),
      ('listeners.0.http.http3', false, 'listener.http.http3 must be a map'),
      ('listeners.0.http.http3.port', '443', 'Expected integer value'),
      ('listeners.0.http.routes', false, 'listener.http.routes must be a list'),
      (
        'listeners.0.http.routes.0',
        false,
        'listener.http.routes entries must be maps',
      ),
      (
        'listeners.0.http.routes.0.match',
        false,
        'listener.http.routes.match must be a map',
      ),
      (
        'listeners.0.http.routes.0.action',
        false,
        'listener.http.routes.action must be a map',
      ),
      (
        'listeners.0.http.routes.0.method_actions',
        false,
        'listener.http.routes.method_actions must be a map',
      ),
      (
        'listeners.0.http.routes.0.method_actions',
        {' ': {}},
        'listener.http.routes.method_actions keys must be non-empty methods',
      ),
      ('listeners.0.http.routes.0.match.headers', false, 'Expected map value'),
      (
        'listeners.0.http.routes.0.match.headers',
        {'X-Test': false},
        'Header values must be strings',
      ),
      (
        'listeners.0.http.routes.0.action.rate_limit',
        'false',
        'listener.http.routes.action.rate_limit must be a map',
      ),
      ('listeners.0.tls', false, 'Expected map value'),
      ('listeners.0.path', false, 'Expected string value'),
      ('session_profiles', false, 'Router "session_profiles" must be a list'),
      ('session_profiles.0', false, 'session_profiles entries must be maps'),
      ('session_profiles.0.auth', false, 'session_profiles.auth must be a map'),
      (
        'authorization_providers',
        false,
        'Router "authorization_providers" must be a map',
      ),
      (
        'authorization_providers.policy',
        false,
        'authorization_providers.policy must be a string or map',
      ),
      (
        'http_auth_providers',
        false,
        'Router "http_auth_providers" must be a map',
      ),
      (
        'http_auth_providers.tokens',
        false,
        'http_auth_providers.tokens must be a string or map',
      ),
      ('internal_realms', false, 'Router "internal_realms" must be a list'),
      ('internal_realms.0', false, 'internal_realms entries must be maps'),
      ('metrics', false, 'Router "metrics" must be a map'),
      ('metrics.open_metrics', false, 'metrics.open_metrics must be a map'),
      ('metrics.open_metrics.path', false, 'Expected string value'),
      (
        'metrics.open_metrics.collection_timeout_ms',
        -1,
        'metrics.open_metrics.collection_timeout_ms must be >= 0',
      ),
      (
        'listeners.0.http.routes.0.action.append_method_suffix',
        'false',
        'Expected boolean value',
      ),
      ('metrics.backpressure', false, 'metrics.backpressure must be a map'),
      (
        'metrics.transport_alerts',
        false,
        'metrics.transport_alerts must be a map',
      ),
      ('authenticators', false, 'Router "authenticators" must be a map'),
      (
        'authenticators.anonymous',
        false,
        'Authenticator "anonymous" must be a map',
      ),
      ('worker_pool', false, 'Router "worker_pool" must be a map'),
      ('worker_pool.min_workers', -1, 'worker_pool.min_workers must be >= 0'),
    ];
    for (final (path, invalid, message) in cases) {
      for (final syntax in ['map', 'json', 'yaml']) {
        test('$syntax rejects $path = ${jsonEncode(invalid)}', () {
          final input = _withSetting(path, invalid);
          expect(
            () => switch (syntax) {
              'map' => RouterConfigLoader.fromMap(input),
              'json' => RouterConfigLoader.fromJsonString(jsonEncode(input)),
              _ => RouterConfigLoader.fromYamlString(jsonEncode(input)),
            },
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                message,
              ),
            ),
          );
        });
      }
    }

    test('fixture is valid before replacing one configuration value', () {
      final settings = loadValidRouterConfig(_config());
      expect(settings.realms.single.name, 'consumer.realm');
      expect(settings.listeners.single.endpoint, '127.0.0.1:0');
      expect(settings.realms.single.roles.single.permissions.single.allow, [
        'call',
      ]);
    });

    for (final input in ['null', '[]', 'false']) {
      test('top-level documents reject $input', () {
        expect(
          () => RouterConfigLoader.fromJsonString(input),
          throwsFormatException,
        );
        expect(
          () => RouterConfigLoader.fromYamlString(input),
          throwsFormatException,
        );
      });
    }
    test('a missing router section does not become a default router', () {
      expect(() => RouterConfigLoader.fromMap({}), throwsFormatException);
    });

    test('header names must be strings even for direct map input', () {
      expect(
        () => RouterConfigLoader.fromMap(
          _withSetting(
            'listeners.0.http.routes.0.match.headers',
            {1: 'value'},
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Header keys must be strings',
          ),
        ),
      );
    });
    test('null header values are omitted and the result is immutable', () {
      final match = loadValidRouterConfig(
        _withSetting(
          'listeners.0.http.routes.0.match.headers',
          {'X-Keep': 'value', 'X-Omit': null},
        ),
      ).listeners.single.http!.routes.single.match;
      expect(match.headers, {'X-Keep': 'value'});
      expect(() => match.headers['X-New'] = 'value', throwsUnsupportedError);
    });

    for (final field in ['max_requests', 'window_ms', 'max_buckets']) {
      for (final invalid in [0, -1]) {
        test('rate limit rejects $field = $invalid', () {
          expect(
            () => _action({field: invalid}),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                'listener.http.routes.action.rate_limit.$field must be > 0',
              ),
            ),
          );
        });
      }
    }
    for (final key in ['unknown', 'header:', 'header:   ', '']) {
      test('rate limit rejects empty or unsupported bucket key "$key"', () {
        expect(() => _action({'key': key}), throwsFormatException);
      });
    }
    test('explicit rate-limit disabling is distinct from defaults', () {
      expect(expectConfigSuccess(() => _action(false)).rateLimit, isNull);
      expect(expectConfigSuccess(() => _action(null)).rateLimit, isNull);
      final enabled = expectConfigSuccess(() => _action(true)).rateLimit;
      expect(enabled, isNotNull);
      expect(enabled!.maxRequests, 60);
      expect(enabled.windowMs, 60000);
      expect(enabled.key, 'global');
      expect(enabled.maxBuckets, 4096);
    });
    test(
      'rate-limit aliases normalize keys and respect primary precedence',
      () {
        final aliases = expectConfigSuccess(
          () => _action({
            'requests': 7,
            'intervalMs': 1234,
            'keyBy': ' HEADER: X-Tenant ',
            'maxBuckets': 13,
          }),
        ).rateLimit;
        expect(aliases, isNotNull);
        expect(aliases!.maxRequests, 7);
        expect(aliases.windowMs, 1234);
        expect(aliases.key, 'header:x-tenant');
        expect(aliases.maxBuckets, 13);
        final primary = expectConfigSuccess(
          () => _action({
            'max_requests': 3,
            'requests': 7,
            'window_ms': 10,
            'intervalMs': 20,
            'key': ' BEARER ',
            'keyBy': 'connection',
            'max_buckets': 5,
            'maxBuckets': 6,
          }),
        ).rateLimit;
        expect(primary, isNotNull);
        expect(primary!.maxRequests, 3);
        expect(primary.windowMs, 10);
        expect(primary.key, 'bearer');
        expect(primary.maxBuckets, 5);
      },
    );
    test('provider shorthand retains types and default options', () {
      final input = _withSetting('authorization_providers.policy', 'local');
      final router = input['router']! as Map<String, Object?>;
      router['http_auth_providers'] = {'tokens': 'bearer'};
      final settings = loadValidRouterConfig(input);
      expect(settings.authorizationProviders.keys, contains('policy'));
      expect(settings.httpAuthProviders.keys, contains('tokens'));
      expect(settings.authorizationProviders['policy']!.type, 'local');
      expect(settings.authorizationProviders['policy']!.options, isEmpty);
      expect(settings.httpAuthProviders['tokens']!.type, 'bearer');
      expect(settings.httpAuthProviders['tokens']!.options, isEmpty);
    });
    test(
      'legacy WebSocket fields survive normalization without input mutation',
      () {
        final input = _withSetting('listeners.0.path', '/legacy-ws');
        final router = input['router']! as Map<String, Object?>;
        final listener =
            (router['listeners']! as List).single as Map<String, Object?>;
        listener['options'] = {
          'serializer_fallback': 'cbor',
          'subprotocols': ['wamp.2.cbor'],
        };
        final original = jsonEncode(input);
        final websocket = loadValidRouterConfig(
          input,
        ).listeners.single.websocket!;
        expect(websocket.path, '/legacy-ws');
        expect(websocket.serializerFallback, 'cbor');
        expect(websocket.subprotocols, ['wamp.2.cbor']);
        expect(
          () => websocket.subprotocols.add('wamp.2.json'),
          throwsUnsupportedError,
        );
        expect(jsonEncode(input), original);
      },
    );
    for (final options in [
      <String, Object?>{},
      {'max_body_size': 8192},
    ]) {
      test(
        'legacy HTTP retains options $options without an explicit HTTP node',
        () {
          final input = _withSetting('listeners.0.http', null);
          final router = input['router']! as Map<String, Object?>;
          final listener =
              (router['listeners']! as List).single as Map<String, Object?>;
          listener['type'] = 'http';
          listener['options'] = options;
          final http = loadValidRouterConfig(input).listeners.single.http;
          expect(http, isNotNull);
          expect(http!.options, options);
          expect(() => http.options['new'] = true, throwsUnsupportedError);
        },
      );
    }
    test('a listener with no explicit type defaults to RawSocket', () {
      final listener = loadValidRouterConfig(
        _withSetting('listeners.0.type', null),
      ).listeners.single;
      expect(listener.protocols, [ListenerProtocol.rawsocket]);
    });
    test(
      'method authentication options retain content and cannot be replaced',
      () {
        final settings = loadValidRouterConfig(
          _withSetting('realms.0.auth.ticket', {
            'authenticator': 'remote',
            'required': true,
          }),
        );
        final options = settings.realms.single.auth.methodOptions;
        expect(options, {
          'ticket': {'authenticator': 'remote', 'required': true},
        });
        expect(
          () => options['ticket']!['required'] = false,
          throwsUnsupportedError,
        );
      },
    );
    test(
      'integral numeric scalars work for required and optional integer fields',
      () {
        final input = _withSetting('worker_pool.min_workers', 3.0);
        final router = input['router']! as Map<String, Object?>;
        final listener =
            (router['listeners']! as List).single as Map<String, Object?>;
        listener['rawsocket'] = {'max_rawsocket_size_exponent': 16.0};
        final settings = loadValidRouterConfig(input);
        expect(settings.workerPool.minWorkers, 3);
        expect(settings.listeners.single.rawsocket!.maxFrameExponent, 16);
      },
    );
    test('nullable per-method authentication options remain empty options', () {
      final settings = loadValidRouterConfig(
        _withSetting('realms.0.auth.ticket', null),
      );
      expect(settings.realms.single.auth.methodOptions, {
        'ticket': <String, Object?>{},
      });
    });
  });

  group('configuration semantic defaults', () {
    test('identities are not disclosed and realms are not auto-created', () {
      final realm = loadValidRouterConfig(_config()).realms.single;
      expect(realm.autoCreate, isFalse);
      final disclose = realm.roles.single.permissions.single.disclose;
      expect(disclose.caller, isFalse);
      expect(disclose.publisher, isFalse);
      expect(disclose.callee, isFalse);
    });
    test(
      'absent optional sections retain empty rather than enabled values',
      () {
        expect(
          loadValidRouterConfig(_withSetting('listeners', null)).listeners,
          isEmpty,
        );
        expect(
          loadValidRouterConfig(
            _withSetting('realms.0.roles.0.permissions', null),
          ).realms.single.roles.single.permissions,
          isEmpty,
        );
        expect(
          loadValidRouterConfig(
            _withSetting('listeners.0.http.routes', null),
          ).listeners.single.http!.routes,
          isEmpty,
        );
        final auth = loadValidRouterConfig(
          _withSetting('session_profiles.0.auth', null),
        ).sessionProfiles.single.auth;
        expect(auth.methods, isEmpty);
        expect(auth.authId, isNull);
        expect(auth.authRole, isNull);
        expect(auth.httpProvider, isNull);
        final match = loadValidRouterConfig(
          _withSetting('listeners.0.http.routes.0.match', null),
        ).listeners.single.http!.routes.single.match;
        expect(match.path, isNull);
        expect(match.prefix, isNull);
        expect(match.host, isNull);
        expect(match.methods, isEmpty);
        expect(match.protocols, isEmpty);
        expect(match.headers, isEmpty);
        expect(match.extra, isEmpty);
      },
    );
    test('session auth identity uses snake-case before camel-case alias', () {
      final auth = loadValidRouterConfig(
        _withSetting('session_profiles.0.auth', {
          'auth_id': 'primary-user',
          'authId': 'other-user',
        }),
      ).sessionProfiles.single.auth;
      expect(auth.authId, 'primary-user');
    });
    test('HTTP3 and OpenMetrics are enabled by their empty configuration', () {
      final settings = loadValidRouterConfig(_config());
      expect(settings.listeners.single.http!.http3!.enabled, isTrue);
      final metrics = settings.metrics!.openMetrics!;
      expect(metrics.enabled, isTrue);
      expect(metrics.collectionTimeout, const Duration(seconds: 5));
      expect(metrics.path, '/metrics');
      expect(metrics.realm, 'connectanum.metrics');
      expect(metrics.listen, isNull);
      expect(metrics.authToken, isNull);
    });
    test('metrics container alone does not enable an OpenMetrics endpoint', () {
      expect(
        loadValidRouterConfig(
          _withSetting('metrics', <String, Object?>{}),
        ).metrics!.openMetrics,
        isNull,
      );
    });
    test('zero collection timeout and zero minimum workers are valid', () {
      expect(
        loadValidRouterConfig(
          _withSetting('metrics.open_metrics.collection_timeout_ms', 0),
        ).metrics!.openMetrics!.collectionTimeout,
        Duration.zero,
      );
      expect(
        loadValidRouterConfig(
          _withSetting('worker_pool.min_workers', 0),
        ).workerPool.minWorkers,
        0,
      );
    });
    for (final services in [null, <String>[]]) {
      test(
        'services $services normalizes to an immutable empty service set',
        () {
          final selected = loadValidRouterConfig(
            _withSetting('internal_realms.0.services', services),
          ).internalRealms.single.services;
          expect(selected, isEmpty);
          expect(() => selected.add('meta'), throwsUnsupportedError);
        },
      );
    }
    test('authenticator options survive parsing and are immutable', () {
      final options = loadValidRouterConfig(
        _withSetting('authenticators.anonymous.options', {
          'auth_role': 'guest',
          'enabled': false,
        }),
      ).authenticators['anonymous']!.options;
      expect(options, {'auth_role': 'guest', 'enabled': false});
      expect(() => options['auth_role'] = 'admin', throwsUnsupportedError);
    });
    test('connection-scoped rate limits stay distinct from global limits', () {
      final action = expectConfigSuccess(
        () => _action({'key': ' CONNECTION '}),
      );
      expect(action.rateLimit, isNotNull);
      expect(action.rateLimit!.key, 'connection');
    });
    test('parsed configuration collections retain fixed lengths', () {
      final settings = loadValidRouterConfig(
        _withSetting('listeners.0.authmethods', ['ticket']),
      );
      final collections = <String, List<Object?>>{
        'realms': settings.realms,
        'realm authentication methods': settings.realms.single.auth.methods,
        'roles': settings.realms.single.roles,
        'permissions': settings.realms.single.roles.single.permissions,
        'listeners': settings.listeners,
        'listener auth methods': settings.listeners.single.authmethods,
        'HTTP routes': settings.listeners.single.http!.routes,
        'session profiles': settings.sessionProfiles,
        'internal realms': settings.internalRealms,
      };
      for (final entry in collections.entries) {
        expect(entry.value, isNotEmpty, reason: entry.key);
        final original = List<Object?>.of(entry.value);
        expect(
          () => entry.value.add(entry.value.first),
          throwsUnsupportedError,
          reason: entry.key,
        );
        expect(entry.value, original, reason: entry.key);
      }
    });

    test('caller changes cannot replace parsed auth methods or routes', () {
      final input = _config();
      final router = input['router']! as Map<String, Object?>;
      final realm = (router['realms']! as List).single as Map<String, Object?>;
      final auth = realm['auth']! as Map<String, Object?>;
      final methods = auth['authmethods']! as List;
      final listener =
          (router['listeners']! as List).single as Map<String, Object?>;
      final http = listener['http']! as Map<String, Object?>;
      final routes = http['routes']! as List;
      final settings = loadValidRouterConfig(input);

      methods[0] = 'ticket';
      routes.clear();

      expect(settings.realms.single.auth.methods, ['anonymous']);
      expect(settings.listeners.single.http?.routes, hasLength(1));
      final route = settings.listeners.single.http!.routes.single;
      expect(route.match.path, '/echo');
      expect(route.action.type, HttpRouteActionType.rpc);
      expect(route.action.procedure, 'com.example.echo');
    });
  });

  group('legacy transport selection', () {
    for (final selection in <(Map<String, Object?>, bool, bool, bool)>[
      ({}, true, false, false),
      (
        {
          'protocols': ['rawsocket'],
        },
        true,
        false,
        false,
      ),
      ({'type': 'rawsocket'}, true, false, false),
      (
        {
          'protocols': ['websocket'],
        },
        false,
        true,
        false,
      ),
      ({'type': 'websocket'}, false, true, false),
      ({'protocols': <String>[], 'type': 'websocket'}, false, true, false),
      (
        {
          'protocols': ['http'],
        },
        false,
        false,
        true,
      ),
      ({'type': 'http'}, false, false, true),
      (
        {
          'protocols': ['websocket'],
          'type': 'rawsocket',
        },
        true,
        true,
        false,
      ),
      (
        {
          'protocols': ['rawsocket'],
          'type': 'websocket',
        },
        true,
        true,
        false,
      ),
      (
        {
          'protocols': ['rawsocket'],
          'type': 'http',
        },
        true,
        false,
        false,
      ),
    ]) {
      test(
        'only selected legacy settings are constructed for ${selection.$1}',
        () {
          final listener = loadValidRouterConfig(
            _withSetting('listeners.0', {
              'endpoint': '127.0.0.1:0',
              ...selection.$1,
              'options': {
                'max_rawsocket_size_exponent': 14,
                'serializer_fallback': 'cbor',
              },
            }),
          ).listeners.single;
          expect(
            listener.rawsocket?.maxFrameExponent,
            selection.$2 ? 14 : null,
          );
          expect(
            listener.websocket?.serializerFallback,
            selection.$3 ? 'cbor' : null,
          );
          expect(listener.http != null, selection.$4);
          if (!selection.$2) expect(listener.rawsocket, isNull);
          if (!selection.$3) expect(listener.websocket, isNull);
        },
      );
    }
    for (final type in ['rawsocket', 'websocket']) {
      test('$type without legacy fields leaves optional settings absent', () {
        final listener = loadValidRouterConfig(
          _withSetting('listeners.0', {
            'endpoint': '127.0.0.1:0',
            'type': type,
          }),
        ).listeners.single;
        expect(listener.rawsocket, isNull);
        expect(listener.websocket, isNull);
        expect(listener.http, isNull);
      });
    }
    for (final field in ['path', 'serializer_fallback', 'subprotocols']) {
      test('WebSocket $field alone is sufficient for legacy settings', () {
        final websocket = loadValidRouterConfig(
          _withSetting('listeners.0', {
            'endpoint': '127.0.0.1:0',
            'protocols': ['websocket'],
            if (field == 'path') 'path': '/legacy',
            'options': {
              if (field == 'serializer_fallback') 'serializer_fallback': 'cbor',
              if (field == 'subprotocols') 'subprotocols': ['wamp.2.cbor'],
            },
          }),
        ).listeners.single.websocket!;
        expect(websocket.path, field == 'path' ? '/legacy' : null);
        expect(
          websocket.serializerFallback,
          field == 'serializer_fallback' ? 'cbor' : null,
        );
        expect(
          websocket.subprotocols,
          field == 'subprotocols' ? ['wamp.2.cbor'] : isEmpty,
        );
      });
    }
    test('unselected legacy transport options are not interpreted', () {
      final listener = loadValidRouterConfig(
        _withSetting('listeners.0', {
          'endpoint': '127.0.0.1:0',
          'protocols': ['http'],
          'options': {
            'max_rawsocket_size_exponent': false,
            'serializer_fallback': false,
            'subprotocols': false,
          },
        }),
      ).listeners.single;
      expect(listener.rawsocket, isNull);
      expect(listener.websocket, isNull);
      expect(listener.http!.options, {
        'max_rawsocket_size_exponent': false,
        'serializer_fallback': false,
        'subprotocols': false,
      });
    });
  });
}

HttpRouteAction _action(Object? value) => RouterConfigLoader.fromMap(
  _withSetting('listeners.0.http.routes.0.action.rate_limit', value),
).listeners.single.http!.routes.single.action;

Map<String, Object?> _withSetting(String path, Object? value) {
  final input = jsonDecode(jsonEncode(_config())) as Map<String, Object?>;
  Object? cursor = input['router'];
  final parts = path.split('.');
  for (final part in parts.take(parts.length - 1)) {
    cursor = cursor is List
        ? cursor[int.parse(part)]
        : (cursor as Map<String, Object?>)[part];
  }
  if (cursor is List) {
    cursor[int.parse(parts.last)] = value;
  } else {
    (cursor as Map<String, Object?>)[parts.last] = value;
  }
  return input;
}

Map<String, Object?> _config() => {
  'router': <String, Object?>{
    'realms': [
      <String, Object?>{
        'name': 'consumer.realm',
        'auth': <String, Object?>{
          'authmethods': ['anonymous'],
        },
        'limits': <String, Object?>{},
        'roles': [
          <String, Object?>{
            'name': 'member',
            'permissions': [
              <String, Object?>{
                'uri': 'com.example.echo',
                'allow': ['call'],
                'disclose': <String, Object?>{},
              },
            ],
          },
        ],
      },
    ],
    'listeners': [
      <String, Object?>{
        'endpoint': '127.0.0.1:0',
        'type': 'websocket',
        'http': <String, Object?>{
          'http3': <String, Object?>{},
          'routes': [
            <String, Object?>{
              'match': <String, Object?>{'path': '/echo'},
              'action': <String, Object?>{
                'type': 'rpc',
                'procedure': 'com.example.echo',
              },
            },
          ],
        },
      },
    ],
    'session_profiles': [
      <String, Object?>{'name': 'public', 'auth': <String, Object?>{}},
    ],
    'authorization_providers': <String, Object?>{
      'policy': <String, Object?>{'type': 'local'},
    },
    'http_auth_providers': <String, Object?>{
      'tokens': <String, Object?>{'type': 'bearer'},
    },
    'internal_realms': [
      <String, Object?>{'name': 'admin'},
    ],
    'metrics': <String, Object?>{'open_metrics': <String, Object?>{}},
    'authenticators': <String, Object?>{
      'anonymous': <String, Object?>{'type': 'anonymous'},
    },
    'worker_pool': <String, Object?>{},
  },
};
