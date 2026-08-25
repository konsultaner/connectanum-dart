import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:wamp_app/src/infrastructure/call_media.dart';
import 'package:wamp_app/src/infrastructure/device_vault.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

enum CallUiPhase {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  active,
  ending,
  ended,
  answeredElsewhere,
  failed,
}

typedef CallTokenGenerator = String Function();

final class CallController extends ChangeNotifier {
  CallController({
    required this._connection,
    required this._trust,
    required this._localDevice,
    required this._mediaFactory,
    CallTokenGenerator? tokenGenerator,
  }) : _tokenGenerator = tokenGenerator ?? _secureToken;

  final AccountConnection _connection;
  final DeviceTrustSession _trust;
  final DeviceRecord _localDevice;
  final CallMediaFactory _mediaFactory;
  final CallTokenGenerator _tokenGenerator;
  final Set<String> _processedSignalIds = <String>{};
  final List<CallIceCandidate> _pendingLocalCandidates = [];
  StreamSubscription<CallWakeup>? _wakeupSubscription;
  StreamSubscription<CallIceCandidate>? _candidateSubscription;
  StreamSubscription<CallMediaConnectionState>? _mediaStateSubscription;
  CallMediaSession? _mediaSession;
  CallRecord? _call;
  CallSessionDescription? _incomingOffer;
  DeviceRecord? _remoteDevice;
  CallUiPhase _phase = CallUiPhase.idle;
  Object? _error;
  bool _busy = false;
  bool _syncRunning = false;
  bool _syncRequested = false;
  bool _initialized = false;
  bool _closed = false;
  int _cursor = 0;
  int _mediaGeneration = 0;
  Future<void> _signalTail = Future<void>.value();

  CallUiPhase get phase => _phase;
  CallRecord? get call => _call;
  CallMediaSession? get mediaSession => _mediaSession;
  bool get busy => _busy;
  bool get hasCall => _phase != CallUiPhase.idle;
  String? get peerUsername {
    final current = _call;
    if (current == null) return null;
    return current.callerUsername == _connection.username
        ? current.calleeUsername
        : current.callerUsername;
  }

  String? get errorMessage => switch (_error) {
    null => null,
    CallMediaException(:final message) => message,
    CallSignalingException() => _error.toString(),
    FormatException() => 'The encrypted call signal was invalid.',
    _ => 'The call could not be completed.',
  };

  Future<void> initialize() async {
    _ensureOpen();
    if (_initialized) return;
    _initialized = true;
    _wakeupSubscription = _connection.callWakeups.listen(
      (_) => _requestSync(),
      onError: (Object error) {
        if (_closed) return;
        _error = error;
        notifyListeners();
      },
    );
    await _drainSync();
  }

  Future<void> startCall({
    required String recipientUsername,
    required CallMediaKind media,
  }) async {
    _ensureOpen();
    if (_busy || _phase != CallUiPhase.idle) return;
    final recipient = AccountRegistration.normalizeUsername(recipientUsername);
    if (recipient == _connection.username) {
      _setFailure(const FormatException('Cannot call the local account.'));
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    CallMediaSession? nextMedia;
    try {
      final directory = await _connection.lookupDevices(recipient);
      final devices = directory.devices
          .where((device) => !device.isRevoked)
          .toList();
      if (devices.isEmpty) {
        throw FormatException('@$recipient has no active device.');
      }
      final configuration = await _connection.getCallConfiguration();
      nextMedia = await _mediaFactory.create(
        media: media,
        configuration: configuration,
      );
      final callId = _tokenGenerator();
      await _replaceMedia(nextMedia);
      final offer = await nextMedia.createOffer();
      final offers = <EncryptedCallSignal>[];
      for (final device in devices) {
        offers.add(
          _sealSignal(
            callId: callId,
            kind: CallSignalKind.offer,
            recipient: device,
            payload: CallDescriptionSignalPayload(offer),
          ),
        );
      }
      final update = await _connection.startCall(
        CallStartRequest(
          media: media,
          calleeUsername: recipient,
          offers: offers,
        ),
      );
      if (_closed || !identical(nextMedia, _mediaSession)) return;
      _call = update.call;
      _remoteDevice = devices.first;
      _phase = CallUiPhase.outgoingRinging;
      await _applySignals(update);
    } catch (error) {
      if (identical(nextMedia, _mediaSession)) await _clearMedia();
      if (!_closed) _setFailure(error);
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> acceptIncoming() async {
    _ensureOpen();
    if (_busy ||
        _phase != CallUiPhase.incomingRinging ||
        _call == null ||
        _incomingOffer == null ||
        _remoteDevice == null) {
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    CallMediaSession? nextMedia;
    try {
      final current = _call!;
      final caller = _remoteDevice!;
      final configuration = await _connection.getCallConfiguration();
      nextMedia = await _mediaFactory.create(
        media: current.media,
        configuration: configuration,
      );
      await _replaceMedia(nextMedia);
      final answer = await nextMedia.acceptOffer(_incomingOffer!);
      final update = await _connection.acceptCall(
        _sealSignal(
          callId: current.callId,
          kind: CallSignalKind.answer,
          recipient: caller,
          payload: CallDescriptionSignalPayload(answer),
        ),
      );
      if (_closed || !identical(nextMedia, _mediaSession)) return;
      _call = update.call;
      if (update.call.acceptedDeviceId != _localDevice.deviceId) {
        await _clearMedia();
        _phase = CallUiPhase.answeredElsewhere;
      } else {
        _phase = CallUiPhase.connecting;
        await _flushLocalCandidates();
      }
      await _applySignals(update);
    } catch (error) {
      if (identical(nextMedia, _mediaSession)) await _clearMedia();
      if (!_closed) {
        _error = error;
        if (error is CallSignalingException &&
            error.kind == CallSignalingFailureKind.answeredElsewhere) {
          _phase = CallUiPhase.answeredElsewhere;
          _requestSync();
        } else {
          _phase = CallUiPhase.incomingRinging;
        }
      }
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> endCall() async {
    _ensureOpen();
    final current = _call;
    final recipient = await _resolveRemoteDevice();
    if (_busy || current == null || recipient == null || current.isTerminal) {
      dismiss();
      return;
    }
    _busy = true;
    _phase = CallUiPhase.ending;
    _error = null;
    notifyListeners();
    try {
      final kind =
          current.state == CallState.ringing &&
              current.calleeUsername == _connection.username
          ? CallSignalKind.decline
          : CallSignalKind.hangup;
      final update = await _connection.endCall(
        _sealSignal(
          callId: current.callId,
          kind: kind,
          recipient: recipient,
          payload: const CallControlSignalPayload(),
        ),
      );
      if (_closed) return;
      _call = update.call;
      await _clearMedia();
      _phase = CallUiPhase.ended;
    } catch (error) {
      if (!_closed) {
        _error = error;
        _phase = current.state == CallState.active
            ? CallUiPhase.active
            : current.callerUsername == _connection.username
            ? CallUiPhase.outgoingRinging
            : CallUiPhase.incomingRinging;
      }
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> setMuted(bool muted) async {
    final media = _mediaSession;
    if (media == null) return;
    try {
      await media.setMuted(muted);
      if (!_closed) notifyListeners();
    } catch (error) {
      _recordError(error);
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    final media = _mediaSession;
    if (media == null) return;
    try {
      await media.setCameraEnabled(enabled);
      if (!_closed) notifyListeners();
    } catch (error) {
      _recordError(error);
    }
  }

  Future<void> setSpeakerEnabled(bool enabled) async {
    final media = _mediaSession;
    if (media == null) return;
    try {
      await media.setSpeakerEnabled(enabled);
      if (!_closed) notifyListeners();
    } catch (error) {
      _recordError(error);
    }
  }

  void dismiss() {
    if (_closed ||
        (_phase != CallUiPhase.ended &&
            _phase != CallUiPhase.answeredElsewhere &&
            _phase != CallUiPhase.failed)) {
      return;
    }
    _call = null;
    _incomingOffer = null;
    _remoteDevice = null;
    _error = null;
    _phase = CallUiPhase.idle;
    notifyListeners();
  }

  void _requestSync() {
    if (_closed) return;
    _syncRequested = true;
    if (!_syncRunning) unawaited(_drainSync());
  }

  Future<void> _drainSync() async {
    if (_closed || _syncRunning) return;
    _syncRunning = true;
    try {
      do {
        _syncRequested = false;
        while (!_closed) {
          final batch = await _connection.syncCalls(
            deviceId: _localDevice.deviceId,
            afterCursor: _cursor,
          );
          if (_closed) return;
          for (final update in batch.updates) {
            await _applyUpdate(update);
          }
          if (batch.nextCursor < _cursor) {
            throw const FormatException(
              'Call synchronization cursor regressed.',
            );
          }
          final advanced = batch.nextCursor > _cursor;
          _cursor = batch.nextCursor;
          if (!advanced || batch.updates.length < 100) break;
        }
      } while (_syncRequested && !_closed);
    } catch (error) {
      _recordError(error);
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> _applyUpdate(CallUpdate update) async {
    if (_closed) return;
    final record = update.call;
    final current = _call;
    if (current == null) {
      if (record.state == CallState.active &&
          record.calleeUsername == _connection.username &&
          record.acceptedDeviceId != _localDevice.deviceId) {
        _call = record;
        _phase = CallUiPhase.answeredElsewhere;
        notifyListeners();
        return;
      }
      if (record.state == CallState.active ||
          (record.state == CallState.ringing &&
              record.callerUsername == _connection.username)) {
        _call = record;
        if (record.state == CallState.ringing) {
          final remoteSignal = update.signals
              .where((signal) => signal.kind == CallSignalKind.offer)
              .firstOrNull;
          if (remoteSignal != null) {
            _remoteDevice = await _lookupDevice(
              remoteSignal.recipientUsername,
              remoteSignal.recipientDeviceId,
            );
          }
        }
        await _endUnrestorableCall();
        return;
      }
      if (record.state != CallState.ringing ||
          record.calleeUsername != _connection.username) {
        return;
      }
      final offer = update.signals
          .where(
            (signal) =>
                signal.kind == CallSignalKind.offer &&
                signal.recipientDeviceId == _localDevice.deviceId,
          )
          .firstOrNull;
      if (offer == null) return;
      try {
        final sender = await _lookupDevice(
          offer.senderUsername,
          offer.senderDeviceId,
        );
        final payload = _openSignal(offer, sender);
        if (payload is! CallDescriptionSignalPayload) {
          throw const FormatException('Incoming call offer is invalid.');
        }
        _call = record;
        _incomingOffer = payload.description;
        _remoteDevice = sender;
        _phase = CallUiPhase.incomingRinging;
        _error = null;
        notifyListeners();
      } catch (error) {
        _setFailure(error);
      }
      return;
    }
    if (current.callId != record.callId) return;
    _call = record;
    if (record.isTerminal) {
      await _clearMedia();
      _phase = CallUiPhase.ended;
      notifyListeners();
      return;
    }
    if (record.state == CallState.active &&
        record.calleeUsername == _connection.username &&
        record.acceptedDeviceId != _localDevice.deviceId) {
      await _clearMedia();
      _phase = CallUiPhase.answeredElsewhere;
      notifyListeners();
      return;
    }
    if (record.state == CallState.active && _mediaSession == null) {
      await _endUnrestorableCall();
      return;
    }
    await _applySignals(update);
    if (record.state == CallState.active && _mediaSession != null) {
      _phase = CallUiPhase.connecting;
      await _flushLocalCandidates();
      notifyListeners();
    }
  }

  Future<void> _applySignals(CallUpdate update) async {
    for (final signal in update.signals) {
      if (signal.recipientDeviceId != _localDevice.deviceId ||
          !_processedSignalIds.add(signal.signalId)) {
        continue;
      }
      final sender = await _lookupDevice(
        signal.senderUsername,
        signal.senderDeviceId,
      );
      final payload = _openSignal(signal, sender);
      switch (payload) {
        case CallDescriptionSignalPayload(:final description)
            when signal.kind == CallSignalKind.answer:
          final media = _mediaSession;
          if (media == null) continue;
          _remoteDevice = sender;
          await media.applyAnswer(description);
          _phase = CallUiPhase.connecting;
          await _flushLocalCandidates();
        case CallCandidateSignalPayload(:final candidate):
          await _mediaSession?.addRemoteCandidate(candidate);
        case CallControlSignalPayload():
          await _clearMedia();
          _phase = CallUiPhase.ended;
        case _:
          // Offers are opened while creating the incoming-call state.
          break;
      }
    }
  }

  Future<void> _replaceMedia(CallMediaSession next) async {
    await _clearMedia();
    if (_closed) {
      await next.dispose();
      return;
    }
    _mediaSession = next;
    final generation = ++_mediaGeneration;
    _candidateSubscription = next.localCandidates.listen((candidate) {
      if (_closed ||
          generation != _mediaGeneration ||
          !identical(next, _mediaSession)) {
        return;
      }
      final call = _call;
      if (call == null || call.state != CallState.active) {
        _pendingLocalCandidates.add(candidate);
        return;
      }
      _queueCandidate(candidate, generation);
    }, onError: _recordError);
    _mediaStateSubscription = next.connectionStates.listen((state) {
      if (_closed ||
          generation != _mediaGeneration ||
          !identical(next, _mediaSession)) {
        return;
      }
      switch (state) {
        case CallMediaConnectionState.connected:
          if (_call?.state == CallState.active &&
              (_phase == CallUiPhase.connecting ||
                  _phase == CallUiPhase.active)) {
            _phase = CallUiPhase.active;
            notifyListeners();
          }
        case CallMediaConnectionState.connecting ||
            CallMediaConnectionState.disconnected:
          if (_phase != CallUiPhase.ending) {
            _phase = CallUiPhase.connecting;
            notifyListeners();
          }
        case CallMediaConnectionState.failed || CallMediaConnectionState.closed:
          unawaited(_failMediaSession(generation));
        case CallMediaConnectionState.newConnection:
          break;
      }
    }, onError: _recordError);
  }

  void _queueCandidate(CallIceCandidate candidate, int generation) {
    _signalTail = _signalTail.then((_) async {
      if (_closed || generation != _mediaGeneration) return;
      final current = _call;
      final recipient = await _resolveRemoteDevice();
      if (current == null ||
          current.state != CallState.active ||
          recipient == null) {
        return;
      }
      try {
        await _connection.sendCallSignal(
          _sealSignal(
            callId: current.callId,
            kind: CallSignalKind.iceCandidate,
            recipient: recipient,
            payload: CallCandidateSignalPayload(candidate),
          ),
        );
      } catch (error) {
        _recordError(error);
      }
    });
  }

  Future<void> _flushLocalCandidates() async {
    if (_pendingLocalCandidates.isEmpty) return;
    final generation = _mediaGeneration;
    final candidates = List<CallIceCandidate>.of(_pendingLocalCandidates);
    _pendingLocalCandidates.clear();
    for (final candidate in candidates) {
      _queueCandidate(candidate, generation);
    }
    await _signalTail;
  }

  Future<void> _failMediaSession(int generation) async {
    if (_closed || generation != _mediaGeneration) return;
    _error = const CallMediaException(
      CallMediaFailureKind.transport,
      'The call media connection failed.',
    );
    final current = _call;
    if (current != null && !current.isTerminal) {
      await endCall();
    } else {
      await _clearMedia();
      if (!_closed) {
        _phase = CallUiPhase.failed;
        notifyListeners();
      }
    }
  }

  Future<void> _endUnrestorableCall() async {
    final current = _call;
    if (_closed || current == null || current.isTerminal) return;
    _phase = CallUiPhase.ending;
    _error = const CallMediaException(
      CallMediaFailureKind.transport,
      'The call ended because its media state could not be resumed.',
    );
    notifyListeners();
    try {
      final recipient = await _resolveRemoteDevice();
      if (recipient == null) {
        throw const FormatException('The remote call device is unavailable.');
      }
      final update = await _connection.endCall(
        _sealSignal(
          callId: current.callId,
          kind: CallSignalKind.hangup,
          recipient: recipient,
          payload: const CallControlSignalPayload(),
        ),
      );
      if (_closed) return;
      _call = update.call;
      _phase = CallUiPhase.ended;
    } catch (error) {
      if (_closed) return;
      _error = error;
      _phase = CallUiPhase.failed;
    }
    notifyListeners();
  }

  EncryptedCallSignal _sealSignal({
    required String callId,
    required CallSignalKind kind,
    required DeviceRecord recipient,
    required CallSignalPayload payload,
  }) {
    final plaintext = CallSignalPayloadCodec.encode(kind, payload);
    try {
      return _trust.sealCallSignal(
        callId: callId,
        signalId: _tokenGenerator(),
        kind: kind,
        recipient: recipient,
        plaintext: plaintext,
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  CallSignalPayload _openSignal(
    EncryptedCallSignal signal,
    DeviceRecord sender,
  ) {
    final plaintext = _trust.openCallSignal(signal: signal, sender: sender);
    try {
      return CallSignalPayloadCodec.decode(signal.kind, plaintext);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Future<DeviceRecord> _lookupDevice(String username, String deviceId) async {
    if (username == _connection.username && deviceId == _localDevice.deviceId) {
      return _localDevice;
    }
    final directory = await _connection.lookupDevices(username);
    return directory.devices.firstWhere(
      (device) => device.deviceId == deviceId && !device.isRevoked,
      orElse: () => throw const FormatException(
        'The call references an unavailable device.',
      ),
    );
  }

  Future<DeviceRecord?> _resolveRemoteDevice() async {
    final cached = _remoteDevice;
    if (cached != null && !cached.isRevoked) return cached;
    final current = _call;
    if (current == null) return null;
    final remoteUsername = current.callerUsername == _connection.username
        ? current.calleeUsername
        : current.callerUsername;
    final remoteDeviceId = current.callerUsername == _connection.username
        ? current.acceptedDeviceId
        : current.callerDeviceId;
    if (remoteDeviceId == null) return null;
    return _remoteDevice = await _lookupDevice(remoteUsername, remoteDeviceId);
  }

  Future<void> _clearMedia() async {
    _mediaGeneration += 1;
    final media = _mediaSession;
    final candidateSubscription = _candidateSubscription;
    final stateSubscription = _mediaStateSubscription;
    _mediaSession = null;
    _candidateSubscription = null;
    _mediaStateSubscription = null;
    _pendingLocalCandidates.clear();
    await Future.wait([
      candidateSubscription?.cancel() ?? Future<void>.value(),
      stateSubscription?.cancel() ?? Future<void>.value(),
    ]);
    await media?.dispose();
  }

  void _setFailure(Object error) {
    if (_closed) return;
    _error = error;
    _phase = CallUiPhase.failed;
    notifyListeners();
  }

  void _recordError(Object error) {
    if (_closed) return;
    _error = error;
    notifyListeners();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Call controller is closed.');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _mediaGeneration += 1;
    final wakeup = _wakeupSubscription;
    _wakeupSubscription = null;
    await Future.wait([
      wakeup?.cancel() ?? Future<void>.value(),
      _clearMedia(),
    ]);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

String _secureToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
