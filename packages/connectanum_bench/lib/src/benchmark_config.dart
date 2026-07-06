import 'dart:convert';

import 'package:yaml/yaml.dart';

class BenchmarkConfig {
  BenchmarkConfig({required this.scenarios});

  final List<BenchmarkScenario> scenarios;

  factory BenchmarkConfig.fromYaml(String source) {
    final dynamic root = loadYaml(source);
    final materialised = _convertYaml(root);
    if (materialised is! Map<String, Object?>) {
      throw FormatException('Top-level benchmark file must be a mapping');
    }
    final scenariosNode = materialised['benchmarks'];
    if (scenariosNode is! List) {
      throw FormatException('"benchmarks" must be a list');
    }
    final scenarios = scenariosNode
        .map((entry) {
          if (entry is! Map<String, Object?>) {
            throw FormatException('Each benchmark entry must be a map');
          }
          return BenchmarkScenario.fromMap(entry);
        })
        .toList(growable: false);
    if (scenarios.isEmpty) {
      throw FormatException('Benchmark configuration must contain scenarios');
    }
    return BenchmarkConfig(scenarios: scenarios);
  }

  factory BenchmarkConfig.single(BenchmarkScenario scenario) =>
      BenchmarkConfig(scenarios: [scenario]);

  String toPrettyJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'benchmarks': scenarios.map((s) => s.toJson()).toList()});
}

class BenchmarkScenario {
  BenchmarkScenario({
    required this.name,
    required this.type,
    required this.duration,
    this.warmup = Duration.zero,
    this.concurrency = 1,
    this.targetRatePerSecond,
    Map<String, Object?>? extra,
  }) : extra = extra == null ? const {} : Map.unmodifiable(extra);

  final String name;
  final String type;
  final Duration duration;
  final Duration warmup;
  final int concurrency;
  final int? targetRatePerSecond;
  final Map<String, Object?> extra;

  factory BenchmarkScenario.fromMap(Map<String, Object?> map) {
    final name = _expectString(map['name'], 'scenario.name');
    final type = _expectString(map['type'], 'scenario.type');
    final duration = _parseDuration(
      _expectString(map['duration'], 'scenario.duration'),
    );
    final warmup = map['warmup'] is String
        ? _parseDuration(map['warmup'] as String)
        : Duration.zero;
    final concurrency = _asInt(map['concurrency'], defaultValue: 1);
    final rate = map['rate'] == null ? null : _asInt(map['rate']);
    final extra = _asMap(map['extra']);
    return BenchmarkScenario(
      name: name,
      type: type,
      duration: duration,
      warmup: warmup,
      concurrency: concurrency,
      targetRatePerSecond: rate,
      extra: extra,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    'duration': _formatDuration(duration),
    if (warmup > Duration.zero) 'warmup': _formatDuration(warmup),
    'concurrency': concurrency,
    if (targetRatePerSecond != null) 'rate': targetRatePerSecond,
    if (extra.isNotEmpty) 'extra': extra,
  };
}

Duration _parseDuration(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.endsWith('ms')) {
    final numPart = lower.substring(0, lower.length - 2);
    return Duration(milliseconds: int.parse(numPart));
  }
  if (lower.endsWith('s')) {
    final numPart = lower.substring(0, lower.length - 1);
    return Duration(seconds: int.parse(numPart));
  }
  if (lower.endsWith('m')) {
    final numPart = lower.substring(0, lower.length - 1);
    return Duration(minutes: int.parse(numPart));
  }
  if (lower.endsWith('h')) {
    final numPart = lower.substring(0, lower.length - 1);
    return Duration(hours: int.parse(numPart));
  }
  throw FormatException('Unsupported duration format "$value"');
}

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds % 1000 != 0) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inSeconds % 60 != 0) {
    return '${duration.inSeconds}s';
  }
  if (duration.inMinutes % 60 != 0) {
    return '${duration.inMinutes}m';
  }
  return '${duration.inHours}h';
}

String _expectString(Object? value, String path) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Expected "$path" to be a non-empty string');
}

int _asInt(Object? value, {int? defaultValue}) {
  if (value == null) {
    if (defaultValue != null) {
      return defaultValue;
    }
    throw FormatException('Expected integer value');
  }
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.parse(value);
  }
  throw FormatException('Expected integer value');
}

Map<String, Object?>? _asMap(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map<String, Object?>) {
    return value;
  }
  throw FormatException('Expected map value');
}

Object? _convertYaml(Object? node) {
  if (node is YamlMap) {
    return Map<String, Object?>.fromEntries(
      node.nodes.entries.map((entry) {
        final key = _convertYaml(entry.key);
        if (key is! String || key.isEmpty) {
          throw FormatException('YAML map keys must be non-empty strings');
        }
        return MapEntry(key, _convertYaml(entry.value));
      }),
    );
  }
  if (node is YamlList) {
    return node.nodes.map(_convertYaml).toList(growable: false);
  }
  if (node is YamlScalar) {
    return node.value;
  }
  return node;
}
