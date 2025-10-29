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
      'type': listener.type,
      'endpoint': listener.endpoint,
      'authmethods': List<String>.from(listener.authmethods),
      'options': listener.options,
    };
    if (listener.path != null) {
      map['path'] = listener.path;
    }
    if (listener.tls != null) {
      map['tls'] = listener.tls;
    }
    return map;
  }

  static Map<String, Object?> _metricsToMap(MetricsSettings metrics) {
    if (metrics.prometheus == null) {
      return const <String, Object?>{};
    }
    final prometheus = metrics.prometheus!;
    return <String, Object?>{
      'prometheus': <String, Object?>{
        'enabled': prometheus.enabled,
        if (prometheus.listen != null) 'listen': prometheus.listen,
      },
    };
  }

  static Map<String, Object?> _workerPoolToMap(WorkerPoolSettings workerPool) {
    return <String, Object?>{'min_workers': workerPool.minWorkers};
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
