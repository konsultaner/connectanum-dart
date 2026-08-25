import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final class FcmPlatformPushConfig {
  const FcmPlatformPushConfig({
    required this.serviceAccountPath,
    this.projectId,
  });

  final String serviceAccountPath;
  final String? projectId;
}

class WampAppServerConfig {
  static const defaultAttachmentMaxTotalBytes = 10 * 1024 * 1024 * 1024;
  static const defaultAttachmentMaxBytesPerSender = 2 * 1024 * 1024 * 1024;
  static const defaultAttachmentStagingTtl = Duration(hours: 24);
  static const defaultAttachmentCleanupInterval = Duration(minutes: 15);

  const WampAppServerConfig({
    required this.host,
    required this.port,
    required this.websocketPath,
    required this.accountStorePath,
    required this.messageStorePath,
    this.pushStorePath,
    this.fcmPush,
    this.attachmentStorePath,
    this.attachmentMaxTotalBytes = defaultAttachmentMaxTotalBytes,
    this.attachmentMaxBytesPerSender = defaultAttachmentMaxBytesPerSender,
    this.attachmentStagingTtl = defaultAttachmentStagingTtl,
    this.attachmentCleanupInterval = defaultAttachmentCleanupInterval,
    required this.argonIterations,
    required this.argonMemoryKiB,
  });

  final String host;
  final int port;
  final String websocketPath;
  final String accountStorePath;
  final String messageStorePath;
  final String? pushStorePath;
  final FcmPlatformPushConfig? fcmPush;
  final String? attachmentStorePath;
  final int attachmentMaxTotalBytes;
  final int attachmentMaxBytesPerSender;
  final Duration attachmentStagingTtl;
  final Duration attachmentCleanupInterval;
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
    final attachmentLimits = document['attachment_limits'] == null
        ? null
        : _map(document['attachment_limits'], 'attachment_limits');
    final platformPush = document['platform_push'] == null
        ? null
        : _map(document['platform_push'], 'platform_push');
    final fcm = platformPush == null || platformPush['fcm'] == null
        ? null
        : _map(platformPush['fcm'], 'platform_push.fcm');
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
    final configuredPush = document['push_store'] == null
        ? '$configuredMessages.push.json'
        : _string(document['push_store'], 'push_store');
    final pushStore = p.isAbsolute(configuredPush)
        ? configuredPush
        : p.normalize(p.join(base, configuredPush));
    final configuredServiceAccount = fcm == null
        ? null
        : _string(
            fcm['service_account_file'],
            'platform_push.fcm.service_account_file',
          );
    final serviceAccountPath = configuredServiceAccount == null
        ? null
        : p.isAbsolute(configuredServiceAccount)
        ? configuredServiceAccount
        : p.normalize(p.join(base, configuredServiceAccount));
    final projectId = fcm == null || fcm['project_id'] == null
        ? null
        : _string(fcm['project_id'], 'platform_push.fcm.project_id');
    final configuredAttachments = document['attachment_store'] == null
        ? '$configuredMessages.attachments'
        : _string(document['attachment_store'], 'attachment_store');
    final attachmentStore = p.isAbsolute(configuredAttachments)
        ? configuredAttachments
        : p.normalize(p.join(base, configuredAttachments));
    final attachmentMaxTotalBytes = attachmentLimits == null
        ? defaultAttachmentMaxTotalBytes
        : _integer(
            attachmentLimits['max_total_bytes'],
            'attachment_limits.max_total_bytes',
            min: 1,
            max: 1 << 50,
          );
    final attachmentMaxBytesPerSender = attachmentLimits == null
        ? defaultAttachmentMaxBytesPerSender
        : _integer(
            attachmentLimits['max_bytes_per_sender'],
            'attachment_limits.max_bytes_per_sender',
            min: 1,
            max: 1 << 50,
          );
    if (attachmentMaxBytesPerSender > attachmentMaxTotalBytes) {
      throw const FormatException(
        'attachment_limits.max_bytes_per_sender must not exceed '
        'max_total_bytes.',
      );
    }
    return WampAppServerConfig(
      host: host,
      port: port,
      websocketPath: websocketPath,
      accountStorePath: accountStore,
      messageStorePath: messageStore,
      pushStorePath: pushStore,
      fcmPush: serviceAccountPath == null
          ? null
          : FcmPlatformPushConfig(
              serviceAccountPath: serviceAccountPath,
              projectId: projectId,
            ),
      attachmentStorePath: attachmentStore,
      attachmentMaxTotalBytes: attachmentMaxTotalBytes,
      attachmentMaxBytesPerSender: attachmentMaxBytesPerSender,
      attachmentStagingTtl: attachmentLimits == null
          ? defaultAttachmentStagingTtl
          : Duration(
              seconds: _integer(
                attachmentLimits['staging_ttl_seconds'],
                'attachment_limits.staging_ttl_seconds',
                min: 1,
                max: 30 * 24 * 60 * 60,
              ),
            ),
      attachmentCleanupInterval: attachmentLimits == null
          ? defaultAttachmentCleanupInterval
          : Duration(
              seconds: _integer(
                attachmentLimits['cleanup_interval_seconds'],
                'attachment_limits.cleanup_interval_seconds',
                min: 1,
                max: 24 * 60 * 60,
              ),
            ),
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
