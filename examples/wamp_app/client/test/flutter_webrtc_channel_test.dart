@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/call_media.dart';
import 'package:wamp_app/src/infrastructure/flutter_webrtc_call_media.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

const _method = MethodChannel('FlutterWebRTC.Method');

// Only the platform channel is simulated. The factory, plugin Dart objects,
// session methods and resource ownership execute unchanged.
class _PlatformMedia {
  final calls = <MethodCall>[];
  final channels = <String>{};
  final failures = <String, Object>{};
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  int texture = 0;
  String offerType = 'offer';
  String? offerSdp = 'v=0\r\ns=local-offer\r\n';

  Map<String, Object> track(String kind) => {
    'id': '$kind-track',
    'label': kind,
    'kind': kind,
    'enabled': true,
  };

  void attach() {
    messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      if (failures[call.method] case final failure?) throw failure;
      switch (call.method) {
        case 'initialize':
          return null;
        case 'createVideoRenderer':
          final id = ++texture;
          _event('FlutterWebRTC/Texture$id');
          return {'textureId': id};
        case 'createPeerConnection':
          _event('FlutterWebRTC/peerConnectionEventpeer-1');
          return {'peerConnectionId': 'peer-1'};
        case 'getUserMedia':
          final constraints = (call.arguments as Map)['constraints'] as Map;
          return {
            'streamId': 'local-stream',
            'audioTracks': [track('audio')],
            'videoTracks': constraints['video'] == false
                ? []
                : [track('video')],
          };
        case 'addTrack':
          final id = (call.arguments as Map)['trackId'] as String;
          return {
            'senderId': '$id-sender',
            'track': track(id.split('-').first),
            'ownsTrack': false,
            'rtpParameters': {
              'transactionId': 'transaction-1',
              'rtcp': {'cname': 'local', 'reducedSize': true},
              'encodings': [],
              'codecs': [],
              'headerExtensions': [],
            },
          };
        case 'createOffer':
          return {'type': offerType, 'sdp': offerSdp};
        case 'createAnswer':
          return {'type': 'answer', 'sdp': 'v=0\r\ns=local-answer\r\n'};
        case 'videoRendererSetSrcObject':
        case 'setMicrophoneMute':
        case 'mediaStreamTrackSetEnable':
        case 'setLocalDescription':
        case 'setRemoteDescription':
        case 'addCandidate':
        case 'enableSpeakerphone':
        case 'trackDispose':
        case 'streamDispose':
        case 'peerConnectionClose':
        case 'peerConnectionDispose':
        case 'videoRendererDispose':
          return null;
        default:
          throw StateError('Unexpected platform operation: ${call.method}');
      }
    });
  }

  void _event(String name) {
    channels.add(name);
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }

  List<Map> arguments(String method) => calls
      .where((c) => c.method == method)
      .map((c) => c.arguments as Map)
      .toList();

  Future<void> peerEvent(Map<String, Object?> event) async {
    final completed = Completer<void>();
    messenger.handlePlatformMessage(
      'FlutterWebRTC/peerConnectionEventpeer-1',
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) => completed.complete(),
    );
    await completed.future;
    await Future<void>.delayed(Duration.zero);
  }

  void detach() {
    messenger.setMockMethodCallHandler(_method, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  }
}

CallConfiguration _configuration({bool expired = false}) => CallConfiguration(
  iceServers: const [],
  expiresAt: DateTime.now().toUtc().add(Duration(minutes: expired ? -1 : 5)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _PlatformMedia platform;
  setUp(() {
    platform = _PlatformMedia()..attach();
  });
  tearDown(() {
    platform.detach();
    debugDefaultTargetPlatformOverride = null;
  });

  test('expired configuration opens no platform resources', () async {
    await expectLater(
      const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.voice,
        configuration: _configuration(expired: true),
      ),
      throwsA(
        isA<CallMediaException>().having(
          (e) => e.kind,
          'kind',
          CallMediaFailureKind.configurationExpired,
        ),
      ),
    );
    expect(platform.calls, isEmpty);
  });

  test(
    'ICE credentials and capture constraints reach the actual plugin',
    () async {
      final session = await const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.video,
        configuration: CallConfiguration(
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          iceServers: [
            CallIceServer(urls: ['stun:example.test:3478']),
            CallIceServer(
              urls: ['turns:example.test:5349'],
              username: 'test-user',
              credential: 'test-credential',
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      expect(
        platform.arguments('createPeerConnection').single['configuration'],
        {
          'sdpSemantics': 'unified-plan',
          'iceServers': [
            {
              'urls': ['stun:example.test:3478'],
            },
            {
              'urls': ['turns:example.test:5349'],
              'username': 'test-user',
              'credential': 'test-credential',
            },
          ],
        },
      );
      expect(platform.arguments('getUserMedia').single['constraints'], {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      expect(session.localRenderer, isA<FlutterWebRtcVideoRendererHandle>());
      expect(session.remoteRenderer, isA<FlutterWebRtcVideoRendererHandle>());
    },
  );

  for (final kind in CallMediaKind.values) {
    test(
      '${kind.name} starts with enabled microphone matching UI state',
      () async {
        final session = await const FlutterWebRtcCallMediaFactory().create(
          media: kind,
          configuration: _configuration(),
        );
        addTearDown(session.dispose);
        await Future<void>.delayed(Duration.zero);
        final renderer =
            session.localRenderer as FlutterWebRtcVideoRendererHandle;
        expect(session.muted, isFalse);
        expect(
          renderer.renderer.srcObject!.getAudioTracks().single.enabled,
          isTrue,
          reason: 'an unmuted call must actually send microphone audio',
        );
        expect(
          platform
              .arguments('setMicrophoneMute')
              .where((a) => a['mute'] == true),
          isEmpty,
          reason: 'preview setup must not mute the capture device',
        );
        expect(session.cameraEnabled, kind == CallMediaKind.video);
        expect(
          platform.arguments('addTrack'),
          hasLength(kind == CallMediaKind.video ? 2 : 1),
        );
      },
    );

    test(
      '${kind.name} offer answer ICE toggles and disposal cross the channel',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final session = await const FlutterWebRtcCallMediaFactory().create(
          media: kind,
          configuration: _configuration(),
        );
        addTearDown(session.dispose);
        final offer = await session.createOffer();
        expect(offer.type, 'offer');
        expect(offer.sdp, 'v=0\r\ns=local-offer\r\n');
        final answer = await session.acceptOffer(
          CallSessionDescription(type: 'offer', sdp: 'v=0\r\ns=remote\r\n'),
        );
        expect(answer.type, 'answer');
        expect(answer.sdp, 'v=0\r\ns=local-answer\r\n');
        await session.applyAnswer(
          CallSessionDescription(type: 'answer', sdp: 'v=0\r\ns=answer\r\n'),
        );
        expect(
          platform
              .arguments('setLocalDescription')
              .map((a) => a['description']),
          [
            {'sdp': offer.sdp, 'type': 'offer'},
            {'sdp': answer.sdp, 'type': 'answer'},
          ],
        );
        expect(platform.arguments('setRemoteDescription'), hasLength(2));
        await session.addRemoteCandidate(
          CallIceCandidate(
            candidate: 'candidate:1 1 UDP 1 127.0.0.1 9000 typ host',
            sdpMid: 'audio',
            sdpMLineIndex: 0,
          ),
        );
        expect(platform.arguments('addCandidate').single['candidate'], {
          'candidate': 'candidate:1 1 UDP 1 127.0.0.1 9000 typ host',
          'sdpMid': 'audio',
          'sdpMLineIndex': 0,
        });
        await session.setMuted(true);
        expect(session.muted, isTrue);
        final stream =
            (session.localRenderer as FlutterWebRtcVideoRendererHandle)
                .renderer
                .srcObject!;
        expect(stream.getAudioTracks().single.enabled, isFalse);
        expect(stream.getVideoTracks().every((track) => track.enabled), isTrue);
        await session.setMuted(false);
        expect(session.muted, isFalse);
        expect(stream.getAudioTracks().single.enabled, isTrue);
        await session.setCameraEnabled(false);
        expect(session.cameraEnabled, isFalse);
        expect(
          stream.getVideoTracks().every((track) => !track.enabled),
          isTrue,
        );
        expect(stream.getAudioTracks().single.enabled, isTrue);
        await session.setCameraEnabled(true);
        expect(session.cameraEnabled, kind == CallMediaKind.video);
        expect(stream.getVideoTracks().every((track) => track.enabled), isTrue);
        expect(session.speakerRoutingSupported, isTrue);
        await session.setSpeakerEnabled(true);
        expect(session.speakerEnabled, isTrue);
        await session.setSpeakerEnabled(false);
        expect(session.speakerEnabled, isFalse);
        expect(
          platform.arguments('enableSpeakerphone').map((a) => a['enable']),
          [true, false],
        );
        await session.dispose();
        final calls = platform.calls.length;
        await session.dispose();
        expect(platform.calls, hasLength(calls));
        expect(
          platform.arguments('trackDispose').map((a) => a['trackId']),
          kind == CallMediaKind.video
              ? ['audio-track', 'video-track']
              : ['audio-track'],
        );
        expect(platform.arguments('streamDispose'), [
          {'streamId': 'local-stream'},
        ]);
        expect(platform.arguments('peerConnectionClose'), [
          {'peerConnectionId': 'peer-1'},
        ]);
        expect(platform.arguments('peerConnectionDispose'), [
          {'peerConnectionId': 'peer-1'},
        ]);
        expect(platform.arguments('videoRendererDispose'), [
          {'textureId': 1},
          {'textureId': 2},
        ]);
      },
    );
  }

  test('peer disposal is attempted even if close fails', () async {
    final session = await const FlutterWebRtcCallMediaFactory().create(
      media: CallMediaKind.voice,
      configuration: _configuration(),
    );
    platform.failures['peerConnectionClose'] = PlatformException(
      code: 'close-failed',
    );
    await session.dispose();
    expect(platform.arguments('peerConnectionClose'), hasLength(1));
    expect(platform.arguments('peerConnectionDispose'), hasLength(1));
    expect(platform.arguments('videoRendererDispose'), hasLength(2));
  });

  test(
    'unsupported platform rejects speaker routing without dispatch',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final session = await const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.voice,
        configuration: _configuration(),
      );
      addTearDown(session.dispose);
      expect(session.speakerRoutingSupported, isFalse);
      await expectLater(
        session.setSpeakerEnabled(true),
        throwsA(
          isA<CallMediaException>().having(
            (e) => e.kind,
            'kind',
            CallMediaFailureKind.unsupported,
          ),
        ),
      );
      expect(platform.arguments('enableSpeakerphone'), isEmpty);
      expect(session.speakerEnabled, isFalse);
    },
  );

  for (final invalid in [('answer', 'v=0\r\n'), ('offer', null)]) {
    test(
      'invalid generated offer ${invalid.$1}/${invalid.$2} is rejected',
      () async {
        final session = await const FlutterWebRtcCallMediaFactory().create(
          media: CallMediaKind.voice,
          configuration: _configuration(),
        );
        addTearDown(session.dispose);
        platform.offerType = invalid.$1;
        platform.offerSdp = invalid.$2;
        // The native plugin rejects null SDP before constructing its object.
        await expectLater(
          session.createOffer(),
          invalid.$2 == null
              ? throwsA(isA<TypeError>())
              : throwsFormatException,
        );
        if (invalid.$2 == null) {
          expect(platform.arguments('setLocalDescription'), isEmpty);
        }
      },
    );
  }

  test('wrong remote SDP type does not reach the peer', () async {
    final session = await const FlutterWebRtcCallMediaFactory().create(
      media: CallMediaKind.voice,
      configuration: _configuration(),
    );
    addTearDown(session.dispose);
    await expectLater(
      session.acceptOffer(
        CallSessionDescription(type: 'answer', sdp: 'v=0\r\n'),
      ),
      throwsFormatException,
    );
    await expectLater(
      session.applyAnswer(
        CallSessionDescription(type: 'offer', sdp: 'v=0\r\n'),
      ),
      throwsFormatException,
    );
    expect(platform.arguments('setRemoteDescription'), isEmpty);
    expect(platform.arguments('createAnswer'), isEmpty);
  });

  for (final failure in [
    'trackDispose',
    'streamDispose',
    'peerConnectionClose',
    'peerConnectionDispose',
    'videoRendererDispose',
  ]) {
    test('$failure failure does not skip remaining cleanup', () async {
      final session = await const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.video,
        configuration: _configuration(),
      );
      var candidatesDone = false, statesDone = false;
      session.localCandidates.listen(
        (_) {},
        onDone: () => candidatesDone = true,
      );
      session.connectionStates.listen((_) {}, onDone: () => statesDone = true);
      platform.failures[failure] = PlatformException(code: 'cleanup-failed');
      await session.dispose();
      expect(platform.arguments('trackDispose'), hasLength(2));
      expect(platform.arguments('streamDispose'), hasLength(1));
      expect(platform.arguments('peerConnectionClose'), hasLength(1));
      expect(platform.arguments('peerConnectionDispose'), hasLength(1));
      expect(platform.arguments('videoRendererDispose'), hasLength(2));
      expect(candidatesDone, isTrue);
      expect(statesDone, isTrue);
      final calls = platform.calls.length;
      await session.dispose();
      expect(platform.calls, hasLength(calls));
    });
  }

  test(
    'addTrack failure releases the already acquired capture stream',
    () async {
      platform.failures['addTrack'] = PlatformException(code: 'attach-failed');
      await expectLater(
        const FlutterWebRtcCallMediaFactory().create(
          media: CallMediaKind.video,
          configuration: _configuration(),
        ),
        throwsA(
          isA<CallMediaException>().having(
            (e) => e.kind,
            'kind',
            CallMediaFailureKind.transport,
          ),
        ),
      );
      expect(platform.arguments('trackDispose').map((a) => a['trackId']), [
        'audio-track',
        'video-track',
      ]);
      expect(platform.arguments('streamDispose'), hasLength(1));
      expect(platform.arguments('peerConnectionClose'), hasLength(1));
      expect(platform.arguments('peerConnectionDispose'), hasLength(1));
      expect(platform.arguments('videoRendererDispose'), hasLength(2));
    },
  );

  test('failed speaker switch preserves the last confirmed state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final session = await const FlutterWebRtcCallMediaFactory().create(
      media: CallMediaKind.voice,
      configuration: _configuration(),
    );
    addTearDown(session.dispose);
    expect(session.speakerRoutingSupported, isTrue);
    await session.setSpeakerEnabled(true);
    platform.failures['enableSpeakerphone'] = PlatformException(code: 'route');
    await expectLater(
      session.setSpeakerEnabled(false),
      throwsA(isA<PlatformException>()),
    );
    expect(session.speakerEnabled, isTrue);
    expect(platform.arguments('enableSpeakerphone').map((a) => a['enable']), [
      true,
      false,
    ]);
  });

  test(
    'all disposed session operations fail before platform dispatch',
    () async {
      final session = await const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.video,
        configuration: _configuration(),
      );
      await session.dispose();
      final before = platform.calls.length;
      final operations = <String, FutureOr<dynamic> Function()>{
        'offer': session.createOffer,
        'accept': () => session.acceptOffer(
          CallSessionDescription(type: 'offer', sdp: 'v=0\r\n'),
        ),
        'answer': () => session.applyAnswer(
          CallSessionDescription(type: 'answer', sdp: 'v=0\r\n'),
        ),
        'candidate': () => session.addRemoteCandidate(
          CallIceCandidate(
            candidate: 'candidate:1 1 UDP 1 127.0.0.1 9000 typ host',
          ),
        ),
        'mute': () => session.setMuted(true),
        'camera': () => session.setCameraEnabled(true),
        'speaker': () => session.setSpeakerEnabled(true),
      };
      for (final entry in operations.entries) {
        await expectLater(
          Future<dynamic>.sync(entry.value),
          throwsA(
            isA<CallMediaException>().having(
              (e) => e.kind,
              'kind',
              CallMediaFailureKind.disposed,
            ),
          ),
          reason: entry.key,
        );
      }
      expect(platform.calls, hasLength(before));
    },
  );

  for (final failure in [
    ('Permission denied', CallMediaFailureKind.permissionDenied),
    ('NotSupported', CallMediaFailureKind.unsupported),
    ('other error', CallMediaFailureKind.transport),
  ]) {
    test('capture failure ${failure.$1} classifies and cleans up', () async {
      platform.failures['getUserMedia'] = PlatformException(
        code: 'media',
        message: failure.$1,
      );
      await expectLater(
        const FlutterWebRtcCallMediaFactory().create(
          media: CallMediaKind.video,
          configuration: _configuration(),
        ),
        throwsA(
          isA<CallMediaException>().having((e) => e.kind, 'kind', failure.$2),
        ),
      );
      expect(platform.arguments('peerConnectionClose'), hasLength(1));
      expect(platform.arguments('peerConnectionDispose'), hasLength(1));
      expect(platform.arguments('videoRendererDispose'), hasLength(2));
      expect(platform.arguments('addTrack'), isEmpty);
    });
  }

  test(
    'malformed ICE is reported without ending the candidate stream',
    () async {
      final session = await const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.voice,
        configuration: _configuration(),
      );
      addTearDown(session.dispose);
      final candidates = <CallIceCandidate>[];
      final errors = <Object>[];
      session.localCandidates.listen(candidates.add, onError: errors.add);
      for (final ignored in [null, '']) {
        await platform.peerEvent({
          'event': 'onCandidate',
          'candidate': {'candidate': ignored},
        });
      }
      expect(candidates, isEmpty);
      expect(errors, isEmpty);
      for (final invalid in <Map<String, Object>>[
        {'candidate': List.filled(16385, 'x').join()},
        {
          'candidate': 'candidate:valid',
          'sdpMid': List.filled(257, 'x').join(),
        },
        {'candidate': 'candidate:valid', 'sdpMLineIndex': -1},
        {'candidate': 'candidate:valid', 'sdpMLineIndex': 65536},
      ]) {
        await platform.peerEvent({
          'event': 'onCandidate',
          'candidate': invalid,
        });
      }
      expect(candidates, isEmpty);
      expect(errors, hasLength(4));
      expect(errors, everyElement(isA<FormatException>()));
      await platform.peerEvent({
        'event': 'onCandidate',
        'candidate': {'candidate': 'candidate:valid'},
      });
      expect(candidates.single.candidate, 'candidate:valid');
      expect(candidates.single.sdpMid, isNull);
      expect(candidates.single.sdpMLineIndex, isNull);
    },
  );

  test(
    'remote track events attach the first stream and ignore empty events',
    () async {
      final session = await const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.video,
        configuration: _configuration(),
      );
      addTearDown(session.dispose);
      final remote =
          (session.remoteRenderer as FlutterWebRtcVideoRendererHandle).renderer;
      final track = platform.track('video');
      final receiver = {
        'receiverId': 'receiver-1',
        'track': track,
        'rtpParameters': {
          'transactionId': 'remote-1',
          'rtcp': {'cname': 'remote', 'reducedSize': true},
          'encodings': [],
          'codecs': [],
          'headerExtensions': [],
        },
      };
      final empty = <String, Object?>{
        'event': 'onTrack',
        'streams': [],
        'track': track,
        'receiver': receiver,
      };
      await platform.peerEvent(empty);
      expect(remote.srcObject, isNull);
      await platform.peerEvent({
        ...empty,
        'streams': [
          for (final id in ['remote-first', 'remote-second'])
            {
              'streamId': id,
              'ownerTag': 'peer-1',
              'audioTracks': [],
              'videoTracks': [track],
            },
        ],
      });
      expect(remote.srcObject!.id, 'remote-first');
      expect(remote.srcObject!.getVideoTracks().single.id, 'video-track');
      expect(platform.arguments('videoRendererSetSrcObject').last, {
        'textureId': 2,
        'streamId': 'remote-first',
        'ownerTag': 'peer-1',
      });
      await platform.peerEvent(empty);
      expect(remote.srcObject!.id, 'remote-first');
    },
  );

  test(
    'peer state and ICE events retain values and terminate on disposal',
    () async {
      final session = await const FlutterWebRtcCallMediaFactory().create(
        media: CallMediaKind.voice,
        configuration: _configuration(),
      );
      final states = <CallMediaConnectionState>[];
      final candidates = <CallIceCandidate>[];
      var statesDone = false, candidatesDone = false;
      session.connectionStates.listen(
        states.add,
        onDone: () => statesDone = true,
      );
      session.localCandidates.listen(
        candidates.add,
        onDone: () => candidatesDone = true,
      );
      for (final state in [
        'new',
        'connecting',
        'connected',
        'disconnected',
        'failed',
        'closed',
      ]) {
        await platform.peerEvent({
          'event': 'peerConnectionState',
          'state': state,
        });
      }
      expect(states, [
        CallMediaConnectionState.newConnection,
        CallMediaConnectionState.connecting,
        CallMediaConnectionState.connected,
        CallMediaConnectionState.disconnected,
        CallMediaConnectionState.failed,
        CallMediaConnectionState.closed,
      ]);
      await platform.peerEvent({
        'event': 'onCandidate',
        'candidate': {
          'candidate': 'candidate:1 1 UDP 1 127.0.0.1 9000 typ host',
          'sdpMid': 'audio',
          'sdpMLineIndex': 0,
        },
      });
      expect(
        candidates.single.candidate,
        'candidate:1 1 UDP 1 127.0.0.1 9000 typ host',
      );
      expect(candidates.single.sdpMid, 'audio');
      expect(candidates.single.sdpMLineIndex, 0);
      await session.dispose();
      expect(statesDone, isTrue);
      expect(candidatesDone, isTrue);
    },
  );
}
