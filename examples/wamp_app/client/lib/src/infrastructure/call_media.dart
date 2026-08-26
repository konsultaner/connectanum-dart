import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:wamp_app_protocol/wamp_app_protocol.dart';

enum CallMediaFailureKind {
  permissionDenied,
  configurationExpired,
  unsupported,
  transport,
  disposed,
}

final class CallMediaException implements Exception {
  const CallMediaException(this.kind, this.message);

  final CallMediaFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

enum CallMediaConnectionState {
  newConnection,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

final class CallSessionDescription {
  CallSessionDescription({required this.type, required this.sdp}) {
    if ((type != 'offer' && type != 'answer') ||
        sdp.isEmpty ||
        utf8.encode(sdp).length >
            WampAppCallLimits.maximumSignalPlaintextBytes) {
      throw const FormatException('Call session description is invalid.');
    }
  }

  final String type;
  final String sdp;
}

final class CallIceCandidate {
  CallIceCandidate({required this.candidate, this.sdpMid, this.sdpMLineIndex}) {
    if (candidate.isEmpty ||
        candidate.length > 16 * 1024 ||
        (sdpMid?.length ?? 0) > 256 ||
        (sdpMLineIndex != null &&
            (sdpMLineIndex! < 0 || sdpMLineIndex! > 65535))) {
      throw const FormatException('ICE candidate is invalid.');
    }
  }

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

sealed class CallSignalPayload {
  const CallSignalPayload();
}

final class CallDescriptionSignalPayload extends CallSignalPayload {
  const CallDescriptionSignalPayload(this.description);

  final CallSessionDescription description;
}

final class CallCandidateSignalPayload extends CallSignalPayload {
  const CallCandidateSignalPayload(this.candidate);

  final CallIceCandidate candidate;
}

final class CallControlSignalPayload extends CallSignalPayload {
  const CallControlSignalPayload();
}

abstract final class CallSignalPayloadCodec {
  static const version = 'wampapp-call-payload-v1';

  static Uint8List encode(CallSignalKind kind, CallSignalPayload payload) {
    final Map<String, dynamic> value;
    switch ((kind, payload)) {
      case (
        CallSignalKind.offer || CallSignalKind.answer,
        CallDescriptionSignalPayload(:final description),
      ):
        if (description.type != kind.name) {
          throw const FormatException(
            'Call description does not match the signal kind.',
          );
        }
        value = {
          'version': version,
          'type': description.type,
          'sdp': description.sdp,
        };
      case (
        CallSignalKind.iceCandidate,
        CallCandidateSignalPayload(:final candidate),
      ):
        value = {
          'version': version,
          'candidate': candidate.candidate,
          if (candidate.sdpMid != null) 'sdp_mid': candidate.sdpMid,
          if (candidate.sdpMLineIndex != null)
            'sdp_mline_index': candidate.sdpMLineIndex,
        };
      case (
        CallSignalKind.decline || CallSignalKind.hangup,
        CallControlSignalPayload(),
      ):
        value = {'version': version, 'control': kind.name};
      case _:
        throw const FormatException(
          'Call payload does not match the signal kind.',
        );
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (bytes.length > WampAppCallLimits.maximumSignalPlaintextBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const FormatException('Call signal payload is too large.');
    }
    return bytes;
  }

  static CallSignalPayload decode(CallSignalKind kind, Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > WampAppCallLimits.maximumSignalPlaintextBytes) {
      throw const FormatException('Call signal payload size is invalid.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['version'] != version) {
      throw const FormatException('Unsupported call signal payload.');
    }
    return switch (kind) {
      CallSignalKind.offer ||
      CallSignalKind.answer => _decodeDescription(kind, decoded),
      CallSignalKind.iceCandidate => _decodeCandidate(decoded),
      CallSignalKind.decline || CallSignalKind.hangup =>
        decoded['control'] == kind.name
            ? const CallControlSignalPayload()
            : throw const FormatException('Call control payload is invalid.'),
    };
  }

  static CallDescriptionSignalPayload _decodeDescription(
    CallSignalKind kind,
    Map<String, dynamic> value,
  ) {
    final type = value['type'];
    final sdp = value['sdp'];
    if (type != kind.name || sdp is! String) {
      throw const FormatException('Call description payload is invalid.');
    }
    return CallDescriptionSignalPayload(
      CallSessionDescription(type: type as String, sdp: sdp),
    );
  }

  static CallCandidateSignalPayload _decodeCandidate(
    Map<String, dynamic> value,
  ) {
    final candidate = value['candidate'];
    final sdpMid = value['sdp_mid'];
    final sdpMLineIndex = value['sdp_mline_index'];
    if (candidate is! String ||
        (sdpMid != null && sdpMid is! String) ||
        (sdpMLineIndex != null && sdpMLineIndex is! int)) {
      throw const FormatException('ICE candidate payload is invalid.');
    }
    return CallCandidateSignalPayload(
      CallIceCandidate(
        candidate: candidate,
        sdpMid: sdpMid as String?,
        sdpMLineIndex: sdpMLineIndex as int?,
      ),
    );
  }
}

abstract interface class CallVideoRendererHandle {}

abstract interface class CallMediaSession {
  CallMediaKind get media;
  Stream<CallIceCandidate> get localCandidates;
  Stream<CallMediaConnectionState> get connectionStates;
  CallVideoRendererHandle get localRenderer;
  CallVideoRendererHandle get remoteRenderer;
  bool get muted;
  bool get cameraEnabled;
  bool get speakerRoutingSupported;
  bool get speakerEnabled;

  Future<CallSessionDescription> createOffer();
  Future<CallSessionDescription> acceptOffer(CallSessionDescription offer);
  Future<void> applyAnswer(CallSessionDescription answer);
  Future<void> addRemoteCandidate(CallIceCandidate candidate);
  Future<void> setMuted(bool muted);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> setSpeakerEnabled(bool enabled);
  Future<void> dispose();
}

abstract interface class CallMediaFactory {
  Future<CallMediaSession> create({
    required CallMediaKind media,
    required CallConfiguration configuration,
  });
}
