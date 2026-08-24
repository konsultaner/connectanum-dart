import 'dart:convert';
import 'dart:typed_data';

import 'package:wamp_app/src/domain/local_chat_message.dart';
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
  int _mailboxCursor = 0;
  final List<LocalChatMessage> _messages = [];

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
  int get mailboxCursor => _mailboxCursor;

  @override
  List<LocalChatMessage> get messages => List.unmodifiable(_messages);

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
    bool allowRevokedSender = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveMailboxState({
    required int cursor,
    required List<LocalChatMessage> messages,
  }) async {
    _mailboxCursor = cursor;
    _messages
      ..clear()
      ..addAll(messages);
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
