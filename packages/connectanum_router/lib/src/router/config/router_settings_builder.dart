import 'router_settings.dart';

/// Fluent builder for assembling [RouterSettings] programmatically.
class RouterSettingsBuilder {
  final List<RealmSettings> _realms = [];
  final List<ListenerSettings> _listeners = [];
  final List<SessionProfileSettings> _sessionProfiles = [];
  final Map<String, AuthenticatorDefinition> _authenticators = {};
  final Map<String, HttpAuthProviderDefinition> _httpAuthProviders = {};
  final List<InternalRealmSettings> _internalRealms = [];
  MetricsSettings? _metrics;
  WorkerPoolSettings _workerPool = const WorkerPoolSettings();

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

  RouterSettingsBuilder addSessionProfile(SessionProfileSettings profile) {
    _sessionProfiles.add(profile);
    return this;
  }

  RouterSettingsBuilder addSessionProfileFromBuilder(
    SessionProfileSettingsBuilder builder,
  ) {
    _sessionProfiles.add(builder.build());
    return this;
  }

  RouterSettingsBuilder addInternalRealm(InternalRealmSettings internalRealm) {
    _internalRealms.add(internalRealm);
    return this;
  }

  RouterSettingsBuilder addInternalRealmFromBuilder(
    InternalRealmSettingsBuilder builder,
  ) {
    _internalRealms.add(builder.build());
    return this;
  }

  RouterSettingsBuilder addAuthenticator(
    String name,
    AuthenticatorDefinition definition,
  ) {
    _authenticators[name] = definition;
    return this;
  }

  RouterSettingsBuilder addHttpAuthProvider(
    String name,
    HttpAuthProviderDefinition definition,
  ) {
    _httpAuthProviders[name] = definition;
    return this;
  }

  RouterSettingsBuilder metrics(MetricsSettings metrics) {
    _metrics = metrics;
    return this;
  }

  RouterSettingsBuilder setWorkerPool(WorkerPoolSettings workerPool) {
    _workerPool = workerPool;
    return this;
  }

  RouterSettings build() => RouterSettings(
    realms: List.unmodifiable(_realms),
    listeners: List.unmodifiable(_listeners),
    sessionProfiles: List.unmodifiable(_sessionProfiles),
    internalRealms: List.unmodifiable(_internalRealms),
    metrics: _metrics,
    authenticators: Map.unmodifiable(_authenticators),
    httpAuthProviders: Map.unmodifiable(_httpAuthProviders),
    workerPool: _workerPool,
  );
}

class SessionProfileSettingsBuilder {
  SessionProfileSettingsBuilder(this.name);

  final String name;
  String? realm;
  final List<String> _authMethods = [];
  String? authId;
  String? authRole;
  String? httpProvider;
  final Map<String, Object?> _roles = {};

  SessionProfileSettingsBuilder setRealm(String? value) {
    realm = value;
    return this;
  }

  SessionProfileSettingsBuilder addAuthMethod(String method) {
    if (!_authMethods.contains(method)) {
      _authMethods.add(method);
    }
    return this;
  }

  SessionProfileSettingsBuilder setAuthMethods(Iterable<String> methods) {
    _authMethods
      ..clear()
      ..addAll(methods);
    return this;
  }

  SessionProfileSettingsBuilder setAuthId(String? value) {
    authId = value;
    return this;
  }

  SessionProfileSettingsBuilder setAuthRole(String? value) {
    authRole = value;
    return this;
  }

  SessionProfileSettingsBuilder setHttpProvider(String? value) {
    httpProvider = value;
    return this;
  }

  SessionProfileSettingsBuilder setRoles(Map<String, Object?> roles) {
    _roles
      ..clear()
      ..addAll(roles);
    return this;
  }

  SessionProfileSettingsBuilder putRole(String role, Object? definition) {
    _roles[role] = definition;
    return this;
  }

  SessionProfileSettings build() => SessionProfileSettings(
    name: name,
    realm: realm,
    auth: SessionProfileAuthSettings(
      methods: List.unmodifiable(_authMethods),
      authId: authId,
      authRole: authRole,
      httpProvider: httpProvider,
    ),
    roles: Map.unmodifiable(_roles),
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
  String? sessionProfile;
  String? path;
  Map<String, Object?>? tls;
  Map<String, Object?> options = const {};
  final List<ListenerProtocol> _protocols = [];
  RawSocketListenerSettings? _rawsocket;
  WebSocketListenerSettings? _websocket;
  HttpListenerSettings? _http;

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

  ListenerSettingsBuilder setSessionProfile(String? value) {
    sessionProfile = value;
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

  ListenerSettingsBuilder addProtocol(ListenerProtocol protocol) {
    if (!_protocols.contains(protocol)) {
      _protocols.add(protocol);
    }
    return this;
  }

  ListenerSettingsBuilder addProtocolFromString(String protocol) {
    return addProtocol(listenerProtocolFromString(protocol));
  }

  ListenerSettingsBuilder setRawSocketOptions(
    RawSocketListenerSettings settings,
  ) {
    _rawsocket = settings;
    return this;
  }

  ListenerSettingsBuilder setWebSocketOptions(
    WebSocketListenerSettings settings,
  ) {
    _websocket = settings;
    return this;
  }

  ListenerSettingsBuilder setHttpOptions(HttpListenerSettings settings) {
    _http = settings;
    return this;
  }

  ListenerSettings build() => ListenerSettings(
    type: type,
    endpoint: endpoint,
    authmethods: List.unmodifiable(authmethods),
    sessionProfile: sessionProfile,
    path: path,
    tls: tls,
    options: options,
    protocols: _protocols.isNotEmpty
        ? List.unmodifiable(_protocols)
        : <ListenerProtocol>[listenerProtocolFromString(type)],
    rawsocket: _rawsocket,
    websocket: _websocket,
    http: _http,
  );
}

class InternalRealmSettingsBuilder {
  InternalRealmSettingsBuilder(this.name);

  final String name;
  String? authId;
  String? authRole;
  String? sessionProfile;
  final Map<String, Object?> _roles = {};
  final Set<String> _services = <String>{};

  InternalRealmSettingsBuilder setAuthId(String? value) {
    authId = value;
    return this;
  }

  InternalRealmSettingsBuilder setAuthRole(String? value) {
    authRole = value;
    return this;
  }

  InternalRealmSettingsBuilder setSessionProfile(String? value) {
    sessionProfile = value;
    return this;
  }

  InternalRealmSettingsBuilder setRoles(Map<String, Object?> roles) {
    _roles
      ..clear()
      ..addAll(roles);
    return this;
  }

  InternalRealmSettingsBuilder putRole(String role, Object? definition) {
    _roles[role] = definition;
    return this;
  }

  InternalRealmSettingsBuilder setServices(Iterable<String> services) {
    _services
      ..clear()
      ..addAll(services);
    return this;
  }

  InternalRealmSettingsBuilder addService(String service) {
    _services.add(service);
    return this;
  }

  InternalRealmSettings build() => InternalRealmSettings(
    name: name,
    authId: authId,
    authRole: authRole,
    sessionProfile: sessionProfile,
    roles: Map.unmodifiable(_roles),
    services: _services.isEmpty ? null : Set<String>.from(_services),
  );
}
