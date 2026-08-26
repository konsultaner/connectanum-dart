import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';
import 'call_store.dart';

final class CallService {
  const CallService({
    required this.accounts,
    required this.store,
    this.maximumClockSkew = const Duration(minutes: 5),
  });

  final AccountStore accounts;
  final CallStore store;
  final Duration maximumClockSkew;

  Future<CallAppendResult> start(
    String callerUsername,
    CallStartRequest request, {
    DateTime? now,
  }) async {
    final caller = AccountRegistration.normalizeUsername(callerUsername);
    request.validate();
    if (request.callerUsername != caller) {
      throw StateError('Call offer does not belong to the caller.');
    }
    final devices = await accounts.listActiveDeviceSnapshot([
      caller,
      request.calleeUsername,
    ]);
    final callerDevice = _findDevice(devices[caller], request.callerDeviceId);
    final calleeDevices = devices[request.calleeUsername] ?? const [];
    if (calleeDevices.isEmpty) {
      throw StateError('The callee has no active devices.');
    }
    final targets = request.offers
        .map((offer) => offer.recipientDeviceId)
        .toSet();
    if (targets.length != calleeDevices.length ||
        calleeDevices.any((device) => !targets.contains(device.deviceId))) {
      throw const FormatException(
        'Call offers must cover every active device.',
      );
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    for (final offer in request.offers) {
      _verifySignal(offer, callerDevice, timestamp);
    }
    return store.start(request, now: timestamp);
  }

  Future<CallAppendResult> accept(
    String callerUsername,
    EncryptedCallSignal answer, {
    DateTime? now,
  }) async {
    await _verifyAuthenticatedSignal(callerUsername, answer, now: now);
    return store.accept(answer, now: now);
  }

  Future<CallAppendResult> signal(
    String callerUsername,
    EncryptedCallSignal signal, {
    DateTime? now,
  }) async {
    await _verifyAuthenticatedSignal(callerUsername, signal, now: now);
    return store.signal(signal, now: now);
  }

  Future<CallAppendResult> end(
    String callerUsername,
    EncryptedCallSignal signal, {
    DateTime? now,
  }) async {
    await _verifyAuthenticatedSignal(callerUsername, signal, now: now);
    return store.end(signal, now: now);
  }

  Future<CallBatch> sync(
    String callerUsername,
    String deviceId, {
    required int afterCursor,
    int limit = 100,
    DateTime? now,
  }) async {
    final caller = AccountRegistration.normalizeUsername(callerUsername);
    final devices = await accounts.listActiveDeviceSnapshot([caller]);
    _findDevice(devices[caller], deviceId);
    return store.sync(
      caller,
      deviceId,
      afterCursor: afterCursor,
      limit: limit,
      now: now,
    );
  }

  Future<void> _verifyAuthenticatedSignal(
    String callerUsername,
    EncryptedCallSignal signal, {
    DateTime? now,
  }) async {
    final caller = AccountRegistration.normalizeUsername(callerUsername);
    signal.validate();
    if (signal.senderUsername != caller) {
      throw StateError('Call signal does not belong to the caller.');
    }
    final devices = await accounts.listActiveDeviceSnapshot([
      signal.senderUsername,
      signal.recipientUsername,
    ]);
    final sender = _findDevice(
      devices[signal.senderUsername],
      signal.senderDeviceId,
    );
    _findDevice(devices[signal.recipientUsername], signal.recipientDeviceId);
    _verifySignal(signal, sender, (now ?? DateTime.now()).toUtc());
  }

  DeviceRecord _findDevice(List<DeviceRecord>? devices, String deviceId) {
    final device = devices
        ?.where((candidate) => candidate.deviceId == deviceId)
        .firstOrNull;
    if (device == null || device.isRevoked) {
      throw StateError('Call signal device is not active.');
    }
    return device;
  }

  void _verifySignal(
    EncryptedCallSignal signal,
    DeviceRecord sender,
    DateTime now,
  ) {
    final earliest = now.subtract(maximumClockSkew);
    final latest = now.add(maximumClockSkew);
    if (signal.createdAt.isBefore(earliest) ||
        signal.createdAt.isAfter(latest)) {
      throw const FormatException(
        'Call signal timestamp is outside the limit.',
      );
    }
    if (signal.senderUsername != sender.username ||
        signal.senderDeviceId != sender.deviceId) {
      throw const FormatException('Call signal sender is invalid.');
    }
    try {
      ed.VerifyKey(
        _decode(
          sender.enrollment.signingPublicKey,
          'signing_public_key',
          expectedBytes: ed.VerifyKey.keyLength,
        ),
      ).verify(
        signature: ed.Signature(
          _decode(
            signal.signature,
            'signature',
            expectedBytes: ed.Signature.signatureLength,
          ),
        ),
        message: Uint8List.fromList(signal.signaturePayload()),
      );
    } catch (_) {
      throw const FormatException('Call signal signature is invalid.');
    }
  }
}

Uint8List _decode(String value, String field, {required int expectedBytes}) {
  try {
    final decoded = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (decoded.length != expectedBytes) throw const FormatException();
    return decoded;
  } catch (_) {
    throw FormatException('$field is invalid.');
  }
}
