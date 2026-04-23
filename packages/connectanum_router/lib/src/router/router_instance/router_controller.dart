part of '../router_instance.dart';

/// High-level router builder that applies configuration to the native runtime
/// and returns a ready-to-use [RouterBinding].
class Router {
  Router(this.config, {RouterSettings? settings}) : _settings = settings {
    _validateConfig();
  }

  final RouterConfig config;
  final RouterSettings? _settings;

  /// Builds the JSON payload expected by the native runtime.
  Uint8List buildNativeConfigJson([RouterSettings? settingsOverride]) {
    final map = _buildNativeMap(settingsOverride ?? _settings);
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  RouterBinding start(
    NativeRuntime runtime, {
    RouterWorkerEntryPoint? workerEntryPoint,
    Duration workerPollInterval = const Duration(milliseconds: 1),
    RouterSettings? settings,
    void Function(Object event)? onEvent,
    bool activateListeners = true,
  }) {
    final routerSettings = settings ?? _settings ?? _buildDefaultSettings();
    final configBytes = buildNativeConfigJson(routerSettings);
    try {
      runtime.applyRouterConfig(configBytes);
    } on UnsupportedError {
      // Ignore runtimes that do not yet support configuration wiring.
    }
    final binding = RouterBinding(
      runtime: runtime,
      endpoints: config.endpoints,
      configJson: configBytes,
      settings: routerSettings,
      workerEntryPoint: workerEntryPoint ?? defaultRouterWorkerEntryPoint,
      workerPollInterval: workerPollInterval,
      onEvent: onEvent,
    );
    if (activateListeners) {
      binding.activateListeners();
    }
    return binding;
  }

  Map<String, Object?> _buildNativeMap(RouterSettings? settings) {
    final listenerByEndpoint = <String, ListenerSettings>{};
    if (settings != null) {
      for (final listener in settings.listeners) {
        listenerByEndpoint[_normalizeConfiguredEndpoint(listener.endpoint)] =
            listener;
      }
    }
    final endpoints = config.endpoints
        .map((endpoint) {
          final map = endpoint.toNativeJson();
          final key = _endpointKey(endpoint.host, endpoint.port);
          final listener = listenerByEndpoint[key];
          map['protocols'] =
              listener?.protocols
                  .map(listenerProtocolToString)
                  .toList(growable: false) ??
              const <String>['rawsocket'];
          final httpSettings = listener?.http;
          if (httpSettings != null && httpSettings.routes.isNotEmpty) {
            map['http_routes'] = httpSettings.routes
                .map(
                  (route) =>
                      _httpRouteSettingsToNative(route, listener, settings),
                )
                .toList(growable: false);
            final httpConfig = <String, Object?>{};
            if (httpSettings.alpn.isNotEmpty) {
              httpConfig['alpn'] = List<String>.from(httpSettings.alpn);
            }
            final http3 = httpSettings.http3;
            if (http3 != null) {
              httpConfig['http3'] = <String, Object?>{
                'enabled': http3.enabled,
                if (http3.port != null) 'port': http3.port,
              };
            }
            if (httpSettings.options.isNotEmpty) {
              httpConfig['options'] = Map<String, Object?>.from(
                httpSettings.options,
              );
            }
            if (httpConfig.isNotEmpty) {
              map['http'] = httpConfig;
            }
          } else if (listener != null &&
              listener.protocols.any((protocol) => protocol.isHttp)) {
            map['http'] = const <String, Object?>{};
          }
          return map;
        })
        .toList(growable: false);
    return <String, Object?>{
      'schema': config.schema,
      'version': config.version,
      'endpoints': endpoints,
    };
  }

  Map<String, Object?> _httpRouteSettingsToNative(
    HttpRouteSettings route,
    ListenerSettings? listener,
    RouterSettings? settings,
  ) {
    final match = route.match;
    final path = (match.path ?? match.prefix)?.trim();
    final matchKind = match.prefix != null && match.path == null
        ? 'prefix'
        : 'exact';
    final routeMap = <String, Object?>{
      'path': (path != null && path.isNotEmpty) ? path : '/',
      'match_kind': matchKind,
    };
    if (match.headers.isNotEmpty) {
      routeMap['headers'] = Map<String, String>.from(match.headers);
    }
    if (match.protocols.isNotEmpty) {
      routeMap['protocols'] = List<String>.from(match.protocols);
    }
    final transportAuth = deriveHttpRouteTransportAuth(
      action: route.action,
      sessionProfile: _sessionProfileForRoute(
        action: route.action,
        listener: listener,
        settings: settings,
      ),
    );
    if (transportAuth.isConfigured) {
      routeMap['transport_auth'] = transportAuth.toNativeMap();
    }

    final methods = match.methods
        .map((method) => method.trim().toUpperCase())
        .where((method) => method.isNotEmpty)
        .toList(growable: false);
    if (methods.isEmpty) {
      routeMap['default'] = _httpRouteActionToNative(
        route.action,
        listener,
        settings,
      );
    } else {
      final targets = <String, Object?>{};
      for (final method in methods) {
        targets[method] = _httpRouteActionToNative(
          route.action,
          listener,
          settings,
        );
      }
      routeMap['methods'] = targets;
    }
    return routeMap;
  }

  Map<String, Object?> _httpRouteActionToNative(
    HttpRouteAction action,
    ListenerSettings? listener,
    RouterSettings? settings,
  ) {
    switch (action.type) {
      case HttpRouteActionType.rpc:
      case HttpRouteActionType.internalCall:
        final procedure = action.procedure?.trim();
        if (procedure == null || procedure.isEmpty) {
          throw StateError(
            'HTTP RPC routes require a non-empty procedure name.',
          );
        }
        final realm = _resolveRouteRealm(
          action,
          listener,
          settings,
          fallbackFromProcedure: action.type == HttpRouteActionType.internalCall
              ? procedure
              : null,
        );
        if (realm == null || realm.isEmpty) {
          throw StateError(
            'HTTP ${action.type.name} routes require a realm; specify action.options.realm or configure a default realm.',
          );
        }
        return {'type': 'translation', 'realm': realm, 'procedure': procedure};
      case HttpRouteActionType.auth:
        return const <String, Object?>{
          'type': 'translation',
          'realm': 'router.http',
          'procedure': 'router.http.auth',
        };
      case HttpRouteActionType.reservedRealm:
        final namespace = _resolveRouteNamespace(action);
        final appendSuffix = _resolveAppendMethodSuffix(action);
        return <String, Object?>{
          'type': 'reserved_realm',
          'namespace': ?namespace,
          'append_method_suffix': appendSuffix,
        };
      case HttpRouteActionType.namespace:
        final namespace = _resolveRouteNamespace(action);
        if (namespace == null || namespace.isEmpty) {
          throw StateError(
            'HTTP namespace routes require a namespace; set action.namespace or action.options.namespace.',
          );
        }
        final realm = _resolveRouteRealm(action, listener, settings);
        if (realm == null || realm.isEmpty) {
          throw StateError(
            'HTTP namespace routes require a realm; specify action.realm, action.options.realm, or configure a listener/default realm.',
          );
        }
        final appendSuffix = _resolveAppendMethodSuffix(action);
        return <String, Object?>{
          'type': 'namespace',
          'realm': realm,
          'namespace': namespace,
          'append_method_suffix': appendSuffix,
        };
      default:
        throw StateError(
          'HTTP route action ${action.type} is not yet supported for native wiring.',
        );
    }
  }

  String? _resolveRouteRealm(
    HttpRouteAction action,
    ListenerSettings? listener,
    RouterSettings? settings, {
    String? fallbackFromProcedure,
  }) {
    String? realm;
    final directRealm = action.realm?.trim();
    if (directRealm != null && directRealm.isNotEmpty) {
      realm = directRealm;
    }
    final optionRealm =
        action.options['realm'] ?? action.options['targetRealm'];
    if (optionRealm is String && optionRealm.trim().isNotEmpty) {
      realm = optionRealm.trim();
    }
    final sessionProfile = _sessionProfileForRoute(
      action: action,
      listener: listener,
      settings: settings,
    );
    final profileRealm = sessionProfile?.realm?.trim();
    if ((realm == null || realm.isEmpty) &&
        profileRealm != null &&
        profileRealm.isNotEmpty) {
      realm = profileRealm;
    }
    realm ??= _listenerRealm(listener);
    realm ??= _uniqueRealm(settings);
    if (realm == null &&
        settings?.metrics?.openMetrics?.realm != null &&
        fallbackFromProcedure != null &&
        fallbackFromProcedure.startsWith(
          '${settings!.metrics!.openMetrics!.realm}.',
        )) {
      realm = settings.metrics!.openMetrics!.realm;
    }
    if (realm == null && fallbackFromProcedure != null) {
      final lastDot = fallbackFromProcedure.lastIndexOf('.');
      if (lastDot > 0) {
        realm = fallbackFromProcedure.substring(0, lastDot);
      }
    }
    return realm;
  }

  SessionProfileSettings? _sessionProfileForRoute({
    required HttpRouteAction action,
    required ListenerSettings? listener,
    required RouterSettings? settings,
  }) {
    if (settings == null) {
      return null;
    }
    final actionProfile = action.sessionProfile?.trim();
    final listenerProfile = listener?.http?.sessionProfile?.trim();
    final profileName = (actionProfile != null && actionProfile.isNotEmpty)
        ? actionProfile
        : ((listenerProfile != null && listenerProfile.isNotEmpty)
              ? listenerProfile
              : null);
    if (profileName == null) {
      return null;
    }
    for (final profile in settings.sessionProfiles) {
      if (profile.name == profileName) {
        return profile;
      }
    }
    throw StateError(
      'Unknown session profile "$profileName" referenced by HTTP route.',
    );
  }

  String? _resolveRouteNamespace(HttpRouteAction action) {
    final direct = action.namespace?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final optionNamespace = action.options['namespace'];
    if (optionNamespace is String) {
      final trimmed = optionNamespace.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  bool _resolveAppendMethodSuffix(
    HttpRouteAction action, {
    bool defaultValue = true,
  }) {
    if (action.appendMethodSuffix != null) {
      return action.appendMethodSuffix!;
    }
    final optionValue = action.options['append_method_suffix'];
    if (optionValue is bool) {
      return optionValue;
    }
    return defaultValue;
  }

  String? _listenerRealm(ListenerSettings? listener) {
    if (listener == null) {
      return null;
    }
    // If the listener options specify an explicit realm, surface it.
    final realm = listener.options['realm'];
    if (realm is String && realm.trim().isNotEmpty) {
      return realm.trim();
    }
    return null;
  }

  String? _uniqueRealm(RouterSettings? settings) {
    if (settings == null) {
      return null;
    }
    final realmNames = settings.realms.map((realm) => realm.name).toSet();
    if (realmNames.length == 1) {
      return realmNames.single;
    }
    return null;
  }

  void _validateConfig() {
    if (config.endpoints.isEmpty) {
      throw ArgumentError('Router requires at least one endpoint');
    }
    final tlsModes = <TlsMode>{};
    int? nativeExponent;
    for (final endpoint in config.endpoints) {
      if (endpoint.tlsMode == TlsMode.dart) {
        throw ArgumentError(
          'TlsMode.dart is not supported yet; use TlsMode.native or terminate TLS externally.',
        );
      }
      tlsModes.add(endpoint.tlsMode);
      if (endpoint.tlsMode == TlsMode.native) {
        nativeExponent ??= endpoint.maxRawSocketSizeExponent;
        if (endpoint.maxRawSocketSizeExponent != nativeExponent) {
          throw ArgumentError(
            'All native TLS endpoints must share the same maxRawSocketSizeExponent. '
            'Expected $nativeExponent but found ${endpoint.maxRawSocketSizeExponent} on ${endpoint.host}:${endpoint.port}.',
          );
        }
      }
    }
    if (tlsModes.contains(TlsMode.native) && tlsModes.contains(TlsMode.dart)) {
      throw ArgumentError(
        'Mixing native and Dart TLS modes across endpoints is currently unsupported',
      );
    }
  }

  RouterSettings _buildDefaultSettings() {
    final realmBuilder = RealmSettingsBuilder('realm1')
      ..addAuthMethod('anonymous')
      ..addRoleFromBuilder(
        RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
          PermissionSettingsBuilder('')
            ..setMatchPolicy(PermissionMatchPolicy.prefix)
            ..allowOperations(const [
              'subscribe',
              'publish',
              'call',
              'register',
              'unregister',
            ]),
        ),
      );

    final listeners = config.endpoints
        .map((endpoint) {
          final builder =
              ListenerSettingsBuilder(
                  'rawsocket',
                  '${endpoint.host}:${endpoint.port}',
                )
                ..addAuthMethod('anonymous')
                ..setOptions({
                  'max_rawsocket_size_exponent':
                      endpoint.maxRawSocketSizeExponent,
                });
          return builder.build();
        })
        .toList(growable: false);

    return RouterSettings(
      realms: [realmBuilder.build()],
      listeners: listeners,
      metrics: null,
      authenticators: const {
        'anonymous': AuthenticatorDefinition(type: 'anonymous'),
      },
      workerPool: const WorkerPoolSettings(),
    );
  }
}
