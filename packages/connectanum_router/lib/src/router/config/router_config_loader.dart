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
    final metrics = _parseMetrics(routerNode['metrics']);
    final authenticators = _parseAuthenticators(routerNode['authenticators']);

    return RouterSettings(
      realms: realms,
      listeners: listeners,
      metrics: metrics,
      authenticators: authenticators,
    );
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
          final type = _expectString(listener['type'], 'listener.type');
          final endpoint = _expectString(
            listener['endpoint'],
            'listener.endpoint',
          );
          final path = _asNullableString(listener['path']);
          final authmethods = _stringList(listener['authmethods']);
          final tls = _asMap(listener['tls'], allowNull: true);
          final options =
              _asMap(listener['options'], allowNull: true) ?? const {};
          return ListenerSettings(
            type: type,
            endpoint: endpoint,
            path: path,
            authmethods: authmethods,
            tls: tls,
            options: options,
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
    final prometheusNode = node['prometheus'];
    PrometheusMetricsSettings? prometheus;
    if (prometheusNode != null) {
      if (prometheusNode is! Map<String, Object?>) {
        throw FormatException('metrics.prometheus must be a map');
      }
      final enabled = _asBool(prometheusNode['enabled'], defaultValue: true);
      final listen = _asString(prometheusNode['listen']);
      prometheus = PrometheusMetricsSettings(enabled: enabled, listen: listen);
    }
    return MetricsSettings(prometheus: prometheus);
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
