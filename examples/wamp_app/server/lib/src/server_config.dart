import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:yaml/yaml.dart';

import 'backup_store.dart';

final class FcmPlatformPushConfig {
  const FcmPlatformPushConfig({
    required this.serviceAccountPath,
    this.projectId,
  });

  final String serviceAccountPath;
  final String? projectId;
}

final class TurnRestConfig {
  TurnRestConfig({
    required Iterable<String> urls,
    required this.sharedSecret,
    this.credentialTtl = const Duration(hours: 1),
  }) : urls = List<String>.unmodifiable(urls) {
    if (this.urls.isEmpty ||
        this.urls.length > 8 ||
        this.urls.any(
          (url) =>
              !(url.startsWith('turn:') || url.startsWith('turns:')) ||
              url.length > 2048,
        ) ||
        sharedSecret.isEmpty ||
        credentialTtl < const Duration(minutes: 5) ||
        credentialTtl > const Duration(hours: 24)) {
      throw const FormatException('TURN REST configuration is invalid.');
    }
  }

  final List<String> urls;
  final String sharedSecret;
  final Duration credentialTtl;

  @override
  String toString() =>
      'TurnRestConfig(urls: $urls, credentialTtl: $credentialTtl, '
      'sharedSecret: [redacted])';
}

class WampAppServerConfig {
  static const defaultAttachmentMaxTotalBytes = 10 * 1024 * 1024 * 1024;
  static const defaultAttachmentMaxBytesPerSender = 2 * 1024 * 1024 * 1024;
  static const defaultAttachmentStagingTtl = Duration(hours: 24);
  static const defaultAttachmentCleanupInterval = Duration(minutes: 15);
  static const defaultBackupMaxTotalBytes =
      BackupStore.defaultMaximumTotalBytes;

  const WampAppServerConfig({
    required this.host,
    required this.port,
    required this.websocketPath,
    required this.accountStorePath,
    required this.messageStorePath,
    this.pushStorePath,
    this.fcmPush,
    this.attachmentStorePath,
    this.backupStorePath,
    this.callStorePath,
    this.stunUrls = const [],
    this.turnRest,
    this.backupMaxTotalBytes = defaultBackupMaxTotalBytes,
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
  final String? backupStorePath;
  final String? callStorePath;
  final List<String> stunUrls;
  final TurnRestConfig? turnRest;
  final int backupMaxTotalBytes;
  final int attachmentMaxTotalBytes;
  final int attachmentMaxBytesPerSender;
  final Duration attachmentStagingTtl;
  final Duration attachmentCleanupInterval;
  final int argonIterations;
  final int argonMemoryKiB;

  static Future<WampAppServerConfig> load(
    String path, {
    Map<String, String>? environment,
  }) async {
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
    final backupLimits = document['backup_limits'] == null
        ? null
        : _map(document['backup_limits'], 'backup_limits');
    final platformPush = document['platform_push'] == null
        ? null
        : _map(document['platform_push'], 'platform_push');
    final fcm = platformPush == null || platformPush['fcm'] == null
        ? null
        : _map(platformPush['fcm'], 'platform_push.fcm');
    final webrtc = document['webrtc'] == null
        ? null
        : _map(document['webrtc'], 'webrtc');
    final turnRest = webrtc == null || webrtc['turn_rest'] == null
        ? null
        : _map(webrtc['turn_rest'], 'webrtc.turn_rest');
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
    final configuredBackups = document['backup_store'] == null
        ? '$configuredMessages.backups'
        : _string(document['backup_store'], 'backup_store');
    final backupStore = p.isAbsolute(configuredBackups)
        ? configuredBackups
        : p.normalize(p.join(base, configuredBackups));
    final configuredCalls = document['call_store'] == null
        ? '$configuredMessages.calls.json'
        : _string(document['call_store'], 'call_store');
    final callStore = p.isAbsolute(configuredCalls)
        ? configuredCalls
        : p.normalize(p.join(base, configuredCalls));
    final stunUrls = _urlList(
      webrtc?['stun_urls'],
      'webrtc.stun_urls',
      schemes: const {'stun'},
    );
    final turnUrls = _urlList(
      turnRest?['urls'],
      'webrtc.turn_rest.urls',
      schemes: const {'turn', 'turns'},
    );
    final turnSecretEnvironment = turnRest == null
        ? null
        : _string(
            turnRest['shared_secret_environment'],
            'webrtc.turn_rest.shared_secret_environment',
          );
    final turnSecret = turnSecretEnvironment == null
        ? null
        : (environment ?? Platform.environment)[turnSecretEnvironment];
    if (turnSecretEnvironment != null &&
        (turnSecret == null || turnSecret.isEmpty)) {
      throw FormatException(
        'webrtc.turn_rest requires environment variable '
        '$turnSecretEnvironment.',
      );
    }
    final backupMaxTotalBytes = backupLimits == null
        ? defaultBackupMaxTotalBytes
        : _integer(
            backupLimits['max_total_bytes'],
            'backup_limits.max_total_bytes',
            min: WampAppBackupTransferLimits.maximumArchiveBytes,
            max: 1 << 50,
          );
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
      backupStorePath: backupStore,
      callStorePath: callStore,
      stunUrls: stunUrls,
      turnRest: turnRest == null
          ? null
          : TurnRestConfig(
              urls: turnUrls,
              sharedSecret: turnSecret!,
              credentialTtl: Duration(
                seconds: _integer(
                  turnRest['credential_ttl_seconds'] ?? 3600,
                  'webrtc.turn_rest.credential_ttl_seconds',
                  min: 300,
                  max: 24 * 60 * 60,
                ),
              ),
            ),
      backupMaxTotalBytes: backupMaxTotalBytes,
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

  static List<String> _urlList(
    Object? value,
    String name, {
    required Set<String> schemes,
  }) {
    if (value == null) return const [];
    if (value is! List || value.isEmpty || value.length > 8) {
      throw FormatException('$name must be a non-empty list.');
    }
    final urls = value
        .map((entry) {
          if (entry is! String ||
              entry.trim() != entry ||
              entry.length > 2048) {
            throw FormatException('$name entries must be valid ICE URLs.');
          }
          final separator = entry.indexOf(':');
          if (separator < 1 ||
              !schemes.contains(entry.substring(0, separator))) {
            throw FormatException('$name contains an unsupported URL scheme.');
          }
          return entry;
        })
        .toList(growable: false);
    return List<String>.unmodifiable(urls);
  }
}
