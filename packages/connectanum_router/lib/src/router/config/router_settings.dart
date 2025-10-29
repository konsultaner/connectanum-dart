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
    this.metrics,
    this.authenticators = const {},
    this.workerPool = const WorkerPoolSettings(),
  });

  final List<RealmSettings> realms;
  final List<ListenerSettings> listeners;
  final MetricsSettings? metrics;
  final Map<String, AuthenticatorDefinition> authenticators;
  final WorkerPoolSettings workerPool;

  RouterSettings copyWith({
    List<RealmSettings>? realms,
    List<ListenerSettings>? listeners,
    MetricsSettings? metrics,
    Map<String, AuthenticatorDefinition>? authenticators,
    WorkerPoolSettings? workerPool,
  }) {
    return RouterSettings(
      realms: realms ?? this.realms,
      listeners: listeners ?? this.listeners,
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

/// Listener/transport configuration (RawSocket, WebSocket, HTTP, ...).
@immutable
class ListenerSettings {
  const ListenerSettings({
    required this.type,
    required this.endpoint,
    this.authmethods = const [],
    this.path,
    this.tls,
    this.options = const {},
  });

  final String type;
  final String endpoint;
  final List<String> authmethods;
  final String? path;
  final Map<String, Object?>? tls;
  final Map<String, Object?> options;
}

/// Metrics configuration (Prometheus, etc.).
@immutable
class MetricsSettings {
  const MetricsSettings({this.prometheus});

  final PrometheusMetricsSettings? prometheus;
}

@immutable
class WorkerPoolSettings {
  const WorkerPoolSettings({this.minWorkers = 1})
      : assert(minWorkers >= 0, 'minWorkers must be >= 0');

  final int minWorkers;

  WorkerPoolSettings copyWith({int? minWorkers}) =>
      WorkerPoolSettings(minWorkers: minWorkers ?? this.minWorkers);
}

@immutable
class PrometheusMetricsSettings {
  const PrometheusMetricsSettings({required this.enabled, this.listen});

  final bool enabled;
  final String? listen;
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
      const DeepCollectionEquality().equals(
        e1.authenticators,
        e2.authenticators,
      ) &&
      e1.metrics == e2.metrics;

  @override
  int hash(RouterSettings e) => Object.hash(
    const ListEquality<RealmSettings>().hash(e.realms),
    const ListEquality<ListenerSettings>().hash(e.listeners),
    const DeepCollectionEquality().hash(e.authenticators),
    e.metrics,
  );

  @override
  bool isValidKey(Object? o) => o is RouterSettings;
}
