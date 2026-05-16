import 'router_config_loader.dart';
import 'router_settings.dart';

import '../models/endpoint.dart';
import '../models/tls_mode.dart';

/// Utility helpers for serialising [RouterSettings] into sendable structures
/// that can cross isolate boundaries and reconstructing them back into strongly
/// typed objects when needed.
abstract final class RouterSettingsCodec {
  static Map<String, Object?> toMap(RouterSettings settings) {
    return <String, Object?>{
      'realms': settings.realms.map(_realmToMap).toList(),
      'listeners': settings.listeners.map(_listenerToMap).toList(),
      if (settings.sessionProfiles.isNotEmpty)
        'session_profiles': settings.sessionProfiles
            .map(_sessionProfileToMap)
            .toList(),
      if (settings.authorizationProviders.isNotEmpty)
        'authorization_providers': settings.authorizationProviders.map((
          key,
          value,
        ) {
          return MapEntry(key, _authorizationProviderToMap(value));
        }),
      if (settings.httpAuthProviders.isNotEmpty)
        'http_auth_providers': settings.httpAuthProviders.map((key, value) {
          return MapEntry(key, _httpAuthProviderToMap(value));
        }),
      if (settings.internalRealms.isNotEmpty)
        'internal_realms': settings.internalRealms
            .map(_internalRealmToMap)
            .toList(),
      if (settings.metrics != null) 'metrics': _metricsToMap(settings.metrics!),
      'worker_pool': _workerPoolToMap(settings.workerPool),
      'authenticators': settings.authenticators.map((key, value) {
        return MapEntry(key, _authenticatorToMap(value));
      }),
    };
  }

  static RouterSettings fromMap(Map<String, Object?> map) {
    return RouterConfigLoader.fromMap({'router': map});
  }

  static Map<String, Object?> _realmToMap(RealmSettings realm) {
    return <String, Object?>{
      'name': realm.name,
      'auto_create': realm.autoCreate,
      if (realm.authorizationProvider != null)
        'authorization_provider': realm.authorizationProvider,
      'auth': _realmAuthToMap(realm.auth),
      'roles': realm.roles.map(_roleToMap).toList(),
      'limits': _limitsToMap(realm.limits),
    };
  }

  static Map<String, Object?> _realmAuthToMap(RealmAuthSettings auth) {
    final map = <String, Object?>{
      'authmethods': List<String>.from(auth.methods),
    };
    auth.methodOptions.forEach((key, value) {
      map[key] = value;
    });
    return map;
  }

  static Map<String, Object?> _limitsToMap(RealmLimitSettings limits) {
    return <String, Object?>{
      'max_pending_auth': limits.maxPendingAuth,
      'auth_timeout_ms': limits.authTimeoutMs,
      'session_idle_ms': limits.sessionIdleMs,
      'max_failed_auth': limits.maxFailedAuth,
      'lockout_ms': limits.lockoutMs,
      'call_timeout_ms': limits.callTimeoutMs,
    };
  }

  static Map<String, Object?> _roleToMap(RoleSettings role) {
    return <String, Object?>{
      'name': role.name,
      'permissions': role.permissions.map(_permissionToMap).toList(),
    };
  }

  static Map<String, Object?> _permissionToMap(PermissionSettings permission) {
    return <String, Object?>{
      'uri': permission.uri,
      'match': _matchPolicyToString(permission.matchPolicy),
      'allow': List<String>.from(permission.allow),
      'deny': List<String>.from(permission.deny),
      'disclose': _discloseToMap(permission.disclose),
    };
  }

  static Map<String, Object?> _discloseToMap(DiscloseSettings disclose) {
    return <String, Object?>{
      'caller': disclose.caller,
      'publisher': disclose.publisher,
      'callee': disclose.callee,
    };
  }

  static Map<String, Object?> _listenerToMap(ListenerSettings listener) {
    final map = <String, Object?>{
      'endpoint': listener.endpoint,
      'authmethods': List<String>.from(listener.authmethods),
    };
    if (listener.sessionProfile != null) {
      map['session_profile'] = listener.sessionProfile;
    }
    if (listener.type != null) {
      map['type'] = listener.type;
    }
    if (listener.protocols.isNotEmpty) {
      map['protocols'] = listener.protocols
          .map(listenerProtocolToString)
          .toList(growable: false);
    }
    if (listener.path != null) {
      map['path'] = listener.path;
    }
    if (listener.tls != null) {
      map['tls'] = listener.tls;
    }
    if (listener.options.isNotEmpty) {
      map['options'] = listener.options;
    }
    if (listener.rawsocket != null) {
      final rawsocketMap = _rawSocketToMap(listener.rawsocket!);
      if (rawsocketMap.isNotEmpty) {
        map['rawsocket'] = rawsocketMap;
      }
    }
    if (listener.websocket != null) {
      final websocketMap = _webSocketToMap(listener.websocket!);
      if (websocketMap.isNotEmpty) {
        map['websocket'] = websocketMap;
      }
    }
    if (listener.http != null) {
      final httpMap = _httpToMap(listener.http!);
      if (httpMap.isNotEmpty) {
        map['http'] = httpMap;
      }
    }
    return map;
  }

  static Map<String, Object?> _rawSocketToMap(
    RawSocketListenerSettings settings,
  ) {
    final map = <String, Object?>{};
    if (settings.maxFrameExponent != null) {
      map['max_rawsocket_size_exponent'] = settings.maxFrameExponent;
    }
    if (settings.options.isNotEmpty) {
      map['options'] = settings.options;
    }
    return map;
  }

  static Map<String, Object?> _webSocketToMap(
    WebSocketListenerSettings settings,
  ) {
    final map = <String, Object?>{};
    if (settings.path != null) {
      map['path'] = settings.path;
    }
    if (settings.subprotocols.isNotEmpty) {
      map['subprotocols'] = List<String>.from(settings.subprotocols);
    }
    if (settings.serializerFallback != null) {
      map['serializer_fallback'] = settings.serializerFallback;
    }
    if (settings.options.isNotEmpty) {
      map['options'] = settings.options;
    }
    return map;
  }

  static Map<String, Object?> _httpToMap(HttpListenerSettings settings) {
    final map = <String, Object?>{};
    if (settings.alpn.isNotEmpty) {
      map['alpn'] = List<String>.from(settings.alpn);
    }
    if (settings.http3 != null) {
      map['http3'] = _http3ToMap(settings.http3!);
    }
    if (settings.sessionProfile != null) {
      map['session_profile'] = settings.sessionProfile;
    }
    if (settings.routes.isNotEmpty) {
      map['routes'] = settings.routes
          .map(_httpRouteToMap)
          .toList(growable: false);
    }
    if (settings.options.isNotEmpty) {
      map['options'] = settings.options;
    }
    return map;
  }

  static Map<String, Object?> _http3ToMap(Http3Settings settings) {
    final map = <String, Object?>{'enabled': settings.enabled};
    if (settings.port != null) {
      map['port'] = settings.port;
    }
    return map;
  }

  static Map<String, Object?> _httpRouteToMap(HttpRouteSettings route) {
    final map = <String, Object?>{
      'match': _httpRouteMatchToMap(route.match),
      'action': _httpRouteActionToMap(route.action),
    };
    if (route.methodActions.isNotEmpty) {
      map['method_actions'] = <String, Object?>{
        for (final entry in route.methodActions.entries)
          entry.key.trim().toUpperCase(): _httpRouteActionToMap(entry.value),
      };
    }
    return map;
  }

  static Map<String, Object?> _httpRouteMatchToMap(HttpRouteMatch match) {
    final map = <String, Object?>{};
    if (match.isCatchAll) {
      map['catch_all'] = true;
    } else if (match.path != null) {
      map['path'] = match.path;
    }
    if (match.prefix != null) {
      map['prefix'] = match.prefix;
    }
    if (match.host != null) {
      map['host'] = match.host;
    }
    if (match.methods.isNotEmpty) {
      map['methods'] = List<String>.from(match.methods);
    }
    if (match.protocols.isNotEmpty) {
      map['protocols'] = List<String>.from(match.protocols);
    }
    if (match.headers.isNotEmpty) {
      map['headers'] = Map<String, String>.from(match.headers);
    }
    if (match.extra.isNotEmpty) {
      map.addAll(match.extra);
    }
    return map;
  }

  static Map<String, Object?> _httpRouteActionToMap(HttpRouteAction action) {
    final map = <String, Object?>{
      'type': httpRouteActionTypeToString(action.type),
    };
    if (action.procedure != null) {
      map['procedure'] = action.procedure;
    }
    if (action.realm != null) {
      map['realm'] = action.realm;
    }
    if (action.sessionProfile != null) {
      map['session_profile'] = action.sessionProfile;
    }
    if (action.namespace != null) {
      map['namespace'] = action.namespace;
    }
    if (action.appendMethodSuffix != null) {
      map['append_method_suffix'] = action.appendMethodSuffix;
    }
    if (action.topic != null) {
      map['topic'] = action.topic;
    }
    if (action.serializer != null) {
      map['serializer'] = action.serializer;
    }
    if (action.contentType != null) {
      map['content_type'] = action.contentType;
    }
    if (action.directory != null) {
      map['directory'] = action.directory;
    }
    if (action.cacheControl != null) {
      map['cache_control'] = action.cacheControl;
    }
    if (action.delegate != null) {
      map['delegate'] = action.delegate;
    }
    if (action.rateLimit != null) {
      map['rate_limit'] = _httpRouteRateLimitToMap(action.rateLimit!);
    }
    if (action.concurrencyLimit != null) {
      map['concurrency_limit'] = _httpRouteConcurrencyLimitToMap(
        action.concurrencyLimit!,
      );
    }
    if (action.accessLog != null) {
      map['access_log'] = _httpRouteAccessLogToMap(action.accessLog!);
    }
    if (action.options.isNotEmpty) {
      map['options'] = action.options;
    }
    return map;
  }

  static Map<String, Object?> _httpRouteRateLimitToMap(
    HttpRouteRateLimitSettings rateLimit,
  ) {
    return <String, Object?>{
      'max_requests': rateLimit.maxRequests,
      'window_ms': rateLimit.window.inMilliseconds,
      'key': rateLimit.key,
    };
  }

  static Map<String, Object?> _httpRouteConcurrencyLimitToMap(
    HttpRouteConcurrencyLimitSettings concurrencyLimit,
  ) {
    return <String, Object?>{
      'max_concurrent': concurrencyLimit.maxConcurrent,
      'key': concurrencyLimit.key,
    };
  }

  static Map<String, Object?> _httpRouteAccessLogToMap(
    HttpRouteAccessLogSettings accessLog,
  ) {
    return <String, Object?>{
      'enabled': accessLog.enabled,
      'include_query': accessLog.includeQuery,
      'include_headers': accessLog.includeHeaders,
    };
  }

  static Map<String, Object?> _metricsToMap(MetricsSettings metrics) {
    final openMetrics = metrics.openMetrics;
    if (openMetrics == null) {
      return const <String, Object?>{};
    }
    final backpressure = metrics.backpressure;
    const defaultBackpressure = BackpressureThrottleSettings();
    final transportAlerts = metrics.transportAlerts;
    const defaultTransportAlerts = TransportAlertSettings();
    const defaultOpenMetrics = OpenMetricsSettings(enabled: true);
    return <String, Object?>{
      'open_metrics': <String, Object?>{
        'enabled': openMetrics.enabled,
        if (openMetrics.listen != null) 'listen': openMetrics.listen,
        if (openMetrics.path != '/metrics') 'path': openMetrics.path,
        if (openMetrics.authToken != null) 'auth_token': openMetrics.authToken,
        if (openMetrics.realm != 'connectanum.metrics')
          'realm': openMetrics.realm,
        if (openMetrics.collectionTimeout !=
            defaultOpenMetrics.collectionTimeout)
          'collection_timeout_ms': openMetrics.collectionTimeout.inMilliseconds,
      },
      if (backpressure != defaultBackpressure)
        'backpressure': <String, Object?>{
          'depth_threshold': backpressure.depthThreshold,
          'new_events_threshold': backpressure.newEventsThreshold,
          'cooldown_ms': backpressure.cooldown.inMilliseconds,
        },
      if (transportAlerts != defaultTransportAlerts)
        'transport_alerts': <String, Object?>{
          'goaway_delta_threshold': transportAlerts.goAwayDeltaThreshold,
          'idle_timeout_delta_threshold':
              transportAlerts.idleTimeoutDeltaThreshold,
          'body_timeout_delta_threshold':
              transportAlerts.bodyTimeoutDeltaThreshold,
          'protocol_error_delta_threshold':
              transportAlerts.protocolErrorDeltaThreshold,
          'internal_error_delta_threshold':
              transportAlerts.internalErrorDeltaThreshold,
          'cooldown_ms': transportAlerts.cooldown.inMilliseconds,
          'throttle_on_alert': transportAlerts.throttleOnAlert,
        },
    };
  }

  static Map<String, Object?> _internalRealmToMap(
    InternalRealmSettings internalRealm,
  ) {
    return <String, Object?>{
      'name': internalRealm.name,
      if (internalRealm.authId != null) 'auth_id': internalRealm.authId,
      if (internalRealm.authRole != null) 'auth_role': internalRealm.authRole,
      if (internalRealm.sessionProfile != null)
        'session_profile': internalRealm.sessionProfile,
      if (internalRealm.roles.isNotEmpty) 'roles': internalRealm.roles,
      if (internalRealm.services.isNotEmpty)
        'services': List<String>.from(internalRealm.services),
    };
  }

  static Map<String, Object?> _sessionProfileToMap(
    SessionProfileSettings profile,
  ) {
    return <String, Object?>{
      'name': profile.name,
      if (profile.realm != null) 'realm': profile.realm,
      'auth': _sessionProfileAuthToMap(profile.auth),
      if (profile.roles.isNotEmpty) 'roles': profile.roles,
    };
  }

  static Map<String, Object?> _sessionProfileAuthToMap(
    SessionProfileAuthSettings auth,
  ) {
    return <String, Object?>{
      if (auth.methods.isNotEmpty) 'methods': List<String>.from(auth.methods),
      if (auth.authId != null) 'auth_id': auth.authId,
      if (auth.authRole != null) 'auth_role': auth.authRole,
      if (auth.httpProvider != null) 'http_provider': auth.httpProvider,
    };
  }

  static Map<String, Object?> _authorizationProviderToMap(
    AuthorizationProviderDefinition definition,
  ) {
    return <String, Object?>{
      'type': definition.type,
      if (definition.options.isNotEmpty) 'options': definition.options,
    };
  }

  static Map<String, Object?> _httpAuthProviderToMap(
    HttpAuthProviderDefinition definition,
  ) {
    return <String, Object?>{
      'type': definition.type,
      if (definition.options.isNotEmpty) 'options': definition.options,
    };
  }

  static Map<String, Object?> _workerPoolToMap(WorkerPoolSettings workerPool) {
    return <String, Object?>{
      'min_workers': workerPool.minWorkers,
      'max_workers': workerPool.maxWorkers,
      'scale_up_pending_dispatches': workerPool.scaleUpPendingDispatches,
      'scale_up_consecutive_ticks': workerPool.scaleUpConsecutiveTicks,
    };
  }

  static Map<String, Object?> _authenticatorToMap(
    AuthenticatorDefinition definition,
  ) {
    return <String, Object?>{
      'type': definition.type,
      'options': definition.options,
    };
  }

  static String _matchPolicyToString(PermissionMatchPolicy policy) {
    switch (policy) {
      case PermissionMatchPolicy.exact:
        return 'exact';
      case PermissionMatchPolicy.prefix:
        return 'prefix';
      case PermissionMatchPolicy.wildcard:
        return 'wildcard';
    }
  }

  static Map<String, Object?> endpointToMap(Endpoint endpoint) {
    return <String, Object?>{
      'host': endpoint.host,
      'port': endpoint.port,
      'tls_mode': endpoint.tlsMode.wireValue,
      if (endpoint.idleTimeout != null)
        'idle_timeout_ms': endpoint.idleTimeout!.inMilliseconds,
      if (endpoint.heartbeatInterval != null)
        'heartbeat_interval_ms': endpoint.heartbeatInterval!.inMilliseconds,
      if (endpoint.heartbeatTimeout != null)
        'heartbeat_timeout_ms': endpoint.heartbeatTimeout!.inMilliseconds,
      if (endpoint.handshakeTimeout != null)
        'handshake_timeout_ms': endpoint.handshakeTimeout!.inMilliseconds,
      if (endpoint.maxHttpContentLength != null)
        'max_http_content_length': endpoint.maxHttpContentLength,
      'max_rawsocket_size_exponent': endpoint.maxRawSocketSizeExponent,
      if (endpoint.webSocketPath != null)
        'websocket_path': endpoint.webSocketPath,
      if (endpoint.sniCertificates.isNotEmpty)
        'sni_certificates': endpoint.sniCertificates
            .map((cert) => cert.toNativeJson())
            .toList(),
    };
  }
}
