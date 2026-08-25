import 'dart:io';

import 'package:test/test.dart';
import 'package:wamp_app_server/src/server_config.dart';

void main() {
  test('attachment limits use production defaults when omitted', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(_configYaml());

    final config = await WampAppServerConfig.load(file.path);

    expect(
      config.attachmentMaxTotalBytes,
      WampAppServerConfig.defaultAttachmentMaxTotalBytes,
    );
    expect(
      config.attachmentMaxBytesPerSender,
      WampAppServerConfig.defaultAttachmentMaxBytesPerSender,
    );
    expect(
      config.attachmentStagingTtl,
      WampAppServerConfig.defaultAttachmentStagingTtl,
    );
    expect(
      config.attachmentCleanupInterval,
      WampAppServerConfig.defaultAttachmentCleanupInterval,
    );
  });

  test('attachment limits load from YAML', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        attachmentLimits: '''
attachment_limits:
  max_total_bytes: 4096
  max_bytes_per_sender: 2048
  staging_ttl_seconds: 3600
  cleanup_interval_seconds: 60
''',
      ),
    );

    final config = await WampAppServerConfig.load(file.path);

    expect(config.attachmentMaxTotalBytes, 4096);
    expect(config.attachmentMaxBytesPerSender, 2048);
    expect(config.attachmentStagingTtl, const Duration(hours: 1));
    expect(config.attachmentCleanupInterval, const Duration(minutes: 1));
  });

  test('per-sender attachment limit cannot exceed the global limit', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        attachmentLimits: '''
attachment_limits:
  max_total_bytes: 1024
  max_bytes_per_sender: 2048
  staging_ttl_seconds: 3600
  cleanup_interval_seconds: 60
''',
      ),
    );

    await expectLater(
      WampAppServerConfig.load(file.path),
      throwsA(isA<FormatException>()),
    );
  });
}

String _configYaml({String attachmentLimits = ''}) =>
    '''
listen:
  host: 127.0.0.1
  port: 8080
websocket_path: /ws
account_store: data/accounts.json
message_store: data/messages.json
attachment_store: data/attachments
$attachmentLimits
argon2id13:
  iterations: 3
  memory_kib: 65536
''';
