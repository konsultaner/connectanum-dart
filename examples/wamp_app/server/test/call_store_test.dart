import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory directory;
  late CallStore store;
  final startedAt = DateTime.utc(2026, 8, 25, 10);
  final aliceDevice = _token(32, 1);
  final bobPhone = _token(32, 2);
  final bobTablet = _token(32, 3);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wamp-call-store-');
    store = CallStore('${directory.path}/calls.json');
    await store.initialize();
  });

  tearDown(() => directory.delete(recursive: true));

  CallStartRequest request({int callSeed = 10}) => CallStartRequest(
    media: CallMediaKind.video,
    calleeUsername: 'bob',
    offers: [
      _signal(
        callSeed: callSeed,
        signalSeed: 11,
        kind: CallSignalKind.offer,
        senderUsername: 'alice',
        senderDeviceId: aliceDevice,
        recipientUsername: 'bob',
        recipientDeviceId: bobPhone,
        createdAt: startedAt,
      ),
      _signal(
        callSeed: callSeed,
        signalSeed: 12,
        kind: CallSignalKind.offer,
        senderUsername: 'alice',
        senderDeviceId: aliceDevice,
        recipientUsername: 'bob',
        recipientDeviceId: bobTablet,
        createdAt: startedAt,
      ),
    ],
  );

  test('start is durable, idempotent, and conflict-safe', () async {
    final initial = request();
    final first = await store.start(initial, now: startedAt);
    final retry = await store.start(
      CallStartRequest.fromWampKeywords(initial.toWampKeywords()),
      now: startedAt.add(const Duration(seconds: 1)),
    );

    expect(first.duplicate, isFalse);
    expect(retry.duplicate, isTrue);
    expect(retry.update.cursor, first.update.cursor);
    final changed = request(callSeed: 10).toWampKeywords();
    (changed['offers'] as List).first['signal_id'] = _token(16, 99);
    expect(
      () => store.start(CallStartRequest.fromWampKeywords(changed)),
      throwsA(isA<CallConflict>()),
    );

    final reopened = CallStore(store.file.path);
    final batch = await reopened.sync(
      'bob',
      bobPhone,
      afterCursor: 0,
      now: startedAt,
    );
    expect(batch.updates.single.call.state, CallState.ringing);
    expect(batch.updates.single.signals.single.recipientDeviceId, bobPhone);
  });

  test('first answer wins atomically across callee devices', () async {
    await store.start(request(), now: startedAt);
    final phoneAnswer = _signal(
      callSeed: 10,
      signalSeed: 20,
      kind: CallSignalKind.answer,
      senderUsername: 'bob',
      senderDeviceId: bobPhone,
      recipientUsername: 'alice',
      recipientDeviceId: aliceDevice,
      createdAt: startedAt.add(const Duration(seconds: 2)),
    );
    final accepted = await store.accept(
      phoneAnswer,
      now: startedAt.add(const Duration(seconds: 2)),
    );
    final retry = await store.accept(
      EncryptedCallSignal.fromJson(phoneAnswer.toJson()),
      now: startedAt.add(const Duration(seconds: 3)),
    );
    final tabletAnswer = _signal(
      callSeed: 10,
      signalSeed: 21,
      kind: CallSignalKind.answer,
      senderUsername: 'bob',
      senderDeviceId: bobTablet,
      recipientUsername: 'alice',
      recipientDeviceId: aliceDevice,
      createdAt: startedAt.add(const Duration(seconds: 2)),
    );

    expect(accepted.update.call.state, CallState.active);
    expect(accepted.update.call.acceptedDeviceId, bobPhone);
    expect(retry.duplicate, isTrue);
    await expectLater(
      store.accept(tabletAnswer),
      throwsA(isA<CallAlreadyAnswered>()),
    );

    final sibling = await store.sync(
      'bob',
      bobTablet,
      afterCursor: 1,
      now: startedAt.add(const Duration(seconds: 3)),
    );
    expect(sibling.updates.single.call.acceptedDeviceId, bobPhone);
    expect(sibling.updates.single.signals, isEmpty);
  });

  test('only selected devices may exchange ICE or end active calls', () async {
    await store.start(request(), now: startedAt);
    await store.accept(
      _signal(
        callSeed: 10,
        signalSeed: 20,
        kind: CallSignalKind.answer,
        senderUsername: 'bob',
        senderDeviceId: bobPhone,
        recipientUsername: 'alice',
        recipientDeviceId: aliceDevice,
        createdAt: startedAt.add(const Duration(seconds: 2)),
      ),
      now: startedAt.add(const Duration(seconds: 2)),
    );
    final candidate = _signal(
      callSeed: 10,
      signalSeed: 30,
      kind: CallSignalKind.iceCandidate,
      senderUsername: 'alice',
      senderDeviceId: aliceDevice,
      recipientUsername: 'bob',
      recipientDeviceId: bobPhone,
      createdAt: startedAt.add(const Duration(seconds: 3)),
    );
    expect((await store.signal(candidate)).duplicate, isFalse);
    expect((await store.signal(candidate)).duplicate, isTrue);

    final siblingCandidate = _signal(
      callSeed: 10,
      signalSeed: 31,
      kind: CallSignalKind.iceCandidate,
      senderUsername: 'bob',
      senderDeviceId: bobTablet,
      recipientUsername: 'alice',
      recipientDeviceId: aliceDevice,
      createdAt: startedAt.add(const Duration(seconds: 3)),
    );
    await expectLater(store.signal(siblingCandidate), throwsFormatException);

    final hangup = _signal(
      callSeed: 10,
      signalSeed: 40,
      kind: CallSignalKind.hangup,
      senderUsername: 'bob',
      senderDeviceId: bobPhone,
      recipientUsername: 'alice',
      recipientDeviceId: aliceDevice,
      createdAt: startedAt.add(const Duration(seconds: 4)),
    );
    final ended = await store.end(
      hangup,
      now: startedAt.add(const Duration(seconds: 4)),
    );
    expect(ended.update.call.state, CallState.ended);
    expect((await store.end(hangup)).duplicate, isTrue);
  });

  test(
    'ring timeout becomes a durable missed update for both accounts',
    () async {
      await store.start(request(), now: startedAt);

      final bob = await store.sync(
        'bob',
        bobPhone,
        afterCursor: 1,
        now: startedAt.add(const Duration(minutes: 2)),
      );
      expect(bob.updates.single.call.state, CallState.missed);
      expect(bob.updates.single.signals, isEmpty);
      final alice = await store.sync(
        'alice',
        aliceDevice,
        afterCursor: 1,
        now: startedAt.add(const Duration(minutes: 2)),
      );
      expect(alice.updates.single.cursor, bob.updates.single.cursor);

      final reopened = CallStore(store.file.path);
      final replay = await reopened.sync(
        'alice',
        aliceDevice,
        afterCursor: 1,
        now: startedAt.add(const Duration(minutes: 3)),
      );
      expect(replay.updates.single.call.state, CallState.missed);
    },
  );

  test(
    'unrelated accounts advance their cursor without seeing signals',
    () async {
      await store.start(request(), now: startedAt);
      final unrelated = await store.sync(
        'mallory',
        _token(32, 77),
        afterCursor: 0,
        now: startedAt,
      );
      expect(unrelated.updates, isEmpty);
      expect(unrelated.nextCursor, 1);
    },
  );
}

EncryptedCallSignal _signal({
  required int callSeed,
  required int signalSeed,
  required CallSignalKind kind,
  required String senderUsername,
  required String senderDeviceId,
  required String recipientUsername,
  required String recipientDeviceId,
  required DateTime createdAt,
}) => EncryptedCallSignal(
  callId: _token(16, callSeed),
  signalId: _token(16, signalSeed),
  kind: kind,
  senderUsername: senderUsername,
  senderDeviceId: senderDeviceId,
  recipientUsername: recipientUsername,
  recipientDeviceId: recipientDeviceId,
  sealedPayload: Uint8List(WampAppCallLimits.sealedBoxOverheadBytes + 1),
  signature: _token(64, signalSeed),
  createdAt: createdAt,
);

String _token(int bytes, int seed) => base64Url
    .encode(List<int>.generate(bytes, (index) => (index + seed) % 256))
    .replaceAll('=', '');
