import 'dart:collection';

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
    this.sessionProfiles = const [],
    this.internalRealms = const [],
    this.metrics,
    this.authenticators = const {},
    this.authorizationProviders = const {},
    this.httpAuthProviders = const {},
    this.workerPool = const WorkerPoolSettings(),
  });

  final List<RealmSettings> realms;
  final List<ListenerSettings> listeners;
  final List<SessionProfileSettings> sessionProfiles;
  final List<InternalRealmSettings> internalRealms;
  final MetricsSettings? metrics;
  final Map<String, AuthenticatorDefinition> authenticators;
  final Map<String, AuthorizationProviderDefinition> authorizationProviders;
  final Map<String, HttpAuthProviderDefinition> httpAuthProviders;
  final WorkerPoolSettings workerPool;

  RouterSettings copyWith({
    List<RealmSettings>? realms,
    List<ListenerSettings>? listeners,
    List<SessionProfileSettings>? sessionProfiles,
    List<InternalRealmSettings>? internalRealms,
    MetricsSettings? metrics,
    Map<String, AuthenticatorDefinition>? authenticators,
    Map<String, AuthorizationProviderDefinition>? authorizationProviders,
    Map<String, HttpAuthProviderDefinition>? httpAuthProviders,
    WorkerPoolSettings? workerPool,
  }) {
    return RouterSettings(
      realms: realms ?? this.realms,
      listeners: listeners ?? this.listeners,
      sessionProfiles: sessionProfiles ?? this.sessionProfiles,
      internalRealms: internalRealms ?? this.internalRealms,
      metrics: metrics ?? this.metrics,
      authenticators: authenticators ?? this.authenticators,
      authorizationProviders:
          authorizationProviders ?? this.authorizationProviders,
      httpAuthProviders: httpAuthProviders ?? this.httpAuthProviders,
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

/// Definition of a realm authorization provider referenced by realm config.
@immutable
class AuthorizationProviderDefinition {
  const AuthorizationProviderDefinition({
    required this.type,
    this.options = const {},
  });

  final String type;
  final Map<String, Object?> options;
}

/// Definition of an HTTP bearer auth provider used by protected HTTP routes.
@immutable
class HttpAuthProviderDefinition {
  const HttpAuthProviderDefinition({
    required this.type,
    this.options = const {},
  });

  final String type;
  final Map<String, Object?> options;
}

/// Shared session/auth profile that multiple transports can reference.
@immutable
class SessionProfileSettings {
  const SessionProfileSettings({
    required this.name,
    this.realm,
    this.auth = const SessionProfileAuthSettings(),
    this.roles = const {},
  });

  final String name;
  final String? realm;
  final SessionProfileAuthSettings auth;
  final Map<String, Object?> roles;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SessionProfileSettings &&
        other.name == name &&
        other.realm == realm &&
        other.auth == auth &&
        const DeepCollectionEquality().equals(other.roles, roles);
  }

  @override
  int get hashCode => Object.hash(
    name,
    realm,
    auth,
    const DeepCollectionEquality().hash(roles),
  );
}

/// Authentication and identity defaults for a [SessionProfileSettings].
@immutable
class SessionProfileAuthSettings {
  const SessionProfileAuthSettings({
    this.methods = const [],
    this.authId,
    this.authRole,
    this.httpProvider,
  });

  final List<String> methods;
  final String? authId;
  final String? authRole;
  final String? httpProvider;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SessionProfileAuthSettings &&
        const ListEquality<String>().equals(other.methods, methods) &&
        other.authId == authId &&
        other.authRole == authRole &&
        other.httpProvider == httpProvider;
  }

  @override
  int get hashCode => Object.hash(
    const ListEquality<String>().hash(methods),
    authId,
    authRole,
    httpProvider,
  );
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
    this.authorizationProvider,
  });

  final String name;
  final RealmAuthSettings auth;
  final List<RoleSettings> roles;
  final RealmLimitSettings limits;
  final bool autoCreate;
  final String? authorizationProvider;
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
    this.sessionProfile,
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
  final String? sessionProfile;
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
        other.sessionProfile == sessionProfile &&
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
    sessionProfile,
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
  const MetricsSettings({
    this.openMetrics,
    this.backpressure = const BackpressureThrottleSettings(),
    this.transportAlerts = const TransportAlertSettings(),
  });

  final OpenMetricsSettings? openMetrics;
  final BackpressureThrottleSettings backpressure;
  final TransportAlertSettings transportAlerts;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MetricsSettings &&
        other.openMetrics == openMetrics &&
        other.backpressure == backpressure &&
        other.transportAlerts == transportAlerts;
  }

  @override
  int get hashCode => Object.hash(openMetrics, backpressure, transportAlerts);
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
    this.collectionTimeout = const Duration(seconds: 5),
  });

  final bool enabled;
  final String? listen;
  final String path;
  final String? authToken;
  final String realm;
  final Duration collectionTimeout;

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
        other.realm == realm &&
        other.collectionTimeout == collectionTimeout;
  }

  @override
  int get hashCode =>
      Object.hash(enabled, listen, path, authToken, realm, collectionTimeout);
}

/// Boss-side throttling thresholds derived from backpressure alerts.
@immutable
class BackpressureThrottleSettings {
  const BackpressureThrottleSettings({
    this.depthThreshold = 16,
    this.newEventsThreshold = 1,
    this.cooldown = const Duration(milliseconds: 250),
  }) : assert(depthThreshold >= 0),
       assert(newEventsThreshold >= 0);

  final int depthThreshold;
  final int newEventsThreshold;
  final Duration cooldown;

  BackpressureThrottleSettings copyWith({
    int? depthThreshold,
    int? newEventsThreshold,
    Duration? cooldown,
  }) {
    return BackpressureThrottleSettings(
      depthThreshold: depthThreshold ?? this.depthThreshold,
      newEventsThreshold: newEventsThreshold ?? this.newEventsThreshold,
      cooldown: cooldown ?? this.cooldown,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is BackpressureThrottleSettings &&
        other.depthThreshold == depthThreshold &&
        other.newEventsThreshold == newEventsThreshold &&
        other.cooldown == cooldown;
  }

  @override
  int get hashCode => Object.hash(depthThreshold, newEventsThreshold, cooldown);
}

/// Alert thresholds for transport lifecycle events (GOAWAY, timeouts, errors).
@immutable
class TransportAlertSettings {
  const TransportAlertSettings({
    this.goAwayDeltaThreshold = 1,
    this.idleTimeoutDeltaThreshold = 1,
    this.bodyTimeoutDeltaThreshold = 1,
    this.protocolErrorDeltaThreshold = 1,
    this.internalErrorDeltaThreshold = 1,
    this.cooldown = const Duration(milliseconds: 500),
    this.throttleOnAlert = true,
  }) : assert(goAwayDeltaThreshold >= 0),
       assert(idleTimeoutDeltaThreshold >= 0),
       assert(bodyTimeoutDeltaThreshold >= 0),
       assert(protocolErrorDeltaThreshold >= 0),
       assert(internalErrorDeltaThreshold >= 0);

  final int goAwayDeltaThreshold;
  final int idleTimeoutDeltaThreshold;
  final int bodyTimeoutDeltaThreshold;
  final int protocolErrorDeltaThreshold;
  final int internalErrorDeltaThreshold;
  final Duration cooldown;
  final bool throttleOnAlert;

  TransportAlertSettings copyWith({
    int? goAwayDeltaThreshold,
    int? idleTimeoutDeltaThreshold,
    int? bodyTimeoutDeltaThreshold,
    int? protocolErrorDeltaThreshold,
    int? internalErrorDeltaThreshold,
    Duration? cooldown,
    bool? throttleOnAlert,
  }) {
    return TransportAlertSettings(
      goAwayDeltaThreshold: goAwayDeltaThreshold ?? this.goAwayDeltaThreshold,
      idleTimeoutDeltaThreshold:
          idleTimeoutDeltaThreshold ?? this.idleTimeoutDeltaThreshold,
      bodyTimeoutDeltaThreshold:
          bodyTimeoutDeltaThreshold ?? this.bodyTimeoutDeltaThreshold,
      protocolErrorDeltaThreshold:
          protocolErrorDeltaThreshold ?? this.protocolErrorDeltaThreshold,
      internalErrorDeltaThreshold:
          internalErrorDeltaThreshold ?? this.internalErrorDeltaThreshold,
      cooldown: cooldown ?? this.cooldown,
      throttleOnAlert: throttleOnAlert ?? this.throttleOnAlert,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TransportAlertSettings &&
        other.goAwayDeltaThreshold == goAwayDeltaThreshold &&
        other.idleTimeoutDeltaThreshold == idleTimeoutDeltaThreshold &&
        other.bodyTimeoutDeltaThreshold == bodyTimeoutDeltaThreshold &&
        other.protocolErrorDeltaThreshold == protocolErrorDeltaThreshold &&
        other.internalErrorDeltaThreshold == internalErrorDeltaThreshold &&
        other.cooldown == cooldown &&
        other.throttleOnAlert == throttleOnAlert;
  }

  @override
  int get hashCode => Object.hash(
    goAwayDeltaThreshold,
    idleTimeoutDeltaThreshold,
    bodyTimeoutDeltaThreshold,
    protocolErrorDeltaThreshold,
    internalErrorDeltaThreshold,
    cooldown,
    throttleOnAlert,
  );
}

@immutable
class InternalRealmSettings {
  InternalRealmSettings({
    required this.name,
    this.authId,
    this.authRole,
    this.sessionProfile,
    Map<String, Object?> roles = const {},
    Set<String>? services,
  }) : roles = Map.unmodifiable(roles),
       services = services == null
           ? const <String>{}
           : Set.unmodifiable(services);

  final String name;
  final String? authId;
  final String? authRole;
  final String? sessionProfile;
  final Map<String, Object?> roles;
  final Set<String> services;

  InternalRealmSettings copyWith({
    String? name,
    String? authId,
    String? authRole,
    String? sessionProfile,
    Map<String, Object?>? roles,
    Set<String>? services,
  }) => InternalRealmSettings(
    name: name ?? this.name,
    authId: authId ?? this.authId,
    authRole: authRole ?? this.authRole,
    sessionProfile: sessionProfile ?? this.sessionProfile,
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
        other.sessionProfile == sessionProfile &&
        const DeepCollectionEquality().equals(other.roles, roles) &&
        const SetEquality<String>().equals(other.services, services);
  }

  @override
  int get hashCode => Object.hash(
    name,
    authId,
    authRole,
    sessionProfile,
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
    this.sessionProfile,
    this.routes = const [],
    this.options = const {},
  });

  final List<String> alpn;
  final Http3Settings? http3;
  final String? sessionProfile;
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
        other.sessionProfile == sessionProfile &&
        const ListEquality<HttpRouteSettings>().equals(other.routes, routes) &&
        const DeepCollectionEquality().equals(other.options, options);
  }

  @override
  int get hashCode => Object.hash(
    const ListEquality<String>().hash(alpn),
    http3,
    sessionProfile,
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
  auth,
  reservedRealm,
  namespace,
  mcp,
  file,
  sessionProxy,
  publish,
  handler,
}

HttpRouteActionType httpRouteActionTypeFromString(String value) {
  switch (value) {
    case 'rpc':
      return HttpRouteActionType.rpc;
    case 'internal_call':
      return HttpRouteActionType.internalCall;
    case 'auth':
      return HttpRouteActionType.auth;
    case 'reserved_realm':
      return HttpRouteActionType.reservedRealm;
    case 'namespace':
      return HttpRouteActionType.namespace;
    case 'mcp':
      return HttpRouteActionType.mcp;
    case 'file':
      return HttpRouteActionType.file;
    case 'session_proxy':
    case 'sessionProxy':
    case 'session-proxy':
      return HttpRouteActionType.sessionProxy;
    case 'publish':
      return HttpRouteActionType.publish;
    case 'handler':
    case 'custom_handler':
    case 'customHandler':
      return HttpRouteActionType.handler;
    default:
      throw FormatException('Unknown HTTP route action type "$value"');
  }
}

String httpRouteActionTypeToString(HttpRouteActionType type) => switch (type) {
  HttpRouteActionType.rpc => 'rpc',
  HttpRouteActionType.internalCall => 'internal_call',
  HttpRouteActionType.auth => 'auth',
  HttpRouteActionType.reservedRealm => 'reserved_realm',
  HttpRouteActionType.namespace => 'namespace',
  HttpRouteActionType.mcp => 'mcp',
  HttpRouteActionType.file => 'file',
  HttpRouteActionType.sessionProxy => 'session_proxy',
  HttpRouteActionType.publish => 'publish',
  HttpRouteActionType.handler => 'handler',
};

@immutable
class HttpRouteMatch {
  const HttpRouteMatch({
    this.path,
    this.prefix,
    this.host,
    this.methods = const [],
    this.protocols = const [],
    this.headers = const {},
    this.extra = const {},
  });

  final String? path;
  final String? prefix;
  final String? host;
  final List<String> methods;
  final List<String> protocols;
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
        const ListEquality<String>().equals(other.protocols, protocols) &&
        const MapEquality<String, String>().equals(other.headers, headers) &&
        const DeepCollectionEquality().equals(other.extra, extra);
  }

  @override
  int get hashCode => Object.hash(
    path,
    prefix,
    host,
    const ListEquality<String>().hash(methods),
    const ListEquality<String>().hash(protocols),
    const MapEquality<String, String>().hash(headers),
    const DeepCollectionEquality().hash(extra),
  );
}

@immutable
class HttpRouteRateLimitSettings {
  const HttpRouteRateLimitSettings({
    this.maxRequests = 60,
    this.windowMs = 60000,
    this.key = 'global',
  }) : assert(maxRequests > 0),
       assert(windowMs > 0);

  final int maxRequests;
  final int windowMs;
  final String key;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HttpRouteRateLimitSettings &&
        other.maxRequests == maxRequests &&
        other.windowMs == windowMs &&
        other.key == key;
  }

  @override
  int get hashCode => Object.hash(maxRequests, windowMs, key);
}

@immutable
class HttpRouteAction {
  const HttpRouteAction({
    required this.type,
    this.procedure,
    this.realm,
    this.sessionProfile,
    this.namespace,
    this.appendMethodSuffix,
    this.topic,
    this.serializer,
    this.contentType,
    this.directory,
    this.cacheControl,
    this.delegate,
    this.rateLimit,
    this.options = const {},
  });

  final HttpRouteActionType type;
  final String? procedure;
  final String? realm;
  final String? sessionProfile;
  final String? namespace;
  final bool? appendMethodSuffix;
  final String? topic;
  final String? serializer;
  final String? contentType;
  final String? directory;
  final String? cacheControl;
  final String? delegate;
  final HttpRouteRateLimitSettings? rateLimit;
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
        other.sessionProfile == sessionProfile &&
        other.namespace == namespace &&
        other.appendMethodSuffix == appendMethodSuffix &&
        other.topic == topic &&
        other.serializer == serializer &&
        other.contentType == contentType &&
        other.directory == directory &&
        other.cacheControl == cacheControl &&
        other.delegate == delegate &&
        other.rateLimit == rateLimit &&
        const DeepCollectionEquality().equals(other.options, options);
  }

  @override
  int get hashCode => Object.hash(
    type,
    procedure,
    realm,
    sessionProfile,
    namespace,
    appendMethodSuffix,
    topic,
    serializer,
    contentType,
    directory,
    cacheControl,
    delegate,
    rateLimit,
    const DeepCollectionEquality().hash(options),
  );
}

@immutable
class HttpRouteSettings {
  const HttpRouteSettings({
    required this.match,
    required this.action,
    this.methodActions = const <String, HttpRouteAction>{},
  });

  final HttpRouteMatch match;
  final HttpRouteAction action;
  final Map<String, HttpRouteAction> methodActions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HttpRouteSettings &&
        other.match == match &&
        other.action == action &&
        const MapEquality<String, HttpRouteAction>().equals(
          other.methodActions,
          methodActions,
        );
  }

  @override
  int get hashCode => Object.hash(
    match,
    action,
    const MapEquality<String, HttpRouteAction>().hash(methodActions),
  );
}

const _openMetricsHttpMethods = ['GET', 'HEAD'];

/// Adds router-native HTTP routes for `metrics.open_metrics.listen`.
///
/// The generated routes are ordinary HTTP bridge routes backed by the internal
/// metrics realm, so `/healthz`, `/health`, and the configured metrics path are
/// served by router sessions instead of a separate sidecar HTTP server.
extension RouterSettingsOpenMetricsHttp on RouterSettings {
  RouterSettings withOpenMetricsHttpRoutes() {
    final openMetrics = metrics?.openMetrics;
    final listen = openMetrics?.listen?.trim();
    if (openMetrics == null ||
        !openMetrics.enabled ||
        listen == null ||
        listen.isEmpty) {
      return this;
    }

    final routes = _openMetricsHttpRoutes(openMetrics);
    final updatedListeners = <ListenerSettings>[];
    var foundMetricsListener = false;
    var changed = false;

    for (final listener in listeners) {
      if (listener.endpoint.trim() != listen) {
        updatedListeners.add(listener);
        continue;
      }
      foundMetricsListener = true;
      final updated = _withOpenMetricsRoutes(listener, routes);
      updatedListeners.add(updated);
      changed = changed || updated != listener;
    }

    if (!foundMetricsListener) {
      updatedListeners.add(
        ListenerSettings(
          type: 'http',
          endpoint: listen,
          options: const {'connectanum_open_metrics_listener': true},
          protocols: const [ListenerProtocol.http, ListenerProtocol.http2],
          http: HttpListenerSettings(routes: routes),
        ),
      );
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(listeners: updatedListeners);
  }
}

List<HttpRouteSettings> _openMetricsHttpRoutes(
  OpenMetricsSettings openMetrics,
) {
  final realm = openMetrics.realm;
  return [
    _openMetricsHttpRoute(
      path: '/healthz',
      realm: realm,
      procedure: 'connectanum.metrics.healthz',
    ),
    _openMetricsHttpRoute(
      path: '/health',
      realm: realm,
      procedure: 'connectanum.metrics.healthz',
    ),
    _openMetricsHttpRoute(
      path: _normalizeOpenMetricsHttpPath(openMetrics.path),
      realm: realm,
      procedure: 'connectanum.metrics.openmetrics',
    ),
  ];
}

HttpRouteSettings _openMetricsHttpRoute({
  required String path,
  required String realm,
  required String procedure,
}) {
  return HttpRouteSettings(
    match: HttpRouteMatch(path: path, methods: _openMetricsHttpMethods),
    action: HttpRouteAction(
      type: HttpRouteActionType.internalCall,
      realm: realm,
      procedure: procedure,
    ),
  );
}

ListenerSettings _withOpenMetricsRoutes(
  ListenerSettings listener,
  List<HttpRouteSettings> routes,
) {
  final existingHttp = listener.http ?? const HttpListenerSettings();
  final missingRoutes = routes
      .where((route) => !_hasExactPathRoute(existingHttp, route.match.path))
      .toList(growable: false);
  final protocols = _protocolsWithHttp(listener);
  if (missingRoutes.isEmpty &&
      const ListEquality<ListenerProtocol>().equals(
        protocols,
        listener.protocols,
      ) &&
      listener.http != null) {
    return listener;
  }

  return ListenerSettings(
    type: listener.type,
    endpoint: listener.endpoint,
    authmethods: listener.authmethods,
    sessionProfile: listener.sessionProfile,
    path: listener.path,
    tls: listener.tls,
    options: listener.options,
    protocols: protocols,
    rawsocket: listener.rawsocket,
    websocket: listener.websocket,
    http: HttpListenerSettings(
      alpn: existingHttp.alpn,
      http3: existingHttp.http3,
      sessionProfile: existingHttp.sessionProfile,
      routes: [...missingRoutes, ...existingHttp.routes],
      options: existingHttp.options,
    ),
  );
}

List<ListenerProtocol> _protocolsWithHttp(ListenerSettings listener) {
  final protocols = <ListenerProtocol>[];
  if (listener.protocols.isEmpty) {
    final type = listener.type?.trim();
    if (type != null && type.isNotEmpty) {
      try {
        protocols.add(listenerProtocolFromString(type));
      } on FormatException {
        // Keep validation in the normal config path; this helper only enriches
        // metrics routes when the listener type is known.
      }
    }
  }
  protocols.addAll(listener.protocols);
  if (!protocols.contains(ListenerProtocol.http)) {
    protocols.add(ListenerProtocol.http);
  }
  if (!protocols.contains(ListenerProtocol.http2)) {
    protocols.add(ListenerProtocol.http2);
  }
  return LinkedHashSet<ListenerProtocol>.from(protocols).toList();
}

bool _hasExactPathRoute(HttpListenerSettings http, String? path) {
  if (path == null || path.isEmpty) {
    return false;
  }
  return http.routes.any((route) => route.match.path == path);
}

String _normalizeOpenMetricsHttpPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '/';
  }
  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
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
      const ListEquality<SessionProfileSettings>().equals(
        e1.sessionProfiles,
        e2.sessionProfiles,
      ) &&
      const ListEquality<InternalRealmSettings>().equals(
        e1.internalRealms,
        e2.internalRealms,
      ) &&
      const DeepCollectionEquality().equals(
        e1.authenticators,
        e2.authenticators,
      ) &&
      const DeepCollectionEquality().equals(
        e1.authorizationProviders,
        e2.authorizationProviders,
      ) &&
      const DeepCollectionEquality().equals(
        e1.httpAuthProviders,
        e2.httpAuthProviders,
      ) &&
      e1.metrics == e2.metrics &&
      e1.workerPool == e2.workerPool;

  @override
  int hash(RouterSettings e) => Object.hash(
    const ListEquality<RealmSettings>().hash(e.realms),
    const ListEquality<ListenerSettings>().hash(e.listeners),
    const ListEquality<SessionProfileSettings>().hash(e.sessionProfiles),
    const ListEquality<InternalRealmSettings>().hash(e.internalRealms),
    const DeepCollectionEquality().hash(e.authenticators),
    const DeepCollectionEquality().hash(e.authorizationProviders),
    const DeepCollectionEquality().hash(e.httpAuthProviders),
    e.metrics,
    e.workerPool,
  );

  @override
  bool isValidKey(Object? o) => o is RouterSettings;
}
