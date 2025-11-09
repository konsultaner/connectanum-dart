import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../state/subscription.dart';

/// Supported matching policies for role permissions.
enum PermissionMatchPolicy { exact, prefix, wildcard }

PermissionMatchPolicy permissionMatchPolicyFromString(String value) {
  switch (value) {
    case 'exact':
      return PermissionMatchPolicy.exact;
    case 'prefix':
      return PermissionMatchPolicy.prefix;
    case 'wildcard':
      return PermissionMatchPolicy.wildcard;
    default:
      throw FormatException('Unknown match policy "$value"');
  }
}

/// Top-level router settings parsed from configuration.
@immutable
class RouterSettings {
  const RouterSettings({
    required this.realms,
    required this.listeners,
    this.internalRealms = const [],
    this.metrics,
    this.authenticators = const {},
    this.workerPool = const WorkerPoolSettings(),
  });

  final List<RealmSettings> realms;
  final List<ListenerSettings> listeners;
  final List<InternalRealmSettings> internalRealms;
  final MetricsSettings? metrics;
  final Map<String, AuthenticatorDefinition> authenticators;
  final WorkerPoolSettings workerPool;

  RouterSettings copyWith({
    List<RealmSettings>? realms,
    List<ListenerSettings>? listeners,
    List<InternalRealmSettings>? internalRealms,
    MetricsSettings? metrics,
    Map<String, AuthenticatorDefinition>? authenticators,
    WorkerPoolSettings? workerPool,
  }) {
    return RouterSettings(
      realms: realms ?? this.realms,
      listeners: listeners ?? this.listeners,
      internalRealms: internalRealms ?? this.internalRealms,
      metrics: metrics ?? this.metrics,
      authenticators: authenticators ?? this.authenticators,
      workerPool: workerPool ?? this.workerPool,
    );
  }
}

/// Definition of an authenticator that can be referenced by realms/listeners.
@immutable
class AuthenticatorDefinition {
  const AuthenticatorDefinition({required this.type, this.options = const {}});

  final String type;
  final Map<String, Object?> options;
}

/// Configuration for an individual realm.
@immutable
class RealmSettings {
  const RealmSettings({
    required this.name,
    required this.auth,
    required this.roles,
    required this.limits,
    this.autoCreate = false,
  });

  final String name;
  final RealmAuthSettings auth;
  final List<RoleSettings> roles;
  final RealmLimitSettings limits;
  final bool autoCreate;
}

/// Pluggable auth configuration for a realm.
@immutable
class RealmAuthSettings {
  const RealmAuthSettings({
    required this.methods,
    this.methodOptions = const {},
  });

  final List<String> methods;
  final Map<String, Map<String, Object?>> methodOptions;

  Map<String, Object?>? optionsFor(String method) => methodOptions[method];
}

/// Role definition containing permissions for publish/subscribe/RPC actions.
@immutable
class RoleSettings {
  const RoleSettings({required this.name, required this.permissions});

  final String name;
  final List<PermissionSettings> permissions;
}

/// Permission entry describing which operations are allowed or denied.
@immutable
class PermissionSettings {
  const PermissionSettings({
    required this.uri,
    this.matchPolicy = PermissionMatchPolicy.exact,
    this.allow = const [],
    this.deny = const [],
    this.disclose = const DiscloseSettings(),
  });

  final String uri;
  final PermissionMatchPolicy matchPolicy;
  final List<String> allow;
  final List<String> deny;
  final DiscloseSettings disclose;

  TopicMatchPolicy toTopicMatchPolicy() {
    switch (matchPolicy) {
      case PermissionMatchPolicy.exact:
        return TopicMatchPolicy.exact;
      case PermissionMatchPolicy.prefix:
        return TopicMatchPolicy.prefix;
      case PermissionMatchPolicy.wildcard:
        return TopicMatchPolicy.wildcard;
    }
  }
}

/// Disclose flags for permissions (caller/publisher callee IDs).
@immutable
class DiscloseSettings {
  const DiscloseSettings({
    this.caller = false,
    this.publisher = false,
    this.callee = false,
  });

  final bool caller;
  final bool publisher;
  final bool callee;
}

/// Limits and timeouts applied at the realm level.
@immutable
class RealmLimitSettings {
  const RealmLimitSettings({
    this.maxPendingAuth = 32,
    this.authTimeoutMs = 10000,
    this.sessionIdleMs = 600000,
    this.maxFailedAuth = 5,
    this.lockoutMs = 900000,
    this.callTimeoutMs = 30000,
  });

  final int maxPendingAuth;
  final int authTimeoutMs;
  final int sessionIdleMs;
  final int maxFailedAuth;
  final int lockoutMs;
  final int callTimeoutMs;
}

/// Listener protocols that can be negotiated per endpoint.
enum ListenerProtocol { rawsocket, websocket, http, http2, http3 }

extension ListenerProtocolX on ListenerProtocol {
  bool get isHttp =>
      this == ListenerProtocol.http ||
      this == ListenerProtocol.http2 ||
      this == ListenerProtocol.http3;
}

ListenerProtocol listenerProtocolFromString(String value) {
  switch (value) {
    case 'rawsocket':
      return ListenerProtocol.rawsocket;
    case 'websocket':
      return ListenerProtocol.websocket;
    case 'http':
      return ListenerProtocol.http;
    case 'http2':
      return ListenerProtocol.http2;
    case 'http3':
      return ListenerProtocol.http3;
    default:
      throw FormatException('Unknown listener protocol "$value"');
  }
}

String listenerProtocolToString(ListenerProtocol protocol) =>
    switch (protocol) {
      ListenerProtocol.rawsocket => 'rawsocket',
      ListenerProtocol.websocket => 'websocket',
      ListenerProtocol.http => 'http',
      ListenerProtocol.http2 => 'http2',
      ListenerProtocol.http3 => 'http3',
    };

/// Listener/transport configuration (RawSocket, WebSocket, HTTP, ...).
@immutable
class ListenerSettings {
  const ListenerSettings({
    required this.endpoint,
    this.type,
    this.authmethods = const [],
    this.path,
    this.tls,
    this.options = const {},
    this.protocols = const [],
    this.rawsocket,
    this.websocket,
    this.http,
  });

  final String? type;
  final String endpoint;
  final List<String> authmethods;
  final String? path;
  final Map<String, Object?>? tls;
  final Map<String, Object?> options;
  final List<ListenerProtocol> protocols;
  final RawSocketListenerSettings? rawsocket;
  final WebSocketListenerSettings? websocket;
  final HttpListenerSettings? http;

  ListenerProtocol? get primaryProtocol =>
      protocols.isNotEmpty ? protocols.first : null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ListenerSettings &&
        other.type == type &&
        other.endpoint == endpoint &&
        const ListEquality<String>().equals(other.authmethods, authmethods) &&
        other.path == path &&
        const DeepCollectionEquality().equals(other.tls, tls) &&
        const DeepCollectionEquality().equals(other.options, options) &&
        const ListEquality<ListenerProtocol>().equals(
          other.protocols,
          protocols,
        ) &&
        other.rawsocket == rawsocket &&
        other.websocket == websocket &&
        other.http == http;
  }

  @override
  int get hashCode => Object.hash(
    type,
    endpoint,
    const ListEquality<String>().hash(authmethods),
    path,
    const DeepCollectionEquality().hash(tls),
    const DeepCollectionEquality().hash(options),
    const ListEquality<ListenerProtocol>().hash(protocols),
    rawsocket,
    websocket,
    http,
  );
}

/// Metrics configuration (OpenMetrics-compatible exporter, etc.).
@immutable
class MetricsSettings {
  const MetricsSettings({this.openMetrics});

  final OpenMetricsSettings? openMetrics;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MetricsSettings && other.openMetrics == openMetrics;
  }

  @override
  int get hashCode => openMetrics?.hashCode ?? 0;
}

@immutable
class WorkerPoolSettings {
  const WorkerPoolSettings({this.minWorkers = 1})
    : assert(minWorkers >= 0, 'minWorkers must be >= 0');

  final int minWorkers;

  WorkerPoolSettings copyWith({int? minWorkers}) =>
      WorkerPoolSettings(minWorkers: minWorkers ?? this.minWorkers);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is WorkerPoolSettings && other.minWorkers == minWorkers;
  }

  @override
  int get hashCode => minWorkers.hashCode;
}

@immutable
class OpenMetricsSettings {
  const OpenMetricsSettings({
    required this.enabled,
    this.listen,
    this.path = '/metrics',
    this.authToken,
    this.realm = 'connectanum.metrics',
  });

  final bool enabled;
  final String? listen;
  final String path;
  final String? authToken;
  final String realm;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is OpenMetricsSettings &&
        other.enabled == enabled &&
        other.listen == listen &&
        other.path == path &&
        other.authToken == authToken &&
        other.realm == realm;
  }

  @override
  int get hashCode => Object.hash(enabled, listen, path, authToken, realm);
}

@immutable
class InternalRealmSettings {
  InternalRealmSettings({
    required this.name,
    this.authId,
    this.authRole,
    Map<String, Object?> roles = const {},
    Set<String>? services,
  }) : roles = Map.unmodifiable(roles),
       services = services == null
           ? const <String>{}
           : Set.unmodifiable(services);

  final String name;
  final String? authId;
  final String? authRole;
  final Map<String, Object?> roles;
  final Set<String> services;

  InternalRealmSettings copyWith({
    String? name,
    String? authId,
    String? authRole,
    Map<String, Object?>? roles,
    Set<String>? services,
  }) => InternalRealmSettings(
    name: name ?? this.name,
    authId: authId ?? this.authId,
    authRole: authRole ?? this.authRole,
    roles: roles ?? this.roles,
    services: services ?? this.services,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is InternalRealmSettings &&
        other.name == name &&
        other.authId == authId &&
        other.authRole == authRole &&
        const DeepCollectionEquality().equals(other.roles, roles) &&
        const SetEquality<String>().equals(other.services, services);
  }

  @override
  int get hashCode => Object.hash(
    name,
    authId,
    authRole,
    const DeepCollectionEquality().hash(roles),
    const SetEquality<String>().hash(services),
  );
}

@immutable
class RawSocketListenerSettings {
  const RawSocketListenerSettings({
    this.maxFrameExponent,
    this.options = const {},
  });

  final int? maxFrameExponent;
  final Map<String, Object?> options;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is RawSocketListenerSettings &&
        other.maxFrameExponent == maxFrameExponent &&
        const DeepCollectionEquality().equals(other.options, options);
  }

  @override
  int get hashCode => Object.hash(
    maxFrameExponent,
    const DeepCollectionEquality().hash(options),
  );
}

@immutable
class WebSocketListenerSettings {
  const WebSocketListenerSettings({
    this.path,
    this.subprotocols = const [],
    this.serializerFallback,
    this.options = const {},
  });

  final String? path;
  final List<String> subprotocols;
  final String? serializerFallback;
  final Map<String, Object?> options;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is WebSocketListenerSettings &&
        other.path == path &&
        const ListEquality<String>().equals(other.subprotocols, subprotocols) &&
        other.serializerFallback == serializerFallback &&
        const DeepCollectionEquality().equals(other.options, options);
  }

  @override
  int get hashCode => Object.hash(
    path,
    const ListEquality<String>().hash(subprotocols),
    serializerFallback,
    const DeepCollectionEquality().hash(options),
  );
}

@immutable
class HttpListenerSettings {
  const HttpListenerSettings({
    this.alpn = const [],
    this.http3,
    this.routes = const [],
    this.options = const {},
  });

  final List<String> alpn;
  final Http3Settings? http3;
  final List<HttpRouteSettings> routes;
  final Map<String, Object?> options;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HttpListenerSettings &&
        const ListEquality<String>().equals(other.alpn, alpn) &&
        other.http3 == http3 &&
        const ListEquality<HttpRouteSettings>().equals(other.routes, routes) &&
        const DeepCollectionEquality().equals(other.options, options);
  }

  @override
  int get hashCode => Object.hash(
    const ListEquality<String>().hash(alpn),
    http3,
    const ListEquality<HttpRouteSettings>().hash(routes),
    const DeepCollectionEquality().hash(options),
  );
}

@immutable
class Http3Settings {
  const Http3Settings({this.enabled = false, this.port});

  final bool enabled;
  final int? port;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Http3Settings &&
        other.enabled == enabled &&
        other.port == port;
  }

  @override
  int get hashCode => Object.hash(enabled, port);
}

enum HttpRouteActionType {
  rpc,
  internalCall,
  reservedRealm,
  namespace,
  file,
  sessionProxy,
  publish,
}

HttpRouteActionType httpRouteActionTypeFromString(String value) {
  switch (value) {
    case 'rpc':
      return HttpRouteActionType.rpc;
    case 'internal_call':
      return HttpRouteActionType.internalCall;
    case 'reserved_realm':
      return HttpRouteActionType.reservedRealm;
    case 'namespace':
      return HttpRouteActionType.namespace;
    case 'file':
      return HttpRouteActionType.file;
    case 'session_proxy':
      return HttpRouteActionType.sessionProxy;
    case 'publish':
      return HttpRouteActionType.publish;
    default:
      throw FormatException('Unknown HTTP route action type "$value"');
  }
}

String httpRouteActionTypeToString(HttpRouteActionType type) => switch (type) {
  HttpRouteActionType.rpc => 'rpc',
  HttpRouteActionType.internalCall => 'internal_call',
  HttpRouteActionType.reservedRealm => 'reserved_realm',
  HttpRouteActionType.namespace => 'namespace',
  HttpRouteActionType.file => 'file',
  HttpRouteActionType.sessionProxy => 'session_proxy',
  HttpRouteActionType.publish => 'publish',
};

@immutable
class HttpRouteMatch {
  const HttpRouteMatch({
    this.path,
    this.prefix,
    this.host,
    this.methods = const [],
    this.headers = const {},
    this.extra = const {},
  });

  final String? path;
  final String? prefix;
  final String? host;
  final List<String> methods;
  final Map<String, String> headers;
  final Map<String, Object?> extra;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HttpRouteMatch &&
        other.path == path &&
        other.prefix == prefix &&
        other.host == host &&
        const ListEquality<String>().equals(other.methods, methods) &&
        const MapEquality<String, String>().equals(other.headers, headers) &&
        const DeepCollectionEquality().equals(other.extra, extra);
  }

  @override
  int get hashCode => Object.hash(
    path,
    prefix,
    host,
    const ListEquality<String>().hash(methods),
    const MapEquality<String, String>().hash(headers),
    const DeepCollectionEquality().hash(extra),
  );
}

@immutable
class HttpRouteAction {
  const HttpRouteAction({
    required this.type,
    this.procedure,
    this.realm,
    this.namespace,
    this.appendMethodSuffix,
    this.topic,
    this.serializer,
    this.contentType,
    this.directory,
    this.cacheControl,
    this.delegate,
    this.options = const {},
  });

  final HttpRouteActionType type;
  final String? procedure;
  final String? realm;
  final String? namespace;
  final bool? appendMethodSuffix;
  final String? topic;
  final String? serializer;
  final String? contentType;
  final String? directory;
  final String? cacheControl;
  final String? delegate;
  final Map<String, Object?> options;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HttpRouteAction &&
        other.type == type &&
        other.procedure == procedure &&
        other.realm == realm &&
        other.namespace == namespace &&
        other.appendMethodSuffix == appendMethodSuffix &&
        other.topic == topic &&
        other.serializer == serializer &&
        other.contentType == contentType &&
        other.directory == directory &&
        other.cacheControl == cacheControl &&
        other.delegate == delegate &&
        const DeepCollectionEquality().equals(other.options, options);
  }

  @override
  int get hashCode => Object.hash(
    type,
    procedure,
    realm,
    namespace,
    appendMethodSuffix,
    topic,
    serializer,
    contentType,
    directory,
    cacheControl,
    delegate,
    const DeepCollectionEquality().hash(options),
  );
}

@immutable
class HttpRouteSettings {
  const HttpRouteSettings({required this.match, required this.action});

  final HttpRouteMatch match;
  final HttpRouteAction action;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HttpRouteSettings &&
        other.match == match &&
        other.action == action;
  }

  @override
  int get hashCode => Object.hash(match, action);
}

/// Equality helpers
class RouterSettingsEquality implements Equality<RouterSettings> {
  const RouterSettingsEquality();

  @override
  bool equals(RouterSettings e1, RouterSettings e2) =>
      const ListEquality<RealmSettings>().equals(e1.realms, e2.realms) &&
      const ListEquality<ListenerSettings>().equals(
        e1.listeners,
        e2.listeners,
      ) &&
      const ListEquality<InternalRealmSettings>().equals(
        e1.internalRealms,
        e2.internalRealms,
      ) &&
      const DeepCollectionEquality().equals(
        e1.authenticators,
        e2.authenticators,
      ) &&
      e1.metrics == e2.metrics &&
      e1.workerPool == e2.workerPool;

  @override
  int hash(RouterSettings e) => Object.hash(
    const ListEquality<RealmSettings>().hash(e.realms),
    const ListEquality<ListenerSettings>().hash(e.listeners),
    const ListEquality<InternalRealmSettings>().hash(e.internalRealms),
    const DeepCollectionEquality().hash(e.authenticators),
    e.metrics,
    e.workerPool,
  );

  @override
  bool isValidKey(Object? o) => o is RouterSettings;
}
