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
    expect(
      config.pushStorePath,
      '${directory.path}/data/messages.json.push.json',
    );
    expect(
      config.backupStorePath,
      '${directory.path}/data/messages.json.backups',
    );
    expect(
      config.callStorePath,
      '${directory.path}/data/messages.json.calls.json',
    );
    expect(config.stunUrls, isEmpty);
    expect(config.turnRest, isNull);
    expect(
      config.backupMaxTotalBytes,
      WampAppServerConfig.defaultBackupMaxTotalBytes,
    );
    expect(config.fcmPush, isNull);
    expect(config.mcp.enabled, isFalse);
    expect(
      config.mcp.consentStorePath,
      '${directory.path}/data/messages.json.mcp-consent.json',
    );
    expect(config.abuseProtection.registration.maxRequests, 20);
    expect(config.abuseProtection.controlPerAccount.maxRequests, 2400);
    expect(config.abuseProtection.transferPerAccount.maxRequests, 12000);
    expect(config.abuseProtection.maxTrackedAccounts, 4096);
  });

  test('abuse-protection budgets load from YAML', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        abuseProtection: '''
abuse_protection:
  max_tracked_accounts: 12
  registration:
    max_requests: 3
    window_seconds: 30
    max_concurrent: 1
  control:
    global:
      max_requests: 100
      window_seconds: 20
      max_concurrent: 10
    per_account:
      max_requests: 8
      window_seconds: 10
      max_concurrent: 2
  transfer:
    global:
      max_requests: 200
      window_seconds: 40
      max_concurrent: 20
    per_account:
      max_requests: 16
      window_seconds: 5
      max_concurrent: 4
''',
      ),
    );

    final config = await WampAppServerConfig.load(file.path);

    expect(config.abuseProtection.maxTrackedAccounts, 12);
    expect(config.abuseProtection.registration.maxRequests, 3);
    expect(
      config.abuseProtection.registration.window,
      const Duration(seconds: 30),
    );
    expect(config.abuseProtection.registration.maxConcurrent, 1);
    expect(config.abuseProtection.controlGlobal.maxRequests, 100);
    expect(config.abuseProtection.controlPerAccount.maxConcurrent, 2);
    expect(
      config.abuseProtection.transferGlobal.window,
      const Duration(seconds: 40),
    );
    expect(config.abuseProtection.transferPerAccount.maxRequests, 16);
  });

  for (final malformed in const [
    'abuse_protection: []\n',
    'abuse_protection:\n  max_tracked_accounts: 0\n',
    'abuse_protection:\n  registration:\n    max_requests: 0\n',
    'abuse_protection:\n  control:\n    global: []\n',
    'abuse_protection:\n  transfer:\n    per_account:\n      window_seconds: 0\n',
  ]) {
    test('malformed abuse-protection config fails closed', () async {
      final directory = await Directory.systemTemp.createTemp(
        'wampapp-config-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/server.yaml');
      await file.writeAsString(_configYaml(abuseProtection: malformed));

      await expectLater(
        WampAppServerConfig.load(file.path),
        throwsFormatException,
      );
    });
  }

  test('MCP endpoint and consent store load from YAML', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        mcp: '''
mcp:
  enabled: true
  path: /agent/mcp
  auth_path: /agent/auth
  consent_store: durable/mcp-consent.json
  allow_insecure_transport: true
''',
      ),
    );

    final config = await WampAppServerConfig.load(file.path);

    expect(config.mcp.enabled, isTrue);
    expect(config.mcp.path, '/agent/mcp');
    expect(config.mcp.authPath, '/agent/auth');
    expect(
      config.mcp.consentStorePath,
      '${directory.path}/durable/mcp-consent.json',
    );
    expect(config.mcp.allowInsecureTransport, isTrue);
  });

  test('cleartext MCP authentication fails closed off loopback', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        host: '0.0.0.0',
        mcp: '''
mcp:
  enabled: true
  allow_insecure_transport: true
''',
      ),
    );

    await expectLater(
      WampAppServerConfig.load(file.path),
      throwsFormatException,
    );
  });

  for (final paths in const [
    '  path: ws\n  auth_path: /mcp/auth\n',
    '  path: /ws\n  auth_path: /mcp/auth\n',
    '  path: /mcp\n  auth_path: /mcp\n',
    '  path: /mcp?unsafe=true\n  auth_path: /mcp/auth\n',
  ]) {
    test('malformed or colliding MCP paths fail closed', () async {
      final directory = await Directory.systemTemp.createTemp(
        'wampapp-config-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/server.yaml');
      await file.writeAsString(
        _configYaml(mcp: 'mcp:\n  enabled: true\n$paths'),
      );

      await expectLater(
        WampAppServerConfig.load(file.path),
        throwsFormatException,
      );
    });
  }

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

  test('push subscription store loads from YAML', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(pushStore: 'push_store: secrets/push.json\n'),
    );

    final config = await WampAppServerConfig.load(file.path);

    expect(config.pushStorePath, '${directory.path}/secrets/push.json');
  });

  test('backup store and total quota load from YAML', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        backupStore: 'backup_store: durable/backups\n',
        backupLimits: '''
backup_limits:
  max_total_bytes: 25165824
''',
      ),
    );

    final config = await WampAppServerConfig.load(file.path);

    expect(config.backupStorePath, '${directory.path}/durable/backups');
    expect(config.backupMaxTotalBytes, 25165824);
  });

  test('FCM platform push config resolves secrets relative to YAML', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        platformPush: '''
platform_push:
  fcm:
    service_account_file: secrets/firebase-service-account.json
    project_id: wampapp-test1
''',
      ),
    );

    final config = await WampAppServerConfig.load(file.path);

    expect(
      config.fcmPush?.serviceAccountPath,
      '${directory.path}/secrets/firebase-service-account.json',
    );
    expect(config.fcmPush?.projectId, 'wampapp-test1');
  });

  test('WebRTC config resolves STUN and secret-backed TURN REST', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        callStore: 'call_store: durable/calls.json\n',
        webrtc: '''
webrtc:
  stun_urls:
    - stun:stun.example.net:3478
  turn_rest:
    urls:
      - turns:turn.example.net:5349?transport=tcp
    shared_secret_environment: TEST_TURN_SECRET
    credential_ttl_seconds: 900
''',
      ),
    );

    final config = await WampAppServerConfig.load(
      file.path,
      environment: const {'TEST_TURN_SECRET': 'private-test-secret'},
    );

    expect(config.callStorePath, '${directory.path}/durable/calls.json');
    expect(config.stunUrls, ['stun:stun.example.net:3478']);
    expect(config.turnRest?.urls, [
      'turns:turn.example.net:5349?transport=tcp',
    ]);
    expect(config.turnRest?.credentialTtl, const Duration(minutes: 15));
    expect(config.turnRest.toString(), contains('[redacted]'));
    expect(config.turnRest.toString(), isNot(contains('private-test-secret')));
  });

  test('missing TURN secret fails configuration closed', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/server.yaml');
    await file.writeAsString(
      _configYaml(
        webrtc: '''
webrtc:
  turn_rest:
    urls:
      - turn:turn.example.net:3478
    shared_secret_environment: MISSING_TURN_SECRET
''',
      ),
    );

    await expectLater(
      WampAppServerConfig.load(file.path, environment: const {}),
      throwsFormatException,
    );
  });

  for (final malformed in const [
    'platform_push: []\n',
    'platform_push:\n  fcm: []\n',
    'platform_push:\n  fcm:\n    service_account_file: ""\n',
  ]) {
    test('malformed platform push config fails closed', () async {
      final directory = await Directory.systemTemp.createTemp(
        'wampapp-config-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/server.yaml');
      await file.writeAsString(_configYaml(platformPush: malformed));

      await expectLater(
        WampAppServerConfig.load(file.path),
        throwsA(isA<FormatException>()),
      );
    });
  }

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

String _configYaml({
  String host = '127.0.0.1',
  String attachmentLimits = '',
  String pushStore = '',
  String backupStore = '',
  String backupLimits = '',
  String platformPush = '',
  String callStore = '',
  String webrtc = '',
  String mcp = '',
  String abuseProtection = '',
}) =>
    '''
listen:
  host: $host
  port: 8080
websocket_path: /ws
account_store: data/accounts.json
message_store: data/messages.json
$pushStore
$backupStore
$backupLimits
$platformPush
$callStore
$webrtc
$mcp
$abuseProtection
attachment_store: data/attachments
$attachmentLimits
argon2id13:
  iterations: 3
  memory_kib: 65536
''';
