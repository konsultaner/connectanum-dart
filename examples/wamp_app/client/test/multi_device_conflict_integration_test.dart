import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/wamp_app_controller.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache.dart';
import 'package:wamp_app/src/infrastructure/attachment_cipher.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/vault_storage.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  test(
    'six live devices converge and fail closed under competing writes',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'wamp-app-multi-device-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final messageStorePath = '${temporary.path}/messages.json';
      final server = await WampAppServer.start(
        WampAppServerConfig(
          host: '127.0.0.1',
          port: 0,
          websocketPath: '/ws',
          accountStorePath: '${temporary.path}/accounts.json',
          messageStorePath: messageStorePath,
          backupStorePath: '${temporary.path}/backups',
          argonIterations: 1,
          argonMemoryKiB: 8192,
        ),
      );
      addTearDown(server.close);

      final prefetchBarrier = _AsyncBarrier(3);
      final aliceCaches = List<AttachmentChunkCache>.generate(
        3,
        (_) => MemoryAttachmentChunkCache(),
      );
      final bobCaches = List<_PrefetchBarrierCache>.generate(
        3,
        (_) => _PrefetchBarrierCache(prefetchBarrier),
      );
      final alice = [
        _controller('Alice phone', attachmentCache: aliceCaches[0]),
        _controller('Alice tablet', attachmentCache: aliceCaches[1]),
        _controller('Alice desktop', attachmentCache: aliceCaches[2]),
      ];
      final bob = [
        _controller('Bob phone', attachmentCache: bobCaches[0]),
        _controller('Bob tablet', attachmentCache: bobCaches[1]),
        _controller('Bob desktop', attachmentCache: bobCaches[2]),
      ];
      final controllers = [...alice, ...bob];
      for (final controller in controllers) {
        addTearDown(controller.dispose);
      }
      final address = server.websocketUri.toString();

      await alice.first.registerAndConnect(
        serverAddress: address,
        username: 'alice',
        displayName: 'Alice Example',
        password: 'alice multi device secret',
      );
      await bob.first.registerAndConnect(
        serverAddress: address,
        username: 'bob',
        displayName: 'Bob Example',
        password: 'bob multi device secret',
      );
      await Future.wait([
        for (final controller in alice.skip(1))
          controller.login(
            serverAddress: address,
            username: 'alice',
            password: 'alice multi device secret',
          ),
        for (final controller in bob.skip(1))
          controller.login(
            serverAddress: address,
            username: 'bob',
            password: 'bob multi device secret',
          ),
      ]);

      expect(
        controllers.map((controller) => controller.status),
        everyElement(WampAppStatus.connected),
      );
      expect(
        (await alice.first.connection!.listDevices()).devices,
        hasLength(3),
      );
      expect((await bob.first.connection!.listDevices()).devices, hasLength(3));

      const rounds = 8;
      final expectedTexts = <String>{};
      for (var round = 0; round < rounds; round += 1) {
        await _waitFor(
          () => controllers.every((entry) => !entry.messageBusy),
          description: 'idle before message round $round',
          details: () => _controllerDetails(controllers),
        );
        final sends = <Future<bool>>[];
        for (var index = 0; index < alice.length; index += 1) {
          final text = 'alice-device-$index-round-$round';
          expectedTexts.add(text);
          sends.add(
            alice[index].sendMessage(recipientUsername: 'bob', text: text),
          );
        }
        for (var index = 0; index < bob.length; index += 1) {
          final text = 'bob-device-$index-round-$round';
          expectedTexts.add(text);
          sends.add(
            bob[index].sendMessage(recipientUsername: 'alice', text: text),
          );
        }
        expect(await Future.wait(sends), everyElement(isTrue));
      }

      await _waitFor(
        () =>
            controllers.every((entry) => !entry.messageBusy) &&
            controllers.every(
              (entry) => entry.messages.length == expectedTexts.length,
            ),
        timeout: const Duration(seconds: 45),
        description: 'all encrypted messages on every device',
        details: () => _controllerDetails(controllers),
      );
      final canonicalIds = alice.first.messages
          .map((message) => message.messageId)
          .toSet();
      expect(canonicalIds, hasLength(expectedTexts.length));
      for (final controller in controllers) {
        expect(controller.messageError, isNull);
        expect(
          controller.messages.map((message) => message.text).toSet(),
          expectedTexts,
        );
        expect(
          controller.messages.map((message) => message.messageId).toSet(),
          canonicalIds,
        );
      }

      final mailbox = MailboxStore(messageStorePath);
      final stored = await mailbox.sync('alice', afterCursor: 0, limit: 500);
      final storedCursors = stored.messages
          .map((message) => message.cursor)
          .toList(growable: false);
      expect(storedCursors, orderedEquals([...storedCursors]..sort()));
      expect(storedCursors.toSet(), hasLength(storedCursors.length));
      expect(
        stored.messages.map((message) => message.message.messageId).toSet(),
        canonicalIds,
      );

      final readTarget = bob.first.messages.firstWhere(
        (message) => !message.outgoing,
      );
      await _waitFor(
        () => bob.every((entry) => !entry.messageBusy),
        description: 'Bob devices idle before read race',
        details: () => _controllerDetails(bob),
      );
      await Future.wait([
        for (final controller in bob)
          controller.markMessageRead(readTarget.messageId),
      ]);
      await _waitFor(
        () => alice.every(
          (controller) =>
              controller.messages
                  .firstWhere(
                    (message) => message.messageId == readTarget.messageId,
                  )
                  .readAt !=
              null,
        ),
        description: 'read receipt on every Alice device',
        details: () => _controllerDetails(alice),
      );

      const oneTimeText = 'only one Bob device may open this';
      final oneTimeBytes = Uint8List.fromList(
        List<int>.generate(4096, (index) => (index * 29) & 0xff),
      );
      await _waitFor(
        () => controllers.every((entry) => !entry.messageBusy),
        description: 'all devices idle before one-time send',
        details: () => _controllerDetails(controllers),
      );
      expect(
        await alice.first.sendMessage(
          recipientUsername: 'bob',
          text: oneTimeText,
          oneTime: true,
          attachmentSources: [
            AttachmentPlaintextSource(
              name: 'view-once.bin',
              contentType: 'application/octet-stream',
              kind: ChatAttachmentKind.file,
              byteCount: oneTimeBytes.length,
              openRead: () => Stream.value(oneTimeBytes),
            ),
          ],
        ),
        isTrue,
      );
      final oneTimeId = alice.first.messages
          .firstWhere((message) => message.text == oneTimeText)
          .messageId;
      await _waitFor(
        () => bob.every(
          (controller) => controller.messages.any(
            (message) => message.messageId == oneTimeId,
          ),
        ),
        description: 'one-time message on every Bob device',
        details: () => _controllerDetails(bob),
      );
      final oneTimeAttachment = bob.first.messages
          .singleWhere((message) => message.messageId == oneTimeId)
          .attachments
          .single;
      await _waitFor(
        () => bob.every((entry) => !entry.messageBusy),
        description: 'Bob devices idle before one-time race',
        details: () => _controllerDetails(bob),
      );
      final openings = await Future.wait([
        for (final controller in bob)
          controller.consumeOneTimeMessage(oneTimeId),
      ]);
      expect(
        openings.where((message) => message?.text == oneTimeText),
        hasLength(1),
      );
      expect(openings.where((message) => message == null), hasLength(2));
      expect(prefetchBarrier.arrivals, 3);
      final winnerIndex = openings.indexWhere((message) => message != null);
      for (var index = 0; index < bob.length; index += 1) {
        final cached = await bobCaches[index].get(
          scope: attachmentCacheScope(bob[index].connection!.endpoint, 'bob'),
          senderUsername: 'alice',
          messageId: oneTimeId,
          attachmentId: oneTimeAttachment.attachmentId,
          chunkIndex: 0,
          chunkCount: oneTimeAttachment.chunkCount,
        );
        expect(cached, index == winnerIndex ? isNotNull : isNull);
      }
      await _waitFor(
        () => bob.every(
          (controller) => controller.messages.every(
            (message) => message.messageId != oneTimeId,
          ),
        ),
        description: 'one-time removal from every Bob device',
        details: () => _controllerDetails(bob),
      );
      await bob[winnerIndex].closeOpenedOneTimeMessage(openings[winnerIndex]!);
      for (var index = 0; index < bob.length; index += 1) {
        expect(
          await bobCaches[index].get(
            scope: attachmentCacheScope(bob[index].connection!.endpoint, 'bob'),
            senderUsername: 'alice',
            messageId: oneTimeId,
            attachmentId: oneTimeAttachment.attachmentId,
            chunkIndex: 0,
            chunkCount: oneTimeAttachment.chunkCount,
          ),
          isNull,
        );
      }

      final profileRevision = alice.first.connection!.profile.revision;
      final profileUpdates = await Future.wait([
        for (var index = 0; index < alice.length; index += 1)
          alice[index].updateProfile(
            AccountProfileUpdate(
              expectedRevision: profileRevision,
              displayName: 'Alice Example',
              status: 'device $index won',
            ),
          ),
      ]);
      expect(profileUpdates.where((updated) => updated), hasLength(1));
      expect(profileUpdates.where((updated) => !updated), hasLength(2));
      expect(
        alice.map((entry) => entry.connection!.profile.revision),
        everyElement(profileRevision + 1),
      );
      expect(
        alice.map((entry) => entry.connection!.profile.status).toSet(),
        hasLength(1),
      );
      for (var index = 0; index < alice.length; index += 1) {
        if (!profileUpdates[index]) {
          expect(
            alice[index].profileError,
            'The profile changed on another device. Review it and try again.',
          );
        }
      }

      final consentUpdates = await Future.wait([
        for (final controller in alice)
          controller.setMcpProfileReadAllowed(true),
      ]);
      expect(consentUpdates.where((updated) => updated), hasLength(1));
      expect(consentUpdates.where((updated) => !updated), hasLength(2));
      expect(
        alice.map((entry) => entry.connection!.mcpConsent.revision),
        everyElement(1),
      );
      expect(
        alice.map((entry) => entry.connection!.mcpConsent.profileReadAllowed),
        everyElement(isTrue),
      );
      for (var index = 0; index < alice.length; index += 1) {
        if (!consentUpdates[index]) {
          expect(
            alice[index].mcpConsentError,
            'MCP consent changed on another device. Review it and try again.',
          );
        }
      }

      final backupOutcomes = await Future.wait([
        for (var index = 0; index < alice.length; index += 1)
          _capture(
            () => alice[index].connection!.uploadRemoteBackup(
              Uint8List.fromList(
                List<int>.generate(8192, (offset) => (offset + index) & 0xff),
              ),
              expectedRevision: 0,
            ),
          ),
      ]);
      final committed = backupOutcomes.whereType<BackupMetadata>().single;
      final conflicts = backupOutcomes.whereType<RemoteBackupException>();
      expect(conflicts, hasLength(2));
      expect(
        conflicts.map((error) => error.kind),
        everyElement(RemoteBackupFailureKind.conflict),
      );
      final backupMetadata = await Future.wait([
        for (final controller in alice)
          controller.connection!.getRemoteBackupMetadata(),
      ]);
      expect(
        backupMetadata.map((metadata) => metadata?.revision),
        everyElement(1),
      );
      expect(
        backupMetadata.map((metadata) => metadata?.sha256),
        everyElement(committed.sha256),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

WampAppController _controller(
  String deviceName, {
  AttachmentChunkCache? attachmentCache,
}) {
  return WampAppController(
    trustStore: EncryptedDeviceVault(
      storage: _MemoryVaultStorage(),
      keyDeriver: const _TestKeyDeriver(),
      iterations: 1,
      memoryKiB: 64,
    ),
    attachmentCache: attachmentCache,
    deviceName: deviceName,
  );
}

final class _AsyncBarrier {
  _AsyncBarrier(this.participants);

  final int participants;
  final Completer<void> _release = Completer<void>();
  int arrivals = 0;

  Future<void> arrive() {
    arrivals += 1;
    if (arrivals == participants) _release.complete();
    if (arrivals > participants) {
      throw StateError(
        'Attachment prefetch barrier received too many arrivals.',
      );
    }
    return _release.future;
  }
}

final class _PrefetchBarrierCache implements AttachmentChunkCache {
  _PrefetchBarrierCache(this._barrier);

  final _AsyncBarrier _barrier;
  final MemoryAttachmentChunkCache _delegate = MemoryAttachmentChunkCache();

  @override
  Future<void> put({
    required String scope,
    required EncryptedAttachmentChunk chunk,
  }) async {
    await _delegate.put(scope: scope, chunk: chunk);
    await _barrier.arrive();
  }

  @override
  Future<EncryptedAttachmentChunk?> get({
    required String scope,
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
    required int chunkCount,
  }) => _delegate.get(
    scope: scope,
    senderUsername: senderUsername,
    messageId: messageId,
    attachmentId: attachmentId,
    chunkIndex: chunkIndex,
    chunkCount: chunkCount,
  );

  @override
  Future<void> removeMessage({
    required String scope,
    required String messageId,
  }) => _delegate.removeMessage(scope: scope, messageId: messageId);

  @override
  Future<void> dispose() => _delegate.dispose();
}

Future<void> _waitFor(
  bool Function() condition, {
  required String description,
  String Function()? details,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Multi-device state did not converge: $description. '
        '${details?.call() ?? ''}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

String _controllerDetails(List<WampAppController> controllers) {
  return controllers
      .map(
        (controller) =>
            '${controller.localDevice?.enrollment.deviceName ?? 'unknown'}:'
            'busy=${controller.messageBusy},messages=${controller.messages.length},'
            'error=${controller.messageError}',
      )
      .join('; ');
}

Future<Object> _capture(Future<Object> Function() action) async {
  try {
    return await action();
  } catch (error) {
    return error;
  }
}

final class _MemoryVaultStorage implements VaultStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

final class _TestKeyDeriver implements VaultKeyDeriver {
  const _TestKeyDeriver();

  @override
  Future<Uint8List> derive({
    required String password,
    required String salt,
    required int iterations,
    required int memoryKiB,
    required Duration timeout,
  }) async {
    return Uint8List.fromList(
      sha256.convert(utf8.encode('$password\n$salt')).bytes,
    );
  }
}
