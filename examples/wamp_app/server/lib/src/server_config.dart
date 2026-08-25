import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class WampAppServerConfig {
  const WampAppServerConfig({
    required this.host,
    required this.port,
    required this.websocketPath,
    required this.accountStorePath,
    required this.messageStorePath,
    this.attachmentStorePath,
    required this.argonIterations,
    required this.argonMemoryKiB,
  });

  final String host;
  final int port;
  final String websocketPath;
  final String accountStorePath;
  final String messageStorePath;
  final String? attachmentStorePath;
  final int argonIterations;
  final int argonMemoryKiB;

  static Future<WampAppServerConfig> load(String path) async {
    final file = File(path);
    final document = loadYaml(await file.readAsString());
    if (document is! YamlMap) {
      throw const FormatException('Server config must be a YAML map.');
    }
    final listen = _map(document['listen'], 'listen');
    final argon = _map(document['argon2id13'], 'argon2id13');
    final host = _string(listen['host'], 'listen.host');
    final port = _integer(listen['port'], 'listen.port', min: 0, max: 65535);
    final websocketPath = _string(document['websocket_path'], 'websocket_path');
    if (!websocketPath.startsWith('/')) {
      throw const FormatException('websocket_path must start with /.');
    }
    final configuredStore = _string(document['account_store'], 'account_store');
    final base = p.dirname(file.absolute.path);
    final accountStore = p.isAbsolute(configuredStore)
        ? configuredStore
        : p.normalize(p.join(base, configuredStore));
    final configuredMessages = _string(
      document['message_store'],
      'message_store',
    );
    final messageStore = p.isAbsolute(configuredMessages)
        ? configuredMessages
        : p.normalize(p.join(base, configuredMessages));
    final configuredAttachments = document['attachment_store'] == null
        ? '$configuredMessages.attachments'
        : _string(document['attachment_store'], 'attachment_store');
    final attachmentStore = p.isAbsolute(configuredAttachments)
        ? configuredAttachments
        : p.normalize(p.join(base, configuredAttachments));
    return WampAppServerConfig(
      host: host,
      port: port,
      websocketPath: websocketPath,
      accountStorePath: accountStore,
      messageStorePath: messageStore,
      attachmentStorePath: attachmentStore,
      argonIterations: _integer(
        argon['iterations'],
        'argon2id13.iterations',
        min: 1,
        max: 20,
      ),
      argonMemoryKiB: _integer(
        argon['memory_kib'],
        'argon2id13.memory_kib',
        min: 8192,
        max: 1048576,
      ),
    );
  }

  static YamlMap _map(Object? value, String name) {
    if (value is! YamlMap) {
      throw FormatException('$name must be a YAML map.');
    }
    return value;
  }

  static String _string(Object? value, String name) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$name must be a non-empty string.');
    }
    return value.trim();
  }

  static int _integer(
    Object? value,
    String name, {
    required int min,
    required int max,
  }) {
    if (value is! int || value < min || value > max) {
      throw FormatException('$name must be between $min and $max.');
    }
    return value;
  }
}
