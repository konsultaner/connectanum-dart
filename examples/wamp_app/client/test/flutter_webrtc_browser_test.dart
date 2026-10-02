@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:wamp_app/src/infrastructure/call_media.dart';
import 'package:wamp_app/src/infrastructure/flutter_webrtc_call_media.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in CallMediaKind.values) {
    test('${kind.name} browser peers connect without muting capture', () async {
      // Replace device acquisition only. Renderers, tracks, peer connections,
      // SDP and ICE use real browser implementations with synthetic media.
      final devices = web.window.navigator.mediaDevices;
      final original = devices.getProperty<JSFunction>('getUserMedia'.toJS);
      final contexts = <web.AudioContext>[];
      final streams = <web.MediaStream>[];
      final sessions = <CallMediaSession>[];
      final subscriptions = <StreamSubscription<dynamic>>[];
      devices.setProperty(
        'getUserMedia'.toJS,
        ((JSObject constraints) {
          final context = web.AudioContext();
          contexts.add(context);
          final stream = context.createMediaStreamDestination().stream;
          if (kind == CallMediaKind.video) {
            final canvas = web.HTMLCanvasElement()
              ..width = 16
              ..height = 16;
            final video = canvas.captureStream(1);
            for (final track in video.getVideoTracks().toDart) {
              stream.addTrack(track);
            }
          }
          streams.add(stream);
          return Future<web.MediaStream>.value(stream).toJS;
        }).toJS,
      );
      addTearDown(() async {
        devices.setProperty('getUserMedia'.toJS, original);
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        for (final session in sessions) {
          await session.dispose();
        }
        for (final stream in streams) {
          for (final track in stream.getTracks().toDart) {
            track.stop();
          }
        }
        for (final context in contexts) {
          await context.close().toDart;
        }
      });

      for (var index = 0; index < 2; index++) {
        sessions.add(
          await const FlutterWebRtcCallMediaFactory().create(
            media: kind,
            configuration: CallConfiguration(
              iceServers: const [],
              expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
            ),
          ),
        );
      }
      final left = sessions[0], right = sessions[1];
      for (final session in sessions) {
        final preview =
            (session.localRenderer as FlutterWebRtcVideoRendererHandle)
                .renderer;
        expect(
          preview.muted,
          isTrue,
          reason: 'local playback must not feed back',
        );
        expect(preview.srcObject!.getAudioTracks().single.enabled, isTrue);
        expect(session.muted, isFalse);
        expect(session.speakerRoutingSupported, isFalse);
        await session.setMuted(true);
        expect(preview.srcObject!.getAudioTracks().single.enabled, isFalse);
        await session.setMuted(false);
        expect(preview.srcObject!.getAudioTracks().single.enabled, isTrue);
        expect(preview.muted, isTrue);
      }

      final fromLeft = <CallIceCandidate>[], fromRight = <CallIceCandidate>[];
      var leftConnected = false, rightConnected = false;
      subscriptions.addAll([
        left.localCandidates.listen(fromLeft.add),
        right.localCandidates.listen(fromRight.add),
        left.connectionStates.listen((s) {
          leftConnected = s == CallMediaConnectionState.connected;
        }),
        right.connectionStates.listen((s) {
          rightConnected = s == CallMediaConnectionState.connected;
        }),
      ]);
      final offer = await left.createOffer();
      final answer = await right.acceptOffer(offer);
      await left.applyAnswer(answer);
      final deadline = Stopwatch()..start();
      while (!(leftConnected && rightConnected) &&
          deadline.elapsed < const Duration(seconds: 15)) {
        while (fromLeft.isNotEmpty) {
          await right.addRemoteCandidate(fromLeft.removeAt(0));
        }
        while (fromRight.isNotEmpty) {
          await left.addRemoteCandidate(fromRight.removeAt(0));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(leftConnected, isTrue);
      expect(rightConnected, isTrue);
      for (final session in sessions) {
        final remote =
            (session.remoteRenderer as FlutterWebRtcVideoRendererHandle)
                .renderer;
        expect(remote.srcObject!.getAudioTracks(), hasLength(1));
        expect(
          remote.srcObject!.getVideoTracks(),
          hasLength(kind == CallMediaKind.video ? 1 : 0),
        );
      }
      for (final session in sessions) {
        await session.dispose();
      }
      for (final stream in streams) {
        expect(
          stream.getTracks().toDart.map((track) => track.readyState),
          everyElement('ended'),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }
}
