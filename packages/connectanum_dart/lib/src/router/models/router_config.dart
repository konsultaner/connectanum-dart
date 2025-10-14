import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'endpoint.dart';

/// Router level configuration aggregating endpoints.
@immutable
class RouterConfig {
  static const String defaultSchema = 'connectanum.router';
  static const int defaultVersion = 1;

  factory RouterConfig({
    required List<Endpoint> endpoints,
    String schema = defaultSchema,
    int version = defaultVersion,
  }) {
    if (endpoints.isEmpty) {
      throw ArgumentError.value(
        endpoints,
        'endpoints',
        'At least one endpoint must be configured',
      );
    }
    return RouterConfig._(
      endpoints: List<Endpoint>.unmodifiable(endpoints),
      schema: schema,
      version: version,
    );
  }

  const RouterConfig._({
    required this.endpoints,
    required this.schema,
    required this.version,
  });

  /// All endpoints managed by the router.
  final List<Endpoint> endpoints;

  /// Schema identifier passed to the native runtime.
  final String schema;

  /// Schema version number.
  final int version;

  /// Serialises the configuration into a map consumable by the native runtime.
  Map<String, Object?> toNativeJson() => {
        'schema': schema,
        'version': version,
        'endpoints':
            endpoints.map((endpoint) => endpoint.toNativeJson()).toList(),
      };

  @override
  int get hashCode => Object.hash(
        schema,
        version,
        const ListEquality<Endpoint>().hash(endpoints),
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is RouterConfig &&
        other.schema == schema &&
        other.version == version &&
        const ListEquality<Endpoint>().equals(other.endpoints, endpoints);
  }

  @override
  String toString() =>
      'RouterConfig(schema: $schema, version: $version, endpoints: ${endpoints.length})';
}
