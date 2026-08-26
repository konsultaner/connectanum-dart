import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:wamp_app/src/domain/local_chat_group.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/local_contact_alias.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';
import 'package:wamp_app/src/domain/outbound_chat_message.dart';
import 'package:wamp_app/src/infrastructure/device_backup_file.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class FakeDeviceTrustStore implements DeviceTrustStore {
  FakeDeviceTrustStore({
    this.initialMessages = const [],
    this.initialGroups = const [],
    this.initialOutbox = const [],
    this.initialContacts = const [],
    LocalAppPreferences? initialPreferences,
    this.operations,
  }) : initialPreferences = initialPreferences ?? LocalAppPreferences.defaults;

  final List<LocalChatMessage> initialMessages;
  final List<LocalChatGroup> initialGroups;
  final List<OutboundChatMessage> initialOutbox;
  final List<LocalContactAlias> initialContacts;
  final LocalAppPreferences initialPreferences;
  final List<String>? operations;
  String? password;
  FakeDeviceTrustSession? session;
  Object? failure;
  Object? importFailure;
  int importCalls = 0;
  Uint8List? importedArchive;

  @override
  Future<DeviceTrustSession> openOrCreate({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String deviceName,
  }) async {
    operations?.add('vault-open');
    this.password = password;
    final failure = this.failure;
    if (failure != null) throw failure;
    final previous = session;
    return session = FakeDeviceTrustSession(
      username,
      previous?.messages ?? initialMessages,
      previous?.groups ?? initialGroups,
      previous?.outbox ?? initialOutbox,
      previous?.mailboxCursor ?? 0,
      previous?.preferences ?? initialPreferences,
      initialContacts: previous?.contacts ?? initialContacts,
    );
  }

  @override
  Future<void> importBackup({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String recoveryPassphrase,
    required Uint8List archive,
  }) async {
    operations?.add('backup-import');
    importCalls += 1;
    final failure = importFailure;
    if (failure != null) throw failure;
    importedArchive = Uint8List.fromList(archive);
  }
}

final class FakeDeviceTrustSession implements DeviceTrustSession {
  FakeDeviceTrustSession(
    this.username,
    List<LocalChatMessage> initialMessages,
    List<LocalChatGroup> initialGroups,
    List<OutboundChatMessage> initialOutbox,
    this._mailboxCursor,
    this._preferences, {
    List<LocalContactAlias> initialContacts = const [],
    this.sealCallSignalCallback,
    this.openCallSignalCallback,
  }) {
    _messages.addAll(initialMessages);
    _groups.addAll(initialGroups);
    _outbox.addAll(initialOutbox);
    _contacts.addAll(initialContacts);
  }

  final String username;
  bool disposed = false;
  int _mailboxCursor;
  final List<LocalChatMessage> _messages = [];
  final List<LocalChatGroup> _groups = [];
  final List<OutboundChatMessage> _outbox = [];
  final List<LocalContactAlias> _contacts = [];
  LocalAppPreferences _preferences;
  Object? saveContactsFailure;
  Completer<void>? saveContactsGate;
  int saveContactsCalls = 0;
  Object? savePreferencesFailure;
  Completer<void>? savePreferencesGate;
  int savePreferencesCalls = 0;
  Object? exportBackupFailure;
  int exportBackupCalls = 0;
  final EncryptedCallSignal Function({
    required String callId,
    required String signalId,
    required CallSignalKind kind,
    required DeviceRecord recipient,
    required Uint8List plaintext,
  })?
  sealCallSignalCallback;
  final Uint8List Function({
    required EncryptedCallSignal signal,
    required DeviceRecord sender,
  })?
  openCallSignalCallback;

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
  List<LocalChatGroup> get groups => List.unmodifiable(_groups);

  @override
  List<OutboundChatMessage> get outbox => List.unmodifiable(_outbox);

  @override
  List<LocalContactAlias> get contacts => List.unmodifiable(_contacts);

  @override
  LocalAppPreferences get preferences => _preferences;

  @override
  Future<Uint8List> exportBackup({required String recoveryPassphrase}) async {
    exportBackupCalls += 1;
    final failure = exportBackupFailure;
    if (failure != null) throw failure;
    return Uint8List.fromList(utf8.encode('fake encrypted backup'));
  }

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
    return WrappedConversationKey(
      conversationId: conversationId,
      senderUsername: username,
      senderDeviceId: deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedKey: _token(80, 6),
      signature: _token(64, 7),
      createdAt: DateTime.utc(2026, 8, 24, 12),
    );
  }

  @override
  EncryptedCallSignal sealCallSignal({
    required String callId,
    required String signalId,
    required CallSignalKind kind,
    required DeviceRecord recipient,
    required Uint8List plaintext,
  }) {
    final callback = sealCallSignalCallback;
    if (callback == null) {
      throw UnsupportedError('Fake call signaling is not configured.');
    }
    return callback(
      callId: callId,
      signalId: signalId,
      kind: kind,
      recipient: recipient,
      plaintext: plaintext,
    );
  }

  @override
  OneTimeMessageConsumption signOneTimeConsumption(String messageId) {
    return OneTimeMessageConsumption(
      messageId: messageId,
      deviceId: deviceId,
      signature: _token(64, 8),
    );
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
  Uint8List openCallSignal({
    required EncryptedCallSignal signal,
    required DeviceRecord sender,
  }) {
    final callback = openCallSignalCallback;
    if (callback == null) {
      throw UnsupportedError('Fake call signaling is not configured.');
    }
    return callback(signal: signal, sender: sender);
  }

  @override
  Future<void> saveMailboxState({
    required int cursor,
    required List<LocalChatMessage> messages,
    List<LocalChatGroup>? groups,
    List<OutboundChatMessage>? outbox,
  }) async {
    _mailboxCursor = cursor;
    _messages
      ..clear()
      ..addAll(messages);
    if (groups != null) {
      _groups
        ..clear()
        ..addAll(groups);
    }
    if (outbox != null) {
      _outbox
        ..clear()
        ..addAll(outbox);
    }
  }

  @override
  Future<void> savePreferences(LocalAppPreferences preferences) async {
    savePreferencesCalls += 1;
    final failure = savePreferencesFailure;
    if (failure != null) throw failure;
    await savePreferencesGate?.future;
    _preferences = preferences;
  }

  @override
  Future<void> saveContacts(List<LocalContactAlias> contacts) async {
    saveContactsCalls += 1;
    final failure = saveContactsFailure;
    if (failure != null) throw failure;
    await saveContactsGate?.future;
    _contacts
      ..clear()
      ..addAll(contacts);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class FakeDeviceBackupFileGateway implements DeviceBackupFileGateway {
  Uint8List? archiveToOpen;
  Uint8List? savedArchive;
  String? suggestedName;
  Object? openFailure;
  Object? saveFailure;
  bool saveAccepted = true;
  int openCalls = 0;
  int saveCalls = 0;

  @override
  Future<Uint8List?> open() async {
    openCalls += 1;
    final failure = openFailure;
    if (failure != null) throw failure;
    final archive = archiveToOpen;
    return archive == null ? null : Uint8List.fromList(archive);
  }

  @override
  Future<bool> save(Uint8List archive, {required String suggestedName}) async {
    saveCalls += 1;
    final failure = saveFailure;
    if (failure != null) throw failure;
    savedArchive = Uint8List.fromList(archive);
    this.suggestedName = suggestedName;
    return saveAccepted;
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
