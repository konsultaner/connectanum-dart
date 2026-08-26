import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wamp_app/src/infrastructure/call_media.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class FlutterWebRtcVideoRendererHandle
    implements CallVideoRendererHandle {
  const FlutterWebRtcVideoRendererHandle(this.renderer);

  final RTCVideoRenderer renderer;
}

final class FlutterWebRtcCallMediaFactory implements CallMediaFactory {
  const FlutterWebRtcCallMediaFactory();

  @override
  Future<CallMediaSession> create({
    required CallMediaKind media,
    required CallConfiguration configuration,
  }) async {
    if (!configuration.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const CallMediaException(
        CallMediaFailureKind.configurationExpired,
        'The call network configuration expired. Try the call again.',
      );
    }

    RTCVideoRenderer? localRenderer;
    RTCVideoRenderer? remoteRenderer;
    RTCPeerConnection? peer;
    MediaStream? localStream;
    try {
      localRenderer = RTCVideoRenderer();
      remoteRenderer = RTCVideoRenderer();
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      peer = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': configuration.iceServers
            .map(
              (server) => <String, dynamic>{
                'urls': server.urls,
                if (server.username != null) 'username': server.username,
                if (server.credential != null) 'credential': server.credential,
              },
            )
            .toList(growable: false),
      });
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': media == CallMediaKind.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      localRenderer.srcObject = localStream;
      localRenderer.muted = true;
      for (final track in localStream.getTracks()) {
        await peer.addTrack(track, localStream);
      }

      final session = _FlutterWebRtcCallMediaSession(
        media: media,
        peer: peer,
        localStream: localStream,
        localRenderer: localRenderer,
        remoteRenderer: remoteRenderer,
      );
      session.bindCallbacks();
      return session;
    } catch (error) {
      await _disposePartial(
        peer: peer,
        localStream: localStream,
        localRenderer: localRenderer,
        remoteRenderer: remoteRenderer,
      );
      if (error is CallMediaException) rethrow;
      final description = error.toString().toLowerCase();
      if (description.contains('notallowed') ||
          description.contains('permission') ||
          description.contains('denied')) {
        throw const CallMediaException(
          CallMediaFailureKind.permissionDenied,
          'Microphone or camera permission was denied.',
        );
      }
      if (description.contains('notsupported') ||
          description.contains('not supported') ||
          description.contains('notfound')) {
        throw const CallMediaException(
          CallMediaFailureKind.unsupported,
          'Required call media is unavailable on this device.',
        );
      }
      throw const CallMediaException(
        CallMediaFailureKind.transport,
        'The call media session could not be started.',
      );
    }
  }
}

final class _FlutterWebRtcCallMediaSession implements CallMediaSession {
  _FlutterWebRtcCallMediaSession({
    required this.media,
    required this._peer,
    required this._localStream,
    required this._localRenderer,
    required this._remoteRenderer,
  });

  @override
  final CallMediaKind media;
  final RTCPeerConnection _peer;
  final MediaStream _localStream;
  final RTCVideoRenderer _localRenderer;
  final RTCVideoRenderer _remoteRenderer;
  final StreamController<CallIceCandidate> _candidateController =
      StreamController<CallIceCandidate>.broadcast(sync: true);
  final StreamController<CallMediaConnectionState> _stateController =
      StreamController<CallMediaConnectionState>.broadcast(sync: true);
  bool _muted = false;
  bool _cameraEnabled = true;
  bool _speakerEnabled = false;
  bool _disposed = false;

  void bindCallbacks() {
    _peer.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (_disposed || candidateValue == null || candidateValue.isEmpty) return;
      try {
        _candidateController.add(
          CallIceCandidate(
            candidate: candidateValue,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
          ),
        );
      } catch (error, stackTrace) {
        _candidateController.addError(error, stackTrace);
      }
    };
    _peer.onTrack = (event) {
      if (_disposed || event.streams.isEmpty) return;
      _remoteRenderer.srcObject = event.streams.first;
    };
    _peer.onConnectionState = (state) {
      if (_disposed) return;
      _stateController.add(_mapConnectionState(state));
    };
  }

  @override
  Stream<CallIceCandidate> get localCandidates => _candidateController.stream;

  @override
  Stream<CallMediaConnectionState> get connectionStates =>
      _stateController.stream;

  @override
  CallVideoRendererHandle get localRenderer =>
      FlutterWebRtcVideoRendererHandle(_localRenderer);

  @override
  CallVideoRendererHandle get remoteRenderer =>
      FlutterWebRtcVideoRendererHandle(_remoteRenderer);

  @override
  bool get muted => _muted;

  @override
  bool get cameraEnabled => media == CallMediaKind.video && _cameraEnabled;

  @override
  bool get speakerRoutingSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  bool get speakerEnabled => _speakerEnabled;

  @override
  Future<CallSessionDescription> createOffer() async {
    _ensureOpen();
    final offer = await _peer.createOffer({});
    await _peer.setLocalDescription(offer);
    return _description(offer, 'offer');
  }

  @override
  Future<CallSessionDescription> acceptOffer(
    CallSessionDescription offer,
  ) async {
    _ensureOpen();
    if (offer.type != 'offer') {
      throw const FormatException('Expected a call offer.');
    }
    await _peer.setRemoteDescription(RTCSessionDescription(offer.sdp, 'offer'));
    final answer = await _peer.createAnswer({});
    await _peer.setLocalDescription(answer);
    return _description(answer, 'answer');
  }

  @override
  Future<void> applyAnswer(CallSessionDescription answer) async {
    _ensureOpen();
    if (answer.type != 'answer') {
      throw const FormatException('Expected a call answer.');
    }
    await _peer.setRemoteDescription(
      RTCSessionDescription(answer.sdp, 'answer'),
    );
  }

  @override
  Future<void> addRemoteCandidate(CallIceCandidate candidate) {
    _ensureOpen();
    return _peer.addCandidate(
      RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  @override
  Future<void> setMuted(bool muted) async {
    _ensureOpen();
    for (final track in _localStream.getAudioTracks()) {
      track.enabled = !muted;
    }
    _muted = muted;
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    _ensureOpen();
    if (media != CallMediaKind.video) return;
    for (final track in _localStream.getVideoTracks()) {
      track.enabled = enabled;
    }
    _cameraEnabled = enabled;
  }

  @override
  Future<void> setSpeakerEnabled(bool enabled) async {
    _ensureOpen();
    if (!speakerRoutingSupported) {
      throw const CallMediaException(
        CallMediaFailureKind.unsupported,
        'Speaker routing is controlled by this platform.',
      );
    }
    await Helper.setSpeakerphoneOn(enabled);
    _speakerEnabled = enabled;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _peer.onIceCandidate = null;
    _peer.onTrack = null;
    _peer.onConnectionState = null;
    await _disposePartial(
      peer: _peer,
      localStream: _localStream,
      localRenderer: _localRenderer,
      remoteRenderer: _remoteRenderer,
    );
    await Future.wait([_candidateController.close(), _stateController.close()]);
  }

  CallSessionDescription _description(
    RTCSessionDescription value,
    String expectedType,
  ) {
    final type = value.type;
    final sdp = value.sdp;
    if (type != expectedType || sdp == null) {
      throw const FormatException(
        'WebRTC returned an invalid session description.',
      );
    }
    return CallSessionDescription(type: type!, sdp: sdp);
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const CallMediaException(
        CallMediaFailureKind.disposed,
        'The call media session is closed.',
      );
    }
  }
}

CallMediaConnectionState _mapConnectionState(RTCPeerConnectionState state) =>
    switch (state) {
      RTCPeerConnectionState.RTCPeerConnectionStateNew =>
        CallMediaConnectionState.newConnection,
      RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
        CallMediaConnectionState.connecting,
      RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
        CallMediaConnectionState.connected,
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
        CallMediaConnectionState.disconnected,
      RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
        CallMediaConnectionState.failed,
      RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
        CallMediaConnectionState.closed,
    };

Future<void> _disposePartial({
  RTCPeerConnection? peer,
  MediaStream? localStream,
  RTCVideoRenderer? localRenderer,
  RTCVideoRenderer? remoteRenderer,
}) async {
  for (final track in localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
    try {
      await track.stop();
    } catch (_) {
      // Continue releasing the remaining media resources.
    }
  }
  try {
    await localStream?.dispose();
  } catch (_) {
    // Continue releasing peer and renderer resources.
  }
  try {
    await peer?.close();
    await peer?.dispose();
  } catch (_) {
    // Renderer disposal still needs to run.
  }
  try {
    localRenderer?.srcObject = null;
    await localRenderer?.dispose();
  } catch (_) {
    // Continue releasing the remote renderer.
  }
  try {
    remoteRenderer?.srcObject = null;
    await remoteRenderer?.dispose();
  } catch (_) {
    // Best-effort cleanup has no further resources to release.
  }
}
