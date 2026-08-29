import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/local_contact_alias.dart';
import 'package:wamp_app/src/domain/outbound_chat_message.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache.dart';
import 'package:wamp_app/src/infrastructure/attachment_cipher.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/message_cipher.dart';
import 'package:wamp_app/src/infrastructure/platform_push_token_source.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'test_support.dart';

void main() {
  test('registration normalizes identity and connects with the same challenge secret', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);

    await controller.registerAndConnect(
      serverAddress: 'ws://localhost:8080',
      username: ' Alice ',
      displayName: 'Alice Example',
      password: 'correct horse battery',
    );

    expect(controller.status, WampAppStatus.connected);
    expect(controller.connection?.username, 'alice');
    expect(gateway.registered?.username, 'alice');
    expect(gateway.loginPassword, 'correct horse battery');
    expect(trustStore.password, 'correct horse battery');
    expect(controller.localDevice?.deviceId, trustStore.session?.deviceId);
  });

  test(
    'remote cleartext endpoints fail before credentials reach a gateway',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
      );
      addTearDown(controller.dispose);

      await controller.login(
        serverAddress: 'ws://chat.example.test/ws',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(controller.status, WampAppStatus.failed);
      expect(controller.errorMessage, contains('wss://'));
      expect(gateway.loginPassword, isNull);
    },
  );

  test('sign out closes the authenticated connection', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    await controller.signOut();

    expect(controller.status, WampAppStatus.signedOut);
    expect(gateway.closed, isTrue);
    expect(trustStore.session?.disposed, isTrue);
  });

  test('concurrent sign out calls join the same cleanup', () async {
    final gateway = _RecordingGateway()..closeGate = Completer<void>();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    final first = controller.signOut();
    await _waitFor(() => gateway.operations.contains('transport-close'));
    var secondCompleted = false;
    final second = controller.signOut().then((_) => secondCompleted = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(secondCompleted, isFalse);
    expect(
      gateway.operations.where((entry) => entry == 'transport-close'),
      hasLength(1),
    );

    gateway.closeGate!.complete();
    await Future.wait([first, second]);
    expect(secondCompleted, isTrue);
  });

  test(
    'local backup export saves an encrypted snapshot and clears busy state',
    () async {
      final files = FakeDeviceBackupFileGateway();
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: _RecordingGateway(),
        trustStore: trustStore,
        backupFiles: files,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      final saved = await controller.exportLocalBackup(
        recoveryPassphrase: 'correct backup recovery phrase',
      );

      expect(saved, isTrue);
      expect(files.saveCalls, 1);
      expect(utf8.decode(files.savedArchive!), 'fake encrypted backup');
      expect(
        files.suggestedName,
        matches(r'^wampapp-device-\d{8}\.wampbackup$'),
      );
      expect(trustStore.session?.exportBackupCalls, 1);
      expect(controller.backupBusy, isFalse);
      expect(controller.backupError, isNull);
    },
  );

  test(
    'local backup restore imports before opening and enrolling trust',
    () async {
      final files = FakeDeviceBackupFileGateway()
        ..archiveToOpen = Uint8List.fromList(utf8.encode('encrypted archive'));
      final operations = <String>[];
      final trustStore = FakeDeviceTrustStore(operations: operations);
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
        backupFiles: files,
      );
      addTearDown(controller.dispose);

      await controller.restoreLocalBackupAndLogin(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'current account password',
        recoveryPassphrase: 'correct backup recovery phrase',
      );

      expect(controller.status, WampAppStatus.connected);
      expect(files.openCalls, 1);
      expect(trustStore.importCalls, 1);
      expect(utf8.decode(trustStore.importedArchive!), 'encrypted archive');
      expect(trustStore.password, 'current account password');
      expect(operations, ['backup-import', 'vault-open']);
      expect(gateway.operations, contains('enroll'));
    },
  );

  test(
    'failed local restore closes login and never opens a trust session',
    () async {
      final files = FakeDeviceBackupFileGateway()
        ..archiveToOpen = Uint8List.fromList(utf8.encode('encrypted archive'));
      final trustStore = FakeDeviceTrustStore()
        ..importFailure = const BackupRestoreException();
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
        backupFiles: files,
      );
      addTearDown(controller.dispose);

      await controller.restoreLocalBackupAndLogin(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'current account password',
        recoveryPassphrase: 'incorrect backup recovery phrase',
      );

      expect(controller.status, WampAppStatus.failed);
      expect(controller.errorMessage, contains('restore'));
      expect(trustStore.session, isNull);
      expect(gateway.closed, isTrue);
      expect(controller.backupBusy, isFalse);
    },
  );

  test('remote backup upload stores the encrypted local archive', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'current account password',
    );

    final stored = await controller.uploadRemoteBackup(
      recoveryPassphrase: 'correct backup recovery phrase',
    );

    expect(stored, isTrue);
    expect(utf8.decode(gateway.remoteBackup!), 'fake encrypted backup');
    expect(gateway.remoteMetadata?.revision, 1);
    expect(trustStore.session?.exportBackupCalls, 1);
    expect(controller.backupBusy, isFalse);
    expect(controller.backupError, isNull);
  });

  test('remote restore downloads before opening the local vault', () async {
    final operations = <String>[];
    final gateway = _RecordingGateway(operations: operations)
      ..seedRemoteBackup(
        Uint8List.fromList(utf8.encode('remote encrypted archive')),
      );
    final trustStore = FakeDeviceTrustStore(operations: operations);
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);

    await controller.restoreRemoteBackupAndLogin(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'current account password',
      recoveryPassphrase: 'correct backup recovery phrase',
    );

    expect(controller.status, WampAppStatus.connected);
    expect(
      utf8.decode(trustStore.importedArchive!),
      'remote encrypted archive',
    );
    expect(
      operations,
      containsAllInOrder([
        'backup-metadata',
        'backup-chunk:0',
        'backup-import',
        'vault-open',
        'enroll',
      ]),
    );
  });

  test('missing remote backup fails before opening the local vault', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);

    await controller.restoreRemoteBackupAndLogin(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'current account password',
      recoveryPassphrase: 'correct backup recovery phrase',
    );

    expect(controller.status, WampAppStatus.failed);
    expect(controller.errorMessage, contains('No encrypted cloud backup'));
    expect(trustStore.session, isNull);
    expect(gateway.closed, isTrue);
  });

  test(
    'platform tokens bind after enrollment and refresh despite mute',
    () async {
      final gateway = _RecordingGateway();
      final source = _ControllerTokenSource(gateway.operations);
      final session = source.addSession();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
        platformPushTokenSource: source,
      );
      addTearDown(controller.dispose);

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      expect(
        gateway.operations.indexOf('enroll'),
        lessThan(gateway.operations.indexOf('token-open')),
      );

      session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
      await _waitFor(() => gateway.pushRegistrations.length == 1);
      final directId = controller.directConversationIdFor('bob')!;
      expect(await controller.setConversationMuted(directId, true), isTrue);
      await _waitFor(() => gateway.pushRegistrations.length == 2);
      expect(gateway.pushRegistrations.last.token, 'token-1');
      expect(gateway.pushRegistrations.last.mutedConversationIds, [directId]);
      session.emit(const PlatformPushToken(provider: 'fcm', token: 'token-2'));
      await _waitFor(() => gateway.pushRegistrations.length == 3);

      expect(gateway.pushRegistrations.map((request) => request.token), [
        'token-1',
        'token-1',
        'token-2',
      ]);
      expect(gateway.pushRegistrations.last.mutedConversationIds, [directId]);
      await controller.signOut();
      expect(session.closed, isTrue);
      expect(gateway.pushUnregistrations, hasLength(1));
      expect(gateway.closed, isTrue);
    },
  );

  test('push provider failure does not disconnect the WAMP session', () async {
    final gateway = _RecordingGateway();
    final source = _ControllerTokenSource(gateway.operations)
      ..openFailure = StateError('provider unavailable');
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
      platformPushTokenSource: source,
    );
    addTearDown(controller.dispose);

    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(controller.status, WampAppStatus.connected);
    expect(controller.connection, isNotNull);
    expect(controller.platformPushError, contains('unavailable'));
    expect(gateway.closed, isFalse);
  });

  test(
    'replacement unregisters push before closing the old transport',
    () async {
      final gateway = _RecordingGateway();
      final source = _ControllerTokenSource(gateway.operations);
      final first = source.addSession();
      source.addSession();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
        platformPushTokenSource: source,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      first.emit(const PlatformPushToken(provider: 'fcm', token: 'token-1'));
      await _waitFor(() => gateway.pushRegistrations.length == 1);

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(
        gateway.operations.indexOf('push-unregister'),
        lessThan(gateway.operations.indexOf('transport-close')),
      );
      expect(controller.status, WampAppStatus.connected);
    },
  );

  test(
    'account preferences persist while sign out clears live state',
    () async {
      final gateway = _RecordingGateway();
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      final directId = controller.directConversationIdFor('bob')!;

      expect(
        await controller.setThemePreference(WampAppThemePreference.dark),
        isTrue,
      );
      expect(await controller.setConversationMuted(directId, true), isTrue);
      expect(
        await controller.setConversationAppearance(
          directId,
          WampAppConversationAppearance.ocean,
        ),
        isTrue,
      );
      expect(
        await controller.setConversationDisappearingMessages(
          directId,
          const Duration(days: 1),
        ),
        isTrue,
      );
      expect(controller.themePreference, WampAppThemePreference.dark);
      expect(controller.isConversationMuted(directId), isTrue);
      expect(
        controller.conversationAppearanceFor(directId),
        WampAppConversationAppearance.ocean,
      );
      expect(
        controller.disappearingMessagesFor(directId),
        const Duration(days: 1),
      );

      await controller.signOut();
      expect(controller.themePreference, WampAppThemePreference.system);
      expect(controller.isConversationMuted(directId), isFalse);
      expect(
        controller.conversationAppearanceFor(directId),
        WampAppConversationAppearance.standard,
      );
      expect(controller.disappearingMessagesFor(directId), isNull);

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      expect(controller.themePreference, WampAppThemePreference.dark);
      expect(controller.isConversationMuted(directId), isTrue);
      expect(
        controller.conversationAppearanceFor(directId),
        WampAppConversationAppearance.ocean,
      );
      expect(
        controller.disappearingMessagesFor(directId),
        const Duration(days: 1),
      );
    },
  );

  test('failed and concurrent preference saves fail closed', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final session = trustStore.session!;
    session.savePreferencesFailure = StateError('storage unavailable');

    expect(
      await controller.setThemePreference(WampAppThemePreference.dark),
      isFalse,
    );
    expect(controller.themePreference, WampAppThemePreference.system);
    expect(controller.preferenceError, contains('Could not save'));
    final directId = controller.directConversationIdFor('bob')!;
    expect(
      await controller.setConversationDisappearingMessages(
        directId,
        const Duration(hours: 1),
      ),
      isFalse,
    );
    expect(controller.disappearingMessagesFor(directId), isNull);
    expect(
      await controller.setConversationAppearance(
        directId,
        WampAppConversationAppearance.ocean,
      ),
      isFalse,
    );
    expect(
      controller.conversationAppearanceFor(directId),
      WampAppConversationAppearance.standard,
    );

    session.savePreferencesFailure = null;
    final gate = session.savePreferencesGate = Completer<void>();
    final first = controller.setThemePreference(WampAppThemePreference.dark);
    await _waitFor(() => controller.preferenceBusy);
    final second = controller.setThemePreference(WampAppThemePreference.light);

    expect(await second, isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(controller.themePreference, WampAppThemePreference.dark);

    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', session.enrollment),
    ];
    final expiryGate = session.savePreferencesGate = Completer<void>();
    final expirySave = controller.setConversationDisappearingMessages(
      directId,
      const Duration(hours: 1),
    );
    await _waitFor(() => controller.preferenceBusy);
    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'must wait for the chat policy',
      ),
      isFalse,
    );
    expect(gateway.sentMessages, isEmpty);
    expiryGate.complete();
    expect(await expirySave, isTrue);
    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'uses the committed chat policy',
      ),
      isTrue,
    );
    expect(
      gateway.sentMessages.single.expiresAt!.difference(
        gateway.sentMessages.single.createdAt,
      ),
      const Duration(hours: 1),
    );
  });

  test(
    'sign out fences a late preference result from the old session',
    () async {
      final gateway = _RecordingGateway();
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      final gate = trustStore.session!.savePreferencesGate = Completer<void>();

      final update = controller.setThemePreference(WampAppThemePreference.dark);
      await _waitFor(() => controller.preferenceBusy);
      await controller.signOut();
      gate.complete();

      expect(await update, isFalse);
      expect(controller.themePreference, WampAppThemePreference.system);
      expect(controller.preferenceBusy, isFalse);
    },
  );

  test('mute policy suppresses presentation only, not mailbox sync', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final conversationId = controller.directConversationIdFor('bob')!;
    final incoming = LocalChatMessage(
      messageId: 'incoming-message',
      conversationId: conversationId,
      peerUsername: 'bob',
      text: 'hello',
      sentAt: DateTime.utc(2026, 8, 25, 12),
      outgoing: false,
    );
    final outgoing = LocalChatMessage(
      messageId: 'outgoing-message',
      conversationId: conversationId,
      peerUsername: 'bob',
      text: 'hello',
      sentAt: DateTime.utc(2026, 8, 25, 12),
      outgoing: true,
    );

    expect(controller.shouldPresentNotificationFor(incoming), isTrue);
    expect(controller.shouldPresentNotificationFor(outgoing), isFalse);
    expect(await controller.setConversationMuted(conversationId, true), isTrue);
    expect(controller.shouldPresentNotificationFor(incoming), isFalse);

    final connection = gateway.connections.single;
    connection.emitWakeup(1);
    await _waitFor(
      () => trustStore.session?.mailboxCursor == 1 && !controller.messageBusy,
    );
    expect(connection.syncAfterCursors, [0, 0]);
  });

  test('sign out fences a late profile update from the old session', () async {
    final gateway = _RecordingGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final gate = Completer<AccountProfile>();
    gateway.profileUpdateGate = gate;

    final update = controller.updateProfile(
      AccountProfileUpdate(
        expectedRevision: 0,
        displayName: 'Late Alice',
        status: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    gate.complete(
      AccountProfile(
        username: 'alice',
        displayName: 'Late Alice',
        status: '',
        revision: 1,
        updatedAt: DateTime.utc(2026, 8, 25),
      ),
    );

    expect(await update, isFalse);
    expect(controller.status, WampAppStatus.signedOut);
    expect(controller.connection, isNull);
    expect(controller.profileBusy, isFalse);
  });

  test('profile lookup rejects a response for another account', () async {
    final gateway = _RecordingGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.profileLookupOverride = _profileFor('carol');

    final profile = await controller.lookupProfile('bob');

    expect(profile, isNull);
    expect(controller.profileError, contains('another account'));
  });

  test('verified local contacts persist across sign out and login', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(
      await controller.bindContact(
        username: '  BOB  ',
        displayName: '  Bob From Phone  ',
      ),
      isTrue,
    );
    expect(gateway.profileLookups, ['bob']);
    expect(controller.contacts.single.username, 'bob');
    expect(controller.contacts.single.displayName, 'Bob From Phone');
    expect(trustStore.session!.saveContactsCalls, 1);

    await controller.signOut();
    expect(controller.contacts, isEmpty);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    expect(controller.contacts.single.username, 'bob');
  });

  test(
    'contacts replace, rename, and remove without duplicate aliases',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(
        await controller.bindContact(username: 'bob', displayName: 'Bob One'),
        isTrue,
      );
      expect(
        await controller.bindContact(username: 'BOB', displayName: 'Bob Two'),
        isTrue,
      );
      expect(controller.contacts, hasLength(1));
      expect(controller.contacts.single.displayName, 'Bob Two');

      final importedAt = controller.contacts.single.importedAt;
      expect(await controller.renameContact('bob', 'Best Bob'), isTrue);
      expect(controller.contacts.single.displayName, 'Best Bob');
      expect(controller.contacts.single.importedAt, importedAt);
      expect(await controller.removeContact('BOB'), isTrue);
      expect(controller.contacts, isEmpty);
    },
  );

  test(
    'contact binding rejects self and mismatched profile responses',
    () async {
      final gateway = _RecordingGateway();
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(
        await controller.bindContact(username: 'alice', displayName: 'Me'),
        isFalse,
      );
      expect(controller.contactError, contains('own account'));
      expect(gateway.profileLookups, isEmpty);

      gateway.profileLookupOverride = _profileFor('carol');
      expect(
        await controller.bindContact(username: 'bob', displayName: 'Bob'),
        isFalse,
      );
      expect(controller.contacts, isEmpty);
      expect(trustStore.session!.saveContactsCalls, 0);
    },
  );

  test('failed and concurrent contact saves fail closed', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore(
      initialContacts: [
        LocalContactAlias(
          username: 'bob',
          displayName: 'Existing Bob',
          importedAt: DateTime.utc(2026, 8, 26),
        ),
      ],
    );
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final session = trustStore.session!;
    session.saveContactsFailure = StateError('storage unavailable');

    expect(await controller.renameContact('bob', 'Lost Rename'), isFalse);
    expect(controller.contacts.single.displayName, 'Existing Bob');
    expect(controller.contactError, contains('failed'));

    session.saveContactsFailure = null;
    final gate = session.saveContactsGate = Completer<void>();
    final first = controller.renameContact('bob', 'Saved Rename');
    await _waitFor(() => controller.contactBusy);
    final second = controller.removeContact('bob');
    expect(await second, isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(controller.contacts.single.displayName, 'Saved Rename');
  });

  test('sign out fences a late contact save from the old session', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore(
      initialContacts: [
        LocalContactAlias(
          username: 'bob',
          displayName: 'Bob',
          importedAt: DateTime.utc(2026, 8, 26),
        ),
      ],
    );
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final gate = trustStore.session!.saveContactsGate = Completer<void>();

    final rename = controller.renameContact('bob', 'Late Bob');
    await _waitFor(() => controller.contactBusy);
    final signOut = controller.signOut();
    gate.complete();
    await signOut;

    expect(await rename, isFalse);
    expect(controller.contacts, isEmpty);
    expect(controller.contactBusy, isFalse);
  });

  test('replacement login fences a late contact profile lookup', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final oldSession = trustStore.session!;
    final lookupGate = gateway.profileLookupGate = Completer<AccountProfile>();

    final binding = controller.bindContact(
      username: 'bob',
      displayName: 'Late Bob',
    );
    await _waitFor(() => controller.contactBusy);
    gateway.profileLookupGate = null;
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    lookupGate.complete(_profileFor('bob'));

    expect(await binding, isFalse);
    expect(oldSession.saveContactsCalls, 0);
    expect(controller.contacts, isEmpty);
    expect(controller.contactBusy, isFalse);
    expect(controller.contactError, isNull);
  });

  test('MCP profile consent defaults denied and updates by revision', () async {
    final gateway = _RecordingGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(controller.mcpConsent.profileReadAllowed, isFalse);
    expect(controller.mcpConsent.revision, 0);
    expect(await controller.setMcpProfileReadAllowed(true), isTrue);
    expect(controller.mcpConsent.profileReadAllowed, isTrue);
    expect(controller.mcpConsent.revision, 1);
    expect(await controller.setMcpProfileReadAllowed(false), isTrue);
    expect(controller.mcpConsent.profileReadAllowed, isFalse);
    expect(controller.mcpConsent.revision, 2);
    expect(gateway.mcpConsentUpdates, [true, false]);
    expect(controller.mcpConsentError, isNull);
  });

  test('MCP consent conflict refreshes the current account state', () async {
    final gateway = _RecordingGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.mcpConsent = WampAppMcpConsent(
      profileReadAllowed: true,
      revision: 3,
      updatedAt: DateTime.utc(2026, 8, 25),
    );
    gateway.nextMcpConsentFailure = const McpConsentException(
      McpConsentFailureKind.conflict,
    );

    expect(await controller.setMcpProfileReadAllowed(true), isFalse);
    expect(controller.mcpConsent.profileReadAllowed, isTrue);
    expect(controller.mcpConsent.revision, 3);
    expect(controller.mcpConsentError, contains('another device'));
  });

  test(
    'replacement stays connected when closing the old transport fails',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      gateway.failNextClose = true;

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(controller.status, WampAppStatus.connected);
      expect(controller.errorMessage, isNull);
    },
  );

  test('failed replacement preserves the existing trusted session', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final existing = controller.connection;
    gateway.loginFailure = StateError('replacement unavailable');

    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(controller.status, WampAppStatus.connected);
    expect(controller.connection, same(existing));
    expect(gateway.closed, isFalse);
  });

  test(
    'trust failure closes the transport and never reports connected',
    () async {
      final gateway = _RecordingGateway();
      final trustStore = FakeDeviceTrustStore()
        ..failure = const VaultUnlockException();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(controller.status, WampAppStatus.failed);
      expect(controller.connection, isNull);
      expect(gateway.closed, isTrue);
      expect(controller.errorMessage, contains('encrypted device storage'));
    },
  );

  test(
    'mailbox wakeups coalesce into serialized cursor synchronization',
    () async {
      final gateway = _RecordingGateway();
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      final connection = gateway.connections.single;
      final blocked = connection.blockNextSync();

      connection.emitWakeup(1);
      await _waitFor(() => connection.syncAfterCursors.length == 2);
      connection.emitWakeup(2);
      connection.emitWakeup(3);
      connection.emitWakeup(2);
      blocked.complete();

      await _waitFor(
        () => trustStore.session?.mailboxCursor == 3 && !controller.messageBusy,
      );
      expect(connection.syncAfterCursors, [0, 0, 1]);
      expect(controller.messageError, isNull);
    },
  );

  test('sign out fences late mailbox wakeups from the old session', () async {
    final gateway = _RecordingGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final connection = gateway.connections.single;
    final syncCount = connection.syncAfterCursors.length;

    await controller.signOut();
    connection.emitWakeup(7);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(connection.syncAfterCursors, hasLength(syncCount));
    expect(controller.status, WampAppStatus.signedOut);
  });

  test(
    'replacement fences mailbox wakeups from the previous session',
    () async {
      final gateway = _RecordingGateway();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(),
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      final previous = gateway.connections.single;
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      final replacement = gateway.connections.last;

      previous.emitWakeup(7);
      replacement.emitWakeup(1);
      await _waitFor(
        () =>
            replacement.syncAfterCursors.length == 2 && !controller.messageBusy,
      );

      expect(previous.syncAfterCursors, [0]);
      expect(replacement.syncAfterCursors, [0, 0]);
    },
  );

  test('malformed mailbox wakeups surface as synchronization errors', () async {
    final gateway = _RecordingGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    gateway.connections.single.emitError(
      const FormatException('Mailbox wakeup cursor is invalid.'),
    );
    await _waitFor(() => controller.messageError != null);

    expect(controller.messageError, 'Mailbox wakeup cursor is invalid.');
    expect(controller.messages, isEmpty);
  });

  test('sign out fences a late one-time consume response', () async {
    final gateway = _RecordingGateway();
    final message = LocalChatMessage(
      messageId: 'one-time-message',
      conversationId: 'alice-bob',
      peerUsername: 'bob',
      text: 'ephemeral plaintext',
      sentAt: DateTime.utc(2026, 8, 24, 12),
      outgoing: false,
      oneTime: true,
    );
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(initialMessages: [message]),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final connection = gateway.connections.single;
    final blocked = connection.blockNextConsume();

    final reveal = controller.consumeOneTimeMessage(message.messageId);
    await _waitFor(() => connection.consumeCalls.length == 1);
    await controller.signOut();
    blocked.complete(
      MessageReceipt(
        messageId: message.messageId,
        cursor: 1,
        deliveredAt: DateTime.utc(2026, 8, 24, 12, 1),
        readAt: DateTime.utc(2026, 8, 24, 12, 1),
        consumedAt: DateTime.utc(2026, 8, 24, 12, 1),
      ),
    );

    expect(await reveal, isNull);
    expect(controller.status, WampAppStatus.signedOut);
    expect(controller.messageError, isNull);
  });

  test(
    'direct chat policy applies expiry to each new encrypted envelope',
    () async {
      final gateway = _RecordingGateway();
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      gateway.deviceDirectories['bob'] = [
        activeDeviceRecord('bob', trustStore.session!.enrollment),
      ];
      final conversationId = controller.directConversationIdFor('bob')!;
      expect(
        await controller.setConversationDisappearingMessages(
          conversationId,
          const Duration(hours: 1),
        ),
        isTrue,
      );

      expect(
        await controller.sendMessage(
          recipientUsername: 'bob',
          text: 'expires with the chat',
        ),
        isTrue,
      );

      final envelope = gateway.sentMessages.single;
      expect(
        envelope.expiresAt!.difference(envelope.createdAt),
        const Duration(hours: 1),
      );
    },
  );

  test(
    'expiry removes open-chat and encrypted-vault state without a wakeup',
    () async {
      final gateway = _OutboxGateway();
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      gateway.deviceDirectories['bob'] = [
        activeDeviceRecord('bob', trustStore.session!.enrollment),
      ];

      expect(
        await controller.sendMessage(
          recipientUsername: 'bob',
          text: 'short-lived local content',
          expiresAfter: const Duration(milliseconds: 500),
        ),
        isTrue,
      );
      expect(controller.messages, hasLength(1));
      expect(trustStore.session!.messages, hasLength(1));

      await _waitFor(
        () =>
            controller.messages.isEmpty && trustStore.session!.messages.isEmpty,
      );
      expect(controller.messageError, isNull);
    },
  );

  test('expiry persistence failure hides content and retries closed', () async {
    final gateway = _OutboxGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];

    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'retry expiry persistence',
        expiresAfter: const Duration(milliseconds: 500),
      ),
      isTrue,
    );
    final session = trustStore.session!;
    final baselineSaveCalls = session.saveMailboxStateCalls;
    session.saveMailboxStateFailure = StateError('vault unavailable');

    await _waitFor(
      () =>
          controller.messages.isEmpty &&
          session.saveMailboxStateCalls > baselineSaveCalls &&
          controller.messageError != null,
    );
    expect(session.messages, hasLength(1));
    expect(controller.messageError, isNotNull);
    expect('${controller.messageError}', isNot(contains('vault unavailable')));

    session.saveMailboxStateFailure = null;
    await _waitFor(
      () => session.messages.isEmpty && controller.messageError == null,
    );
    expect(controller.messages, isEmpty);
    expect(controller.messageError, isNull);
  });

  test('lost reply retries one exact envelope and reconciles once', () async {
    final gateway = _OutboxGateway()..acceptThenTimeout = true;
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];

    final queued = await controller.sendMessage(
      recipientUsername: 'bob',
      text: 'send exactly once',
    );

    expect(queued, isTrue);
    expect(controller.messages, hasLength(1));
    expect(
      trustStore.session!.outbox.single.state,
      OutboundMessageState.retryable,
    );
    expect(controller.messageError, isNull);
    final messageId = controller.messages.single.messageId;
    final firstWire = jsonEncode(gateway.attempts.single.toJson());

    expect(await controller.retryMessage(messageId), isTrue);

    expect(gateway.attempts, hasLength(2));
    expect(jsonEncode(gateway.attempts.last.toJson()), firstWire);
    expect(gateway.attempts.last.messageId, messageId);
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.messageId, messageId);
    expect(trustStore.session!.outbox, isEmpty);
    expect(trustStore.session!.messages, hasLength(1));
  });

  test(
    'uploads encrypted chunks before publishing an attachment envelope',
    () async {
      final gateway = _OutboxGateway();
      final trustStore = FakeDeviceTrustStore();
      final cache = MemoryAttachmentChunkCache();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
        attachmentCache: cache,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      gateway.deviceDirectories['bob'] = [
        activeDeviceRecord('bob', trustStore.session!.enrollment),
      ];
      final plaintext = Uint8List.fromList(
        List<int>.generate(33000, (index) => (index * 17) % 256),
      );

      expect(
        await controller.sendMessage(
          recipientUsername: 'bob',
          text: '',
          attachmentSources: [
            AttachmentPlaintextSource(
              name: 'private-photo.jpg',
              contentType: 'image/jpeg',
              kind: ChatAttachmentKind.image,
              byteCount: plaintext.length,
              openRead: () => Stream.value(plaintext),
            ),
          ],
        ),
        isTrue,
      );

      expect(gateway.operations, ['put:0', 'send']);
      expect(gateway.attempts.single.attachmentIds, hasLength(1));
      expect(
        gateway.attempts.single.toJson().toString(),
        isNot(contains('jpg')),
      );
      final local = controller.messages.single;
      expect(local.text, isEmpty);
      expect(local.attachments.single.name, 'private-photo.jpg');
      expect(
        await controller.loadAttachment(
          messageId: local.messageId,
          attachmentId: local.attachments.single.attachmentId,
        ),
        plaintext,
      );
      expect(gateway.attachmentGetAttempts, isEmpty);
    },
  );

  test('reconnect resumes after a committed chunk reply is lost', () async {
    final gateway = _OutboxGateway()..failAfterStoredChunkIndex = 0;
    final trustStore = FakeDeviceTrustStore();
    final cache = MemoryAttachmentChunkCache();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
      attachmentCache: cache,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];
    final plaintext = Uint8List.fromList(
      List<int>.generate(
        WampAppAttachmentLimits.defaultChunkBytes + 17,
        (index) => index % 251,
      ),
    );

    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'resume safely',
        attachmentSources: [
          AttachmentPlaintextSource(
            name: 'large.bin',
            contentType: 'application/octet-stream',
            kind: ChatAttachmentKind.file,
            byteCount: plaintext.length,
            openRead: () => Stream.value(plaintext),
          ),
        ],
      ),
      isTrue,
    );
    final pending = trustStore.session!.outbox.single;
    expect(pending.state, OutboundMessageState.retryable);
    expect(gateway.attachmentPutAttempts, [0]);
    expect(gateway.attempts, isEmpty);

    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(gateway.attachmentPutAttempts, [0, 1]);
    expect(gateway.attempts, hasLength(1));
    expect(gateway.attempts.single.messageId, pending.envelope.messageId);
    expect(trustStore.session!.outbox, isEmpty);
    expect(controller.messages.single.attachments, hasLength(1));
  });

  test(
    'downloads a missing ciphertext chunk once and verifies plaintext',
    () async {
      final gateway = _OutboxGateway();
      final producerCache = MemoryAttachmentChunkCache();
      addTearDown(producerCache.dispose);
      final plaintext = Uint8List.fromList(
        List<int>.generate(8193, (index) => (index * 29) % 256),
      );
      const messageId = 'incoming_message_123456';
      final producerCipher = AttachmentCipher();
      addTearDown(producerCipher.dispose);
      final descriptor = (await producerCipher.encryptSources(
        scope: 'producer',
        senderUsername: 'alice',
        messageId: messageId,
        sources: [
          AttachmentPlaintextSource(
            name: 'received.png',
            contentType: 'image/png',
            kind: ChatAttachmentKind.image,
            byteCount: plaintext.length,
            openRead: () => Stream.value(plaintext),
          ),
        ],
        cache: producerCache,
      )).single;
      for (var index = 0; index < descriptor.chunkCount; index += 1) {
        final chunk = (await producerCache.get(
          scope: 'producer',
          senderUsername: 'alice',
          messageId: messageId,
          attachmentId: descriptor.attachmentId,
          chunkIndex: index,
          chunkCount: descriptor.chunkCount,
        ))!;
        gateway.attachmentChunks[gateway._attachmentKey(
              messageId,
              descriptor.attachmentId,
              index,
            )] =
            chunk;
      }
      final trustStore = FakeDeviceTrustStore(
        initialMessages: [
          LocalChatMessage(
            messageId: messageId,
            conversationId: 'alice-bob',
            peerUsername: 'alice',
            text: '',
            sentAt: DateTime.utc(2026, 8, 25, 12),
            outgoing: false,
            attachments: [descriptor],
          ),
        ],
      );
      final cache = MemoryAttachmentChunkCache();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
        attachmentCache: cache,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'bob',
        password: 'correct horse battery',
      );

      final first = await controller.loadAttachment(
        messageId: messageId,
        attachmentId: descriptor.attachmentId,
      );
      final second = await controller.loadAttachment(
        messageId: messageId,
        attachmentId: descriptor.attachmentId,
      );

      expect(first, plaintext);
      expect(second, plaintext);
      expect(gateway.attachmentGetAttempts, [0]);
    },
  );

  test(
    'view-once attachments prefetch before consume and close invalidates cache',
    () async {
      const messageId = 'view-once-attachment-message';
      final plaintext = Uint8List.fromList(
        List<int>.generate(65537, (index) => (index * 23) % 251),
      );
      final producerCache = MemoryAttachmentChunkCache();
      final consumerCache = MemoryAttachmentChunkCache();
      final attachmentCipher = AttachmentCipher();
      addTearDown(producerCache.dispose);
      addTearDown(consumerCache.dispose);
      addTearDown(attachmentCipher.dispose);
      final descriptor = (await attachmentCipher.encryptSources(
        scope: 'producer',
        senderUsername: 'alice',
        messageId: messageId,
        sources: [
          AttachmentPlaintextSource(
            name: 'view-once.bin',
            contentType: 'application/octet-stream',
            kind: ChatAttachmentKind.file,
            byteCount: plaintext.length,
            openRead: () => Stream.value(plaintext),
          ),
        ],
        cache: producerCache,
      )).single;
      final gateway = _OutboxGateway();
      for (var index = 0; index < descriptor.chunkCount; index += 1) {
        final chunk = (await producerCache.get(
          scope: 'producer',
          senderUsername: 'alice',
          messageId: messageId,
          attachmentId: descriptor.attachmentId,
          chunkIndex: index,
          chunkCount: descriptor.chunkCount,
        ))!;
        gateway.attachmentChunks[gateway._attachmentKey(
              messageId,
              descriptor.attachmentId,
              index,
            )] =
            chunk;
      }
      final aliceTrust = FakeDeviceTrustSession(
        'alice',
        const [],
        const [],
        const [],
        0,
        LocalAppPreferences.defaults,
      );
      final envelope = MessageCipher().encrypt(
        senderUsername: 'alice',
        recipientUsername: 'bob',
        text: 'Open this attachment once.',
        trust: aliceTrust,
        participantDevices: [
          activeDeviceRecord('alice', aliceTrust.enrollment),
          activeDeviceRecord('bob', aliceTrust.enrollment),
        ],
        now: DateTime.utc(2026, 8, 25, 12),
        oneTime: true,
        messageId: messageId,
        attachments: [descriptor],
      );
      gateway.store(envelope, deliveredTo: 'bob');
      final controller = WampAppController(
        gateway: gateway,
        trustStore: FakeDeviceTrustStore(
          initialMessages: [
            LocalChatMessage(
              messageId: messageId,
              conversationId: envelope.conversationId,
              peerUsername: 'alice',
              text: 'Open this attachment once.',
              sentAt: envelope.createdAt,
              outgoing: false,
              oneTime: true,
              attachments: [descriptor],
            ),
          ],
        ),
        attachmentCache: consumerCache,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'bob',
        password: 'correct horse battery',
      );

      final opened = await controller.consumeOneTimeMessage(messageId);

      expect(opened?.text, 'Open this attachment once.');
      expect(opened?.attachments, [descriptor]);
      expect(gateway.consumeAttempts, hasLength(1));
      expect(gateway.attachmentChunks, isEmpty);
      expect(
        gateway.attachmentGetAttempts,
        List<int>.generate(descriptor.chunkCount, (index) => index),
      );
      expect(controller.messages, isEmpty);
      final bytes = await controller.loadOpenedOneTimeAttachment(
        message: opened!,
        attachmentId: descriptor.attachmentId,
      );
      expect(bytes, plaintext);
      bytes!.fillRange(0, bytes.length, 0);
      expect(gateway.attachmentGetAttempts, hasLength(descriptor.chunkCount));

      await controller.closeOpenedOneTimeMessage(opened);

      expect(opened.attachments, isEmpty);
      expect(
        await controller.loadOpenedOneTimeAttachment(
          message: opened,
          attachmentId: descriptor.attachmentId,
        ),
        isNull,
      );
      expect(
        await consumerCache.get(
          scope: attachmentCacheScope(controller.connection!.endpoint, 'bob'),
          senderUsername: 'alice',
          messageId: messageId,
          attachmentId: descriptor.attachmentId,
          chunkIndex: 0,
          chunkCount: descriptor.chunkCount,
        ),
        isNull,
      );
    },
  );

  test('view-once attachment prefetch failure does not consume', () async {
    const messageId = 'incomplete-view-once-attachment';
    final descriptor = EncryptedAttachmentDescriptor(
      attachmentId: 'incomplete-view-once-attachment-id',
      name: 'missing.bin',
      contentType: 'application/octet-stream',
      kind: ChatAttachmentKind.file,
      plaintextBytes: 1,
      plaintextSha256: sha256.convert(const [1]).toString(),
      chunkBytes: 1,
      chunkCount: 1,
      key: Uint8List(32),
    );
    final gateway = _OutboxGateway();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: FakeDeviceTrustStore(
        initialMessages: [
          LocalChatMessage(
            messageId: messageId,
            conversationId: 'alice-bob',
            peerUsername: 'alice',
            text: '',
            sentAt: DateTime.utc(2026, 8, 25, 12),
            outgoing: false,
            oneTime: true,
            attachments: [descriptor],
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'bob',
      password: 'correct horse battery',
    );

    expect(await controller.consumeOneTimeMessage(messageId), isNull);
    expect(gateway.consumeAttempts, isEmpty);
    expect(controller.messages.single.messageId, messageId);
  });

  test('message conflicts are terminal until explicitly discarded', () async {
    final gateway = _OutboxGateway()
      ..nextFailureKind = MessageSendFailureKind.conflict;
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];

    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'conflicting message',
      ),
      isTrue,
    );
    final messageId = controller.messages.single.messageId;
    expect(
      controller.outboundMessageFor(messageId)?.state,
      OutboundMessageState.conflict,
    );
    expect(await controller.retryMessage(messageId), isFalse);
    expect(gateway.attempts, hasLength(1));

    expect(await controller.discardOutboundMessage(messageId), isTrue);
    expect(controller.messages, isEmpty);
    expect(trustStore.session!.outbox, isEmpty);
  });

  test('mailbox envelope mismatch becomes a terminal conflict', () async {
    final gateway = _OutboxGateway()..failBeforeAccept = true;
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];
    expect(
      await controller.sendMessage(
        recipientUsername: 'bob',
        text: 'retain local plaintext',
      ),
      isTrue,
    );
    final original = gateway.attempts.single;
    final changedPayload = Uint8List.fromList(original.encryptedPayload);
    changedPayload[0] ^= 1;
    final conflicting = EncryptedChatMessage(
      messageId: original.messageId,
      conversationId: original.conversationId,
      senderUsername: original.senderUsername,
      senderDeviceId: original.senderDeviceId,
      recipientUsername: original.recipientUsername!,
      createdAt: original.createdAt,
      encryptedPayload: changedPayload,
      wrappedKeys: original.wrappedKeys,
      oneTime: original.oneTime,
      expiresAt: original.expiresAt,
    );
    gateway.store(conflicting);

    await controller.refreshMessages();

    expect(controller.messages.single.text, 'retain local plaintext');
    expect(
      controller.outboundMessageFor(original.messageId)?.state,
      OutboundMessageState.conflict,
    );
    expect(await controller.retryMessage(original.messageId), isFalse);
    expect(gateway.attempts, hasLength(1));
  });

  test('reconnect does not retry a terminal message conflict', () async {
    final gateway = _OutboxGateway()
      ..nextFailureKind = MessageSendFailureKind.conflict;
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];
    await controller.sendMessage(
      recipientUsername: 'bob',
      text: 'do not retry automatically',
    );
    final messageId = gateway.attempts.single.messageId;

    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );

    expect(gateway.attempts, hasLength(1));
    expect(
      controller.outboundMessageFor(messageId)?.state,
      OutboundMessageState.conflict,
    );
    expect(controller.messages.single.messageId, messageId);
  });

  test('sign out fences a late send response from the old session', () async {
    final gateway = _OutboxGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    gateway.deviceDirectories['bob'] = [
      activeDeviceRecord('bob', trustStore.session!.enrollment),
    ];
    final blocked = gateway.blockNextSend();
    final sending = controller.sendMessage(
      recipientUsername: 'bob',
      text: 'late response',
    );
    await _waitFor(() => gateway.attempts.isNotEmpty);
    final oldSession = trustStore.session!;

    await controller.signOut();
    blocked.complete(
      MessageSendReceipt(
        messageId: gateway.attempts.single.messageId,
        cursor: 1,
        acceptedAt: DateTime.utc(2026, 8, 25, 12),
        duplicate: false,
      ),
    );

    expect(await sending, isTrue);
    expect(controller.status, WampAppStatus.signedOut);
    expect(controller.messageBusy, isFalse);
    expect(controller.messageError, isNull);
    expect(oldSession.outbox.single.state, OutboundMessageState.queued);
    expect(oldSession.outbox.single.attemptCount, 1);
  });

  test(
    'reconnect retries a transient outbox entry once with the same id',
    () async {
      final gateway = _OutboxGateway()..failBeforeAccept = true;
      final trustStore = FakeDeviceTrustStore();
      final controller = WampAppController(
        gateway: gateway,
        trustStore: trustStore,
      );
      addTearDown(controller.dispose);
      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );
      gateway.deviceDirectories['bob'] = [
        activeDeviceRecord('bob', trustStore.session!.enrollment),
      ];
      expect(
        await controller.sendMessage(
          recipientUsername: 'bob',
          text: 'recover after reconnect',
        ),
        isTrue,
      );
      final firstWire = jsonEncode(gateway.attempts.single.toJson());

      await controller.login(
        serverAddress: 'ws://localhost:8080',
        username: 'alice',
        password: 'correct horse battery',
      );

      expect(gateway.attempts, hasLength(2));
      expect(jsonEncode(gateway.attempts.last.toJson()), firstWire);
      expect(controller.messages, hasLength(1));
      expect(trustStore.session!.outbox, isEmpty);
    },
  );

  test('creates and atomically sends an encrypted group envelope', () async {
    final gateway = _RecordingGateway();
    final trustStore = FakeDeviceTrustStore();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final enrollment = trustStore.session!.enrollment;
    gateway.deviceDirectories['bob'] = [activeDeviceRecord('bob', enrollment)];
    gateway.deviceDirectories['carol'] = [
      activeDeviceRecord('carol', enrollment),
    ];

    final group = await controller.createGroup(
      title: ' Launch crew ',
      memberUsernames: const [' Carol ', 'bob'],
    );
    expect(group, isNotNull);
    expect(group!.title, 'Launch crew');
    expect(group.memberUsernames, ['alice', 'bob', 'carol']);
    expect(controller.groups.single.hasSameDefinition(group), isTrue);
    expect(
      await controller.setConversationDisappearingMessages(
        group.conversationId,
        const Duration(days: 7),
      ),
      isTrue,
    );

    await controller.sendGroupMessage(
      groupId: group.conversationId,
      text: 'one atomic message',
    );

    expect(gateway.sentMessages, hasLength(1));
    expect(gateway.sentMessages.single.isGroup, isTrue);
    expect(gateway.sentMessages.single.participantUsernames, [
      'alice',
      'bob',
      'carol',
    ]);
    expect(gateway.sentMessages.single.wrappedKeys, hasLength(3));
    expect(
      gateway.sentMessages.single.expiresAt!.difference(
        gateway.sentMessages.single.createdAt,
      ),
      const Duration(days: 7),
    );
    expect(controller.messageError, isNull);
  });

  test('uploads group attachments before the atomic group envelope', () async {
    final gateway = _OutboxGateway();
    final trustStore = FakeDeviceTrustStore();
    final cache = MemoryAttachmentChunkCache();
    final controller = WampAppController(
      gateway: gateway,
      trustStore: trustStore,
      attachmentCache: cache,
    );
    addTearDown(controller.dispose);
    await controller.login(
      serverAddress: 'ws://localhost:8080',
      username: 'alice',
      password: 'correct horse battery',
    );
    final enrollment = trustStore.session!.enrollment;
    gateway.deviceDirectories['bob'] = [activeDeviceRecord('bob', enrollment)];
    gateway.deviceDirectories['carol'] = [
      activeDeviceRecord('carol', enrollment),
    ];
    final group = await controller.createGroup(
      title: 'Field team',
      memberUsernames: const ['bob', 'carol'],
    );
    final plaintext = Uint8List.fromList(
      List<int>.generate(17000, (index) => (index * 31) % 256),
    );

    expect(
      await controller.sendGroupMessage(
        groupId: group!.conversationId,
        text: '',
        attachmentSources: [
          AttachmentPlaintextSource(
            name: 'field-map.png',
            contentType: 'image/png',
            kind: ChatAttachmentKind.image,
            byteCount: plaintext.length,
            openRead: () => Stream.value(plaintext),
          ),
        ],
      ),
      isTrue,
    );

    expect(gateway.operations, ['put:0', 'send']);
    final envelope = gateway.attempts.single;
    expect(envelope.isGroup, isTrue);
    expect(envelope.participantUsernames, ['alice', 'bob', 'carol']);
    expect(envelope.attachmentIds, hasLength(1));
    expect(controller.messages.single.attachments.single.name, 'field-map.png');
    expect(controller.messageError, isNull);
  });
}

AccountProfile _profileFor(String username) => AccountProfile(
  username: AccountRegistration.normalizeUsername(username),
  displayName: 'Alice Example',
  status: '',
  revision: 0,
  updatedAt: DateTime.utc(2026, 8, 24),
);

class _RecordingGateway implements AccountGateway {
  _RecordingGateway({List<String>? operations})
    : operations = operations ?? <String>[];

  AccountRegistration? registered;
  String? loginPassword;
  bool closed = false;
  bool failNextClose = false;
  Completer<void>? closeGate;
  Object? loginFailure;
  Completer<AccountProfile>? profileUpdateGate;
  Completer<AccountProfile>? profileLookupGate;
  AccountProfile? profileLookupOverride;
  final List<String> profileLookups = [];
  WampAppMcpConsent mcpConsent = WampAppMcpConsent.denied;
  Object? nextMcpConsentFailure;
  final List<bool> mcpConsentUpdates = [];
  final List<_GatewayConnection> connections = [];
  final Map<String, List<DeviceRecord>> deviceDirectories = {};
  final List<EncryptedChatMessage> sentMessages = [];
  final List<String> operations;
  final List<PlatformPushSubscriptionRequest> pushRegistrations = [];
  final List<PlatformPushSubscriptionKey> pushUnregistrations = [];
  BackupUploadRequest? backupRequest;
  final List<Uint8List> backupChunks = [];
  BackupMetadata? remoteMetadata;
  Uint8List? remoteBackup;

  void seedRemoteBackup(Uint8List archive) {
    remoteBackup = Uint8List.fromList(archive);
    remoteMetadata = BackupMetadata(
      revision: 1,
      byteCount: archive.length,
      chunkCount:
          (archive.length + WampAppBackupTransferLimits.chunkBytes - 1) ~/
          WampAppBackupTransferLimits.chunkBytes,
      sha256: sha256.convert(archive).toString(),
      updatedAt: DateTime.utc(2026, 8, 25),
    );
  }

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) async {
    registered = registration;
    return RegistrationReceipt(
      username: registration.username,
      displayName: registration.displayName,
      createdAt: DateTime.utc(2026, 8, 24),
    );
  }

  @override
  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  }) async {
    loginPassword = password;
    final loginFailure = this.loginFailure;
    if (loginFailure != null) throw loginFailure;
    final connection = _GatewayConnection()..serverCursor = 0;
    connections.add(connection);
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    return AccountConnection(
      endpoint: endpoint,
      username: normalizedUsername,
      initialProfile: _profileFor(normalizedUsername),
      initialMcpConsent: mcpConsent,
      getProfileCallback: (username) async {
        final normalized = AccountRegistration.normalizeUsername(username);
        profileLookups.add(normalized);
        final gate = profileLookupGate;
        if (gate != null) return gate.future;
        return profileLookupOverride ?? _profileFor(normalized);
      },
      getMcpConsentCallback: () async => mcpConsent,
      updateMcpConsentCallback: (update) async {
        final failure = nextMcpConsentFailure;
        nextMcpConsentFailure = null;
        if (failure != null) throw failure;
        if (update.expectedRevision != mcpConsent.revision) {
          throw const McpConsentException(McpConsentFailureKind.conflict);
        }
        mcpConsentUpdates.add(update.profileReadAllowed);
        mcpConsent = WampAppMcpConsent(
          profileReadAllowed: update.profileReadAllowed,
          revision: update.expectedRevision + 1,
          updatedAt: DateTime.utc(2026, 8, 25),
        );
        return mcpConsent;
      },
      updateProfileCallback: (update) async {
        final gate = profileUpdateGate;
        if (gate != null) return gate.future;
        return AccountProfile(
          username: normalizedUsername,
          displayName: update.displayName,
          status: update.status,
          revision: update.expectedRevision + 1,
          updatedAt: DateTime.utc(2026, 8, 25),
          avatarBytes: update.avatarBytes,
          avatarContentType: update.avatarContentType,
        );
      },
      enrollDeviceCallback: (enrollment) async {
        operations.add('enroll');
        final record = activeDeviceRecord(normalizedUsername, enrollment);
        deviceDirectories[normalizedUsername] = [record];
        return record;
      },
      listDevicesCallback: (_) async =>
          DeviceDirectory(deviceDirectories[normalizedUsername] ?? const []),
      lookupDevicesCallback: (lookupUsername, _) async => DeviceDirectory(
        deviceDirectories[AccountRegistration.normalizeUsername(
              lookupUsername,
            )] ??
            const [],
      ),
      revokeDeviceCallback: (_) => throw UnimplementedError(),
      sendMessageCallback: (message) async {
        sentMessages.add(message);
        connection.serverCursor += 1;
        return MessageSendReceipt(
          messageId: message.messageId,
          cursor: connection.serverCursor,
          acceptedAt: DateTime.utc(2026, 8, 24, 12),
          duplicate: false,
        );
      },
      syncMessagesCallback: connection.sync,
      markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
      consumeOneTimeCallback: connection.consume,
      registerPlatformPushCallback: (request) async {
        operations.add('push-register');
        pushRegistrations.add(request);
        return PlatformPushSubscriptionReceipt(
          deviceId: request.deviceId,
          provider: request.provider,
          registeredAt: DateTime.utc(2026, 8, 25),
          updatedAt: DateTime.utc(2026, 8, 25),
        );
      },
      unregisterPlatformPushCallback: (key) async {
        operations.add('push-unregister');
        pushUnregistrations.add(key);
        return true;
      },
      beginBackupUploadCallback: (request) async {
        operations.add('backup-begin');
        backupRequest = request;
        backupChunks.clear();
        return BackupUploadSession(
          uploadId: 'abcdefghijklmnop',
          expectedRevision: request.expectedRevision,
        );
      },
      putBackupChunkCallback: (chunk) async {
        operations.add('backup-put:${chunk.chunkIndex}');
        backupChunks.add(chunk.bytes);
      },
      commitBackupUploadCallback: (_) async {
        operations.add('backup-commit');
        final request = backupRequest!;
        final builder = BytesBuilder(copy: false);
        for (final chunk in backupChunks) {
          builder.add(chunk);
        }
        final archive = builder.takeBytes();
        remoteBackup = archive;
        return remoteMetadata = BackupMetadata(
          revision: request.expectedRevision + 1,
          byteCount: request.byteCount,
          chunkCount: request.chunkCount,
          sha256: request.sha256,
          updatedAt: DateTime.utc(2026, 8, 25),
        );
      },
      getBackupMetadataCallback: () async {
        operations.add('backup-metadata');
        return remoteMetadata;
      },
      getBackupChunkCallback: (revision, chunkIndex) async {
        operations.add('backup-chunk:$chunkIndex');
        final archive = remoteBackup!;
        final start = chunkIndex * WampAppBackupTransferLimits.chunkBytes;
        final end = (start + WampAppBackupTransferLimits.chunkBytes).clamp(
          0,
          archive.length,
        );
        return EncryptedBackupDownloadChunk(
          revision: revision,
          chunkIndex: chunkIndex,
          bytes: Uint8List.sublistView(archive, start, end),
        );
      },
      deleteBackupCallback: (expectedRevision) async {
        operations.add('backup-delete');
        if (remoteMetadata?.revision != expectedRevision) return false;
        remoteMetadata = null;
        remoteBackup = null;
        return true;
      },
      mailboxWakeups: connection.wakeups.stream,
      latestMailboxWakeupCursorCallback: () => connection.latestWakeupCursor,
      latestMailboxWakeupErrorCallback: () => null,
      closeTransport: () async {
        operations.add('transport-close');
        await closeGate?.future;
        closed = true;
        if (failNextClose) {
          failNextClose = false;
          throw StateError('old transport already failed');
        }
      },
    );
  }
}

final class _ControllerTokenSource implements PlatformPushTokenSource {
  _ControllerTokenSource(this.operations);

  final List<String> operations;
  final List<_ControllerTokenSession> _sessions = [];
  Object? openFailure;
  bool disposed = false;

  _ControllerTokenSession addSession() {
    final session = _ControllerTokenSession();
    _sessions.add(session);
    return session;
  }

  @override
  Future<PlatformPushTokenSession?> open() async {
    operations.add('token-open');
    final failure = openFailure;
    if (failure != null) throw failure;
    return _sessions.isEmpty ? null : _sessions.removeAt(0);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    for (final session in _sessions) {
      await session.close();
    }
    _sessions.clear();
  }
}

final class _ControllerTokenSession implements PlatformPushTokenSession {
  final _tokens = StreamController<PlatformPushToken>();
  bool closed = false;

  @override
  Stream<PlatformPushToken> get tokens => _tokens.stream;

  void emit(PlatformPushToken token) {
    if (!closed) _tokens.add(token);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _tokens.close();
  }
}

final class _OutboxGateway implements AccountGateway {
  final Map<String, List<DeviceRecord>> deviceDirectories = {};
  final List<EncryptedChatMessage> attempts = [];
  final List<MailboxMessage> _mailbox = [];
  bool acceptThenTimeout = false;
  bool failBeforeAccept = false;
  MessageSendFailureKind? nextFailureKind;
  int _cursor = 0;
  Completer<MessageSendReceipt>? _sendGate;
  final Map<String, EncryptedAttachmentChunk> attachmentChunks = {};
  final List<int> attachmentPutAttempts = [];
  final List<int> attachmentGetAttempts = [];
  final List<OneTimeMessageConsumption> consumeAttempts = [];
  final List<String> operations = [];
  int? failAfterStoredChunkIndex;

  Completer<MessageSendReceipt> blockNextSend() =>
      _sendGate = Completer<MessageSendReceipt>();

  void store(EncryptedChatMessage message, {String? deliveredTo}) {
    _cursor += 1;
    _mailbox.add(
      MailboxMessage(
        cursor: _cursor,
        message: message,
        acceptedAt: DateTime.utc(2026, 8, 25, 12, _cursor),
        recipientStates: deliveredTo == null
            ? const {}
            : {
                deliveredTo: MailboxRecipientState(
                  deliveredAt: DateTime.utc(2026, 8, 25, 12, _cursor),
                ),
              },
      ),
    );
  }

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  }) async {
    final normalized = AccountRegistration.normalizeUsername(username);
    return AccountConnection(
      endpoint: endpoint,
      username: normalized,
      initialProfile: _profileFor(normalized),
      getProfileCallback: (username) async => _profileFor(username),
      updateProfileCallback: (update) async => AccountProfile(
        username: normalized,
        displayName: update.displayName,
        status: update.status,
        revision: update.expectedRevision + 1,
        updatedAt: DateTime.utc(2026, 8, 25),
        avatarBytes: update.avatarBytes,
        avatarContentType: update.avatarContentType,
      ),
      enrollDeviceCallback: (enrollment) async {
        final device = activeDeviceRecord(normalized, enrollment);
        deviceDirectories[normalized] = [device];
        return device;
      },
      listDevicesCallback: (_) async =>
          DeviceDirectory(deviceDirectories[normalized] ?? const []),
      lookupDevicesCallback: (lookup, _) async => DeviceDirectory(
        deviceDirectories[AccountRegistration.normalizeUsername(lookup)] ??
            const [],
      ),
      revokeDeviceCallback: (_) => throw UnimplementedError(),
      sendMessageCallback: _send,
      putAttachmentChunkCallback: _putAttachmentChunk,
      attachmentUploadStatusCallback: _attachmentStatus,
      getAttachmentChunkCallback: _getAttachmentChunk,
      syncMessagesCallback: (afterCursor, limit) async {
        final messages = _mailbox
            .where((message) => message.cursor > afterCursor)
            .take(limit)
            .toList(growable: false);
        return MailboxBatch(nextCursor: _cursor, messages: messages);
      },
      markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
      consumeOneTimeCallback: _consumeOneTime,
      mailboxWakeups: const Stream<MailboxWakeup>.empty(),
      latestMailboxWakeupCursorCallback: () => 0,
      latestMailboxWakeupErrorCallback: () => null,
      closeTransport: () async {},
    );
  }

  Future<MessageSendReceipt> _send(EncryptedChatMessage message) async {
    operations.add('send');
    attempts.add(message);
    final sendGate = _sendGate;
    _sendGate = null;
    if (sendGate != null) return sendGate.future;
    final failureKind = nextFailureKind;
    nextFailureKind = null;
    if (failureKind != null) throw MessageSendException(failureKind);
    if (failBeforeAccept) {
      failBeforeAccept = false;
      throw TimeoutException('send response was not available');
    }
    final existing = _mailbox
        .where((stored) => stored.message.messageId == message.messageId)
        .firstOrNull;
    if (existing != null) {
      if (jsonEncode(existing.message.toJson()) !=
          jsonEncode(message.toJson())) {
        throw const MessageSendException(MessageSendFailureKind.conflict);
      }
      return MessageSendReceipt(
        messageId: message.messageId,
        cursor: existing.cursor,
        acceptedAt: existing.acceptedAt,
        duplicate: true,
      );
    }
    _cursor += 1;
    final acceptedAt = DateTime.utc(2026, 8, 25, 12, _cursor);
    _mailbox.add(
      MailboxMessage(cursor: _cursor, message: message, acceptedAt: acceptedAt),
    );
    if (acceptThenTimeout) {
      acceptThenTimeout = false;
      throw TimeoutException('accepted reply was lost');
    }
    return MessageSendReceipt(
      messageId: message.messageId,
      cursor: _cursor,
      acceptedAt: acceptedAt,
      duplicate: false,
    );
  }

  Future<AttachmentChunkReceipt> _putAttachmentChunk(
    EncryptedAttachmentChunk chunk,
  ) async {
    attachmentPutAttempts.add(chunk.chunkIndex);
    operations.add('put:${chunk.chunkIndex}');
    final key = _attachmentKey(
      chunk.messageId,
      chunk.attachmentId,
      chunk.chunkIndex,
    );
    final existing = attachmentChunks[key];
    if (existing != null &&
        jsonEncode(existing.toWampKeywords()) !=
            jsonEncode(chunk.toWampKeywords())) {
      throw const AttachmentTransferException(
        AttachmentTransferFailureKind.conflict,
      );
    }
    attachmentChunks[key] = chunk;
    final duplicate = existing != null;
    if (failAfterStoredChunkIndex == chunk.chunkIndex) {
      failAfterStoredChunkIndex = null;
      throw TimeoutException('attachment reply was lost');
    }
    final complete =
        attachmentChunks.values
            .where(
              (candidate) =>
                  candidate.messageId == chunk.messageId &&
                  candidate.attachmentId == chunk.attachmentId,
            )
            .length ==
        chunk.chunkCount;
    return AttachmentChunkReceipt(
      messageId: chunk.messageId,
      attachmentId: chunk.attachmentId,
      chunkIndex: chunk.chunkIndex,
      ciphertextSha256: chunk.ciphertextSha256,
      duplicate: duplicate,
      complete: complete,
    );
  }

  Future<AttachmentUploadStatus> _attachmentStatus(
    String messageId,
    String attachmentId,
    int chunkCount,
  ) async {
    final received =
        attachmentChunks.values
            .where(
              (chunk) =>
                  chunk.messageId == messageId &&
                  chunk.attachmentId == attachmentId,
            )
            .map((chunk) => chunk.chunkIndex)
            .toList(growable: false)
          ..sort();
    return AttachmentUploadStatus(
      messageId: messageId,
      attachmentId: attachmentId,
      chunkCount: chunkCount,
      receivedChunks: received,
    );
  }

  Future<EncryptedAttachmentChunk> _getAttachmentChunk(
    String messageId,
    String attachmentId,
    int chunkIndex,
  ) async {
    attachmentGetAttempts.add(chunkIndex);
    final chunk =
        attachmentChunks[_attachmentKey(messageId, attachmentId, chunkIndex)];
    if (chunk == null) {
      throw const AttachmentTransferException(
        AttachmentTransferFailureKind.notFound,
      );
    }
    return chunk;
  }

  Future<MessageReceipt> _consumeOneTime(
    OneTimeMessageConsumption consumption,
  ) async {
    consumeAttempts.add(consumption);
    final existing = _mailbox.reversed
        .where((stored) => stored.message.messageId == consumption.messageId)
        .firstOrNull;
    if (existing == null) throw StateError('Message was not found.');
    final recipient = existing.message.recipientUsername!;
    final current = existing.recipientStateFor(recipient);
    if (current?.consumedAt != null) {
      if (current?.consumedByDeviceId != consumption.deviceId) {
        throw StateError('Message was consumed by another device.');
      }
      return MessageReceipt(
        messageId: consumption.messageId,
        cursor: existing.cursor,
        deliveredAt: current?.deliveredAt,
        readAt: current?.readAt,
        consumedAt: current?.consumedAt,
      );
    }
    final consumedAt = DateTime.utc(2026, 8, 25, 12, 30);
    final states = Map<String, MailboxRecipientState>.of(
      existing.recipientStates,
    );
    states[recipient] = MailboxRecipientState(
      deliveredAt: current?.deliveredAt ?? consumedAt,
      readAt: consumedAt,
      consumedAt: consumedAt,
      consumedByDeviceId: consumption.deviceId,
    );
    _cursor += 1;
    final updated = MailboxMessage(
      cursor: _cursor,
      message: existing.message,
      acceptedAt: existing.acceptedAt,
      recipientStates: states,
    );
    _mailbox.add(updated);
    attachmentChunks.removeWhere(
      (key, _) => key.startsWith('${consumption.messageId}\n'),
    );
    return MessageReceipt(
      messageId: consumption.messageId,
      cursor: updated.cursor,
      deliveredAt: consumedAt,
      readAt: consumedAt,
      consumedAt: consumedAt,
    );
  }

  String _attachmentKey(
    String messageId,
    String attachmentId,
    int chunkIndex,
  ) => '$messageId\n$attachmentId\n$chunkIndex';
}

final class _GatewayConnection {
  final StreamController<MailboxWakeup> wakeups =
      StreamController<MailboxWakeup>.broadcast(sync: true);
  final List<int> syncAfterCursors = [];
  int latestWakeupCursor = 0;
  int serverCursor = 0;
  final List<OneTimeMessageConsumption> consumeCalls = [];
  Completer<void>? _syncGate;
  Completer<MessageReceipt>? _consumeGate;

  Completer<void> blockNextSync() => _syncGate = Completer<void>();

  Completer<MessageReceipt> blockNextConsume() =>
      _consumeGate = Completer<MessageReceipt>();

  Future<MailboxBatch> sync(int afterCursor, int _) async {
    syncAfterCursors.add(afterCursor);
    final cursor = serverCursor;
    final gate = _syncGate;
    _syncGate = null;
    await gate?.future;
    return MailboxBatch(nextCursor: cursor, messages: const []);
  }

  Future<MessageReceipt> consume(OneTimeMessageConsumption consumption) {
    consumeCalls.add(consumption);
    final gate = _consumeGate;
    _consumeGate = null;
    if (gate == null) throw StateError('No consume response was configured.');
    return gate.future;
  }

  void emitWakeup(int cursor) {
    serverCursor = cursor > serverCursor ? cursor : serverCursor;
    latestWakeupCursor = cursor > latestWakeupCursor
        ? cursor
        : latestWakeupCursor;
    wakeups.add(MailboxWakeup(cursor: cursor));
  }

  void emitError(Object error) => wakeups.addError(error);
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
