import 'dart:io';

import 'router_config_loader.dart';
import 'router_settings.dart';

/// Convenience helpers for loading router configuration files from disk.
class RouterConfigLoaderIo {
  RouterConfigLoaderIo._();

  /// Loads configuration from [path], inferring the format from the file
  /// extension (`.json`, `.yaml`, `.yml`).
  static Future<RouterSettings> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Configuration file not found', path);
    }
    final contents = await file.readAsString();
    final lower = path.toLowerCase();
    if (lower.endsWith('.json')) {
      return RouterConfigLoader.fromJsonString(contents);
    }
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return RouterConfigLoader.fromYamlString(contents);
    }
    throw FormatException(
      'Unsupported configuration extension for "$path". '
      'Expected .json, .yaml, or .yml.',
    );
  }
}
