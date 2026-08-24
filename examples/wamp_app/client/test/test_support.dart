import 'dart:convert';
import 'dart:typed_data';

import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class FakeDeviceTrustStore implements DeviceTrustStore {
  String? password;
  FakeDeviceTrustSession? session;
  Object? failure;

  @override
  Future<DeviceTrustSession> openOrCreate({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String deviceName,
  }) async {
    this.password = password;
    final failure = this.failure;
    if (failure != null) throw failure;
    return session = FakeDeviceTrustSession(username);
  }
}

final class FakeDeviceTrustSession implements DeviceTrustSession {
  FakeDeviceTrustSession(this.username);

  final String username;
  bool disposed = false;

  @override
  late final DeviceEnrollment enrollment = DeviceEnrollment(
    deviceId: _token(32, 1),
    deviceName: 'Test device',
    signingPublicKey: _token(32, 2),
    exchangePublicKey: _token(32, 3),
    attestation: _token(64, 4),
    createdAt: DateTime.utc(2026, 8, 24),
  );

  @override
  String get deviceId => enrollment.deviceId;

  @override
  String get safetyNumber => 'AAAA BBBB CCCC DDDD';

  @override
  bool isVerified(DeviceRecord contact) => false;

  @override
  Future<void> markVerified(DeviceRecord contact) async {}

  @override
  String safetyNumberFor(DeviceRecord contact) => safetyNumber;

  @override
  WrappedConversationKey wrapConversationKey({
    required String conversationId,
    required DeviceRecord recipient,
    required Uint8List conversationKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Uint8List unwrapConversationKey({
    required WrappedConversationKey envelope,
    required DeviceRecord sender,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

DeviceRecord activeDeviceRecord(String username, DeviceEnrollment enrollment) {
  return DeviceRecord(
    username: username,
    enrollment: enrollment,
    enrolledAt: DateTime.utc(2026, 8, 24, 12),
    lastSeenAt: DateTime.utc(2026, 8, 24, 12),
  );
}

String _token(int length, int seed) => base64Url
    .encode(List<int>.generate(length, (index) => (seed + index) & 0xff))
    .replaceAll('=', '');
