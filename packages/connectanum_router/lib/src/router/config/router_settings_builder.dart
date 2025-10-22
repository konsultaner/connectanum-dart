import 'router_settings.dart';

/// Fluent builder for assembling [RouterSettings] programmatically.
class RouterSettingsBuilder {
  final List<RealmSettings> _realms = [];
  final List<ListenerSettings> _listeners = [];
  final Map<String, AuthenticatorDefinition> _authenticators = {};
  MetricsSettings? _metrics;

  RouterSettingsBuilder addRealm(RealmSettings realm) {
    _realms.add(realm);
    return this;
  }

  RouterSettingsBuilder addRealmFromBuilder(RealmSettingsBuilder builder) {
    _realms.add(builder.build());
    return this;
  }

  RouterSettingsBuilder addListener(ListenerSettings listener) {
    _listeners.add(listener);
    return this;
  }

  RouterSettingsBuilder addListenerFromBuilder(
    ListenerSettingsBuilder builder,
  ) {
    _listeners.add(builder.build());
    return this;
  }

  RouterSettingsBuilder addAuthenticator(
    String name,
    AuthenticatorDefinition definition,
  ) {
    _authenticators[name] = definition;
    return this;
  }

  RouterSettingsBuilder metrics(MetricsSettings metrics) {
    _metrics = metrics;
    return this;
  }

  RouterSettings build() => RouterSettings(
    realms: List.unmodifiable(_realms),
    listeners: List.unmodifiable(_listeners),
    metrics: _metrics,
    authenticators: Map.unmodifiable(_authenticators),
  );
}

class RealmSettingsBuilder {
  RealmSettingsBuilder(this.name);

  final String name;
  bool autoCreate = false;
  final List<String> _methods = [];
  final Map<String, Map<String, Object?>> _methodOptions = {};
  final List<RoleSettings> _roles = [];
  RealmLimitSettings limits = const RealmLimitSettings();

  RealmSettingsBuilder addAuthMethod(
    String method, {
    Map<String, Object?> options = const {},
  }) {
    if (!_methods.contains(method)) {
      _methods.add(method);
    }
    if (options.isNotEmpty) {
      _methodOptions[method] = Map.unmodifiable(options);
    }
    return this;
  }

  RealmSettingsBuilder addRole(RoleSettings role) {
    _roles.add(role);
    return this;
  }

  RealmSettingsBuilder addRoleFromBuilder(RoleSettingsBuilder builder) {
    _roles.add(builder.build());
    return this;
  }

  RealmSettingsBuilder setLimits(RealmLimitSettings value) {
    limits = value;
    return this;
  }

  RealmSettings build() => RealmSettings(
    name: name,
    autoCreate: autoCreate,
    auth: RealmAuthSettings(
      methods: List.unmodifiable(_methods),
      methodOptions: Map.unmodifiable(_methodOptions),
    ),
    roles: List.unmodifiable(_roles),
    limits: limits,
  );
}

class RoleSettingsBuilder {
  RoleSettingsBuilder(this.name);

  final String name;
  final List<PermissionSettings> _permissions = [];

  RoleSettingsBuilder addPermission(PermissionSettings permission) {
    _permissions.add(permission);
    return this;
  }

  RoleSettingsBuilder addPermissionFromBuilder(
    PermissionSettingsBuilder builder,
  ) {
    _permissions.add(builder.build());
    return this;
  }

  RoleSettings build() =>
      RoleSettings(name: name, permissions: List.unmodifiable(_permissions));
}

class PermissionSettingsBuilder {
  PermissionSettingsBuilder(this.uri);

  final String uri;
  PermissionMatchPolicy matchPolicy = PermissionMatchPolicy.exact;
  final List<String> allow = [];
  final List<String> deny = [];
  DiscloseSettings disclose = const DiscloseSettings();

  PermissionSettingsBuilder setMatchPolicy(PermissionMatchPolicy policy) {
    matchPolicy = policy;
    return this;
  }

  PermissionSettingsBuilder allowOperations(Iterable<String> operations) {
    allow
      ..clear()
      ..addAll(operations);
    return this;
  }

  PermissionSettingsBuilder denyOperations(Iterable<String> operations) {
    deny
      ..clear()
      ..addAll(operations);
    return this;
  }

  PermissionSettingsBuilder setDisclose(DiscloseSettings settings) {
    disclose = settings;
    return this;
  }

  PermissionSettings build() => PermissionSettings(
    uri: uri,
    matchPolicy: matchPolicy,
    allow: List.unmodifiable(allow),
    deny: List.unmodifiable(deny),
    disclose: disclose,
  );
}

class ListenerSettingsBuilder {
  ListenerSettingsBuilder(this.type, this.endpoint);

  final String type;
  final String endpoint;
  final List<String> authmethods = [];
  String? path;
  Map<String, Object?>? tls;
  Map<String, Object?> options = const {};

  ListenerSettingsBuilder addAuthMethod(String method) {
    if (!authmethods.contains(method)) {
      authmethods.add(method);
    }
    return this;
  }

  ListenerSettingsBuilder setPath(String value) {
    path = value;
    return this;
  }

  ListenerSettingsBuilder setTls(Map<String, Object?> tlsOptions) {
    tls = Map.unmodifiable(tlsOptions);
    return this;
  }

  ListenerSettingsBuilder setOptions(Map<String, Object?> newOptions) {
    options = Map.unmodifiable(newOptions);
    return this;
  }

  ListenerSettings build() => ListenerSettings(
    type: type,
    endpoint: endpoint,
    authmethods: List.unmodifiable(authmethods),
    path: path,
    tls: tls,
    options: options,
  );
}
