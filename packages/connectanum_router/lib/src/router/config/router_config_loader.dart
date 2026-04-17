import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'router_settings.dart';

/// Parses router configuration files (JSON or YAML) into strongly typed settings.
class RouterConfigLoader {
  const RouterConfigLoader._();

  /// Parses a JSON document containing the router configuration.
  static RouterSettings fromJsonString(String source) {
    final dynamic decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Top-level JSON document must be an object');
    }
    return fromMap(decoded);
  }

  static List<ListenerProtocol> _parseListenerProtocols(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('listener.protocols must be a list');
    }
    final result = <ListenerProtocol>[];
    for (final entry in node) {
      if (entry is! String) {
        throw FormatException('listener.protocols entries must be strings');
      }
      result.add(listenerProtocolFromString(entry));
    }
    return List.unmodifiable(result);
  }

  static RawSocketListenerSettings? _parseRawSocketListener(dynamic node) {
    if (node == null) {
      return null;
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('listener.rawsocket must be a map');
    }
    final maxExponent = _asNullableInt(node['max_rawsocket_size_exponent']);
    final options = _asMap(node['options'], allowNull: true) ?? const {};
    return RawSocketListenerSettings(
      maxFrameExponent: maxExponent,
      options: options,
    );
  }

  static WebSocketListenerSettings? _parseWebSocketListener(
    dynamic node,
    String? legacyPath,
  ) {
    if (node == null) {
      return null;
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('listener.websocket must be a map');
    }
    final path = _asNullableString(node['path']) ?? legacyPath;
    final subprotocols = _stringList(node['subprotocols']);
    final serializerFallback = _asNullableString(node['serializer_fallback']);
    final options = _asMap(node['options'], allowNull: true) ?? const {};
    return WebSocketListenerSettings(
      path: path,
      subprotocols: subprotocols,
      serializerFallback: serializerFallback,
      options: options,
    );
  }

  static HttpListenerSettings? _parseHttpListener(dynamic node) {
    if (node == null) {
      return null;
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('listener.http must be a map');
    }
    final alpn = _stringList(node['alpn']);
    final sessionProfile = _asNullableString(node['session_profile']);
    final http3Node = node['http3'];
    Http3Settings? http3;
    if (http3Node != null) {
      if (http3Node is! Map<String, Object?>) {
        throw FormatException('listener.http.http3 must be a map');
      }
      final enabled = _asBool(http3Node['enabled'], defaultValue: true);
      final port = _asNullableInt(http3Node['port']);
      http3 = Http3Settings(enabled: enabled, port: port);
    }
    final routes = _parseHttpRoutes(node['routes']);
    final options = _asMap(node['options'], allowNull: true) ?? const {};
    return HttpListenerSettings(
      alpn: List.unmodifiable(alpn),
      http3: http3,
      sessionProfile: sessionProfile,
      routes: List.unmodifiable(routes),
      options: options,
    );
  }

  static List<HttpRouteSettings> _parseHttpRoutes(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('listener.http.routes must be a list');
    }
    return node
        .map((route) {
          if (route is! Map<String, Object?>) {
            throw FormatException('listener.http.routes entries must be maps');
          }
          final match = _parseHttpRouteMatch(route['match']);
          final action = _parseHttpRouteAction(route['action']);
          return HttpRouteSettings(match: match, action: action);
        })
        .toList(growable: false);
  }

  static HttpRouteMatch _parseHttpRouteMatch(dynamic node) {
    if (node == null) {
      return const HttpRouteMatch();
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('listener.http.routes.match must be a map');
    }
    final matchMap = Map<String, Object?>.from(node);
    final path = _asNullableString(matchMap.remove('path'));
    final prefix = _asNullableString(matchMap.remove('prefix'));
    final host = _asNullableString(matchMap.remove('host'));
    final methods = _stringList(matchMap.remove('methods'));
    final method = _asNullableString(matchMap.remove('method'));
    final combinedMethods = <String>[...methods, if (method != null) method];
    final headers = _stringStringMap(matchMap.remove('headers'));
    return HttpRouteMatch(
      path: path,
      prefix: prefix,
      host: host,
      methods: List.unmodifiable(combinedMethods),
      headers: headers,
      extra: Map<String, Object?>.unmodifiable(matchMap),
    );
  }

  static HttpRouteAction _parseHttpRouteAction(dynamic node) {
    if (node is! Map<String, Object?>) {
      throw FormatException('listener.http.routes.action must be a map');
    }
    final map = Map<String, Object?>.from(node);
    final type = httpRouteActionTypeFromString(
      _expectString(map.remove('type'), 'listener.http.routes.action.type'),
    );
    final procedure = _asNullableString(map.remove('procedure'));
    final realm = _asNullableString(map.remove('realm'));
    final sessionProfile = _asNullableString(
      map.remove('session_profile') ?? map.remove('sessionProfile'),
    );
    final namespace = _asNullableString(map.remove('namespace'));
    final appendMethodSuffix = _asNullableBool(
      map.remove('append_method_suffix'),
    );
    final topic = _asNullableString(map.remove('topic'));
    final serializer = _asNullableString(map.remove('serializer'));
    final contentType = _asNullableString(map.remove('content_type'));
    final directory = _asNullableString(map.remove('directory'));
    final cacheControl = _asNullableString(map.remove('cache_control'));
    final delegate = _asNullableString(map.remove('delegate'));
    final actionOptions =
        _asMap(map.remove('options'), allowNull: true) ?? const {};
    final extras = Map<String, Object?>.unmodifiable(map);
    final mergedOptions = actionOptions.isEmpty && extras.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.unmodifiable(<String, Object?>{
            ...actionOptions,
            ...extras,
          });
    return HttpRouteAction(
      type: type,
      procedure: procedure,
      realm: realm,
      sessionProfile: sessionProfile,
      namespace: namespace,
      appendMethodSuffix: appendMethodSuffix,
      topic: topic,
      serializer: serializer,
      contentType: contentType,
      directory: directory,
      cacheControl: cacheControl,
      delegate: delegate,
      options: mergedOptions,
    );
  }

  static RawSocketListenerSettings? _deriveLegacyRawSocketSettings(
    List<ListenerProtocol> protocols,
    String? type,
    Map<String, Object?> options,
  ) {
    if (!protocols.contains(ListenerProtocol.rawsocket) &&
        type != 'rawsocket') {
      return null;
    }
    final legacyMax = _asNullableInt(options['max_rawsocket_size_exponent']);
    if (legacyMax == null) {
      return null;
    }
    return RawSocketListenerSettings(maxFrameExponent: legacyMax);
  }

  static WebSocketListenerSettings? _deriveLegacyWebSocketSettings(
    List<ListenerProtocol> protocols,
    String? type,
    String? path,
    Map<String, Object?> options,
  ) {
    if (!protocols.contains(ListenerProtocol.websocket) &&
        type != 'websocket') {
      return null;
    }
    final serializerFallback = _asNullableString(
      options['serializer_fallback'],
    );
    final subprotocols = _stringList(options['subprotocols']);
    if (path == null && serializerFallback == null && subprotocols.isEmpty) {
      return null;
    }
    return WebSocketListenerSettings(
      path: path,
      serializerFallback: serializerFallback,
      subprotocols: List.unmodifiable(subprotocols),
    );
  }

  static HttpListenerSettings? _deriveLegacyHttpSettings(
    List<ListenerProtocol> protocols,
    Map<String, Object?> options,
  ) {
    if (!protocols.any((protocol) => protocol.isHttp)) {
      return null;
    }
    return HttpListenerSettings(
      options: options.isEmpty
          ? const {}
          : Map<String, Object?>.unmodifiable(options),
    );
  }

  /// Parses a YAML document containing the router configuration.
  static RouterSettings fromYamlString(String source) {
    final yaml = loadYaml(source);
    final dynamic materialised = _convertYamlNode(yaml);
    if (materialised is! Map<String, Object?>) {
      throw FormatException('Top-level YAML document must be a mapping');
    }
    return fromMap(materialised);
  }

  /// Parses configuration from a map (already decoded from JSON/YAML).
  static RouterSettings fromMap(Map<String, Object?> root) {
    final routerNode = root['router'];
    if (routerNode is! Map<String, Object?>) {
      throw FormatException('Expected "router" section with configuration');
    }

    final realms = _parseRealms(routerNode['realms']);
    final listeners = _parseListeners(routerNode['listeners']);
    final sessionProfiles = _parseSessionProfiles(
      routerNode['session_profiles'],
    );
    final internalRealms = _parseInternalRealms(routerNode['internal_realms']);
    final metrics = _parseMetrics(routerNode['metrics']);
    final authenticators = _parseAuthenticators(routerNode['authenticators']);
    final httpAuthProviders = _parseHttpAuthProviders(
      routerNode['http_auth_providers'],
    );
    final workerPool = _parseWorkerPool(routerNode['worker_pool']);

    return RouterSettings(
      realms: realms,
      listeners: listeners,
      sessionProfiles: sessionProfiles,
      internalRealms: internalRealms,
      metrics: metrics,
      authenticators: authenticators,
      httpAuthProviders: httpAuthProviders,
      workerPool: workerPool,
    );
  }

  static List<SessionProfileSettings> _parseSessionProfiles(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('Router "session_profiles" must be a list');
    }
    return node
        .map((entry) {
          if (entry is! Map<String, Object?>) {
            throw FormatException('session_profiles entries must be maps');
          }
          final name = _expectString(entry['name'], 'session_profiles.name');
          final realm = _asNullableString(entry['realm']);
          final auth = _parseSessionProfileAuth(entry['auth']);
          final roles = _asMap(entry['roles'], allowNull: true) ?? const {};
          return SessionProfileSettings(
            name: name,
            realm: realm,
            auth: auth,
            roles: roles,
          );
        })
        .toList(growable: false);
  }

  static SessionProfileAuthSettings _parseSessionProfileAuth(dynamic node) {
    if (node == null) {
      return const SessionProfileAuthSettings();
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('session_profiles.auth must be a map');
    }
    return SessionProfileAuthSettings(
      methods: _stringList(node['methods']),
      authId: _asNullableString(node['auth_id'] ?? node['authId']),
      authRole: _asNullableString(node['auth_role'] ?? node['authRole']),
      httpProvider: _asNullableString(
        node['http_provider'] ?? node['httpProvider'] ?? node['provider'],
      ),
    );
  }

  static Map<String, HttpAuthProviderDefinition> _parseHttpAuthProviders(
    dynamic node,
  ) {
    if (node == null) {
      return const {};
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('Router "http_auth_providers" must be a map');
    }
    final providers = <String, HttpAuthProviderDefinition>{};
    for (final entry in node.entries) {
      final name = entry.key;
      final value = entry.value;
      if (value is String) {
        providers[name] = HttpAuthProviderDefinition(type: value);
        continue;
      }
      if (value is! Map<String, Object?>) {
        throw FormatException(
          'http_auth_providers.$name must be a string or map',
        );
      }
      final type = _expectString(
        value['type'] ?? value['provider_type'],
        'http_auth_providers.$name.type',
      );
      final options = _asMap(value['options'], allowNull: true) ?? const {};
      providers[name] = HttpAuthProviderDefinition(
        type: type,
        options: options,
      );
    }
    return Map.unmodifiable(providers);
  }

  static List<RealmSettings> _parseRealms(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('Expected "realms" to be a list');
    }
    return node
        .map((entry) {
          if (entry is! Map<String, Object?>) {
            throw FormatException('Each realm entry must be a map');
          }
          final name = _expectString(entry['name'], 'realm.name');
          final autoCreate = _asBool(entry['auto_create'], defaultValue: false);
          final auth = _parseRealmAuth(entry['auth']);
          final roles = _parseRoles(entry['roles']);
          final limits = _parseRealmLimits(entry['limits']);
          return RealmSettings(
            name: name,
            autoCreate: autoCreate,
            auth: auth,
            roles: roles,
            limits: limits,
          );
        })
        .toList(growable: false);
  }

  static RealmAuthSettings _parseRealmAuth(dynamic node) {
    if (node == null) {
      throw FormatException('Realm "auth" section is required');
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('Realm "auth" must be a map');
    }
    final methodsNode = node['authmethods'];
    if (methodsNode is! List) {
      throw FormatException('Realm auth "authmethods" must be a list');
    }
    final methods = methodsNode
        .map((method) {
          if (method is! String) {
            throw FormatException('Auth method names must be strings');
          }
          return method;
        })
        .toList(growable: false);

    final methodOptions = <String, Map<String, Object?>>{};
    final reserved = const {'authmethods'};
    for (final entry in node.entries) {
      final key = entry.key;
      if (reserved.contains(key)) {
        continue;
      }
      final value = entry.value;
      final options = _asMap(value, allowNull: true);
      if (options != null) {
        methodOptions[key] = options;
      } else {
        methodOptions[key] = const {};
      }
    }

    return RealmAuthSettings(
      methods: List.unmodifiable(methods),
      methodOptions: Map.unmodifiable(methodOptions),
    );
  }

  static List<RoleSettings> _parseRoles(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('Realm "roles" must be a list');
    }
    return node
        .map((role) {
          if (role is! Map<String, Object?>) {
            throw FormatException('Role entries must be maps');
          }
          final name = _expectString(role['name'], 'role.name');
          final permissions = _parsePermissions(role['permissions']);
          return RoleSettings(name: name, permissions: permissions);
        })
        .toList(growable: false);
  }

  static List<PermissionSettings> _parsePermissions(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('Role "permissions" must be a list');
    }
    return node
        .map((perm) {
          if (perm is! Map<String, Object?>) {
            throw FormatException('Permission entries must be maps');
          }
          final uri = _expectString(perm['uri'], 'permission.uri');
          final match = permissionMatchPolicyFromString(
            _asString(perm['match'], defaultValue: 'exact'),
          );
          final allow = _stringList(perm['allow']);
          final deny = _stringList(perm['deny']);
          final disclose = _parseDisclose(perm['disclose']);
          return PermissionSettings(
            uri: uri,
            matchPolicy: match,
            allow: allow,
            deny: deny,
            disclose: disclose,
          );
        })
        .toList(growable: false);
  }

  static DiscloseSettings _parseDisclose(dynamic node) {
    if (node == null) {
      return const DiscloseSettings();
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('permission.disclose must be a map');
    }
    return DiscloseSettings(
      caller: _asBool(node['caller'], defaultValue: false),
      publisher: _asBool(node['publisher'], defaultValue: false),
      callee: _asBool(node['callee'], defaultValue: false),
    );
  }

  static RealmLimitSettings _parseRealmLimits(dynamic node) {
    if (node == null) {
      return const RealmLimitSettings();
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('Realm "limits" must be a map');
    }
    return RealmLimitSettings(
      maxPendingAuth: _asInt(node['max_pending_auth'], defaultValue: 32),
      authTimeoutMs: _asInt(node['auth_timeout_ms'], defaultValue: 10000),
      sessionIdleMs: _asInt(node['session_idle_ms'], defaultValue: 600000),
      maxFailedAuth: _asInt(node['max_failed_auth'], defaultValue: 5),
      lockoutMs: _asInt(node['lockout_ms'], defaultValue: 900000),
      callTimeoutMs: _asInt(node['call_timeout_ms'], defaultValue: 30000),
    );
  }

  static List<ListenerSettings> _parseListeners(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('Router "listeners" must be a list');
    }
    return node
        .map((listener) {
          if (listener is! Map<String, Object?>) {
            throw FormatException('Listener entries must be maps');
          }
          final type = _asNullableString(listener['type']);
          final endpoint = _expectString(
            listener['endpoint'],
            'listener.endpoint',
          );
          final path = _asNullableString(listener['path']);
          final authmethods = _stringList(listener['authmethods']);
          final sessionProfile = _asNullableString(
            listener['session_profile'] ?? listener['sessionProfile'],
          );
          final tls = _asMap(listener['tls'], allowNull: true);
          final options =
              _asMap(listener['options'], allowNull: true) ?? const {};
          final protocols = _parseListenerProtocols(listener['protocols']);
          final rawsocket = _parseRawSocketListener(listener['rawsocket']);
          final websocket = _parseWebSocketListener(
            listener['websocket'],
            path,
          );
          final http = _parseHttpListener(listener['http']);

          final resolvedProtocols = List<ListenerProtocol>.unmodifiable(
            protocols.isNotEmpty
                ? protocols
                : (type != null
                      ? <ListenerProtocol>[listenerProtocolFromString(type)]
                      : <ListenerProtocol>[ListenerProtocol.rawsocket]),
          );

          final normalizedRawsocket =
              rawsocket ??
              _deriveLegacyRawSocketSettings(resolvedProtocols, type, options);
          final normalizedWebsocket =
              websocket ??
              _deriveLegacyWebSocketSettings(
                resolvedProtocols,
                type,
                path,
                options,
              );
          final normalizedHttp =
              http ?? _deriveLegacyHttpSettings(resolvedProtocols, options);

          return ListenerSettings(
            type: type,
            endpoint: endpoint,
            path: path,
            authmethods: authmethods,
            sessionProfile: sessionProfile,
            tls: tls,
            options: options,
            protocols: resolvedProtocols,
            rawsocket: normalizedRawsocket,
            websocket: normalizedWebsocket,
            http: normalizedHttp,
          );
        })
        .toList(growable: false);
  }

  static List<InternalRealmSettings> _parseInternalRealms(dynamic node) {
    if (node == null) {
      return const [];
    }
    if (node is! List) {
      throw FormatException('Router "internal_realms" must be a list');
    }
    return node
        .map((entry) {
          if (entry is! Map<String, Object?>) {
            throw FormatException('internal_realms entries must be maps');
          }
          final name = _expectString(entry['name'], 'internal_realms.name');
          final authId = _asNullableString(entry['auth_id']);
          final authRole = _asNullableString(entry['auth_role']);
          final sessionProfile = _asNullableString(
            entry['session_profile'] ?? entry['sessionProfile'],
          );
          final roles = _asMap(entry['roles'], allowNull: true) ?? const {};
          final servicesList = _stringList(entry['services']);
          final Set<String>? services = servicesList.isEmpty
              ? null
              : Set<String>.from(servicesList);
          return InternalRealmSettings(
            name: name,
            authId: authId,
            authRole: authRole,
            sessionProfile: sessionProfile,
            roles: roles,
            services: services,
          );
        })
        .toList(growable: false);
  }

  static MetricsSettings? _parseMetrics(dynamic node) {
    if (node == null) {
      return null;
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('Router "metrics" must be a map');
    }
    final openMetricsNode = node['open_metrics'] ?? node['prometheus'];
    if (openMetricsNode == null) {
      return const MetricsSettings();
    }
    if (openMetricsNode is! Map<String, Object?>) {
      throw FormatException('metrics.open_metrics must be a map');
    }
    final enabled = _asBool(openMetricsNode['enabled'], defaultValue: true);
    final listen = _asNullableString(openMetricsNode['listen']);
    final path = _asString(openMetricsNode['path'], defaultValue: '/metrics');
    final authToken = _asNullableString(openMetricsNode['auth_token']);
    final realm = _asString(
      openMetricsNode['realm'],
      defaultValue: 'connectanum.metrics',
    );
    final backpressureSettings = _parseBackpressureSettings(
      node['backpressure'],
    );
    final transportAlertSettings = _parseTransportAlertSettings(
      node['transport_alerts'],
    );
    return MetricsSettings(
      openMetrics: OpenMetricsSettings(
        enabled: enabled,
        listen: listen,
        path: path,
        authToken: authToken,
        realm: realm,
      ),
      backpressure: backpressureSettings,
      transportAlerts: transportAlertSettings,
    );
  }

  static BackpressureThrottleSettings _parseBackpressureSettings(dynamic node) {
    if (node == null) {
      return const BackpressureThrottleSettings();
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('metrics.backpressure must be a map');
    }
    final depth = _asInt(
      node['depth_threshold'],
      defaultValue: const BackpressureThrottleSettings().depthThreshold,
    );
    final newEvents = _asInt(
      node['new_events_threshold'],
      defaultValue: const BackpressureThrottleSettings().newEventsThreshold,
    );
    final cooldownMs = _asInt(
      node['cooldown_ms'],
      defaultValue:
          const BackpressureThrottleSettings().cooldown.inMilliseconds,
    );
    return BackpressureThrottleSettings(
      depthThreshold: depth,
      newEventsThreshold: newEvents,
      cooldown: Duration(milliseconds: cooldownMs),
    );
  }

  static TransportAlertSettings _parseTransportAlertSettings(dynamic node) {
    if (node == null) {
      return const TransportAlertSettings();
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('metrics.transport_alerts must be a map');
    }
    final goAway = _asInt(
      node['goaway_delta_threshold'],
      defaultValue: const TransportAlertSettings().goAwayDeltaThreshold,
    );
    final idleTimeout = _asInt(
      node['idle_timeout_delta_threshold'],
      defaultValue: const TransportAlertSettings().idleTimeoutDeltaThreshold,
    );
    final bodyTimeout = _asInt(
      node['body_timeout_delta_threshold'],
      defaultValue: const TransportAlertSettings().bodyTimeoutDeltaThreshold,
    );
    final protocolError = _asInt(
      node['protocol_error_delta_threshold'],
      defaultValue: const TransportAlertSettings().protocolErrorDeltaThreshold,
    );
    final internalError = _asInt(
      node['internal_error_delta_threshold'],
      defaultValue: const TransportAlertSettings().internalErrorDeltaThreshold,
    );
    final cooldownMs = _asInt(
      node['cooldown_ms'],
      defaultValue: const TransportAlertSettings().cooldown.inMilliseconds,
    );
    final throttle = _asBool(
      node['throttle_on_alert'],
      defaultValue: const TransportAlertSettings().throttleOnAlert,
    );
    return TransportAlertSettings(
      goAwayDeltaThreshold: goAway,
      idleTimeoutDeltaThreshold: idleTimeout,
      bodyTimeoutDeltaThreshold: bodyTimeout,
      protocolErrorDeltaThreshold: protocolError,
      internalErrorDeltaThreshold: internalError,
      cooldown: Duration(milliseconds: cooldownMs),
      throttleOnAlert: throttle,
    );
  }

  static Map<String, AuthenticatorDefinition> _parseAuthenticators(
    dynamic node,
  ) {
    if (node == null) {
      return const {};
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('Router "authenticators" must be a map');
    }
    final entries = <String, AuthenticatorDefinition>{};
    for (final entry in node.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is! Map<String, Object?>) {
        throw FormatException('Authenticator "$key" must be a map');
      }
      final type = _expectString(value['type'], 'authenticator.type');
      final options = _asMap(value['options'], allowNull: true) ?? const {};
      entries[key] = AuthenticatorDefinition(
        type: type,
        options: Map.unmodifiable(options),
      );
    }
    return Map.unmodifiable(entries);
  }

  static WorkerPoolSettings _parseWorkerPool(dynamic node) {
    if (node == null) {
      return const WorkerPoolSettings();
    }
    if (node is! Map<String, Object?>) {
      throw FormatException('Router "worker_pool" must be a map');
    }
    final minWorkers = _asInt(node['min_workers'], defaultValue: 1);
    if (minWorkers < 0) {
      throw FormatException('worker_pool.min_workers must be >= 0');
    }
    return WorkerPoolSettings(minWorkers: minWorkers);
  }

  static String _expectString(dynamic value, String path) {
    if (value is String) {
      return value;
    }
    throw FormatException('Expected "$path" to be a string');
  }

  static String _asString(dynamic value, {String? defaultValue}) {
    if (value == null) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw FormatException('Expected string value');
    }
    if (value is String) {
      return value;
    }
    throw FormatException('Expected string value');
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('Expected string value');
  }

  static bool? _asNullableBool(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    throw FormatException('Expected boolean value');
  }

  static bool _asBool(dynamic value, {required bool defaultValue}) {
    if (value == null) {
      return defaultValue;
    }
    if (value is bool) {
      return value;
    }
    throw FormatException('Expected boolean value');
  }

  static int _asInt(dynamic value, {required int defaultValue}) {
    if (value == null) {
      return defaultValue;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw FormatException('Expected integer value');
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw FormatException('Expected integer value');
  }

  static List<String> _stringList(dynamic value) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw FormatException('Expected list of strings');
    }
    return value
        .map((entry) {
          if (entry is! String) {
            throw FormatException('List entries must be strings');
          }
          return entry;
        })
        .toList(growable: false);
  }

  static Map<String, Object?>? _asMap(dynamic value, {bool allowNull = false}) {
    if (value == null) {
      if (allowNull) {
        return null;
      }
      throw FormatException('Expected map value');
    }
    if (value is Map<String, Object?>) {
      return Map.unmodifiable(value);
    }
    throw FormatException('Expected map value');
  }

  static Map<String, String> _stringStringMap(dynamic value) {
    if (value == null) {
      return const {};
    }
    if (value is! Map) {
      throw FormatException('Expected map value');
    }
    final result = <String, String>{};
    value.forEach((key, dynamic entryValue) {
      if (key is! String) {
        throw FormatException('Header keys must be strings');
      }
      if (entryValue == null) {
        return;
      }
      if (entryValue is! String) {
        throw FormatException('Header values must be strings');
      }
      result[key] = entryValue;
    });
    return Map.unmodifiable(result);
  }

  static dynamic _convertYamlNode(dynamic node) {
    if (node is YamlMap) {
      return Map<String, Object?>.fromEntries(
        node.entries.map(
          (entry) =>
              MapEntry(entry.key.toString(), _convertYamlNode(entry.value)),
        ),
      );
    }
    if (node is YamlList) {
      return node.map(_convertYamlNode).toList();
    }
    return node;
  }
}
