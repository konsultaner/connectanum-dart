import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/application/call_controller.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';
import 'package:wamp_app/src/infrastructure/call_media.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'test_support.dart';

void main() {
  test('outgoing call encrypts offers and flushes ICE after answer', () async {
    final harness = _CallHarness();
    final media = _FakeCallMediaSession(CallMediaKind.video);
    harness.mediaFactory.sessions.add(media);
    harness.onStart = (request) async {
      expect(request.offers, hasLength(2));
      expect(
        request.offers.map((offer) => offer.recipientDeviceId),
        containsAll([harness.bob.deviceId, harness.bobSibling.deviceId]),
      );
      return CallUpdate(
        cursor: 1,
        call: harness.ringingCall(request.callId, CallMediaKind.video),
        signals: request.offers,
      );
    };
    final controller = harness.controller();
    addTearDown(() async {
      await controller.close();
      controller.dispose();
      await harness.close();
    });
    await controller.initialize();

    await controller.startCall(
      recipientUsername: 'bob',
      media: CallMediaKind.video,
    );
    expect(controller.phase, CallUiPhase.outgoingRinging);
    expect(media.createdOffers, 1);
    expect(harness.plaintextReferences, isNotEmpty);
    expect(
      harness.plaintextReferences.every(
        (bytes) => bytes.every((value) => value == 0),
      ),
      isTrue,
    );
    media.emitState(CallMediaConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(controller.phase, CallUiPhase.outgoingRinging);

    media.emitCandidate(
      CallIceCandidate(
        candidate: 'candidate:1 1 UDP 1 127.0.0.1 9000 typ host',
        sdpMid: 'video',
        sdpMLineIndex: 0,
      ),
    );
    expect(harness.sentSignals, isEmpty);

    final answer = harness.remoteSignal(
      callId: controller.call!.callId,
      kind: CallSignalKind.answer,
      sender: harness.bob,
      payload: CallDescriptionSignalPayload(
        CallSessionDescription(type: 'answer', sdp: 'v=0\r\ns=answer\r\n'),
      ),
    );
    harness.batches.add(
      CallBatch(
        nextCursor: 2,
        updates: [
          CallUpdate(
            cursor: 2,
            call: harness.activeCall(controller.call!.callId),
            signals: [answer],
          ),
        ],
      ),
    );
    harness.wakeups.add(const CallWakeup(cursor: 2));
    await _waitFor(() => harness.sentSignals.length == 1);

    expect(media.appliedAnswers.single.sdp, contains('answer'));
    expect(harness.sentSignals.single.kind, CallSignalKind.iceCandidate);
    expect(controller.phase, CallUiPhase.connecting);
    media.emitState(CallMediaConnectionState.connected);
    await _waitFor(() => controller.phase == CallUiPhase.active);
  });

  test('first answer on another callee device disposes local media', () async {
    final harness = _CallHarness(username: 'bob');
    final media = _FakeCallMediaSession(CallMediaKind.voice);
    harness.mediaFactory.sessions.add(media);
    final callId = _token(18, 70);
    final offer = harness.remoteSignal(
      callId: callId,
      kind: CallSignalKind.offer,
      sender: harness.alice,
      payload: CallDescriptionSignalPayload(
        CallSessionDescription(type: 'offer', sdp: 'v=0\r\ns=offer\r\n'),
      ),
    );
    harness.batches.add(
      CallBatch(
        nextCursor: 1,
        updates: [
          CallUpdate(
            cursor: 1,
            call: harness.ringingCall(callId, CallMediaKind.voice),
            signals: [offer],
          ),
        ],
      ),
    );
    harness.onAccept = (answer) async => CallUpdate(
      cursor: 2,
      call: harness.activeCall(
        callId,
        acceptedDeviceId: harness.bobSibling.deviceId,
      ),
      signals: [answer],
    );
    final controller = harness.controller();
    addTearDown(() async {
      await controller.close();
      controller.dispose();
      await harness.close();
    });

    await controller.initialize();
    expect(controller.phase, CallUiPhase.incomingRinging);
    await controller.acceptIncoming();

    expect(controller.phase, CallUiPhase.answeredElsewhere);
    expect(controller.mediaSession, isNull);
    expect(media.disposed, isTrue);
    expect(media.acceptedOffers.single.sdp, contains('offer'));
  });

  test(
    'end failure preserves active state and stale media is fenced',
    () async {
      final harness = _CallHarness();
      final firstMedia = _FakeCallMediaSession(CallMediaKind.voice);
      final secondMedia = _FakeCallMediaSession(CallMediaKind.voice);
      harness.mediaFactory.sessions.addAll([firstMedia, secondMedia]);
      harness.onStart = (request) async => CallUpdate(
        cursor: 1,
        call: harness.ringingCall(request.callId, CallMediaKind.voice),
        signals: request.offers,
      );
      final controller = harness.controller();
      addTearDown(() async {
        await controller.close();
        controller.dispose();
        await harness.close();
      });
      await controller.initialize();
      await controller.startCall(
        recipientUsername: 'bob',
        media: CallMediaKind.voice,
      );
      final callId = controller.call!.callId;
      final answer = harness.remoteSignal(
        callId: callId,
        kind: CallSignalKind.answer,
        sender: harness.bob,
        payload: CallDescriptionSignalPayload(
          CallSessionDescription(type: 'answer', sdp: 'v=0\r\ns=answer\r\n'),
        ),
      );
      harness.batches.add(
        CallBatch(
          nextCursor: 2,
          updates: [
            CallUpdate(
              cursor: 2,
              call: harness.activeCall(callId),
              signals: [answer],
            ),
          ],
        ),
      );
      harness.wakeups.add(const CallWakeup(cursor: 2));
      await _waitFor(() => controller.phase == CallUiPhase.connecting);
      firstMedia.emitState(CallMediaConnectionState.connected);
      await _waitFor(() => controller.phase == CallUiPhase.active);

      harness.onEnd = (_) async => throw StateError('offline');
      await controller.endCall();
      expect(controller.phase, CallUiPhase.active);
      expect(controller.busy, isFalse);
      expect(controller.errorMessage, isNotNull);

      harness.onEnd = (signal) async => CallUpdate(
        cursor: 3,
        call: harness.terminalCall(callId),
        signals: [signal],
      );
      await controller.endCall();
      expect(firstMedia.disposed, isTrue);
      expect(controller.phase, CallUiPhase.ended);
      controller.dismiss();
      await controller.startCall(
        recipientUsername: 'bob',
        media: CallMediaKind.voice,
      );
      expect(controller.phase, CallUiPhase.outgoingRinging);

      firstMedia.emitState(CallMediaConnectionState.failed);
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, CallUiPhase.outgoingRinging);
      expect(controller.mediaSession, same(secondMedia));
    },
  );

  test('sync cursor regression fails closed without spinning', () async {
    final harness = _CallHarness();
    final irrelevant = CallUpdate(
      cursor: 1,
      call: harness.terminalCall(_token(18, 91)),
    );
    harness.batches.addAll([
      CallBatch(nextCursor: 100, updates: List.filled(100, irrelevant)),
      CallBatch(nextCursor: 50, updates: const []),
    ]);
    final controller = harness.controller();
    addTearDown(() async {
      await controller.close();
      controller.dispose();
      await harness.close();
    });

    await controller.initialize();

    expect(controller.errorMessage, 'The encrypted call signal was invalid.');
    expect(harness.syncAfter, [0, 100]);
  });

  test('reconnect terminates active call whose media state was lost', () async {
    final harness = _CallHarness();
    final callId = _token(18, 95);
    EncryptedCallSignal? termination;
    harness.batches.add(
      CallBatch(
        nextCursor: 1,
        updates: [CallUpdate(cursor: 1, call: harness.activeCall(callId))],
      ),
    );
    harness.onEnd = (signal) async {
      termination = signal;
      return CallUpdate(
        cursor: 2,
        call: harness.terminalCall(callId),
        signals: [signal],
      );
    };
    final controller = harness.controller();
    addTearDown(() async {
      await controller.close();
      controller.dispose();
      await harness.close();
    });

    await controller.initialize();

    expect(controller.phase, CallUiPhase.ended);
    expect(controller.mediaSession, isNull);
    expect(termination?.kind, CallSignalKind.hangup);
    expect(controller.errorMessage, contains('could not be resumed'));
  });
}

final class _CallHarness {
  _CallHarness({this.username = 'alice'}) {
    trust = FakeDeviceTrustSession(
      username,
      const [],
      const [],
      const [],
      0,
      LocalAppPreferences.defaults,
      sealCallSignalCallback: _seal,
      openCallSignalCallback: _open,
    );
    localDevice = activeDeviceRecord(username, trust.enrollment);
  }

  final String username;
  late final FakeDeviceTrustSession trust;
  late final DeviceRecord localDevice;
  final DeviceRecord alice = activeDeviceRecord('alice', _enrollment(10));
  final DeviceRecord bob = activeDeviceRecord('bob', _enrollment(20));
  final DeviceRecord bobSibling = activeDeviceRecord('bob', _enrollment(30));
  final StreamController<CallWakeup> wakeups =
      StreamController<CallWakeup>.broadcast(sync: true);
  final List<CallBatch> batches = [];
  final List<int> syncAfter = [];
  final List<EncryptedCallSignal> sentSignals = [];
  final List<Uint8List> plaintextReferences = [];
  final Map<String, Uint8List> _plaintextBySignal = {};
  final _FakeCallMediaFactory mediaFactory = _FakeCallMediaFactory();
  int _tokenSeed = 100;
  Future<CallUpdate> Function(CallStartRequest request)? onStart;
  Future<CallUpdate> Function(EncryptedCallSignal answer)? onAccept;
  Future<CallUpdate> Function(EncryptedCallSignal signal)? onEnd;

  CallController controller() => CallController(
    connection: _connection(),
    trust: trust,
    localDevice: localDevice,
    mediaFactory: mediaFactory,
    tokenGenerator: () => _token(18, _tokenSeed++),
  );

  CallRecord ringingCall(String callId, CallMediaKind media) => CallRecord(
    callId: callId,
    callerUsername: 'alice',
    callerDeviceId: alice.deviceId,
    calleeUsername: 'bob',
    media: media,
    state: CallState.ringing,
    createdAt: DateTime.utc(2026, 8, 25, 12),
  );

  CallRecord activeCall(String callId, {String? acceptedDeviceId}) =>
      CallRecord(
        callId: callId,
        callerUsername: 'alice',
        callerDeviceId: alice.deviceId,
        calleeUsername: 'bob',
        media: CallMediaKind.voice,
        state: CallState.active,
        acceptedDeviceId: acceptedDeviceId ?? bob.deviceId,
        createdAt: DateTime.utc(2026, 8, 25, 12),
        answeredAt: DateTime.utc(2026, 8, 25, 12, 0, 1),
      );

  CallRecord terminalCall(String callId) => CallRecord(
    callId: callId,
    callerUsername: 'alice',
    callerDeviceId: alice.deviceId,
    calleeUsername: 'bob',
    media: CallMediaKind.voice,
    state: CallState.ended,
    acceptedDeviceId: bob.deviceId,
    createdAt: DateTime.utc(2026, 8, 25, 12),
    answeredAt: DateTime.utc(2026, 8, 25, 12, 0, 1),
    endedAt: DateTime.utc(2026, 8, 25, 12, 0, 2),
  );

  EncryptedCallSignal remoteSignal({
    required String callId,
    required CallSignalKind kind,
    required DeviceRecord sender,
    required CallSignalPayload payload,
  }) {
    final signalId = _token(18, _tokenSeed++);
    final plaintext = CallSignalPayloadCodec.encode(kind, payload);
    _plaintextBySignal[signalId] = Uint8List.fromList(plaintext);
    plaintext.fillRange(0, plaintext.length, 0);
    return EncryptedCallSignal(
      callId: callId,
      signalId: signalId,
      kind: kind,
      senderUsername: sender.username,
      senderDeviceId: sender.deviceId,
      recipientUsername: username,
      recipientDeviceId: localDevice.deviceId,
      sealedPayload: Uint8List(49)..fillRange(0, 49, 7),
      signature: _token(64, _tokenSeed++),
      createdAt: DateTime.utc(2026, 8, 25, 12),
    );
  }

  EncryptedCallSignal _seal({
    required String callId,
    required String signalId,
    required CallSignalKind kind,
    required DeviceRecord recipient,
    required Uint8List plaintext,
  }) {
    plaintextReferences.add(plaintext);
    _plaintextBySignal[signalId] = Uint8List.fromList(plaintext);
    return EncryptedCallSignal(
      callId: callId,
      signalId: signalId,
      kind: kind,
      senderUsername: username,
      senderDeviceId: localDevice.deviceId,
      recipientUsername: recipient.username,
      recipientDeviceId: recipient.deviceId,
      sealedPayload: Uint8List(49)..fillRange(0, 49, 8),
      signature: _token(64, _tokenSeed++),
      createdAt: DateTime.utc(2026, 8, 25, 12),
    );
  }

  Uint8List _open({
    required EncryptedCallSignal signal,
    required DeviceRecord sender,
  }) {
    final plaintext = _plaintextBySignal[signal.signalId];
    if (plaintext == null) throw StateError('Missing fake signal payload.');
    return Uint8List.fromList(plaintext);
  }

  AccountConnection _connection() {
    final profile = AccountProfile(
      username: username,
      displayName: username,
      status: '',
      revision: 0,
      updatedAt: DateTime.utc(2026, 8, 25),
    );
    return AccountConnection(
      endpoint: ServerEndpoint.parse('ws://localhost:8080/ws'),
      username: username,
      initialProfile: profile,
      closeTransport: () async {},
      getProfileCallback: (_) async => profile,
      updateProfileCallback: (_) async => profile,
      enrollDeviceCallback: (_) async => localDevice,
      listDevicesCallback: (_) async => DeviceDirectory([localDevice]),
      lookupDevicesCallback: (lookup, _) async {
        final normalized = AccountRegistration.normalizeUsername(lookup);
        return switch (normalized) {
          'alice' => DeviceDirectory([alice]),
          'bob' => DeviceDirectory([bob, bobSibling]),
          _ => DeviceDirectory(const []),
        };
      },
      revokeDeviceCallback: (_) => throw UnimplementedError(),
      sendMessageCallback: (_) => throw UnimplementedError(),
      syncMessagesCallback: (cursor, _) async =>
          MailboxBatch(nextCursor: cursor, messages: const []),
      markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
      consumeOneTimeCallback: (_) => throw UnimplementedError(),
      getCallConfigurationCallback: () async => CallConfiguration(
        iceServers: const [],
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ),
      startCallCallback: (request) => onStart!(request),
      acceptCallCallback: (answer) => onAccept!(answer),
      sendCallSignalCallback: (signal) async {
        sentSignals.add(signal);
        return CallUpdate(
          cursor: 3 + sentSignals.length,
          call: activeCall(signal.callId),
          signals: [signal],
        );
      },
      endCallCallback: (signal) => onEnd!(signal),
      syncCallsCallback: (_, afterCursor, _) async {
        syncAfter.add(afterCursor);
        if (batches.isEmpty) {
          return CallBatch(nextCursor: afterCursor, updates: const []);
        }
        return batches.removeAt(0);
      },
      callWakeups: wakeups.stream,
      latestCallWakeupCursorCallback: () => 0,
      latestCallWakeupErrorCallback: () => null,
      mailboxWakeups: const Stream<MailboxWakeup>.empty(),
      latestMailboxWakeupCursorCallback: () => 0,
      latestMailboxWakeupErrorCallback: () => null,
    );
  }

  Future<void> close() => wakeups.close();
}

final class _FakeCallMediaFactory implements CallMediaFactory {
  final List<_FakeCallMediaSession> sessions = [];

  @override
  Future<CallMediaSession> create({
    required CallMediaKind media,
    required CallConfiguration configuration,
  }) async {
    if (sessions.isEmpty) throw StateError('No fake media session queued.');
    final session = sessions.removeAt(0);
    expect(session.media, media);
    return session;
  }
}

final class _FakeRenderer implements CallVideoRendererHandle {}

final class _FakeCallMediaSession implements CallMediaSession {
  _FakeCallMediaSession(this.media);

  @override
  final CallMediaKind media;
  final StreamController<CallIceCandidate> _candidates =
      StreamController<CallIceCandidate>.broadcast(sync: true);
  final StreamController<CallMediaConnectionState> _states =
      StreamController<CallMediaConnectionState>.broadcast(sync: true);
  final _FakeRenderer _renderer = _FakeRenderer();
  final List<CallSessionDescription> acceptedOffers = [];
  final List<CallSessionDescription> appliedAnswers = [];
  final List<CallIceCandidate> remoteCandidates = [];
  int createdOffers = 0;
  bool disposed = false;
  bool _muted = false;
  bool _cameraEnabled = true;
  bool _speakerEnabled = false;

  @override
  Stream<CallIceCandidate> get localCandidates => _candidates.stream;
  @override
  Stream<CallMediaConnectionState> get connectionStates => _states.stream;
  @override
  CallVideoRendererHandle get localRenderer => _renderer;
  @override
  CallVideoRendererHandle get remoteRenderer => _renderer;
  @override
  bool get muted => _muted;
  @override
  bool get cameraEnabled => media == CallMediaKind.video && _cameraEnabled;
  @override
  bool get speakerRoutingSupported => true;
  @override
  bool get speakerEnabled => _speakerEnabled;

  @override
  Future<CallSessionDescription> createOffer() async {
    createdOffers += 1;
    return CallSessionDescription(type: 'offer', sdp: 'v=0\r\ns=offer\r\n');
  }

  @override
  Future<CallSessionDescription> acceptOffer(
    CallSessionDescription offer,
  ) async {
    acceptedOffers.add(offer);
    return CallSessionDescription(type: 'answer', sdp: 'v=0\r\ns=answer\r\n');
  }

  @override
  Future<void> applyAnswer(CallSessionDescription answer) async {
    appliedAnswers.add(answer);
  }

  @override
  Future<void> addRemoteCandidate(CallIceCandidate candidate) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> setMuted(bool muted) async => _muted = muted;
  @override
  Future<void> setCameraEnabled(bool enabled) async => _cameraEnabled = enabled;
  @override
  Future<void> setSpeakerEnabled(bool enabled) async =>
      _speakerEnabled = enabled;

  void emitCandidate(CallIceCandidate candidate) => _candidates.add(candidate);
  void emitState(CallMediaConnectionState state) => _states.add(state);

  @override
  Future<void> dispose() async => disposed = true;
}

DeviceEnrollment _enrollment(int seed) => DeviceEnrollment(
  deviceId: _token(32, seed),
  deviceName: 'Device $seed',
  signingPublicKey: _token(32, seed + 1),
  exchangePublicKey: _token(32, seed + 2),
  attestation: _token(64, seed + 3),
  createdAt: DateTime.utc(2026, 8, 25),
);

String _token(int bytes, int seed) => base64Url
    .encode(List<int>.generate(bytes, (index) => (seed + index) % 256))
    .replaceAll('=', '');

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not satisfied before the test deadline.');
}
